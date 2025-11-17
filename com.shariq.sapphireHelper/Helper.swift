//
//  Helper.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02
//

import Foundation
import os.log
import CoreAudio

fileprivate enum IOPMPrivate {
    static let kIOPMSleepDisabledKey = "SleepDisabled" as CFString

    private static let IOPMSetSystemPowerSetting: (@convention(c) (CFString, CFTypeRef) -> IOReturn)? = {
        let framework = Bundle(path: "/System/Library/Frameworks/IOKit.framework")
        guard let symbol = framework?.executableURL.flatMap({ dlopen($0.path, RTLD_LAZY) }).flatMap({ dlsym($0, "IOPMSetSystemPowerSetting") }) else {
            return nil
        }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString, CFTypeRef) -> IOReturn).self)
    }()

    static func setSleepDisabled(_ disabled: Bool) -> IOReturn {
        guard let function = IOPMSetSystemPowerSetting else {
            os_log("IOPMSetSystemPowerSetting symbol not found.")
            return kIOReturnUnsupported
        }
        let cfValue: CFTypeRef = disabled ? (kCFBooleanTrue as CFTypeRef) : (kCFBooleanFalse as CFTypeRef)
        return function(kIOPMSleepDisabledKey, cfValue)
    }
}

class Helper: NSObject, HelperProtocol {

    private let logger = Logger(subsystem: "com.shariq.sapphireHelper", category: "Helper")
    var client: InstallationClient?
    private let smc: SMC?

    private var keyChargeControl: String?
    private var keyDischargeControl: String?
    private var keyMagsafeLED: String?

    override init() {
        self.smc = SMC()
        super.init()

        if self.smc == nil {
            logger.critical("FATAL ERROR: Could not establish connection to SMC. The helper will not function.")
        } else {
            logger.log("SMC connection successful. Probing for keys...")
            probeForKeys()
        }
    }

    deinit {
        logger.log("Helper deinitializing and closing SMC connection.")
        if let smc = smc, let fanCount = smc.getValue("FNum") {
            for i in 0..<Int(fanCount) {
                logger.log("Reverting fan \(i) to automatic mode as helper is deinitializing.")
                _ = smc.setFanMode(i, mode: .automatic)
            }
        }
        _ = smc?.close()
    }

    private func probeForKeys() {
        guard let smc = self.smc else { return }
        let allKeys = Set(smc.getAllKeys())

        if allKeys.contains("CHCS") { keyChargeControl = "CHCS" }
        else if allKeys.contains("CHTE") { keyChargeControl = "CHTE" }
        else if allKeys.contains("CH0B") { keyChargeControl = "CH0B" }

        if allKeys.contains("CHIE") { keyDischargeControl = "CHIE" }
        else if allKeys.contains("CH0I") { keyDischargeControl = "CH0I" }

        if allKeys.contains("ACLC") { keyMagsafeLED = "ACLC" }

        logger.log("""
        Probe Complete:
        - Charge Control Key: \(self.keyChargeControl ?? "Not Found")
        - Discharge Control Key: \(self.keyDischargeControl ?? "Not Found")
        - MagSafe LED Key: \(self.keyMagsafeLED ?? "Not Found")
        """)
    }

    // MARK: - Battery Functions

    func setChargeLimit(_ limit: Int, reply: @escaping (Error?) -> Void) {
        let data = Data([UInt8(max(20, min(100, limit)))])
        let result = smc?.writeData("BCLM", data: data)
        reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write BCLM."))
    }

    func enableCharging(_ enabled: Bool, reply: @escaping (Error?) -> Void) {
        logger.debug("[SapphireHelper] Received command: enableCharging(\(enabled))")

        guard let chargeKey = keyChargeControl else {
            logger.error("[SapphireHelper] ERROR: No charge control key found. Cannot execute enableCharging.")
            reply(makeError(code: .smcWriteFailed, description: "No charge control key found for this Mac."))
            return
        }

        let data: Data
        switch chargeKey {
        case "CHCS", "CHTE": data = Data(enabled ? [0x00, 0x00, 0x00, 0x00] : [0x01, 0x00, 0x00, 0x00])
        case "CH0B":
            data = Data(enabled ? [0x00] : [0x02])
            if smc?.getAllKeys().contains("CH0C") ?? false { _ = smc?.writeData("CH0C", data: data) }
        default:
            logger.error("[SapphireHelper] ERROR: Unknown charge key '\(chargeKey)'.")
            reply(makeError(code: .smcWriteFailed, description: "Unknown charge key."))
            return
        }

        let hexString = data.map { String(format: "%02x", $0) }.joined()
        logger.debug("[SapphireHelper] Writing to SMC Key '\(chargeKey)' with data: 0x\(hexString)")

        let result = smc?.writeData(chargeKey, data: data)
        if result == kIOReturnSuccess {
            logger.debug("[SapphireHelper] SMC Write SUCCESS for key '\(chargeKey)'.")
        } else {
            logger.error("[SapphireHelper] SMC Write FAILED for key '\(chargeKey)' with error code: \(String(describing: result)).")
        }

        reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write charge key '\(chargeKey)'."))
    }

