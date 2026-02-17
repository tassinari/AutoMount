//
//  MountCommandMenu.swift
//  MagicMount
//
//

import SwiftUI



struct MountCommandMenu: Commands {
    var model : ShareDataModel
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings
   var body: some Commands {
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
           .keyboardShortcut("?", modifiers: [.command])
       }
  }
}
