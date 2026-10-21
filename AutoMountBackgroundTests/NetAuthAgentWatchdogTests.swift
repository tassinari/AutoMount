//
//  NetAuthAgentWatchdogTests.swift
//  AutoMountBackgroundTests
//
//  Pins when a wedged NetAuthSysAgent gets restarted (issue #62). On 2026-10-21 the
//  agent hung at 03:08 inside an SMB login, and every later mount timed out until it
//  was killed by hand, though the server answered on port 445 throughout.
//

import XCTest
import libMounter
@testable import AutoMountBackground

private final class WatchdogClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); current += seconds; lock.unlock()
    }
}

/// Records restarts instead of killing anything.
private final class FakeRestarter: NetAuthAgentRestarting, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let result: Bool

    init(result: Bool = true) {
        self.result = result
    }

    var restarts: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func restart() async -> Bool {
        lock.lock(); count += 1; lock.unlock()
        return result
    }
}

private struct FakeReachability: ServerReachability {
    let reachable: Bool
    func isReachable(host: String, port: Int, timeout: TimeInterval) async -> Bool { reachable }
}

final class NetAuthAgentWatchdogTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let server = "synology:445"

    func testBelowThresholdDoesNotRestart() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 3)
        watchdog.recordTimeout(server)
        watchdog.recordTimeout(server)
        XCTAssertFalse(watchdog.shouldRestart(for: server, now: start))
    }

    func testThresholdReachedRestarts() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 3)
        for _ in 0..<3 { watchdog.recordTimeout(server) }
        XCTAssertTrue(watchdog.shouldRestart(for: server, now: start))
    }

    func testAnswerResetsTheCount() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 3)
        watchdog.recordTimeout(server)
        watchdog.recordTimeout(server)
        watchdog.recordAnswer(server)
        watchdog.recordTimeout(server)
        XCTAssertFalse(watchdog.shouldRestart(for: server, now: start))
    }

    func testServersAreCountedSeparately() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 2)
        watchdog.recordTimeout(server)
        watchdog.recordTimeout("other:445")
        XCTAssertFalse(watchdog.shouldRestart(for: server, now: start))
        XCTAssertFalse(watchdog.shouldRestart(for: "other:445", now: start))
    }

    func testCooldownLimitsRestarts() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 1, cooldown: 900)
        watchdog.recordTimeout(server)
        watchdog.recordRestart(now: start)

        watchdog.recordTimeout(server)
        XCTAssertFalse(watchdog.shouldRestart(for: server, now: start + 899))
        XCTAssertTrue(watchdog.shouldRestart(for: server, now: start + 900))
    }

    func testRestartClearsEveryCount() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 1, cooldown: 0)
        watchdog.recordTimeout(server)
        watchdog.recordTimeout("other:445")
        watchdog.recordRestart(now: start)
        XCTAssertFalse(watchdog.shouldRestart(for: server, now: start))
        XCTAssertFalse(watchdog.shouldRestart(for: "other:445", now: start))
    }

    func testServerKeyUsesHostAndDefaultPort() {
        XCTAssertEqual(NetAuthAgentWatchdog.serverKey(for: URL(string: "smb://Synology/media")!), "synology:445")
        XCTAssertEqual(NetAuthAgentWatchdog.serverKey(for: URL(string: "smb://synology:4450/media")!), "synology:4450")
        XCTAssertEqual(NetAuthAgentWatchdog.serverKey(for: URL(string: "nfs://nas/export")!), "nas:2049")
        XCTAssertNil(NetAuthAgentWatchdog.serverKey(for: URL(string: "file:///tmp")!))
    }

    /// Reading the process table must work without touching any process.
    func testPidLookupFindsThisProcessByName() {
        let name = String(ProcessInfo.processInfo.processName.prefix(16))
        let pids = NetAuthAgentRestarter.pids(named: name, uid: getuid())
        XCTAssertTrue(pids.contains(getpid()), "Expected \(name) (pid \(getpid())) in \(pids)")
        XCTAssertTrue(NetAuthAgentRestarter.pids(named: "no-such-process-xyz", uid: getuid()).isEmpty)
    }
}

final class RemounterAgentRestartTests: XCTestCase {

    private func makeShares() -> [Share] {
        ["media", "MarkPhotos", "NancyPhotos"].map {
            Share(url: URL(string: "smb://synology/\($0)")!,
                  name: $0,
                  mountPoint: "/Volumes/\($0)",
                  managed: true,
                  connected: .unmounted)
        }
    }

    @MainActor private func mountCount(_ storage: MockStorage) -> Int {
        storage.callLog.filter { $0 == "mount" }.count
    }

    /// The 2026-10-21 morning: every share on a reachable server times out, so the agent is
    /// restarted once and every share is retried in a follow-up pass.
    @MainActor func testRepeatedTimeoutsFromReachableServerRestartTheAgent() async {
        let restarter = FakeRestarter()
        let storage = MockStorage(list: makeShares(), mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: true))

        await remounter.checkAndRemount(.network)

        XCTAssertEqual(restarter.restarts, 1)
        XCTAssertEqual(mountCount(storage), 6, "3 timeouts, restart, then a follow-up pass for all 3")
    }

    @MainActor func testUnreachableServerDoesNotRestartTheAgent() async {
        let restarter = FakeRestarter()
        let storage = MockStorage(list: makeShares(), mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: false))

        await remounter.checkAndRemount(.network)

        XCTAssertEqual(restarter.restarts, 0)
        XCTAssertEqual(mountCount(storage), 3)
    }

    /// A failed restart (no agent running) does not queue a retry pass.
    @MainActor func testFailedRestartDoesNotRetry() async {
        let restarter = FakeRestarter(result: false)
        let storage = MockStorage(list: makeShares(), mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: true))

        await remounter.checkAndRemount(.network)

        XCTAssertEqual(restarter.restarts, 1)
        XCTAssertEqual(mountCount(storage), 3)
    }

    /// A server that keeps timing out after a restart does not get the agent killed again
    /// until the cooldown has passed.
    @MainActor func testRestartsAreLimitedByCooldown() async {
        let clock = WatchdogClock()
        let restarter = FakeRestarter()
        let storage = MockStorage(list: makeShares(), mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  backoff: RemountBackoff(initialDelay: 0, maximumDelay: 0),
                                  watchdog: NetAuthAgentWatchdog(timeoutThreshold: 3, cooldown: 900),
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: true),
                                  now: { clock.now })

        await remounter.checkAndRemount(.network)
        XCTAssertEqual(restarter.restarts, 1)

        clock.advance(by: 600)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(restarter.restarts, 1, "Still inside the cooldown")

        clock.advance(by: 300)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(restarter.restarts, 2)
    }

    /// Timeouts mixed with answers (e.g. a slow server that sometimes mounts) never
    /// reach the threshold.
    @MainActor func testAnsweredMountsKeepTheAgentAlive() async {
        let restarter = FakeRestarter()
        var responses: [MountResponse] = [.timeout, .success("/Volumes/MarkPhotos"), .timeout]
        let storage = MockStorage(list: makeShares(), mountHandler: { _ in responses.removeFirst() })
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: true))

        await remounter.checkAndRemount(.network)

        XCTAssertEqual(restarter.restarts, 0)
    }
}
