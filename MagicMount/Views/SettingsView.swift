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
        .frame(width: 300)
    }
}
