//
//  DuplicateMountTests.swift
//  libMounterTests
//
//  Covers the two guards that stop a share being mounted a second time at a
//  deduplicated path such as `/Volumes/media-1`.
//
//  NetFS does not refuse to mount an already-mounted share: it reports success
//  having mounted it again somewhere else. These tests pin both defences —
//  the pre-flight mount-table check, and the post-mount mount-point check.
//

import XCTest
@testable import libMounter

final class DuplicateMountPreflightTests: XCTestCase {

    private static let suiteName = "group.org.tassinari.automount.duplicatetest"

    private func makeStorage() -> StorageManager {
        return StorageManager(defaults: UserDefaults(suiteName: Self.suiteName))
    }

    private func share(_ urlString: String,
                       name: String,
                       mountPoint: String?,
                       connected: ConnectionState = .unmounted) -> Share {
        return Share(url: URL(string: urlString)!,
                     name: name,
                     mountPoint: mountPoint,
                     managed: true,
                     connected: connected)
    }

    private func mounted(_ urlString: String, name: String, path: String) -> MountedVolumesData {
        return MountedVolumesData(name: name, remountURL: URL(string: urlString)!, path: path)
    }

    /// The core regression: the share list said `.unmounted`, but by the time the mount
    /// is attempted the kernel already has it mounted. Without this check NetFS would
    /// happily create `/Volumes/media-1`.
    func testMountIsSkippedWhenKernelAlreadyHasShareMounted() async throws {
        let storage = makeStorage()
        let target = share("smb://tassinari@synology:445/media",
                           name: "media",
                           mountPoint: "/Volumes/media",
                           connected: .unmounted)
        let table = [mounted("smb://tassinari@synology:445/media", name: "media", path: "/Volumes/media")]

        let response = try await storage.mount(target, ui: false, mountedVolumes: { table })

        guard case .alreadyMounted = response else {
            return XCTFail("Expected .alreadyMounted for a share the kernel already has, got \(response)")
        }
    }

    /// The match is on the remote URL, not the mount point — the whole failure mode is
    /// the share being mounted somewhere *other* than where this `Share` expects to be.
    func testMountIsSkippedEvenWhenMountedAtADifferentPath() async throws {
        let storage = makeStorage()
        let target = share("smb://tassinari@synology:445/media",
                           name: "media",
                           mountPoint: "/Volumes/media",
                           connected: .unmounted)
        // Already mounted, but at the deduplicated path from a previous bad run.
        let table = [mounted("smb://tassinari@synology:445/media", name: "media-1", path: "/Volumes/media-1")]

        let response = try await storage.mount(target, ui: false, mountedVolumes: { table })

        guard case .alreadyMounted = response else {
            return XCTFail("A share mounted at any path must not be mounted again, got \(response)")
        }
    }

    /// A different share on the same server must not be mistaken for this one.
    ///
    /// Asserted on the matching predicate directly rather than by calling `mount`: letting it
    /// fall through would fire a real NetFS call, whose result depends on whether the server
    /// happens to be reachable.
    func testDifferentShareOnSameHostIsNotTreatedAsDuplicate() {
        let target = share("smb://tassinari@synology:445/media",
                           name: "media",
                           mountPoint: "/Volumes/media",
                           connected: .unmounted)
        let other = mounted("smb://tassinari@synology:445/MarkPhotos", name: "MarkPhotos", path: "/Volumes/MarkPhotos")

        XCTAssertFalse(other.equal(to: target),
                       "A different share on the same host must not count as a duplicate")
    }

    /// The same share differing only in the user component still matches: the mount table
    /// reports the user NetFS connected as, which need not match what the user typed.
    func testSameShareMatchesRegardlessOfUserComponent() {
        let target = share("smb://synology/media",
                           name: "media",
                           mountPoint: "/Volumes/media",
                           connected: .unmounted)
        let table = mounted("smb://tassinari@synology:445/media", name: "media", path: "/Volumes/media")

        XCTAssertTrue(table.equal(to: target),
                      "The same share must match even when the mount table records a user")
    }

    /// The existing state-based guard must still short-circuit before any lookup.
    func testConnectedShareShortCircuitsWithoutConsultingMountTable() async throws {
        let storage = makeStorage()
        let target = share("smb://tassinari@synology:445/media",
                           name: "media",
                           mountPoint: "/Volumes/media",
                           connected: .mounted)
        let consulted = LookupFlag()

        let response = try await storage.mount(target, ui: false, mountedVolumes: {
            consulted.record()
            return []
        })

        guard case .alreadyMounted = response else {
            return XCTFail("A share already marked mounted must return .alreadyMounted, got \(response)")
        }
        XCTAssertFalse(consulted.wasConsulted, "The mount table should not be read for an already-mounted share")
    }

