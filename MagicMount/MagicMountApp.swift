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
        Window("Main Window", id: "main")  {
            ShareListView(model: model)
        }
        .commands{ MountCommandMenu(model: model) }
        Settings {
            SettingsView()
        }
        .windowResizability(.contentSize)
        Window("MagicMount Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 600, height: 700)
    }
}
