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
        var consulted = false

        let response = try await storage.mount(target, ui: false, mountedVolumes: {
            consulted = true
            return []
        })

        guard case .alreadyMounted = response else {
            return XCTFail("A share already marked mounted must return .alreadyMounted, got \(response)")
        }
        XCTAssertFalse(consulted, "The mount table should not be read for an already-mounted share")
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

/// The backstop: NetFS reported success, but at the wrong mount point.
final class DuplicateMountRejectionTests: XCTestCase {

    private func share(mountPoint: String?) -> Share {
        return Share(url: URL(string: "smb://tassinari@synology:445/media")!,
                     name: "media",
                     mountPoint: mountPoint,
                     managed: true,
                     connected: .unmounted)
    }

    /// A mount that lands on `/Volumes/media-1` when the share expects `/Volumes/media`
    /// is a duplicate, and must be reported as such rather than as success.
    func testSuccessAtUnexpectedPathIsRejected() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media-1"),
            expecting: share(mountPoint: "/Volumes/media")
        )
        guard case .duplicateRejected(let path) = result else {
            return XCTFail("Expected .duplicateRejected, got \(result)")
        }
        XCTAssertEqual(path, "/Volumes/media-1")
    }

    func testSuccessAtExpectedPathPassesThrough() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media"),
            expecting: share(mountPoint: "/Volumes/media")
        )
        guard case .success(let path) = result else {
            return XCTFail("Expected .success, got \(result)")
        }
        XCTAssertEqual(path, "/Volumes/media")
    }

    /// Mount points differing only by a trailing slash are the same place.
    func testTrailingSlashDoesNotCountAsMismatch() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media/"),
            expecting: share(mountPoint: "/Volumes/media")
        )
        guard case .success = result else {
            return XCTFail("A trailing slash must not be read as a different mount point, got \(result)")
        }
    }

    /// A share with no recorded mount point has no expectation to violate — the first
    /// ever mount of a newly added share must not be rejected.
    func testShareWithoutMountPointIsNeverRejected() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media"),
            expecting: share(mountPoint: nil)
        )
        guard case .success = result else {
            return XCTFail("A share with no expected mount point must pass through, got \(result)")
        }
    }

    func testEmptyExpectedMountPointIsNeverRejected() {
        let result = MountData.rejectIfDuplicate(
            response: .success("/Volumes/media"),
            expecting: share(mountPoint: "")
        )
        guard case .success = result else {
            return XCTFail("An empty expected mount point must pass through, got \(result)")
        }
    }

    /// With no share to compare against, the response is returned untouched.
    func testNilExpectationPassesThrough() {
        let result = MountData.rejectIfDuplicate(response: .success("/Volumes/media-1"), expecting: nil)
        guard case .success = result else {
            return XCTFail("Expected .success, got \(result)")
        }
    }

    /// Success with no reported path cannot be checked, so it must not be rejected.
    func testSuccessWithoutPathPassesThrough() {
        let result = MountData.rejectIfDuplicate(
            response: .success(nil),
            expecting: share(mountPoint: "/Volumes/media")
        )
        guard case .success = result else {
            return XCTFail("Expected .success, got \(result)")
        }
    }

    /// Failures must not be reinterpreted as duplicates.
    func testFailureResponsesArePassedThroughUnchanged() {
        let expecting = share(mountPoint: "/Volumes/media")

        guard case .timeout = MountData.rejectIfDuplicate(response: .timeout, expecting: expecting) else {
            return XCTFail("Expected .timeout to pass through")
        }
        guard case .authenticationError = MountData.rejectIfDuplicate(response: .authenticationError, expecting: expecting) else {
            return XCTFail("Expected .authenticationError to pass through")
        }
        guard case .alreadyMounted = MountData.rejectIfDuplicate(response: .alreadyMounted, expecting: expecting) else {
            return XCTFail("Expected .alreadyMounted to pass through")
        }
    }
}
