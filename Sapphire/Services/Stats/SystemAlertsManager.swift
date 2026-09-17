//
//  SystemAlertsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-04
//

import AppKit
import Combine
import UserNotifications

private struct SystemAlertsConfiguration: Equatable {
    let isEnabled: Bool
    let sustainedCPUEnabled: Bool
    let cpuThreshold: Double
    let memoryPressureEnabled: Bool
    let lowDiskEnabled: Bool
    let diskThresholdGB: Double

    init(_ settings: Settings) {
        isEnabled = settings.monitoringAlertsEnabled
        sustainedCPUEnabled = settings.monitoringAlertSustainedCPUEnabled
        cpuThreshold = settings.monitoringAlertCPUThreshold
        memoryPressureEnabled = settings.monitoringAlertMemoryPressureEnabled
        lowDiskEnabled = settings.monitoringAlertLowDiskEnabled
        diskThresholdGB = settings.monitoringAlertDiskThresholdGB
    }
}

@MainActor
final class SystemAlertsManager {
    static let shared = SystemAlertsManager()

    private var settingsCancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var statsCancellable: AnyCancellable?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var diskCheckTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    private var cpuHistory: [(date: Date, usage: Double)] = []

    private var lastCPUAlert = Date.distantPast
    private var lastPressureAlert = Date.distantPast
    private var lastDiskAlert = Date.distantPast

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        SettingsModel.shared.changes(of: SystemAlertsConfiguration.init)
            .sink { [weak self] configuration in
                self?.apply(configuration)
            }
            .store(in: &settingsCancellables)

        apply(SystemAlertsConfiguration(SettingsModel.shared.settings))
    }

    private func apply(_ configuration: SystemAlertsConfiguration) {
        stopMonitoring()
        guard configuration.isEnabled else { return }

        if configuration.sustainedCPUEnabled {
            StatsManager.shared.setPolling(for: "SystemAlerts", requiredStats: [.cpu])
            statsCancellable = StatsManager.shared.$currentStats
                .compactMap { $0?.cpu?.totalUsage }
                .receive(on: RunLoop.main)
                .sink { [weak self] usage in
                    self?.sampleCPU(usage: usage, threshold: configuration.cpuThreshold)
                }
        }

        if configuration.memoryPressureEnabled {
            startMemoryPressureMonitoring()
        }

        if configuration.lowDiskEnabled {
            sampleDiskSpace(thresholdGB: configuration.diskThresholdGB)
            diskCheckTimer = Timer.scheduledCoalescing(
                withTimeInterval: 15 * 60,
                repeats: true,
                toleranceFraction: 0.25
            ) { [weak self] _ in
                self?.sampleDiskSpace(thresholdGB: SettingsModel.shared.settings.monitoringAlertDiskThresholdGB)
            }

            let center = NSWorkspace.shared.notificationCenter
            workspaceObservers = [
                NSWorkspace.didWakeNotification,
                NSWorkspace.didMountNotification,
                NSWorkspace.didUnmountNotification,
            ].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.sampleDiskSpace(thresholdGB: SettingsModel.shared.settings.monitoringAlertDiskThresholdGB)
                    }
                }
            }
        }
    }

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pressure = self.memoryPressureSource?.data else { return }
                guard Date().timeIntervalSince(self.lastPressureAlert) > 1800 else { return }
                self.lastPressureAlert = Date()
                if pressure.contains(.critical) {
                    self.postAlert(title: "Memory Pressure", body: "Memory pressure is critical — consider closing some apps.")
                } else {
                    self.postAlert(title: "Memory Pressure", body: "Memory pressure is high — consider closing some apps.")
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func stopMonitoring() {
        StatsManager.shared.setPolling(for: "SystemAlerts", requiredStats: [])
        statsCancellable = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        diskCheckTimer?.invalidate()
        diskCheckTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        cpuHistory.removeAll()
    }

    // MARK: - CPU

    private func sampleCPU(usage: Double, threshold: Double) {
        let now = Date()
        guard usage * 100 >= threshold else {
            cpuHistory.removeAll()
            return
        }
        cpuHistory.append((now, usage))
        cpuHistory.removeAll { now.timeIntervalSince($0.date) > 60 }

        guard let first = cpuHistory.first,
              now.timeIntervalSince(first.date) >= 45,
              now.timeIntervalSince(lastCPUAlert) > 600 else { return }
        let average = cpuHistory.map(\.usage).reduce(0, +) / Double(cpuHistory.count)
        lastCPUAlert = Date()
        cpuHistory.removeAll()
        postAlert(
            title: "High CPU Load",
            body: "CPU has been at \(Int((average * 100).rounded()))% for about a minute."
        )
    }

    // MARK: - Disk space

    private func sampleDiskSpace(thresholdGB: Double) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return }

        let freeGB = Double(free) / (1024 * 1024 * 1024)
        guard freeGB < thresholdGB,
              Date().timeIntervalSince(lastDiskAlert) > 3600 else { return }
        lastDiskAlert = Date()
        postAlert(
            title: "Low Disk Space",
            body: "Only \(String(format: "%.1f", freeGB)) GB free on your startup disk."
        )
    }

    // MARK: - Notification delivery

    private func postAlert(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "com.sapphire.monitoring.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}