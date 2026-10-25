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

    private func timeouts(_ count: Int, _ watchdog: inout NetAuthAgentWatchdog) {
        for _ in 0..<count { watchdog.recordTimeout() }
    }

    func testBelowThresholdDoesNotRestart() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 3)
        timeouts(2, &watchdog)
        XCTAssertFalse(watchdog.shouldRestart(now: start))
    }

    func testThresholdReachedRestarts() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 3)
        timeouts(3, &watchdog)
        XCTAssertTrue(watchdog.shouldRestart(now: start))
    }

    /// Any answer, even a failure, shows the agent is alive.
    func testAnswerResetsTheCount() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 3)
        timeouts(2, &watchdog)
        watchdog.recordAnswer(success: false)
        timeouts(1, &watchdog)
        XCTAssertFalse(watchdog.shouldRestart(now: start))
    }

    /// Used on wake: earlier timeouts no longer count.
    func testResetTimeoutsClearsTheCount() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 3)
        timeouts(2, &watchdog)
        watchdog.resetTimeouts()
        timeouts(1, &watchdog)
        XCTAssertFalse(watchdog.shouldRestart(now: start))
    }

    func testCooldownLimitsRestarts() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 1, cooldown: 900)
        timeouts(1, &watchdog)
        watchdog.recordRestart(now: start)

        timeouts(1, &watchdog)
        XCTAssertFalse(watchdog.shouldRestart(now: start + 899))
        XCTAssertTrue(watchdog.shouldRestart(now: start + 900))
    }

    func testRestartClearsTheCount() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 1, cooldown: 0)
        timeouts(1, &watchdog)
        watchdog.recordRestart(now: start)
        XCTAssertFalse(watchdog.shouldRestart(now: start))
    }

    /// Restarts that are not followed by a successful mount double the cooldown, up to the cap.
    func testCooldownGrowsWhileRestartsDoNotHelp() {
        var watchdog = NetAuthAgentWatchdog(timeoutThreshold: 1, cooldown: 900, maximumCooldown: 3000)
        XCTAssertEqual(watchdog.currentCooldown, 900)
        watchdog.recordRestart(now: start)
        XCTAssertEqual(watchdog.currentCooldown, 900)
        watchdog.recordRestart(now: start)
        XCTAssertEqual(watchdog.currentCooldown, 1800)
        watchdog.recordRestart(now: start)
        XCTAssertEqual(watchdog.currentCooldown, 3000, "Capped at the maximum")

        watchdog.recordAnswer(success: false)
        XCTAssertEqual(watchdog.currentCooldown, 3000, "A failed answer does not show the restart helped")
        watchdog.recordAnswer(success: true)
        XCTAssertEqual(watchdog.currentCooldown, 900)
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

    /// One share on each of three servers.
    private func makeSharesOnSeparateServers() -> [Share] {
        ["smb://nas1/media", "smb://nas2/media", "smb://nas3/media"].map {
            Share(url: URL(string: $0)!, name: nil, mountPoint: nil,
                  managed: true, connected: .unmounted)
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
        XCTAssertTrue(storage.callLog.contains("netFSAgentRestarted"),
                      "The NetFS gate must be reopened before the follow-up pass")
    }

    /// One agent serves every server, so timeouts count across servers: one share on each
    /// of three servers is detected in a single pass, not after three backoff rounds.
    @MainActor func testTimeoutsAcrossServersRestartTheAgent() async {
        let restarter = FakeRestarter()
        let storage = MockStorage(list: makeSharesOnSeparateServers(), mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: true))

        await remounter.checkAndRemount(.network)

        XCTAssertEqual(restarter.restarts, 1)
    }

    /// Timeouts from before a sleep do not count toward a restart after wake.
    @MainActor func testWakeClearsTimeoutsFromBeforeSleep() async {
        let clock = WatchdogClock()
        let restarter = FakeRestarter()
        let shares = Array(makeShares().prefix(2))
        let storage = MockStorage(list: shares, mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  backoff: RemountBackoff(initialDelay: 0, maximumDelay: 0),
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: true),
                                  now: { clock.now })

        await remounter.checkAndRemount(.network)
        XCTAssertEqual(restarter.restarts, 0, "Only 2 timeouts")

        await remounter.checkAndRemount(.wake)
        XCTAssertEqual(restarter.restarts, 0, "Without the wake reset this would make 4 in a row")
    }

    /// A share in backoff is skipped, so it is neither mounted nor counted.
    @MainActor func testSharesInBackoffAreNotCounted() async {
        let restarter = FakeRestarter()
        let storage = MockStorage(list: [makeShares()[0]], mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage,
                                  watchdog: NetAuthAgentWatchdog(timeoutThreshold: 2),
                                  agentRestarter: restarter,
                                  reachability: FakeReachability(reachable: true))

        await remounter.checkAndRemount(.network)
        await remounter.checkAndRemount(.network)

        XCTAssertEqual(mountCount(storage), 1, "The second pass skips the backed-off share")
        XCTAssertEqual(restarter.restarts, 0)
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

        clock.advance(by: 900)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(restarter.restarts, 2, "Restarts that did not help double the cooldown")

        clock.advance(by: 900)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(restarter.restarts, 3)
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
