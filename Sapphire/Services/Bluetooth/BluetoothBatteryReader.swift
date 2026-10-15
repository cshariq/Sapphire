//
//  BluetoothBatteryReader.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
@preconcurrency import CoreBluetooth
import IOBluetooth
import IOKit
import OSLog

// MARK: - Concurrency helpers

final class OneShotContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: Value) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return false }
        pending.resume(returning: value)
        return true
    }
}

@MainActor
final class SingleFlight<Value: Sendable> {
    private var inFlight: Task<Value, Never>?

    var isRunning: Bool { inFlight != nil }

    func run(_ operation: @escaping @Sendable () async -> Value) async -> Value {
        if let inFlight { return await inFlight.value }
        let task = Task { await operation() }
        inFlight = task
        let value = await task.value
        if inFlight == task { inFlight = nil }
        return value
    }
}

// MARK: - Reader

@MainActor
class BluetoothBatteryReader: NSObject, ObservableObject {
    static let shared = BluetoothBatteryReader()

    nonisolated static let slowRefreshMaxAge: TimeInterval = 5 * 60
    nonisolated static let ioRegistryCacheLifetime: TimeInterval = 15
    nonisolated static let gattTimeout: TimeInterval = 6

    private let slowRefresh = SingleFlight<Void>()
    private var lastSlowRefresh: Date?
    private(set) var systemProfilerBatteries: [SystemProfilerBattery] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "BluetoothBatteryReader")

    private override init() {
        super.init()
    }

    nonisolated static func isFresh(lastRefresh: Date?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let lastRefresh else { return false }
        let age = now.timeIntervalSince(lastRefresh)
        return age >= 0 && age < maxAge
    }

    var lastSlowRefreshDate: Date? { lastSlowRefresh }

    func refreshAllBatteries(maxAge: TimeInterval = BluetoothBatteryReader.slowRefreshMaxAge) async {
        if !slowRefresh.isRunning, Self.isFresh(lastRefresh: lastSlowRefresh, now: Date(), maxAge: maxAge) {
            return
        }
        await slowRefresh.run { [weak self] in
            await self?.performSlowRefresh()
        }
    }

    private func performSlowRefresh() async {
        let plistReadings = await Task.detached(priority: .utility) {
            Self.parseBluetoothPlistReadings()
        }.value
        var results = applyPlistReadings(plistReadings)

        async let profiler = Self.fetchSystemProfilerBatteries()
        async let gatt = GATTBatteryReadSession.read(timeout: Self.gattTimeout)

        let profilerReadings = await profiler
        systemProfilerBatteries = profilerReadings
        results += applySystemProfilerReadings(profilerReadings)
        results += applyGATTReadings(await gatt)

        lastSlowRefresh = Date()
        logger.debug("BluetoothBatteryReader completed with \(results) results")
    }

    // MARK: IORegistry (cheap path)

    struct IORegistryBatteryReading: Sendable, Equatable {
        let address: String
        let percent: Int
        let statusFlags: Int
        let product: String
    }

    private nonisolated static let ioRegistryLock = NSLock()
    private nonisolated(unsafe) static var ioRegistryCache: (time: TimeInterval, readings: [IORegistryBatteryReading])?

    private nonisolated static let ioRegistryClasses = [
        "AppleDeviceManagementHIDEventService",
        "AppleBluetoothHIDKeyboard",
        "BNBTrackpadDevice",
        "BNBMouseDevice",
    ]

    nonisolated static func ioRegistryBatteries() -> [IORegistryBatteryReading] {
        let now = ProcessInfo.processInfo.systemUptime
        ioRegistryLock.lock()
        if let cache = ioRegistryCache, now - cache.time < ioRegistryCacheLifetime {
            ioRegistryLock.unlock()
            return cache.readings
        }
        ioRegistryLock.unlock()

        var readings: [IORegistryBatteryReading] = []
        for className in ioRegistryClasses {
            var iterator = io_iterator_t()
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let percent = registryProperty(service, "BatteryPercent") as? Int,
                      percent > 0, percent <= 100,
                      let address = registryProperty(service, "DeviceAddress") as? String else { continue }
                readings.append(IORegistryBatteryReading(
                    address: normalizedAddress(address),
                    percent: percent,
                    statusFlags: registryProperty(service, "BatteryStatusFlags") as? Int ?? 0,
                    product: registryProperty(service, "Product") as? String ?? ""
                ))
            }
        }

        ioRegistryLock.lock()
        ioRegistryCache = (now, readings)
        ioRegistryLock.unlock()
        return readings
    }

    nonisolated static func ioRegistryBatteryLevel(forAddress address: String) -> Int? {
        let wanted = normalizedAddress(address)
        return ioRegistryBatteries().first { $0.address == wanted }?.percent
    }

    private nonisolated static func registryProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    nonisolated static func normalizedAddress(_ address: String) -> String {
        address.replacingOccurrences(of: "-", with: ":").uppercased()
    }

    // MARK: Bluetooth plist

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

    private func applyPlistReadings(_ readings: [PlistBatteryReading]) -> Int {
        let now = Date().timeIntervalSince1970
        var applied = 0

        for reading in readings {
            if AccessoryBatteryStore.checkIfBlocked(name: reading.deviceName) { continue }

            let existing = AccessoryBatteryStore.getByName(reading.deviceName)
            if reading.requiresStaleCheck, let existing, (now - existing.lastUpdate) <= 120 { continue }

            AccessoryBatteryStore.updateDevice(BatteryDevice(
                deviceID: reading.deviceID,
                deviceType: "general_bt",
                deviceName: reading.deviceName,
                batteryLevel: reading.batteryLevel,
                isCharging: 0,
                lastUpdate: now
            ))
            applied += 1
        }
        return applied
    }

    // MARK: system_profiler (slow fallback)

    struct SystemProfilerBattery: Sendable, Equatable {
        let name: String
        let baseName: String
        let address: String?
        let level: Int
        let type: String
    }

    private static func fetchSystemProfilerBatteries() async -> [SystemProfilerBattery] {
        let json: String? = await withCheckedContinuation { continuation in
            let once = OneShotContinuation(continuation)
            SPBluetoothDataModel.shared.refeshData(maxAge: slowRefreshMaxAge) { data in
                once.resume(returning: data)
            } error: {
                once.resume(returning: nil)
            }
        }
        guard let json else { return [] }
        let data = Data(json.utf8)
        return await Task.detached(priority: .utility) {
            parseSystemProfilerBatteries(data)
        }.value
    }

    nonisolated static func parseSystemProfilerBatteries(_ data: Data) -> [SystemProfilerBattery] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]] else {
            return []
        }

        var results: [SystemProfilerBattery] = []
        for section in sections {
            guard let devices = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in devices {
                for (name, value) in entry {
                    guard let details = value as? [String: Any] else { continue }
                    let address = (details["device_address"] as? String).map(normalizedAddress)
                    let type = details["device_minorType"] as? String ?? "general_bt"
                    for key in details.keys.sorted() where key.hasPrefix("device_batteryLevel") {
                        guard let level = parsePercent(details[key]) else { continue }
                        let side: String? = switch key.dropFirst("device_batteryLevel".count) {
                        case "Left": "Left"
                        case "Right": "Right"
                        case "Case": "Case"
                        default: nil
                        }
                        results.append(SystemProfilerBattery(
                            name: side.map { "\(name) (\($0))" } ?? name,
                            baseName: name,
                            address: address,
                            level: level,
                            type: type
                        ))
                    }
                }
            }
        }
        return results
    }

    private nonisolated static func parsePercent(_ value: Any?) -> Int? {
        let level: Int?
        switch value {
        case let number as Int: level = number
        case let text as String: level = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        default: level = nil
        }
        guard let level, level > 0, level <= 100 else { return nil }
        return level
    }

    private func applySystemProfilerReadings(_ readings: [SystemProfilerBattery]) -> Int {
        let now = Date().timeIntervalSince1970
        var applied = 0
        for reading in readings where !AccessoryBatteryStore.checkIfBlocked(name: reading.name) {
            if let existing = AccessoryBatteryStore.getByName(reading.name), now - existing.lastUpdate <= 60 { continue }
            AccessoryBatteryStore.updateDevice(BatteryDevice(
                deviceID: reading.name == reading.baseName ? (reading.address ?? reading.name) : "\(reading.address ?? reading.baseName) \(reading.name)",
                deviceType: reading.type,
                deviceName: reading.name,
                batteryLevel: reading.level,
                isCharging: 0,
                lastUpdate: now
            ))
            applied += 1
        }
        return applied
    }

    // MARK: GATT (slow fallback)

    private func applyGATTReadings(_ readings: [GATTBatteryReadSession.Reading]) -> Int {
        let now = Date().timeIntervalSince1970
        var applied = 0
        for reading in readings {
            let identifier = reading.identifier.uuidString
            guard let name = reading.name ?? AccessoryBatteryStore.getByID(identifier)?.deviceName else { continue }
            let existing = AccessoryBatteryStore.getByName(name)
            if let level = reading.level, existing == nil || now - (existing?.lastUpdate ?? 0) > 60 {
                AccessoryBatteryStore.updateDevice(BatteryDevice(
                    deviceID: identifier,
                    deviceType: "general_bt",
                    deviceName: name,
                    batteryLevel: level,
                    isCharging: existing?.isCharging ?? 0,
                    lastUpdate: now
                ))
                applied += 1
                logger.debug("[BLE] \(name, privacy: .public): \(level)%")
            }
            if let model = reading.model, var current = AccessoryBatteryStore.getByName(name) {
                current.deviceModel = model
                AccessoryBatteryStore.updateDevice(current)
            }
        }
        return applied
    }
}

