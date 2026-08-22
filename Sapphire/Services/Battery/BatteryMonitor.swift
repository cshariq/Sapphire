//
//  BatteryMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-03.
//

import Foundation
import IOKit.ps
import AppKit

@MainActor
class BatteryMonitor: ObservableObject {
    @Published var currentState: BatteryState?

    static let shared = BatteryMonitor()
    private var runLoopSource: CFRunLoopSource?

    private var lastLoggedLevel: Int?
    private var lastPeriodicLogTime: Date = .distantPast
    private let periodicLogInterval: TimeInterval = 300
    private var periodicLogTimer: Timer?
    private var sleepObservers: [NSObjectProtocol] = []

    private init() {
        setupBatteryChangeNotification()
        setupSleepWakeObservers()
        updateBatteryState()
        startPeriodicLogging()
    }

    private func startPeriodicLogging() {
        periodicLogTimer?.invalidate()
        periodicLogTimer = Timer.scheduledTimer(withTimeInterval: periodicLogInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.logPeriodicSnapshot()
            }
        }
        if let periodicLogTimer {
            RunLoop.main.add(periodicLogTimer, forMode: .common)
        }
    }

    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.updateBatteryState()
                    self?.forceLogSnapshot()
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.updateBatteryState()
                    self?.forceLogSnapshot()
                }
            }
        ]
    }

    private func logPeriodicSnapshot() {
        let now = Date()
        guard now.timeIntervalSince(lastPeriodicLogTime) >= periodicLogInterval - 1 else { return }
        lastPeriodicLogTime = now
        BatteryDataLogger.shared.logCurrentState()
    }

    private func forceLogSnapshot() {
        lastPeriodicLogTime = Date()
        BatteryDataLogger.shared.logCurrentState()
    }

    deinit {
        periodicLogTimer?.invalidate()
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func setupBatteryChangeNotification() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let unsafeSelf = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()

            Task { @MainActor in
                unsafeSelf.updateBatteryState()
            }
        }

        let context = Unmanaged.passRetained(self).toOpaque()

        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.runLoopSource = source
        } else {
            print("[BatteryMonitor] ERROR: Failed to create run loop source.")
        }
    }

    private func updateBatteryState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let powerSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, powerSource)?.takeUnretainedValue() as? [String: AnyObject] else {
            print("[BatteryMonitor WARNING] Could not get power source info.")
            return
        }

        let level = info[kIOPSCurrentCapacityKey] as? Int ?? -1
        let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
        let sourceState = info[kIOPSPowerSourceStateKey] as? String ?? ""

        let newState = BatteryState(
            level: level,
            isCharging: isCharging,
            isPluggedIn: sourceState == kIOPSACPowerValue
        )

        if newState != self.currentState {
            self.currentState = newState
        }

        if level != self.lastLoggedLevel {
            self.lastLoggedLevel = level

            BatteryDataLogger.shared.logCurrentState()
        }
    }
}