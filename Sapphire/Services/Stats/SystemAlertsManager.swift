//
//  SystemAlertsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-04
//

import AppKit
import Combine
import IOKit.ps
import UserNotifications

private struct SystemAlertsConfiguration: Equatable {
    let isEnabled: Bool
    let sustainedCPUEnabled: Bool
    let cpuThreshold: Double
    let memoryPressureEnabled: Bool
    let lowDiskEnabled: Bool
    let diskThresholdGB: Double
    let temperatureEnabled: Bool
    let temperatureThreshold: Double
    let lowBatteryEnabled: Bool
    let lowBatteryThreshold: Double

    init(_ settings: Settings) {
        isEnabled = settings.monitoringAlertsEnabled
        sustainedCPUEnabled = settings.monitoringAlertSustainedCPUEnabled
        cpuThreshold = settings.monitoringAlertCPUThreshold
        memoryPressureEnabled = settings.monitoringAlertMemoryPressureEnabled
        lowDiskEnabled = settings.monitoringAlertLowDiskEnabled
        diskThresholdGB = settings.monitoringAlertDiskThresholdGB
        temperatureEnabled = settings.monitoringAlertTemperatureEnabled
        temperatureThreshold = settings.monitoringAlertTemperatureThreshold
        lowBatteryEnabled = settings.monitoringAlertLowBatteryEnabled
        lowBatteryThreshold = settings.monitoringAlertLowBatteryThreshold
    }

    var cpuActive: Bool { isEnabled && sustainedCPUEnabled }
    var memoryActive: Bool { isEnabled && memoryPressureEnabled }
    var diskActive: Bool { isEnabled && lowDiskEnabled }
    var temperatureActive: Bool { isEnabled && temperatureEnabled }
    var batteryActive: Bool { isEnabled && lowBatteryEnabled }
}

@MainActor
final class SystemAlertsManager: ObservableObject {
    static let shared = SystemAlertsManager()

    enum NotificationAccess: Equatable {
        case unknown, allowed, denied
    }

    @Published private(set) var notificationAccess: NotificationAccess = .unknown

    private static let pollingRequester = "SystemAlerts"
    private static let maximumTemperatureKeys = 24
    private static let temperatureSampleInterval: TimeInterval = 12

    private enum AlertKind: String {
        case cpu, temperature, memoryPressure, lowDisk, lowBattery
    }

    private enum PressureLevel {
        case warning, critical
    }

    private var settingsCancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var configuration: SystemAlertsConfiguration?

    private var cpuCancellable: AnyCancellable?
    private var temperatureCancellables = Set<AnyCancellable>()
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var diskCheckTimer: Timer?
    private var diskObservers: [NSObjectProtocol] = []
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?

    private var cpuGate = SustainedThresholdGate(duration: 45, cooldown: 600)
    private var temperatureGate = SustainedThresholdGate(duration: 30, cooldown: 900, minimumSamples: 3, maximumGap: 30)
    private var batteryLatch = LowBatteryLatch()
    private var diskLatch = LowDiskLatch()

    private var lastPressureAlert: TimeInterval?
    private var lastPressureLevel: PressureLevel?
    private var lastDiskAlert: TimeInterval?

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

    private func apply(_ new: SystemAlertsConfiguration) {
        let old = configuration
        guard new != old else { return }
        configuration = new

        if new.isEnabled, old?.isEnabled != true {
            requestNotificationAccess()
            observeAppActivation()
        } else if !new.isEnabled {
            stopObservingAppActivation()
        }

        if new.cpuActive != (old?.cpuActive ?? false) {
            new.cpuActive ? startCPUMonitoring() : stopCPUMonitoring()
        }
        if new.memoryActive != (old?.memoryActive ?? false) {
            new.memoryActive ? startMemoryPressureMonitoring() : stopMemoryPressureMonitoring()
        }
        if new.diskActive != (old?.diskActive ?? false) {
            new.diskActive ? startDiskMonitoring() : stopDiskMonitoring()
        } else if new.diskActive, new.diskThresholdGB != old?.diskThresholdGB {
            diskLatch = LowDiskLatch()
            sampleDiskSpace()
        }
        if new.temperatureActive != (old?.temperatureActive ?? false) {
            new.temperatureActive ? startTemperatureMonitoring() : stopTemperatureMonitoring()
        }
        if new.batteryActive != (old?.batteryActive ?? false) {
            new.batteryActive ? startBatteryMonitoring() : stopBatteryMonitoring()
        } else if new.batteryActive, new.lowBatteryThreshold != old?.lowBatteryThreshold {
            sampleBattery()
        }
    }

