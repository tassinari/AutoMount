//
//  ShareDataModelExtension.swift
//  AutoMount
//
//  Created by Mark Tassinari on 2/20/26.
//
import Foundation
import AppKit

///ShareDataModel app specific functions
///

extension ShareDataModel {
    static let settingsURL = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    var canOpenURL : Bool{
        return URL(string: Self.settingsURL) != nil
    }
    var aleternatOpenString : String{
        return String(localized: "share_list.alternate_open_instructions")
    }
    
    func openSettings(){
        guard let url = URL(string: Self.settingsURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    
    
}