    func setDischarge(_ discharging: Bool, reply: @escaping (Error?) -> Void) {
        logger.debug("[SapphireHelper] Received command: setDischarge(\(discharging))")

        guard let dischargeKey = keyDischargeControl else {
            logger.error("[SapphireHelper] ERROR: No discharge control key found. Cannot execute setDischarge.")
            reply(discharging ? makeError(code: .smcWriteFailed, description: "No discharge control key found.") : nil)
            return
        }

        let data: Data
        switch dischargeKey {
        case "CHIE": data = Data(discharging ? [0x08] : [0x00])
        case "CH0I": data = Data(discharging ? [0x01] : [0x00])
        default:
            logger.error("[SapphireHelper] ERROR: Unknown discharge key '\(dischargeKey)'.")
            reply(makeError(code: .smcWriteFailed, description: "Unknown discharge key."))
            return
        }

        let hexString = data.map { String(format: "%02x", $0) }.joined()
        logger.debug("[SapphireHelper] Writing to SMC Key '\(dischargeKey)' with data: 0x\(hexString)")

        let result = smc?.writeData(dischargeKey, data: data)
        if result == kIOReturnSuccess {
            logger.debug("[SapphireHelper] SMC Write SUCCESS for key '\(dischargeKey)'.")
        } else {
            logger.error("[SapphireHelper] SMC Write FAILED for key '\(dischargeKey)' with error code: \(String(describing: result)).")
        }

        reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write discharge key '\(dischargeKey)'."))
    }

    func setMagSafeLED(color: Int, reply: @escaping (Error?) -> Void) {
        guard let ledKey = keyMagsafeLED else {
            reply(makeError(code: .smcWriteFailed, description: "MagSafe LED key not found."))
            return
        }
        let result = smc?.writeData(ledKey, data: Data([UInt8(color)]))
        reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write MagSafe LED key."))
    }

    func startCalibration(reply: @escaping (Error?) -> Void) {
        logger.log("Calibration cycle initiated by client. Preparing hardware.")

        let group = DispatchGroup()
        var lastError: Error?

        group.enter()
        setDischarge(false) { error in
            if let error = error {
                self.logger.error("Calibration failed at step 1 (enable adapter): \(error.localizedDescription)")
                lastError = error
            }
            group.leave()
        }
        group.wait()
        if lastError != nil { reply(lastError); return }

        group.enter()
        enableCharging(true) { error in
            if let error = error {
                self.logger.error("Calibration failed at step 2 (enable charging): \(error.localizedDescription)")
                lastError = error
            }
            group.leave()
        }
        group.wait()
        if lastError != nil { reply(lastError); return }

        group.enter()
        setChargeLimit(100) { error in
            if let error = error {
                self.logger.error("Calibration failed at step 3 (set limit to 100%): \(error.localizedDescription)")
                lastError = error
            }
            group.leave()
        }
        group.wait()

        if lastError == nil {
            logger.log("Hardware prepared for calibration charging phase.")
        }
        reply(lastError)
    }