    func stopMonitoring() {
        stopCPUMonitoring()
        stopMemoryPressureMonitoring()
        stopDiskMonitoring()
        stopTemperatureMonitoring()
        stopBatteryMonitoring()
        stopObservingAppActivation()
        configuration = nil
    }

    // MARK: - CPU

    private func startCPUMonitoring() {
        cpuGate.resetWindow()
        cpuCancellable = StatsManager.shared.cpuSamples
            .sink { [weak self] sample in
                self?.sampleCPU(usage: sample.load.totalUsage, uptime: sample.uptime)
            }
        StatsManager.shared.setPolling(for: Self.pollingRequester, requiredStats: [.cpu])
    }

    private func stopCPUMonitoring() {
        cpuCancellable = nil
        cpuGate.resetWindow()
        StatsManager.shared.setPolling(for: Self.pollingRequester, requiredStats: [])
    }

    private func sampleCPU(usage: Double, uptime: TimeInterval) {
        guard let configuration, configuration.cpuActive else { return }
        guard let average = cpuGate.record(usage * 100, threshold: configuration.cpuThreshold, at: uptime) else { return }
        postAlert(
            kind: .cpu,
            title: "High CPU Load",
            body: "CPU has been at \(Int(average.rounded()))% for about a minute."
        )
    }

    // MARK: - Temperature

    private func startTemperatureMonitoring() {
        temperatureGate.resetWindow()
        let stats = StatsManager.shared
        stats.requestSensorCatalog()
        stats.$allSensors
            .map { Self.cpuTemperatureKeys(in: $0) }
            .removeDuplicates()
            .sink { [weak self] keys in
                self?.temperatureKeys = keys
                StatsManager.shared.setSensorKeys(
                    for: Self.pollingRequester,
                    keys: keys,
                    interval: Self.temperatureSampleInterval
                )
            }
            .store(in: &temperatureCancellables)
        stats.sensorSamples
            .sink { [weak self] sample in self?.sampleTemperature(sample.sensors, uptime: sample.uptime) }
            .store(in: &temperatureCancellables)
    }

    private func stopTemperatureMonitoring() {
        temperatureCancellables.removeAll()
        temperatureGate.resetWindow()
        temperatureKeys = []
        StatsManager.shared.setSensorKeys(for: Self.pollingRequester, keys: [])
    }

    private static func cpuTemperatureKeys(in catalog: [any Sensor_p]) -> Set<String> {
        func rank(_ key: String) -> Int {
            if key.hasPrefix("Tp") || key.hasPrefix("Tf") { return 0 }
            if key.hasPrefix("Te") { return 1 }
            return 2
        }
        return Set(catalog
            .filter { $0.group == .CPU && $0.type == .temperature }
            .map(\.key)
            .sorted { (rank($0), $0) < (rank($1), $1) }
            .prefix(maximumTemperatureKeys))
    }

    private var temperatureKeys: Set<String> = []

    private func sampleTemperature(_ sensors: [any Sensor_p], uptime: TimeInterval) {
        guard let configuration, configuration.temperatureActive else { return }
        let readings = sensors.filter { temperatureKeys.contains($0.key) }.map(\.value)
        guard let hottest = readings.max() else { return }
        guard temperatureGate.record(hottest, threshold: configuration.temperatureThreshold, at: uptime) != nil else { return }
        postAlert(
            kind: .temperature,
            title: "High Temperature",
            body: "The CPU has been running at about \(Int(hottest.rounded()))°C for 30 seconds."
        )
    }

    // MARK: - Memory pressure

    private func startMemoryPressureMonitoring() {
        guard memoryPressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pressure = self.memoryPressureSource?.data else { return }
                self.handleMemoryPressure(pressure)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func stopMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        lastPressureAlert = nil
        lastPressureLevel = nil
    }

