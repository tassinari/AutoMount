//
//  MountsCellViewModelTests.swift
//  MagicMountTests
//
//  Created by Mark Tassinari on 1/27/26.
//

import XCTest
@testable import MagicMount
import libMounter
import Observation
internal import ServiceManagement
import OSLog


final class MountsCellViewModelTests: BaseTest {

    let baseshare = Share(user: nil, password: nil, url: URL(string: "smb://localhost")!, name: "test", mountPoint: "/Volumes/share", managed: false, connected: .unmounted)
    
    @MainActor func testModelInits() async throws{
        let mockStorage: MockStorage = MockStorage()
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertNotNil(model)
        XCTAssertEqual(baseshare, model.share)
    }
    
    @MainActor func testEjectCallsUnmount() async throws{
        let mockStorage: MockStorage = MockStorage()
        
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(mockStorage.unmountCalled)
        model.eject()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(mockStorage.unmountCalled)
        XCTAssertFalse(mockStorage.mountCalled)
    }
    
    @MainActor func testEjectLogsThrow() async throws{
        enum TestError : Error{
            case someError
        }
        let mockStorage: MockStorage = MockStorage(throwError: TestError.someError)
        
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(mockStorage.unmountCalled)
        model.eject()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(mockStorage.unmountCalled)
        XCTAssertFalse(mockStorage.mountCalled)
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("unmount error : someError")}))
        
    }
    
    @MainActor func testMountCalls() async throws{
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare))
        
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(mockStorage.mountCalled)
        model.mount()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(mockStorage.mountCalled)
        XCTAssertFalse(mockStorage.unmountCalled)
    }
    @MainActor func testMountFailLogsMountErrors() async throws{
        let cases : [MountResponse] = [.timeout, .authenticationError, .cannotFindHost, .noSuchFileOrDirectory, .connectionRefused, .alreadyMounted]
        let expected = ["timeout", "authenticationError", "cannotFindHost", "noSuchFileOrDirectory", "connectionRefused", "alreadyMounted"]
        for (i,c) in cases.enumerated(){
            let mockStorage: MockStorage = MockStorage(mountResponse: c)
            
            let model = MountCellViewModel(share: baseshare, storage: mockStorage)
            XCTAssertFalse(mockStorage.mountCalled)
            model.mount()
            try await Task.sleep(nanoseconds: 1_000_000)
            XCTAssertTrue(mockStorage.mountCalled)
            XCTAssertFalse(mockStorage.unmountCalled)
            let logs = try getLogs()
            XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("mount error, non success returned (\(expected[i])")}))
        }
       
    }
    
    @MainActor func testMountLogsThrow() async throws{
        enum TestError : Error{
            case someError
        }
        let mockStorage: MockStorage = MockStorage(throwError: TestError.someError)
        
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(mockStorage.unmountCalled)
        model.mount()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(mockStorage.mountCalled)
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("mount error : someError")}))
        
    }
    
    @MainActor func testEditCallsHandler() async throws{
        let mockStorage: MockStorage = MockStorage()
        let exp = expectation(description: "wait for edit")
        let model = MountCellViewModel(share: baseshare, storage: mockStorage){ share in
            XCTAssert(share == self.baseshare)
            exp.fulfill()
        }
        model.edit()
        await fulfillment(of: [exp], timeout: 1)
    }
    
    @MainActor func testMountPressedButtonCallsEject() async throws{
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare))
        baseshare.connected = .mounted
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(mockStorage.unmountCalled)
        model.mountUnmountPressed()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(mockStorage.unmountCalled)
        XCTAssertFalse(mockStorage.mountCalled)
    }
    @MainActor func testMountPressedButtonCallsMount() async throws{
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare))
        baseshare.connected = .unmounted
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(mockStorage.mountCalled)
        model.mountUnmountPressed()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(mockStorage.mountCalled)
        XCTAssertFalse(mockStorage.unmountCalled)
    }
    @MainActor func testMountPressedButtonNoOp() async throws{
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare))
        baseshare.connected = .mounting
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(mockStorage.mountCalled)
        XCTAssertFalse(mockStorage.unmountCalled)
        model.mountUnmountPressed()
        try await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertFalse(mockStorage.mountCalled)
        XCTAssertFalse(mockStorage.unmountCalled)
    }
    @MainActor func testManageGetsManaged() async throws{
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare))
        baseshare.managed = true
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertTrue(baseshare.managed)
        XCTAssertTrue(model.autoMount)
       
        
    }
    @MainActor func testManageGetsUnManaged() async throws{
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare))
        baseshare.managed = false
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        XCTAssertFalse(baseshare.managed)
        XCTAssertFalse(model.autoMount)
       
        
    }
    @MainActor func testManageSetsUnManaged() async throws{
        let exp = expectation(description: "wait for manage")
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare), deleteHandler: { share in
            XCTAssertEqual(share, self.baseshare)
            XCTAssertFalse(self.baseshare.managed)
            exp.fulfill()
        })
        baseshare.managed = true
        XCTAssertTrue(baseshare.managed)
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        model.autoMount.toggle()
        XCTAssertFalse(model.autoMount)
        await fulfillment(of: [exp], timeout: 1)
        
    }
    @MainActor func testManageSetsManaged() async throws{
        let exp = expectation(description: "wait for manage")
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare), addHandler: { share in
            XCTAssertEqual(share, self.baseshare)
            XCTAssertTrue(self.baseshare.managed)
            exp.fulfill()
        })
        baseshare.managed = false
        XCTAssertFalse(baseshare.managed)
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        model.autoMount.toggle()
        XCTAssertTrue(model.autoMount)
        await fulfillment(of: [exp], timeout: 1)
       
        
    }
    @MainActor func testManageToggleThrows() async throws{
        enum TestError : Error{
            case thatError
        }
        let mockStorage: MockStorage = MockStorage(mountResponse: .success(baseshare), addHandler: { share in
            throw TestError.thatError
        })
        baseshare.managed = false
        XCTAssertFalse(baseshare.managed)
        let model = MountCellViewModel(share: baseshare, storage: mockStorage)
        model.autoMount.toggle()
        XCTAssertTrue(model.autoMount)
        let logs = try getLogs()
        XCTAssertTrue( logs.contains(where: {$0.composedMessage.contains("Cell mount/unmount error: thatError")}))
    }
}
