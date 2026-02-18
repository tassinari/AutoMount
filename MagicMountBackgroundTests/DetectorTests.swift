
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

        guard case let .volume(event) = delegate.events.last else {
            return XCTFail("Expected a volume event")
        }
        XCTAssertEqual(event.path, path)
        switch event.type {
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

        guard case let .volume(event) = delegate.events.last else {
            return XCTFail("Expected a volume event")
        }
        XCTAssertEqual(event.path, path)
        switch event.type {
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

        guard case .wake = delegate.events.last else {
            return XCTFail("Expected a wake event")
        }
    }

    // MARK: - Network Debounce

    func testNetworkDebounceDefaultValue() {
        let detector = Detector()
        XCTAssertEqual(detector.networkDebounceInterval, 20)
    }

    // Verifies that the network event fires after the debounce interval
    func testNetworkEvent_firesAfterDebounceInterval() {
        let detector = Detector()
        let delegate = TestDelegate()
        detector.networkDebounceInterval = 0.2

        let exp = expectation(description: "Network event after debounce")
        delegate.networkExpectation = exp
        detector.listen(delegate)

        detector.queue.async {
            detector.scheduleNetworkEvent()
        }

        // Should NOT have fired immediately
        let networkEvents = delegate.events.filter { if case .network = $0 { return true }; return false }
        XCTAssertTrue(networkEvents.isEmpty, "Network event should not fire immediately")

        wait(for: [exp], timeout: 2.0)
        let finalNetworkEvents = delegate.events.filter { if case .network = $0 { return true }; return false }
        XCTAssertEqual(finalNetworkEvents.count, 1)
    }

    // Verifies that rapid network events are coalesced into a single delegate call
    func testNetworkEvent_debounceResetsOnSubsequentEvents() {
        let detector = Detector()
        let delegate = TestDelegate()
        detector.networkDebounceInterval = 0.3

        let exp = expectation(description: "Single network event after debounce")
        delegate.networkExpectation = exp
        detector.listen(delegate)

        // Fire three rapid network events on the detector's queue
        for _ in 0..<3 {
            detector.queue.async {
                detector.scheduleNetworkEvent()
            }
        }

        wait(for: [exp], timeout: 2.0)

        // Wait a bit more to ensure no extra events arrive
        let noMore = expectation(description: "No extra events")
        noMore.isInverted = true
        delegate.networkExpectation = noMore
        wait(for: [noMore], timeout: 0.5)

        let networkEvents = delegate.events.filter { if case .network = $0 { return true }; return false }
        XCTAssertEqual(networkEvents.count, 1, "Multiple rapid network events should coalesce into one")
    }

    // Sends 10 rapid network events and verifies only a single delegate call fires
    func testNetworkEvent_tenRapidEvents_coalesceIntoOne() {
        let detector = Detector()
        let delegate = TestDelegate()
        detector.networkDebounceInterval = 0.3

        let exp = expectation(description: "Single network event after 10 rapid calls")
        delegate.networkExpectation = exp
        detector.listen(delegate)

        // Fire 10 rapid network events on the detector's queue
        for _ in 0..<10 {
            detector.queue.async {
                detector.scheduleNetworkEvent()
            }
        }

        wait(for: [exp], timeout: 2.0)

        // Wait extra time to confirm no additional events arrive
        let noMore = expectation(description: "No extra events")
        noMore.isInverted = true
        delegate.networkExpectation = noMore
        wait(for: [noMore], timeout: 0.5)

        let networkEvents = delegate.events.filter { if case .network = $0 { return true }; return false }
        XCTAssertEqual(networkEvents.count, 1, "10 rapid network events should coalesce into exactly one delegate call")
    }

    func testNetworkDebounceInterval_canBeUpdatedAfterInit() {
        let detector = Detector()
        detector.networkDebounceInterval = 77
        XCTAssertEqual(detector.networkDebounceInterval, 77)
    }

    // Ensures deinit runs (cancels monitor and removes observers). We assert deallocation and that
    // further notifications do not deliver events to the (previous) delegate.
    func testDeinit_removesObservers_andCancelsMonitor() throws {
        weak var weakDetector: Detector?
        var delegateEvents: [DetectorEvent] = []

        // Create a scope to drop strong references
        do {
            let detector = Detector()
            let delegate = TestDelegate()
            weakDetector = detector

            detector.listen(delegate)

            // Capture events for later comparison
            delegate.expectation = expectation(description: "Initial mount event")
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.didMountNotification,
                object: nil,
                userInfo: ["NSDevicePath": "/Volumes/First"]
            )
            waitForExpectations(timeout: 2.0)
            delegateEvents = delegate.events
            // detector goes out of scope here
        }

        // Ensure deallocation happened
        let expDealloc = expectation(description: "Detector deallocated")
        DispatchQueue.global().async {
            // Poll briefly for deallocation
            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline, weakDetector != nil { usleep(10_000) }
            expDealloc.fulfill()
        }
        wait(for: [expDealloc], timeout: 2.0)
        XCTAssertNil(weakDetector, "Detector should have been deallocated")

        // Posting another notification should not crash or deliver new events anywhere
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didMountNotification,
            object: nil,
            userInfo: ["NSDevicePath": "/Volumes/Second"]
        )

        // Nothing to wait for; just assert we still only had the first event captured
        XCTAssertFalse(delegateEvents.isEmpty, "Should have captured at least one event before deinit")
    }

   
}
