//
//  Device.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-07.
//

import Foundation
import CoreBluetooth
import Accelerate
import AppKit

// MARK: - GATT Service Constants
let DeviceInformation = CBUUID(string:"180A")
let ManufacturerName = CBUUID(string:"2A29")
let ModelName = CBUUID(string:"2A24")
let ExposureNotification = CBUUID(string:"FD6F")

// MARK: - Device Class
class Device: NSObject, Identifiable {
    let uuid: UUID
    var id: UUID { uuid }

    var peripheral: CBPeripheral?
    var manufacture: String?
    var model: String?
    var rssi: Int = 0

    private var resolvedName: String?
    private var resolvedMacAddress: String?

    var displayName: String {
        if let name = resolvedName, !name.isEmpty { return name }

        if let advertisedName = peripheral?.name, !advertisedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return advertisedName
        }

        if let manu = manufacture, let mod = model {
            if manu == "Apple Inc.", let appleName = appleDeviceNames[mod] { return appleName }
            if !manu.isEmpty && !mod.isEmpty { return "\(manu) \(mod)" }
            if !mod.isEmpty { return mod }
        }

        if let mac = resolvedMacAddress {
            return "Device (\(mac))"
        }

        return "Unnamed Device"
    }

    override var description: String {
        return displayName
    }

    init(uuid: UUID, peripheral: CBPeripheral?, rssi: Int) {
        self.uuid = uuid
        self.peripheral = peripheral
        self.rssi = rssi
        super.init()
        resolveDeviceInfo()
    }

    private func resolveDeviceInfo() {
        let uuidString = self.uuid.uuidString
        var finalName: String?
        var finalMac: String?

        if let dbInfo = BluetoothDeviceResolver.shared.getLEDeviceInfo(from: uuidString) {
            finalName = dbInfo.name
            finalMac = dbInfo.macAddr
        }

        if finalMac == nil {
            finalMac = BluetoothDeviceResolver.shared.getMACFromPlist(for: uuidString)
        }

        if finalName == nil, let mac = finalMac {
            finalName = BluetoothDeviceResolver.shared.getNameFromPlist(for: mac)
        }

        self.resolvedName = finalName
        self.resolvedMacAddress = finalMac
    }
}

// MARK: - BLE Delegate Protocol
@MainActor
protocol BLEDelegate {
    var monitoredPeripheralState: CBPeripheralState { get set }
    func newDevice(device: Device)
    func updateDevice(device: Device)
    func removeDevice(device: Device)
    func updateRSSI(rssi: Int?, active: Bool)
    func updatePresence(presence: Bool, reason: String)
    func bluetoothPowerWarn()
}

