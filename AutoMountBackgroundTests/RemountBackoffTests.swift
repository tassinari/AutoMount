//
//  RemountBackoffTests.swift
//  AutoMountBackgroundTests
//
//  Pins that a share whose mounts keep timing out is retried with growing gaps
//  instead of on every event. On 2026-09-29 back-to-back passes sent well over a
//  hundred mount requests into a wedged NetAuthSysAgent overnight.
//

import XCTest
import libMounter
@testable import AutoMountBackground

/// A clock a test can move by hand.
private final class TestClock: @unchecked Sendable {
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

final class RemountBackoffTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testUnknownShareMayBeAttempted() {
        let backoff = RemountBackoff()
        XCTAssertNil(backoff.retryAfter("smb://synology/media", now: start))
    }

    func testTimeoutsDoubleTheWaitUpToTheCap() {
        var backoff = RemountBackoff(initialDelay: 60, maximumDelay: 300)
        let key = "smb://synology/media"
        var waits: [TimeInterval] = []
        for _ in 0..<5 {
            backoff.recordTimeout(key, now: start)
            waits.append(backoff.retryAfter(key, now: start)!.timeIntervalSince(start))
        }
        XCTAssertEqual(waits, [60, 120, 240, 300, 300])
    }

    func testShareMayBeAttemptedOnceItsWaitHasPassed() {
        var backoff = RemountBackoff(initialDelay: 60, maximumDelay: 300)
        let key = "smb://synology/media"
        backoff.recordTimeout(key, now: start)
        XCTAssertNotNil(backoff.retryAfter(key, now: start + 59))
        XCTAssertNil(backoff.retryAfter(key, now: start + 60))
    }

    func testManyTimeoutsStayAtTheCap() {
        var backoff = RemountBackoff(initialDelay: 60, maximumDelay: 300)
        let key = "smb://synology/media"
        for _ in 0..<10_000 {
            backoff.recordTimeout(key, now: start)
        }
        XCTAssertEqual(backoff.retryAfter(key, now: start)?.timeIntervalSince(start), 300)
    }

    func testResetClearsOnlyThatShare() {
        var backoff = RemountBackoff()
        backoff.recordTimeout("smb://synology/media", now: start)
        backoff.recordTimeout("smb://synology/MarkPhotos", now: start)
        backoff.reset("smb://synology/media")
        XCTAssertNil(backoff.retryAfter("smb://synology/media", now: start))
        XCTAssertNotNil(backoff.retryAfter("smb://synology/MarkPhotos", now: start))
    }

    func testResetRestartsTheSequence() {
        var backoff = RemountBackoff(initialDelay: 60, maximumDelay: 300)
        let key = "smb://synology/media"
        backoff.recordTimeout(key, now: start)
        backoff.recordTimeout(key, now: start)
        backoff.reset(key)
        backoff.recordTimeout(key, now: start)
        XCTAssertEqual(backoff.retryAfter(key, now: start)?.timeIntervalSince(start), 60)
    }

    func testResetAllClearsEveryShare() {
        var backoff = RemountBackoff()
        backoff.recordTimeout("smb://synology/media", now: start)
        backoff.recordTimeout("smb://synology/MarkPhotos", now: start)
        backoff.resetAll()
        XCTAssertNil(backoff.retryAfter("smb://synology/media", now: start))
        XCTAssertNil(backoff.retryAfter("smb://synology/MarkPhotos", now: start))
    }
}

final class RemounterBackoffTests: XCTestCase {

    private func makeShare() -> Share {
        Share(url: URL(string: "smb://synology/media")!,
              name: "media",
              mountPoint: "/Volumes/media",
              managed: true,
              connected: .unmounted)
    }

    @MainActor private func mountCount(_ storage: MockStorage) -> Int {
        storage.callLog.filter { $0 == "mount" }.count
    }

    /// The overnight loop: events keep arriving, but a share that just timed out is not
    /// attempted again until its wait has passed.
    @MainActor func testTimedOutShareIsNotRetriedUntilItsWaitPasses() async {
        let clock = TestClock()
        let storage = MockStorage(list: [makeShare()], mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage, now: { clock.now })

        await remounter.checkAndRemount(.network)
        await remounter.checkAndRemount(.network)
        await remounter.checkAndRemount(.timer)
        XCTAssertEqual(mountCount(storage), 1)

        clock.advance(by: 60)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(mountCount(storage), 2)

        // The second timeout doubles the wait.
        clock.advance(by: 60)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(mountCount(storage), 2)
        clock.advance(by: 60)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(mountCount(storage), 3)
    }

    /// A real wake means the user is back, so backed-off shares are retried at once.
    @MainActor func testWakeRetriesABackedOffShareImmediately() async {
        let clock = TestClock()
        let storage = MockStorage(list: [makeShare()], mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage, now: { clock.now })

        await remounter.checkAndRemount(.network)
        await remounter.checkAndRemount(.wake)
        XCTAssertEqual(mountCount(storage), 2)
    }

    /// Failures other than a timeout return quickly and say nothing about NetFS being
    /// stuck, so they are retried on every event as before.
    @MainActor func testFastFailuresAreNotBackedOff() async {
        let storage = MockStorage(list: [makeShare()], mountResponse: .cannotFindHost)
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        await remounter.checkAndRemount(.network)
        await remounter.checkAndRemount(.network)
        XCTAssertEqual(mountCount(storage), 2)
    }

    /// A share that stops timing out starts its backoff from scratch next time.
    @MainActor func testNonTimeoutOutcomeClearsTheBackoff() async {
        let clock = TestClock()
        var responses: [MountResponse] = [.timeout, .cannotFindHost, .timeout, .success("/Volumes/media")]
        let storage = MockStorage(list: [makeShare()], mountHandler: { _ in
            responses.removeFirst()
        })
        let remounter = Remounter(debounceSeconds: 0, storage: storage, now: { clock.now })

        await remounter.checkAndRemount(.network)   // timeout: wait 60s
        clock.advance(by: 60)
        await remounter.checkAndRemount(.network)   // no host: backoff cleared
        await remounter.checkAndRemount(.network)   // timeout again: wait 60s, not 120s
        clock.advance(by: 60)
        await remounter.checkAndRemount(.network)   // retried after 60s
        XCTAssertEqual(mountCount(storage), 4)
        XCTAssertTrue(responses.isEmpty)
    }
}
