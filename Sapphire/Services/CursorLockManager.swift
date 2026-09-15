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

    private struct Configuration: Equatable {
        let enabled: Bool
        let allowedAppStates: [String: Bool]
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "CursorLock")

    private let lock = NSRecursiveLock()

    private var settingEnabled = false
    private var allowedAppStates: [String: Bool] = [:]
    private var lockEnabled: Bool = false
    private var lockedY: CGFloat = 0
    private var lastX: CGFloat = 0
    private var reentry: Bool = false
    private var lastCapsOn: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private var currentActiveAppBundleID: String?

    var sensitivity: CGFloat = 1.0

    private var mouseTapToken: GlobalEventTap.Token?
    private var capsTapToken: GlobalEventTap.Token?

    private init() {
        MainActor.assumeIsolated {
            registerTrustAwareness()
            SettingsModel.shared.$settings
                .map {
                    Configuration(
                        enabled: $0.capsLockHorizontalLockEnabled,
                        allowedAppStates: $0.capsLockHorizontalLockAppStates
                    )
                }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] configuration in self?.apply(configuration) }
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

    private func apply(_ configuration: Configuration) {
        lock.lock()
        settingEnabled = configuration.enabled
        allowedAppStates = configuration.allowedAppStates
        lock.unlock()

        if configuration.enabled {
            installTaps()
        } else {
            teardownTaps()
        }
    }

    @MainActor
    private func registerTrustAwareness() {
        AccessibilityTrustMonitor.shared.register(name: "CursorLock") { [weak self] in
            self?.teardownTaps()
        } reinstall: { [weak self] in
            self?.installTaps()
        }
    }

    private func installTaps() {
        lock.lock()
        let enabled = settingEnabled
        lock.unlock()
        guard enabled else { return }

        let initialCapsOn = NSEvent.modifierFlags.contains(.capsLock)
        updateLockState(capsOn: initialCapsOn)

        installCapsTap()
        installMouseTap()
    }

    private func installCapsTap() {
        lock.lock()
        defer { lock.unlock() }
        guard capsTapToken == nil else { return }

        let capsFlagsMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        capsTapToken = GlobalEventTap.shared.register(
            name: "CursorLock.caps",
            mask: capsFlagsMask,
            priority: EventTapPriority.filter
        ) { [weak self] type, event in
            guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
                return .pass
            }
            guard type == .flagsChanged, let self else { return .pass }
            let capsOn = event.flags.contains(.maskAlphaShift)
            let currentY = event.location.y
            self.updateLockState(capsOn: capsOn, currentY: currentY)
            return .pass
        }
    }

    private func installMouseTap() {
        lock.lock()
        defer { lock.unlock() }
        guard mouseTapToken == nil else { return }

        let eventMask = CGEventMask(
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )

        mouseTapToken = GlobalEventTap.shared.register(
            name: "CursorLock.mouse",
            mask: eventMask,
            priority: EventTapPriority.filter,
            enabled: lockEnabled
        ) { [weak self] type, event in
            guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
                return .pass
            }
            return self?.processMouseEvent(event, type: type) ?? .pass
        }
    }

    private func processMouseEvent(_ event: CGEvent, type: CGEventType) -> EventTapDecision {
        lock.lock()
        defer { lock.unlock() }

        guard lockEnabled else {
            return .pass
        }

        if type == .scrollWheel {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0.0)
            return .pass
        }

        if reentry {
            reentry = false
            return .pass
        }

        var dx = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
        if dx == 0 {
            dx = event.location.x - lastX
        }

        lastX += dx * sensitivity
        reentry = true

        warpCursorWithoutSuppression(to: CGPoint(x: lastX, y: lockedY))
        return .swallow
    }

    private func teardownTaps() {
        lock.lock()
        defer { lock.unlock() }

        if let mouseTapToken {
            GlobalEventTap.shared.unregister(mouseTapToken)
        }
        mouseTapToken = nil

        if let capsTapToken {
            GlobalEventTap.shared.unregister(capsTapToken)
        }
        capsTapToken = nil

        lockEnabled = false
        reentry = false
    }

    private func isActiveAppAllowed() -> Bool {
        guard let bundleID = currentActiveAppBundleID else { return true }
        return allowedAppStates[bundleID, default: true]
    }

    private func warpCursorWithoutSuppression(to target: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let defaultInterval = source?.localEventsSuppressionInterval ?? 0.25

        source?.localEventsSuppressionInterval = 0.0
        CGWarpMouseCursorPosition(target)
        source?.localEventsSuppressionInterval = defaultInterval

        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    fileprivate func updateLockState(capsOn: Bool, currentY: CGFloat? = nil) {
        lock.lock()
        defer { lock.unlock() }
        lastCapsOn = capsOn
        let newLockEnabled = capsOn && settingEnabled && isActiveAppAllowed()

        if newLockEnabled != self.lockEnabled {
            self.lockEnabled = newLockEnabled
            if let token = mouseTapToken {
                DispatchQueue.main.async {
                    GlobalEventTap.shared.setEnabled(token, newLockEnabled)
                }
            }
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
                logger.debug("CapsLock horizontal lock enabled at Y: \(self.lockedY, privacy: .public)")
            } else {
                if let source = CGEventSource(stateID: .hidSystemState) {
                    source.localEventsSuppressionInterval = 0.25
                }
                reentry = false
                logger.debug("CapsLock horizontal lock disabled")
            }
        }
    }

    func applyLockIfNeeded(to event: NSEvent) {
        lock.lock()
        let enabled = lockEnabled
        let targetY = lockedY
        lock.unlock()
        guard enabled else { return }
        guard let currentLoc = CGEvent(source: nil)?.location else { return }
        guard currentLoc.y != targetY else { return }
        let target = CGPoint(x: currentLoc.x, y: targetY)

        warpCursorWithoutSuppression(to: target)
    }

    deinit {
        teardownTaps()
    }
}