    private func handleMemoryPressure(_ pressure: DispatchSource.MemoryPressureEvent) {
        let level: PressureLevel
        if pressure.contains(.critical) {
            level = .critical
        } else if pressure.contains(.warning) {
            level = .warning
        } else {
            lastPressureAlert = nil
            lastPressureLevel = nil
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let escalated = level == .critical && lastPressureLevel == .warning
        if !escalated, let last = lastPressureAlert, now - last < 1800 { return }
        lastPressureAlert = now
        lastPressureLevel = level
        switch level {
        case .critical:
            postAlert(kind: .memoryPressure, title: "Memory Pressure", body: "Memory pressure is critical — consider closing some apps.")
        case .warning:
            postAlert(kind: .memoryPressure, title: "Memory Pressure", body: "Memory pressure is high — consider closing some apps.")
        }
    }

    // MARK: - Disk space

    private func startDiskMonitoring() {
        guard diskCheckTimer == nil else { return }
        diskLatch = LowDiskLatch()
        sampleDiskSpace()
        diskCheckTimer = Timer.scheduledCoalescing(
            withTimeInterval: 15 * 60,
            repeats: true,
            toleranceFraction: 0.25
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleDiskSpace() }
        }

        let center = NSWorkspace.shared.notificationCenter
        diskObservers = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sampleDiskSpace() }
            }
        }
    }

    private func stopDiskMonitoring() {
        diskCheckTimer?.invalidate()
        diskCheckTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        diskObservers.forEach(center.removeObserver)
        diskObservers.removeAll()
    }

    private func sampleDiskSpace() {
        guard let configuration, configuration.diskActive else { return }
        let thresholdGB = configuration.diskThresholdGB
        Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let free = values?.volumeAvailableCapacityForImportantUsage else { return }
            let freeGB = Double(free) / (1024 * 1024 * 1024)
            await MainActor.run { [weak self] in
                self?.reportDiskSpace(freeGB: freeGB, thresholdGB: thresholdGB)
            }
        }
    }

    private func reportDiskSpace(freeGB: Double, thresholdGB: Double) {
        guard configuration?.diskActive == true else { return }
        guard diskLatch.update(freeGB: freeGB, thresholdGB: thresholdGB) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastDiskAlert, now - last < 3600 { return }
        lastDiskAlert = now
        postAlert(
            kind: .lowDisk,
            title: "Low Disk Space",
            body: "Only \(String(format: "%.1f", freeGB)) GB free on your startup disk."
        )
    }

    // MARK: - Battery

    private func startBatteryMonitoring() {
        guard powerSourceRunLoopSource == nil else { return }
        batteryLatch = LowBatteryLatch()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<SystemAlertsManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.sampleBattery() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSourceRunLoopSource = source
        sampleBattery()
    }

    private func stopBatteryMonitoring() {
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
            CFRunLoopSourceInvalidate(powerSourceRunLoopSource)
        }
        powerSourceRunLoopSource = nil
    }

    private func sampleBattery() {
        guard let configuration, configuration.batteryActive else { return }
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let level = Int((Double(current) / Double(maximum) * 100).rounded())
            let onBattery = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            let threshold = Int(configuration.lowBatteryThreshold.rounded())
            if batteryLatch.update(level: level, onBattery: onBattery, threshold: threshold) {
                postAlert(kind: .lowBattery, title: "Low Battery", body: "Battery is at \(level)%. Connect your Mac to power.")
            }
            return
        }
    }

    // MARK: - Notification delivery

    private func requestNotificationAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in SystemAlertsManager.shared.refreshNotificationAccess() }
        }
    }

    func refreshNotificationAccess() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let access: NotificationAccess
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: access = .allowed
            case .denied: access = .denied
            default: access = .unknown
            }
            Task { @MainActor in
                let manager = SystemAlertsManager.shared
                if manager.notificationAccess != access { manager.notificationAccess = access }
            }
        }
    }

    private func observeAppActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { SystemAlertsManager.shared.refreshNotificationAccess() }
        }
    }

    private func stopObservingAppActivation() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func postAlert(kind: AlertKind, title: String, body: String) {
        let identifier = "com.shariq.sapphire.monitoring.\(kind.rawValue)"
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            Task { @MainActor in
                let access: NotificationAccess = allowed ? .allowed : (settings.authorizationStatus == .denied ? .denied : .unknown)
                let manager = SystemAlertsManager.shared
                if manager.notificationAccess != access { manager.notificationAccess = access }
            }
            guard allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = identifier
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}