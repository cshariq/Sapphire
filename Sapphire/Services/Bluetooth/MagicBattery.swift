//
//  MagicBattery.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2024/2/9.
//

import SwiftUI
import Foundation
import IOBluetooth

extension Notification.Name {
    static let bluetoothBatteryLevelsDidUpdate = Notification.Name("bluetoothBatteryLevelsDidUpdate")
}

struct SPParsedInfo {
    let name: String
    let minorType: String
    let batteryLevelLeft: String?
    let batteryLevelRight: String?
    let batteryLevelCase: String?
}

class SPBluetoothDataModel {
    static var shared: SPBluetoothDataModel = SPBluetoothDataModel()

    var data: String = "{}"

    var deviceMap: [String: SPParsedInfo] = [:]

    private var lastRefreshTime: Date?
    private var waiters: [(String?) -> Void] = []
    private let refreshQueue = DispatchQueue(label: "com.sapphire.sp_refresh", qos: .utility)
    private static let processTimeout = 10

    func refeshData(force: Bool = false, maxAge: TimeInterval = 5 * 60, completion: @escaping (String) -> Void, error: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        if !force, let lastRefreshTime, Date().timeIntervalSince(lastRefreshTime) < maxAge {
            completion(data)
            return
        }

        waiters.append { result in
            if let result { completion(result) } else { error?() }
        }
        guard waiters.count == 1 else { return }

        refreshQueue.async {
            let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"], timeout: Self.processTimeout)
            DispatchQueue.main.async {
                if let result {
                    self.data = result
                    self.parseJSONToMap()
                    self.lastRefreshTime = Date()
                }
                let pending = self.waiters
                self.waiters.removeAll()
                pending.forEach { $0(result) }
            }
        }
    }

