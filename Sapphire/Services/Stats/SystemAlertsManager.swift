//
//  SystemAlertsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-04
//

import AppKit
import Combine
import UserNotifications

@MainActor
final class SystemAlertsManager {
    static let shared = SystemAlertsManager()

    private var settingsCancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var timer: Timer?

    private var cpuHistory: [Double] = []
    private let cpuSampler = AggregateCPUUsageSampler()

    private var lastCPUAlert = Date.distantPast
    private var lastPressureAlert = Date.distantPast
    private var lastDiskAlert = Date.distantPast

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        SettingsModel.shared.changes(of: \.monitoringAlertsEnabled)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.startMonitoring()
                } else {
                    self.stopMonitoring()
                }
            }
            .store(in: &settingsCancellables)

        if SettingsModel.shared.settings.monitoringAlertsEnabled {
            startMonitoring()
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        sample()
        timer = Timer.scheduledCoalescing(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        cpuHistory.removeAll()
        cpuSampler.reset()
    }

    private func sample() {
        let settings = SettingsModel.shared.settings
        guard settings.monitoringAlertsEnabled else { return }

        if settings.monitoringAlertSustainedCPUEnabled {
            sampleCPU(threshold: settings.monitoringAlertCPUThreshold)
        }
        if settings.monitoringAlertMemoryPressureEnabled {
            sampleMemoryPressure()
        }
        if settings.monitoringAlertLowDiskEnabled {
            sampleDiskSpace(thresholdGB: settings.monitoringAlertDiskThresholdGB)
        }
    }

    // MARK: - CPU

    private func sampleCPU(threshold: Double) {
        guard let usage = currentCPUUsage() else { return }
        cpuHistory.append(usage)
        if cpuHistory.count > 4 { cpuHistory.removeFirst() }

        guard cpuHistory.count == 4 else { return }
        let average = cpuHistory.reduce(0, +) / Double(cpuHistory.count)
        guard average * 100 >= threshold,
              Date().timeIntervalSince(lastCPUAlert) > 600 else { return }
        lastCPUAlert = Date()
        postAlert(
            title: "High CPU Load",
            body: "CPU has been at \(Int((average * 100).rounded()))% for about a minute."
        )
    }

    private func currentCPUUsage() -> Double? {
        cpuSampler.sample()
    }

    // MARK: - Memory pressure

    private func sampleMemoryPressure() {
        guard Date().timeIntervalSince(lastPressureAlert) > 1800 else { return }
        guard let memory = SystemMemorySnapshot.sample() else { return }
        let fraction = memory.usedFraction
        if fraction >= 0.95 {
            lastPressureAlert = Date()
            postAlert(title: "Memory Pressure", body: "Memory use is at \(Int((fraction * 100).rounded()))% — consider closing some apps.")
        } else if fraction >= 0.90 {
            lastPressureAlert = Date()
            postAlert(title: "Memory Pressure", body: "Memory use is high at \(Int((fraction * 100).rounded()))%.")
        }
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