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

    private static let networkInterval: TimeInterval = 1
    private static let networkMaximumGap: TimeInterval = 3

    private var settingsCancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var configuration: MenuBarReadoutsConfiguration?

    private var statusItem: NSStatusItem?
    private var statsCancellable: AnyCancellable?
    private var networkTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private var lastNetworkSample: NetworkRateMath.Sample?
    private var lastInterfaceCounters: [Int: (received: UInt64, sent: UInt64)]?
    private var accumulatedReceived: UInt64 = 0
    private var accumulatedSent: UInt64 = 0
    private var networkText: String?

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
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        guard configuration.isEnabled, configuration.showCPU || configuration.showMemory || configuration.showNetwork else {
            removeStatusItem()
            self.configuration = configuration
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.isVisible = false
            statusItem = item
        }

        var requiredStats = Set<StatType>()
        if configuration.showCPU { requiredStats.insert(.cpu) }
        if configuration.showMemory { requiredStats.insert(.ram) }
        StatsManager.shared.setPolling(for: "MenuBarReadouts", requiredStats: requiredStats)

        if requiredStats.isEmpty {
            statsCancellable = nil
        } else if statsCancellable == nil {
            statsCancellable = StatsManager.shared.$currentStats
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateReadout() }
        }

        if configuration.showNetwork {
            startNetworkSampling()
        } else {
            stopNetworkSampling()
        }
        updateReadout()
    }

    func removeStatusItem() {
        configuration = nil
        StatsManager.shared.setPolling(for: "MenuBarReadouts", requiredStats: [])
        statsCancellable = nil
        stopNetworkSampling()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    // MARK: - Network sampling

    private func startNetworkSampling() {
        guard networkTimer == nil else { return }
        lastNetworkSample = nil
        networkText = nil
        networkTimer = Timer.scheduledCoalescing(withTimeInterval: Self.networkInterval, repeats: true, toleranceFraction: 0.2) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleNetwork() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lastNetworkSample = nil }
        }
        sampleNetwork()
    }

    private func stopNetworkSampling() {
        networkTimer?.invalidate()
        networkTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        lastNetworkSample = nil
        lastInterfaceCounters = nil
        networkText = nil
    }

    private func sampleNetwork() {
        guard let counters = Self.interfaceByteCounters() else { return }
        if let previous = lastInterfaceCounters {
            for (index, now) in counters {
                guard let before = previous[index],
                      now.received >= before.received,
                      now.sent >= before.sent else { continue }
                accumulatedReceived &+= now.received - before.received
                accumulatedSent &+= now.sent - before.sent
            }
        }
        lastInterfaceCounters = counters
        let sample = NetworkRateMath.Sample(
            received: accumulatedReceived,
            sent: accumulatedSent,
            uptime: ProcessInfo.processInfo.systemUptime
        )
        let rates = NetworkRateMath.rates(from: lastNetworkSample, to: sample, maximumGap: Self.networkMaximumGap)
        lastNetworkSample = sample
        guard let rates else { return }
        let text = "↓\(Self.formatRate(rates.down)) ↑\(Self.formatRate(rates.up))"
        guard text != networkText else { return }
        networkText = text
        updateReadout()
    }

    // MARK: - Rendering

    private func updateReadout() {
        guard let configuration, configuration.isEnabled, let statusItem else { return }

        var parts: [String] = []
        let stats = StatsManager.shared.currentStats
        if configuration.showCPU, let cpu = stats?.cpu?.totalUsage {
            parts.append("CPU \(Self.leftPadded("\(Int((cpu * 100).rounded()))", to: 3))%")
        }
        if configuration.showMemory, let memory = stats?.ram, memory.total > 0 {
            let gigabyte = 1024.0 * 1024.0 * 1024.0
            let used = Self.leftPadded(String(format: "%.1f", memory.used / gigabyte), to: 4)
            parts.append("RAM \(used) / \(String(format: "%.0f", memory.total / gigabyte)) GB")
        }
        if configuration.showNetwork, let networkText {
            parts.append(networkText)
        }

        let title = parts.joined(separator: "  ")
        let shouldShow = !title.isEmpty
        if statusItem.isVisible != shouldShow { statusItem.isVisible = shouldShow }
        guard shouldShow, let button = statusItem.button else { return }
        if button.attributedTitle.string != title {
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: Self.readoutFont])
        }
        let toolTip = "Sapphire readouts — CPU, RAM, network rates"
        if button.toolTip != toolTip { button.toolTip = toolTip }
    }

    private static let readoutFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    private static let figureSpace = "\u{2007}"

    private static func leftPadded(_ text: String, to width: Int) -> String {
        let missing = width - text.count
        guard missing > 0 else { return text }
        return String(repeating: figureSpace, count: missing) + text
    }

    private static func formatRate(_ bytesPerSecond: Double) -> String {
        let value: String
        let unit: String
        if bytesPerSecond >= 1024 * 1024 {
            value = String(format: "%.1f", bytesPerSecond / (1024 * 1024))
            unit = "MB/s"
        } else if bytesPerSecond >= 1024 {
            value = String(format: "%.0f", bytesPerSecond / 1024)
            unit = "KB/s"
        } else {
            value = String(format: "%.0f", bytesPerSecond)
            unit = "B/s"
        }
        return "\(leftPadded(value, to: 5)) \(leftPadded(unit, to: 4))"
    }

    // MARK: - Interface counters

    private static let excludedInterfacePrefixes = [
        "lo", "gif", "stf", "awdl", "llw", "nan", "utun", "bridge",
        "ap", "anpi", "p2p", "XHC", "vmenet", "tap", "tun",
    ]

    private static func includesInterface(index: UInt16) -> Bool {
        var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        guard if_indextoname(UInt32(index), &nameBuffer) != nil else { return false }
        let name = String(cString: nameBuffer)
        guard !name.isEmpty else { return false }
        return !excludedInterfacePrefixes.contains { name.hasPrefix($0) }
    }

    private static func interfaceByteCounters() -> [Int: (received: UInt64, sent: UInt64)]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        length += 512
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var counters: [Int: (received: UInt64, sent: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let header = base.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   messageLength >= MemoryLayout<if_msghdr2>.size {
                    let message = base.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = Int32(message.ifm_flags)
                    if (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0,
                       includesInterface(index: message.ifm_index) {
                        counters[Int(message.ifm_index)] = (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
        }
        return counters
    }
}