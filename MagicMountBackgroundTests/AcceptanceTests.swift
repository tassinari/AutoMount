//
//  AcceptanceTests.swift
//  MagicMountBackgroundTests
//
//  Created by Claude on 2/18/26.
//

import Foundation
import XCTest
import libMounter
@testable import MagicMountBackground

/// End-to-end acceptance tests that exercise the full
/// Model → Detector → Remounter → Storage pipeline,
/// simulating real-world scenarios a user would encounter.
final class AcceptanceTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "org.tassinari.magicmount.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - WiFi Reconnect Scenario

    /// Simulates joining a WiFi network: the OS fires several rapid NWPathMonitor
    /// updates. The debounced pipeline should coalesce them into a single mount attempt.
    @MainActor func testWiFiReconnect_rapidNetworkEvents_mountsOnce() async throws {
        let exp = expectation(description: "mount called exactly once")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        var mountCount = 0

        let share = Share(url: URL(string: "smb://fileserver/docs")!, name: "docs",
                          mountPoint: "/Volumes/docs", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            mountCount += 1
            exp.fulfill()
            return .success("/Volumes/docs")
        })

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0.3, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        // Simulate 5 rapid network events (like NWPathMonitor on WiFi join)
        for _ in 0..<5 {
            model.didDetectEvent(.network)
            try await Task.sleep(for: .milliseconds(50))
        }

        await fulfillment(of: [exp], timeout: 3)
        XCTAssertEqual(mountCount, 1, "Rapid network events should coalesce into a single mount")
    }

    // MARK: - Wake From Sleep Scenario

    /// Simulates waking from sleep: a wake event followed by a network event.
    /// Both trigger checkAndRemount, so the debounce should coalesce them.
    @MainActor func testWakeFromSleep_wakeAndNetworkEvents_mountsOnce() async throws {
        let exp = expectation(description: "mount called once after wake+network")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        var mountCount = 0

        let share = Share(url: URL(string: "smb://nas/media")!, name: "media",
                          mountPoint: "/Volumes/media", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            mountCount += 1
            exp.fulfill()
            return .success("/Volumes/media")
        })

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0.3, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        // Wake event fires first, then network becomes available shortly after
        model.didDetectEvent(.wake)
        try await Task.sleep(for: .milliseconds(100))
        model.didDetectEvent(.network)

        await fulfillment(of: [exp], timeout: 3)
        XCTAssertEqual(mountCount, 1, "Wake + network should coalesce into a single mount")
    }

    // MARK: - Mixed Managed and Unmanaged Shares

    /// Only managed + unmounted shares should be remounted.
    /// Unmanaged shares and already-mounted shares should be left alone.
    @MainActor func testRemount_onlyManagedUnmountedShares() async throws {
        let exp = expectation(description: "only managed unmounted share is mounted")
        var mountedNames: [String] = []

        let managedUnmounted = Share(url: URL(string: "smb://server/work")!, name: "work",
                                     mountPoint: "/Volumes/work", managed: true, connected: .unmounted)
        let managedMounted = Share(url: URL(string: "smb://server/archive")!, name: "archive",
                                   mountPoint: "/Volumes/archive", managed: true, connected: .mounted)
        let unmanagedUnmounted = Share(url: URL(string: "smb://server/public")!, name: "public",
                                       mountPoint: "/Volumes/public", managed: false, connected: .unmounted)

        let storage = MockStorage(list: [managedUnmounted, managedMounted, unmanagedUnmounted],
                                  mountHandler: { share in
            mountedNames.append(share.name ?? "unknown")
            exp.fulfill()
            return .success(share.mountPoint)
        })

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        model.didDetectEvent(.network)
        await fulfillment(of: [exp], timeout: 2)

        // Small delay to ensure no extra mounts sneak in
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mountedNames, ["work"],
                       "Only managed+unmounted share should be mounted, got: \(mountedNames)")
    }

    // MARK: - Multiple Unmounted Shares

    /// All managed unmounted shares should be reconnected in a single pass.
    @MainActor func testRemount_allManagedUnmountedSharesReconnected() async throws {
        let exp = expectation(description: "all shares mounted")
        exp.expectedFulfillmentCount = 3
        var mountedNames: Set<String> = []

        let shares = [
            Share(url: URL(string: "smb://server/a")!, name: "a", mountPoint: "/Volumes/a", managed: true, connected: .unmounted),
            Share(url: URL(string: "smb://server/b")!, name: "b", mountPoint: "/Volumes/b", managed: true, connected: .unmounted),
            Share(url: URL(string: "smb://server/c")!, name: "c", mountPoint: "/Volumes/c", managed: true, connected: .unmounted),
        ]

        let storage = MockStorage(list: shares, mountHandler: { share in
            mountedNames.insert(share.name ?? "unknown")
            exp.fulfill()
            return .success(share.mountPoint)
        })

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        model.didDetectEvent(.network)
        await fulfillment(of: [exp], timeout: 2)

        XCTAssertEqual(mountedNames, ["a", "b", "c"], "All managed unmounted shares should be reconnected")
    }

    // MARK: - Mount Failure Resilience

    /// A mount failure for one share should not prevent others from being attempted.
    @MainActor func testRemount_failureOnOneShare_doesNotBlockOthers() async throws {
        let exp = expectation(description: "both shares attempted")
        exp.expectedFulfillmentCount = 2
        var attemptedNames: [String] = []

        let failShare = Share(url: URL(string: "smb://dead/gone")!, name: "gone",
                              mountPoint: "/Volumes/gone", managed: true, connected: .unmounted)
        let goodShare = Share(url: URL(string: "smb://server/good")!, name: "good",
                              mountPoint: "/Volumes/good", managed: true, connected: .unmounted)

        let storage = MockStorage(list: [failShare, goodShare], mountHandler: { share in
            attemptedNames.append(share.name ?? "unknown")
            exp.fulfill()
            if share.name == "gone" {
                return .connectionRefused
            }
            return .success(share.mountPoint)
        })

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        model.didDetectEvent(.network)
        await fulfillment(of: [exp], timeout: 2)

        XCTAssertEqual(attemptedNames.count, 2, "Both shares should be attempted even if one fails")
        XCTAssertTrue(attemptedNames.contains("gone"))
        XCTAssertTrue(attemptedNames.contains("good"))
    }

    // MARK: - Empty Share List

    /// No shares configured — a network event should not crash or error.
    @MainActor func testRemount_noShares_completesGracefully() async throws {
        let storage = MockStorage(list: [])

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        model.didDetectEvent(.network)

        // Give the debounced task time to complete
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(storage.mountCalled, "No shares means no mount calls")
    }

    // MARK: - Settings Change Mid-Flight

    /// Changing the debounce interval via UserDefaults takes effect on the next event.
    @MainActor func testSettingsChange_newDebounceAppliesImmediately() async throws {
        let exp = expectation(description: "mount called with new debounce")
        var mountTime: Date?

        let share = Share(url: URL(string: "smb://server/files")!, name: "files",
                          mountPoint: "/Volumes/files", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            mountTime = Date.now
            exp.fulfill()
            return .success(nil)
        })

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 9999, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        // Fire an event with the huge debounce — won't fire anytime soon
        model.didDetectEvent(.network)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(storage.mountCalled, "Should not have mounted yet with 9999s debounce")

        // User changes debounce to 0.1s via settings
        defaults.set(0.1, forKey: Constant.networkDebounceKey)
        try await Task.sleep(for: .milliseconds(200)) // let the notification propagate

        // Fire another event — should use the new debounce
        let callTime = Date.now
        model.didDetectEvent(.network)

        await fulfillment(of: [exp], timeout: 2)
        XCTAssertNotNil(mountTime, "Mount should have been called")
    }

    // MARK: - Volume Event Does Not Trigger Remount

    /// A volume mount/unmount notification should reload the share list,
    /// but NOT trigger a remount cycle.
    @MainActor func testVolumeEvent_doesNotTriggerRemount() async throws {
        let share = Share(url: URL(string: "smb://server/data")!, name: "data",
                          mountPoint: "/Volumes/data", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share])

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        // Send a volume event (a USB drive was plugged in)
        model.didDetectEvent(.volume(MountEvent(type: .mounted, path: "/Volumes/USB")))

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(storage.mountCalled,
                       "Volume events should reload shares, not trigger remount")
    }

    // MARK: - Auth Error Does Not Retry Endlessly

    /// If a share returns an auth error, it should be attempted once per remount cycle,
    /// not retried within the same cycle.
    @MainActor func testAuthError_attemptedOncePerCycle() async throws {
        let exp = expectation(description: "auth share attempted")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true

        let share = Share(url: URL(string: "smb://secure/private")!, name: "private",
                          mountPoint: "/Volumes/private", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            exp.fulfill()
            return .authenticationError
        })

        let defaults = freshDefaults()
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        model.didDetectEvent(.network)
        await fulfillment(of: [exp], timeout: 2)

        // Ensure no extra attempts within the same cycle
        try await Task.sleep(for: .milliseconds(200))
        // assertForOverFulfill would have caught extra calls
    }
}
