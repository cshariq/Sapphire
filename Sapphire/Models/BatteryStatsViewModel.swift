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
    private struct Snapshot: Equatable {
        var batteryLevel = 0
        var isCharging = false
        var timeRemaining = "--"
        var temperature: Double = 0
        var systemPower: Double = 0
        var adapterPower: Double = 0
        var powerConsumption: Double = 0
        var amperage = 0
        var voltage: Double = 0
        var lowPowerModeEnabled = false
        var designCapacity = 0
        var maxCapacity = 0
        var appleMaxCapacity = 0
        var cycleCount = 0
        var health = "Unknown"
        var powerAdapterInfo: PowerAdapterInfo?
    }

    @Published private var snapshot = Snapshot()

    var batteryLevel: Int { snapshot.batteryLevel }
    var isCharging: Bool { snapshot.isCharging }
    var timeRemaining: String { snapshot.timeRemaining }
    var temperature: Double { snapshot.temperature }
    var systemPower: Double { snapshot.systemPower }
    var adapterPower: Double { snapshot.adapterPower }
    var powerConsumption: Double { snapshot.powerConsumption }
    var amperage: Int { snapshot.amperage }
    var voltage: Double { snapshot.voltage }
    var lowPowerModeEnabled: Bool { snapshot.lowPowerModeEnabled }
    var designCapacity: Int { snapshot.designCapacity }
    var maxCapacity: Int { snapshot.maxCapacity }
    var appleMaxCapacity: Int { snapshot.appleMaxCapacity }
    var cycleCount: Int { snapshot.cycleCount }
    var health: String { snapshot.health }
    var powerAdapterInfo: PowerAdapterInfo? { snapshot.powerAdapterInfo }

    private let batteryManager = BatteryManager.shared
    private let batteryMonitor = BatteryMonitor.shared
    private let statsManager = StatsManager.shared
    private let powerModeManager = PowerModeManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var lastSlowRefresh = Date.distantPast
    private var fetchInFlight = false

    init() {}

    func start(highFrequency _: Bool = false) {
        guard !isStarted else { return }
        isStarted = true
        setupBindings()
        fetchStats()
    }

    func stop() {
        cancellables.removeAll()
        isStarted = false
    }

    private func setupBindings() {
        batteryMonitor.$currentState.compactMap { $0 }.receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateSnapshot {
                    $0.batteryLevel = state.level
                    $0.isCharging = state.isCharging
                }
            }.store(in: &cancellables)

        statsManager.$currentStats.compactMap { $0 }.receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self else { return }
                let batteryStats = payload.battery
                let isCharging = self.snapshot.isCharging
                let timeToUse = isCharging ? batteryStats?.timeToCharge : batteryStats?.timeToEmpty
                self.updateSnapshot {
                    if let power = payload.systemPower { $0.systemPower = power }
                    $0.adapterPower = payload.sensors?.sensors.first { $0.key == "PDTR" }?.value ?? 0
                    if let batteryStats {
                        $0.powerConsumption = batteryStats.powerDraw
                        $0.amperage = batteryStats.amperage
                        $0.voltage = batteryStats.voltage
                        $0.timeRemaining = self.formatTime(minutes: timeToUse)
                    }
                }
                self.fetchStats()
            }.store(in: &cancellables)

        powerModeManager.$isLowPowerModeActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.updateSnapshot { $0.lowPowerModeEnabled = enabled }
            }
            .store(in: &cancellables)
    }

    func fetchStats() {
        guard !fetchInFlight else { return }
        fetchInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { fetchInFlight = false }

            let temperature = await batteryManager.getBatteryTemperature()
            let lowPowerModeEnabled = powerModeManager.isLowPowerModeEnabled()
            self.updateSnapshot {
                $0.temperature = temperature
                $0.lowPowerModeEnabled = lowPowerModeEnabled
            }

            let now = Date()
            guard now.timeIntervalSince(lastSlowRefresh) >= 10 else { return }
            lastSlowRefresh = now

            async let designCap = batteryManager.getDesignCapacity()
            async let maxCap = batteryManager.getMaxCapacity()
            async let appleMaxCap = batteryManager.getAppleMaxCapacity()
            async let cycles = batteryManager.getCycleCount()
            async let health = batteryManager.getBatteryHealth()
            async let adapter = batteryManager.getPowerAdapterInfo()

            let values = await (designCap, maxCap, appleMaxCap, cycles, health, adapter)
            self.updateSnapshot {
                ($0.designCapacity, $0.maxCapacity, $0.appleMaxCapacity, $0.cycleCount, $0.health, $0.powerAdapterInfo) = values
            }
        }
    }

    private func updateSnapshot(_ update: (inout Snapshot) -> Void) {
        var next = snapshot
        update(&next)
        guard next != snapshot else { return }
        snapshot = next
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