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
            return "Sensor detected and ready."
        case .foundVendorSpecific:
            return "Sensor hardware exists, but only a vendor-specific HID interface was found."
        case .notFound:
            return "No lid angle sensor was detected on this Mac."
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
        if let device = findHIDDevice(usagePage: 0x0020, usage: 0x008A) {
            return .foundStandard(device: device)
        }

        if deviceExistsWithProductID(0x8104) {
            return .foundVendorSpecific
        }

        return .notFound
    }

    private static func findHIDDevice(usagePage: Int, usage: Int) -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            "UsagePage": usagePage,
            "Usage": usage,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }

        for device in devices {
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
        case settingsPreview
    }

    static let shared = LidAngleSensor()

    @Published private(set) var angle = 120.0
    @Published private(set) var velocity = 0.0
    @Published private(set) var isAvailable = false
    @Published private(set) var tick: UInt = 0
    @Published private(set) var statusMessage = "Sensor not available"

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

    private static let angleSmoothingFactor = 0.05
    private static let velocitySmoothingFactor = 0.3
    private static let movementThreshold = 0.5
    private static let movementTimeout: TimeInterval = 0.05
    private static let velocityDecay = 0.5
    private static let additionalDecay = 0.8
    private static let pollInterval: TimeInterval = 1.0
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

    func acquire(_ client: Client) {
        let inserted = activeClients.insert(client).inserted
        guard inserted else { return }
        startIfNeeded()
    }

    func release(_ client: Client) {
        let removed = activeClients.remove(client) != nil
        guard removed else { return }
        if activeClients.isEmpty {
            stop()
        }
    }

    private func startIfNeeded() {
        guard isAvailable, timer == nil, let hidDevice else { return }
        guard IOHIDDeviceOpen(hidDevice, Self.noOptions) == kIOReturnSuccess else { return }

        isDeviceOpen = true
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        timer.tolerance = 0.2
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if isDeviceOpen, let hidDevice {
            IOHIDDeviceClose(hidDevice, Self.noOptions)
            isDeviceOpen = false
        }
    }

    private func poll() {
        guard let hidDevice else { return }

        var length = CFIndex(hidReport.count)
        let result = IOHIDDeviceGetReport(
            hidDevice,
            kIOHIDReportTypeFeature,
            1,
            &hidReport,
            &length
        )

        guard result == kIOReturnSuccess, length >= 3 else { return }

        let rawValue = UInt16(hidReport[2]) << 8 | UInt16(hidReport[1])
        let rawAngle = Double(rawValue)

        updateVelocity(from: rawAngle)
        angle = rawAngle
        tick &+= 1
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
        velocity = smoothedVelocity
    }
}
