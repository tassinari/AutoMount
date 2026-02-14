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
        await rm.checkAndRemount()
       
        await fulfillment(of: [exp], timeout: 1)
    }
    @MainActor func testRemounterDoesntCallMount() async throws {
       
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .mounted)
        let storage = MockStorage(list:[share])
       
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount()
        XCTAssertFalse(storage.mountCalled)
       
    }
    @MainActor func testRemounterDoesntCallMountAndLogs() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .mounted)
        let storage = MockStorage(list:[share])
       
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
       
        await fulfillment(of: [exp], timeout: 2)
    }
    
    @MainActor func testRemounterLogsError() async throws {
        let name = "localhost."
        let share = Share(url: URL(string: "smb://localHost")!, name: name, mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share], mountResponse: .alreadyMounted)
        let rm = Remounter(debounceSeconds: 0,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
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
        await rm.checkAndRemount()
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Generic error in mount attempt: \(String(describing: ErrorTest.someError))")}))
    }
    @MainActor func testRemounterDebounceWorks() async throws {
       
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share])
       
        let rm = Remounter(debounceSeconds: 10,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount()
        XCTAssertFalse(storage.mountCalled)
       
    }
    @MainActor func testRDebounceLogs() async throws {
        let share = Share(url: URL(string: "smb://localHost")!, name: "localHost", mountPoint: "/volume/test", managed: true, connected: .unmounted)
        let storage = MockStorage(list:[share])
       
        let rm = Remounter(debounceSeconds: 10,storage:storage)
        XCTAssertFalse(storage.mountCalled)
        XCTAssertNil(storage.shareCalled)
        await rm.checkAndRemount()
        let logs = try getLogs()
        
        XCTAssertTrue(logs.contains(where: {$0.composedMessage.contains("Cache still valid, not remounting")}))
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

