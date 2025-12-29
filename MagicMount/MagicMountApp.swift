//
//  MagicMountApp.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/24/25.
//

import SwiftUI

enum MounterConstants {
    static let newMountWindowID: String = "newMountWindowID"
}

@main
struct MagicMountApp: App {
    var body: some Scene {
        WindowGroup {
            MountsView(shares: MountInfo.mountedVolumes().filter({$0.type != "file"}))
        }
        WindowGroup(id: MounterConstants.newMountWindowID) {
            NewMount()
                
        }
    }
}
