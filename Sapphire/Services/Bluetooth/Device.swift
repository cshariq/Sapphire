//
//  Device.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-07.
//
//
//
//

import Foundation
import CoreBluetooth
import Accelerate
import AppKit

let DeviceInformation = CBUUID(string:"180A")
let ManufacturerName = CBUUID(string:"2A29")
let ModelName = CBUUID(string:"2A24")

class Device: NSObject, Identifiable {
    let uuid : UUID!
    var id: UUID { uuid }

    var peripheral : CBPeripheral?

    var manufacture : String?
    var model : String?
    var rssi: Int = 0

    var displayName: String {
        if let advertisedName = peripheral?.name, !advertisedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return advertisedName
        }
        if let manu = manufacture, let mod = model {
            if manu == "Apple Inc.", let appleName = appleDeviceNames[mod] { return appleName }
            return "\(manu) \(mod)"
        }
        return "Unnamed Device (\(uuid.uuidString))"
    }

    override var description: String {
        return displayName
    }

    init(uuid _uuid: UUID) {
        uuid = _uuid
    }
}

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
    private var scanUpdateTimer: Timer?
    private var discoveredPeripheralsBatch: [UUID: (peripheral: CBPeripheral, rssi: NSNumber)] = [:]

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

        self.discoveredPeripheralsBatch.removeAll()
        self.scanUpdateTimer?.invalidate()
        self.scanUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true, block: { [weak self] _ in
            self?.processDiscoveredDevicesBatch()
        })

        scanForPeripherals(withDuplicates: true)
    }

    @MainActor func stopScanning() {
        self.isScanningContinuously = false
        self.includeUnnamedDevices = false
        self.scanUpdateTimer?.invalidate()
        self.scanUpdateTimer = nil

        processDiscoveredDevicesBatch()

        if activeModeTimer == nil {
            centralMgr.stopScan()
        }
    }

    // MARK: - Monitoring Control

    func setPassiveMode(_ mode: Bool) {
        passiveMode = mode
        if passiveMode {
            activeModeTimer?.invalidate(); activeModeTimer = nil
            if let p = monitoredPeripheral { centralMgr.cancelPeripheralConnection(p) }
            if monitoredPeripheral?.state != .connected {
                scanForPeripherals(withDuplicates: false)
            }
        }
    }

    func startMonitor(uuid: UUID) {
        if let p = monitoredPeripheral, p.identifier != uuid {
            centralMgr.cancelPeripheralConnection(p)
        }
        monitoredUUID = uuid
        monitoredPeripheral = devices[uuid]?.peripheral ?? centralMgr.retrievePeripherals(withIdentifiers: [uuid]).first

        proximityTimer?.invalidate()
        resetSignalTimer()
        activeModeTimer?.invalidate(); activeModeTimer = nil

        if let p = monitoredPeripheral, p.state == .connected {
             if !passiveMode { startActiveMode(peripheral: p) }
        } else {
            if !passiveMode {
                connectMonitoredPeripheral()
            } else {
                scanForPeripherals(withDuplicates: false)
            }
        }
    }

    func resetSignalTimer() {
        signalTimer?.invalidate()
        signalTimer = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false, block: { _ in
            Task { @MainActor in
                self.delegate?.updateRSSI(rssi: nil, active: false)
                self.delegate?.updatePresence(presence: false, reason: "lost")
            }
            self.scanForPeripherals(withDuplicates: false)
        })
        if let timer = signalTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    func connectMonitoredPeripheral() {
        guard let p = monitoredPeripheral else { return }
        if p.state == .disconnected {
            Task { @MainActor in self.delegate?.monitoredPeripheralState = .connecting }
            centralMgr.connect(p, options: nil)
            connectionTimer?.invalidate()
            connectionTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false, block: { _ in
                if p.state == .connecting { self.centralMgr.cancelPeripheralConnection(p) }
            })
            if let timer = connectionTimer { RunLoop.main.add(timer, forMode: .common) }
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

    @MainActor func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.identifier == monitoredUUID {
            if central.isScanning && !isScanningContinuously {
                central.stopScan()
            }
            if monitoredPeripheral == nil { monitoredPeripheral = peripheral }
            if activeModeTimer == nil {
                updateMonitoredPeripheral(RSSI.intValue)
                if !passiveMode { connectMonitoredPeripheral() }
            }
        }

        if isScanningContinuously {
            discoveredPeripheralsBatch[peripheral.identifier] = (peripheral, RSSI)
        }
    }

    @MainActor private func processDiscoveredDevicesBatch() {
        let batch = self.discoveredPeripheralsBatch
        self.discoveredPeripheralsBatch.removeAll()

        for (uuid, data) in batch {
            let peripheral = data.peripheral
            let rssi = data.rssi.intValue > 0 ? 0 : data.rssi.intValue

            guard rssi >= thresholdRSSI else { continue }

            let hasName = peripheral.name != nil && !peripheral.name!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if hasName || includeUnnamedDevices {
                if let existingDevice = self.devices[uuid] {
                    existingDevice.rssi = rssi
                    existingDevice.peripheral = peripheral
                    self.delegate?.updateDevice(device: existingDevice)
                } else {
                    let newDevice = Device(uuid: uuid)
                    newDevice.peripheral = peripheral
                    newDevice.rssi = rssi
                    self.devices[uuid] = newDevice
                    self.delegate?.newDevice(device: newDevice)
                }
            }
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
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == monitoredUUID {
            Task { @MainActor in self.delegate?.monitoredPeripheralState = .disconnected }
            activeModeTimer?.invalidate(); activeModeTimer = nil
            lastReadAt = 0
            if !passiveMode {
                connectMonitoredPeripheral()
            }
        }
    }

    // MARK: - Proximity & RSSI Logic

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
            proximityTimer?.invalidate(); proximityTimer = nil
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
                proximityTimer?.invalidate(); proximityTimer = nil
            }
        }
        resetSignalTimer()
    }

    private func startActiveMode(peripheral: CBPeripheral) {
        guard activeModeTimer == nil, !passiveMode else { return }

        if centralMgr.isScanning { centralMgr.stopScan() }

        activeModeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince1970 > self.lastReadAt + 10 && self.lastReadAt != 0 {
                self.centralMgr.cancelPeripheralConnection(peripheral)
                self.activeModeTimer?.invalidate(); self.activeModeTimer = nil
                self.scanForPeripherals(withDuplicates: false)
            } else if peripheral.state == .connected {
                peripheral.readRSSI()
            } else {
                self.connectMonitoredPeripheral()
            }
        })
        if let timer = activeModeTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    // MARK: - CBPeripheralDelegate

    @MainActor func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral.identifier == monitoredUUID, error == nil else { return }
        lastReadAt = Date().timeIntervalSince1970
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue
        updateMonitoredPeripheral(rssi)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == DeviceInformation {
                peripheral.discoverCharacteristics([ManufacturerName, ModelName], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for chara in chars {
            if chara.uuid == ManufacturerName || chara.uuid == ModelName {
                peripheral.readValue(for:chara)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, let device = devices[peripheral.identifier] else { return }
        let str = String(data: value, encoding: .utf8)

        if characteristic.uuid == ManufacturerName { device.manufacture = str }
        if characteristic.uuid == ModelName { device.model = str }
        Task { @MainActor in self.delegate?.updateDevice(device: device) }
    }
}