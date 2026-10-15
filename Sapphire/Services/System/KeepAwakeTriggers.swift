//
//  KeepAwakeTriggers.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import AppKit
import CoreGraphics
import Foundation
import IOKit.ps

struct KeepAwakeTriggerConfiguration: Equatable {
    var whileAppsRun: Bool
    var appBundleIDs: Set<String>
    var whileOnACPower: Bool
    var whileExternalDisplay: Bool
    var pauseWhenLocked: Bool

    init(
        whileAppsRun: Bool = false,
        appBundleIDs: Set<String> = [],
        whileOnACPower: Bool = false,
        whileExternalDisplay: Bool = false,
        pauseWhenLocked: Bool = false
    ) {
        self.whileAppsRun = whileAppsRun
        self.appBundleIDs = appBundleIDs
        self.whileOnACPower = whileOnACPower
        self.whileExternalDisplay = whileExternalDisplay
        self.pauseWhenLocked = pauseWhenLocked
    }

    init(_ settings: Settings) {
        self.init(
            whileAppsRun: settings.caffeinateWhileAppsRun,
            appBundleIDs: Set(settings.caffeinateTriggerAppBundleIDs),
            whileOnACPower: settings.caffeinateWhileOnACPower,
            whileExternalDisplay: settings.caffeinateWhileExternalDisplay,
            pauseWhenLocked: settings.caffeinatePauseTriggersWhenLocked
        )
    }

    var watchesApps: Bool { whileAppsRun && !appBundleIDs.isEmpty }
    var hasAnyTrigger: Bool { watchesApps || whileOnACPower || whileExternalDisplay }
    var watchesLock: Bool { hasAnyTrigger && pauseWhenLocked }
}

struct KeepAwakeTriggerState: Equatable {
    var watchedAppRunning = false
    var onACPower = false
    var externalDisplayConnected = false
    var screenLocked = false
}

enum KeepAwakeTriggerEvaluator {
    static func shouldKeepAwake(_ configuration: KeepAwakeTriggerConfiguration, _ state: KeepAwakeTriggerState) -> Bool {
        guard configuration.hasAnyTrigger else { return false }
        if configuration.pauseWhenLocked && state.screenLocked { return false }
        return (configuration.watchesApps && state.watchedAppRunning)
            || (configuration.whileOnACPower && state.onACPower)
            || (configuration.whileExternalDisplay && state.externalDisplayConnected)
    }

    static func hasExternalDisplay(_ displays: [(isBuiltIn: Bool, isVirtual: Bool)]) -> Bool {
        displays.contains { !$0.isBuiltIn && !$0.isVirtual }
    }
}

@MainActor
final class KeepAwakeTriggerMonitor {
    private(set) var configuration = KeepAwakeTriggerConfiguration()
    private(set) var state = KeepAwakeTriggerState()
    private(set) var shouldKeepAwake = false

    private let onChange: (Bool) -> Void

    private var appObservers: [NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?
    private var displayObserver: NSObjectProtocol?
    private var displayWorkItem: DispatchWorkItem?
    private var lockObservers: [NSObjectProtocol] = []

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func update(_ configuration: KeepAwakeTriggerConfiguration) {
        let previous = self.configuration
        self.configuration = configuration

        if configuration.watchesApps {
            if !previous.watchesApps || previous.appBundleIDs != configuration.appBundleIDs {
                installAppWatching()
            }
        } else {
            removeAppWatching()
        }

        if configuration.whileOnACPower { installPowerWatching() } else { removePowerWatching() }
        if configuration.whileExternalDisplay { installDisplayWatching() } else { removeDisplayWatching() }
        if configuration.watchesLock { installLockWatching() } else { removeLockWatching() }

        evaluate()
    }

    func stop() {
        update(KeepAwakeTriggerConfiguration())
    }

    private func evaluate() {
        let decision = KeepAwakeTriggerEvaluator.shouldKeepAwake(configuration, state)
        guard decision != shouldKeepAwake else { return }
        shouldKeepAwake = decision
        onChange(decision)
    }

    // MARK: - Apps

    private func installAppWatching() {
        removeAppWatching()
        state.watchedAppRunning = isAnyWatchedAppRunning(excluding: nil)

        let center = NSWorkspace.shared.notificationCenter
        appObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let bundleID = app?.bundleIdentifier,
                      self.configuration.appBundleIDs.contains(bundleID) else { return }
                self.state.watchedAppRunning = true
                self.evaluate()
            }
        })
        appObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, let bundleID = app.bundleIdentifier,
                      self.configuration.appBundleIDs.contains(bundleID) else { return }
                self.state.watchedAppRunning = self.isAnyWatchedAppRunning(excluding: app)
                self.evaluate()
            }
        })
    }

    private func removeAppWatching() {
        let center = NSWorkspace.shared.notificationCenter
        appObservers.forEach { center.removeObserver($0) }
        appObservers.removeAll()
        state.watchedAppRunning = false
    }

    private func isAnyWatchedAppRunning(excluding terminated: NSRunningApplication?) -> Bool {
        configuration.appBundleIDs.contains { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains { $0 !== terminated }
        }
    }

    // MARK: - Power

    private func installPowerWatching() {
        guard powerSource == nil else { return }
        state.onACPower = Self.isOnACPower()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<KeepAwakeTriggerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerSourceChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    private func removePowerWatching() {
        if let powerSource {
            CFRunLoopSourceInvalidate(powerSource)
            self.powerSource = nil
        }
        state.onACPower = false
    }

    private func powerSourceChanged() {
        guard powerSource != nil else { return }
        state.onACPower = Self.isOnACPower()
        evaluate()
    }

    private static func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return true
        }
        return (type as String) == kIOPMACPowerKey
    }

    // MARK: - Displays

    private func installDisplayWatching() {
        guard displayObserver == nil else { return }
        state.externalDisplayConnected = Self.isExternalDisplayConnected()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDisplayCheck() }
        }
    }

    private func removeDisplayWatching() {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
        displayWorkItem?.cancel()
        displayWorkItem = nil
        state.externalDisplayConnected = false
    }

    private func scheduleDisplayCheck() {
        displayWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.displayObserver != nil else { return }
                self.displayWorkItem = nil
                self.state.externalDisplayConnected = Self.isExternalDisplayConnected()
                self.evaluate()
            }
        }
        displayWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: item)
    }

    private static func isExternalDisplayConnected() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return false }
        let displays = ids.prefix(Int(count)).map { id in
            (isBuiltIn: CGDisplayIsBuiltin(id) != 0, isVirtual: DisplayManager.isVirtual(displayID: id))
        }
        return KeepAwakeTriggerEvaluator.hasExternalDisplay(displays)
    }

    // MARK: - Lock

    private func installLockWatching() {
        guard lockObservers.isEmpty else { return }
        state.screenLocked = Self.isScreenLocked()
        let center = DistributedNotificationCenter.default()
        lockObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.screenLocked = true
                self?.evaluate()
            }
        })
        lockObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.screenLocked = false
                self?.evaluate()
            }
        })
    }

    private func removeLockWatching() {
        let center = DistributedNotificationCenter.default()
        lockObservers.forEach { center.removeObserver($0) }
        lockObservers.removeAll()
        state.screenLocked = false
    }

    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}