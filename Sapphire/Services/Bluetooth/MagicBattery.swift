//
//  MagicBattery.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2024/2/9.
//

import SwiftUI
import Foundation
import IOBluetooth

class SPBluetoothDataModel {
    static var shared: SPBluetoothDataModel = SPBluetoothDataModel()
    var data: String = "{}"

    func refeshData(completion: (String) -> Void, error: (() -> Void)? = nil) {
        if let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"]) {
            data = result
            completion(result)
        } else {
            error?()
        }
    }
}

class MagicBattery {
    static var shared: MagicBattery = MagicBattery()

    @AppStorage("readBTDevice") var readBTDevice = true
    @AppStorage("updateInterval") var updateInterval = 1
    @AppStorage("deviceName") var deviceName = "Mac"

    func startScan() {
        scanDevices()
    }

    @objc func scanDevices() {
        if self.readBTDevice {
            self.getIOBTBattery()
            self.getMagicBattery()
            self.getOldMagicKeyboard()
            self.getOldMagicTrackpad()
            self.getOldMagicMouse()
        }
    }

    func findParentKey(forValue value: Any, in json: [String: Any]) -> String? {
        for (key, subJson) in json {
            if let subJsonDictionary = subJson as? [String: Any] {
                if subJsonDictionary.values.contains(where: { $0 as? String == value as? String }) {
                    return key
                } else if let parentKey = findParentKey(forValue: value, in: subJsonDictionary) {
                    return parentKey
                }
            } else if let subJsonArray = subJson as? [[String: Any]] {
                for subJsonDictionary in subJsonArray {
                    if subJsonDictionary.values.contains(where: { $0 as? String == value as? String }) {
                        return key
                    } else if let parentKey = findParentKey(forValue: value, in: subJsonDictionary) {
                        return parentKey
                    }
                }
            }
        }
        return nil
    }

