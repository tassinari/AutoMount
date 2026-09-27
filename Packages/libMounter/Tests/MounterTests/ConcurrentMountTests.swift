//
//  ConcurrentMountTests.swift
//  libMounterTests
//
//  Covers the guards against a share being mounted by several requests at once:
//  the in-flight guard in `StorageManager.mount`, the timeout that cancels a
//  NetFS request left pending across sleep, and the identity key they rely on.
//

import XCTest
@testable import libMounter

/// Counts calls and holds each one open until released, so tests can line up
/// concurrent mounts deterministically.
private actor MountGate {
    private(set) var calls = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        calls += 1
        await withCheckedContinuation { waiting.append($0) }
    }

    var waitingCount: Int { waiting.count }

    func releaseAll() {
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

final class InFlightMountTests: XCTestCase {

    private func makeStorage() -> StorageManager {
        StorageManager(defaults: UserDefaults(suiteName: "group.org.tassinari.automount.inflighttest"))
    }

    private func share(_ urlString: String, name: String = "media") -> Share {
        Share(url: URL(string: urlString)!, name: name, mountPoint: "/Volumes/\(name)",
              managed: true, connected: .unmounted)
    }

    private func waitForWaiters(_ gate: MountGate, count: Int) async throws {
        let deadline = Date.now.addingTimeInterval(2)
        while await gate.waitingCount < count {
            guard Date.now < deadline else { return XCTFail("Timed out waiting for mounts to start") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The core regression: concurrent callers mounting the same share must produce one
    /// NetFS request, not one each.
    func testConcurrentMountsOfTheSameShareMountOnce() async throws {
        let storage = makeStorage()
        let gate = MountGate()
        let target = share("smb://synology/media")
        let perform: @Sendable (Share) async throws -> MountResponse = { _ in
            await gate.enter()
            return .success("/Volumes/media")
        }

        let first = Task { try await storage.mount(target, ui: false, mountedVolumes: { [] }, performMount: perform) }
        try await waitForWaiters(gate, count: 1)
        let second = Task { try await storage.mount(target, ui: false, mountedVolumes: { [] }, performMount: perform) }
        let third = Task { try await storage.mount(target, ui: false, mountedVolumes: { [] }, performMount: perform) }
        try await Task.sleep(for: .milliseconds(100))

        let callsWhileBlocked = await gate.calls
        XCTAssertEqual(callsWhileBlocked, 1, "Later callers must wait for the mount in flight")

        await gate.releaseAll()
        for task in [first, second, third] {
            guard case .success(let path) = try await task.value else {
                return XCTFail("Every caller should see the shared outcome")
            }
            XCTAssertEqual(path, "/Volumes/media")
        }
        let totalCalls = await gate.calls
        XCTAssertEqual(totalCalls, 1)
    }

    /// Two spellings of the same share are the same mount: host case, the default port and
    /// SMB share-name case all differ here.
    func testDifferentSpellingsOfTheSameShareAreTreatedAsOne() async throws {
        let storage = makeStorage()
        let gate = MountGate()
        let perform: @Sendable (Share) async throws -> MountResponse = { _ in
            await gate.enter()
            return .success("/Volumes/media")
        }

        let upper = share("smb://Synology/Media")
        let explicit = share("smb://tassinari@synology:445/media")

        let first = Task {
            try await storage.mount(upper, ui: false, mountedVolumes: { [] }, performMount: perform)
        }
        try await waitForWaiters(gate, count: 1)
        let second = Task {
            try await storage.mount(explicit, ui: false, mountedVolumes: { [] }, performMount: perform)
        }
        try await Task.sleep(for: .milliseconds(100))

        await gate.releaseAll()
        _ = try await first.value
        _ = try await second.value
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
    }

    /// The guard is per share: different shares still mount concurrently.
    func testDifferentSharesMountConcurrently() async throws {
        let storage = makeStorage()
        let gate = MountGate()
        let perform: @Sendable (Share) async throws -> MountResponse = { share in
            await gate.enter()
            return .success(share.mountPoint)
        }

        let mediaShare = share("smb://synology/media", name: "media")
        let photosShare = share("smb://synology/MarkPhotos", name: "MarkPhotos")

        let media = Task {
            try await storage.mount(mediaShare, ui: false, mountedVolumes: { [] }, performMount: perform)
        }
        let photos = Task {
            try await storage.mount(photosShare, ui: false, mountedVolumes: { [] }, performMount: perform)
        }
        try await waitForWaiters(gate, count: 2)

        await gate.releaseAll()
        _ = try await media.value
        _ = try await photos.value
        let calls = await gate.calls
        XCTAssertEqual(calls, 2)
    }

    /// Once a mount finishes, the share is no longer in flight: a later mount (say, after it
    /// dropped again) goes ahead rather than replaying the old result.
    func testShareCanBeMountedAgainAfterPreviousAttemptFinishes() async throws {
        let storage = makeStorage()
        let target = share("smb://synology/media")
        let counter = CallCounter()
        let perform: @Sendable (Share) async throws -> MountResponse = { _ in
            await counter.increment()
            return .timeout
        }

        _ = try await storage.mount(target, ui: false, mountedVolumes: { [] }, performMount: perform)
        _ = try await storage.mount(target, ui: false, mountedVolumes: { [] }, performMount: perform)

        let calls = await counter.count
        XCTAssertEqual(calls, 2)
    }

    /// A failed attempt is cleared from the in-flight table too, so it cannot wedge the share.
    func testThrowingMountIsClearedFromInFlight() async throws {
        struct Boom: Error {}
        let storage = makeStorage()
        let target = share("smb://synology/media")

        do {
            _ = try await storage.mount(target, ui: false, mountedVolumes: { [] },
                                        performMount: { _ in throw Boom() })
            XCTFail("Expected the mount to throw")
        } catch is Boom {}

        let response = try await storage.mount(target, ui: false, mountedVolumes: { [] },
                                                performMount: { _ in .success("/Volumes/media") })
        guard case .success = response else {
            return XCTFail("Expected a fresh attempt after the failure, got \(response)")
        }
    }

    /// An unattended attempt cannot prompt for a password, so a `ui: true` caller that
    /// arrives during it must not inherit its `.authenticationError`: it waits for that
    /// attempt, then makes its own.
    func testInteractiveCallerDoesNotInheritUnattendedAuthenticationFailure() async throws {
        let storage = makeStorage()
        let gate = MountGate()
        let target = share("smb://synology/media")
        let unattended: @Sendable (Share) async throws -> MountResponse = { _ in
            await gate.enter()
            return .authenticationError
        }

        let background = Task {
            try await storage.mount(target, ui: false, mountedVolumes: { [] }, performMount: unattended)
        }
        try await waitForWaiters(gate, count: 1)
        let interactive = Task {
            try await storage.mount(target, ui: true, mountedVolumes: { [] },
                                    performMount: { _ in .success("/Volumes/media") })
        }
        try await Task.sleep(for: .milliseconds(100))
        let callsWhileBlocked = await gate.calls
        XCTAssertEqual(callsWhileBlocked, 1, "The interactive caller must wait, not mount alongside")

        await gate.releaseAll()
        guard case .authenticationError = try await background.value else {
            return XCTFail("The unattended caller keeps its own outcome")
        }
        guard case .success = try await interactive.value else {
            return XCTFail("The interactive caller should have made its own attempt")
        }
    }

    /// If the attempt it waited on succeeded, the interactive caller sees the share in the
    /// mount table and does not mount it a second time.
    func testInteractiveCallerSkipsMountThatSucceededWhileWaiting() async throws {
        let storage = makeStorage()
        let gate = MountGate()
        let target = share("smb://synology/media")
        let mounted = MountedFlag()
        let unattended: @Sendable (Share) async throws -> MountResponse = { _ in
            await gate.enter()
            mounted.set()
            return .success("/Volumes/media")
        }
        let volumes: @Sendable () -> [MountedVolumesData] = {
            mounted.isSet ? [MountedVolumesData(name: "media", remountURL: target.url, path: "/Volumes/media")] : []
        }

        let background = Task {
            try await storage.mount(target, ui: false, mountedVolumes: volumes, performMount: unattended)
        }
        try await waitForWaiters(gate, count: 1)
        let interactive = Task {
            try await storage.mount(target, ui: true, mountedVolumes: volumes,
                                    performMount: { _ in XCTFail("Must not mount twice"); return .timeout })
        }
        try await Task.sleep(for: .milliseconds(100))

        await gate.releaseAll()
        _ = try await background.value
        guard case .alreadyMounted = try await interactive.value else {
            return XCTFail("Expected .alreadyMounted once the first attempt succeeded")
        }
    }
}

/// Lock-guarded flag a mount stub sets to show up in a fake mount table.
private final class MountedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock(); value = true; lock.unlock()
    }

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

/// Lock-guarded record of cancelled tokens.
private final class CancelLog: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [Int] = []

    func record(_ token: Int) {
        lock.lock(); tokens.append(token); lock.unlock()
    }

    var cancelled: [Int] {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }
}

/// Lock-guarded holder for a request's completion callback, so a test can finish the
/// request later -- or never.
private final class PendingFinish: @unchecked Sendable {
    private let lock = NSLock()
    private var finish: (@Sendable (MountResponse) -> Void)?

    func store(_ finish: @escaping @Sendable (MountResponse) -> Void) {
        lock.lock(); self.finish = finish; lock.unlock()
    }

    func complete(_ response: MountResponse) {
        lock.lock(); let finish = self.finish; lock.unlock()
        finish?(response)
    }
}

final class MountRequestTimeoutTests: XCTestCase {

    /// A request that never completes -- the NetFS request parked in NetAuthSysAgent while the
    /// Mac sleeps -- is cancelled at the deadline and reported as a timeout.
    func testPendingRequestIsCancelledAtDeadline() async {
        let log = CancelLog()
        let pending = PendingFinish()

        let response = await MountData.awaitMountRequest(timeout: 0.1, start: { finish in
            pending.store(finish)
            return 42
        }, cancel: { log.record($0) })

        guard case .timeout = response else {
            return XCTFail("Expected .timeout, got \(response)")
        }
        XCTAssertEqual(log.cancelled, [42], "The pending request must be cancelled so it cannot mount later")
    }

    /// A request that completes in time is returned as-is and not cancelled.
    func testCompletedRequestIsReturnedAndNotCancelled() async throws {
        let log = CancelLog()

        let response = await MountData.awaitMountRequest(timeout: 0.2, start: { finish in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
                finish(.success("/Volumes/media"))
            }
            return 7
        }, cancel: { log.record($0) })

        guard case .success(let path) = response else {
            return XCTFail("Expected .success, got \(response)")
        }
        XCTAssertEqual(path, "/Volumes/media")
        // Let the deadline pass; it must not cancel a request that already finished.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(log.cancelled, [])
    }

    /// A request rejected synchronously (NetFS returning an error before queuing it) reports
    /// that error immediately and leaves nothing to cancel.
    func testSynchronousFailureIsReturnedImmediately() async throws {
        let log = CancelLog()

        let response = await MountData.awaitMountRequest(timeout: 0.1, start: { finish in
            finish(.cannotFindHost)
            return nil as Int?
        }, cancel: { log.record($0) })

        guard case .cannotFindHost = response else {
            return XCTFail("Expected .cannotFindHost, got \(response)")
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(log.cancelled, [])
    }

    /// A completion that arrives after the deadline is ignored rather than resuming twice.
    func testLateCompletionAfterTimeoutIsIgnored() async throws {
        let pending = PendingFinish()

        let response = await MountData.awaitMountRequest(timeout: 0.05, start: { finish in
            pending.store(finish)
            return 1
        }, cancel: { _ in })

        guard case .timeout = response else {
            return XCTFail("Expected .timeout, got \(response)")
        }
        pending.complete(.success("/Volumes/media")) // must not crash with a double resume
    }

    /// With no timeout (interactive mounts, where the user may be typing a password) the
    /// request is awaited however long it takes.
    func testNilTimeoutWaitsForCompletion() async {
        let log = CancelLog()

        let response = await MountData.awaitMountRequest(timeout: nil, start: { finish in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                finish(.authenticationError)
            }
            return 3
        }, cancel: { log.record($0) })

        guard case .authenticationError = response else {
            return XCTFail("Expected .authenticationError, got \(response)")
        }
        XCTAssertEqual(log.cancelled, [])
    }
}

final class MountIdentityTests: XCTestCase {

    private func identity(_ urlString: String) -> String {
        Share(url: URL(string: urlString)!, name: nil, mountPoint: nil,
              managed: true, connected: .unmounted).mountIdentity
    }

    func testSMBIdentityIgnoresCaseDefaultPortAndUser() {
        XCTAssertEqual(identity("smb://Synology/Media"),
                       identity("smb://tassinari@synology:445/media"))
    }

    func testDifferentPortsAreDifferentShares() {
        XCTAssertNotEqual(identity("smb://synology/media"),
                          identity("smb://synology:4450/media"))
    }

    func testNFSPathsAreCaseSensitive() {
        XCTAssertNotEqual(identity("nfs://server/Export"),
                          identity("nfs://server/export"))
    }

    func testDifferentSharesOnTheSameHostDiffer() {
        XCTAssertNotEqual(identity("smb://synology/media"),
                          identity("smb://synology/MarkPhotos"))
    }
}
