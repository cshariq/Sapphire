//
//  CursorLockManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-07-08.
//

import AppKit
import SwiftUI
import CoreGraphics
import OSLog
import Carbon.HIToolbox
import Combine

final class CursorLockManager {
    static let shared = CursorLockManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "CursorLock")

    private var lockEnabled: Bool = false
    private var lockedY: CGFloat = 0
    private var lastX: CGFloat = 0
    private var reentry: Bool = false
    private var lastCapsOn: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private var currentActiveAppBundleID: String?

    var sensitivity: CGFloat = 1.0

    private var mouseEventTap: CFMachPort?
    private var mouseRunLoopSource: CFRunLoopSource?
    private var capsEventTap: CFMachPort?
    private var capsRunLoopSource: CFRunLoopSource?

    private init() {
        registerTrustAwareness()

        MainActor.assumeIsolated {
            SettingsModel.shared.$settings
                .map(\.capsLockHorizontalLockEnabled)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled in
                    guard let self else { return }
                    if enabled {
                        self.installTaps()
                    } else {
                        self.teardownTaps()
                    }
                }
                .store(in: &cancellables)

            ActiveAppMonitor.shared.$activeAppBundleID
                .receive(on: DispatchQueue.main)
                .sink { [weak self] bundleID in
                    self?.currentActiveAppBundleID = bundleID
                    self?.updateLockState(capsOn: self?.lastCapsOn ?? false)
                }
                .store(in: &cancellables)
            currentActiveAppBundleID = ActiveAppMonitor.shared.activeAppBundleID
        }
    }

    private func registerTrustAwareness() {
        AccessibilityTrustMonitor.shared.register(name: "CursorLock") { [weak self] in
            self?.teardownTaps()
        } reinstall: { [weak self] in
            self?.installTaps()
        }
    }

    private func installTaps() {
        guard SettingsModel.shared.settings.capsLockHorizontalLockEnabled else { return }

        let initialCapsOn = NSEvent.modifierFlags.contains(.capsLock)
        updateLockState(capsOn: initialCapsOn)

        installCapsTap()

        if lockEnabled {
            installMouseTap()
        }
    }

    private func installCapsTap() {
        guard capsEventTap == nil else { return }

        let capsFlagsMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        if let capsTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: capsFlagsMask,
                                          callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
                return Unmanaged.passUnretained(event)
            }

            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<CursorLockManager>.fromOpaque(refcon).takeUnretainedValue()
            let capsOn = event.flags.contains(.maskAlphaShift)
            let currentY = event.location.y

            manager.updateLockState(capsOn: capsOn, currentY: currentY)
            return Unmanaged.passUnretained(event)
        }, userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())) {
            self.capsEventTap = capsTap
            let capsSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, capsTap, 0)
            self.capsRunLoopSource = capsSource
            CFRunLoopAddSource(CFRunLoopGetCurrent(), capsSource, .commonModes)
            CGEvent.tapEnable(tap: capsTap, enable: true)
        }
    }

    private func installMouseTap() {
        guard mouseEventTap == nil else { return }

        let eventMask = CGEventMask(
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )

        let mouseTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                         place: .headInsertEventTap,
                                         options: .defaultTap,
                                         eventsOfInterest: eventMask,
                                         callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
                return Unmanaged.passUnretained(event)
            }

            guard let refc = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<CursorLockManager>.fromOpaque(refc).takeUnretainedValue()

            guard manager.lockEnabled else {
                return Unmanaged.passUnretained(event)
            }

            if type == .scrollWheel {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0.0)
                return Unmanaged.passUnretained(event)
            }

            if manager.reentry {
                manager.reentry = false
                return Unmanaged.passUnretained(event)
            }

            var dx = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))

            if dx == 0 {
                let currentX = event.location.x
                dx = currentX - manager.lastX
            }

            manager.lastX += dx * manager.sensitivity

            manager.reentry = true

            let target = CGPoint(x: manager.lastX, y: manager.lockedY)
            manager.warpCursorWithoutSuppression(to: target)

            return nil
        }, userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        if let mouseTap = mouseTap {
            self.mouseEventTap = mouseTap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseTap, 0)
            self.mouseRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: mouseTap, enable: true)
        }
    }

    private func teardownMouseTap() {
        if let source = mouseRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        mouseRunLoopSource = nil

        if let tap = mouseEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        mouseEventTap = nil
    }

    private func teardownTaps() {
        teardownMouseTap()

        if let source = capsRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = capsEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        capsEventTap = nil
        capsRunLoopSource = nil

        lockEnabled = false
        reentry = false
    }

    private func isActiveAppAllowed() -> Bool {
        guard let bundleID = currentActiveAppBundleID else { return true }
        return SettingsModel.shared.settings.capsLockHorizontalLockAppStates[bundleID, default: true]
    }

    private func warpCursorWithoutSuppression(to target: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let defaultInterval = source?.localEventsSuppressionInterval ?? 0.25

        source?.localEventsSuppressionInterval = 0.0
        CGWarpMouseCursorPosition(target)
        source?.localEventsSuppressionInterval = defaultInterval

        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    private func updateLockState(capsOn: Bool, currentY: CGFloat? = nil) {
        lastCapsOn = capsOn
        let settingEnabled = SettingsModel.shared.settings.capsLockHorizontalLockEnabled
        let newLockEnabled = capsOn && settingEnabled && isActiveAppAllowed()

        if newLockEnabled != self.lockEnabled {
            self.lockEnabled = newLockEnabled
            if newLockEnabled {
                if let currentLoc = CGEvent(source: nil)?.location {
                    lockedY = currentLoc.y
                    lastX = currentLoc.x
                } else {
                    lockedY = currentY ?? 0
                    lastX = 0
                }
                reentry = false

                if let source = CGEventSource(stateID: .hidSystemState) {
                    source.localEventsSuppressionInterval = 0.0
                }

                warpCursorWithoutSuppression(to: CGPoint(x: lastX, y: lockedY))
                installMouseTap()
                logger.debug("CapsLock horizontal lock enabled at Y: \(self.lockedY, privacy: .public)")
            } else {
                if let source = CGEventSource(stateID: .hidSystemState) {
                    source.localEventsSuppressionInterval = 0.25
                }
                reentry = false
                teardownMouseTap()
                logger.debug("CapsLock horizontal lock disabled")
            }
        }
    }

    func applyLockIfNeeded(to event: NSEvent) {
        guard lockEnabled else { return }
        guard let currentLoc = CGEvent(source: nil)?.location else { return }
        guard currentLoc.y != lockedY else { return }
        let target = CGPoint(x: currentLoc.x, y: lockedY)

        warpCursorWithoutSuppression(to: target)
    }

    deinit {
        if let tap = mouseEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let capsTap = capsEventTap {
            CGEvent.tapEnable(tap: capsTap, enable: false)
        }
    }
}