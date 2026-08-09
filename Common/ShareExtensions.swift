//
//  ShareExtensions.swift
//  AutoMount
//
//  Created by Mark Tassinari on 2/4/26.
//
import libMounter
import Foundation
import AppKit

extension Share {
    var iconText : String{
        switch connected{
            
        case .mounted:
            return  Constant.shareIconTextMounted
        case .unmounted:
            return  Constant.shareIconTextUnMounted
        case .mounting:
            return Constant.shareIconTextMounting
        case .unmounting:
            return Constant.shareIconTextUnMounting
        }
    }
    var canOpen : Bool{
        switch connected{
            
        case .mounted:
           true
        default:
            false
        }
    }
    var showProgressView : Bool{
        switch connected{
            
        case .mounting, .unmounting:
           true
        default:
            false
        }
    }
    // MARK: - Sort helpers

    var sortableName: String { name ?? "" }
    var sortableMountPoint: String { mountPoint ?? "" }
    var sortableManaged: Int { managed ? 1 : 0 }
    var sortableStatus: Int {
        switch connected {
        case .mounted: return 0
        case .mounting: return 1
        case .unmounting: return 2
        case .unmounted: return 3
        }
    }

    /// Reveals the share's mount point in Finder.
    ///
    /// Deliberately does no existence check first. `FileManager.fileExists` on a stale network
    /// mount blocks uninterruptibly until the SMB timeout, and this runs straight off a
    /// SwiftUI button action on the main actor — which is exactly how a dead server used to
    /// beach-ball the menu bar popup. `activateFileViewerSelecting` handles a missing path on
    /// its own, and Finder is the right process to absorb that stall.
    public func open(){
        guard let path = self.mountPoint else {return}
        let url = URL(filePath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
