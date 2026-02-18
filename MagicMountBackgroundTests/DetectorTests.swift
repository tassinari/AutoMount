
//
//  TestDelegate.swift
//  MagicMount
//
//  Created by Mark Tassinari on 2/12/26.
//


import XCTest
@testable import MagicMountBackground
import AppKit

private final class TestDelegate: DetectorDelegate {
    var events: [DetectorEvent] = []
    var expectation: XCTestExpectation?
    var networkExpectation: XCTestExpectation?
    var wakeExpectation: XCTestExpectation?

    func didDetectEvent(_ event: DetectorEvent) {
        events.append(event)
        switch event {
        case .network:
            networkExpectation?.fulfill()
        case .wake:
            wakeExpectation?.fulfill()
        case .volume:
            expectation?.fulfill()
        }
    }
}

final class DetectorTests: XCTestCase {

    // Ensures delegate is wired and listen assigns it
    func testListen_setsDelegate() throws {
        let detector = Detector()
        let delegate = TestDelegate()

        detector.listen(delegate)

        // @testable import exposes internal properties
        XCTAssertTrue(detector.delegate === delegate, "Detector should retain and use the provided delegate")
    }

    // Verifies mount notification triggers volume(mounted) event with the expected path
    func testVolumeMount_postsNotification_triggersDelegate()  {
        let detector = Detector()
        let delegate = TestDelegate()
        let exp = expectation(description: "Receive mounted volume event")
        delegate.expectation = exp

        detector.listen(delegate)

        let path = "/Volumes/USB"
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didMountNotification,
            object: nil,
            userInfo: ["NSDevicePath": path]
        )

        wait(for: [exp], timeout: 2.0)

        guard let volumeEvent = delegate.events.lazy.compactMap({
            if case let .volume(e) = $0 { return e }; return nil
        }).first else {
            return XCTFail("Expected a volume event")
        }
        XCTAssertEqual(volumeEvent.path, path)
        switch volumeEvent.type {
        case .mounted: break
        case .unmounted: XCTFail("Expected mounted event, got unmounted")
        }
    }

    // Verifies unmount notification triggers volume(unmounted) event with the expected path
    func testVolumeUnmount_postsNotification_triggersDelegate() throws {
        let detector = Detector()
        let delegate = TestDelegate()
        let exp = expectation(description: "Receive unmounted volume event")
        delegate.expectation = exp

        detector.listen(delegate)

        let path = "/Volumes/USB"
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didUnmountNotification,
            object: nil,
            userInfo: ["NSDevicePath": path]
        )

        wait(for: [exp], timeout: 2.0)

        guard let volumeEvent = delegate.events.lazy.compactMap({
            if case let .volume(e) = $0 { return e }; return nil
        }).first else {
            return XCTFail("Expected a volume event")
        }
        XCTAssertEqual(volumeEvent.path, path)
        switch volumeEvent.type {
        case .unmounted: break
        case .mounted: XCTFail("Expected unmounted event, got mounted")
        }
    }

    // MARK: - Wake

    func testWake_postsNotification_triggersDelegate() {
        let detector = Detector()
        let delegate = TestDelegate()
        let exp = expectation(description: "Receive wake event")
        delegate.wakeExpectation = exp

        detector.listen(delegate)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        wait(for: [exp], timeout: 2.0)

        guard delegate.events.contains(where: { if case .wake = $0 { return true }; return false }) else {
            return XCTFail("Expected a wake event")
        }
    }

    // MARK: - Network

    func testNetworkEvent_firesOnListen() {
        let detector = Detector()
        let delegate = TestDelegate()
        let exp = expectation(description: "Receive network event on listen")
        delegate.networkExpectation = exp

        detector.listen(delegate)

        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(delegate.events.contains(where: { if case .network = $0 { return true }; return false }),
                       "Expected a .network event after listen")
    }

    // MARK: - Deinit

    func testDeinit_removesObservers_andCancelsMonitor() {
        var detector: Detector? = Detector()
        let delegate = TestDelegate()
        detector?.listen(delegate)

        weak var weakDetector = detector
        detector = nil

        XCTAssertNil(weakDetector, "Detector should deallocate when all references are released")

        // Post a notification after deallocation — should not crash
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didMountNotification,
            object: nil,
            userInfo: ["NSDevicePath": "/Volumes/Gone"]
        )
    }
}
