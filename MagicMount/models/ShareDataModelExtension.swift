//
//  ShareDataModelExtension.swift
//  MagicMount
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
        return "Go to  -> Settings -> General -> Login Items & Extensions -> App Background Activity"
    }
    
    func openSettings(){
        guard let url = URL(string: Self.settingsURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    
    
}
