//
//  Logger.swift
//  AutoMount
//
//  Created by Mark Tassinari on 12/28/25.
//


import Foundation
import os


internal func debug( _ msg : String){
    MounterLog().debug(msg)
}
internal func notice( _ msg : String){
    MounterLog().notice(msg)
}
internal func error( _ msg : String){
    MounterLog().error(msg)
}

/// Thin wrapper around `os.Logger` providing debug, notice, and error logging
/// for the Mounter subsystem (category: `"Mounter"`).
internal struct MounterLog : Sendable{
    
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