    private func parseJSONToMap() {
        guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8), options: []) as? [String: Any],
              let rawDataType = json["SPBluetoothDataType"] as? [[String: Any]],
              let firstSection = rawDataType.first else { return }

        var newMap: [String: SPParsedInfo] = [:]
        let collections = ["device_connected", "device_not_connected"]

        for key in collections {
            if let devices = firstSection[key] as? [[String: Any]] {
                for entry in devices {
                    guard let name = entry.keys.first,
                          let details = entry[name] as? [String: Any],
                          let address = details["device_address"] as? String else { continue }

                    let normalizedMac = address.replacingOccurrences(of: "-", with: ":").uppercased()

                    let info = SPParsedInfo(
                        name: name,
                        minorType: details["device_minorType"] as? String ?? "general_bt",
                        batteryLevelLeft: details["device_batteryLevelLeft"] as? String,
                        batteryLevelRight: details["device_batteryLevelRight"] as? String,
                        batteryLevelCase: details["device_batteryLevelCase"] as? String
                    )
                    newMap[normalizedMac] = info
                }
            }
        }
        self.deviceMap = newMap
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
        guard self.readBTDevice else { return }

        self.getIOBTBattery()
        self.getMagicBattery()

        DispatchQueue.global(qos: .background).async {
            self.getOldMagicKeyboard()
            self.getOldMagicTrackpad()
            self.getOldMagicMouse()
        }
    }

    func getDeviceName(_ mac: String, _ def: String) -> String {
        return SPBluetoothDataModel.shared.deviceMap[mac]?.name ?? def
    }

    func getDeviceType(_ mac: String, _ def: String) -> String {
        return SPBluetoothDataModel.shared.deviceMap[mac]?.minorType ?? def
    }

    func getDeviceTypeWithPID(_ pid: String, _ def: String) -> String {
        return def
    }

    func readMagicBattery(object: io_object_t) {
        var mac = ""
        var type = "hid"
        var status = 0
        var percent = 0
        var productName = ""
        let lastUpdate = Date().timeIntervalSince1970

        if let address = IORegistryEntryCreateCFProperty(object, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            mac = address.replacingOccurrences(of:"-", with:":").uppercased()
        }
        if let flags = IORegistryEntryCreateCFProperty(object, "BatteryStatusFlags" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
            status = flags
            if status == 4 { status = 0 }
        }
        if let level = IORegistryEntryCreateCFProperty(object, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
            percent = level
        }
        if let product = IORegistryEntryCreateCFProperty(object, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            productName = product

            if productName.contains("Trackpad") { type = "Trackpad" }
            else if productName.contains("Keyboard") { type = "Keyboard" }
            else if productName.contains("Mouse") { type = "MMouse" }

            if type == "hid" {
                let lookupType = getDeviceType(mac, type)
                if lookupType.contains("Trackpad") { type = "Trackpad" }
                else if lookupType.contains("Keyboard") { type = "Keyboard" }
                else if lookupType.contains("Mouse") { type = "MMouse" }
            } else {
                productName = getDeviceName(mac, productName)
            }
        }
        if !productName.contains("Internal"){
            DispatchQueue.main.async {
                AccessoryBatteryStore.updateDevice(BatteryDevice(deviceID: mac, deviceType: type, deviceName: productName, batteryLevel: percent, isCharging: status, parentName: self.deviceName, lastUpdate: lastUpdate))
            }
        }
    }

    func getMagicBattery() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let matchingDict : CFDictionary = IOServiceMatching("AppleDeviceManagementHIDEventService")
        let kernResult = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &serialPortIterator)

        if KERN_SUCCESS == kernResult {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 {
                    readMagicBattery(object: object)
                    IOObjectRelease(object)
                }
            } while object != 0
        }
        IOObjectRelease(serialPortIterator)
    }

    func getOldMagicKeyboard() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let matchingDict : CFDictionary = IOServiceMatching("AppleBluetoothHIDKeyboard")
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &serialPortIterator) == KERN_SUCCESS {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 {
                    readMagicBattery(object: object)
                    IOObjectRelease(object)
                }
            } while object != 0
        }
        IOObjectRelease(serialPortIterator)
    }

    func getOldMagicTrackpad() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let matchingDict : CFDictionary = IOServiceMatching("BNBTrackpadDevice")
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &serialPortIterator) == KERN_SUCCESS {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 {
                    readMagicBattery(object: object)
                    IOObjectRelease(object)
                }
            } while object != 0
        }
        IOObjectRelease(serialPortIterator)
    }

    func getOldMagicMouse() {
        var serialPortIterator = io_iterator_t()
        var object : io_object_t
        let matchingDict : CFDictionary = IOServiceMatching("BNBMouseDevice")
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &serialPortIterator) == KERN_SUCCESS {
            repeat {
                object = IOIteratorNext(serialPortIterator)
                if object != 0 {
                    readMagicBattery(object: object)
                    IOObjectRelease(object)
                }
            } while object != 0
        }
        IOObjectRelease(serialPortIterator)
    }

    func getIOBTBattery() {
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices {
                if device.isConnected() {
                    guard let name = device.name, let address = device.addressString else { continue }

                    let now = Date().timeIntervalSince1970
                    let normalizedAddress = address.replacingOccurrences(of: "-", with: ":").uppercased()
                    let type = getDeviceType(normalizedAddress, "general_bt")

                    if device.isMultiBatteryDevice {
                        let caseLevel = device.batteryPercentCase
                        let leftLevel = device.batteryPercentLeft
                        let rightLevel = device.batteryPercentRight

                        if caseLevel == 0 && leftLevel == 0 && rightLevel == 0 {
                            continue
                        }

                        if caseLevel > 0 && caseLevel <= 100 {
                            AccessoryBatteryStore.updateDevice(BatteryDevice(deviceID: address + "_case", deviceType: "ap_case", deviceName: name + " (Case)".local, batteryLevel: Int(caseLevel), isCharging: 0, lastUpdate: now))
                        }
                        if leftLevel > 0 && leftLevel <= 100 {
                            AccessoryBatteryStore.updateDevice(BatteryDevice(deviceID: address + "_left", deviceType: "ap_pod_left", deviceName: name + " 🄻", batteryLevel: Int(leftLevel), isCharging: 0, parentName: name + " (Case)".local, lastUpdate: now))
                        }
                        if rightLevel > 0 && rightLevel <= 100 {
                            AccessoryBatteryStore.updateDevice(BatteryDevice(deviceID: address + "_right", deviceType: "ap_pod_right", deviceName: name + " 🅁", batteryLevel: Int(rightLevel), isCharging: 0, parentName: name + " (Case)".local, lastUpdate: now))
                        }

                        let validLevels = [leftLevel, rightLevel].filter { $0 > 0 && $0 <= 100 }
                        if !validLevels.isEmpty {
                            let averageLevel = validLevels.reduce(0, +) / validLevels.count
                            let userInfo = ["name": name, "address": address, "level": averageLevel] as [String : Any]
                            NotificationCenter.default.post(name: .bluetoothBatteryLevelsDidUpdate, object: nil, userInfo: userInfo)
                        }

                    } else if case let battery = device.batteryPercentSingle, battery > 0 && battery <= 100 {
                        AccessoryBatteryStore.updateDevice(BatteryDevice(deviceID: address, deviceType: type, deviceName: name, batteryLevel: battery, isCharging: 0, lastUpdate: now))
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