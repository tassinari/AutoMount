//
//  StaleMountTests.swift
//  libMounterTests
//
//  Reproduces the sleep/wake failure these fixes exist for: the server goes away while the
//  kernel still holds the mount. Pausing the SMB container is the closest faithful analogue —
//  the TCP connection stays open but nothing answers, exactly like a NAS after a laptop sleeps.
//

import XCTest
@testable import libMounter

final class StaleMountTests: BaseTest {

    private let shareName = "smbTestShare"
    private let mountPoint = "/Volumes/smbTestShare"
    private static let dockerPath = "/usr/local/bin/docker"

    override class func setUp() {
        // Only start the container if nothing is listening yet: `dockerMount.sh` exits 125 when
        // the container already exists, and these tests share it with the other suites.
        if !Self.isServerAccepting() {
            Self.runPreTestScript(script: "Scripts/dockerMount.sh")
        }
        // Wait for the SMB server to actually accept connections. Mounting before the port is
        // listening returns `.timeout`, which previously made these tests look like product
        // failures when they were really racing container startup.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !Self.isServerAccepting() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    /// Deliberately does *not* remove the container: `dockerUnmount.sh` deletes it outright,
    /// and the other suites in this package share the same one. Tearing it down here left
    /// later tests mounting against a server that no longer existed.
    override class func tearDown() {
        Self.container(command: "unpause")
    }

    /// Whether the SMB test server is listening on its port yet.
    private static func isServerAccepting() -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(1445).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    override func setUp() async throws {
        try await super.setUp()
        Self.container(command: "unpause")
        // Another suite's tearDown may have removed the shared container between tests, so
        // make sure a server is up and listening before each test rather than only once.
        if !Self.isServerAccepting() {
            Self.runPreTestScript(script: "Scripts/dockerMount.sh")
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline, !Self.isServerAccepting() {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    override func tearDown() async throws {
        // Always leave the container running, otherwise a failure here strands later tests.
        Self.container(command: "unpause")
        // Force-detach rather than unmount politely: if the server was left paused, the polite
        // path blocks on the dead session and strands the *next* test behind a stale mount.
        // The detach runs on its own thread, so wait for the mount point to actually clear —
        // otherwise the next test starts against a half-detached mount.
        if MountInfo.isVolumeMounted(at: URL(filePath: mountPoint)) {
            MountData.forceUnmountDetached(path: mountPoint)
            _ = await waitForMountPointToDisappear(mountPoint, timeout: 60)
        }
        try await super.tearDown()
    }

    /// Runs a docker lifecycle command against the test container, ignoring failures
    /// (the container may legitimately not be paused).
    @discardableResult
    private static func container(command: String) -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: dockerPath) else { return -1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = [command, "smb-test"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func requireDocker() throws {
        guard FileManager.default.isExecutableFile(atPath: Self.dockerPath) else {
            throw XCTSkip("Docker is required for stale-mount tests")
        }
        guard Self.isServerAccepting() else {
            throw XCTSkip("SMB test server is not accepting connections")
        }
    }

    /// Mounts the test share and waits for it to appear in the kernel mount table.
    ///
    /// Both halves matter. A mount that silently returned `.timeout` would make later
    /// assertions misleading, and `.alreadyMounted` can be reported while a previous test's
    /// forced detach is still completing in the background — so the mount point is polled
    /// rather than assumed.
    private func mountTestShare() async throws {
        let mountData = MountData(scheme: "smb", host: "localhost", port: 1445, path: shareName)

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if MountInfo.remoteMountPoints().contains(mountPoint) { return }

            let response = try await mountData.mount()
            switch response {
            case .success:
                if MountInfo.remoteMountPoints().contains(mountPoint) { return }
            case .alreadyMounted:
                // Stale bookkeeping from an in-flight detach; wait for it to settle and retry.
                break
            default:
                XCTFail("Could not mount the test share: \(response)")
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
        XCTFail("Test share never appeared at \(mountPoint)")
    }

    /// A mounted, reachable share must read as responsive.
    func testHealthyMountIsResponsive() async throws {
        try requireDocker()
        try await mountTestShare()

        let responsive = await MountInfo.isMountResponsive(path: mountPoint, timeout: 5)
        XCTAssertTrue(responsive, "A reachable mount must be reported as responsive")
    }

    /// The core regression: once the server stops answering, the mount point still exists
    /// in the kernel table but must be recognised as stale rather than treated as healthy.
    func testStaleMountIsDetectedAndCleared() async throws {
        try requireDocker()
        try await mountTestShare()
        XCTAssertTrue(MountInfo.remoteMountPoints().contains(mountPoint),
                      "Precondition: the test share should be mounted")

        Self.container(command: "pause")

        // The mount table still lists it — this is precisely why `fileExists` used to hang.
        XCTAssertTrue(MountInfo.remoteMountPoints().contains(mountPoint),
                      "A stale mount still occupies its mount point")

        let responsive = await MountInfo.isMountResponsive(path: mountPoint, timeout: 4)
        XCTAssertFalse(responsive, "An unreachable mount must be reported as stale")

        let start = Date()
        let cleared = await storage.clearStaleMounts(timeout: 4)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(cleared.contains(mountPoint),
                      "clearStaleMounts should have detached \(mountPoint), cleared: \(cleared)")
        // The caller must not inherit the kernel's teardown wait, which can exceed two minutes.
        XCTAssertLessThan(elapsed, 15,
                          "clearStaleMounts should return promptly, took \(elapsed)s")

        // The detach itself finishes on a background thread, so the mount point disappears
        // shortly afterwards rather than synchronously.
        let removed = await waitForMountPointToDisappear(mountPoint, timeout: 240)
        XCTAssertTrue(removed, "The stale mount point should eventually be gone")
    }

    /// Polls the kernel mount table until `path` is no longer listed.
    private func waitForMountPointToDisappear(_ path: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !MountInfo.remoteMountPoints().contains(path) { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    /// Clearing stale mounts must never detach a working one.
    func testClearStaleMountsLeavesHealthyMountsAlone() async throws {
        try requireDocker()
        try await mountTestShare()
        XCTAssertTrue(MountInfo.remoteMountPoints().contains(mountPoint))

        let cleared = await storage.clearStaleMounts(timeout: 5)

        XCTAssertFalse(cleared.contains(mountPoint), "A healthy mount must not be cleared")
        XCTAssertTrue(MountInfo.remoteMountPoints().contains(mountPoint),
                      "A healthy mount must survive stale clearing")
    }

    /// Reading the kernel mount table must stay fast even while a mount is unreachable —
    /// this is what stops the volume enumeration from freezing the UI.
    func testMountTableStaysFastWhileMountIsStale() async throws {
        try requireDocker()
        try await mountTestShare()

        Self.container(command: "pause")

        let start = Date()
        let volumes = MountInfo.mountedVolumes()
        let mounted = MountInfo.isVolumeMounted(at: URL(filePath: mountPoint))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(mounted, "The stale mount should still be listed")
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertLessThan(elapsed, 1.0,
                          "Enumerating volumes must not block on a dead server, took \(elapsed)s")
    }

    /// The remount URL must survive the round trip through the kernel mount table, so the
    /// share can actually be remounted after its stale mount is cleared.
    func testStaleMountStillYieldsUsableRemountURL() async throws {
        try requireDocker()
        try await mountTestShare()

        Self.container(command: "pause")

        guard let volume = MountInfo.mountedVolumes().first(where: { $0.path == mountPoint }) else {
            XCTFail("Stale mount should still be enumerable")
            return
        }
        XCTAssertEqual(volume.remountURL.scheme, "smb")
        XCTAssertEqual(volume.remountURL.host, "localhost")
        XCTAssertEqual(volume.remountURL.port, 1445)
        XCTAssertEqual(volume.name, shareName)
    }
}
