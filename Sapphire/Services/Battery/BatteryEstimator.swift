//
//  BatteryEstimator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-14.
//

import Foundation
import Combine
import IOKit.ps

@MainActor
class BatteryEstimator: ObservableObject {
    static let shared = BatteryEstimator(batteryMonitor: BatteryMonitor.shared)

    @Published var estimatedTimeRemaining: String?
    @Published var batteryLevel: Int = 100
    @Published var isCharging: Bool = false

    private var batteryMonitor: BatteryMonitor
    private var cancellables = Set<AnyCancellable>()

    init(batteryMonitor: BatteryMonitor) {
        self.batteryMonitor = batteryMonitor

        batteryMonitor.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.update(with: state)
            }
            .store(in: &cancellables)
    }

    private func update(with state: BatteryState?) {
        guard let state = state else {
            setEstimate(nil)
            return
        }

        if batteryLevel != state.level { batteryLevel = state.level }
        if isCharging != state.isCharging { isCharging = state.isCharging }

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let powerSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, powerSource)?.takeUnretainedValue() as? [String: AnyObject] else {
            setEstimate(nil)
            return
        }

        let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int ?? 0
        let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int ?? 0
        let isCharged = info[kIOPSIsChargedKey] as? Bool ?? false

        if isCharged {
            setEstimate("Charged")
        } else if state.isCharging, timeToFull > 0 {
            setEstimate("\(formatTime(minutes: timeToFull))")
        } else if !state.isCharging, timeToEmpty > 0 {
            setEstimate("\(formatTime(minutes: timeToEmpty))")
        } else {
            setEstimate("")
        }
    }

    private func setEstimate(_ value: String?) {
        if estimatedTimeRemaining != value { estimatedTimeRemaining = value }
    }

    private func formatTime(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}