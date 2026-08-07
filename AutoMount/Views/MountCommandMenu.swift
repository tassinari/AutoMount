//
//  MountCommandMenu.swift
//  MagicMount
//
//

import SwiftUI



struct MountCommandMenu: Commands {
    var model : ShareDataModel
    @Environment(\.openWindow) var openWindow
   var body: some Commands {
       CommandGroup(replacing: .newItem) {
           Button {
               openWindow(value: MainWindow())
           } label: {
               Text("menu.new_window")
           }
           .keyboardShortcut("n", modifiers: [.shift, .command])
       }
       CommandGroup(after: .appSettings) {
           Button(String(localized: "menu.settings")) {
               openWindow(id: "settings")
           }
           .keyboardShortcut(",", modifiers: [.command])
       }
       CommandMenu(String(localized: "menu.mount")) {
           Button {
               model.showAddShare = true
           } label: {
               Text("menu.mount_drive")
           }
           .keyboardShortcut("k",modifiers: [.command])
       }
       CommandGroup(replacing: .help) {
           Button(String(localized: "menu.help")) {
               openWindow(id: "help")
           }
           .keyboardShortcut("/", modifiers: [ .command])
       }
       

  }
}
