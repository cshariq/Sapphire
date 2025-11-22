//
//  IDeviceBattery.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2024/2/6.
//

import SwiftUI
import Foundation

class IDeviceBattery {
    static let shared: IDeviceBattery = IDeviceBattery()

    @AppStorage("readPencil") var readPencil = false
    @AppStorage("readIDevice") var readIDevice = true
    @AppStorage("updateInterval") var updateInterval = 1

    private let scanQueue = DispatchQueue(label: "com.sapphire.idevice_scan", qos: .utility)

    func startScan() {
        scanDevices()
    }

    @objc func scanDevices() {
        scanQueue.async {
            if !self.readIDevice { return }
            self.getIDeviceBattery()
        }
    }

    func getPencil(d: BatteryDevice, type: String = "") {
        if d.deviceType == "iPad" && readPencil {
            Thread.detachNewThread {
                if let result = process(path: "/bin/bash", arguments: ["\(Bundle.main.resourcePath!)/logReader.sh", "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevicesyslog", type, d.deviceID], timeout: 11 * self.updateInterval) {
                    if let json = try? JSONSerialization.jsonObject(with: Data(result.utf8), options: []) as? [String: Any] {
                        if let level = json["level"] as? Int, let model = json["model"] as? String, let vendor = json["vendor"] as? String {
                            let status = (json["status"] as? Int) ?? 0
                            print("[IDeviceBattery]  Found Pencil via \(d.deviceName): Level \(level)%, Charging: \(status), Model: \(model)")
                            DispatchQueue.main.async {
                                AirBatteryModel.updateDevice(BatteryDevice(deviceID: "Pencil_"+d.deviceID, deviceType: vendor == "Apple" ? "ApplePencil" : "Pencil", deviceName: vendor == "Apple" ? "Apple Pencil".local : "Pencil".local, deviceModel: model, batteryLevel: level, isCharging: status, parentName: d.deviceName, lastUpdate: Date().timeIntervalSince1970))
                            }
                        }
                    }
                }
            }
        }
    }

    func getIDeviceBattery() {
        if let result = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevice_id", arguments: ["-n"]) {
            let ids = result.components(separatedBy: .newlines).filter { !$0.isEmpty }
            print("[IDeviceBattery] Found network devices: \(ids)")
            for id in ids {
                if shouldScan(id: id) {
                    writeBatteryInfo(id, "-n")
                    if let d = AirBatteryModel.getByID(id) { getPencil(d: d, type: "-n") }
                }
            }
        }

        if let result = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevice_id", arguments: ["-l"]) {
            let ids = result.components(separatedBy: .newlines).filter { !$0.isEmpty }
            print("[IDeviceBattery] Found USB devices: \(ids)")
            for id in ids {
                if shouldScan(id: id) {
                    writeBatteryInfo(id, "")
                    if let d = AirBatteryModel.getByID(id) { getPencil(d: d) }
                }
            }
        }
    }

    private func shouldScan(id: String) -> Bool {
        if let d = AirBatteryModel.getByID(id) {
            if (Date().timeIntervalSince1970 - d.lastUpdate) < Double(60 * updateInterval) {
                return false
            }
        }
        return true
    }

    func writeBatteryInfo(_ id: String, _ connectType: String) {
        print("[IDeviceBattery] Querying battery info for device ID: \(id)")
        let lastUpdate = Date().timeIntervalSince1970
        if connectType == "" { _ = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/wificonnection", arguments: ["-u", id, "true"]) }

        if let deviceInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id]){
            let i = deviceInfo.components(separatedBy: .newlines)
            if let deviceName = i.filter({ $0.contains("DeviceName") }).first?.components(separatedBy: ": ").last,
               let model = i.filter({ $0.contains("ProductType") }).first?.components(separatedBy: ": ").last,
               let type = i.filter({ $0.contains("DeviceClass") }).first?.components(separatedBy: ": ").last {

                if let batteryInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id, "-q", "com.apple.mobile.battery"]) {
                    let b = batteryInfo.components(separatedBy: .newlines)
                    if let levelStr = b.filter({ $0.contains("BatteryCurrentCapacity") }).first?.components(separatedBy: ": ").last,
                       let level = Int(levelStr),
                       let charging = b.filter({ $0.contains("BatteryIsCharging") }).first!.components(separatedBy: ": ").last {

                        print("[IDeviceBattery] Parsed iDevice: \(deviceName) (\(type)), Level: \(level)%, Charging: \(charging)")
                        DispatchQueue.main.async {
                            AirBatteryModel.updateDevice(BatteryDevice(deviceID: id, deviceType: type, deviceName: deviceName, deviceModel: model, batteryLevel: level, isCharging: Bool(charging)! ? 1 : 0, lastUpdate: lastUpdate))
                        }

                        if let watchInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/comptest", arguments: [id]) {
                            let w = watchInfo.components(separatedBy: .newlines)
                            if let watchID = w.filter({ $0.contains("Checking watch") }).first?.components(separatedBy: " ").last,
                               let watchName = w.filter({ $0.contains("DeviceName") }).first?.components(separatedBy: ": ").last,
                               let watchModel = w.filter({ $0.contains("ProductType") }).first?.components(separatedBy: ": ").last,
                               let watchLevelStr = w.filter({ $0.contains("BatteryCurrentCapacity") }).first?.components(separatedBy: ": ").last,
                               let watchLevel = Int(watchLevelStr),
                               let watchCharging = w.filter({ $0.contains("BatteryIsCharging") }).first?.components(separatedBy: ": ").last {

                                print("[IDeviceBattery] Parsed Apple Watch via \(deviceName): \(watchName), Level: \(watchLevel)%, Charging: \(watchCharging)")
                                DispatchQueue.main.async {
                                    AirBatteryModel.updateDevice(BatteryDevice(deviceID: watchID, deviceType: "Watch", deviceName: watchName, deviceModel: watchModel, batteryLevel: watchLevel, isCharging: Bool(watchCharging)! ? 1 : 0, parentName: deviceName, lastUpdate: lastUpdate))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}