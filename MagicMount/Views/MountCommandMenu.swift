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
               Text("New Window")
           }
           .keyboardShortcut("n", modifiers: [.shift, .command])
       }
       CommandGroup(after: .appSettings) {
           Button("Settings…") {
               openWindow(id: "settings")
           }
           .keyboardShortcut(",", modifiers: [.command])
       }
       CommandMenu("Mount") {
           Button {
               model.showAddShare = true
           } label: {
               Text("Mount drive")
           }
           .keyboardShortcut("k",modifiers: [.command])
       }
       CommandGroup(replacing: .help) {
           Button("MagicMount Help") {
               openWindow(id: "help")
           }
           .keyboardShortcut("/", modifiers: [ .command])
       }
       

  }
}
