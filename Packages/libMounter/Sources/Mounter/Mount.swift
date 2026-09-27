
import Foundation
import NetFS

/// Errors thrown during mount URL construction or data preparation.
///
/// - ``badURL``: The URL could not be constructed from the share's components.
/// - ``noMountData``: The share's URL could not be decomposed into valid mount data.
public enum MountError: Error, Equatable{
    case badURL, noMountData
    /// A forced unmount failed; the associated value is the `errno` returned by `unmount(2)`.
    case unmountFailed(Int32)
}

/// The result of a NetFS mount operation.
///
/// OS-level error codes are defined in `<sys/errno.h>` and mapped to
/// descriptive cases for common failure modes.
public enum MountResponse : Sendable{
    /// An error not covered by the specific cases, wrapping the underlying `Error`.
    case genericError(Error)
    /// The mount succeeded. The associated value is the local mount path, if available.
    case success(String?)
    /// Authentication failed (e.g. invalid credentials).
    case authenticationError
    /// The remote host could not be reached.
    case cannotFindHost
    /// The connection timed out before the mount could complete.
    case timeout
    /// The remote share path does not exist on the server.
    case noSuchFileOrDirectory
    /// The server actively refused the connection.
    case connectionRefused
    /// The volume is already mounted at a local path.
    case alreadyMounted
    /// The mount succeeded but landed on a different mount point than the share expected,
    /// meaning it duplicated an existing mount. The duplicate has been detached.
    /// The associated value is the duplicate path that was rejected.
    case duplicateRejected(String)

}
internal struct MountedVolumesData: Equatable{
    let name : String
    let remountURL : URL
    let path : String
    
    /// Whether this mounted volume is the same remote share as `to`.
    ///
    /// Matches on identity — scheme, host, port and share path — rather than on mount point,
    /// since a share can be mounted at a path other than the one it is recorded at.
    func equal(to: Share) -> Bool {
        guard let scheme = remountURL.scheme?.lowercased(),
              scheme == to.url.scheme?.lowercased() else { return false }
        guard remountURL.host?.lowercased() == to.url.host?.lowercased() else { return false }
        // The mount table always spells the port out (`//host:445/share`) while a user-typed
        // URL usually omits it, so compare against the scheme's default when either is absent.
        guard MountedVolumesData.port(of: remountURL, scheme: scheme)
                == MountedVolumesData.port(of: to.url, scheme: scheme) else { return false }
        return MountedVolumesData.pathsEqual(remountURL.path(), to.url.path(), scheme: scheme)
    }

    /// The URL's port, falling back to the scheme's default so `smb://h/s` and
    /// `smb://h:445/s` are recognised as the same server.
    fileprivate static func port(of url: URL, scheme: String) -> Int? {
        if let port = url.port { return port }
        switch scheme {
        case "smb": return 445
        case "afp": return 548
        case "nfs": return 2049
        default: return nil
        }
    }

    /// Compares two share paths under the case rules of their protocol.
    ///
    /// SMB and AFP share names are case-insensitive on the server, so `/Media` and `/media`
    /// are the same share and must match — otherwise the duplicate guard misses the mount it
    /// exists to catch. NFS exports are case-sensitive paths, so they are compared exactly.
    fileprivate static func pathsEqual(_ lhs: String, _ rhs: String, scheme: String) -> Bool {
        switch scheme {
        case "smb", "afp":
            return lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
        default:
            return lhs == rhs
        }
    }
    var share: Share {
        return Share( url: remountURL, name: name, mountPoint: path, managed: false, connected: .mounted)
    }
}

extension Share {
    /// A key that is equal for two shares exactly when ``MountedVolumesData/equal(to:)``
    /// would treat them as the same remote share: scheme, host and port (defaulted per
    /// scheme), plus the path under its protocol's case rules. The user name is ignored,
    /// as it is there.
    ///
    /// Used to recognise a second mount of a share that is already being mounted, however
    /// its URL happens to be spelled.
    internal var mountIdentity: String {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return url.absoluteString
        }
        let port = MountedVolumesData.port(of: url, scheme: scheme).map { ":\($0)" } ?? ""
        let path: String
        switch scheme {
        case "smb", "afp":
            path = url.path().lowercased()
        default:
            path = url.path()
        }
        return "\(scheme)://\(host)\(port)\(path)"
    }
}

