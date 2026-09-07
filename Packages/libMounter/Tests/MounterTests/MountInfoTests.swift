//
//  MountInfoTests.swift
//  libMounterTests
//
//  Covers the kernel-mount-table reader that replaced the FileManager volume
//  enumeration, and the stale-mount machinery built on top of it.
//

import XCTest
@testable import libMounter

final class MountInfoRemountURLTests: XCTestCase {

    // MARK: - SMB

    func testSMBDeviceStringWithUserAndPort() {
        let url = MountInfo.remountURL(from: "//tassinari@synology:445/media", fileSystemType: "smbfs")
        XCTAssertEqual(url?.absoluteString, "smb://tassinari@synology:445/media")
        XCTAssertEqual(url?.host, "synology")
        XCTAssertEqual(url?.port, 445)
        XCTAssertEqual(url?.path, "/media")
    }

    func testSMBDeviceStringWithoutUser() {
        let url = MountInfo.remountURL(from: "//synology/media", fileSystemType: "smbfs")
        XCTAssertEqual(url?.scheme, "smb")
        XCTAssertEqual(url?.host, "synology")
        XCTAssertNil(url?.user)
        XCTAssertEqual(url?.path, "/media")
    }

    func testSMBDeviceStringWithoutPort() {
        let url = MountInfo.remountURL(from: "//user@server/share", fileSystemType: "smbfs")
        XCTAssertNil(url?.port)
        XCTAssertEqual(url?.user, "user")
    }

    /// Share names with spaces must survive the round trip percent-encoded.
    func testSMBShareNameWithSpaceIsEncoded() {
        let url = MountInfo.remountURL(from: "//server/Time Machine", fileSystemType: "smbfs")
        XCTAssertEqual(url?.host, "server")
        // `path` decodes, `absoluteString` stays encoded.
        XCTAssertEqual(url?.path, "/Time Machine")
        XCTAssertTrue(url?.absoluteString.contains("%20") ?? false,
                      "Expected the space to be percent-encoded, got \(url?.absoluteString ?? "nil")")
    }

    /// A domain-qualified user (`DOMAIN;user`) still parses — the last `@` separates the host.
    func testSMBWithEmailStyleUserUsesLastAtSign() {
        let url = MountInfo.remountURL(from: "//user@corp.com@server/share", fileSystemType: "smbfs")
        XCTAssertEqual(url?.host, "server")
        XCTAssertEqual(url?.user, "user@corp.com")
    }

    // MARK: - AFP

    func testAFPDeviceString() {
        let url = MountInfo.remountURL(from: "//user@server/volume", fileSystemType: "afpfs")
        XCTAssertEqual(url?.scheme, "afp")
        XCTAssertEqual(url?.host, "server")
        XCTAssertEqual(url?.path, "/volume")
    }

    // MARK: - NFS

    func testNFSDeviceString() {
        let url = MountInfo.remountURL(from: "server:/export/data", fileSystemType: "nfs")
        XCTAssertEqual(url?.scheme, "nfs")
        XCTAssertEqual(url?.host, "server")
        XCTAssertEqual(url?.path, "/export/data")
    }

    func testNFSDeviceStringWithSlashPrefixedExport() {
        let url = MountInfo.remountURL(from: "192.168.1.10:/volume1/media", fileSystemType: "nfs")
        XCTAssertEqual(url?.host, "192.168.1.10")
        XCTAssertEqual(url?.path, "/volume1/media")
    }

    // MARK: - Rejections

    func testUnsupportedFileSystemTypeReturnsNil() {
        XCTAssertNil(MountInfo.remountURL(from: "//server/share", fileSystemType: "apfs"))
        XCTAssertNil(MountInfo.remountURL(from: "/dev/disk1s1", fileSystemType: "hfs"))
        XCTAssertNil(MountInfo.remountURL(from: "map -hosts", fileSystemType: "autofs"))
    }

    func testMalformedDeviceStringsReturnNil() {
        XCTAssertNil(MountInfo.remountURL(from: "//server", fileSystemType: "smbfs"),
                     "No share component should be rejected")
        XCTAssertNil(MountInfo.remountURL(from: "///share", fileSystemType: "smbfs"),
                     "Empty authority should be rejected")
        XCTAssertNil(MountInfo.remountURL(from: "//server/", fileSystemType: "smbfs"),
                     "Empty share should be rejected")
        XCTAssertNil(MountInfo.remountURL(from: "", fileSystemType: "smbfs"))
        XCTAssertNil(MountInfo.remountURL(from: "not-a-device-string", fileSystemType: "smbfs"))
    }
}

