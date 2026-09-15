//
//  LyricsLog.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation
import os

enum LyricsLog {
    static let logger = Logger(subsystem: "com.shariq.sapphire", category: "lyrics")

    private static let lastByKey = OSAllocatedUnfairLock(initialState: [String: String]())

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func infoOnChange(_ key: String, _ message: String) {
        let changed = lastByKey.withLock { last in
            guard last[key] != message else { return false }
            last[key] = message
            return true
        }
        if changed { info(message) }
    }
}