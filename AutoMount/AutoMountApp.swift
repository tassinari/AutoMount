//
//  AutoMountApp.swift
//  AutoMount
//
//  Created by Mark Tassinari on 12/24/25.
//

import SwiftUI
import libMounter


@main
struct AutoMountApp: App {

    @Environment(\.openWindow) var openWindow
    private let model = ShareDataModel(storage: StorageManager())
    var body: some Scene {
        WindowGroup(for: MainWindow.self)  { _ in
            ShareListView(model: model)
        }
        .commands{
            MountCommandMenu(model: model)
        }

        Window(String(localized: "menu.help"), id: "help-background") {
            HelpView(anchor: "background-service")
        }
        .defaultSize(width: 600, height: 700)
        Window(String(localized: "menu.help"), id: "help") {
            HelpView()
        }
        .defaultSize(width: 600, height: 700)
        Window(String(localized: "menu.settings_window"), id: "settings") {
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
