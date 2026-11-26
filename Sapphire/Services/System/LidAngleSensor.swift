//
//  LidAngleSensor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-04-01
//

import AppKit
import Combine
import Foundation
import IOKit.hid
import QuartzCore

enum LASSensorProbeResult: CustomStringConvertible {
    case foundStandard(device: IOHIDDevice)
    case foundVendorSpecific
    case notFound

    var description: String {
        switch self {
        case .foundStandard:
            return "found (standard UsagePage 0x0020)"
        case .foundVendorSpecific:
            return "found (vendor-specific UsagePage 0xFF00)"
        case .notFound:
            return "not found"
        }
    }
}

struct MacModelInfo {
    let identifier: String

    static func current() -> MacModelInfo {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return MacModelInfo(identifier: String(cString: model))
    }
}

struct LASDiagnostic {
    let modelInfo: MacModelInfo
    let probeResult: LASSensorProbeResult

    var statusMessage: String {
        switch probeResult {
        case .foundStandard:
            return String(localized: "Sensor detected and ready.")
        case .foundVendorSpecific:
            return String(localized: "Sensor hardware exists, but only a vendor-specific HID interface was found.")
        case .notFound:
            return String(localized: "No lid angle sensor was detected on this Mac.")
        }
    }

    static let shared: LASDiagnostic = {
        let model = MacModelInfo.current()
        let probe = probeSensor()
        let diagnostic = LASDiagnostic(modelInfo: model, probeResult: probe)

        print("[LAS] Model: \(model.identifier)")
        print("[LAS] Probe: \(probe)")
        print("[LAS] Status: \(diagnostic.statusMessage)")

        return diagnostic
    }()

    static func run() -> LASDiagnostic {
        shared
    }

    private static func probeSensor() -> LASSensorProbeResult {
        if let device = findStandardDevice() {
            return .foundStandard(device: device)
        }

        if deviceExistsWithProductID(0x8104) {
            return .foundVendorSpecific
        }

        return .notFound
    }

    static func findStandardDevice() -> IOHIDDevice? {
        findHIDDevice(usagePage: 0x0020, usage: 0x008A)
    }

    private static func findHIDDevice(usagePage: Int, usage: Int) -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDDeviceUsagePageKey as String: usagePage,
            kIOHIDDeviceUsageKey as String: usage,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }

        for device in devices {
            guard (IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? NSNumber)?.boolValue == true else {
                continue
            }
            var report = [UInt8](repeating: 0, count: 8)
            var length = CFIndex(report.count)

            guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
                continue
            }
            defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

            let result = IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                1,
                &report,
                &length
            )

            if result == kIOReturnSuccess, length >= 3 {
                return device
            }
        }

        return nil
    }

    private static func deviceExistsWithProductID(_ productID: Int) -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return false
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: productID,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return false
        }

        return !devices.isEmpty
    }
}

@MainActor
final class LidAngleSensor: ObservableObject {
    enum Client: Hashable {
        case caffeineManager
        case automationManager
        case hingeAnimationStandby
        case hingeAnimation
        case systemEnhanceSettingsPreview
        case caffeineSettingsPreview
    }

    static let shared = LidAngleSensor()

    @Published private(set) var angle = 120.0
    @Published private(set) var velocity = 0.0
    @Published private(set) var isAvailable = false
    @Published private(set) var isReporting = false
    @Published private(set) var tick: UInt = 0
    @Published private(set) var statusMessage = String(localized: "Sensor not available")

    private(set) var diagnostic: LASDiagnostic?

    private var hidDevice: IOHIDDevice?
    private var isDeviceOpen = false
    private var timer: Timer?
    private var activeClients = Set<Client>()

    private var hidReport = [UInt8](repeating: 0, count: 8)
    private var lastAngle = 0.0
    private var smoothedAngle = 0.0
    private var smoothedVelocity = 0.0
    private var lastUpdateTime: TimeInterval = 0
    private var lastMovementTime: TimeInterval = 0
    private var isFirstUpdate = true
    private var consecutiveReadFailures = 0
    private var recoveryAttempts = 0
    private var nextReopenAttemptTime: TimeInterval = 0

    private enum StandbyPace {
        case alert
        case resting
        case closed
    }

    private var standbyPace = StandbyPace.alert
    private var standbyReferenceAngle: Double?
    private var standbyReferenceTime: TimeInterval = 0
    private var timerInterval: TimeInterval = 0

