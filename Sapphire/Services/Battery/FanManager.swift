//
//  FanManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation
import Combine

// MARK: - Data Models

struct FanCurvePoint: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var temperature: Int
    var rpm: Int

    enum CodingKeys: String, CodingKey {
        case temperature, rpm
    }
}

enum FanControlMode: Equatable {
    case auto
    case constant(rpm: Int)
    case sensor(sensorKey: String, minTemp: Int, maxTemp: Int)
    case customCurve(sensorKey: String, points: [FanCurvePoint])
}

struct StoredFanControlMode: Codable, Equatable {
    enum Kind: String, Codable {
        case auto, constant, sensor, customCurve
    }

    var kind: Kind
    var rpm: Int?
    var sensorKey: String?
    var minTemp: Int?
    var maxTemp: Int?
    var points: [FanCurvePoint]?

    init(from mode: FanControlMode) {
        switch mode {
        case .auto:
            kind = .auto
        case .constant(let rpm):
            kind = .constant
            self.rpm = rpm
        case .sensor(let sensorKey, let minTemp, let maxTemp):
            kind = .sensor
            self.sensorKey = sensorKey
            self.minTemp = minTemp
            self.maxTemp = maxTemp
        case .customCurve(let sensorKey, let points):
            kind = .customCurve
            self.sensorKey = sensorKey
            self.points = points
        }
    }

    func toMode() -> FanControlMode {
        switch kind {
        case .auto:
            return .auto
        case .constant:
            return .constant(rpm: rpm ?? 2000)
        case .sensor:
            return .sensor(
                sensorKey: sensorKey ?? "TC0P",
                minTemp: minTemp ?? 40,
                maxTemp: maxTemp ?? 75
            )
        case .customCurve:
            return .customCurve(
                sensorKey: sensorKey ?? "TC0P",
                points: points ?? []
            )
        }
    }
}

struct TemperatureSensor: Identifiable, Hashable {
    let id = UUID()
    let key: String
    var name: String { SensorNameMap.name(for: key) }
    var value: Double = 0
}

// MARK: - Fan Manager

@MainActor
class FanManager: ObservableObject {
    static let shared = FanManager()

    @Published var fans: [FanInfo] = []
    @Published private(set) var sensors: [TemperatureSensor] = []
    @Published private(set) var fanModes: [Int: FanControlMode] = [:]

    private var updateTimer: Timer?
    private var helperRetryTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var pollingConsumers = 0

    private var needsControlLoop: Bool {
        fanModes.values.contains {
            if case .auto = $0 { return false }
            return true
        }
    }

