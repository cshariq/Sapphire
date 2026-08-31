//
//  TimeFormatting.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation

extension TimeInterval {

    var asMinuteSecondClock: String {
        let clamped = max(0, isFinite ? self : 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var asStopwatchClock: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}