final class MountInfoTableTests: XCTestCase {

    /// The whole point of the `getfsstat` rewrite: reading the mount table must not
    /// touch any mounted filesystem, so it stays fast even with a dead server attached.
    func testFileSystemStatsIsFast() {
        let start = Date()
        let stats = MountInfo.fileSystemStats()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertFalse(stats.isEmpty, "The root filesystem should always be present")
        XCTAssertLessThan(elapsed, 0.5, "Reading the mount table should be near-instant, took \(elapsed)s")
    }

    func testFileSystemStatsIncludesRootVolume() {
        let stats = MountInfo.fileSystemStats()
        let mountPoints = stats.map { fs -> String in
            var mutable = fs
            return withUnsafePointer(to: &mutable.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
        }
        XCTAssertTrue(mountPoints.contains("/"), "Expected the root mount point in \(mountPoints)")
    }

    /// Local volumes (including the root volume and disk images) must never be reported
    /// as network shares.
    func testMountedVolumesExcludesLocalVolumes() {
        for volume in MountInfo.mountedVolumes() {
            XCTAssertNotEqual(volume.path, "/", "Root volume must be excluded")
            XCTAssertFalse(volume.path.hasPrefix("/System/Volumes/"),
                           "\(volume.path) is a local system volume and must be excluded")
        }
    }

    /// Every reported volume must carry a URL this app could actually remount.
    func testMountedVolumesProduceUsableRemountURLs() {
        for volume in MountInfo.mountedVolumes() {
            XCTAssertNotNil(volume.remountURL.host, "\(volume.path) has no host")
            let scheme = volume.remountURL.scheme ?? ""
            XCTAssertTrue(["smb", "afp", "nfs"].contains(scheme),
                          "\(volume.path) produced unexpected scheme '\(scheme)'")
            XCTAssertTrue(volume.path.hasPrefix("/"), "Mount point should be absolute")
        }
    }

    /// `remoteMountPoints` feeds stale-mount clearing, so it must not include system
    /// plumbing such as the autofs entry backing `/System/Volumes/Data/home`.
    func testRemoteMountPointsExcludesAutofsAndLocal() {
        let points = MountInfo.remoteMountPoints()
        XCTAssertFalse(points.contains("/"), "Root must never be listed for stale clearing")
        XCTAssertFalse(points.contains("/System/Volumes/Data/home"),
                       "autofs mounts must be excluded, got \(points)")
    }

    func testRemoteMountPointsMatchesMountedVolumes() {
        let points = Set(MountInfo.remoteMountPoints())
        for volume in MountInfo.mountedVolumes() {
            XCTAssertTrue(points.contains(volume.path),
                          "\(volume.path) is reported as a volume but not as a remote mount point")
        }
    }

    func testIsVolumeMountedRejectsUnknownPath() {
        XCTAssertFalse(MountInfo.isVolumeMounted(at: URL(filePath: "/Volumes/NoSuchVolume-\(UUID().uuidString)")))
    }

    func testIsVolumeMountedFindsRootVolume() {
        XCTAssertTrue(MountInfo.isVolumeMounted(at: URL(filePath: "/")))
    }

    /// A trailing slash must not change the answer.
    func testIsVolumeMountedIgnoresTrailingSlash() throws {
        guard let point = MountInfo.remoteMountPoints().first else {
            throw XCTSkip("No network mounts attached; nothing to compare")
        }
        XCTAssertTrue(MountInfo.isVolumeMounted(at: URL(filePath: point)))
        XCTAssertTrue(MountInfo.isVolumeMounted(at: URL(filePath: point + "/")))
    }

    /// `isVolumeMounted` must answer from the mount table, never by stat-ing the path,
    /// so it stays fast even when the mount behind it is dead.
    func testIsVolumeMountedIsFast() {
        let start = Date()
        _ = MountInfo.isVolumeMounted(at: URL(filePath: "/Volumes/SomeVolume"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
}

final class MountResponsivenessTests: XCTestCase {

    func testNonExistentPathIsNotResponsive() async {
        let responsive = await MountInfo.isMountResponsive(
            path: "/Volumes/NoSuchVolume-\(UUID().uuidString)",
            timeout: 2
        )
        XCTAssertFalse(responsive)
    }

    func testLocalDirectoryIsResponsive() async {
        let responsive = await MountInfo.isMountResponsive(path: NSTemporaryDirectory(), timeout: 2)
        XCTAssertTrue(responsive, "A local temp directory must always answer")
    }

    /// A healthy path must answer well inside its budget — this is what keeps
    /// `clearStaleMounts` from detaching working mounts.
    func testResponsivePathReturnsQuickly() async {
        let start = Date()
        _ = await MountInfo.isMountResponsive(path: NSTemporaryDirectory(), timeout: 5)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "A healthy path should not consume the timeout, took \(elapsed)s")
    }

    /// The caller must never wait materially longer than the timeout it asked for,
    /// which is the guarantee that keeps the UI responsive against a dead server.
    func testProbeRespectsTimeoutBudget() async {
        let start = Date()
        _ = await MountInfo.isMountResponsive(path: "/Volumes/NoSuchVolume-\(UUID().uuidString)", timeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "Probe overran its 1s budget, took \(elapsed)s")
    }

    func testConcurrentProbesAllComplete() async {
        let paths = (0..<8).map { _ in NSTemporaryDirectory() }
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for path in paths {
                group.addTask { await MountInfo.isMountResponsive(path: path, timeout: 3) }
            }
            var collected: [Bool] = []
            for await result in group { collected.append(result) }
            return collected
        }
        XCTAssertEqual(results.count, paths.count)
        XCTAssertTrue(results.allSatisfy { $0 }, "All local probes should succeed")
    }
}

final class ForceUnmountTests: XCTestCase {

    func testForceUnmountOnNonMountPointThrows() {
        let path = URL(filePath: NSTemporaryDirectory()).appending(path: "not-a-mount-\(UUID().uuidString)")
        XCTAssertThrowsError(try MountData.forceUnmount(url: path)) { error in
            guard case MountError.unmountFailed = error else {
                XCTFail("Expected .unmountFailed, got \(error)")
                return
            }
        }
    }

    func testForceUnmountErrorCarriesErrno() {
        let path = URL(filePath: "/definitely/not/mounted/\(UUID().uuidString)")
        do {
            try MountData.forceUnmount(url: path)
            XCTFail("Expected a throw")
        } catch MountError.unmountFailed(let code) {
            XCTAssertNotEqual(code, 0, "errno should describe the failure")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// `MountError` gained an associated value; equality must still work for callers.
    func testMountErrorEquatable() {
        XCTAssertEqual(MountError.badURL, MountError.badURL)
        XCTAssertEqual(MountError.unmountFailed(2), MountError.unmountFailed(2))
        XCTAssertNotEqual(MountError.unmountFailed(2), MountError.unmountFailed(5))
        XCTAssertNotEqual(MountError.badURL, MountError.noMountData)
    }
}

final class TimeoutTests: XCTestCase {

    func testFastOperationReturnsItsValue() async throws {
        let value = try await withTimeout(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testSlowOperationThrowsTimeout() async {
        do {
            _ = try await withTimeout(seconds: 0.2) {
                try await Task.sleep(for: .seconds(10))
                return 1
            }
            XCTFail("Expected a timeout")
        } catch is TimeoutError {
            // expected
        } catch {
            XCTFail("Expected TimeoutError, got \(error)")
        }
    }

    func testTimeoutReportsItsBudget() async {
        do {
            _ = try await withTimeout(seconds: 0.15) {
                try await Task.sleep(for: .seconds(10))
                return 1
            }
            XCTFail("Expected a timeout")
        } catch let error as TimeoutError {
            XCTAssertEqual(error.seconds, 0.15)
        } catch {
            XCTFail("Expected TimeoutError, got \(error)")
        }
    }

    func testOperationErrorPropagates() async {
        enum Sample: Error { case failed }
        do {
            _ = try await withTimeout(seconds: 5) { throw Sample.failed }
            XCTFail("Expected the operation's own error")
        } catch is TimeoutError {
            XCTFail("Should surface the operation error, not a timeout")
        } catch {
            XCTAssertTrue(error is Sample)
        }
    }

    func testTimeoutReturnsPromptly() async {
        let start = Date()
        _ = try? await withTimeout(seconds: 0.2) {
            try await Task.sleep(for: .seconds(10))
            return 1
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.5, "Timeout should fire near its budget, took \(elapsed)s")
    }
}
