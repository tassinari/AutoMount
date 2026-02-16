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

    @MainActor func testNetworkDebounceReadFromDefaults() async throws {
        let defaults = freshDefaults()
        defaults.set(42.0, forKey: Constant.networkDebounceKey)

        let model = Model(defaults: defaults, storage: MockStorage())

        XCTAssertEqual(model.detector.networkDebounceInterval, 42.0)
    }

    @MainActor func testNetworkDebounceDefaultWhenKeyAbsent() async throws {
        let defaults = freshDefaults()
        // Do NOT set the key

        let model = Model(defaults: defaults, storage: MockStorage())

        XCTAssertEqual(model.detector.networkDebounceInterval, Constant.networkDebounceDefault)
    }

    @MainActor func testDefaultsChangeNotification_updatesDetectorDebounce() async throws {
        let defaults = freshDefaults()
        let model = Model(defaults: defaults, storage: MockStorage())
        XCTAssertEqual(model.detector.networkDebounceInterval, Constant.networkDebounceDefault)

        defaults.set(55.0, forKey: Constant.networkDebounceKey)

        // The notification fires on the main run loop; give it a tick to process.
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(model.detector.networkDebounceInterval, 55.0)
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
}
