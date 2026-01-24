//
//  Logger.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//


import Foundation
import os


internal func debug( _ msg : String){
    MounterLog.shared.debug(msg)
}
internal func notice( _ msg : String){
    MounterLog.shared.notice(msg)
}
internal func error( _ msg : String){
    MounterLog.shared.error(msg)
}

internal class MounterLog : @unchecked Sendable{
    
    static let shared = MounterLog()
    private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: "Mounter"
    )
    
    func debug(_ msg: String){
        logger.debug("\(msg)")
    }
    func notice(_ msg: String){
        logger.notice("\(msg)")
    }
    func error(_ msg: String){
        logger.error("\(msg, privacy: .public)")
    }
}
