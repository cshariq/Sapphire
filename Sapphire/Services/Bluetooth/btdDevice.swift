//
//  btdDevice.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2024/2/9.
//

import Foundation

let fd = FileManager.default
let ud = UserDefaults.standard

struct btdDevice: Codable, Equatable {
    let time: Date
    let vid: String
    let pid: String
    let type: String
    let mac: String
    let name: String
    let level: Int
}

struct BatteryDevice: Hashable, Codable {
    var hasBattery: Bool = true
    var deviceID: String
    var deviceType: String
    var deviceName: String
    var deviceModel: String?
    var batteryLevel: Int
    var isCharging: Int
    var isCharged: Bool = false
    var isPaused: Bool = false
    var acPowered: Bool = false
    var isHidden: Bool = false
    var lowPower: Bool = false
    var parentName: String = ""
    var lastUpdate: Double
    var realUpdate: Double = 0.0

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hasBattery)
        hasher.combine(deviceID)
        hasher.combine(deviceType)
        hasher.combine(deviceName)
        hasher.combine(deviceModel)
        hasher.combine(batteryLevel)
        hasher.combine(isCharging)
        hasher.combine(isCharged)
        hasher.combine(isPaused)
        hasher.combine(acPowered)
        hasher.combine(isHidden)
        hasher.combine(lowPower)
        hasher.combine(lastUpdate)
        hasher.combine(realUpdate)
        hasher.combine(parentName)
    }
}

enum AirBatteryModel {
    private static let devicesLock = NSLock()
    private static var devices: [BatteryDevice] = []
    static let machineType = ud.string(forKey: "machineType") ?? "Mac"
    static let key = "com.lihaoyun6.AirBattery.widget"

    static func updateDevice(_ device: BatteryDevice) {
        devicesLock.lock()
        defer { devicesLock.unlock() }

        if let index = devices.firstIndex(where: {
            $0.deviceID == device.deviceID || $0.deviceName == device.deviceName
        }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    static func hideDevice(_ name: String) {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        for index in devices.indices where devices[index].deviceName == name {
            devices[index].isHidden = true
        }
    }

    static func unhideDevice(_ name: String) {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        for index in devices.indices where devices[index].deviceName == name {
            devices[index].isHidden = false
        }
    }

    private static func devicesSnapshot() -> [BatteryDevice] {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return devices
    }

    static func getBlackList() -> [BatteryDevice] {
        let blackList = Set(ud.stringArray(forKey: "blackList") ?? [])
        return getAll(noFilter: true).filter { blackList.contains($0.deviceName) }
    }

    static func getAll(reverse: Bool = false, noFilter: Bool = false) -> [BatteryDevice] {
        let thisMac = ud.string(forKey: "deviceName")
        let disappearMinutes = max(ud.object(forKey: "disappearTime") as? Int ?? 20, 1)
        let blackList = Set(ud.stringArray(forKey: "blackList") ?? [])
        let blockedItems = Set(ud.stringArray(forKey: "blockedDevices") ?? [])
        let whitelistMode = ud.bool(forKey: "whitelistMode")
        let now = Date().timeIntervalSince1970

        let snapshot = devicesSnapshot()
        var list = (reverse ? Array(snapshot.reversed()) : snapshot).filter {
            now - $0.lastUpdate < Double(disappearMinutes * 60)
        }
        if !noFilter {
            list.removeAll { blackList.contains($0.deviceName) || $0.isHidden }
        }
        list.removeAll {
            let isListed = blockedItems.contains($0.deviceName)
            return whitelistMode ? !isListed : isListed
        }

        let childrenByParent = Dictionary(grouping: list.filter { !$0.parentName.isEmpty }, by: \.parentName)
        var ordered: [BatteryDevice] = []
        var inserted = Set<BatteryDevice>()

        func appendOnce(_ device: BatteryDevice) {
            if inserted.insert(device).inserted {
                ordered.append(device)
            }
        }

        for device in list where device.parentName == thisMac {
            appendOnce(device)
        }
        for device in list where device.parentName.isEmpty {
            appendOnce(device)
            for child in childrenByParent[device.deviceName] ?? [] {
                appendOnce(child)
            }
        }
        for device in list {
            appendOnce(device)
        }
        return ordered
    }

    static func getByName(_ name: String) -> BatteryDevice? {
        getAll(noFilter: true).first { $0.deviceName == name }
    }

    static func getByID(_ id: String) -> BatteryDevice? {
        getAll(noFilter: true).first { $0.deviceID == id }
    }

    static func singleDeviceName() -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier
        if bundleIdentifier == key {
            guard let documents = fd.urls(for: .documentDirectory, in: .userDomainMask).first else { return "" }
            return (try? String(
                contentsOf: documents.appendingPathComponent("singleDeviceName"),
                encoding: .utf8
            )) ?? ""
        }

        guard let library = fd.urls(for: .libraryDirectory, in: .userDomainMask).first else { return "" }
        let url = library.appendingPathComponent("Containers/\(key)/Data/Documents/singleDeviceName")
        try? fd.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ud.string(forKey: "deviceOnWidget")?.write(to: url, atomically: true, encoding: .utf8)
        return ""
    }

    static func getJsonURL() -> URL {
        if Bundle.main.bundleIdentifier == key,
           let documents = fd.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent("data.json")
        }
        let library = fd.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fd.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return library.appendingPathComponent("Containers/\(key)/Data/Documents/data.json")
    }

    static func writeData() {
        let revList = ud.object(forKey: "revListOnWidget") as? Bool ?? false

        var devices = getAll(reverse: revList)
        let ibStatus = InternalBattery.status
        if ibStatus.hasBattery { devices.insert(ib2ab(ibStatus), at: 0) }
        do {
            let jsonData = try JSONEncoder().encode(devices)
            let url = getJsonURL()
            try fd.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jsonData.write(to: url, options: .atomic)
        } catch {
            print("Write JSON error：\(error)")
        }
    }

    static func readData(url: URL = getJsonURL()) -> [BatteryDevice] {
        guard fd.fileExists(atPath: url.path) else { return [] }
        do {
            let jsonData = try Data(contentsOf: url)
            return try JSONDecoder().decode([BatteryDevice].self, from: jsonData)
        } catch {
            print("Read JSON error：\(error)")
        }
        return []
    }

    static func ncGetAll(url: URL, fromWidget: Bool = false) -> [BatteryDevice] {
        let disappearTime = max(ud.object(forKey: "disappearTime") as? Int ?? 20, 1)
        let devices = readData(url: url)
        let now = Date().timeIntervalSince1970
        let localDeviceNames = Set((fromWidget ? readData() : getAll()).map(\.deviceName))
        var list = devices.filter {
            now - $0.lastUpdate < Double(disappearTime * 60)
                && !localDeviceNames.contains($0.deviceName)
        }
        if let first = devices.first, !list.contains(first), !list.isEmpty {
            list.insert(first, at: 0)
        }
        if list.count == 1, list.first?.hasBattery == false { return [] }
        return list
    }

    static func checkIfBlocked(name: String) -> Bool {
        let whitelistMode = ud.bool(forKey: "whitelistMode")
        let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        if (blockedItems.contains(name) && !whitelistMode) || (!blockedItems.contains(name) && whitelistMode) {
            return true
        }
        return false
    }
}