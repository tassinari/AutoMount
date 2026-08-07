//
//  RemounterTests.swift
//  MagicMount
//
//  Created by Mark Tassinari on 2/11/26.
//

import Foundation
import XCTest
import libMounter
@testable import MagicMountBackground
import OSLog

final class RemounterTests : XCTestCase{
    
    @MainActor func testRemounterInit() async throws {
        let remounter = Remounter(storage:MockStorage())
        XCTAssertNotNil(remounter)
    }
    
    @MainActor func testRemounterCallsMount() async throws {
        let exp = expectation(description: "wait for share")
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountHandler: {thisShare in
            XCTAssertEqual(share, thisShare)
            exp.fulfill()
            return .success(nil)
        })
       
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
       
        await fulfillment(of: [exp], timeout: 1)
    }
    @MainActor func testRemounterDoesntCallMount() async throws {
       
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .mounted)
        let storage = MockStorage(list:[share])
       
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        XCTAssertFalse(storage.mountCalled)

    }
    @MainActor func testRemounterDoesntCallMountAndLogs() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .mounted)
        let storage = MockStorage(list:[share])
       
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("\(name) connected, not attempting remount")}))
       
    }
    @MainActor func testTHrowLogs() async throws {
        enum ErrorTest : Error{
            case someError
        }
       let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], throwError: ErrorTest.someError)
       
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Mount(\(name)) threw:  someError")}))
       
    }
  
    @MainActor func testRemounterCallsMultiMount() async throws {
        let exp = expectation(description: "wait for share")
        
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let share2 = Share(url: URL(string: "smb://localHost2")!, name: "localHost2", mountPoint: "/volume/test2", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share,share2], mountHandler: {thisShare in
            XCTAssert(thisShare == share || thisShare == share2)
            exp.fulfill()
            return .success(nil)
        })
        exp.expectedFulfillmentCount = 2
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
       
        await fulfillment(of: [exp], timeout: 2)
    }
    
    @MainActor func testRemounterLogsError() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .alreadyMounted)
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Mount failure for \(name): already mounted")}))
    }
    @MainActor func testRemounterLogsErrorRefused() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .connectionRefused)
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Mount failure for \(name): connection refused")}))
    }
    @MainActor func testRemounterLogsNoSuch() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .noSuchFileOrDirectory)
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Mount failure for \(name): no such file or directory")}))
    }
    @MainActor func testRemounterLogstimout() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .timeout)
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Mount failure for \(name): timeout")}))
    }
    @MainActor func testRemounterLogsCannotFind() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .cannotFindHost)
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Mount failure for \(name): no host")}))
    }
    @MainActor func testRemounterLogsAuthError() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .authenticationError)
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Mount failure for \(name): auth error")}))
    }
    @MainActor func testRemounterLogsSuccess() async throws {
        let name = "localhost."
        let mp = "/volume/test"
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: mp, managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .success(mp))
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Success, \(name) is mounted on \(mp)")}))
    }
    @MainActor func testRemounterLogsGenericError() async throws {
        enum ErrorTest : Error{
            case someError
        }
        let name = "localhost."
        let mp = "/volume/test"
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: mp, managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .genericError(ErrorTest.someError))
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount(.network)
        
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Generic error in mount attempt: \(String(describing: ErrorTest.someError))")}))
    }
    @MainActor func testRDebounceLogs() async throws {
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share])

        let rm = Remounter(debounceSeconds: 0.2,storage:storage)
        Task { await rm.checkAndRemount(.network) } // launch concurrently
        try await Task.sleep(for: .seconds(0.05))
        await rm.checkAndRemount(.network) // cancels first via reentrancy, logs rescheduling
        let logs = try getLogs()

        XCTAssertTrue(logs.contains(where: {$0.composedMessage.contains("Rescheduling debounced remount")}))
    }
                                
    
    
    
    @MainActor func testDebounceDelaysExecution() async throws {
        let exp = expectation(description: "mount called after debounce")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        var mountTime: Date?

        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost",
                          mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            mountTime = Date.now
            exp.fulfill()
            return .success(nil)
        })

        let rm = Remounter(debounceSeconds: 0.5, storage: storage)
        let callTime = Date.now
        await rm.checkAndRemount(.network)

        await fulfillment(of: [exp], timeout: 2)

        // Mount should not have fired before the debounce period
        let elapsed = mountTime!.timeIntervalSince(callTime)
        XCTAssertGreaterThanOrEqual(elapsed, 0.4,
            "Mount should wait at least the debounce period, but fired after \(elapsed)s")
    }

    @MainActor func testDebounceCoalescesMultipleCalls() async throws {
        let exp = expectation(description: "mount called once after debounce")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        var mountCount = 0
        var mountTime: Date?

        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost",
                          mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            mountCount += 1
            mountTime = Date.now
            exp.fulfill()
            return .success(nil)
        })

        let rm = Remounter(debounceSeconds: 1.0, storage: storage)

        // Call 3 times with short gaps — each should cancel the previous
        Task { await rm.checkAndRemount(.network) }
        try await Task.sleep(for: .seconds(0.2))
        Task { await rm.checkAndRemount(.network) }
        try await Task.sleep(for: .seconds(0.2))
        let lastCallTime = Date.now
        await rm.checkAndRemount(.network)

        await fulfillment(of: [exp], timeout: 3)

        XCTAssertEqual(mountCount, 1, "Mount should fire exactly once")
        let elapsed = mountTime!.timeIntervalSince(lastCallTime)
        XCTAssertGreaterThanOrEqual(elapsed, 0.9,
            "Mount should wait at least the debounce period after the last call, but fired after \(elapsed)s")
    }

    @MainActor func testSetDebounceAllowsRemountAfterChange() async throws {
        let exp = expectation(description: "mount called after debounce lowered")
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list: [share], mountHandler: { _ in
            exp.fulfill()
            return .success(nil)
        })

        // Start with a large debounce so the first call won't fire
        let rm = Remounter(debounceSeconds: 9999, storage: storage)
        Task { await rm.checkAndRemount(.network) } // launch concurrently
        try await Task.sleep(for: .seconds(0.05))
        XCTAssertFalse(storage.mountCalled, "Should be blocked by debounce")

        // Lower debounce to 0 and try again — cancels the 9999s task
        await rm.setDebounce(0)
        await rm.checkAndRemount(.network)

        await fulfillment(of: [exp], timeout: 1)
    }

    func getLogs() throws -> [OSLogEntryLog]{
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: .now.addingTimeInterval(-5))
        let predicate = NSPredicate(format:
                                        "(subsystem == %@ && category == %@)",
                                    Bundle.main.bundleIdentifier!, "MagicMount")
        let entries = try OSLogStore.local().getEntries(at: position, matching: predicate)
        let it = entries.makeIterator()
        var msgs : [OSLogEntryLog] = []
        var msg = it.next()
        while(msg != nil){
            if let entrylog = msg as? OSLogEntryLog{
                msgs.append(entrylog)
            }
            msg = it.next()
        }
        return msgs
    }
}