    // MARK: - Sensor & Generic Functions
    func getAllTemperatureSensors(reply: @escaping ([String]) -> Void) {
        let allKeys = smc?.getAllKeys() ?? []
        reply(allKeys.filter { $0.hasPrefix("T") && $0.count == 4 })
    }
    func getAllSMCKeys(reply: @escaping ([String]) -> Void) {
        reply(smc?.getAllKeys() ?? [])
    }
    func getSensorValue(key: String, reply: @escaping (Double) -> Void) {
        reply(smc?.getValue(key) ?? -1.0)
    }
    func getBatteryTemperature(reply: @escaping (Double) -> Void) {
        reply(smc?.getValue("TB0T") ?? 0.0)
    }
    func getVersion(reply: @escaping (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A")
    }

    // MARK: - Fan Control Functions
    func getFanCount(reply: @escaping (Int) -> Void) { reply(Int(smc?.getValue("FNum") ?? 0)) }
    func getFanInfo(fanIndex: Int, reply: @escaping (FanInfo?) -> Void) {
        guard let smc = smc else { reply(nil); return }
        let name = smc.getStringValue("F\(fanIndex)ID") ?? "Fan \(fanIndex)"
        let minRPM = Int(smc.getValue("F\(fanIndex)Mn") ?? 0)
        let maxRPM = Int(smc.getValue("F\(fanIndex)Mx") ?? 0)
        let currentRPM = Int(smc.getValue("F\(fanIndex)Ac") ?? 0)
        reply(FanInfo(id: fanIndex, name: name.isEmpty ? "Fan \(fanIndex)" : name, minRPM: minRPM, maxRPM: maxRPM, currentRPM: currentRPM))
    }
    func setFanMode(fanIndex: Int, mode: UInt8, reply: @escaping (Error?) -> Void) {
        guard let smc = smc else { reply(makeError(code: .smcOpenFailed, description: "SMC not connected.")); return }
        logger.log("Request to set fan \(fanIndex) to AUTO mode.")
        let modeResult = smc.setFanMode(fanIndex, mode: .automatic)
        let speedResult = smc.setFanSpeed(fanIndex, speed: 0)
        if modeResult == kIOReturnSuccess && speedResult == kIOReturnSuccess { reply(nil) }
        else { reply(makeError(code: .smcWriteFailed, description: "Failed to set fan mode to auto.")) }
    }
    func setFanTargetSpeed(fanIndex: Int, speed: Int, reply: @escaping (Error?) -> Void) {
        guard let smc = smc else { reply(makeError(code: .smcOpenFailed, description: "SMC not connected.")); return }
        let result = smc.setFanSpeed(fanIndex, speed: speed)
        reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write F\(fanIndex)Tg."))
    }
    func setFanToConstantRPM(fanIndex: Int, speed: Int, reply: @escaping (Error?) -> Void) {
        logger.log("Request to set fan \(fanIndex) to a constant \(speed) RPM.")
        guard let smc = smc else { logger.error("SMC connection not available."); reply(makeError(code: .smcOpenFailed, description: "SMC not connected.")); return }
        logger.log("Step 1/2: Setting fan \(fanIndex) to FORCED mode.")
        let modeResult = smc.setFanMode(fanIndex, mode: .forced)
        if modeResult != kIOReturnSuccess {
            logger.error("Failed to set fan mode to forced for fan \(fanIndex). Aborting. Error code: \(modeResult)"); reply(makeError(code: .smcWriteFailed, description: "Failed to set fan to manual mode.")); return
        }
        logger.log("Step 2/2: Setting fan \(fanIndex) target speed to \(speed) RPM.")
        let speedResult = smc.setFanSpeed(fanIndex, speed: speed)
        if speedResult != kIOReturnSuccess {
            logger.error("Failed to set fan target speed for fan \(fanIndex). Error code: \(speedResult)"); _ = smc.setFanMode(fanIndex, mode: .automatic); reply(makeError(code: .smcWriteFailed, description: "Failed to write F\(fanIndex)Tg.")); return
        }
        logger.log("Successfully set fan \(fanIndex) to \(speed) RPM."); reply(nil)
    }

    func createAggregateDevice(subDeviceUIDs: [String], masterDeviceUID: String, reply: @escaping (UInt32) -> Void) {
        guard let masterDeviceID = getDeviceID(from: masterDeviceUID),
              let masterSampleRate = getSampleRate(from: masterDeviceID) else {
            reply(0)
            return
        }

        let subDeviceList = subDeviceUIDs.map { uid -> [String: Any] in
            var subDeviceDict: [String: Any] = [kAudioSubDeviceUIDKey: uid as CFString]
            if uid != masterDeviceUID { subDeviceDict[kAudioSubDeviceDriftCompensationKey] = 1 }
            return subDeviceDict
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sapphire Multi-Output",
            kAudioAggregateDeviceUIDKey: "com.shariq.sapphire.multi-output-device",
            kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
            kAudioAggregateDeviceMasterSubDeviceKey: masterDeviceUID as CFString,
            kAudioAggregateDeviceIsStackedKey: 1
        ]

        var aggregateDeviceID: AudioDeviceID = 0
        let createStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)

        guard createStatus == noErr, aggregateDeviceID != 0 else {
            reply(0)
            return
        }

        var mutableSampleRate = masterSampleRate
        var propertySize = UInt32(MemoryLayout.size(ofValue: mutableSampleRate))
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let setRateStatus = AudioObjectSetPropertyData(aggregateDeviceID, &address, 0, nil, propertySize, &mutableSampleRate)

        if setRateStatus != noErr {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            reply(0)
            return
        }

        reply(aggregateDeviceID)
    }

    func destroyAggregateDevice(id: UInt32, reply: @escaping (Bool) -> Void) {
        let status = AudioHardwareDestroyAggregateDevice(id)
        reply(status == noErr)
    }

