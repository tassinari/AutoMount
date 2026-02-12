//
//  MockStorage.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/25/26.
//

import Foundation
import libMounter
import ServiceManagement

enum MockStore{
    static let store = ShareDataModel(storage: MockStorage(list: PreviewData.mockShares))
    
}

class MockStorage: Storage{
    
    func mount(_ share: libMounter.Share, ui: Bool) async throws -> libMounter.MountResponse {
        mountCalled = true
        shareCalled = share
        if let err = throwError {
            throw err
        }
        if let mountHandler{
            return try await mountHandler(share)
        }
        return mountResponse
    }
    
    func unmount(_: libMounter.Share) async throws {
        unmountCalled = true
        if let err = throwError {
            throw err
        }
    }
    let mountResponse : MountResponse
    let addHandler : (Share) throws -> Void
    @MainActor let mountHandler : ((Share) async throws -> MountResponse)?
    let deleteHandler : (Share) throws -> Void
    var mockMountList: [Share]
    var mountCalled : Bool = false
    var unmountCalled : Bool = false
    var throwError : Error? = nil
    var shareCalled : Share? = nil
    
    init(list: [Share] = [],
         mountResponse: MountResponse = .timeout,
         addHandler: @escaping (Share) throws -> Void = {_ in },
         throwError: Error? = nil,
         deleteHandler : @escaping (Share) throws -> Void = { _ in },
         mountHandler :  ((Share) async throws -> MountResponse)? = nil) {
        self.mockMountList = list
        self.addHandler = addHandler
        self.deleteHandler = deleteHandler
        self.mountResponse = mountResponse
        self.throwError = throwError
        self.mountHandler = mountHandler
    }
    
    func fullMountList() async -> [Share]{
        return mockMountList
    }
    
    func addMount(_ mount: Share) async throws {
        if let err = throwError {
            throw err
        }
        try addHandler(mount)
    }
    
    func deleteMount(_ mount: Share) async throws {
        if let err = throwError {
            throw err
        }
        try deleteHandler(mount)
    }
   
}

class MockSMService : AppServiceInterface{
    var registerCalled : Bool = false
    var unRegisterCalled : Bool = false
    var mockStatus: SMAppService.Status
    var shouldThrow : Error?
    
    init(mockStatus: SMAppService.Status = .notRegistered, shouldThrow: Error? = nil) {
        self.mockStatus = mockStatus
        self.shouldThrow = shouldThrow
    }
    
    func register() throws {
        registerCalled = true
        if let err = shouldThrow{
            throw err
        }
       
    }
    
    func unregister() throws {
        unRegisterCalled = true
        if let err = shouldThrow{
            throw err
        }
        
    }
    
    var status: SMAppService.Status{
        return mockStatus
    }
    
    static func openSystemSettingsLoginItems() {
        
    }
    
    
}