internal struct MountInfo{

    /// Reads the kernel's mount table without touching any of the mounted filesystems.
    ///
    /// `getfsstat(2)` with `MNT_NOWAIT` answers purely from in-kernel state, so it cannot
    /// block on an unreachable server. This matters after a sleep/wake: a stale network
    /// mount still has a mount point, and any call that stats it (`FileManager`'s
    /// `mountedVolumeURLs` + `resourceValues`, `fileExists`, …) blocks uninterruptibly
    /// in the kernel until the SMB timeout expires — freezing whatever thread asked.
    ///
    /// - Returns: One `statfs` entry per mounted filesystem, or `[]` if the table could not be read.
    internal static func fileSystemStats() -> [Darwin.statfs] {
        // Pass 1: ask how many filesystems are mounted.
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }

        // Over-allocate slightly: a filesystem can be mounted between the two calls.
        let capacity = Int(count) + 8
        var buffer = [Darwin.statfs](repeating: Darwin.statfs(), count: capacity)
        let byteCount = Int32(capacity * MemoryLayout<Darwin.statfs>.stride)

        let written = buffer.withUnsafeMutableBufferPointer { pointer in
            getfsstat(pointer.baseAddress, byteCount, MNT_NOWAIT)
        }
        guard written > 0 else { return [] }

