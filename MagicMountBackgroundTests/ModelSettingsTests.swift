//
//  ModelSettingsTests.swift
//  MagicMountBackgroundTests
//
//  Created by Claude on 2/16/26.
//

import Foundation
import XCTest
import libMounter
@testable import MagicMountBackground

final class ModelSettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "org.tassinari.magicmount.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }


    @MainActor func testPeriodicTimer_callsCheckAndRemount() async throws {
        let defaults = freshDefaults()
        // Set a very small periodic interval (0.003 minutes ≈ 0.2 seconds)
        defaults.set(0.003, forKey: Constant.periodicRemountKey)

        let exp = expectation(description: "mount called by periodic timer")
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            exp.fulfill()
            return .success(nil)
        })
        let remounter = Remounter(debounceSeconds: 0, storage: storage)

        _ = Model(defaults: defaults, remounter: remounter, storage: storage)

        await fulfillment(of: [exp], timeout: 2)
    }

    // MARK: - Network event triggers Remounter

    @MainActor func testNetworkEvent_triggersRemounterViaModel() async throws {
        let defaults = freshDefaults()
        let exp = expectation(description: "mount called via network event")
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            exp.fulfill()
            return .success(nil)
        })
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        model.didDetectEvent(.network)

        await fulfillment(of: [exp], timeout: 2)
    }

    // MARK: - Wake event triggers Remounter

    @MainActor func testWakeEvent_triggersRemounterViaModel() async throws {
        let defaults = freshDefaults()
        let exp = expectation(description: "mount called via wake event")
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            exp.fulfill()
            return .success(nil)
        })
        let remounter = Remounter(debounceSeconds: 0, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        model.didDetectEvent(.wake)

        await fulfillment(of: [exp], timeout: 2)
    }

    // MARK: - Volume event does NOT trigger remount

    @MainActor func testModelVolumeEvent_doesNotTriggerRemount() async throws {
        let defaults = freshDefaults()
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .mounted)
        let storage = MockStorage(list: [share])
        // Use a high debounce so any stray .network events from NWPathMonitor won't trigger mount
        let remounter = Remounter(debounceSeconds: 9999, storage: storage)

        let model = Model(defaults: defaults, remounter: remounter, storage: storage)
        model.didDetectEvent(.volume(MountEvent(type: .mounted, path: "/Volumes/USB")))

        try await Task.sleep(for: .seconds(0.5))
        XCTAssertFalse(storage.mountCalled, "Volume events should not trigger remount")
        withExtendedLifetime(model) {}
    }

    // MARK: - Settings change updates Remounter debounce

    @MainActor func testDefaultsChange_updatesRemounterDebounce() async throws {
        let defaults = freshDefaults()
        defaults.set(9999.0, forKey: Constant.networkDebounceKey)

        let exp = expectation(description: "mount called after debounce lowered")
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            exp.fulfill()
            return .success(nil)
        })
        let remounter = Remounter(debounceSeconds: 9999, storage: storage)
        let model = Model(defaults: defaults, remounter: remounter, storage: storage)

        // Change debounce to 0 via defaults — Model should propagate to remounter
        defaults.set(0.0, forKey: Constant.networkDebounceKey)

        // Give the defaults observer time to fire
        try await Task.sleep(for: .seconds(0.2))

        model.didDetectEvent(.network)

        await fulfillment(of: [exp], timeout: 2)
    }
}
