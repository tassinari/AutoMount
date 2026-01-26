//
//  MockStorage.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/25/26.
//

import Foundation
import libMounter
import ServiceManagement

class MockStorage: Storage {
    let addHandler : (Share) -> Void
    let deleteHandler : (Share) -> Void
    var mockMountList: [Share]
    
    init(list: [Share] = [], addHandler: @escaping (Share) -> Void = {_ in }, deleteHandler : @escaping (Share) -> Void = { _ in }) {
        self.mockMountList = list
        self.addHandler = addHandler
        self.deleteHandler = deleteHandler
    }
    
    var fullMountList: [Share]?{
        return mockMountList
    }
    
    func addMount(_ mount: Share) throws {
        addHandler(mount)
    }
    
    func deleteMount(_ mount: Share) throws {
        deleteHandler(mount)
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