    private static let angleSmoothingFactor = 0.05
    private static let velocitySmoothingFactor = 0.3
    private static let movementThreshold = 0.5
    private static let movementTimeout: TimeInterval = 0.05
    private static let velocityDecay = 0.5
    private static let additionalDecay = 0.8
    private static let pollInterval: TimeInterval = 0.5
    private static let settingsPreviewPollInterval: TimeInterval = 0.15
    private static let hingeAnimationStandbyPollInterval: TimeInterval = 0.05
    /// Standby only watches for the lid to start moving. Each read is a synchronous HID round trip plus a
    /// main run loop wake-up, the largest steady cost left while idle or playing media, so a lid that has
    /// not moved for a while is read a quarter as often, and a shut lid (clamshell) at the default rate.
    private static let hingeAnimationRestingPollInterval: TimeInterval = 0.2
    private static let hingeAnimationClosedPollInterval: TimeInterval = 0.5
    private static let standbyRestDelay: TimeInterval = 5
    /// Readings are whole degrees and can flicker by one at rest.
    private static let standbyMotionThreshold = 2.0
    private static let standbyClosedAngle = 4.0
    private static let hingeAnimationPollInterval: TimeInterval = 1.0 / 60.0
    private static let readFailureThreshold = 4
    private static let reprobeThreshold = 3
    private static let reopenRetryInterval: TimeInterval = 1
    nonisolated private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    private init() {
        let diagnostic = LASDiagnostic.run()
        self.diagnostic = diagnostic
        statusMessage = diagnostic.statusMessage

        if case .foundStandard(let device) = diagnostic.probeResult {
            hidDevice = device
            isAvailable = true
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil

        if isDeviceOpen, let hidDevice {
            IOHIDDeviceClose(hidDevice, Self.noOptions)
        }
    }

    private var currentPollInterval: TimeInterval {
        if activeClients.contains(.hingeAnimation) {
            return Self.hingeAnimationPollInterval
        }
        let isShowingSettings = activeClients.contains(.systemEnhanceSettingsPreview)
            || activeClients.contains(.caffeineSettingsPreview)
        let baseInterval = isShowingSettings ? Self.settingsPreviewPollInterval : Self.pollInterval
        guard activeClients.contains(.hingeAnimationStandby) else { return baseInterval }
        switch standbyPace {
        case .alert: return Self.hingeAnimationStandbyPollInterval
        case .resting: return min(Self.hingeAnimationRestingPollInterval, baseInterval)
        case .closed: return min(Self.hingeAnimationClosedPollInterval, baseInterval)
        }
    }

    /// Slows the standby poll while the lid sits still or shut, and restores it on the first movement.
    private func updateStandbyPace(for rawAngle: Double) {
        let now = CACurrentMediaTime()
        if let reference = standbyReferenceAngle {
            if abs(rawAngle - reference) >= Self.standbyMotionThreshold {
                standbyReferenceAngle = rawAngle
                standbyReferenceTime = now
            }
        } else {
            standbyReferenceAngle = rawAngle
            standbyReferenceTime = now
        }

        let pace: StandbyPace
        if now - standbyReferenceTime < Self.standbyRestDelay {
            pace = .alert
        } else if rawAngle <= Self.standbyClosedAngle {
            pace = .closed
        } else {
            pace = .resting
        }
        guard pace != standbyPace else { return }
        standbyPace = pace
        guard timer != nil, currentPollInterval != timerInterval else { return }
        timer?.invalidate()
        scheduleTimer()
    }

    private func resetStandbyPace() {
        standbyPace = .alert
        standbyReferenceAngle = nil
        standbyReferenceTime = 0
    }

    func acquire(_ client: Client) {
        let inserted = activeClients.insert(client).inserted
        guard inserted else { return }
        if timer == nil {
            startIfNeeded()
        } else {
            restartTimer()
        }
    }

    func release(_ client: Client) {
        let removed = activeClients.remove(client) != nil
        guard removed else { return }
        if activeClients.isEmpty {
            stop()
        } else {
            restartTimer()
        }
    }

    private func startIfNeeded() {
        guard isAvailable, timer == nil, let hidDevice else { return }
        isDeviceOpen = IOHIDDeviceOpen(hidDevice, Self.noOptions) == kIOReturnSuccess
        if !isDeviceOpen {
            markReadingUnavailable()
        }
        startTimer()
    }

    private func restartTimer() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        startTimer()
    }

    private func startTimer() {
        scheduleTimer()
        poll()
    }

    private func scheduleTimer() {
        let interval = currentPollInterval
        timerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        timer.tolerance = activeClients.contains(.hingeAnimation)
            ? min(0.002, interval * 0.1)
            : min(0.2, interval * 0.2)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if isDeviceOpen, let hidDevice {
            IOHIDDeviceClose(hidDevice, Self.noOptions)
            isDeviceOpen = false
        }
        isReporting = false
        reportingMirror = false
        consecutiveReadFailures = 0
        recoveryAttempts = 0
        nextReopenAttemptTime = 0
        resetStandbyPace()
    }