    func setAggregateSubDeviceVolume(aggregateDeviceID: UInt32, subDeviceUID: String, volume: Float, reply: @escaping (Bool) -> Void) {
        guard let subDeviceID = findSubDeviceID(in: aggregateDeviceID, for: subDeviceUID) else {
            reply(false)
            return
        }

        var mutableVolume = volume
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(subDeviceID, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: mutableVolume)), &mutableVolume)
        reply(status == noErr)
    }

    func setAggregateSubDeviceBalance(aggregateDeviceID: UInt32, subDeviceUID: String, balance: Float, reply: @escaping (Bool) -> Void) {
        guard let subDeviceID = findSubDeviceID(in: aggregateDeviceID, for: subDeviceUID) else {
            reply(false)
            return
        }

        var mutableBalance = balance
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStereoPan, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(subDeviceID, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: mutableBalance)), &mutableBalance)
        reply(status == noErr)
    }

    func setAggregateSubDeviceDelay(aggregateDeviceID: UInt32, subDeviceUID: String, delayInSeconds: Float, reply: @escaping (Bool) -> Void) {
        guard let subDeviceID = findSubDeviceID(in: aggregateDeviceID, for: subDeviceUID),
              let sampleRate = getSampleRate(from: subDeviceID) else {
            reply(false)
            return
        }

        let delayInFrames = UInt32(Double(delayInSeconds) * sampleRate)
        var mutableDelay = delayInFrames

        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyLatency, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(subDeviceID, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: mutableDelay)), &mutableDelay)
        reply(status == noErr)
    }

    private func findSubDeviceID(in aggregateID: AudioDeviceID, for targetUID: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nil, &propertySize) == noErr, propertySize > 0 else {
            return nil
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var subDeviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &propertySize, &subDeviceIDs) == noErr else {
            return nil
        }

        for id in subDeviceIDs {
            if getDeviceUID(from: id) == targetUID {
                return id
            }
        }

        return nil
    }

    private func getDeviceUID(from deviceID: AudioDeviceID) -> String? {
        var deviceUID: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

        if AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &deviceUID) == noErr {
            return deviceUID as String
        }
        return nil
    }

    private func getDeviceID(from uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize) == noErr else { return nil }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs) == noErr else { return nil }

        for deviceID in deviceIDs {
            if getDeviceUID(from: deviceID) == uid {
                return deviceID
            }
        }
        return nil
    }

    private func getSampleRate(from deviceID: AudioDeviceID) -> Double? {
        var sampleRate: Double = 0
        var propertySize = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &sampleRate) == noErr {
            return sampleRate
        }
        return nil
    }

    func enableLowPowerMode(reply: @escaping (Error?) -> Void) {
        logger.log("Attempting to enable Low Power Mode...")
        let result = runPrivilegedCommand("/usr/bin/pmset", args: ["-a", "lowpowermode", "1"])
        if result == 0 {
            logger.log("Successfully enabled Low Power Mode.")
            reply(nil)
        } else {
            logger.error("Failed to enable Low Power Mode. Exit code: \(result)")
            reply(makeError(code: .generalError, description: "Failed to enable Low Power Mode. Exit code: \(result)"))
        }
    }

    func disableLowPowerMode(reply: @escaping (Error?) -> Void) {
        logger.log("Attempting to disable Low Power Mode...")
        let result = runPrivilegedCommand("/usr/bin/pmset", args: ["-a", "lowpowermode", "0"])
        if result == 0 {
            logger.log("Successfully disabled Low Power Mode.")
            reply(nil)
        } else {
            logger.error("Failed to disable Low Power Mode. Exit code: \(result)")
            reply(makeError(code: .generalError, description: "Failed to disable Low Power Mode. Exit code: \(result)"))
        }
    }

    private func runPrivilegedCommand(_ path: String, args: [String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    logger.error("Command failed with output: \(output)")
                }
            }

            return task.terminationStatus
        } catch {
            logger.error("Failed to run command: \(error.localizedDescription)")
            return -1
        }
    }

    func preventSystemSleep(reply: @escaping (Error?) -> Void) {
        logger.log("Client requested to prevent system sleep (clamshell mode).")
        let result = IOPMPrivate.setSleepDisabled(true)
        if result == kIOReturnSuccess {
            reply(nil)
        } else {
            let errorDescription = "Failed to disable system sleep via IOKit. Error: \(result)"
            logger.error("\(errorDescription)")
            reply(makeError(code: .generalError, description: errorDescription))
        }
    }

    func allowSystemSleep(reply: @escaping (Error?) -> Void) {
        logger.log("Client requested to allow system sleep.")
        let result = IOPMPrivate.setSleepDisabled(false)
        if result == kIOReturnSuccess {
            reply(nil)
        } else {
            let errorDescription = "Failed to enable system sleep via IOKit. Error: \(result)"
            logger.error("\(errorDescription)")
            reply(makeError(code: .generalError, description: errorDescription))
        }
    }
}