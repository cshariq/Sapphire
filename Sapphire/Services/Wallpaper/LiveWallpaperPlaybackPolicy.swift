//
//  LiveWallpaperPlaybackPolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit
import IOKit.ps

@MainActor
final class LiveWallpaperPlaybackPolicy {
    enum Reason: String, CaseIterable {
        case displaysAsleep
        case systemSleeping
        case sessionInactive
        case lowPowerMode
        case onBattery
        case thermalPressure
    }

    var onChange: ((Set<Reason>) -> Void)?

    private(set) var reasons: Set<Reason> = []

    var pauseOnLowPower = false {
        didSet {
            guard pauseOnLowPower != oldValue else { return }
            refreshPowerReasons()
        }
    }

    var pauseOnBattery = false {
        didSet {
            guard pauseOnBattery != oldValue else { return }
            updateBatteryMonitoring()
            refreshPowerReasons()
        }
    }

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var isRunning = false

    var isSuspended: Bool { !reasons.isEmpty }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.set(.displaysAsleep, true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.set(.displaysAsleep, false) }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.set(.systemSleeping, true) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.set(.systemSleeping, false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.set(.sessionInactive, true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.set(.sessionInactive, false) }
        observe(.default, .NSProcessInfoPowerStateDidChange) { $0.refreshPowerReasons() }
        observe(.default, ProcessInfo.thermalStateDidChangeNotification) { $0.refreshPowerReasons() }

        updateBatteryMonitoring()
        refreshPowerReasons()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        updateBatteryMonitoring()
        commit([])
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (LiveWallpaperPlaybackPolicy) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    private func set(_ reason: Reason, _ active: Bool) {
        var next = reasons
        if active { next.insert(reason) } else { next.remove(reason) }
        commit(next)
    }

    fileprivate func refreshPowerReasons() {
        guard isRunning else { return }
        var next = reasons
        let info = ProcessInfo.processInfo
        toggle(&next, .lowPowerMode, pauseOnLowPower && info.isLowPowerModeEnabled)
        toggle(&next, .onBattery, pauseOnBattery && Self.isOnBatteryPower)
        toggle(&next, .thermalPressure, info.thermalState == .serious || info.thermalState == .critical)
        commit(next)
    }

    private func toggle(_ set: inout Set<Reason>, _ reason: Reason, _ active: Bool) {
        if active { set.insert(reason) } else { set.remove(reason) }
    }

    private func commit(_ next: Set<Reason>) {
        guard next != reasons else { return }
        reasons = next
        onChange?(next)
    }

    private func updateBatteryMonitoring() {
        let shouldMonitor = isRunning && pauseOnBattery
        if shouldMonitor, powerSourceRunLoopSource == nil {
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let policy = Unmanaged<LiveWallpaperPlaybackPolicy>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    policy.refreshPowerReasons()
                }
            }, context)?.takeRetainedValue() else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceRunLoopSource = source
        } else if !shouldMonitor, let source = powerSourceRunLoopSource {
            CFRunLoopSourceInvalidate(source)
            powerSourceRunLoopSource = nil
        }
    }

    static var isOnBatteryPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == kIOPMBatteryPowerKey
    }
}