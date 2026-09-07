//
//  Constants.swift
//  AutoMount
//
//  Created by Mark Tassinari on 2/1/26.
//

import Foundation

enum Constant{
    
    static let appGroupIdentifier = "group.org.tassinari.automount"
    static let driveIconConnected = "externaldrive.badge.checkmark"
    static let driveIconDisConnected = "externaldrive.badge.xmark"
    static let shareIconTextMounted = "eject.fill"
    static let shareIconTextUnMounted = "arrowshape.up.circle"
    static let shareIconTextMounting = "trash.square"
    static let shareIconTextUnMounting = "arrowshape.down.circle"
    static let serversKey = "servers"
    static let serverEmptyKey = "serverEmptyKey"
    static let networkDebounceKey = "networkDebounceInterval"
    static let periodicRemountKey = "periodicRemountInterval"
    static let networkDebounceDefault: Double = 15   // seconds
    static let periodicRemountDefault: Double = 5    // minutes
    static let networkDebounceOptions: [Double] = [5, 15, 30, 60]
    static let periodicRemountOptions: [Double] = [0, 1, 5, 15, 60]  // 0 = Off
}

/// The app's version as shown to the user.
///
/// Both values are injected at archive time by `Scripts/build-release.sh`
/// (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) rather than stored in the
/// project file, so a debug build legitimately reports the project's
/// placeholder 1.0. The bundle is a parameter so tests can supply their own
/// rather than asserting against whichever plist the test host happens to have.
struct AppVersion {

    /// `CFBundleShortVersionString`, e.g. "1.0.3".
    let short: String
    /// `CFBundleVersion`, e.g. "150".
    let build: String

    /// Falls back to a visibly wrong marker rather than an empty string: a
    /// blank version in the About box reads as a layout bug, "--" reads as
    /// missing data and is searchable in a bug report.
    static let unknown = "--"

    init(bundle: Bundle = .main) {
        func string(_ key: String) -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                return Self.unknown
            }
            return value
        }
        short = string("CFBundleShortVersionString")
        build = string("CFBundleVersion")
    }

    /// Formatted for display, e.g. "Version 1.0.3 (150)".
    var displayText: String {
        String(localized: "settings.about.version \(short) (\(build))")
    }
}
