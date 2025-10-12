//
//  BatteryMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-03.
//
//
//
//
//
//

import Foundation
import IOKit.ps

@MainActor
class BatteryMonitor: ObservableObject {
    @Published var currentState: BatteryState?

    static let shared = BatteryMonitor()
    private var runLoopSource: CFRunLoopSource?

    private init() {
        print("[BatteryMonitor LOG] Initializing and setting up notifications.")
        setupBatteryChangeNotification()
        updateBatteryState()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            print("[BatteryMonitor LOG] Deinitialized and removed run loop source.")
        }
    }

    private func setupBatteryChangeNotification() {
        let callback: IOPowerSourceCallbackType = { context in
            print("[BatteryMonitor LOG] OS Power Source Callback Fired!")

            guard let context = context else {
                print("[BatteryMonitor ERROR] Callback context was nil.")
                return
            }
            let unsafeSelf = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()

            Task { @MainActor in
                unsafeSelf.updateBatteryState()
            }
        }

        let context = Unmanaged.passRetained(self).toOpaque()

        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.runLoopSource = source
            print("[BatteryMonitor LOG] Successfully attached to main run loop.")
        } else {
            print("[BatteryMonitor ERROR] Failed to create run loop source.")
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

        if newState != currentState {
            self.currentState = newState
        }
    }
}