    func testShareWithoutMountDataThrows() async {
        let storage = makeStorage()
        // `smb:media` has no host at all, so it cannot be decomposed into MountData.
        // (`smb:///media` would yield an empty-string host, which still constructs.)
        let target = Share(url: URL(string: "smb:media")!,
                           name: "media",
                           mountPoint: nil,
                           managed: true,
                           connected: .unmounted)
        do {
            _ = try await storage.mount(target, ui: false, mountedVolumes: { [] })
            XCTFail("Expected MountError.noMountData")
        } catch let error as MountError {
            XCTAssertEqual(error, .noMountData)
        } catch {
            XCTFail("Expected MountError.noMountData, got \(error)")
        }
    }
}

/// The backstop: NetFS reported success, but the share was already mounted elsewhere.
///
/// The test is identity, not location — how many mount points now carry this share's remote
/// URL — so a share that legitimately mounts somewhere other than where it was last recorded
/// is never touched.
final class DuplicateMountRejectionTests: XCTestCase {

    private let shareURL = URL(string: "smb://tassinari@synology:445/media")!

    private func share(mountPoint: String?) -> Share {
        return Share(url: shareURL,
                     name: "media",
                     mountPoint: mountPoint,
                     managed: true,
                     connected: .unmounted)
    }

    private func volume(_ path: String, url: URL? = nil) -> MountedVolumesData {
        return MountedVolumesData(name: (path as NSString).lastPathComponent,
                                  remountURL: url ?? shareURL,
                                  path: path)
    }

    /// The share appears at two mount points, so the one NetFS just reported is surplus.
    func testDuplicateAtSecondMountPointIsRejected() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media-1"),
            expecting: share(mountPoint: "/Volumes/media"),
            mountedVolumes: { [self.volume("/Volumes/media"), self.volume("/Volumes/media-1")] }
        )
        guard case .duplicateRejected(let path) = result else {
            return XCTFail("Expected .duplicateRejected, got \(result)")
        }
        XCTAssertEqual(path, "/Volumes/media-1")
    }

    /// One mount point carrying the share is the normal case, whatever path it is.
    func testSingleMountPassesThrough() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media"),
            expecting: share(mountPoint: "/Volumes/media"),
            mountedVolumes: { [self.volume("/Volumes/media")] }
        )
        guard case .success = result else {
            return XCTFail("Expected .success, got \(result)")
        }
    }

    /// Regression for the review finding on this PR's first revision: the share is recorded
    /// at `/Volumes/media-1` (persisted while the duplicate bug had it there), the duplicate
    /// has since been cleaned up, and a clean mount lands on `/Volumes/media`. Only one mount
    /// point carries the share, so this must pass through untouched — the earlier
    /// stored-path comparison force-unmounted it.
    func testCleanMountAtDifferentPathThanRecordedIsNotRejected() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media"),
            expecting: share(mountPoint: "/Volumes/media-1"),
            mountedVolumes: { [self.volume("/Volumes/media")] }
        )
        guard case .success(let path) = result else {
            return XCTFail("A relocated but unique mount must not be rejected, got \(result)")
        }
        XCTAssertEqual(path, "/Volumes/media")
    }

    /// A first-ever mount of a newly added share has nothing to duplicate.
    func testFirstEverMountIsNeverRejected() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media"),
            expecting: share(mountPoint: nil),
            mountedVolumes: { [self.volume("/Volumes/media")] }
        )
        guard case .success = result else {
            return XCTFail("A first-ever mount must pass through, got \(result)")
        }
    }

    /// A different share on the same host mounted alongside is not a duplicate.
    func testOtherSharesOnSameHostAreNotCounted() {
        let other = URL(string: "smb://tassinari@synology:445/photos")!
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media"),
            expecting: share(mountPoint: "/Volumes/media"),
            mountedVolumes: { [self.volume("/Volumes/media"),
                               self.volume("/Volumes/photos", url: other)] }
        )
        guard case .success = result else {
            return XCTFail("A different share must not count as a duplicate, got \(result)")
        }
    }

    /// Trailing-slash spellings of the reported path still match a table entry.
    func testTrailingSlashStillMatchesTableEntry() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media-1/"),
            expecting: share(mountPoint: "/Volumes/media"),
            mountedVolumes: { [self.volume("/Volumes/media"), self.volume("/Volumes/media-1")] }
        )
        guard case .duplicateRejected = result else {
            return XCTFail("Expected .duplicateRejected, got \(result)")
        }
    }

    /// If the kernel does not show the reported path, nothing is unmounted — we never
    /// force-detach a path we cannot confirm.
    func testPathAbsentFromMountTableIsNotDetached() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/somewhere-else"),
            expecting: share(mountPoint: "/Volumes/media"),
            mountedVolumes: { [self.volume("/Volumes/media"), self.volume("/Volumes/media-1")] }
        )
        guard case .success = result else {
            return XCTFail("An unconfirmed path must not be detached, got \(result)")
        }
    }

    /// With no share to compare against, the response is returned untouched.
    func testNilExpectationPassesThrough() {
        let result = MountData.rejectIfDuplicate(response: .success("/Volumes/media-1"),
                                                 expecting: nil,
                                                 mountedVolumes: { [] })
        guard case .success = result else {
            return XCTFail("Expected .success, got \(result)")
        }
    }

    /// Success with no reported path cannot be checked, so it must not be rejected.
    func testSuccessWithoutPathPassesThrough() {
        let result = MountData.rejectIfDuplicate(
            response: .success(nil),
            expecting: share(mountPoint: "/Volumes/media"),
            mountedVolumes: { [self.volume("/Volumes/media"), self.volume("/Volumes/media-1")] }
        )
        guard case .success = result else {
            return XCTFail("Expected .success, got \(result)")
        }
    }

    /// Failures must not be reinterpreted as duplicates.
    func testFailureResponsesArePassedThroughUnchanged() {
        let expecting = share(mountPoint: "/Volumes/media")
        let table = { [self.volume("/Volumes/media"), self.volume("/Volumes/media-1")] }

        guard case .timeout = MountData.rejectIfDuplicate(response: .timeout, expecting: expecting, mountedVolumes: table) else {
            return XCTFail("Expected .timeout to pass through")
        }
        guard case .authenticationError = MountData.rejectIfDuplicate(response: .authenticationError, expecting: expecting, mountedVolumes: table) else {
            return XCTFail("Expected .authenticationError to pass through")
        }
        guard case .alreadyMounted = MountData.rejectIfDuplicate(response: .alreadyMounted, expecting: expecting, mountedVolumes: table) else {
            return XCTFail("Expected .alreadyMounted to pass through")
        }
    }
}