        return Array(buffer.prefix(Int(written)))
    }

    /// Converts a `statfs` C char tuple field (`f_mntonname` / `f_mntfromname`) into a `String`.
    private static func string(from path: UnsafePointer<CChar>) -> String {
        return String(cString: path)
    }

    /// The local mount points of every currently mounted share-type network filesystem.
    ///
    /// Derived from the kernel mount table, so it is safe to call while a server is unreachable.
    /// Restricted to the filesystem types this app mounts, which excludes system plumbing such
    /// as the `autofs` entry backing `/System/Volumes/Data/home`.
    internal static func remoteMountPoints() -> [String] {
        return fileSystemStats().compactMap { fs in
            guard isRemote(fs), isSupportedShareType(fs) else { return nil }
            var mutable = fs
            return withUnsafePointer(to: &mutable.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { string(from: $0) }
            }
        }
    }

    /// Whether a mounted filesystem lives on a remote server.
    ///
    /// The kernel sets `MNT_LOCAL` for anything backed by local hardware (including disk images),
    /// so its absence is the authoritative "this is a network mount" signal.
    private static func isRemote(_ fs: Darwin.statfs) -> Bool {
        return (fs.f_flags & UInt32(MNT_LOCAL)) == 0
    }

    /// The filesystem types this app knows how to mount and remount.
    internal static let supportedFileSystemTypes: Set<String> = ["smbfs", "afpfs", "nfs"]

    /// Whether a mounted filesystem is one of the share types this app manages.
    private static func isSupportedShareType(_ fs: Darwin.statfs) -> Bool {
        var mutable = fs
        let type = withUnsafePointer(to: &mutable.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { string(from: $0) }
        }
        return supportedFileSystemTypes.contains(type)
    }

    static func mountedVolumes() -> [MountedVolumesData] {
        var result: [MountedVolumesData] = []
        for var fs in fileSystemStats() {
            // Same filter as `remoteMountPoints()`: remote *and* a share type this app
            // manages. `isRemote` alone would admit any non-MNT_LOCAL filesystem whose
            // device string happens to parse as `//host/share`.
            guard isRemote(fs), isSupportedShareType(fs) else { continue }

            let mountPoint = withUnsafePointer(to: &fs.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { string(from: $0) }
            }
            let from = withUnsafePointer(to: &fs.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { string(from: $0) }
            }
            let type = withUnsafePointer(to: &fs.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { string(from: $0) }
            }

            guard let remote = remountURL(from: from, fileSystemType: type) else { continue }

            // The volume name is the last path component of the mount point, which is what
            // Finder displays. Reading `.volumeNameKey` instead would stat a possibly dead mount.
            let name = (mountPoint as NSString).lastPathComponent
            result.append(MountedVolumesData(name: name, remountURL: remote, path: mountPoint))
        }
        return result
    }

    /// Rebuilds a remount URL from a `statfs` `f_mntfromname` device string.
    ///
    /// SMB and AFP report `//user@host/share` (the user part is optional); NFS reports
    /// `host:/export`. Anything else is not something this app can remount, so it is skipped.
    ///
    /// - Parameters:
    ///   - from: The `f_mntfromname` value, e.g. `//tassinari@synology:445/media`.
    ///   - fileSystemType: The `f_fstypename` value, e.g. `smbfs`, `afpfs`, `nfs`.
    /// - Returns: The reconstructed URL, or `nil` if the device string is not recognised.
    internal static func remountURL(from: String, fileSystemType: String) -> URL? {
        let scheme: String
        switch fileSystemType {
        case "smbfs":
            scheme = "smb"
        case "afpfs":
            scheme = "afp"
        case "nfs":
            scheme = "nfs"
        default:
            return nil
        }

        if from.hasPrefix("//") {
            // //user@host[:port]/share  or  //host/share
            let body = String(from.dropFirst(2))
            guard let slash = body.firstIndex(of: "/") else { return nil }
            let authority = String(body[body.startIndex..<slash])
            let share = String(body[body.index(after: slash)...])
            guard !authority.isEmpty, !share.isEmpty else { return nil }
            return url(scheme: scheme, authority: authority, path: share)
        }

        if fileSystemType == "nfs", let colon = from.firstIndex(of: ":") {
            // host:/export
            let authority = String(from[from.startIndex..<colon])
            let export = String(from[from.index(after: colon)...])
            guard !authority.isEmpty, !export.isEmpty else { return nil }
            let trimmed = export.hasPrefix("/") ? String(export.dropFirst()) : export
            return url(scheme: scheme, authority: authority, path: trimmed)
        }

        return nil
    }

    /// Builds a URL from a scheme, an `[user@]host[:port]` authority, and a share path.
    ///
    /// `URLComponents` percent-encodes each field correctly, which matters for shares and
    /// usernames containing spaces or other reserved characters.
    private static func url(scheme: String, authority: String, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme

        var hostPart = authority
        if let at = authority.lastIndex(of: "@") {
            components.user = String(authority[authority.startIndex..<at])
            hostPart = String(authority[authority.index(after: at)...])
        }
        if let colon = hostPart.lastIndex(of: ":"),
           let port = Int(hostPart[hostPart.index(after: colon)...]) {
            components.port = port
            hostPart = String(hostPart[hostPart.startIndex..<colon])
        }
        guard !hostPart.isEmpty else { return nil }
        components.host = hostPart
        components.path = "/" + path
        return components.url
    }

    public static func isVolumeMounted(at local: URL) -> Bool {
        // Compare against the kernel mount table rather than stat-ing the path, so a stale
        // mount answers instantly instead of blocking until the network timeout.
        let target = standardized(local.path)
        for var fs in fileSystemStats() {
            let mountPoint = withUnsafePointer(to: &fs.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { string(from: $0) }
            }
            if standardized(mountPoint) == target { return true }
        }
        return false
    }

    /// Normalises a path for comparison by dropping any trailing slash.
    private static func standardized(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    /// Whether a mount point still answers filesystem calls within `timeout`.
    ///
    /// A stale network mount is indistinguishable from a healthy one in the mount table — the
    /// only way to tell them apart is to touch it and see whether it answers. So the blocking
    /// `stat(2)` runs on its own detached thread and the caller waits on a semaphore: when the
    /// timeout wins, the caller resumes immediately while the doomed thread stays parked in the
    /// kernel until SMB gives up. That leaked thread is the deliberate trade — it costs one
    /// blocked thread, and it buys a caller that never freezes.
    ///
    /// - Parameters:
    ///   - path: The mount point to probe.
    ///   - timeout: How long to wait for an answer.
    /// - Returns: `true` if the mount responded in time, `false` if it timed out or errored.
    internal static func isMountResponsive(path: String, timeout: TimeInterval) async -> Bool {
        return await withCheckedContinuation { continuation in
            let semaphore = DispatchSemaphore(value: 0)
            // Shared with a thread that may outlive this call, so its lifetime is managed by
            // ARC and every access is lock-guarded.
            let result = ProbeResult()

            // A dedicated thread, not a global-queue dispatch: a hung open would otherwise
            // occupy a cooperative-pool thread that other work needs.
            let probe = Thread {
                // Both `stat` and a bare `open` of the mount point are answered from the
                // cached directory vnode, so a dead server still looks healthy. Actually
                // *reading* the directory is what forces a round trip to the server, and is
                // therefore the only reliable liveness signal.
                guard let dir = opendir(path) else {
                    semaphore.signal()
                    return
                }
                errno = 0
                let entry = readdir(dir)
                // A genuinely empty directory returns nil with errno untouched; a dead mount
                // sets errno (ETIMEDOUT/ENOTCONN) or blocks until the caller gives up.
                if entry != nil || errno == 0 {
                    result.markResponded()
                }
                closedir(dir)
                semaphore.signal()
            }
            probe.stackSize = 512 * 1024
            probe.start()

            DispatchQueue.global().async {
                // If this times out the probe thread stays parked in the kernel until SMB gives
                // up. That is the deliberate trade: one blocked thread, and a caller that
                // never freezes.
                let waited = semaphore.wait(timeout: .now() + timeout)
                continuation.resume(returning: waited == .success && result.responded)
            }
        }
    }
}

