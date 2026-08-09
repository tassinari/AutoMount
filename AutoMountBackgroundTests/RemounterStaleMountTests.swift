//
//  RemounterStaleMountTests.swift
//  AutoMountBackgroundTests
//
//  Covers the two changes that keep a wake-from-sleep from freezing the app:
//  reconnectAll no longer runs on the main actor, and it clears stale mounts
//  before consulting the mount list.
//

import XCTest
import libMounter
@testable import AutoMountBackground

final class RemounterStaleMountTests: XCTestCase {

    private func makeShare(name: String = "share",
                           host: String = "localHost",
                           connected: ConnectionState = .unmounted) -> Share {
        Share(url: URL(string: "smb://\(host)")!,
              name: name,
              mountPoint: "/Volumes/\(name)",
              managed: true,
              connected: connected)
    }

    /// Stale mounts must be cleared on every remount pass, otherwise a dead mount point
    /// keeps reporting as connected and nothing is ever remounted.
    @MainActor func testRemountClearsStaleMounts() async throws {
        let storage = MockStorage(list: [makeShare()], mountResponse: .success(nil))
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        XCTAssertFalse(storage.clearStaleMountsCalled)
        await remounter.checkAndRemount(.wake)

        XCTAssertTrue(storage.clearStaleMountsCalled,
                      "A remount pass must clear stale mounts first")
    }

    /// Ordering is the whole point: reading the mount list before clearing stale mounts
    /// would see a dead mount as connected and skip the remount.
    @MainActor func testStaleMountsClearedBeforeMountListIsRead() async throws {
        let storage = MockStorage(list: [makeShare()], mountResponse: .success(nil))
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        await remounter.checkAndRemount(.wake)

        guard let clearIndex = storage.callLog.firstIndex(of: "clearStaleMounts"),
              let listIndex = storage.callLog.firstIndex(of: "fullMountList") else {
            XCTFail("Expected both calls, got \(storage.callLog)")
            return
        }
        XCTAssertLessThan(clearIndex, listIndex,
                          "Stale mounts must be cleared before the list is read: \(storage.callLog)")
    }

    /// The share is remounted after its stale mount point has been detached — the sequence
    /// that used to produce a duplicate mount such as /Volumes/media-1.
    @MainActor func testStaleMountIsClearedThenShareRemounted() async throws {
        let share = makeShare(name: "media")
        let storage = MockStorage(list: [share],
                                  mountResponse: .success("/Volumes/media"),
                                  staleMounts: ["/Volumes/media"])
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        await remounter.checkAndRemount(.wake)

        XCTAssertTrue(storage.clearStaleMountsCalled)
        XCTAssertTrue(storage.mountCalled, "The share should be remounted after clearing")
        XCTAssertEqual(storage.callLog.first, "clearStaleMounts")
    }

    /// Clearing runs even when every share already looks connected: the mount list cannot
    /// be trusted until the stale entries are gone.
    @MainActor func testClearsStaleMountsEvenWhenAllSharesLookConnected() async throws {
        let storage = MockStorage(list: [makeShare(connected: .mounted)])
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        await remounter.checkAndRemount(.wake)

        XCTAssertTrue(storage.clearStaleMountsCalled)
        XCTAssertFalse(storage.mountCalled, "A genuinely connected share should not be remounted")
    }

    /// `reconnectAll` must not be main-actor isolated. If it were, this call would need to
    /// hop to the main actor and would serialise behind any main-thread work.
    func testRemountRunsOffTheMainActor() async throws {
        let storage = MockStorage(list: [makeShare()], mountResponse: .success(nil))
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        // Deliberately called from a non-main-actor context.
        XCTAssertFalse(Thread.isMainThread, "Precondition: this test body is not on the main thread")
        await remounter.checkAndRemount(.network)

        let called = await MainActor.run { storage.mountCalled }
        XCTAssertTrue(called)
    }

    /// A remount pass must not block the main thread. Before the fix, `reconnectAll` was
    /// `@MainActor`, so the mount work ran there and an unreachable server froze the UI.
    @MainActor func testRemountDoesNotBlockTheMainThread() async throws {
        let storage = MockStorage(list: [makeShare()], mountHandler: { _ in
            // Simulates a slow mount against an unresponsive server.
            try await Task.sleep(for: .milliseconds(600))
            return .success(nil)
        })
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        let remountTask = Task { await remounter.checkAndRemount(.wake) }

        // While the remount is in flight the main actor must stay free to do work.
        try await Task.sleep(for: .milliseconds(100))
        let start = Date()
        var counter = 0
        for _ in 0..<1000 { counter += 1 }
        let mainActorLatency = Date().timeIntervalSince(start)

        XCTAssertEqual(counter, 1000)
        XCTAssertLessThan(mainActorLatency, 0.3,
                          "Main actor was blocked for \(mainActorLatency)s during a remount")
        await remountTask.value
    }

    /// Storage errors during clearing must not abort the remount pass.
    @MainActor func testRemountProceedsWhenNothingIsStale() async throws {
        let storage = MockStorage(list: [makeShare()],
                                  mountResponse: .success(nil),
                                  staleMounts: [])
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        await remounter.checkAndRemount(.wake)

        XCTAssertTrue(storage.clearStaleMountsCalled)
        XCTAssertTrue(storage.mountCalled, "An unmounted share should still be remounted")
    }
}
