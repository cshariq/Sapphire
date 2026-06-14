//
//  ClamshellDetector.swift
//  Sapphire
//

import AppKit
import Foundation
import IOKit

@MainActor
enum ClamshellDetector {
    private static let closedLidAngleThreshold: Double = 8

    /// When the registry reports closed, hold that through brief unreadable windows (e.g. notch resize).
    private static var registryReportedClosed = false
    private static var consecutiveRegistryOpenReadings = 0
    private static let registryOpenReadingsRequiredToClearSticky = 3

    static var isClosed: Bool {
        if let registryState = readAppleClamshellState() {
            if registryState {
                consecutiveRegistryOpenReadings = 0
                registryReportedClosed = true
                return true
            }

            consecutiveRegistryOpenReadings += 1
            if consecutiveRegistryOpenReadings >= registryOpenReadingsRequiredToClearSticky {
                registryReportedClosed = false
            }

            if registryReportedClosed {
                return true
            }
            return false
        }

        if registryReportedClosed {
            return true
        }

        let sensor = LidAngleSensor.shared
        if sensor.isAvailable, sensor.angle <= closedLidAngleThreshold {
            return true
        }

        return isLikelyClamshellFromDisplays
    }

    static func resetStickyState() {
        registryReportedClosed = false
        consecutiveRegistryOpenReadings = 0
    }

    private static var isLikelyClamshellFromDisplays: Bool {
        guard isPortableMac else { return false }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }

        var hasActiveBuiltIn = false
        var hasExternal = false

        for screen in screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }

            if CGDisplayIsBuiltin(displayID) != 0 {
                hasActiveBuiltIn = true
            } else {
                hasExternal = true
            }
        }

        return hasExternal && !hasActiveBuiltIn
    }

    private static var isPortableMac: Bool {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return false }

        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let identifier = String(cString: model)
        return identifier.hasPrefix("MacBook")
    }

    private static func readAppleClamshellState() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer {
            if service != 0 {
                IOObjectRelease(service)
            }
        }

        guard service != 0 else { return nil }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return nil
    }
}