/// Resumes a continuation at most once, however many parties race to resume it.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MountResponse, Never>?

    init(_ continuation: CheckedContinuation<MountResponse, Never>) {
        self.continuation = continuation
    }

    /// Resumes with `value` if nothing has yet.
    /// - Returns: `true` if this call was the one that resumed.
    @discardableResult
    func resume(returning value: MountResponse) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
        return pending != nil
    }
}

/// A lock-guarded flag shared between the probe thread and the waiter in
/// ``MountInfo/isMountResponsive(path:timeout:)``.
private final class ProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markResponded() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var responded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

internal struct MountData{
    public let scheme: String
    public let host: String
    public let port : Int?
    public let path: String
    
    public var url: URL{
        get throws{
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            if !path.isEmpty, !path.hasPrefix("/"){
                components.path = "/\(path)"
            }else{
                components.path = path
            }
            
            if let port{
                components.port = port
            }else{
                components.port = 445
            }
            guard let url = components.url else{
                throw MountError.badURL
            }
            return url
        }
    }
    
    /// How long an unattended mount may take before it is cancelled.
    ///
    /// `NetFSMountURLSync` has no timeout of its own that survives sleep: a request made while
    /// the network is going away sits in NetAuthSysAgent until connectivity returns, however
    /// long that is. Requests piled up that way overnight all complete together on the next
    /// wake, and each mounts the share again at `/Volumes/<name>-1`, `-2`, ...
    internal static let unattendedMountTimeout: TimeInterval = 60

