//
//  DDC.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation

class DDC {
    static func isAvailable(for display: Display) -> Bool {
        return !display.isBuiltin
    }

    static func setBrightness(for displayID: CGDirectDisplayID, to value: Float) -> Bool {
        print("[DDC] Setting brightness to \(value) for display \(displayID)")
        return true
    }

    static func setContrast(for displayID: CGDirectDisplayID, to value: Float) -> Bool {
        print("[DDC] Setting contrast to \(value) for display \(displayID)")
        return true
    }

    static func getBrightness(for displayID: CGDirectDisplayID) -> Float? {
        print("[DDC] Faking read brightness for display \(displayID)")
        return 50.0
    }

    static func getContrast(for displayID: CGDirectDisplayID) -> Float? {
        print("[DDC] Faking read contrast for display \(displayID)")
        return 75.0
    }

    static func setPower(for displayID: CGDirectDisplayID, to power: PowerState) -> Bool {
        print("[DDC] Setting power to \(power) for display \(displayID)")
        return true
    }
}