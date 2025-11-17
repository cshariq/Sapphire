//
//  FanManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation
import Combine

// MARK: - Data Models
struct TemperatureSensor: Identifiable, Hashable {
    let id = UUID()
    let key: String
    var name: String { SensorNameMap.name(for: key) }
    var value: Double = 0
}

enum FanControlMode: Equatable {
    case auto
    case constant(rpm: Int)
    case sensor(sensorKey: String, minTemp: Int, maxTemp: Int)
}

// MARK: - Fan Manager
@MainActor
class FanManager: ObservableObject {
    static let shared = FanManager()

    @Published var fans: [FanInfo] = []
    @Published private(set) var sensors: [TemperatureSensor] = []
    @Published private(set) var fanModes: [Int: FanControlMode] = [:]

    private var updateTimer: Timer?

    private init() {
        Task {
            await initializeFans()
            await initializeSensors()
            startMonitoring()
        }
    }

    private func initializeFans() async {
        guard let helper = getHelper() else { return }
        let fanCount = await helper.getFanCount()
        guard fanCount > 0 else {
            print("[FanManager] No fans found on this device.")
            return
        }

        var fanArray: [FanInfo] = []
        for i in 0..<fanCount {
            if let fanInfo = await helper.getFanInfo(fanIndex: i) {
                fanArray.append(fanInfo)
                fanModes[i] = .auto
            }
        }
        self.fans = fanArray.sorted { $0.name < $1.name }
    }

    private func initializeSensors() async {
        guard let helper = getHelper() else { return }

        let allSMCKeys = await helper.getAllSMCKeys()
        let availableKeys = Set(allSMCKeys)

        var foundSensors: [TemperatureSensor] = []

        for (key, _) in SensorNameMap.knownSensors {
            if availableKeys.contains(key) {
                foundSensors.append(TemperatureSensor(key: key))
            }
        }

        let wildcardPrefixes = ["TC"]
        for prefix in wildcardPrefixes {
            for i in 0...15 {
                let hexChar = String(format: "%X", i)
                let keyLower = "\(prefix)\(hexChar)c"
                if availableKeys.contains(keyLower) {
                    foundSensors.append(TemperatureSensor(key: keyLower))
                }
                let keyUpper = "\(prefix)\(hexChar)C"
                if availableKeys.contains(keyUpper) {
                    foundSensors.append(TemperatureSensor(key: keyUpper))
                }
            }
        }

        self.sensors = foundSensors.sorted { $0.name < $1.name }
    }

    private func startMonitoring() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateData()
        }
    }

    private func updateData() {
        Task {
            guard let helper = getHelper() else { return }

            for i in 0..<fans.count {
                if let updatedFan = await helper.getFanInfo(fanIndex: i) {
                    self.fans[i].currentRPM = updatedFan.currentRPM
                }
            }

            for i in 0..<sensors.count {
                self.sensors[i].value = await helper.getSensorValue(key: sensors[i].key)
            }

            applySensorBasedControl()
        }
    }

    private func applySensorBasedControl() {
        for i in 0..<fans.count {
            if case .sensor(let sensorKey, let minTemp, let maxTemp) = fanModes[i] {
                guard let sensor = sensors.first(where: { $0.key == sensorKey }) else { continue }

                let tempRange = Double(maxTemp - minTemp)
                if tempRange <= 0 { continue }
                let speedRange = Double(fans[i].maxRPM - fans[i].minRPM)

                let currentTemp = sensor.value
                var targetRPM: Int

                if currentTemp <= Double(minTemp) { targetRPM = fans[i].minRPM }
                else if currentTemp >= Double(maxTemp) { targetRPM = fans[i].maxRPM }
                else {
                    let tempProgress = (currentTemp - Double(minTemp)) / tempRange
                    targetRPM = fans[i].minRPM + Int(tempProgress * speedRange)
                }

                targetRPM = max(fans[i].minRPM, min(fans[i].maxRPM, targetRPM))

                Task { await getHelper()?.setFanTargetSpeed(fanIndex: i, speed: targetRPM) }
            }
        }
    }

    func setFanMode(for fanIndex: Int, to mode: FanControlMode) {
        guard fans.indices.contains(fanIndex) else { return }
        fanModes[fanIndex] = mode

        Task {
            guard let helper = getHelper() else { return }
            switch mode {
            case .auto:
                await helper.setFanMode(fanIndex: fanIndex, mode: 0)
            case .constant(let rpm):
                await helper.setFanToConstantRPM(fanIndex: fanIndex, speed: rpm)
            case .sensor:
                await helper.setFanMode(fanIndex: fanIndex, mode: 1)
            }
        }
    }

    func getMode(for fanIndex: Int) -> FanControlMode {
        return fanModes[fanIndex] ?? .auto
    }

    private func getHelper() -> HelperProtocol? {
        return BatteryManager.shared.getHelper()
    }
}

// MARK: - Async Helper Wrappers

extension HelperProtocol {
    func getFanCount() async -> Int {
        await withCheckedContinuation { continuation in
            getFanCount { count in
                continuation.resume(returning: count)
            }
        }
    }

    func getFanInfo(fanIndex: Int) async -> FanInfo? {
        await withCheckedContinuation { (continuation: CheckedContinuation<FanInfo?, Never>) in
            getFanInfo(fanIndex: fanIndex) { fanInfo in
                continuation.resume(returning: fanInfo)
            }
        }
    }

    func getAllTemperatureSensors(reply: @escaping ([String]) -> Void) {
        reply([])
    }

    func getSensorValue(key: String) async -> Double {
        await withCheckedContinuation { continuation in
            getSensorValue(key: key) { value in
                continuation.resume(returning: value)
            }
        }
    }

    func setFanMode(fanIndex: Int, mode: UInt8) async {
        await withCheckedContinuation { continuation in
            setFanMode(fanIndex: fanIndex, mode: mode) { _ in
                continuation.resume()
            }
        }
    }

    func setFanTargetSpeed(fanIndex: Int, speed: Int) async {
        await withCheckedContinuation { continuation in
            setFanTargetSpeed(fanIndex: fanIndex, speed: speed) { _ in
                continuation.resume()
            }
        }
    }

    func setFanToConstantRPM(fanIndex: Int, speed: Int) async {
        await withCheckedContinuation { continuation in
            setFanToConstantRPM(fanIndex: fanIndex, speed: speed) { _ in
                continuation.resume()
            }
        }
    }

    func getAllSMCKeys() async -> [String] {
        await withCheckedContinuation { continuation in
            getAllSMCKeys { keys in
                continuation.resume(returning: keys)
            }
        }
    }
}