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
    private var model: MountsViewModel = MountsViewModel()
    var body: some Scene {
        WindowGroup {
            MountsView()
                .environment(model)
        }
        WindowGroup(id: MounterConstants.newMountWindowID) {
            NewMount()
                
                
        }
    }
}
