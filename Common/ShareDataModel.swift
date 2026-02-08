//
//  StorageModel.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/31/26.
//

import Foundation
import libMounter
import AppKit
import SwiftUI

/// An obserable wrapper arounf the Storage class.  Publishes observable `shares` for the UI, wraps all the operations around storage and calls refresh after each operation

@MainActor @Observable final class ShareDataModel {
    
    var shares: [Share] = []
    private var storage: Storage
    var showAddShare : Bool = false
    
    private var unmountNote : NSObjectProtocol?
    private var mountNote : NSObjectProtocol?
   
    
    @MainActor deinit {
        if let unmountNote = unmountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(unmountNote)
        }
        if let mountNote = mountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(mountNote)
        }
    }
    
    init(storage : Storage){
        self.storage = storage
        Task{
            await load()
        }
        mountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) {  note in
            if let info = note.userInfo {
                let path = info["NSDevicePath"] as? String
                Task {@MainActor [weak self] in
                    self?.updateConnection(mounted: true, devicePath: path)
                }
            }
        }
        unmountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { note in
            if let info = note.userInfo {
                let path = info["NSDevicePath"] as? String
                Task {@MainActor [weak self] in
                    self?.updateConnection(mounted: false, devicePath: path)
                }
            }
        }
    }
    /// updates Share from a user info dictionary passed by the mount/unmount notification
    private func updateConnection(mounted: Bool, devicePath: String?){
        Task{
            await self.load()
        }
    }

    func mount(_ share : Share, ui: Bool = false) async throws -> MountResponse{
        //swap out the share to a mounting copy
        let loading = share.mountingCopy
        var mutableShares = shares
        if let index = mutableShares.firstIndex(of: share){
            mutableShares[index] = loading
            shares = mutableShares
        }
        let response = try await storage.mount(share, ui: ui)
        await load()
        return response
    }
    func unmount(_ share : Share) async throws{
        //swap out the share to a mounting copy
        let loading = share.unmountingCopy
        var mutableShares = shares
        if let index = mutableShares.firstIndex(of: share){
            mutableShares[index] = loading
            shares = mutableShares
        }
        try await storage.unmount(share)
        await load()
    }
    func manage(_ share : Share) async throws {
        try await storage.addMount(share)
        await load()
    }
    func unmanage(_ share : Share) async throws {
        try await storage.deleteMount(share)
        await load()
    }
    func load() async {
        let theShares = await storage.fullMountList()
        withAnimation {
            shares = theShares
        }
    }
}