/// Share identity matching — the predicate both guards rely on.
final class ShareIdentityMatchingTests: XCTestCase {

    private func volume(_ urlString: String) -> MountedVolumesData {
        return MountedVolumesData(name: "v",
                                  remountURL: URL(string: urlString)!,
                                  path: "/Volumes/v")
    }

    private func share(_ urlString: String) -> Share {
        return Share(url: URL(string: urlString)!, name: "v",
                     mountPoint: nil, managed: true, connected: .unmounted)
    }

    /// Shares on different ports of the same host are different shares; treating them as
    /// equal would suppress a legitimate mount and report it as "already mounted".
    func testDifferentPortsAreNotEqual() {
        XCTAssertFalse(volume("smb://synology:4450/media").equal(to: share("smb://synology:445/media")))
    }

    /// The mount table spells out `:445` while a user-typed URL omits it — same share.
    func testDefaultPortMatchesOmittedPort() {
        XCTAssertTrue(volume("smb://synology:445/media").equal(to: share("smb://synology/media")))
        XCTAssertTrue(volume("afp://synology:548/media").equal(to: share("afp://synology/media")))
    }

    /// SMB share names are case-insensitive on the server, so a case difference must not
    /// let the duplicate guard miss an existing mount.
    func testSMBPathComparisonIsCaseInsensitive() {
        XCTAssertTrue(volume("smb://synology/media").equal(to: share("smb://synology/Media")))
    }

    /// NFS exports are case-sensitive filesystem paths.
    func testNFSPathComparisonIsCaseSensitive() {
        XCTAssertFalse(volume("nfs://synology/export/media").equal(to: share("nfs://synology/export/Media")))
    }

    /// Hostnames are case-insensitive.
    func testHostComparisonIsCaseInsensitive() {
        XCTAssertTrue(volume("smb://Synology/media").equal(to: share("smb://synology/media")))
    }

    func testDifferentSharesAreNotEqual() {
        XCTAssertFalse(volume("smb://synology/media").equal(to: share("smb://synology/photos")))
        XCTAssertFalse(volume("smb://synology/media").equal(to: share("smb://other/media")))
        XCTAssertFalse(volume("smb://synology/media").equal(to: share("afp://synology/media")))
    }
}

/// Records whether the injected mount-table lookup was called. The lookup closure is
/// `@Sendable`, so the flag cannot simply be a captured `var`.
private final class LookupFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var consulted = false

    func record() {
        lock.lock()
        defer { lock.unlock() }
        consulted = true
    }

    var wasConsulted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return consulted
    }
}
