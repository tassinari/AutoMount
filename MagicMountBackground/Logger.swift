//
//  Logger.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//


import Foundation
import os


internal func debug( _ msg : String){
    MagicMountLog.shared.debug(msg)
}
internal func notice( _ msg : String){
    MagicMountLog.shared.notice(msg)
}
internal func error( _ msg : String){
    MagicMountLog.shared.error(msg)
}

internal class MagicMountLog{
    
    static let shared = MagicMountLog()
    private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: "MagicMount"
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
