//
//  MagicMountApp.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/24/25.
//

import SwiftUI
import libMounter


@main
struct MagicMountApp: App {
    
    private let model = ShareDataModel(storage: StorageManager())
    var body: some Scene {
        WindowGroup {
            ShareListView(model: model)
        }
        .commands{ MountCommandMenu(model: model) }
        Settings {
            SettingsView()
        }
    }
}
