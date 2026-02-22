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

  }
}
