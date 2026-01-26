//
//  Logger.swift
//  MagicMount
//
//  Created by Mark Tassinari on 12/28/25.
//


import Foundation
import os

internal nonisolated func debug(_ msg: String) {
    Task {
        await MagicMountLog.shared.debug(msg)
    }
}

internal nonisolated func notice(_ msg: String) {
    Task {
        await MagicMountLog.shared.notice(msg)
    }
}

internal nonisolated func error(_ msg: String) {
    Task {
        await MagicMountLog.shared.error(msg)
    }
}

internal actor MagicMountLog {

    static let shared = MagicMountLog()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "MagicMount"
    )

    func debug(_ msg: String) {
        logger.debug("\(msg)")
    }

    func notice(_ msg: String) {
        logger.notice("\(msg)")
    }

    func error(_ msg: String) {
        logger.error("\(msg, privacy: .public)")
    }
}
