//
//  MountsViewModel.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/25/26.
//
import Foundation
import libMounter
import AppKit
import ServiceManagement
import SwiftUI

@Observable final class MountsViewModel{
    private var unmountNote : NSObjectProtocol?
    private var mountNote : NSObjectProtocol?
    var mounts: [Share] = []
    let storage: Storage
    
    deinit {
        if let unmountNote = unmountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(unmountNote)
        }
        if let mountNote = mountNote {
            NSWorkspace.shared.notificationCenter.removeObserver(mountNote)
        }
    }
    @MainActor init(storage : Storage = StorageManager(), service : AppServiceInterface) {
        self.storage = storage
        do{
            switch service.status {
            case .notRegistered:
                try service.register()
            case .enabled:
                MagicMount.notice("SMService enabled")
                break // No-op, already approved
            case .requiresApproval:
                //TODO: show note in UI on how to enable
                MagicMount.notice("SMService requires approval")
                break
            case .notFound:
                MagicMount.notice("SMService not found!")
            @unknown default:
                break
            }
        }catch{
            MagicMount.error("SMService start threw error: \(String(describing: error))")
        }
        refresh()
        mountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            if let info = note.userInfo{
                self?.updateConnection(mounted: true, dict: info)
            }
        }
        unmountNote  = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) {[weak self] note in
            if let info = note.userInfo{
                self?.updateConnection(mounted: false, dict: info)
            }
        }
    }
    /// updates Share from a user info dictionary passed by the mount/unmount notification
    func updateConnection(mounted: Bool, dict: [AnyHashable: Any]){
        if  let path = dict["NSDevicePath"] as? String{
            var found = false
            for mount in mounts{
                if mount.mountPoint == path{
                    found = true
                    withAnimation {
                        mount.connected = mounted ? .mounted : .unmounted
                    }
                }
            }
            if !found{
                self.refresh()
            }
        }
        else{
            self.refresh()
        }
    }
   
    func refresh(){
        mounts = storage.fullMountList ?? []
    }
    


}
