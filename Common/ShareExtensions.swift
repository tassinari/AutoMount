//
//  ShareExtensions.swift
//  MagicMount
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
    public func open(){
        let url = URL(filePath: mountPoint)
        if FileManager.default.fileExists(atPath: url.path){
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        
    }
}
