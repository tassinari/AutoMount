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
import ServiceManagement

/// An obserable wrapper arounf the Storage class.  Publishes observable `shares` for the UI, wraps all the operations around storage and calls refresh after each operation

@MainActor @Observable final class ShareDataModel {


    var shares: [Share] = []
    private var storage: Storage
    private let appService: AppServiceInterface
    var showAddShare : Bool = false

    var isLoginItemEnabled: Bool = true

    private var unmountNote : NSObjectProtocol?
    private var mountNote : NSObjectProtocol?
    private var activateNote : NSObjectProtocol?
   
    
    @MainActor deinit {
        if let unmountNote = unmountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(unmountNote)
        }
        if let mountNote = mountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(mountNote)
        }
        if let activateNote = activateNote {
            NotificationCenter.default.removeObserver(activateNote)
        }
    }
    
    init(storage : Storage, appService: AppServiceInterface? = nil){
        self.storage = storage
        self.appService = appService ?? DefaultServiceInterface()
        self.isLoginItemEnabled = self.appService.status == .enabled
        Task{
            await load()
        }
        // Register the background login item so the system knows about it.
        // Without this the helper is never installed and the status stays
        // .notRegistered, which surfaces as the "no background permission" warning.
        enableLoginItem()
        activateNote = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLoginItemStatus()
            }
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
    func refreshLoginItemStatus() {
        isLoginItemEnabled = appService.status == .enabled
    }

    /// Registers the background login item with the system. Safe to call repeatedly:
    /// it no-ops once the item is already enabled. After a successful register the
    /// item may be in `.requiresApproval` until the user approves it in
    /// System Settings → Login Items, so the status is refreshed afterwards.
    @discardableResult
    func enableLoginItem() -> Bool {
        guard appService.status != .enabled else {
            isLoginItemEnabled = true
            return true
        }
        do {
            try appService.register()
            notice("Registered background login item.")
        } catch let registerError {
            error("Failed to register background login item: \(registerError.localizedDescription)")
        }
        refreshLoginItemStatus()
        return isLoginItemEnabled
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
    func shareMatching(url: URL) -> Share?{
        return self.shares.first { share in
            guard let comp = URLComponents(url: share.url, resolvingAgainstBaseURL: false) else { return false}
            guard let matchComp = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false}
            if comp.path == matchComp.path && comp.host == matchComp.host && comp.scheme == matchComp.scheme  {
                return true
            }
            return false
        }
    }
}
