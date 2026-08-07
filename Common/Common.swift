//
//  Common.swift
//  AutoMount
//
//  Created by Mark Tassinari on 1/25/26.
//

import Foundation
import libMounter
import ServiceManagement



extension StorageManager : Storage {}

public protocol Storage {
    
    func fullMountList() async -> [Share]
    func addMount(_ mount: Share) async throws
    func deleteMount(_ mount: Share) async throws
    
    func mount(_ : Share, ui: Bool) async throws -> MountResponse
    func unmount(_ : Share) async throws
}


public protocol AppServiceInterface{
    func register() throws
    func unregister() throws
    var status : SMAppService.Status {get}
    static func openSystemSettingsLoginItems()
}

class DefaultServiceInterface : AppServiceInterface{
    private var service : SMAppService
    init(){
        service =  SMAppService.loginItem(identifier: "org.tassinari.AutoMount.AutoMountBackground")
    }
    func register() throws{
        try service.register()
    }
    func unregister() throws{
        try service.unregister()
    }
    var status : SMAppService.Status {
        return service.status
    }
    class func openSystemSettingsLoginItems(){
        SMAppService.openSystemSettingsLoginItems()
    }
}
