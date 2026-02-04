//
//  MountCellModel.swift
//  MagicMount
//
//  Created by Mark Tassinari on 1/27/26.
//


import SwiftUI
import libMounter

@Observable class MountCellViewModel {
    let store: ShareDataModel
    let share: Share
    let manageHandler: ((Share) -> Void)?
    var autoMount: Bool
    {
        didSet {
            Task{
                do {
                    if autoMount {
                        try await store.manage(share)
                    } else {
                        try await store.unmanage(share)
                    }
                } catch {
                    MagicMount.error(
                        "Cell mount/unmount error: \(String(describing: error))"
                    )
                }
            }
            
        }
    }

    init(share: Share, store: ShareDataModel , handler: ((Share) -> Void)? = nil) {
        self.share = share
        self.manageHandler = handler
        self.store = store
        autoMount = share.managed
    }

    func eject() {
        Task {
            do {
                try await store.unmount(share)
            } catch {
                MagicMount.error("unmount error : \(String(describing: error))")
            }
        }
    }
    
    func mount() {
        Task {
            do {
                let result = try await store.mount(share)
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

    func driveIconName() -> String{
        switch share.connected {
        case .mounted:
            return Constant.driveIconConnected
        default:
            return Constant.driveIconDisConnected
        }
    }
    func driveIconColor() -> Color{
        switch share.connected {
        case .mounted:
            return .green
        default:
            return .gray
        }
    }
}
