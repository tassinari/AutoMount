//
//  MountsViewModelTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 1/25/26.
//

import XCTest
@testable import MagicMount
import libMounter
import Observation
internal import ServiceManagement
import OSLog

class BaseTest: XCTestCase {
    let defaultsSuiteName = "group.org.tassinari.magicmount.test"
    let baseMockService = MockSMService()
    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults(suiteName: defaultsSuiteName)?.removeObject(forKey: StorageManager.storeKey)
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


final class MountsViewModelTests: BaseTest {

    @MainActor func testModelInit() async throws{
        let mock = MockStorage(list: [])
        let model = MountsViewModel(storage: mock, service: baseMockService)
        XCTAssertNotNil(model)
    }
    @MainActor func testModelMountsMatchesStorage() async throws{
        let shares = [
    
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/1")!, name: "mount1", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/2")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/3")!, name: "mount2", mountPoint: "vol/mount", managed: false, connected:.mounted)
        ]
        let mock = MockStorage(list: shares)
        let model = MountsViewModel(storage: mock, service: baseMockService)
        XCTAssertEqual(model.mounts, shares)
    }
    
    @MainActor func testModelRefreshesListEmpty() async throws{
        let shares = [
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/1")!, name: "mount1", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/2")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted)
        ]
        
        let mock = MockStorage(list: shares)
        let model = MountsViewModel(storage: mock, service: baseMockService)
        XCTAssertEqual(model.mounts, shares)
        mock.mockMountList = []
        model.refresh()
        XCTAssertTrue(model.mounts.isEmpty)
        
    }
    @MainActor func testModelRefreshesList() async throws{
        let shares = [
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/1")!, name: "mount1", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/2")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted)
        ]
        
        let mock = MockStorage(list: shares)
        let model = MountsViewModel(storage: mock, service: baseMockService)
        XCTAssertEqual(model.mounts, shares)
        let list2 = [
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/1")!, name: "mount1", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/2")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/3")!, name: "mount1", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/4")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
        ]
        mock.mockMountList = list2
        model.refresh()
        XCTAssertEqual(model.mounts, list2)
        
    }
    
    @MainActor func testModelUnMountNotificationUpdatesShare() async throws{
        let testShare = Share(user: nil, password: nil, url: URL(string: "smb://example.com/mount1")!, name: "mount1", mountPoint: "Volumes/mount1", managed: false, connected: .mounted)
        let shares = [
            testShare,
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/2")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/3")!, name: "mount2", mountPoint: "vol/mount", managed: false, connected:.mounted)
        ]
        let mock = MockStorage(list: shares)
        let model = MountsViewModel(storage: mock, service: baseMockService)
        XCTAssertEqual(model.mounts, shares)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didUnmountNotification, object: nil, userInfo: ["NSDevicePath" : "Volumes/mount1"])
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssert(testShare.connected == .unmounted)
    }
    @MainActor func testModelMountNotificationUpdatesShare() async throws{
        let testShare = Share(user: nil, password: nil, url: URL(string: "smb://example.com/mount1")!, name: "mount1", mountPoint: "Volumes/mount1", managed: false, connected: .unmounted)
        let shares = [
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/4")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
            testShare,
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/2")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/3")!, name: "mount2", mountPoint: "vol/mount", managed: false, connected:.mounted)
        ]
        let mock = MockStorage(list: shares)
        let model = MountsViewModel(storage: mock, service: baseMockService)
        XCTAssertEqual(model.mounts, shares)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didMountNotification, object: nil, userInfo: ["NSDevicePath" : "Volumes/mount1"])
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssert(testShare.connected == .mounted)
    }
    
    @MainActor func testModelMountNotificationUpdatesShareWithNoUserInfo() async throws{
        //internal refresh should be called
       
        let shares1 = [
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/2")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example.com/3")!, name: "mount2", mountPoint: "vol/mount", managed: false, connected:.mounted)
        ]
        let shares2 = [
            Share(user: nil, password: nil, url: URL(string: "smb://example2.com/4")!, name: "mount3", mountPoint: "vol/mount", managed: false, connected: .mounted),
            Share(user: nil, password: nil, url: URL(string: "smb://example2.com/5")!, name: "mount2", mountPoint: "vol/mount", managed: false, connected:.mounted)
        ]
        XCTAssertNotEqual(shares1, shares2)
        let mock = MockStorage(list: shares1)
        let model = MountsViewModel(storage: mock, service: baseMockService)
        XCTAssertEqual(shares1, model.mounts)
        mock.mockMountList = shares2
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didUnmountNotification, object: nil, userInfo: [:])
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(model.mounts, shares2)
    }
    
    @MainActor func testModelCallsRegister() async throws{
      
        let mock = MockStorage(list: [])
        let mockService = MockSMService(mockStatus: .notRegistered)

        let _ = MountsViewModel(storage: mock, service: mockService)
        XCTAssertTrue(mockService.registerCalled)
        XCTAssertFalse(mockService.unRegisterCalled)
       
    }
    @MainActor func testModelDoesntCallRegisterOnEnabled() async throws{
        
        let mock = MockStorage(list: [])
        let mockService = MockSMService(mockStatus: .enabled)

        let _ = MountsViewModel(storage: mock, service: mockService)
        XCTAssertFalse(mockService.registerCalled)
        XCTAssertFalse(mockService.unRegisterCalled)
        
    }
    @MainActor func testModelLogsWhenServiceNotFOund() async throws{
        
        let mock = MockStorage(list: [])
        let mockService = MockSMService(mockStatus: .notFound)

        let _ = MountsViewModel(storage: mock, service: mockService)
        XCTAssertFalse(mockService.registerCalled)
        XCTAssertFalse(mockService.unRegisterCalled)
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("SMService not found!")}))
        
    }
    @MainActor func testModelLogsWhenServiceEnabled() async throws{
        
        let mock = MockStorage(list: [])
        let mockService = MockSMService(mockStatus: .enabled)

        let _ = MountsViewModel(storage: mock, service: mockService)
        XCTAssertFalse(mockService.registerCalled)
        XCTAssertFalse(mockService.unRegisterCalled)
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("SMService enabled")}))
        
    }
    @MainActor func testModelLogsWhenError() async throws{
        enum MockError : Error{
            case someCase
        }
        
        let mock = MockStorage(list: [])
        let error =  MockError.someCase
        let mockService = MockSMService(mockStatus: .notRegistered, shouldThrow: error)
        let _ = MountsViewModel(storage: mock, service: mockService)
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("SMService start threw error: someCase")}))
        
    }
    @MainActor func testModelLogsWhenRequiresApproval() async throws{
        enum MockError : Error{
            case someCase
        }
        
        let mock = MockStorage(list: [])
        let error =  MockError.someCase
        let mockService = MockSMService(mockStatus: .requiresApproval, shouldThrow: error)
        let _ = MountsViewModel(storage: mock, service: mockService)
        XCTAssertFalse(mockService.registerCalled)
        XCTAssertFalse(mockService.unRegisterCalled)
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("SMService requires approval")}))
        
    }
}