// MARK: - GATT read session

private final class GATTBatteryReadSession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    struct Reading: Sendable {
        let identifier: UUID
        let name: String?
        var level: Int?
        var model: String?
    }

    private static let batteryService = CBUUID(string: "180F")
    private static let deviceInformationService = CBUUID(string: "180A")
    private static let batteryLevelCharacteristic = CBUUID(string: "2A19")
    private static let modelNumberCharacteristic = CBUUID(string: "2A24")

    private let queue = DispatchQueue(label: "com.sapphire.bluetooth.gatt-battery", qos: .utility)
    private var central: CBCentralManager?
    private var pending: [UUID: CBPeripheral] = [:]
    private var outstandingReads: [UUID: Int] = [:]
    private var readings: [UUID: Reading] = [:]
    private var completion: OneShotContinuation<[Reading]>?
    private var finished = false

    static func read(timeout: TimeInterval) async -> [Reading] {
        guard CBManager.authorization == .allowedAlways else { return [] }
        let session = GATTBatteryReadSession()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.start(OneShotContinuation(continuation), timeout: timeout)
            }
        } onCancel: {
            session.queue.async { session.finish() }
        }
    }

    private func start(_ completion: OneShotContinuation<[Reading]>, timeout: TimeInterval) {
        queue.async { [self] in
            self.completion = completion
            guard !finished else {
                completion.resume(returning: [])
                return
            }
            central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            queue.asyncAfter(deadline: .now() + timeout) { [self] in finish() }
        }
    }

    private func finish() {
        if finished { return }
        finished = true
        if let central {
            for peripheral in pending.values {
                peripheral.delegate = nil
                central.cancelPeripheralConnection(peripheral)
            }
            central.delegate = nil
        }
        pending.removeAll()
        central = nil
        completion?.resume(returning: Array(readings.values))
        completion = nil
    }

    private func done(with peripheral: CBPeripheral) {
        peripheral.delegate = nil
        central?.cancelPeripheralConnection(peripheral)
        pending[peripheral.identifier] = nil
        outstandingReads[peripheral.identifier] = nil
        if pending.isEmpty { finish() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !finished else { return }
        switch central.state {
        case .poweredOn:
            let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
            guard !connected.isEmpty else {
                finish()
                return
            }
            for peripheral in connected where pending[peripheral.identifier] == nil {
                pending[peripheral.identifier] = peripheral
                readings[peripheral.identifier] = Reading(identifier: peripheral.identifier, name: peripheral.name)
                central.connect(peripheral, options: nil)
            }
        case .unknown, .resetting:
            break
        default:
            finish()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !finished else { return }
        peripheral.delegate = self
        peripheral.discoverServices([Self.batteryService, Self.deviceInformationService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard !finished else { return }
        done(with: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !finished else { return }
        guard let services = peripheral.services, !services.isEmpty else {
            done(with: peripheral)
            return
        }
        outstandingReads[peripheral.identifier] = services.count
        for service in services {
            peripheral.discoverCharacteristics([Self.batteryLevelCharacteristic, Self.modelNumberCharacteristic], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !finished else { return }
        let wanted = (service.characteristics ?? []).filter {
            $0.uuid == Self.batteryLevelCharacteristic || $0.uuid == Self.modelNumberCharacteristic
        }
        outstandingReads[peripheral.identifier, default: 1] += wanted.count - 1
        for characteristic in wanted {
            peripheral.readValue(for: characteristic)
        }
        if (outstandingReads[peripheral.identifier] ?? 0) <= 0 { done(with: peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !finished else { return }
        if error == nil, let data = characteristic.value, !data.isEmpty {
            var reading = readings[peripheral.identifier] ?? Reading(identifier: peripheral.identifier, name: peripheral.name)
            if characteristic.uuid == Self.batteryLevelCharacteristic {
                let level = Int(data[data.startIndex])
                if level > 0, level <= 100 { reading.level = level }
            } else if characteristic.uuid == Self.modelNumberCharacteristic {
                reading.model = String(data: data, encoding: .ascii)
            }
            readings[peripheral.identifier] = reading
        }
        outstandingReads[peripheral.identifier, default: 1] -= 1
        if (outstandingReads[peripheral.identifier] ?? 0) <= 0 { done(with: peripheral) }
    }
}