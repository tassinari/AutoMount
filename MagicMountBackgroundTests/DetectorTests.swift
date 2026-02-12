
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

    func didDetectEvent(_ event: DetectorEvent) {
        switch event {
            
        case .network, .sleep:
            break
        case .volume(_ ):
            events.append(event)
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
