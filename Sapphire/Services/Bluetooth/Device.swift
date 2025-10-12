//
//  Device.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-07.
//
//  This file contains the Device model and the BLE management class.
//  The BLE class has been upgraded to actively probe unnamed devices
//  to discover their manufacturer and model, similar to BLEUnlock's behavior.
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

    // Properties for resolved info from system caches
    private var resolvedName: String?
    private var resolvedMacAddress: String?

    var displayName: String {
        // 1. Prioritize an already resolved name from system caches
        if let name = resolvedName, !name.isEmpty { return name }

        // 2. Try the advertised name from the peripheral
        if let advertisedName = peripheral?.name, !advertisedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return advertisedName
        }
        
        // 3. Try building a name from the GATT service info (manufacturer + model)
        if let manu = manufacture, let mod = model {
            if manu == "Apple Inc.", let appleName = appleDeviceNames[mod] { return appleName }
            // For non-Apple devices like Samsung, this is very useful
            if !manu.isEmpty && !mod.isEmpty { return "\(manu) \(mod)" }
            if !mod.isEmpty { return mod }
        }

        // 4. Fallback to a generic name using the MAC address if available
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

    /// Uses the BluetoothDeviceResolver to look up info in private system caches.
    private func resolveDeviceInfo() {
        let uuidString = self.uuid.uuidString
        var finalName: String?
        var finalMac: String?

        // A. Try modern SQLite DBs first (macOS Monterey and newer)
        if let dbInfo = BluetoothDeviceResolver.shared.getLEDeviceInfo(from: uuidString) {
            finalName = dbInfo.name
            finalMac = dbInfo.macAddr
        }

        // B. If no MAC, try legacy plist for MAC
        if finalMac == nil {
            finalMac = BluetoothDeviceResolver.shared.getMACFromPlist(for: uuidString)
        }
        
        // C. If we found a MAC but still have no name, try to get the name using the MAC from the plist
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

    // --- Timers and Settings ---
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

    // --- Scanning Properties ---
    var isScanningContinuously = false
    var includeUnnamedDevices = false
    private var scanUpdateTimer: Timer?
    private var discoveredPeripheralsBatch: [UUID: (peripheral: CBPeripheral, rssi: NSNumber, advertisementData: [String: Any])] = [:]
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
        self.discoveredPeripheralsBatch.removeAll()
        
        self.scanUpdateTimer?.invalidate()
        self.scanUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true, block: { [weak self] _ in
            self?.processDiscoveredDevicesBatch()
        })

        scanForPeripherals(withDuplicates: true)
    }

    @MainActor func stopScanning() {
        self.isScanningContinuously = false
        // self.includeUnnamedDevices = false // Don't reset this, let manager control it
        self.scanUpdateTimer?.invalidate()
        self.scanUpdateTimer = nil

        processDiscoveredDevicesBatch()

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

    @MainActor func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Filter out COVID-19 Exposure Notification devices immediately
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], serviceUUIDs.contains(ExposureNotification) {
            return
        }
        
        // Handle the device currently being monitored for lock/unlock
        if peripheral.identifier == monitoredUUID {
            if central.isScanning && !isScanningContinuously { central.stopScan() }
            if monitoredPeripheral == nil { monitoredPeripheral = peripheral }
            if activeModeTimer == nil {
                updateMonitoredPeripheral(RSSI.intValue)
                if !passiveMode { connectMonitoredPeripheral() }
            }
        }

        // If we are in general scanning mode, add the device to the batch for processing
        if isScanningContinuously {
            discoveredPeripheralsBatch[peripheral.identifier] = (peripheral, RSSI, advertisementData)
        }
    }

    @MainActor private func processDiscoveredDevicesBatch() {
        let batch = self.discoveredPeripheralsBatch
        self.discoveredPeripheralsBatch.removeAll()

        for (uuid, data) in batch {
            let peripheral = data.peripheral
            let rssi = data.rssi.intValue > 0 ? 0 : data.rssi.intValue

            guard rssi >= thresholdRSSI else { continue }
            
            if let existingDevice = self.devices[uuid] {
                // Update existing device
                existingDevice.rssi = rssi
                existingDevice.peripheral = peripheral // Keep peripheral reference fresh
                self.delegate?.updateDevice(device: existingDevice)
            } else {
                // This is a new device, create and resolve its info
                let newDevice = Device(uuid: uuid, peripheral: peripheral, rssi: rssi)
                let hasGoodName = newDevice.displayName != "Unnamed Device"
                
                if hasGoodName || self.includeUnnamedDevices {
                    self.devices[uuid] = newDevice
                    self.delegate?.newDevice(device: newDevice)
                    
                    // If the device is still unnamed after cache lookup, try connecting to it
                    // to read its GATT service for more information.
                    if !hasGoodName && !peripheralsBeingProbed.contains(uuid) {
                        print("[BLE] Probing new unnamed device: \(uuid)")
                        peripheralsBeingProbed.insert(uuid)
                        centralMgr.connect(peripheral, options: nil)
                    }
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        
        if peripheral.identifier == monitoredUUID {
            // This is a connection for proximity monitoring
            Task { @MainActor in self.delegate?.monitoredPeripheralState = .connected }
            connectionTimer?.invalidate(); connectionTimer = nil
            if !passiveMode {
                startActiveMode(peripheral: peripheral)
            }
        } else if peripheralsBeingProbed.contains(peripheral.identifier) {
            // This is a temporary "probe" connection during a scan to get more info
            print("[BLE] Probe connected to \(peripheral.identifier). Discovering services...")
            peripheral.discoverServices([DeviceInformation])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Clean up if a probe connection fails
        if peripheralsBeingProbed.contains(peripheral.identifier) {
            print("[BLE] Probe failed to connect to \(peripheral.identifier). Error: \(error?.localizedDescription ?? "Unknown")")
            peripheralsBeingProbed.remove(peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Handle disconnect for the monitored device
        if peripheral.identifier == monitoredUUID {
            Task { @MainActor in self.delegate?.monitoredPeripheralState = .disconnected }
            activeModeTimer?.invalidate(); activeModeTimer = nil
            lastReadAt = 0
            if !passiveMode {
                connectMonitoredPeripheral()
            }
        }
        
        // Clean up after a probe connection disconnects
        if peripheralsBeingProbed.contains(peripheral.identifier) {
             print("[BLE] Probe disconnected from \(peripheral.identifier).")
             peripheralsBeingProbed.remove(peripheral.identifier)
        }
    }
    
    // MARK: - CBPeripheralDelegate (For Probing and Monitoring)

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            // If no services are found, disconnect the probe
            if peripheralsBeingProbed.contains(peripheral.identifier) {
                centralMgr.cancelPeripheralConnection(peripheral)
            }
            return
        }
        
        for service in services {
            if service.uuid == DeviceInformation {
                peripheral.discoverCharacteristics([ManufacturerName, ModelName], for: service)
                return // Found the service we need, stop searching
            }
        }

        // If the Device Information service was not found after checking all services, disconnect the probe
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
        
        // If we didn't find the characteristics we were looking for, disconnect the probe
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
        
        // If this was a probe and we have now read both values, we're done. Disconnect.
        if peripheralsBeingProbed.contains(peripheral.identifier) && device.manufacture != nil && device.model != nil {
            centralMgr.cancelPeripheralConnection(peripheral)
        }
    }

    // This delegate method is specifically for the active monitoring mode
    @MainActor func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral.identifier == monitoredUUID, error == nil else { return }
        lastReadAt = Date().timeIntervalSince1970
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue
        updateMonitoredPeripheral(rssi)
    }
    
    // MARK: - Monitoring Logic
    
    func setPassiveMode(_ mode: Bool) { passiveMode = mode; if passiveMode { activeModeTimer?.invalidate(); activeModeTimer = nil; if let p = monitoredPeripheral { centralMgr.cancelPeripheralConnection(p) }; if monitoredPeripheral?.state != .connected { scanForPeripherals(withDuplicates: false) } } }
    func startMonitor(uuid: UUID) { if let p = monitoredPeripheral, p.identifier != uuid { centralMgr.cancelPeripheralConnection(p) }; monitoredUUID = uuid; monitoredPeripheral = devices[uuid]?.peripheral ?? centralMgr.retrievePeripherals(withIdentifiers: [uuid]).first; proximityTimer?.invalidate(); resetSignalTimer(); activeModeTimer?.invalidate(); activeModeTimer = nil; if let p = monitoredPeripheral, p.state == .connected { if !passiveMode { startActiveMode(peripheral: p) } } else { if !passiveMode { connectMonitoredPeripheral() } else { scanForPeripherals(withDuplicates: false) } } }
    func resetSignalTimer() { signalTimer?.invalidate(); signalTimer = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false, block: { _ in Task { @MainActor in self.delegate?.updateRSSI(rssi: nil, active: false); self.delegate?.updatePresence(presence: false, reason: "lost") }; self.scanForPeripherals(withDuplicates: false) }); if let timer = signalTimer { RunLoop.main.add(timer, forMode: .common) } }
    func connectMonitoredPeripheral() { guard let p = monitoredPeripheral else { return }; if p.state == .disconnected { Task { @MainActor in self.delegate?.monitoredPeripheralState = .connecting }; centralMgr.connect(p, options: nil); connectionTimer?.invalidate(); connectionTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false, block: { _ in if p.state == .connecting { self.centralMgr.cancelPeripheralConnection(p) } }); if let timer = connectionTimer { RunLoop.main.add(timer, forMode: .common) } } }
    private func getEstimatedRSSI(rssi: Int) -> Int { if latestRSSIs.count >= latestN { latestRSSIs.removeFirst() }; latestRSSIs.append(Double(rssi)); var mean: Double = 0.0; vDSP_meanvD(latestRSSIs, 1, &mean, vDSP_Length(latestRSSIs.count)); return Int(mean) }
    @MainActor private func updateMonitoredPeripheral(_ rssi: Int) { let estimatedRSSI = getEstimatedRSSI(rssi: rssi); Task { @MainActor in self.delegate?.updateRSSI(rssi: estimatedRSSI, active: self.activeModeTimer != nil) }; if estimatedRSSI >= unlockRSSI { Task { @MainActor in self.delegate?.updatePresence(presence: true, reason: "close") }; proximityTimer?.invalidate(); proximityTimer = nil; latestRSSIs.removeAll() } else if estimatedRSSI < lockRSSI { if proximityTimer == nil { proximityTimer = Timer.scheduledTimer(withTimeInterval: proximityTimeout, repeats: false, block: { _ in Task { @MainActor in self.delegate?.updatePresence(presence: false, reason: "away") }; self.proximityTimer = nil; self.latestRSSIs.removeAll() }); if let timer = proximityTimer { RunLoop.main.add(timer, forMode: .common) } } } else if estimatedRSSI >= lockRSSI { if proximityTimer != nil { proximityTimer?.invalidate(); proximityTimer = nil } }; resetSignalTimer() }
    private func startActiveMode(peripheral: CBPeripheral) { guard activeModeTimer == nil, !passiveMode else { return }; if centralMgr.isScanning { centralMgr.stopScan() }; activeModeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true, block: { [weak self] _ in guard let self = self else { return }; if Date().timeIntervalSince1970 > self.lastReadAt + 10 && self.lastReadAt != 0 { self.centralMgr.cancelPeripheralConnection(peripheral); self.activeModeTimer?.invalidate(); self.activeModeTimer = nil; self.scanForPeripherals(withDuplicates: false) } else if peripheral.state == .connected { peripheral.readRSSI() } else { self.connectMonitoredPeripheral() } }); if let timer = activeModeTimer { RunLoop.main.add(timer, forMode: .common) } }
}

// MARK: - Apple Device Name Lookup Dictionary