    /// Mounts the share via NetFS.
    ///
    /// - Parameters:
    ///   - ui: Whether the system may present authentication UI.
    ///   - expecting: The share being mounted. After the mount, the kernel mount table is
    ///     re-read: if this share's remote URL now appears at more than one mount point, the
    ///     mount NetFS just made was a duplicate -- see ``rejectIfDuplicate(response:expecting:mountedVolumes:)``.
    ///   - timeout: Cancel the request and report ``MountResponse/timeout`` if it has not
    ///     completed after this many seconds of wall-clock time (which, unlike uptime, keeps
    ///     counting while the Mac sleeps). `nil` waits indefinitely -- appropriate when `ui`
    ///     is `true` and the user may be typing a password.
    ///   - mountedVolumes: Returns the volumes the kernel currently has mounted. Injected so
    ///     the duplicate backstop can be exercised without touching real mounts.
    internal func mount(ui: Bool = false,
                        expecting: Share? = nil,
                        timeout: TimeInterval? = nil,
                        mountedVolumes: @escaping @Sendable () -> [MountedVolumesData] = MountInfo.mountedVolumes) async throws -> MountResponse {

        let url = try self.url
        let response = await MountData.awaitMountRequest(timeout: timeout, start: { finish in
            let mountD = NSMutableDictionary()
            let optD = NSMutableDictionary()
            optD.setValue(true as CFBoolean, forKey: kNetFSSoftMountKey)
            if !ui{
                mountD.setValue(kNAUIOptionNoUI, forKey:kNAUIOptionKey)
            }
            var requestID: AsyncRequestID?
            let status = NetFSMountURLAsync(url as CFURL, nil, nil, nil,
                                            mountD as CFMutableDictionary, optD as CFMutableDictionary,
                                            &requestID, DispatchQueue.global()) { status, _, mountpoints in
                finish(MountData.response(for: status, mountpoints: mountpoints))
            }
            if status != 0 {
                // Rejected before it was queued; the completion block will not run.
                finish(MountData.response(for: status, mountpoints: nil))
                return nil
            }
            return requestID.map(MountRequest.init)
        }, cancel: { (request: MountRequest) in
            libMounter.error("Mount of \(url.absoluteString) timed out; cancelling request")
            _ = NetFSMountURLCancel(request.id)
        })

        return MountData.rejectIfDuplicate(response: response,
                                           expecting: expecting,
                                           mountedVolumes: mountedVolumes)
    }

    /// A pending `NetFSMountURLAsync` request. The raw pointer is an opaque token that NetFS
    /// only ever reads back in `NetFSMountURLCancel`, so passing it between threads is safe.
    internal struct MountRequest: @unchecked Sendable {
        let id: AsyncRequestID
    }

    /// Waits for an asynchronous mount request, cancelling it if it outlives `timeout`.
    ///
    /// Whichever comes first -- the request's completion or the deadline -- decides the
    /// result; the other is ignored. On the deadline, `cancel` is called with the request's
    /// token so the request cannot complete later and mount the share behind our back.
    ///
    /// - Parameters:
    ///   - timeout: Seconds of wall-clock time to wait, or `nil` to wait indefinitely.
    ///   - start: Issues the request. It receives a `finish` callback to report the outcome
    ///     (which may be called synchronously), and returns the token needed to cancel it, or
    ///     `nil` if there is nothing to cancel.
    ///   - cancel: Cancels a pending request.
    internal static func awaitMountRequest<Token: Sendable>(
        timeout: TimeInterval?,
        start: (@escaping @Sendable (MountResponse) -> Void) -> Token?,
        cancel: @escaping @Sendable (Token) -> Void
    ) async -> MountResponse {
        await withCheckedContinuation { continuation in
            let outcome = ResumeOnce(continuation)
            let token = start { response in
                outcome.resume(returning: response)
            }
            guard let timeout else { return }
            DispatchQueue.global().asyncAfter(wallDeadline: .now() + timeout) {
                if outcome.resume(returning: .timeout), let token {
                    cancel(token)
                }
            }
        }
    }

    /// Maps a NetFS status code, and the mount points it reported, to a ``MountResponse``.
    private static func response(for status: Int32, mountpoints: CFArray?) -> MountResponse {
        switch status{
        case 0:
            let paths = (mountpoints as? [AnyObject])?.compactMap { $0 as? String } ?? []
            return .success(paths.first)
        case EAUTH:
            return .authenticationError
        case EHOSTUNREACH:
            return .cannotFindHost
        case ETIMEDOUT:
            return .timeout
        case ECONNREFUSED, ELOOP:
            return .connectionRefused
        case ENOENT:
            return .noSuchFileOrDirectory
        case EEXIST:
            return .alreadyMounted
        default:
            return .genericError(NSError(domain: "NetFS", code: Int(status), userInfo: nil))
        }
    }

