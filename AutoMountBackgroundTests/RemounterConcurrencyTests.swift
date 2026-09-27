//
//  RemounterConcurrencyTests.swift
//  AutoMountBackgroundTests
//
//  Pins that only one remount pass runs at a time. Overlapping passes, each
//  stuck in a mount while the Mac slept, all completed together on wake and
//  mounted the same share at /Volumes/<name>, <name>-1 and <name>-2.
//

import XCTest
import libMounter
@testable import AutoMountBackground

final class RemounterConcurrencyTests: XCTestCase {

    private func makeShare(connected: ConnectionState = .unmounted) -> Share {
        Share(url: URL(string: "smb://synology/MarkPhotos")!,
              name: "MarkPhotos",
              mountPoint: "/Volumes/MarkPhotos",
              managed: true,
              connected: connected)
    }

    /// Polls until `condition` holds, so a test can wait for a pass to reach a mount.
    @MainActor private func waitUntil(timeout: TimeInterval = 2,
                                      _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else {
                return XCTFail("Timed out waiting for condition")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The overnight failure: a pass is stuck in a mount while further wake, network and
    /// timer events arrive. None of them may start a mount of their own alongside it.
    @MainActor func testEventsDuringARunningPassDoNotStartConcurrentMounts() async throws {
        var inFlight = 0
        var maxInFlight = 0
        var mountCount = 0
        var gate: CheckedContinuation<Void, Never>?

        let storage = MockStorage(list: [makeShare()])
        storage.mountHandler = { [unowned storage] _ in
            mountCount += 1
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            if mountCount == 1 {
                // Hold the first mount open, like a NetFS request made as the Mac slept.
                await withCheckedContinuation { gate = $0 }
                // It succeeded, so a later pass must see the share as connected.
                storage.mockMountList = [self.makeShare(connected: .mounted)]
            }
            inFlight -= 1
            return .success("/Volumes/MarkPhotos")
        }
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        let first = Task { await remounter.checkAndRemount(.wake) }
        try await waitUntil { gate != nil }

        let later = [DetectorEvent.network, .timer, .wake].map { event in
            Task { await remounter.checkAndRemount(event) }
        }
        // Give the later events time to get past their debounce.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(mountCount, 1, "No second mount may start while the first is in flight")

        gate?.resume()
        await first.value
        for task in later { await task.value }

        XCTAssertEqual(maxInFlight, 1, "Mounts must never overlap")
        XCTAssertEqual(mountCount, 1, "The share was mounted by the first pass; nothing else should mount it")
    }

    /// Events that arrive during a pass are not dropped: exactly one follow-up pass runs
    /// after it, however many events there were.
    @MainActor func testEventsDuringARunningPassQueueExactlyOneFollowUpPass() async throws {
        var gate: CheckedContinuation<Void, Never>?
        var mountCount = 0

        let storage = MockStorage(list: [makeShare()])
        storage.mountHandler = { _ in
            mountCount += 1
            if mountCount == 1 {
                await withCheckedContinuation { gate = $0 }
            }
            return .timeout
        }
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        let first = Task { await remounter.checkAndRemount(.wake) }
        try await waitUntil { gate != nil }

        let later = (0..<3).map { _ in
            Task { await remounter.checkAndRemount(.network) }
        }
        try await Task.sleep(for: .milliseconds(200))

        gate?.resume()
        await first.value
        for task in later { await task.value }

        let passes = storage.callLog.filter { $0 == "fullMountList" }.count
        XCTAssertEqual(passes, 2, "Expected the original pass plus one follow-up, got \(storage.callLog)")
        XCTAssertEqual(mountCount, 2, "The follow-up pass should retry the still-unmounted share")
    }

    /// Once a pass (and its follow-up) has finished, the next event starts a fresh one.
    @MainActor func testNewPassRunsAfterPreviousPassFinishes() async throws {
        let storage = MockStorage(list: [makeShare()], mountResponse: .timeout)
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        await remounter.checkAndRemount(.wake)
        await remounter.checkAndRemount(.network)

        let passes = storage.callLog.filter { $0 == "fullMountList" }.count
        XCTAssertEqual(passes, 2)
    }
}
