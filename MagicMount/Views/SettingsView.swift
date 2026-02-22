//
//  SettingsView.swift
//  MagicMount
//
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuInBar", store: UserDefaults(suiteName: "group.org.tassinari.magicmount"))
    private var showMenuInBar = true

    @AppStorage(Constant.networkDebounceKey, store: UserDefaults(suiteName: "group.org.tassinari.magicmount"))
    private var networkDebounce: Double = Constant.networkDebounceDefault

    @AppStorage(Constant.periodicRemountKey, store: UserDefaults(suiteName: "group.org.tassinari.magicmount"))
    private var periodicRemount: Double = Constant.periodicRemountDefault

    var body: some View {
        TabView {
            Form {
                Toggle("Show in menu bar", isOn: $showMenuInBar)
                Button("Clear previous servers") {
                    AddEditModel.clearPreviousServers()
                }

                Section("Timing") {
                    Stepper(
                        "Network debounce: \(Int(networkDebounce))s",
                        value: $networkDebounce,
                        in: 5...120,
                        step: 5
                    )
                    Stepper(
                        "Periodic remount: \(Int(periodicRemount)) min",
                        value: $periodicRemount,
                        in: 1...60,
                        step: 1
                    )
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Settings", systemImage: "gear") }

            VStack {
                Text("Magic Mount")
                    .font(.title)
                Text("by Mark Tassinari")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .frame(minWidth: 300, minHeight: 200)
    }
}
