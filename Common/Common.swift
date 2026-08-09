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

    /// Forcibly detaches any mount point whose server no longer responds.
    ///
    /// - Returns: The mount points that were cleared.
    @discardableResult
    func clearStaleMounts() async -> [String]
}

public extension Storage {
    /// Default no-op, so conformances that do not manage real mounts need not implement it.
    @discardableResult
    func clearStaleMounts() async -> [String] { return [] }
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
