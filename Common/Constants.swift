//
//  Constants.swift
//  MagicMount
//
//  Created by Mark Tassinari on 2/1/26.
//

import Foundation

enum Constant{
    
    static let appGroupIdentifier = "group.org.tassinari.magicmount"
    static let driveIconConnected = "externaldrive.badge.checkmark"
    static let driveIconDisConnected = "externaldrive.badge.xmark"
    static let shareIconTextMounted = "eject.fill"
    static let shareIconTextUnMounted = "arrowshape.up.circle"
    static let shareIconTextMounting = "trash.square"
    static let shareIconTextUnMounting = "arrowshape.down.circle"
    static let serversKey = "servers"
    static let networkDebounceKey = "networkDebounceInterval"
    static let periodicRemountKey = "periodicRemountInterval"
    static let networkDebounceDefault: Double = 15   // seconds
    static let periodicRemountDefault: Double = 5    // minutes
    static let networkDebounceOptions: [Double] = [5, 15, 30, 60]
    static let periodicRemountOptions: [Double] = [0, 1, 5, 15, 60]  // 0 = Off
}