    private func poll() {
        guard let hidDevice else { return }

        guard isDeviceOpen else {
            reopenIfNeeded(hidDevice)
            return
        }

        var length = CFIndex(hidReport.count)
        let result = IOHIDDeviceGetReport(
            hidDevice,
            kIOHIDReportTypeFeature,
            1,
            &hidReport,
            &length
        )

        guard result == kIOReturnSuccess, length >= 3 else {
            handleReadFailure(on: hidDevice)
            return
        }

        consecutiveReadFailures = 0
        recoveryAttempts = 0
        nextReopenAttemptTime = 0
        // The poll runs many times a second for as long as the app is open. It reads
        // plain copies of what it last published instead of going through the
        // @Published wrappers on every tick.
        if !reportingMirror {
            reportingMirror = true
            isReporting = true
            statusMessage = diagnostic?.statusMessage ?? String(localized: "Sensor detected and ready.")
            isFirstUpdate = true
        }

        let rawValue = UInt16(hidReport[2]) << 8 | UInt16(hidReport[1])
        let rawAngle = Double(rawValue)

        updateVelocity(from: rawAngle)
        updateStandbyPace(for: rawAngle)
        // Only a running hinge animation needs every tick (it times how long the lid has been still); standby
        // just watches for the lid to start moving.
        let needsEveryTick = activeClients.contains(.hingeAnimation)
        guard needsEveryTick || rawAngle != angleMirror || !hasPublishedTick else { return }
        angleMirror = rawAngle
        hasPublishedTick = true
        angle = rawAngle
        tick &+= 1
    }

    private var reportingMirror = false
    private var angleMirror = Double.nan
    private var hasPublishedTick = false
    private var velocityMirror = 0.0

    private func handleReadFailure(on hidDevice: IOHIDDevice) {
        consecutiveReadFailures += 1
        guard consecutiveReadFailures >= Self.readFailureThreshold else { return }

        markReadingUnavailable()
        IOHIDDeviceClose(hidDevice, Self.noOptions)
        isDeviceOpen = false
        recoveryAttempts += 1
        nextReopenAttemptTime = CACurrentMediaTime() + Self.reopenRetryInterval
    }

    private func reopenIfNeeded(_ currentDevice: IOHIDDevice) {
        let now = CACurrentMediaTime()
        guard now >= nextReopenAttemptTime else { return }
        nextReopenAttemptTime = now + Self.reopenRetryInterval

        var device = currentDevice
        if recoveryAttempts >= Self.reprobeThreshold,
           let replacement = LASDiagnostic.findStandardDevice() {
            hidDevice = replacement
            device = replacement
            recoveryAttempts = 0
        }

        isDeviceOpen = IOHIDDeviceOpen(device, Self.noOptions) == kIOReturnSuccess
        if isDeviceOpen {
            consecutiveReadFailures = 0
        } else {
            recoveryAttempts += 1
            markReadingUnavailable()
        }
    }

    private func markReadingUnavailable() {
        isReporting = false
        reportingMirror = false
        velocity = 0
        velocityMirror = 0
        statusMessage = String(localized: "The lid angle sensor stopped responding. Reconnecting…")
    }

    private func updateVelocity(from rawAngle: Double) {
        let now = CACurrentMediaTime()

        guard !isFirstUpdate else {
            lastAngle = rawAngle
            smoothedAngle = rawAngle
            lastUpdateTime = now
            lastMovementTime = now
            isFirstUpdate = false
            return
        }

        let dt = now - lastUpdateTime
        guard dt > 0, dt < 1.0 else {
            lastUpdateTime = now
            return
        }

        smoothedAngle = Self.angleSmoothingFactor * rawAngle + (1 - Self.angleSmoothingFactor) * smoothedAngle

        let delta = smoothedAngle - lastAngle
        let instantVelocity: Double
        if abs(delta) < Self.movementThreshold {
            instantVelocity = 0
        } else {
            instantVelocity = abs(delta / dt)
            lastAngle = smoothedAngle
        }

        if instantVelocity > 0 {
            smoothedVelocity = Self.velocitySmoothingFactor * instantVelocity + (1 - Self.velocitySmoothingFactor) * smoothedVelocity
            lastMovementTime = now
        } else {
            smoothedVelocity *= Self.velocityDecay
        }

        if now - lastMovementTime > Self.movementTimeout {
            smoothedVelocity *= Self.additionalDecay
        }

        lastUpdateTime = now
        if smoothedVelocity < 0.01 { smoothedVelocity = 0 }
        if velocityMirror != smoothedVelocity {
            velocityMirror = smoothedVelocity
            velocity = smoothedVelocity
        }
    }
}