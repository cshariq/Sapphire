//
//  IDeviceBattery.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2024/2/6.
//

import Foundation

final class IDeviceBattery {
    static let shared = IDeviceBattery()

    private let defaults = UserDefaults.standard
    private let scanQueue = DispatchQueue(label: "com.sapphire.idevice-scan", qos: .utility)
    private let pencilQueue = DispatchQueue(
        label: "com.sapphire.idevice-pencil-scan",
        qos: .utility,
        attributes: .concurrent
    )
    private let stateLock = NSLock()

    private var scanIsPendingOrRunning = false
    private var pencilScansInFlight: Set<String> = []
    private var didLogMissingTools = false

    private init() {}

    private var readsPencil: Bool {
        defaults.bool(forKey: "readPencil")
    }

    private var readsIDevices: Bool {
        defaults.object(forKey: "readIDevice") as? Bool ?? true
    }

    private var updateInterval: Int {
        max(defaults.integer(forKey: "updateInterval"), 1)
    }

    func startScan() {
        scanDevices()
    }

    func scanDevices() {
        stateLock.lock()
        guard !scanIsPendingOrRunning else {
            stateLock.unlock()
            return
        }
        scanIsPendingOrRunning = true
        stateLock.unlock()

        scanQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.stateLock.lock()
                self.scanIsPendingOrRunning = false
                self.stateLock.unlock()
            }
            guard self.readsIDevices, self.validateBundledTools() else { return }
            self.scanConnectedDevices()
        }
    }

    func getPencil(d device: BatteryDevice, type connectionType: String = "") {
        guard device.deviceType == "iPad", readsPencil else { return }

        stateLock.lock()
        let inserted = pencilScansInFlight.insert(device.deviceID).inserted
        stateLock.unlock()
        guard inserted else { return }

        pencilQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.stateLock.lock()
                self.pencilScansInFlight.remove(device.deviceID)
                self.stateLock.unlock()
            }

            guard
                let scriptPath = self.resourcePath("logReader.sh"),
                let syslogPath = self.toolPath("idevicesyslog"),
                let result = process(
                    path: "/bin/bash",
                    arguments: [scriptPath, syslogPath, connectionType, device.deviceID],
                    timeout: 11 * self.updateInterval
                ),
                let json = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
                let level = json["level"] as? Int,
                let model = json["model"] as? String,
                let vendor = json["vendor"] as? String
            else { return }

            let status = json["status"] as? Int ?? 0
            let isApplePencil = vendor == "Apple"
            let pencil = BatteryDevice(
                deviceID: "Pencil_" + device.deviceID,
                deviceType: isApplePencil ? "ApplePencil" : "Pencil",
                deviceName: isApplePencil ? "Apple Pencil".local : "Pencil".local,
                deviceModel: model,
                batteryLevel: level,
                isCharging: status,
                parentName: device.deviceName,
                lastUpdate: Date().timeIntervalSince1970
            )
            DispatchQueue.main.async {
                AirBatteryModel.updateDevice(pencil)
            }
        }
    }

    private func scanConnectedDevices() {
        scanDevices(connectionFlag: "-n", label: "network")
        scanDevices(connectionFlag: "-l", label: "USB")
    }

    private func scanDevices(connectionFlag: String, label: String) {
        guard
            let identifierTool = toolPath("idevice_id"),
            let result = process(path: identifierTool, arguments: [connectionFlag])
        else { return }

        let identifiers = result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !identifiers.isEmpty else { return }

        print("[IDeviceBattery] Found \(label) devices: \(identifiers)")
        let infoConnectionFlag = connectionFlag == "-n" ? "-n" : ""
        for identifier in identifiers where shouldScan(id: identifier) {
            if let device = readBatteryInfo(identifier, connectionType: infoConnectionFlag) {
                getPencil(d: device, type: infoConnectionFlag)
            }
        }
    }

    private func shouldScan(id: String) -> Bool {
        guard let device = AirBatteryModel.getByID(id) else { return true }
        return Date().timeIntervalSince1970 - device.lastUpdate >= Double(60 * updateInterval)
    }

    private func readBatteryInfo(_ id: String, connectionType: String) -> BatteryDevice? {
        guard let infoTool = toolPath("ideviceinfo") else { return nil }
        print("[IDeviceBattery] Querying battery info for device ID: \(id)")

        if connectionType.isEmpty, let connectionTool = toolPath("wificonnection") {
            _ = process(path: connectionTool, arguments: ["-u", id, "true"])
        }

        let connectionArguments = connectionType.isEmpty ? [] : [connectionType]
        guard
            let deviceOutput = process(
                path: infoTool,
                arguments: connectionArguments + ["-u", id]
            )
        else { return nil }

        let deviceInfo = parsedInfo(deviceOutput)
        guard
            let deviceName = deviceInfo["DeviceName"],
            let model = deviceInfo["ProductType"],
            let type = deviceInfo["DeviceClass"],
            let batteryOutput = process(
                path: infoTool,
                arguments: connectionArguments + ["-u", id, "-q", "com.apple.mobile.battery"]
            )
        else { return nil }

        let batteryInfo = parsedInfo(batteryOutput)
        guard
            let levelText = batteryInfo["BatteryCurrentCapacity"],
            let level = Int(levelText),
            let chargingText = batteryInfo["BatteryIsCharging"]
        else { return nil }

        let charging = chargingText.caseInsensitiveCompare("true") == .orderedSame ? 1 : 0
        let lastUpdate = Date().timeIntervalSince1970
        let device = BatteryDevice(
            deviceID: id,
            deviceType: type,
            deviceName: deviceName,
            deviceModel: model,
            batteryLevel: level,
            isCharging: charging,
            lastUpdate: lastUpdate
        )
        DispatchQueue.main.async {
            AirBatteryModel.updateDevice(device)
        }

        updatePairedWatch(parentName: deviceName, deviceID: id, lastUpdate: lastUpdate)
        return device
    }

    private func updatePairedWatch(parentName: String, deviceID: String, lastUpdate: TimeInterval) {
        guard
            let companionTool = toolPath("comptest"),
            let output = process(path: companionTool, arguments: [deviceID])
        else { return }

        let info = parsedInfo(output)
        let watchID = output
            .components(separatedBy: .newlines)
            .first { $0.contains("Checking watch") }?
            .split(separator: " ")
            .last
            .map(String.init)

        guard
            let watchID,
            let watchName = info["DeviceName"],
            let watchModel = info["ProductType"],
            let watchLevelText = info["BatteryCurrentCapacity"],
            let watchLevel = Int(watchLevelText),
            let chargingText = info["BatteryIsCharging"]
        else { return }

        let watch = BatteryDevice(
            deviceID: watchID,
            deviceType: "Watch",
            deviceName: watchName,
            deviceModel: watchModel,
            batteryLevel: watchLevel,
            isCharging: chargingText.caseInsensitiveCompare("true") == .orderedSame ? 1 : 0,
            parentName: parentName,
            lastUpdate: lastUpdate
        )
        DispatchQueue.main.async {
            AirBatteryModel.updateDevice(watch)
        }
    }

    private func parsedInfo(_ output: String) -> [String: String] {
        output.components(separatedBy: .newlines).reduce(into: [:]) { result, line in
            guard let separator = line.firstIndex(of: ":") else { return }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            result[key] = value
        }
    }

    private func validateBundledTools() -> Bool {
        let requiredTools = ["idevice_id", "ideviceinfo", "idevicesyslog", "wificonnection", "comptest"]
        let areAvailable = requiredTools.allSatisfy { toolPath($0) != nil }
        if !areAvailable, !didLogMissingTools {
            didLogMissingTools = true
            print("[IDeviceBattery] Bundled libimobiledevice tools are unavailable; skipping device scan.")
        }
        return areAvailable
    }

    private func toolPath(_ name: String) -> String? {
        resourcePath("libimobiledevice/bin/\(name)", mustBeExecutable: true)
    }

    private func resourcePath(_ relativePath: String, mustBeExecutable: Bool = false) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent(relativePath, isDirectory: false)
        let path = url.path
        let isAvailable = mustBeExecutable
            ? FileManager.default.isExecutableFile(atPath: path)
            : FileManager.default.fileExists(atPath: path)
        return isAvailable ? path : nil
    }
}