    /// Turns a "successful" mount that duplicated an existing one back into a no-op.
    ///
    /// NetFS does not refuse to mount a share that is already mounted: it returns success
    /// having mounted it a second time at a deduplicated path (`/Volumes/media-1`). The
    /// pre-flight check in `StorageManager.mount` catches almost all of these, but it races
    /// against anything else mounting the same share. This is the backstop.
    ///
    /// The test is identity, not location: after the mount, ask the kernel how many mount
    /// points now carry this share's *remote URL*. One is the normal case, whatever path it
    /// landed on -- a first-ever mount and a share that legitimately relocated both look like
    /// this. More than one means NetFS just mounted an already-mounted share, and the path it
    /// reported is the surplus copy, so it is detached again.
    ///
    /// Deliberately **not** compared against the share's stored `mountPoint`: that value is
    /// whatever path the share occupied when it was first persisted and is never refreshed,
    /// so a share recorded at `/Volumes/media-1` would see a clean mount at `/Volumes/media`
    /// as a duplicate and force-unmount a volume that is working.
    internal static func rejectIfDuplicate(response: MountResponse,
                                           expecting: Share?,
                                           mountedVolumes: () -> [MountedVolumesData]) -> MountResponse {
        guard case .success(let actualPath) = response,
              let actualPath,
              !actualPath.isEmpty,
              let share = expecting else {
            return response
        }
        // Count the mount points currently carrying this share's remote URL.
        let entries = mountedVolumes().filter { $0.equal(to: share) }
        guard entries.count > 1 else {
            return response
        }
        // Only detach the copy NetFS just reported, and only if the kernel agrees it is one
        // of the duplicates -- never unmount a path we cannot see in the table.
        guard entries.contains(where: { normalize($0.path) == normalize(actualPath) }) else {
            return response
        }
        libMounter.error("Mount of \(share.name ?? "--") at \(actualPath) duplicates an existing mount; detaching duplicate")
        forceUnmountDetached(path: actualPath)
        return .duplicateRejected(actualPath)
    }

    /// Drops a trailing slash so two spellings of the same mount point compare equal.
    private static func normalize(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    internal static func unmount(url: URL) async throws {
        // Check the kernel mount table instead of `fileExists`, which blocks on a stale mount.
        guard MountInfo.isVolumeMounted(at: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await FileManager.default.unmountVolume(
            at: url,
            options: [.withoutUI]
        )
    }

    /// Forcibly detaches a mount point via `unmount(2)` with `MNT_FORCE`.
    ///
    /// Used for stale mounts, where the polite `unmountVolume` path would itself block
    /// trying to flush to a server that is no longer reachable. `MNT_FORCE` tells the
    /// kernel to tear the mount down and fail any in-flight I/O rather than wait.
    ///
    /// - Parameter url: The local mount point to detach.
    /// - Throws: `MountError.unmountFailed` carrying `errno` if the kernel refuses.
    internal static func forceUnmount(url: URL) throws {
        let result = url.path.withCString { Darwin.unmount($0, MNT_FORCE) }
        if result != 0 {
            throw MountError.unmountFailed(errno)
        }
    }

    /// Starts a forced unmount on a dedicated thread and returns immediately.
    ///
    /// Even with `MNT_FORCE`, `unmount(2)` blocks while the kernel tears down a dead SMB
    /// session — measured at over two minutes against an unresponsive server. Callers clearing
    /// stale mounts must not inherit that wait, and nothing downstream depends on the detach
    /// having finished: the mount point disappears from the mount table when the kernel is done.
    ///
    /// - Parameter path: The local mount point to detach.
    internal static func forceUnmountDetached(path: String) {
        let thread = Thread {
            let result = path.withCString { Darwin.unmount($0, MNT_FORCE) }
            if result != 0 {
                libMounter.error("Forced unmount of \(path) failed with errno \(errno)")
            } else {
                notice("Forced unmount of \(path) completed")
            }
        }
        thread.stackSize = 512 * 1024
        thread.start()
    }
}

