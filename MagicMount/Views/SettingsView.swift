//
//  SettingsView.swift
//  MagicMount
//
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuInBar", store: UserDefaults(suiteName: "group.org.tassinari.magicmount"))
    private var showMenuInBar = true

    var body: some View {
        Form {
            Toggle("Show in menu bar", isOn: $showMenuInBar)
            Button("Clear previous servers") {
                AddEditModel.clearPreviousServers()
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
    }
}
