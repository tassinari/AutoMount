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
                Toggle("settings.toggle.show_menu_bar", isOn: $showMenuInBar)
                Button(String(localized: "settings.button.clear_servers")) {
                    AddEditModel.clearPreviousServers()
                }

                Section("settings.section.timing") {
                    Stepper(
                        String(localized: "settings.stepper.network_debounce \(Int(networkDebounce))"),
                        value: $networkDebounce,
                        in: 5...120,
                        step: 5
                    )
                    Stepper(
                        String(localized: "settings.stepper.periodic_remount \(Int(periodicRemount))"),
                        value: $periodicRemount,
                        in: 1...60,
                        step: 1
                    )
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("settings.tab.settings", systemImage: "gear") }

            VStack {
                Text("common.app_name")
                    .font(.title)
                Text("settings.about.attribution")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label("settings.tab.about", systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .frame(minWidth: 300, minHeight: 200)
    }
}
