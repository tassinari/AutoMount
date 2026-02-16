//
//  Constants.swift
//  MagicMount
//
//  Created by Mark Tassinari on 2/1/26.
//

import Foundation

enum Constant{
    
    static let driveIconConnected = "externaldrive.badge.checkmark"
    static let driveIconDisConnected = "externaldrive.badge.xmark"
    static let shareIconTextMounted = "eject.fill"
    static let shareIconTextUnMounted = "arrowshape.up.circle"
    static let shareIconTextMounting = "trash.square"
    static let shareIconTextUnMounting = "arrowshape.down.circle"

    static let networkDebounceKey = "networkDebounceInterval"
    static let periodicRemountKey = "periodicRemountInterval"
    static let networkDebounceDefault: Double = 20   // seconds
    static let periodicRemountDefault: Double = 10   // minutes
}