    func getDeviceName(_ mac: String, _ def: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any] {
            if let parent = findParentKey(forValue: mac, in: json) {
                return parent
            }
        }
        return def
    }

    func getDeviceType(_ mac: String, _ def: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
           let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
           let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    let d = device as! [String: Any]
                    if let n = d.keys.first, let info = d[n] as? [String: Any] {
                        if let id = info["device_address"] as? String,
                           let type = info["device_minorType"] as? String{
                            if id == mac { return type }
                        }
                    }
                }
            }
        }
        return def
    }

    func getDeviceTypeWithPID(_ pid: String, _ def: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8), options: []) as? [String: Any],
           let SPBluetoothDataTypeRaw = json["SPBluetoothDataType"] as? [Any],
           let SPBluetoothDataType = SPBluetoothDataTypeRaw[0] as? [String: Any]{
            if let device_connected = SPBluetoothDataType["device_connected"] as? [Any]{
                for device in device_connected{
                    let d = device as! [String: Any]
                    if let n = d.keys.first, let info = d[n] as? [String: Any] {
                        if let id = info["device_productID"] as? String,
                           let type = info["device_minorType"] as? String{
                            if id == pid { return type }
                        }
                    }
                }
            }
        }
        return def
    }

    func readMagicBattery(object: io_object_t) {
        var mac = ""
        var type = "hid"
        var status = 0
        var percent = 0
        var productName = ""
        let lastUpdate = Date().timeIntervalSince1970
        if let productProperty = IORegistryEntryCreateCFProperty(object, "DeviceAddress" as CFString, kCFAllocatorDefault, 0) {
            mac = productProperty.takeRetainedValue() as! String
            mac = mac.replacingOccurrences(of:"-", with:":").uppercased()
        }
        if let percentProperty = IORegistryEntryCreateCFProperty(object, "BatteryStatusFlags" as CFString, kCFAllocatorDefault, 0) {
            status = percentProperty.takeRetainedValue() as! Int
            if status == 4 { status = 0 }
        }
        if let percentProperty = IORegistryEntryCreateCFProperty(object, "BatteryPercent" as CFString, kCFAllocatorDefault, 0) {
            percent = percentProperty.takeRetainedValue() as! Int
        }
        if let productProperty = IORegistryEntryCreateCFProperty(object, "Product" as CFString, kCFAllocatorDefault, 0) {
            productName = productProperty.takeRetainedValue() as! String
            if productName.contains("Trackpad") { type = "Trackpad" }
            if productName.contains("Keyboard") { type = "Keyboard" }
            if productName.contains("Mouse") { type = "MMouse" }
            if type == "hid" {
                type = getDeviceType(mac, type)
                if type.contains("Trackpad") { type = "Trackpad" }
                if type.contains("Keyboard") { type = "Keyboard" }
                if type.contains("Mouse") { type = "MMouse" }
            } else {
                productName = getDeviceName(mac, productName)
            }
        }
        if !productName.contains("Internal"){
            AirBatteryModel.updateDevice(BatteryDevice(deviceID: mac, deviceType: type, deviceName: productName, batteryLevel: percent, isCharging: status, parentName: deviceName, lastUpdate: lastUpdate))
        }
    }

    func getMagicBattery() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t
        if #available(macOS 12.0, *) {
            masterPort = kIOMainPortDefault
        } else {
            masterPort = kIOMasterPortDefault
        }
        let matchingDict : CFDictionary = IOServiceMatching("AppleDeviceManagementHIDEventService")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)

        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }

    func getOldMagicKeyboard() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t
        if #available(macOS 12.0, *) { masterPort = kIOMainPortDefault } else { masterPort = kIOMasterPortDefault }
        let matchingDict : CFDictionary = IOServiceMatching("AppleBluetoothHIDKeyboard")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }

    func getOldMagicTrackpad() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t
        if #available(macOS 12.0, *) { masterPort = kIOMainPortDefault } else { masterPort = kIOMasterPortDefault }
        let matchingDict : CFDictionary = IOServiceMatching("BNBTrackpadDevice")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }

    func getOldMagicMouse() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let masterPort: mach_port_t
        if #available(macOS 12.0, *) { masterPort = kIOMainPortDefault } else { masterPort = kIOMasterPortDefault }
        let matchingDict : CFDictionary = IOServiceMatching("BNBMouseDevice")
        let kernResult = IOServiceGetMatchingServices(masterPort, matchingDict, &serialPortIterator)
        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 { readMagicBattery(object: object) }
            } while object != 0
            IOObjectRelease(object)
        }
        IOObjectRelease(serialPortIterator)
    }

    func getIOBTBattery() {
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices {
                if device.isConnected() {
                    guard let name = device.name, let address = device.addressString else { continue }

                    let now = Date().timeIntervalSince1970
                    let type = getDeviceType(address.replacingOccurrences(of: "-", with: ":").uppercased(), "general_bt")

                    if device.isMultiBatteryDevice {
                        let caseLevel = device.batteryPercentCase
                        let leftLevel = device.batteryPercentLeft
                        let rightLevel = device.batteryPercentRight

                        if caseLevel == 0 && leftLevel == 0 && rightLevel == 0 {
                            continue
                        }

                        if caseLevel > 0 && caseLevel <= 100 {
                            AirBatteryModel.updateDevice(BatteryDevice(deviceID: address + "_case", deviceType: "ap_case", deviceName: name + " (Case)".local, batteryLevel: Int(caseLevel), isCharging: 0, lastUpdate: now))
                        }
                        if leftLevel > 0 && leftLevel <= 100 {
                            AirBatteryModel.updateDevice(BatteryDevice(deviceID: address + "_left", deviceType: "ap_pod_left", deviceName: name + " 🄻", batteryLevel: Int(leftLevel), isCharging: 0, parentName: name + " (Case)".local, lastUpdate: now))
                        }
                        if rightLevel > 0 && rightLevel <= 100 {
                            AirBatteryModel.updateDevice(BatteryDevice(deviceID: address + "_right", deviceType: "ap_pod_right", deviceName: name + " 🅁", batteryLevel: Int(rightLevel), isCharging: 0, parentName: name + " (Case)".local, lastUpdate: now))
                        }

                        let validLevels = [leftLevel, rightLevel].filter { $0 > 0 && $0 <= 100 }
                        if !validLevels.isEmpty {
                            let averageLevel = validLevels.reduce(0, +) / validLevels.count
                            let userInfo = ["name": name, "level": averageLevel] as [String : Any]
                            NotificationCenter.default.post(name: .didUpdateAirPodsBattery, object: nil, userInfo: userInfo)
                        }

                    } else if let battery = device.batteryPercentSingle as? Int, battery > 0 && battery <= 100 {
                        AirBatteryModel.updateDevice(BatteryDevice(deviceID: address, deviceType: type, deviceName: name, batteryLevel: battery, isCharging: 0, lastUpdate: now))
                    }
                }
            }
        }
    }
}

extension IOBluetoothDevice {
    func getValue(forKey: String) -> Any? {
        if self.responds(to: Selector((forKey))) {
            return self.value(forKey: forKey)
        }
        return nil
    }

    var isAppleDevice: Bool {
        return self.getValue(forKey: "isAppleDevice") as? Bool ?? false
    }

    var isMultiBatteryDevice: Bool {
        return self.getValue(forKey: "isMultiBatteryDevice") as? Bool ?? false
    }

    var batteryPercentSingle: Int {
        return self.getValue(forKey: "batteryPercentSingle") as? Int ?? 0
    }

    var batteryPercentCase: Int {
        return self.getValue(forKey: "batteryPercentCase") as? Int ?? 0
    }

    var batteryPercentLeft: Int {
        return self.getValue(forKey: "batteryPercentLeft") as? Int ?? 0
    }

    var batteryPercentRight: Int {
        return self.getValue(forKey: "batteryPercentRight") as? Int ?? 0
    }
}