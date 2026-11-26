//
//  ClamshellDetector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import Foundation
import IOKit
import os.log

@MainActor
enum ClamshellDetector {
    private static let closedLidAngleThreshold: Double = 8

    private static var registryReportedClosed = false
    private static var consecutiveRegistryOpenReadings = 0
    private static let registryOpenReadingsRequiredToClearSticky = 10
    private static var lastRegistryReadTime: Date?
    private static let minRegistryReadInterval: TimeInterval = 2.0

    private static var lastLoggedIsClosed: Bool?

    /// Read on screen-parameter changes, wakes and power-guard refreshes; logs only when the answer changes.
    static var isClosed: Bool {
        let (closed, reason) = evaluateIsClosed()
        if closed != lastLoggedIsClosed {
            lastLoggedIsClosed = closed
            os_log("ClamshellDetector: isClosed - %{public}@ (%{public}@)", closed ? "true" : "false", reason)
        }
        return closed
    }

    private static func evaluateIsClosed() -> (Bool, String) {
        let now = Date()
        if let lastRead = lastRegistryReadTime, now.timeIntervalSince(lastRead) < minRegistryReadInterval {
            return (registryReportedClosed, "cached within interval")
        }
        lastRegistryReadTime = now

        if let registryState = readAppleClamshellState() {
            if registryState {
                consecutiveRegistryOpenReadings = 0
                registryReportedClosed = true
                return (true, "registryState=true")
            }

            consecutiveRegistryOpenReadings += 1
            if consecutiveRegistryOpenReadings >= registryOpenReadingsRequiredToClearSticky {
                registryReportedClosed = false
                consecutiveRegistryOpenReadings = 0
            }

            if registryReportedClosed {
                return (true, "registryReportedClosed sticky, registryState=false")
            }
            return (false, "registryState=false")
        }

        if registryReportedClosed {
            return (true, "registryReportedClosed sticky, registry read failed")
        }

        let sensor = LidAngleSensor.shared
        if sensor.isAvailable, sensor.angle <= closedLidAngleThreshold {
            return (true, String(format: "lid angle: %.1f", sensor.angle))
        }

        let displayBased = isLikelyClamshellFromDisplays
        return (displayBased, String(format: "displayBased, sensorAvailable: %@, sensorAngle: %.1f",
                                     sensor.isAvailable ? "true" : "false", sensor.angle))
    }

    static func resetStickyState() {
        registryReportedClosed = false
        consecutiveRegistryOpenReadings = 0
    }

    private static var nativeChangeHandler: ((Bool) -> Void)?
    private static var isObservingNatively = false

    @discardableResult
    static func startObservingNativeEvents(_ handler: @escaping (Bool) -> Void) -> Bool {
        nativeChangeHandler = handler
        guard !isObservingNatively else { return true }

        let started = startClamshellStateNotifications { isClosed in
            MainActor.assumeIsolated {
                ClamshellDetector.receiveNativeStateChange(isClosed)
            }
        }
        isObservingNatively = started
        return started
    }

    private static func receiveNativeStateChange(_ isClosed: Bool) {
        registryReportedClosed = isClosed
        consecutiveRegistryOpenReadings = 0
        lastRegistryReadTime = Date()
        os_log("ClamshellDetector: native event - isClosed=%{public}@", isClosed ? "true" : "false")
        nativeChangeHandler?(isClosed)
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