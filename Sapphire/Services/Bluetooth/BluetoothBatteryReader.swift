//
//  BluetoothBatteryReader.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import CoreBluetooth
import IOBluetooth
import OSLog

@MainActor
class BluetoothBatteryReader: NSObject, ObservableObject {
    static let shared = BluetoothBatteryReader()

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharUUID = CBUUID(string: "2A19")
    private let modelNumberCharUUID = CBUUID(string: "2A24")

    private var centralManager: CBCentralManager!
    private var pendingPeripherals: Set<CBPeripheral> = []
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var batchTimeoutTask: Task<Void, Never>?
    private var readResults: [String: Int] = [:]
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "BluetoothBatteryReader")

    private override init() {
        super.init()
    }

    private func ensureCentralManager() -> CBCentralManager {
        if let centralManager { return centralManager }
        let manager = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        centralManager = manager
        return manager
    }

    func refreshAllBatteries() async {
        readResults.removeAll()
        pendingPeripherals.removeAll()
        batchTimeoutTask?.cancel()

        let readings = await Task.detached(priority: .utility) {
            Self.parseBluetoothPlistReadings()
        }.value
        applyPlistReadings(readings)

        await readBatteriesFromCoreBluetooth()

        logger.debug("BluetoothBatteryReader completed with \(self.readResults.count) results")
    }

    private struct PlistBatteryReading: Sendable {
        let deviceID: String
        let deviceName: String
        let batteryLevel: Int
        let requiresStaleCheck: Bool
    }

    private nonisolated static func parseBluetoothPlistReadings() -> [PlistBatteryReading] {
        var readings: [PlistBatteryReading] = []

        guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist") else { return readings }

        if let cbcache = plist["CoreBluetoothCache"] as? [String: [String: Any]] {
            for (uuid, info) in cbcache {
                if let batteryLevel = info["BatteryLevel"] as? Int, batteryLevel > 0, batteryLevel <= 100 {
                    let deviceName = (info["DeviceName"] as? String) ?? uuid
                    let address = info["DeviceAddress"] as? String ?? uuid
                    readings.append(PlistBatteryReading(deviceID: address, deviceName: deviceName, batteryLevel: batteryLevel, requiresStaleCheck: false))
                }
            }
        }

        if let devCache = plist["DeviceCache"] as? [String: [String: Any]] {
            for (mac, info) in devCache {
                guard let deviceName = info["Name"] as? String,
                      !deviceName.isEmpty else { continue }

                let batteryLevels: [(String, String?)] = [
                    ("BatteryPercent", nil),
                    ("BatteryPercentLeft", "Left"),
                    ("BatteryPercentRight", "Right"),
                    ("BatteryPercentCase", "Case"),
                    ("BatteryPercentSingle", nil),
                ]

                for (key, side) in batteryLevels {
                    guard let raw = info[key] as? Int, raw > 0, raw <= 100 else { continue }
                    let suffix = side.map { " (\($0))" } ?? ""
                    readings.append(PlistBatteryReading(deviceID: mac + suffix, deviceName: deviceName + suffix, batteryLevel: raw, requiresStaleCheck: true))
                }
            }
        }

        return readings
    }

    private func applyPlistReadings(_ readings: [PlistBatteryReading]) {
        let now = Date().timeIntervalSince1970

        for reading in readings {
            if AirBatteryModel.checkIfBlocked(name: reading.deviceName) { continue }

            let existing = AirBatteryModel.getByName(reading.deviceName)
            if reading.requiresStaleCheck, let existing, (now - existing.lastUpdate) <= 120 { continue }

            let device = BatteryDevice(
                deviceID: reading.deviceID,
                deviceType: "general_bt",
                deviceName: reading.deviceName,
                batteryLevel: reading.batteryLevel,
                isCharging: 0,
                lastUpdate: now
            )
            AirBatteryModel.updateDevice(device)
            readResults[reading.deviceID] = reading.batteryLevel
            let source = reading.requiresStaleCheck ? "Plist/DeviceCache" : "Plist"
            logger.debug("[\(source, privacy: .public)] \(reading.deviceName, privacy: .public): \(reading.batteryLevel)%")
        }
    }

    private func readBatteriesFromCoreBluetooth() async {
        guard CBManager.authorization == .allowedAlways else {
            logger.debug("Bluetooth access not granted; skipping CoreBluetooth battery reads")
            return
        }

        let central = ensureCentralManager()
        guard central.state == .poweredOn else {
            logger.debug("CoreBluetooth not powered on, skipping")
            return
        }

        let connected = central.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])
        guard !connected.isEmpty else {
            logger.debug("No connected peripherals with Battery Service")
            return
        }

        logger.debug("Found \(connected.count) connected peripherals with Battery Service")
        central.delegate = self

        for peripheral in connected {
            pendingPeripherals.insert(peripheral)
            central.connect(peripheral, options: nil)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingContinuation = continuation
            batchTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                self?.releaseBatch(afterTimeout: true)
            }
        }
    }

    private func releaseBatch(afterTimeout: Bool) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        batchTimeoutTask?.cancel()
        batchTimeoutTask = nil

        if afterTimeout {
            for peripheral in pendingPeripherals {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            pendingPeripherals.removeAll()
            centralManager.delegate = nil
            logger.debug("CoreBluetooth battery batch timed out; released")
        }

        continuation.resume()
    }
}

