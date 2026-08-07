//
//  Logger.swift
//  AutoMount
//
//  Created by Mark Tassinari on 12/28/25.
//


import Foundation
import os

internal nonisolated func debug(_ msg: String) {
    Task {
        await AutoMountLog.shared.debug(msg)
    }
}

internal nonisolated func notice(_ msg: String) {
    Task {
        await AutoMountLog.shared.notice(msg)
    }
}

internal nonisolated func error(_ msg: String) {
    Task {
        await AutoMountLog.shared.error(msg)
    }
}

internal actor AutoMountLog {

    static let shared = AutoMountLog()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AutoMount"
    )

    func debug(_ msg: String) {
        logger.debug("\(msg, privacy: .public)")
    }

    func notice(_ msg: String) {
        logger.notice("\(msg, privacy: .public)")
    }

    func error(_ msg: String) {
        logger.error("\(msg, privacy: .public)")
    }
}