// MARK: - BLE Class (with Probing Logic)
class BLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralMgr : CBCentralManager!
    var devices : [UUID : Device] = [:]
    var delegate: BLEDelegate?
    var monitoredUUID: UUID?
    var monitoredPeripheral: CBPeripheral?

    var proximityTimer : Timer?
    var signalTimer: Timer?
    var activeModeTimer : Timer?
    var connectionTimer : Timer?

    var lockRSSI = -80
    var unlockRSSI = -60
    var proximityTimeout = 5.0
    var signalTimeout = 60.0
    var passiveMode = false
    var thresholdRSSI = -80

    private var lastReadAt = 0.0
    private var powerWarn = true
    private var latestRSSIs: [Double] = []
    private let latestN: Int = 5

    var isScanningContinuously = false
    var includeUnnamedDevices = false
    private var peripheralsBeingProbed = Set<UUID>()

    override init() {
        super.init()
        centralMgr = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning Control

    private func scanForPeripherals(withDuplicates: Bool) {
        guard centralMgr.state == .poweredOn, !centralMgr.isScanning else { return }
        let options = [CBCentralManagerScanOptionAllowDuplicatesKey: withDuplicates]
        centralMgr.scanForPeripherals(withServices: nil, options: options)
    }

    func startScanning(includeUnnamed: Bool) {
        self.isScanningContinuously = true
        self.includeUnnamedDevices = includeUnnamed
        self.peripheralsBeingProbed.removeAll()

        scanForPeripherals(withDuplicates: true)
    }

    @MainActor func stopScanning() {
        self.isScanningContinuously = false

        if activeModeTimer == nil {
            centralMgr.stopScan()
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if monitoredUUID != nil || isScanningContinuously {
                scanForPeripherals(withDuplicates: isScanningContinuously)
            }
        case .poweredOff:
            signalTimer?.invalidate(); signalTimer = nil
            if powerWarn {
                powerWarn = false
                Task { @MainActor in self.delegate?.bluetoothPowerWarn() }
            }
        default: break
        }
    }

    @MainActor private func processDiscoveredPeripheral(_ peripheral: CBPeripheral, rssi RSSI: NSNumber, advertisementData: [String: Any]) {
        let rssiInt = RSSI.intValue > 0 ? 0 : RSSI.intValue
        let uuid = peripheral.identifier

        guard rssiInt >= thresholdRSSI else { return }

        if let existingDevice = self.devices[uuid] {
            existingDevice.rssi = rssiInt
            existingDevice.peripheral = peripheral
            self.delegate?.updateDevice(device: existingDevice)
        } else {
            let newDevice = Device(uuid: uuid, peripheral: peripheral, rssi: rssiInt)
            let hasGoodName = newDevice.displayName != "Unnamed Device"

            if hasGoodName || self.includeUnnamedDevices {
                self.devices[uuid] = newDevice
                self.delegate?.newDevice(device: newDevice)

                if !hasGoodName && !peripheralsBeingProbed.contains(uuid) {
                    print("[BLE] Probing new unnamed device: \(uuid)")
                    peripheralsBeingProbed.insert(uuid)
                    centralMgr.connect(peripheral, options: nil)
                }
            }
        }
    }

    @MainActor func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], serviceUUIDs.contains(ExposureNotification) {
            return
        }

        if peripheral.identifier == monitoredUUID {
            if central.isScanning && !isScanningContinuously {
                 central.stopScan()
            }
            if monitoredPeripheral == nil {
                monitoredPeripheral = peripheral
            }

            if let device = self.devices[peripheral.identifier] {
                device.peripheral = peripheral
                device.rssi = RSSI.intValue
                self.delegate?.updateDevice(device: device)
            } else {
                let newDevice = Device(uuid: peripheral.identifier, peripheral: peripheral, rssi: RSSI.intValue)
                self.devices[peripheral.identifier] = newDevice
                self.delegate?.newDevice(device: newDevice)
            }

            if activeModeTimer == nil {
                updateMonitoredPeripheral(RSSI.intValue)
                if !passiveMode {
                    connectMonitoredPeripheral()
                }
            }
        } else if isScanningContinuously {
            processDiscoveredPeripheral(peripheral, rssi: RSSI, advertisementData: advertisementData)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self

        if peripheral.identifier == monitoredUUID {
            Task { @MainActor in self.delegate?.monitoredPeripheralState = .connected }
            connectionTimer?.invalidate(); connectionTimer = nil
            if !passiveMode {
                startActiveMode(peripheral: peripheral)
            }
        } else if peripheralsBeingProbed.contains(peripheral.identifier) {
            print("[BLE] Probe connected to \(peripheral.identifier). Discovering services...")
            peripheral.discoverServices([DeviceInformation])
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheralsBeingProbed.contains(peripheral.identifier) {
            print("[BLE] Probe failed to connect to \(peripheral.identifier). Error: \(error?.localizedDescription ?? "Unknown")")
            peripheralsBeingProbed.remove(peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == monitoredUUID {
            Task { @MainActor in self.delegate?.monitoredPeripheralState = .disconnected }
            activeModeTimer?.invalidate(); activeModeTimer = nil
            lastReadAt = 0
            if !passiveMode {
                print("[BLE] Monitored peripheral disconnected. Reconnecting in 1 second...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.connectMonitoredPeripheral()
                }
            }
        }

        if peripheralsBeingProbed.contains(peripheral.identifier) {
             print("[BLE] Probe disconnected from \(peripheral.identifier).")
             peripheralsBeingProbed.remove(peripheral.identifier)
        }
    }

    // MARK: - CBPeripheralDelegate (For Probing and Monitoring)

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            if peripheralsBeingProbed.contains(peripheral.identifier) {
                centralMgr.cancelPeripheralConnection(peripheral)
            }
            return
        }

        for service in services {
            if service.uuid == DeviceInformation {
                peripheral.discoverCharacteristics([ManufacturerName, ModelName], for: service)
                return
            }
        }

        if peripheralsBeingProbed.contains(peripheral.identifier) {
            centralMgr.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else {
            if peripheralsBeingProbed.contains(peripheral.identifier) {
                centralMgr.cancelPeripheralConnection(peripheral)
            }
            return
        }

        var characteristicsToRead = 0
        for chara in chars {
            if chara.uuid == ManufacturerName || chara.uuid == ModelName {
                peripheral.readValue(for: chara)
                characteristicsToRead += 1
            }
        }

        if characteristicsToRead == 0 && peripheralsBeingProbed.contains(peripheral.identifier) {
             centralMgr.cancelPeripheralConnection(peripheral)
        }
    }

    @MainActor func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, let device = devices[peripheral.identifier] else { return }
        let str = String(data: value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var didUpdate = false
        if characteristic.uuid == ManufacturerName {
            device.manufacture = str
            didUpdate = true
        }
        if characteristic.uuid == ModelName {
            device.model = str
            didUpdate = true
        }

        if didUpdate {
            self.delegate?.updateDevice(device: device)
        }

        if peripheralsBeingProbed.contains(peripheral.identifier) && device.manufacture != nil && device.model != nil {
            centralMgr.cancelPeripheralConnection(peripheral)
        }
    }

    @MainActor func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral.identifier == monitoredUUID, error == nil else { return }
        lastReadAt = Date().timeIntervalSince1970
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue

        if let device = self.devices[peripheral.identifier] {
            device.rssi = rssi
            self.delegate?.updateDevice(device: device)
        }

        updateMonitoredPeripheral(rssi)
    }

    // MARK: - Monitoring Logic

    func startMonitor(uuid: UUID) {
        if let p = monitoredPeripheral, p.identifier != uuid {
            centralMgr.cancelPeripheralConnection(p)
        }

        monitoredUUID = uuid
        monitoredPeripheral = devices[uuid]?.peripheral ?? centralMgr.retrievePeripherals(withIdentifiers: [uuid]).first

        proximityTimer?.invalidate(); proximityTimer = nil
        activeModeTimer?.invalidate(); activeModeTimer = nil
        connectionTimer?.invalidate(); connectionTimer = nil
        resetSignalTimer()

        if let p = monitoredPeripheral {
            if p.state == .connected && !passiveMode {
                print("[BLE] Monitored peripheral already connected. Starting active mode.")
                startActiveMode(peripheral: p)
            } else {
                print("[BLE] Monitored peripheral found. Attempting to connect for monitoring.")
                connectMonitoredPeripheral()
            }
        } else {
            print("[BLE] Monitored peripheral not found in cache or system registry. Scanning to discover...")
            scanForPeripherals(withDuplicates: true)
        }
    }

    func stopMonitor() {
        if let p = monitoredPeripheral, p.identifier == monitoredUUID {
            if p.state == .connected || p.state == .connecting {
                centralMgr.cancelPeripheralConnection(p)
            }
        }
        monitoredUUID = nil
        monitoredPeripheral = nil
        proximityTimer?.invalidate(); proximityTimer = nil
        signalTimer?.invalidate(); signalTimer = nil
        activeModeTimer?.invalidate(); activeModeTimer = nil

        if !isScanningContinuously && centralMgr.isScanning {
            centralMgr.stopScan()
        }
        print("[BLE] Monitoring has been stopped.")
    }

    func setPassiveMode(_ mode: Bool) {
        passiveMode = mode
        if passiveMode {
            activeModeTimer?.invalidate()
            activeModeTimer = nil
            if let p = monitoredPeripheral {
                centralMgr.cancelPeripheralConnection(p)
            }
            if monitoredPeripheral?.state != .connected {
                scanForPeripherals(withDuplicates: false)
            }
        }
    }

    func connectMonitoredPeripheral() {
        guard let p = monitoredPeripheral else {
            print("[BLE] Cannot connect: monitoredPeripheral is nil. A scan should be in progress.")
            return
        }

        guard p.state == .disconnected || p.state == .disconnecting else {
            print("[BLE] Connection attempt ignored, peripheral state is not disconnected (current: \(p.state.rawValue))")
            return
        }

        Task { @MainActor in self.delegate?.monitoredPeripheralState = .connecting }
        print("[BLE] Attempting to connect to peripheral: \(p.identifier)")
        centralMgr.connect(p, options: nil)

        connectionTimer?.invalidate()
        let connectionTimeout = 10.0
        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeout, repeats: false, block: { [weak self] _ in
            guard let self = self, let p = self.monitoredPeripheral, p.state == .connecting else { return }
            print("[BLE] Connection timed out for peripheral: \(p.identifier). Cancelling.")
            self.centralMgr.cancelPeripheralConnection(p)
        })
        if let timer = connectionTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func resetSignalTimer() {
        signalTimer?.invalidate()
        signalTimer = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false, block: { _ in
            Task { @MainActor in
                self.delegate?.updateRSSI(rssi: nil, active: false)
                self.delegate?.updatePresence(presence: false, reason: "lost")
            }
            self.scanForPeripherals(withDuplicates: false)
        })
        if let timer = signalTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func getEstimatedRSSI(rssi: Int) -> Int {
        if latestRSSIs.count >= latestN { latestRSSIs.removeFirst() }
        latestRSSIs.append(Double(rssi))
        var mean: Double = 0.0
        vDSP_meanvD(latestRSSIs, 1, &mean, vDSP_Length(latestRSSIs.count))
        return Int(mean)
    }

    @MainActor private func updateMonitoredPeripheral(_ rssi: Int) {
        let estimatedRSSI = getEstimatedRSSI(rssi: rssi)

        Task { @MainActor in self.delegate?.updateRSSI(rssi: estimatedRSSI, active: self.activeModeTimer != nil) }

        if estimatedRSSI >= unlockRSSI {
            Task { @MainActor in self.delegate?.updatePresence(presence: true, reason: "close") }
            proximityTimer?.invalidate()
            proximityTimer = nil
            latestRSSIs.removeAll()
        } else if estimatedRSSI < lockRSSI {
            if proximityTimer == nil {
                proximityTimer = Timer.scheduledTimer(withTimeInterval: proximityTimeout, repeats: false, block: { _ in
                    Task { @MainActor in self.delegate?.updatePresence(presence: false, reason: "away") }
                    self.proximityTimer = nil
                    self.latestRSSIs.removeAll()
                })
                if let timer = proximityTimer { RunLoop.main.add(timer, forMode: .common) }
            }
        } else if estimatedRSSI >= lockRSSI {
            if proximityTimer != nil {
                proximityTimer?.invalidate()
                proximityTimer = nil
            }
        }
        resetSignalTimer()
    }

    private func startActiveMode(peripheral: CBPeripheral) {
        guard activeModeTimer == nil, !passiveMode else { return }
        if centralMgr.isScanning { centralMgr.stopScan() }

        activeModeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }

            if Date().timeIntervalSince1970 > self.lastReadAt + 10 && self.lastReadAt != 0 {
                self.centralMgr.cancelPeripheralConnection(peripheral)
                self.activeModeTimer?.invalidate()
                self.activeModeTimer = nil
                self.scanForPeripherals(withDuplicates: false)
            } else if peripheral.state == .connected {
                peripheral.readRSSI()
            } else {
                self.connectMonitoredPeripheral()
            }
        })
        if let timer = activeModeTimer { RunLoop.main.add(timer, forMode: .common) }
    }
}

// MARK: - Apple Device Name Lookup Dictionary