extension BluetoothBatteryReader: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, !pendingPeripherals.isEmpty {
            for p in pendingPeripherals {
                central.connect(p, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([batteryServiceUUID, CBUUID(string: "180A")])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        pendingPeripherals.remove(peripheral)
        if pendingPeripherals.isEmpty { releaseBatch(afterTimeout: false) }
    }
}

extension BluetoothBatteryReader: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            centralManager.cancelPeripheralConnection(peripheral)
            pendingPeripherals.remove(peripheral)
            if pendingPeripherals.isEmpty { releaseBatch(afterTimeout: false) }
            return
        }
        for service in services {
            peripheral.discoverCharacteristics([batteryLevelCharUUID, modelNumberCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == batteryLevelCharUUID || char.uuid == modelNumberCharUUID {
                peripheral.readValue(for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let deviceName = peripheral.name ?? AirBatteryModel.getByID(peripheral.identifier.uuidString)?.deviceName else {
            finishPeripheral(peripheral)
            return
        }

        if characteristic.uuid == batteryLevelCharUUID, let data = characteristic.value {
            let level = Int(data[0])
            guard level > 0, level <= 100 else {
                finishPeripheral(peripheral)
                return
            }

            let now = Date().timeIntervalSince1970
            let existing = AirBatteryModel.getByName(deviceName)
            if existing == nil || (now - (existing?.lastUpdate ?? 0)) > 60 {
                let device = BatteryDevice(
                    deviceID: peripheral.identifier.uuidString,
                    deviceType: "general_bt",
                    deviceName: deviceName,
                    batteryLevel: level,
                    isCharging: existing?.isCharging ?? 0,
                    lastUpdate: now
                )
                AirBatteryModel.updateDevice(device)
            }
            readResults[peripheral.identifier.uuidString] = level
            logger.debug("[BLE] \(deviceName): \(level)%")
        }

        if characteristic.uuid == modelNumberCharUUID, let data = characteristic.value {
            let model = String(data: data, encoding: .ascii) ?? ""
            if var existing = AirBatteryModel.getByName(deviceName) {
                existing.deviceModel = model
                AirBatteryModel.updateDevice(existing)
            }
        }

        finishPeripheral(peripheral)
    }

    private func finishPeripheral(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
        pendingPeripherals.remove(peripheral)
        if pendingPeripherals.isEmpty {
            releaseBatch(afterTimeout: false)
        }
    }
}

extension BluetoothBatteryReader {

    nonisolated static func getSystemProfileBatteries() async -> [(name: String, level: Int, type: String)] {
        guard let result = await ProcessRunner.run(
            executablePath: "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json"],
            timeout: 15
        ), result.succeeded else {
            return []
        }

        return parseSystemProfilerData(result.stdoutData)
    }

    private nonisolated static func parseSystemProfilerData(_ data: Data) -> [(name: String, level: Int, type: String)] {
        var results: [(String, Int, String)] = []

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let btData = json["SPBluetoothDataType"] as? [[String: Any]],
              let first = btData.first,
              let devices = first["device_connected"] as? [[String: Any]] else {
            return results
        }

        for device in devices {
            guard let name = device["device_name"] as? String,
                  let minorType = device["device_minorType"] as? String else { continue }
            let levels: [(String, String?)] = [
                ("device_batteryLevelLeft", "Left"),
                ("device_batteryLevelRight", "Right"),
                ("device_batteryLevelCase", "Case"),
                ("device_batteryLevelSingle", nil),
            ]
            for (key, side) in levels {
                if let raw = device[key] as? String,
                   let level = Int(raw.replacingOccurrences(of: "%", with: "")),
                   level > 0, level <= 100 {
                    let displayName = side.map { "\(name) (\($0))" } ?? name
                    results.append((displayName, level, minorType))
                }
            }
        }
        return results
    }
}