    private init() {
        loadPersistedModes()
        registerHelperObservers()
        Task {
            await refreshHardwareState()
            refreshPollingState()
        }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func beginPolling() {
        pollingConsumers += 1
        refreshPollingState()
        Task { await refreshHardwareState() }
    }

    func endPolling() {
        pollingConsumers = max(0, pollingConsumers - 1)
        refreshPollingState()
    }

    private func refreshPollingState() {
        if needsControlLoop || pollingConsumers > 0 {
            startMonitoring(interval: needsControlLoop ? 3.0 : 5.0)
        } else {
            stopMonitoring()
        }
    }

    private func registerHelperObservers() {
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(forName: .sapphireHelperConnectionRestored, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.refreshHardwareState() }
            },
            center.addObserver(forName: .sapphireHelperConnectionLost, object: nil, queue: .main) { [weak self] _ in
                self?.startHelperRetryIfNeeded()
            }
        ]
    }

    func refreshHardwareState() async {
        await initializeFans()
        await initializeSensors()
        restorePersistedModes()
        refreshPollingState()
        if !fans.isEmpty {
            helperRetryTimer?.invalidate()
            helperRetryTimer = nil
        }
    }

    private func startHelperRetryIfNeeded() {
        guard helperRetryTimer == nil else { return }
        helperRetryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { await self?.refreshHardwareState() }
        }
    }

    private func initializeFans() async {
        guard let helper = getHelper() else {
            startHelperRetryIfNeeded()
            return
        }

        let fanCount = await helper.getFanCount()
        guard fanCount > 0 else {
            startHelperRetryIfNeeded()
            return
        }

        var fanArray: [FanInfo] = []
        for index in 0..<fanCount {
            if let fanInfo = await helper.getFanInfo(fanIndex: index) {
                fanArray.append(fanInfo)
                if fanModes[fanInfo.id] == nil {
                    fanModes[fanInfo.id] = .auto
                }
            }
        }

        if fanArray.isEmpty {
            startHelperRetryIfNeeded()
            return
        }

        fans = fanArray.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func initializeSensors() async {
        guard let helper = getHelper() else { return }

        let availableKeys = Set(await helper.getAllSMCKeys())
        var foundSensors: [TemperatureSensor] = []

        for (key, _) in SensorNameMap.knownSensors where availableKeys.contains(key) {
            foundSensors.append(TemperatureSensor(key: key))
        }

        for i in 0...15 {
            let hexChar = String(format: "%X", i)
            for key in ["TC\(hexChar)c", "TC\(hexChar)C"] where availableKeys.contains(key) {
                foundSensors.append(TemperatureSensor(key: key))
            }
        }

        sensors = foundSensors
            .reduce(into: [TemperatureSensor]()) { result, sensor in
                if !result.contains(where: { $0.key == sensor.key }) {
                    result.append(sensor)
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func startMonitoring(interval: TimeInterval = 3.0) {
        if let updateTimer, updateTimer.isValid, abs(updateTimer.timeInterval - interval) < 0.01 {
            return
        }
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateData()
        }
        if let updateTimer {
            RunLoop.main.add(updateTimer, forMode: .common)
        }
        updateData()
    }

    private func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateData() {
        Task {
            guard let helper = getHelper() else { return }

            let currentFans = fans
            let currentSensors = sensors

            await withTaskGroup(of: Void.self) { group in
                for fan in currentFans {
                    let fanID = fan.id
                    group.addTask {
                        if let updatedFan = await helper.getFanInfo(fanIndex: fanID) {
                            await MainActor.run {
                                guard let index = self.fans.firstIndex(where: { $0.id == fanID }) else { return }
                                self.fans[index].currentRPM = updatedFan.currentRPM
                            }
                        }
                    }
                }
                for sensor in currentSensors {
                    let key = sensor.key
                    group.addTask {
                        let newValue = await helper.getSensorValue(key: key)
                        if newValue >= 0 {
                            await MainActor.run {
                                guard let index = self.sensors.firstIndex(where: { $0.key == key }) else { return }
                                self.sensors[index].value = newValue
                            }
                        }
                    }
                }
            }

            applyActiveControlModes()
        }
    }

    private func applyActiveControlModes() {
        for fan in fans {
            guard let mode = fanModes[fan.id] else { continue }
            switch mode {
            case .auto:
                continue
            case .constant(let rpm):
                Task { await getHelper()?.setFanToConstantRPM(fanIndex: fan.id, speed: rpm) }
            case .sensor(let sensorKey, let minTemp, let maxTemp):
                applyLinearCurve(
                    fan: fan,
                    sensorKey: sensorKey,
                    points: [
                        FanCurvePoint(temperature: minTemp, rpm: fan.minRPM),
                        FanCurvePoint(temperature: maxTemp, rpm: fan.maxRPM)
                    ]
                )
            case .customCurve(let sensorKey, let points):
                applyLinearCurve(fan: fan, sensorKey: sensorKey, points: points)
            }
        }
    }

    private func applyLinearCurve(fan: FanInfo, sensorKey: String, points: [FanCurvePoint]) {
        guard let sensor = sensors.first(where: { $0.key == sensorKey }) else { return }
        let sortedPoints = points.sorted { $0.temperature < $1.temperature }
        guard sortedPoints.count >= 2 else { return }

        let currentTemp = sensor.value
        var targetRPM = fan.minRPM

        if currentTemp <= Double(sortedPoints[0].temperature) {
            targetRPM = sortedPoints[0].rpm
        } else if currentTemp >= Double(sortedPoints[sortedPoints.count - 1].temperature) {
            targetRPM = sortedPoints[sortedPoints.count - 1].rpm
        } else {
            for index in 0..<(sortedPoints.count - 1) {
                let lower = sortedPoints[index]
                let upper = sortedPoints[index + 1]
                let lowerTemp = Double(lower.temperature)
                let upperTemp = Double(upper.temperature)
                guard currentTemp >= lowerTemp, currentTemp <= upperTemp else { continue }
                let progress = (currentTemp - lowerTemp) / max(upperTemp - lowerTemp, 1)
                targetRPM = lower.rpm + Int(progress * Double(upper.rpm - lower.rpm))
                break
            }
        }

        targetRPM = max(fan.minRPM, min(fan.maxRPM, targetRPM))
        Task { await getHelper()?.setFanTargetSpeed(fanIndex: fan.id, speed: targetRPM) }
    }

    func setFanMode(for fanID: Int, to mode: FanControlMode) {
        guard fans.contains(where: { $0.id == fanID }) else { return }
        fanModes[fanID] = mode
        persistModes()
        refreshPollingState()

        Task {
            guard let helper = getHelper() else { return }
            switch mode {
            case .auto:
                await helper.setFanMode(fanIndex: fanID, mode: 0)
            case .constant(let rpm):
                await helper.setFanToConstantRPM(fanIndex: fanID, speed: rpm)
            case .sensor(_, _, _):
                let minRPM = fans.first(where: { $0.id == fanID })?.minRPM ?? 2000
                await helper.setFanToConstantRPM(fanIndex: fanID, speed: minRPM)
            case .customCurve(_, let points):
                let startRPM = points.sorted { $0.temperature < $1.temperature }.first?.rpm
                    ?? fans.first(where: { $0.id == fanID })?.minRPM
                    ?? 2000
                await helper.setFanToConstantRPM(fanIndex: fanID, speed: startRPM)
            }
        }
    }

    func getMode(for fanID: Int) -> FanControlMode {
        fanModes[fanID] ?? .auto
    }

    func markAllFansAutomatic() {
        for fan in fans {
            fanModes[fan.id] = .auto
        }
        persistModes()
        refreshPollingState()
    }

    static func defaultCurvePoints(for fan: FanInfo) -> [FanCurvePoint] {
        let midRPM = fan.minRPM + ((fan.maxRPM - fan.minRPM) / 2)
        return [
            FanCurvePoint(temperature: 45, rpm: fan.minRPM),
            FanCurvePoint(temperature: 65, rpm: midRPM),
            FanCurvePoint(temperature: 85, rpm: fan.maxRPM)
        ]
    }

    private func loadPersistedModes() {
        let stored = SettingsModel.shared.settings.fanControlModes
        fanModes = stored.reduce(into: [:]) { result, entry in
            guard let fanID = Int(entry.key) else { return }
            result[fanID] = entry.value.toMode()
        }
    }

    private func restorePersistedModes() {
        for fan in fans {
            guard let mode = fanModes[fan.id] else { continue }
            if case .auto = mode { continue }
            setFanMode(for: fan.id, to: mode)
        }
    }

    private func persistModes() {
        var settings = SettingsModel.shared.settings
        settings.fanControlModes = fanModes.reduce(into: [:]) { result, entry in
            result[String(entry.key)] = StoredFanControlMode(from: entry.value)
        }
        SettingsModel.shared.settings = settings
    }

    private func getHelper() -> HelperProtocol? {
        BatteryManager.shared.getHelper()
    }
}

// MARK: - Async Helper Wrappers

private enum HelperAsyncTimeout {
    static let seconds: TimeInterval = 3.0
}

extension HelperProtocol {
    func getFanCount() async -> Int {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: 0) { finish in
            getFanCount(reply: finish)
        }
    }

    func getFanInfo(fanIndex: Int) async -> FanInfo? {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: nil as FanInfo?) { finish in
            getFanInfo(fanIndex: fanIndex, reply: finish)
        }
    }

    func getSensorValue(key: String) async -> Double {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: -1.0) { finish in
            getSensorValue(key: key, reply: finish)
        }
    }

    func setFanMode(fanIndex: Int, mode: UInt8) async {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: ()) { finish in
            setFanMode(fanIndex: fanIndex, mode: mode) { _ in finish(()) }
        }
    }

    func setFanTargetSpeed(fanIndex: Int, speed: Int) async {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: ()) { finish in
            setFanTargetSpeed(fanIndex: fanIndex, speed: speed) { _ in finish(()) }
        }
    }

    func setFanToConstantRPM(fanIndex: Int, speed: Int) async {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: ()) { finish in
            setFanToConstantRPM(fanIndex: fanIndex, speed: speed) { _ in finish(()) }
        }
    }

    func getAllSMCKeys() async -> [String] {
        await withTimeoutReply(seconds: HelperAsyncTimeout.seconds, default: [String]()) { finish in
            getAllSMCKeys(reply: finish)
        }
    }
}

private func withTimeoutReply<T>(
    seconds: TimeInterval,
    default defaultValue: T,
    start: (@escaping (T) -> Void) -> Void
) async -> T {
    await withCheckedContinuation { continuation in
        let lock = NSLock()
        var finished = false
        let finish: (T) -> Void = { value in
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            continuation.resume(returning: value)
        }

        start(finish)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
            finish(defaultValue)
        }
    }
}