//
//  MenuBarReadoutsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-04
//

import AppKit
import Combine
import Darwin
import Foundation

private struct MenuBarReadoutsConfiguration: Equatable {
    let isEnabled: Bool
    let showCPU: Bool
    let showMemory: Bool
    let showNetwork: Bool

    init(_ settings: Settings) {
        isEnabled = settings.monitoringMenuBarReadoutsEnabled
        showCPU = settings.monitoringReadoutShowCPU
        showMemory = settings.monitoringReadoutShowMemory
        showNetwork = settings.monitoringReadoutShowNetwork
    }
}

@MainActor
final class MenuBarReadoutsManager {
    static let shared = MenuBarReadoutsManager()

    private var settingsCancellables = Set<AnyCancellable>()
    private var isStarted = false

    private var statusItem: NSStatusItem?
    private var statsCancellable: AnyCancellable?
    private var networkTimer: Timer?

    private var lastNetworkSample: (received: UInt64, sent: UInt64, date: Date)?

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        SettingsModel.shared.changes(of: MenuBarReadoutsConfiguration.init)
            .sink { [weak self] configuration in
                self?.apply(configuration)
            }
            .store(in: &settingsCancellables)

        apply(MenuBarReadoutsConfiguration(SettingsModel.shared.settings))
    }

    private func apply(_ configuration: MenuBarReadoutsConfiguration) {
        guard configuration.isEnabled else {
            removeStatusItem()
            return
        }

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        var requiredStats = Set<StatType>()
        if configuration.showCPU { requiredStats.insert(.cpu) }
        if configuration.showMemory { requiredStats.insert(.ram) }
        StatsManager.shared.setPolling(for: "MenuBarReadouts", requiredStats: requiredStats)

        statsCancellable = nil
        if !requiredStats.isEmpty {
            statsCancellable = StatsManager.shared.$currentStats
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateReadout() }
        }

        networkTimer?.invalidate()
        networkTimer = nil
        lastNetworkSample = nil
        if configuration.showNetwork, requiredStats.isEmpty {
            networkTimer = Timer.scheduledCoalescing(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.updateReadout()
            }
        }
        updateReadout()
    }

    func removeStatusItem() {
        StatsManager.shared.setPolling(for: "MenuBarReadouts", requiredStats: [])
        statsCancellable = nil
        networkTimer?.invalidate()
        networkTimer = nil
        lastNetworkSample = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func updateReadout() {
        let settings = SettingsModel.shared.settings
        guard settings.monitoringMenuBarReadoutsEnabled else { return }

        var parts: [String] = []
        let stats = StatsManager.shared.currentStats
        if settings.monitoringReadoutShowCPU, let cpu = stats?.cpu?.totalUsage {
            parts.append("CPU \(Int((cpu * 100).rounded()))%")
        }
        if settings.monitoringReadoutShowMemory, let memory = stats?.ram {
            let gigabyte = 1024.0 * 1024.0 * 1024.0
            parts.append(String(
                format: "RAM %.1f / %.0f GB",
                memory.used / gigabyte,
                memory.total / gigabyte
            ))
        }
        if settings.monitoringReadoutShowNetwork {
            let rates = networkRates()
            if rates.down > 0 || rates.up > 0 {
                parts.append("↓\(Self.formatRate(rates.down)) ↑\(Self.formatRate(rates.up))")
            }
        }

        guard let button = statusItem?.button else { return }
        if parts.isEmpty {
            button.title = ""
        } else {
            button.title = parts.joined(separator: "  ")
        }
        button.toolTip = "Sapphire readouts — CPU, RAM, network rates"
    }

    private static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        }
        if bytesPerSecond >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    // MARK: - Samplers

    private func networkRates() -> (down: Double, up: Double) {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let interfaceList else {
            return (0, 0)
        }
        defer { freeifaddrs(interfaceList) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = interfaceList
        while let ifa = pointer {
            defer { pointer = ifa.pointee.ifa_next }
            let flags = Int32(ifa.pointee.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0,
                  (flags & IFF_UP) != 0,
                  ifa.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }
            if let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
        }

        let now = Date()
        if let previous = lastNetworkSample {
            let elapsed = now.timeIntervalSince(previous.date)
            let down = elapsed > 0 ? Double(received - min(received, previous.received)) / elapsed : 0
            let up = elapsed > 0 ? Double(sent - min(sent, previous.sent)) / elapsed : 0
            lastNetworkSample = (received, sent, now)
            return (max(0, down), max(0, up))
        }
        lastNetworkSample = (received, sent, now)
        return (0, 0)
    }
}