//
//  BLEBattery.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2024/2/9.
//
//
//
//
//
//

import SwiftUI
import Foundation
import CoreBluetooth

class BLEBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @AppStorage("ideviceOverBLE") var ideviceOverBLE = false
    @AppStorage("readBTDevice") var readBTDevice = true
    @AppStorage("readBLEDevice") var readBLEDevice = false
    @AppStorage("updateInterval") var updateInterval = 1
    @AppStorage("twsMerge") var twsMerge = 5

    var centralManager: CBCentralManager!
    var peripherals: [CBPeripheral?] = []
    var otherAppleDevices: [String] = []
    var bleDevicesLevel: [String:UInt8] = [:]
    var bleDevicesVendor: [String:String] = [:]
    var scanTimer: Timer?

    private var processedThisScan: Set<String> = []

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scan(longScan: true)
        } else {
            print("[BLEBattery] ️ Bluetooth is not powered on. State: \(central.state.rawValue)")
        }
    }

    func startScan() {
        let interval = TimeInterval(29 * updateInterval)
        scanTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(scan), userInfo: nil, repeats: true)
        print("[BLEBattery] Starting continuous BLE scans every \(interval) seconds for AirPods.")
        scan(longScan: true)
    }

    @objc func scan(longScan: Bool = false) {
        if centralManager.state == .poweredOn && !centralManager.isScanning {
            self.processedThisScan.removeAll()

            let scanDuration = longScan ? 15.0 : 5.0
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + scanDuration) {
                self.stopScan()
            }
        }
    }

    func stopScan() {
        if centralManager.isScanning {
            centralManager.stopScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        var get = false
        let now = Double(Date().timeIntervalSince1970)
        if let deviceName = peripheral.name{
            if AirBatteryModel.checkIfBlocked(name: deviceName) { return }
            if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count > 0 {
                if data[0] != 76 {
                    if readBLEDevice {
                        if let device = AirBatteryModel.getByName(deviceName) {
                            if now - device.lastUpdate > Double(60 * updateInterval) { get = true } } else { get = true }
                    }
                } else {
                    if data.count > 2 {
                        if [16, 12].contains(data[2]) && !otherAppleDevices.contains(deviceName) && ideviceOverBLE {
                            if let device = AirBatteryModel.getByName(deviceName), let _ = device.deviceModel { if now - device.lastUpdate > Double(60 * updateInterval) { get = true } } else { get = true }
                        }
                        if data.count == 25 && data[2] == 18 && readBTDevice { getAirpods(peripheral: peripheral, data: data, messageType: "close") }
                        if data.count == 29 && data[2] == 7 && readBTDevice { getAirpods(peripheral: peripheral, data: data, messageType: "open") }
                    }
                }
            }
        }
        if get {
            self.peripherals.append(peripheral)
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        var clear = true
        if service.uuid == CBUUID(string: "180F") || service.uuid == CBUUID(string: "180A") {
            for characteristic in characteristics {
                if [CBUUID(string: "2A19"), CBUUID(string: "2A24"), CBUUID(string: "2A29")].contains(characteristic.uuid) {
                    clear = false
                    peripheral.readValue(for: characteristic)
                }
            }
        }
        if clear { if let index = self.peripherals.firstIndex(of: peripheral) { self.peripherals.remove(at: index) } }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == CBUUID(string: "2A19"){
            if let data = characteristic.value, let deviceName = peripheral.name {
                let now = Date().timeIntervalSince1970
                let level = Int(data[0])
                if level > 100 { return }
                var charging = 0
                if let lastLevel = bleDevicesLevel[deviceName] {
                    if level > lastLevel { charging = 1 }
                }
                bleDevicesLevel[deviceName] = data[0]
                if var device = AirBatteryModel.getByName(deviceName) {
                    device.deviceID = peripheral.identifier.uuidString
                    device.batteryLevel = level
                    device.lastUpdate = now
                    if charging != -1 { device.isCharging = charging }
                    AirBatteryModel.updateDevice(device)
                } else {
                    let device = BatteryDevice(deviceID: peripheral.identifier.uuidString, deviceType: getType(deviceName), deviceName: deviceName, batteryLevel: level, isCharging: charging, lastUpdate: now)
                    AirBatteryModel.updateDevice(device)
                }
            }
        }

        if characteristic.uuid == CBUUID(string: "2A24") {
            if let data = characteristic.value, let model = data.ascii(), let deviceName = peripheral.name, let vendor = bleDevicesVendor[deviceName] {
                if vendor == "Apple Inc." && model.contains("Watch") { otherAppleDevices.append(deviceName); return }
                if var device = AirBatteryModel.getByName(deviceName), device.deviceModel != model{
                    if vendor == "Apple Inc." {
                        device.deviceType = model.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "\\d", with: "", options: .regularExpression, range: nil)
                        device.deviceModel = model
                    } else {
                        device.deviceType = getType(deviceName)
                    }
                    device.lastUpdate = Date().timeIntervalSince1970
                    AirBatteryModel.updateDevice(device)
                }
            }
        }

        if characteristic.uuid == CBUUID(string: "2A29") {
            if let deviceName = peripheral.name {
                if let data = characteristic.value, let vendor = data.ascii() { bleDevicesVendor[deviceName] = vendor }
            }
        }
    }

    func getLevel(_ name: String, _ side: String) -> UInt8{
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any],
        let device_connected = SPBluetoothDataType["device_connected"] as? [Any] {
            for device in device_connected{
                let d = device as! [String: Any]
                if let n = d.keys.first,n == name,let info = d[n] as? [String: Any] {
                    if let level = info["device_batteryLevel"+side] as? String {
                        return UInt8(level.replacingOccurrences(of: "%", with: "")) ?? 255
                    }
                }
            }
        }
        return 255
    }

    func getType(_ name: String) -> String{
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any],
        let device_connected = SPBluetoothDataType["device_connected"] as? [Any] {
            for device in device_connected{
                let d = device as! [String: Any]
                if let n = d.keys.first,n == name,let info = d[n] as? [String: Any] {
                    if let type = info["device_minorType"] as? String {
                        return type
                    }
                }
            }
        }
        return "general_bt"
    }

    func getAirpods(peripheral: CBPeripheral, data: Data, messageType: String) {
        guard let name = peripheral.name else { return }

        if processedThisScan.contains(name) {
            return
        }

        if AirBatteryModel.checkIfBlocked(name: name) { return }

        print("[BLEBattery] AirPods '\(name)' advertisement received (\(messageType)): \(data.hexEncodedString())")

        if let deviceName = peripheral.name{
            let now = Date().timeIntervalSince1970
            let dataHex = data.hexEncodedString()
            let index = dataHex.index(dataHex.startIndex, offsetBy: 14)
            let flip = (strtoul(String(dataHex[index]), nil, 16) & 0x02) == 0
            let deviceID = peripheral.identifier.uuidString
            var model = (messageType == "open" ? getHeadphoneModel(String(format: "%02x%02x", data[6], data[5])) : "Airpods Pro 2")
            if let Case = AirBatteryModel.getByName(deviceName + " (Case)".local) { model = Case.deviceModel ?? model }

            var caseLevel = data[messageType == "open" ? 16 : 12]
            var caseCharging = 0
            if caseLevel != 255 {
                caseCharging = caseLevel > 100 ? 1 : 0
                caseLevel = (caseLevel ^ 128) & caseLevel
            }else{ caseLevel = getLevel(deviceName, "Case") }

            var leftLevel = data[messageType == "open" ? (flip ? 15 : 14) : 13]
            var leftCharging = 0
            if leftLevel != 255 {
                leftCharging = leftLevel > 100 ? 1 : 0
                leftLevel = (leftLevel ^ 128) & leftLevel
            }else{ leftLevel = getLevel(deviceName, "Left") }

            var rightLevel = data[messageType == "open" ? (flip ? 14 : 15) : 14]
            var rightCharging = 0
            if rightLevel != 255 {
                rightCharging = rightLevel > 100 ? 1 : 0
                rightLevel = (rightLevel ^ 128) & rightLevel
            }else{ rightLevel = getLevel(deviceName, "Right") }

            print("[BLEBattery] AirPods '\(deviceName)': Case=\(caseLevel)%, L=\(leftLevel)%, R=\(rightLevel)%. Flip=\(flip)")

            if !["Airpods Max", "Beats Solo Pro", "Beats Solo 3", "Beats Studio Pro"].contains(model) {
                if caseLevel != 255 { AirBatteryModel.updateDevice(BatteryDevice(deviceID: deviceID, deviceType: "ap_case", deviceName: deviceName + " (Case)".local, deviceModel: model, batteryLevel: Int(caseLevel), isCharging: caseCharging, lastUpdate: now)) }

                if leftLevel != 255 && rightLevel != 255 && (abs(Int(leftLevel) - Int(rightLevel)) < twsMerge) && leftCharging == rightCharging {
                    AirBatteryModel.hideDevice(deviceName + " 🄻")
                    AirBatteryModel.hideDevice(deviceName + " 🅁")
                    AirBatteryModel.updateDevice(BatteryDevice(deviceID: deviceID + "_All", deviceType: "ap_pod_all", deviceName: deviceName + " 🄻🅁", deviceModel: model, batteryLevel: Int(min(leftLevel, rightLevel)), isCharging: leftCharging, isHidden: false, parentName: deviceName + " (Case)".local, lastUpdate: now))
                } else {
                    AirBatteryModel.hideDevice(deviceName + " 🄻🅁")
                    if leftLevel != 255 { AirBatteryModel.updateDevice(BatteryDevice(deviceID: deviceID + "_Left", deviceType: "ap_pod_left", deviceName: deviceName + " 🄻", deviceModel: model, batteryLevel: Int(leftLevel), isCharging: leftCharging, isHidden: false, parentName: deviceName + " (Case)".local ,lastUpdate: now)) }
                    if rightLevel != 255 { AirBatteryModel.updateDevice(BatteryDevice(deviceID: deviceID + "_Right", deviceType: "ap_pod_right", deviceName: deviceName + " 🅁", deviceModel: model, batteryLevel: Int(rightLevel), isCharging: rightCharging, isHidden: false, parentName: deviceName + " (Case)".local, lastUpdate: now)) }
                }
            } else {
                if model == "Beats Studio Pro" {
                    AirBatteryModel.updateDevice(BatteryDevice(deviceID: deviceID, deviceType: "ap_case", deviceName: deviceName, deviceModel: model, batteryLevel: Int(rightLevel), isCharging: rightCharging, lastUpdate: now))
                } else {
                    leftLevel = leftLevel != 255 ? leftLevel : 0
                    rightLevel = rightLevel != 255 ? rightLevel : 0
                    AirBatteryModel.updateDevice(BatteryDevice(deviceID: deviceID, deviceType: "ap_case", deviceName: deviceName, deviceModel: model, batteryLevel: Int(max(rightLevel, leftLevel)), isCharging: rightCharging + leftCharging > 0 ? 1 : 0, lastUpdate: now))
                }
            }

            let validLevels = [leftLevel, rightLevel].filter { $0 != 255 }
            if !validLevels.isEmpty {
                let averageLevel = validLevels.reduce(0, +) / UInt8(validLevels.count)
                let userInfo = ["name": deviceName, "level": Int(averageLevel)] as [String : Any]
                NotificationCenter.default.post(name: .didUpdateAirPodsBattery, object: nil, userInfo: userInfo)

                processedThisScan.insert(name)
            }
        }
    }

    func getPaired() -> [String]{
        var paired:[String] = []
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
        let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
        let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    let d = device as! [String: Any]
                    if let key = d.keys.first { paired.append(key) }
                }
            }
            if let device_connected = SPBluetoothDataType["device_not_connected"] as? [Any]{
                for device in device_connected{
                    let d = device as! [String: Any]
                    if let key = d.keys.first { paired.append(key) }
                }
            }
        }
        return paired
    }
}