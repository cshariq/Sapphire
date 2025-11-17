//
//  BatteryStatsViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class BatteryStatsViewModel: ObservableObject {
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var timeRemaining: String = "--"
    @Published var temperature: Double = 0
    @Published var powerConsumption: Double = 0
    @Published var amperage: Int = 0
    @Published var voltage: Double = 0
    @Published var lowPowerModeEnabled: Bool = false

    @Published var designCapacity: Int = 0
    @Published var maxCapacity: Int = 0
    @Published var appleMaxCapacity: Int = 0
    @Published var cycleCount: Int = 0
    @Published var health: String = "Unknown"

    @Published var powerAdapterInfo: PowerAdapterInfo?

    private let batteryManager = BatteryManager.shared
    private let batteryMonitor = BatteryMonitor.shared
    private let statsManager = StatsManager.shared
    private let powerModeManager = PowerModeManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    init() {
        setupBindings()
        fetchStats()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.fetchStats()
        }
    }

    deinit { refreshTimer?.invalidate() }

    private func setupBindings() {
        batteryMonitor.$currentState.compactMap { $0 }.receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.batteryLevel = state.level
                self?.isCharging = state.isCharging
            }.store(in: &cancellables)

        statsManager.$currentStats.compactMap { $0?.battery }.receive(on: DispatchQueue.main)
            .sink { [weak self] batteryStats in
                self?.powerConsumption = batteryStats.powerDraw
                self?.amperage = batteryStats.amperage
                self?.voltage = batteryStats.voltage
                let timeToUse = self?.isCharging == true ? batteryStats.timeToCharge : batteryStats.timeToEmpty
                self?.timeRemaining = self?.formatTime(minutes: timeToUse) ?? "--"
            }.store(in: &cancellables)
    }

    func fetchStats() {
        Task {
            async let designCap = batteryManager.getDesignCapacity()
            async let maxCap = batteryManager.getMaxCapacity()
            async let appleMaxCap = batteryManager.getAppleMaxCapacity()
            async let cycles = batteryManager.getCycleCount()
            async let health = batteryManager.getBatteryHealth()
            async let temp = batteryManager.getBatteryTemperature()
            async let adapter = batteryManager.getPowerAdapterInfo()

            (self.designCapacity, self.maxCapacity, self.appleMaxCapacity, self.cycleCount, self.health, self.temperature, self.powerAdapterInfo) = await (designCap, maxCap, appleMaxCap, cycles, health, temp, adapter)

            self.lowPowerModeEnabled = powerModeManager.isLowPowerModeEnabled()
        }
    }

    private func formatTime(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "--" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    var maxCapacityPercentage: Int {
        guard designCapacity > 0 else { return 100 }
        return min(Int((Double(maxCapacity) / Double(designCapacity)) * 100), 100)
    }

    var appleMaxCapacityPercentage: Int {
        guard designCapacity > 0 else { return 100 }
        return min(Int((Double(appleMaxCapacity) / Double(designCapacity)) * 100), 100)
    }
}