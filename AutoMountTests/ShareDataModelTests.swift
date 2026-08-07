//
//  ShareDataModelTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 2/4/26.
//

import XCTest
import Foundation
import libMounter
import ServiceManagement
@testable import MagicMount

@MainActor
final class ShareDataModelTests: XCTestCase {

    func testInitWithStorageLoadsShares() async throws{
        let shares = [
            Share(url: URL(string: "localhost")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares)
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        XCTAssert(model.shares.count == shares.count)
        XCTAssertEqual(model.shares, shares)
      
        
    }
    func testMountNotificationCallsReload() async throws{
        let shares = [
            Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares)
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        XCTAssert(model.shares.count == shares.count)
        XCTAssertEqual(model.shares, shares)
        let shares2 = [
            Share(url: URL(string: "localhost4")!, name: "test4", mountPoint: "/some/path4", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost5")!, name: "test5", mountPoint: "/some/path5", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost6")!, name: "test6", mountPoint: "/some/path6", managed: true, connected: .mounted)
                
        ]
        storage.mockMountList = shares2
        let info = ["NSDevicePath" : "/some/path/to/dosnt/matter"]
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didMountNotification, object: nil, userInfo: info)
        XCTAssertNotEqual(shares, shares2)
        
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssert(model.shares.count == shares.count)
        XCTAssertEqual(model.shares, shares2)
    }
    func testUnMountNotificationCallsReload() async throws{
        let shares = [
            Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares)
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        XCTAssert(model.shares.count == shares.count)
        XCTAssertEqual(model.shares, shares)
        let shares2 = [
            Share(url: URL(string: "localhost4")!, name: "test4", mountPoint: "/some/path4", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost5")!, name: "test5", mountPoint: "/some/path5", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost6")!, name: "test6", mountPoint: "/some/path6", managed: true, connected: .mounted)
                
        ]
        storage.mockMountList = shares2
        let info = ["NSDevicePath" : "/some/path/to/dosnt/matter"]
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didUnmountNotification, object: nil, userInfo: info)
        XCTAssertNotEqual(shares, shares2)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssert(model.shares.count == shares.count)
        XCTAssertEqual(model.shares, shares2)
    }
    
    func testMountSuccess() async throws{
        let path = "works"
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares, mountResponse: .success(path))
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        let resp = try await model.mount(share)
        switch resp{
        case .success(let p):
            XCTAssertEqual(p, path)
        default:
            XCTFail()
        }
    }
    func testMountError() async throws{
       
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares, mountResponse: .genericError(TestError.someError))
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        let resp = try await model.mount(share)
        switch resp{
        case .genericError(let err):
            guard let error = err as? TestError else { XCTFail(); return }
            XCTAssertEqual(error, TestError.someError)
        default:
            XCTFail()
        }
    }
    func testMountThrows() async throws{
       
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares, throwError: TestError.someError)
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        do{
            let resp = try await model.mount(share)
            XCTFail("should not succeed but got \(resp)")
        }catch let err as TestError{
            XCTAssert(err == TestError.someError)
        }catch{
            XCTFail("wrong error got \(error)")
        }
    }
    func testUnMountSuccess() async throws{
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .mounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares)
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        XCTAssertFalse(storage.unmountCalled)
        try await model.unmount(share)
        XCTAssertTrue(storage.unmountCalled)
    }
   
    func testUnMountThrows() async throws{
       
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
                
        ]
        let storage = MockStorage(list: shares, throwError: TestError.someError)
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        do{
            try await model.unmount(share)
            XCTFail("should not succeed but got")
        }catch let err as TestError{
            XCTAssert(err == TestError.someError)
        }catch{
            XCTFail("wrong error got \(error)")
        }
    }
    func testAddSuccess() async throws{
        
        let exp = expectation(description: "wait")
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
        ]
        let storage = MockStorage(list: shares, addHandler:  { passedshare in
            XCTAssert(passedshare == share)
            exp.fulfill()
        })
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        try await model.manage(share)
        await fulfillment(of: [exp], timeout: 1)
    }
    
    func testAddThrows() async throws{
        
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
        ]
        let storage = MockStorage(list: shares, throwError: TestError.someError)
    
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        do{
            try await model.manage(share)
            XCTFail("should have thrown")
        }catch let err as TestError{
            XCTAssert(err == .someError)
        }catch{
            XCTFail("Got \(error)")
        }
      
    }
    func testDeleteSuccess() async throws{
        
        let exp = expectation(description: "wait")
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
        ]
        let storage = MockStorage(list: shares,deleteHandler:  { passedshare in
            XCTAssert(passedshare == share)
            exp.fulfill()
        })
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        try await model.unmanage(share)
        await fulfillment(of: [exp], timeout: 1)
    }
    
    func testDeleteThrows() async throws{
        
        let share = Share(url: URL(string: "localhost1")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let shares = [
            share,
            Share(url: URL(string: "localhost2")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted),
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
        ]
        let storage = MockStorage(list: shares, throwError: TestError.someError)
    
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        do{
            try await model.unmanage(share)
            XCTFail("should have thrown")
        }catch let err as TestError{
            XCTAssert(err == .someError)
        }catch{
            XCTFail("Got \(error)")
        }
      
    }

    func testURLMatchWorks() async throws{
        let share = Share(url: URL(string: "smb://localhost1/some/path")!, name: "test", mountPoint: "/some/path", managed: true, connected: .unmounted)
        let share2 = Share(url: URL(string: "afp://localhost1/some/other/path")!, name: "test2", mountPoint: "/some/path1", managed: true, connected: .mounted)
        let shares = [
            share,
            share2,
            Share(url: URL(string: "localhost3")!, name: "test3", mountPoint: "/some/path2", managed: true, connected: .mounted)
        ]
        let storage = MockStorage(list: shares, throwError: TestError.someError)
    
        let model = ShareDataModel(storage: storage)
        try await Task.sleep(nanoseconds: 1000)
        guard let testURL = URL(string: "smb://localhost1/some/path") else {XCTFail() ; return}
        XCTAssert(model.shareMatching(url: testURL) == share)
        guard let failtestURL = URL(string: "smb://localhost1/some/bad/path") else {XCTFail() ; return}
        XCTAssertNil(model.shareMatching(url: failtestURL) )
        guard let test2URL = URL(string: "afp://localhost1/some/other/path") else {XCTFail() ; return}
        XCTAssert(model.shareMatching(url: test2URL) == share2 )
        guard let failtestHttp = URL(string: "http://localhost1/some/path") else {XCTFail() ; return}
        XCTAssertNil(model.shareMatching(url: failtestHttp) )
    }
    
    func testLoginItemEnabledReturnsTrue() async throws {
        let storage = MockStorage(list: [])
        let model = ShareDataModel(storage: storage, appService: MockSMService(mockStatus: .enabled))
        try await Task.sleep(nanoseconds: 1000)
        XCTAssertTrue(model.isLoginItemEnabled)
    }

    func testLoginItemNotRegisteredReturnsFalse() async throws {
        let storage = MockStorage(list: [])
        let model = ShareDataModel(storage: storage, appService: MockSMService(mockStatus: .notRegistered))
        try await Task.sleep(nanoseconds: 1000)
        XCTAssertFalse(model.isLoginItemEnabled)
    }

    func testInitRegistersLoginItemWhenNotEnabled() async throws {
        let storage = MockStorage(list: [])
        let service = MockSMService(mockStatus: .notRegistered)
        _ = ShareDataModel(storage: storage, appService: service)
        try await Task.sleep(nanoseconds: 1000)
        XCTAssertTrue(service.registerCalled)
    }

    func testInitDoesNotRegisterWhenAlreadyEnabled() async throws {
        let storage = MockStorage(list: [])
        let service = MockSMService(mockStatus: .enabled)
        _ = ShareDataModel(storage: storage, appService: service)
        try await Task.sleep(nanoseconds: 1000)
        XCTAssertFalse(service.registerCalled)
    }

    func testEnableLoginItemSucceedsWhenStatusBecomesEnabled() async throws {
        let storage = MockStorage(list: [])
        // Start not-registered so init attempts registration; registration "succeeds"
        // and the service now reports .enabled, so the model reflects that.
        let service = MockSMService(mockStatus: .enabled)
        service.mockStatus = .notRegistered
        let model = ShareDataModel(storage: storage, appService: service)
        service.mockStatus = .enabled
        let enabled = model.enableLoginItem()
        XCTAssertTrue(enabled)
        XCTAssertTrue(model.isLoginItemEnabled)
    }

    func testEnableLoginItemHandlesRegistrationError() async throws {
        let storage = MockStorage(list: [])
        let service = MockSMService(mockStatus: .notRegistered, shouldThrow: TestError.someError)
        let model = ShareDataModel(storage: storage, appService: service)
        // A thrown register error must not crash and must leave the item disabled.
        let enabled = model.enableLoginItem()
        XCTAssertTrue(service.registerCalled)
        XCTAssertFalse(enabled)
        XCTAssertFalse(model.isLoginItemEnabled)
    }

    enum TestError : Error{
        case someError
    }
}
