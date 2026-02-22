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

    @Environment(\.openWindow) var openWindow
    private let model = ShareDataModel(storage: StorageManager())
    var body: some Scene {
        WindowGroup(for: MainWindow.self)  { _ in
            ShareListView(model: model)
        }
        .commands{
            MountCommandMenu(model: model)
        }

        Window("MagicMount Help", id: "help-background") {
            HelpView(anchor: "background-service")
        }
        .defaultSize(width: 600, height: 700)
        Window("MagicMount Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 600, height: 700)
        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 400, height: 300)
    }
}
struct MainWindow : Hashable, Identifiable, Codable{
    var id: String {
        return "mainWindow"
    }
}
