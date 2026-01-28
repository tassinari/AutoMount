//
//  MountCellModel.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/27/26.
//


import SwiftUI
import libMounter

@Observable class MountCellViewModel {
    let share: Share
    let manageHandler: ((Share) -> Void)?
    let storage : Storage
    var autoMount: Bool {
        set {
            share.managed = newValue
            do {
                if newValue {
                    try storage.addMount(share)
                } else {
                    try storage.deleteMount(share)
                }
            } catch {
                MagicMount.error(
                    "Cell mount/unmount error: \(String(describing: error))"
                )
            }
        }
        get {
            return share.managed
        }
    }

    init(share: Share, storage: Storage = StorageManager() , handler: ((Share) -> Void)? = nil) {
        self.share = share
        self.manageHandler = handler
        self.storage = storage
    }

    func eject() {
        Task {
            do {
                try await storage.unmount(share)
            } catch {
                MagicMount.error("unmount error : \(String(describing: error))")
            }
        }
    }
    
    func mount() {
        Task {
            do {
                let result = try await storage.mount(share)
                switch result {
                case .success(_):
                    break
                default:
                    MagicMount.error("mount error, non success returned (\(result))")
                }
            } catch {
                MagicMount.error("mount error : \(String(describing: error))")
            }
        }
    }
    
    func edit() {
        manageHandler?(share)
    }
    
    func mountUnmountPressed() {
        switch share.connected {
        case .mounted:
            eject()
        case .unmounted:
            mount()
        default:
            //no op the other cases
            break
        }
    }
    var shouldShowOpenIcon: Bool {
        share.connected == .mounted || share.connected == .unmounting
    }
    var shouldDisableMountBoutton: Bool {
        share.connected == .mounting || share.connected == .unmounting
    }

}
