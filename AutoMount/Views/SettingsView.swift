//
//  SettingsView.swift
//  AutoMount
//
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuInBar", store: UserDefaults(suiteName: Constant.appGroupIdentifier))
    private var showMenuInBar = true

    @AppStorage(Constant.networkDebounceKey, store: UserDefaults(suiteName: Constant.appGroupIdentifier))
    private var networkDebounce: Double = Constant.networkDebounceDefault

    @AppStorage(Constant.periodicRemountKey, store: UserDefaults(suiteName: Constant.appGroupIdentifier))
    private var periodicRemount: Double = Constant.periodicRemountDefault
    
    @AppStorage(Constant.serverEmptyKey, store: UserDefaults(suiteName: Constant.appGroupIdentifier)) var serverEmpty: Bool = false

    private func debounceLabel(_ seconds: Double) -> String {
        String(localized: "settings.picker.seconds \(Int(seconds))")
    }

    private func periodicLabel(_ minutes: Double) -> String {
        if minutes == 0 {
            return String(localized: "settings.picker.off")
        } else if minutes == 1 {
            return String(localized: "settings.picker.minute")
        } else if minutes == 60 {
            return String(localized: "settings.picker.hour")
        } else {
            return String(localized: "settings.picker.minutes \(Int(minutes))")
        }
    }

    var body: some View {
        TabView {
            Form {
                VStack(alignment: .leading) {
                    Toggle("settings.toggle.show_menu_bar", isOn: $showMenuInBar)
                    Text("settings.description.menubar_note")
                        .font(.callout)
                        .padding([.top, .bottom],3)
                        .foregroundStyle(.secondary)
                    
                }
                VStack(alignment: .leading) {
                    Button(String(localized: "settings.button.clear_servers")) {
                        AddEditModel.clearPreviousServers()
                        
                    }
                    .disabled(serverEmpty)
                    Text("settings.description.clear_servers_note")
                        .font(.callout)
                        .padding([.top, .bottom],3)
                        .foregroundStyle(.secondary)
                }
                

                Section {
                    Picker(String(localized: "settings.picker.network_debounce"), selection: $networkDebounce) {
                        ForEach(Constant.networkDebounceOptions, id: \.self) { value in
                            Text(debounceLabel(value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("settings.description.network_debounce")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("settings.section.network_debounce")
                }

                Section {
                    Picker(String(localized: "settings.picker.periodic_remount"), selection: $periodicRemount) {
                        ForEach(Constant.periodicRemountOptions, id: \.self) { value in
                            Text(periodicLabel(value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("settings.description.periodic_remount")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("settings.section.periodic_remount")
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
// MARK: - Preview (Mock)

#if DEBUG

struct Settings_Previews: PreviewProvider {

    static var previews: some View {
        SettingsView()
    }
}

#endif
