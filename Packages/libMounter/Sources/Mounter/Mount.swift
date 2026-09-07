
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

}
internal struct MountedVolumesData: Equatable{
    let name : String
    let remountURL : URL
    let path : String
    
    func equal(to: Share) -> Bool {
        return remountURL.scheme == to.url.scheme && remountURL.host == to.url.host && remountURL.path() == to.url.path()
    }
    var share: Share {
        return Share( url: remountURL, name: name, mountPoint: path, managed: false, connected: .mounted)
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
            guard isRemote(fs) else { continue }

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
    
    internal func mount(ui: Bool = false) async throws -> MountResponse {
       
        let url = try self.url
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var cfArray: Unmanaged<CFArray>?
                let mountD = NSMutableDictionary()
                let optD = NSMutableDictionary()
                optD.setValue(true as CFBoolean, forKey: kNetFSSoftMountKey)
                if !ui{
                    mountD.setValue(kNAUIOptionNoUI, forKey:kNAUIOptionKey)
                }
                let response = NetFSMountURLSync(url as CFURL, nil, nil, nil, mountD as CFMutableDictionary, optD as CFMutableDictionary, &cfArray)
                print("Responses: \(response)")
                var retVal: MountResponse = .alreadyMounted
                switch response{
                case 0:
                    let messages: [String] = {
                        guard let unmanaged = cfArray else { return [] }
                        let arrayRef: CFArray = unmanaged.takeUnretainedValue()
                        let anyArray = arrayRef as [AnyObject]
                        return anyArray.compactMap { $0 as? String }
                    }()
                    retVal =  .success(messages.first)
                    //
                case EAUTH:
                    retVal =  .authenticationError
                case EHOSTUNREACH:
                    retVal =  .cannotFindHost
                case ETIMEDOUT:
                    retVal =  .timeout
                case ECONNREFUSED, ELOOP:
                    retVal =  .connectionRefused
                case ENOENT:
                    retVal =  .noSuchFileOrDirectory
                case EEXIST:
                    retVal =  .alreadyMounted
                    
                default:
                    retVal =  .genericError(NSError(domain: "NetFS", code: Int(response), userInfo: nil))
                }
                cont.resume(returning: retVal)
            }
        }
        
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

