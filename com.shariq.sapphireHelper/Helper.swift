//
//  Helper.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02
//

import Foundation
import os.log
import CoreAudio
import IOKit
import IOKit.ps
import CoreGraphics
import AppKit
import Security
import Darwin

private enum HelperSapphireVersionOrdering {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = ParsedVersion(lhs)
        let right = ParsedVersion(rhs)

        let major = compareInteger(left.core.first ?? "0", right.core.first ?? "0")
        if major != .orderedSame { return major }

        let minor = compareFraction(
            left.core.count > 1 ? left.core[1] : "0",
            right.core.count > 1 ? right.core[1] : "0"
        )
        if minor != .orderedSame { return minor }

        let coreCount = max(left.core.count, right.core.count)
        if coreCount > 2 {
            for index in 2..<coreCount {
                let component = compareInteger(
                    index < left.core.count ? left.core[index] : "0",
                    index < right.core.count ? right.core[index] : "0"
                )
                if component != .orderedSame { return component }
            }
        }

        return comparePrerelease(left.prerelease, right.prerelease)
    }

    static func compareBuild(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let right = rhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        for index in 0..<max(left.count, right.count) {
            let component = compareInteger(
                index < left.count ? left[index] : "0",
                index < right.count ? right[index] : "0"
            )
            if component != .orderedSame { return component }
        }
        return .orderedSame
    }

    private static func comparePrerelease(_ lhs: [String]?, _ rhs: [String]?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (left?, right?):
            for index in 0..<max(left.count, right.count) {
                guard index < left.count else { return .orderedAscending }
                guard index < right.count else { return .orderedDescending }
                let leftToken = left[index]
                let rightToken = right[index]
                if leftToken == rightToken { continue }
                let leftIsNumeric = leftToken.allSatisfy(\.isNumber)
                let rightIsNumeric = rightToken.allSatisfy(\.isNumber)
                if leftIsNumeric, rightIsNumeric {
                    return compareInteger(leftToken, rightToken)
                }
                if leftIsNumeric { return .orderedAscending }
                if rightIsNumeric { return .orderedDescending }
                return leftToken.compare(rightToken, options: [.caseInsensitive, .numeric])
            }
            return .orderedSame
        }
    }

    private static func compareInteger(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedDigits(lhs)
        let right = normalizedDigits(rhs)
        if left.count != right.count {
            return left.count > right.count ? .orderedDescending : .orderedAscending
        }
        return left.compare(right)
    }

    private static func compareFraction(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        return lhs.padding(toLength: count, withPad: "0", startingAt: 0)
            .compare(rhs.padding(toLength: count, withPad: "0", startingAt: 0))
    }

    private static func normalizedDigits(_ value: String) -> String {
        let digits = value.prefix(while: \.isNumber)
        let trimmed = digits.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private struct ParsedVersion {
        let core: [String]
        let prerelease: [String]?

        init(_ raw: String) {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("v") || value.hasPrefix("V")),
               value.dropFirst().first?.isNumber == true {
                value.removeFirst()
            }
            if let firstDigit = value.firstIndex(where: \.isNumber), firstDigit != value.startIndex {
                value = String(value[firstDigit...])
            }
            value = String(value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0])
            let pieces = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            core = pieces[0].split(separator: ".", omittingEmptySubsequences: false).map {
                let digits = $0.prefix(while: \.isNumber)
                return digits.isEmpty ? "0" : String(digits)
            }
            let tokens = pieces.count > 1
                ? pieces[1].split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "_" })
                    .map { String($0).lowercased() }
                : []
            prerelease = tokens.isEmpty ? nil : tokens
        }
    }
}

fileprivate enum IOPMPrivate {
    static let kIOPMSleepDisabledKey = "SleepDisabled" as CFString

    private static func loadSymbol<T>(_ name: String) -> T? {
        let framework = Bundle(path: "/System/Library/Frameworks/IOKit.framework")
        guard let handle = framework?.executableURL.flatMap({ dlopen($0.path, RTLD_LAZY) }),
              let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    static let IOPMSetSystemPowerSetting: (@convention(c) (CFString, CFTypeRef) -> IOReturn)? = loadSymbol("IOPMSetSystemPowerSetting")

    static let IOPMSchedulePowerEvent: (@convention(c) (CFDate?, CFString?, CFString?) -> IOReturn)? = loadSymbol("IOPMSchedulePowerEvent")
    static let IOPMCancelScheduledPowerEvent: (@convention(c) (CFDate?, CFString?, CFString?) -> IOReturn)? = loadSymbol("IOPMCancelScheduledPowerEvent")
    static let IOPMCopyScheduledPowerEvents: (@convention(c) () -> Unmanaged<CFArray>?)? = loadSymbol("IOPMCopyScheduledPowerEvents")

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
    private let updateInstallLock = NSLock()
    var client: InstallationClient?
    private let smc: SMC?
    private let sensorCacheLock = NSLock()
    private var sensorCache: [String: Double] = [:]
    private var sensorCacheTimestamp = Date.distantPast
    private let sensorCacheLifetime: TimeInterval = 0.25

    private struct AppliedFanState: Equatable {
        let mode: FanMode
        let speed: Int?
    }
    private let fanStateLock = NSLock()
    private var appliedFanStates: [Int: AppliedFanState] = [:]

    private var keyChargeControl: String?
    private var keyChargeControlSecondary: String?
    private var keyDischargeControl: String?
    private var keyDischargeControlSecondary: String?
    private var keyMagsafeLED: String?
    private var keyAdapterEnable: String?
    private var keyChargeLimit: String?

    private var keyFirmwareChargeLimitActivation: String?
    private var keyFirmwareChargeLimitUpper: String?
    private var keyFirmwareChargeLimitLower: String?
    var chargeControlMode: ChargeControlMode = .unsupported
    private var pendingFirmwareUpper: Int = 80
    private let firmwareHysteresis = 5

    private let dischargeWatchdogLock = NSLock()
    private var dischargeWatchdogTimer: Timer?
    private var dischargeWatchdogFloor: Int = 0
    private var dischargeWatchdogRechargeOnFloor: Bool = false
    private var dischargeWatchdogBypass: Bool = false

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
        stopDischargeWatchdog()
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
        let has: (String) -> Bool = { smc.keyExists($0) }

        if has("CH0B") {
            keyChargeControl = "CH0B"
            if has("CH0C") { keyChargeControlSecondary = "CH0C" }
        } else if has("CH0C") {
            keyChargeControl = "CH0C"
        } else if has("CHTE") {
            keyChargeControl = "CHTE"
        } else if has("CHCS") {
            keyChargeControl = "CHCS"
        }

        #if arch(arm64)
        let primaryDischargeKey = "CH0I"
        let secondaryDischargeKey = "CH0K"
        #else
        let primaryDischargeKey = "CH0K"
        let secondaryDischargeKey = "CH0I"
        #endif

        if has(primaryDischargeKey) {
            keyDischargeControl = primaryDischargeKey
            if has("CHIE") { keyDischargeControlSecondary = "CHIE" }
        } else if has("CH0J") {
            keyDischargeControl = "CH0J"
            if has("CHIE") { keyDischargeControlSecondary = "CHIE" }
        } else if has("CHIE") {
            keyDischargeControl = "CHIE"
        } else if has(secondaryDischargeKey) {
            keyDischargeControl = secondaryDischargeKey
        }

        if has("ACLC") { keyMagsafeLED = "ACLC" }
        else if has("BFCL") { keyMagsafeLED = "BFCL" }

        if has("BCLM") { keyChargeLimit = "BCLM" }
        if has("ACEN") { keyAdapterEnable = "ACEN" }

        if has("bfF0") && has("bfD0") && has("bfE0") {
            keyFirmwareChargeLimitActivation = "bfF0"
            keyFirmwareChargeLimitUpper = "bfD0"
            keyFirmwareChargeLimitLower = "bfE0"
        }

        if keyFirmwareChargeLimitActivation != nil && keyFirmwareChargeLimitUpper != nil && keyFirmwareChargeLimitLower != nil {
            chargeControlMode = .firmware
        } else if keyChargeControl != nil || keyChargeLimit != nil {
            chargeControlMode = .legacy
        } else {
            chargeControlMode = .unsupported
        }

        logger.log("""
        Probe Complete:
        - Charge Control Mode: \(String(describing: self.chargeControlMode))
        - Charge Control Key: \(self.keyChargeControl ?? "Not Found")\(self.keyChargeControlSecondary.map { " (+\($0))" } ?? "")
        - Discharge Control Key: \(self.keyDischargeControl ?? "Not Found")\(self.keyDischargeControlSecondary.map { " (+\($0))" } ?? "")
        - MagSafe LED Key: \(self.keyMagsafeLED ?? "Not Found")
        - Charge Limit Key (BCLM): \(self.keyChargeLimit ?? "Not Found")
        - Adapter Enable Key (ACEN): \(self.keyAdapterEnable ?? "Not Found")
        - Firmware Charge-Limit Keys: \(self.keyFirmwareChargeLimitActivation == nil ? "Not Found" : "bfF0/bfD0/bfE0")
        """)
    }

    // MARK: - Battery Functions

    func setChargeLimit(_ limit: Int, reply: @escaping (Error?) -> Void) {
        let clamped = max(10, min(100, limit))

        switch chargeControlMode {
        case .firmware:
            pendingFirmwareUpper = clamped
            reply(applyFirmwareChargeLimit(upper: clamped))
        case .legacy:
            if let limitKey = keyChargeLimit {
                let data = Data([UInt8(clamped)])
                let result = smc?.writeData(limitKey, data: data)
                reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write \(limitKey)."))
            } else if clamped >= 100 {
                enableCharging(true) { error in
                    reply(error)
                }
            } else {
                reply(makeError(code: .smcWriteFailed, description: "No charge limit key found for this Mac."))
            }
        case .unsupported:
            reply(makeError(code: .smcWriteFailed, description: "No charge control key found for this Mac."))
        }
    }

    // MARK: - Firmware Charge-Limit Control (macOS 27-era / Tahoe)

    private func readFirmwareActivation() -> UInt8? {
        guard let key = keyFirmwareChargeLimitActivation,
              let bytes = smc?.readRawBytes(key), !bytes.isEmpty else { return nil }
        return bytes[0]
    }

    private func readFirmwareLimitValue(_ key: String?) -> UInt32? {
        guard let key, let bytes = smc?.readRawBytes(key), bytes.count >= 4 else { return nil }
        return UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
    }

    private func writeFirmwareActivation(_ active: Bool) -> Error? {
        guard let key = keyFirmwareChargeLimitActivation else {
            return makeError(code: .smcWriteFailed, description: "Firmware charge-limit activation key not found.")
        }
        let value: UInt8 = active ? 0x02 : 0x00
        for attempt in 1...3 {
            _ = smc?.writeData(key, data: Data([value]))
            if readFirmwareActivation() == value { return nil }
            if attempt < 3 { usleep(20_000) }
        }
        return makeError(code: .smcWriteFailed, description: "Failed to write and verify \(key).")
    }

    private func writeFirmwareLimitValue(_ key: String, _ value: UInt32) -> Error? {
        let data = Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
        for attempt in 1...3 {
            _ = smc?.writeData(key, data: data)
            if readFirmwareLimitValue(key) == value { return nil }
            if attempt < 3 { usleep(20_000) }
        }
        return makeError(code: .smcWriteFailed, description: "Failed to write and verify \(key).")
    }

    func deactivateFirmwareChargeLimit() -> Error? {
        if let current = readFirmwareActivation(), current == 0x00 { return nil }
        return writeFirmwareActivation(false)
    }

    func applyFirmwareChargeLimit(upper: Int) -> Error? {
        guard keyFirmwareChargeLimitActivation != nil,
              let upperKey = keyFirmwareChargeLimitUpper,
              let lowerKey = keyFirmwareChargeLimitLower else {
            return makeError(code: .smcWriteFailed, description: "Firmware charge-limit keys not found.")
        }

        if upper >= 100 {
            return deactivateFirmwareChargeLimit()
        }

        let lower = max(0, upper - firmwareHysteresis)
        let currentActive = readFirmwareActivation() == 0x02
        let currentUpper = readFirmwareLimitValue(upperKey)
        let currentLower = readFirmwareLimitValue(lowerKey)
        if currentActive, currentUpper == UInt32(upper), currentLower == UInt32(lower) {
            return nil
        }

        if let error = writeFirmwareActivation(false) { return error }
        if let error = writeFirmwareLimitValue(upperKey, UInt32(upper)) { return error }
        if let error = writeFirmwareLimitValue(lowerKey, UInt32(lower)) { return error }
        return writeFirmwareActivation(true)
    }

    func enableCharging(_ enabled: Bool, reply: @escaping (Error?) -> Void) {
        logger.debug("[SapphireHelper] Received command: enableCharging(\(enabled))")

        if chargeControlMode == .firmware {
            reply(enabled ? deactivateFirmwareChargeLimit() : applyFirmwareChargeLimit(upper: pendingFirmwareUpper))
            return
        }

        guard let chargeKey = keyChargeControl else {
            if let limitKey = keyChargeLimit {
                let data = Data([enabled ? 0x64 : 0x0A])
                let hexString = data.map { String(format: "%02x", $0) }.joined()
                logger.debug("[SapphireHelper] Writing to SMC Key '\(limitKey)' with data: 0x\(hexString)")
                let result = smc?.writeData(limitKey, data: data)
                reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write \(limitKey)."))
                return
            }
            logger.error("[SapphireHelper] ERROR: No charge control key found. Cannot execute enableCharging.")
            reply(makeError(code: .smcWriteFailed, description: "No charge control key found for this Mac."))
            return
        }

        let writes: [(String, Data)]
        switch chargeKey {
        case "CH0B", "CH0C":
            var list = [(chargeKey, Data(enabled ? [0x00] : [0x02]))]
            if let secondary = keyChargeControlSecondary {
                list.append((secondary, Data(enabled ? [0x00] : [0x02])))
            }
            writes = list
        case "CHTE", "CHCS":
            writes = [(chargeKey, Data(enabled ? [0x00, 0x00, 0x00, 0x00] : [0x01, 0x00, 0x00, 0x00]))]
        default:
            logger.error("[SapphireHelper] ERROR: Unknown charge key '\(chargeKey)'.")
            reply(makeError(code: .smcWriteFailed, description: "Unknown charge key."))
            return
        }

        var succeeded = false
        for (key, data) in writes {
            let hexString = data.map { String(format: "%02x", $0) }.joined()
            logger.debug("[SapphireHelper] Writing to SMC Key '\(key)' with data: 0x\(hexString)")

            let result = smc?.writeData(key, data: data)
            if result == kIOReturnSuccess {
                succeeded = true
                logger.debug("[SapphireHelper] SMC Write SUCCESS for key '\(key)'.")
            } else {
                logger.error("[SapphireHelper] SMC Write FAILED for key '\(key)' with error code: \(String(describing: result)).")
            }
        }

        reply(succeeded ? nil : makeError(code: .smcWriteFailed, description: "Failed to write charge key '\(chargeKey)'."))
    }

    private func writeDischargeControlDirect(_ discharging: Bool) -> Error? {
        if let dischargeKey = keyDischargeControl {
            let writes: [(String, Data)]
            switch dischargeKey {
            case "CH0I", "CH0J", "CH0K":
                var list = [(dischargeKey, Data(discharging ? [0x01] : [0x00]))]
                if let secondary = keyDischargeControlSecondary {
                    list.append((secondary, Data(discharging ? [0x08] : [0x00])))
                }
                writes = list
            case "CHIE":
                writes = [(dischargeKey, Data(discharging ? [0x08] : [0x00]))]
            default:
                logger.error("[SapphireHelper] ERROR: Unknown discharge key '\(dischargeKey)'.")
                return makeError(code: .smcWriteFailed, description: "Unknown discharge key.")
            }

            var succeeded = false
            for (key, data) in writes {
                let hexString = data.map { String(format: "%02x", $0) }.joined()
                logger.debug("[SapphireHelper] Writing to SMC Key '\(key)' with data: 0x\(hexString)")

                let result = smc?.writeData(key, data: data)
                if result == kIOReturnSuccess {
                    succeeded = true
                    logger.debug("[SapphireHelper] SMC Write SUCCESS for key '\(key)'.")
                } else {
                    logger.error("[SapphireHelper] SMC Write FAILED for key '\(key)' with error code: \(String(describing: result)).")
                }
            }

            return succeeded ? nil : makeError(code: .smcWriteFailed, description: "Failed to write discharge key '\(dischargeKey)'.")
        }

        if let adapterKey = keyAdapterEnable {
            let data = Data(discharging ? [0x00] : [0x01])
            let hexString = data.map { String(format: "%02x", $0) }.joined()
            logger.debug("[SapphireHelper] Writing to SMC Key '\(adapterKey)' with data: 0x\(hexString)")

            let result = smc?.writeData(adapterKey, data: data)
            if discharging, let limitKey = keyChargeLimit {
                _ = smc?.writeData(limitKey, data: Data([0x0A]))
            }
            if result == kIOReturnSuccess {
                logger.debug("[SapphireHelper] SMC Write SUCCESS for key '\(adapterKey)'.")
            } else {
                logger.error("[SapphireHelper] SMC Write FAILED for key '\(adapterKey)' with error code: \(String(describing: result)).")
            }

            return result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write discharge key '\(adapterKey)'.")
        }

        logger.error("[SapphireHelper] ERROR: No discharge control key found. Cannot execute setDischarge.")
        return discharging ? makeError(code: .smcWriteFailed, description: "No discharge control key found.") : nil
    }

    private func startDischargeWatchdog(safetyFloor: Int, rechargeOnFloor: Bool, bypassSafetyFloor: Bool) {
        dischargeWatchdogLock.lock()
        defer { dischargeWatchdogLock.unlock() }

        dischargeWatchdogFloor = safetyFloor
        dischargeWatchdogRechargeOnFloor = rechargeOnFloor
        dischargeWatchdogBypass = bypassSafetyFloor
        guard dischargeWatchdogTimer == nil else { return }

        dischargeWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkDischargeWatchdog()
        }
    }

    private func checkDischargeWatchdog() {
        let batteryPercent = readCurrentBatteryPercentage()
        guard batteryPercent >= 0 else { return }

        let (currentFloor, rechargeOnFloor, bypass) = dischargeWatchdogLock.withLock {
            (dischargeWatchdogFloor, dischargeWatchdogRechargeOnFloor, dischargeWatchdogBypass)
        }

        if !bypass && batteryPercent <= currentFloor {
            logger.log("[SapphireHelper] Discharge watchdog: battery at \(batteryPercent)% <= floor \(currentFloor)%, forcing discharge off.")
            _ = writeDischargeControlDirect(false)

            if rechargeOnFloor {
                logger.log("[SapphireHelper] Discharge watchdog: re-enabling charging at \(batteryPercent)%.")
                _ = enableCharging(true) { _ in }
            }

            stopDischargeWatchdog()
        }
    }

    private func stopDischargeWatchdog() {
        dischargeWatchdogLock.lock()
        defer { dischargeWatchdogLock.unlock() }

        dischargeWatchdogTimer?.invalidate()
        dischargeWatchdogTimer = nil
        dischargeWatchdogFloor = 0
    }

    func setDischarge(_ discharging: Bool, safetyFloor: Int, rechargeOnFloor: Bool, bypassSafetyFloor: Bool, reply: @escaping (Error?) -> Void) {
        logger.debug("[SapphireHelper] Received command: setDischarge(\(discharging), safetyFloor: \(safetyFloor), rechargeOnFloor: \(rechargeOnFloor), bypassSafetyFloor: \(bypassSafetyFloor))")

        let error = writeDischargeControlDirect(discharging)

        if discharging && safetyFloor > 0 {
            startDischargeWatchdog(safetyFloor: safetyFloor, rechargeOnFloor: rechargeOnFloor, bypassSafetyFloor: bypassSafetyFloor)
        } else {
            stopDischargeWatchdog()
        }

        reply(error)
    }

    func setMagSafeLED(color: Int, reply: @escaping (Error?) -> Void) {
        guard let ledKey = keyMagsafeLED else {
            reply(makeError(code: .smcWriteFailed, description: "MagSafe LED key not found."))
            return
        }
        guard color >= 0, color <= 255 else {
            logger.debug("[SapphireHelper] MagSafe LED color \(color) out of range; ignoring.")
            reply(nil)
            return
        }
        let value: UInt8
        switch ledKey {
        case "BFCL":
            value = color == 3 ? 0x00 : 0x5F
        default:
            value = UInt8(color)
        }
        let result = smc?.writeData(ledKey, data: Data([value]))
        reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write MagSafe LED key."))
    }

    func startCalibration(reply: @escaping (Error?) -> Void) {
        logger.log("Calibration cycle initiated by client. Preparing hardware.")

        let group = DispatchGroup()
        var lastError: Error?

        group.enter()
        DispatchQueue.global(qos: .default).async {
            let error = self.writeDischargeControlDirect(false)
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
                self.enableCharging(true) { fallbackError in
                    if let fallbackError = fallbackError {
                        lastError = fallbackError
                    } else {
                        lastError = nil
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.wait()

        if lastError == nil {
            logger.log("Hardware prepared for calibration charging phase.")
        }
        reply(lastError)
    }

    // MARK: - Sensor & Generic Functions

    private func readCurrentBatteryPercentage() -> Int {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let powerSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, powerSource)?.takeUnretainedValue() as? [String: AnyObject] else {
            return -1
        }
        return info[kIOPSCurrentCapacityKey] as? Int ?? -1
    }

    func getAllTemperatureSensors(reply: @escaping ([String]) -> Void) {
        let allKeys = smc?.getAllKeys() ?? []
        reply(allKeys.filter { $0.hasPrefix("T") && $0.count == 4 })
    }
    func getAllSMCKeys(reply: @escaping ([String]) -> Void) {
        reply(smc?.getAllKeys() ?? [])
    }
    func getSensorValues(keys: [String], reply: @escaping (NSDictionary) -> Void) {
        guard let smc else {
            reply(NSDictionary())
            return
        }

        sensorCacheLock.lock()
        let now = Date()
        let cacheIsFresh = now.timeIntervalSince(sensorCacheTimestamp) < sensorCacheLifetime
        let uniqueKeys = Array(Set(keys))
        let missingKeys = uniqueKeys.filter { !cacheIsFresh || sensorCache[$0] == nil }
        for key in missingKeys {
            sensorCache[key] = smc.getValue(key) ?? -1.0
        }
        sensorCacheTimestamp = now

        let values = NSMutableDictionary(capacity: uniqueKeys.count)
        for key in uniqueKeys {
            values[key] = NSNumber(value: sensorCache[key] ?? -1.0)
        }
        sensorCacheLock.unlock()
        reply(values)
    }

    func getSensorValue(key: String, reply: @escaping (Double) -> Void) {
        getSensorValues(keys: [key]) { values in
            reply((values[key] as? NSNumber)?.doubleValue ?? -1.0)
        }
    }
    func getBatteryTemperature(reply: @escaping (Double) -> Void) {
        reply(readBatteryTemperature())
    }

    func readBatteryTemperature() -> Double {
        for key in ["TB0T", "TB1T", "TB2T"] {
            if let value = smc?.getValue(key), value > 0 {
                return value
            }
        }
        return 0.0
    }
    func getVersion(reply: @escaping (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A")
    }
    func getProtocolVersion(reply: @escaping (Int) -> Void) {
        reply(SapphireHelperProtocolVersion)
    }

    func installUpdate(
        newAppPath: String,
        currentAppPath: String,
        expectedVersion: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        logger.info("[Helper] installUpdate requested (new=\(newAppPath) current=\(currentAppPath))")

        guard updateInstallLock.try() else {
            completion(false, "Another Sapphire update is already being installed.")
            return
        }
        defer { updateInstallLock.unlock() }

        func fail(_ message: String) {
            logger.error("[Helper] installUpdate failed: \(message)")
            completion(false, message)
        }

        let fileManager = FileManager.default
        let newURL = URL(fileURLWithPath: newAppPath).standardizedFileURL
        let currentURL = URL(fileURLWithPath: currentAppPath).standardizedFileURL
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let currentComponents = currentURL.pathComponents
        let applicationsComponents = applicationsURL.pathComponents
        let newValues = try? newURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        let currentValues = try? currentURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard !newAppPath.isEmpty,
              newURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              fileManager.fileExists(atPath: newURL.path),
              newValues?.isSymbolicLink != true,
              !currentAppPath.isEmpty,
              currentURL.path != "/",
              newURL != currentURL,
              fileManager.fileExists(atPath: currentURL.path),
              currentValues?.isSymbolicLink != true,
              !expectedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              currentComponents.count == applicationsComponents.count + 1,
              currentComponents.prefix(applicationsComponents.count).elementsEqual(applicationsComponents),
              Bundle(url: currentURL)?.bundleIdentifier == "com.cshariq.sapphire",
              Bundle(url: newURL)?.bundleIdentifier == "com.cshariq.sapphire" else {
            fail("Invalid app paths for the update.")
            return
        }

        var currentCode: SecStaticCode?
        var requirement: SecRequirement?
        let validationFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(currentURL as CFURL, [], &currentCode) == errSecSuccess,
              let currentCode,
              SecStaticCodeCheckValidity(currentCode, validationFlags, nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
              let requirement else {
            fail("The installed Sapphire signature could not be validated.")
            return
        }

        let currentBundle = Bundle(url: currentURL)
        guard let currentVersion = currentBundle?
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !currentVersion.isEmpty else {
            fail("The installed Sapphire version could not be read.")
            return
        }
        let currentBuild = currentBundle?
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

        let parent = currentURL.deletingLastPathComponent()
        let transactionID = UUID().uuidString
        let stagingURL = parent.appendingPathComponent(".Sapphire-update-\(transactionID).app")
        do {
            try fileManager.copyItem(at: newURL, to: stagingURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            fail("Could not stage the update: \(error.localizedDescription)")
            return
        }

        var stagedCode: SecStaticCode?
        let stagedBundle = Bundle(url: stagingURL)
        let stagedVersion = stagedBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let stagedBuild = stagedBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let marketingComparison = stagedVersion.map {
            HelperSapphireVersionOrdering.compare($0, currentVersion)
        }
        let isMonotonicUpgrade = marketingComparison == .orderedDescending
            || (marketingComparison == .orderedSame
                && HelperSapphireVersionOrdering.compareBuild(stagedBuild, currentBuild) == .orderedDescending)
        guard stagedBundle?.bundleIdentifier == "com.cshariq.sapphire",
              stagedVersion == expectedVersion,
              isMonotonicUpgrade,
              SecStaticCodeCreateWithPath(stagingURL as CFURL, [], &stagedCode) == errSecSuccess,
              let stagedCode,
              SecStaticCodeCheckValidity(stagedCode, validationFlags, requirement) == errSecSuccess else {
            try? fileManager.removeItem(at: stagingURL)
            fail("The staged update must be newer than the installed signed release and match its verified version and signature.")
            return
        }

        do {
            _ = try fileManager.replaceItemAt(
                currentURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            fail("The filesystem could not transactionally install the update: \(error.localizedDescription)")
            return
        }

        logger.log("[Helper] installUpdate succeeded; new app is in place at \(currentAppPath)")
        completion(true, nil)
    }
    // MARK: - Continuity Microphone driver

    private static let halPluginDirectory = "/Library/Audio/Plug-Ins/HAL"
    private static let micDriverName = "SapphireAudioDriver.driver"
    private static let micRingDirectory = "/Library/Application Support/Sapphire"
    private static let micRingPath = "/Library/Application Support/Sapphire/ContinuityMic.ring"
    private static let micRingByteSize = 80 + 48000 * 2 * 1 * 4

    func installAudioDriver(driverBundlePath: String, reply: @escaping (Bool, String?) -> Void) {
        logger.info("[Helper] installAudioDriver requested (\(driverBundlePath))")
        let fileManager = FileManager.default

        func fail(_ message: String) {
            logger.error("[Helper] installAudioDriver failed: \(message)")
            reply(false, message)
        }

        guard !driverBundlePath.isEmpty,
              (driverBundlePath as NSString).lastPathComponent == Self.micDriverName,
              driverBundlePath.hasPrefix("/"),
              !driverBundlePath.contains(".."),
              fileManager.fileExists(atPath: driverBundlePath) else {
            fail("The audio driver path is not valid.")
            return
        }

        let destination = (Self.halPluginDirectory as NSString).appendingPathComponent(Self.micDriverName)

        do {
            if !fileManager.fileExists(atPath: Self.halPluginDirectory) {
                try fileManager.createDirectory(atPath: Self.halPluginDirectory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
            }
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.copyItem(atPath: driverBundlePath, toPath: destination)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)
        } catch {
            fail("Could not install the driver: \(error.localizedDescription)")
            return
        }

        do {
            if !fileManager.fileExists(atPath: Self.micRingDirectory) {
                try fileManager.createDirectory(atPath: Self.micRingDirectory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
            }
            if !fileManager.fileExists(atPath: Self.micRingPath) {
                fileManager.createFile(atPath: Self.micRingPath, contents: nil,
                                       attributes: [.posixPermissions: 0o666])
            }
            let handle = FileHandle(forWritingAtPath: Self.micRingPath)
            try handle?.truncate(atOffset: UInt64(Self.micRingByteSize))
            try handle?.close()
            try fileManager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: Self.micRingPath)
        } catch {
            fail("Could not prepare the microphone buffer: \(error.localizedDescription)")
            return
        }

        let status = runPrivilegedCommand("/bin/launchctl", args: ["kickstart", "-k", "system/com.apple.audio.coreaudiod"])
        if status != 0 {
            logger.warning("[Helper] coreaudiod restart returned \(status); the device may need a reboot")
        }

        logger.log("[Helper] installAudioDriver succeeded")
        reply(true, nil)
    }

    func uninstallAudioDriver(reply: @escaping (Bool, String?) -> Void) {
        let destination = (Self.halPluginDirectory as NSString).appendingPathComponent(Self.micDriverName)
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            if fileManager.fileExists(atPath: Self.micRingPath) {
                try fileManager.removeItem(atPath: Self.micRingPath)
            }
        } catch {
            reply(false, "Could not remove the driver: \(error.localizedDescription)")
            return
        }
        _ = runPrivilegedCommand("/bin/launchctl", args: ["kickstart", "-k", "system/com.apple.audio.coreaudiod"])
        logger.log("[Helper] uninstallAudioDriver succeeded")
        reply(true, nil)
    }

    func getChargeControlMode(reply: @escaping (Int) -> Void) {
        reply(chargeControlMode.rawValue)
    }

    // MARK: - Fan Control Functions
    func getFanCount(reply: @escaping (Int) -> Void) {
        guard let smc else {
            reply(0)
            return
        }

        let probed = probeFanCount(using: smc)
        if let count = smc.getValue("FNum").map({ Int($0) }), count > 0 {
            reply(max(count, probed))
            return
        }
        reply(probed)
    }

    private func probeFanCount(using smc: SMC) -> Int {
        var probed = 0
        for index in 0..<8 {
            let hasFan = smc.keyExists("F\(index)Mn")
                || smc.keyExists("F\(index)Mx")
                || smc.keyExists("F\(index)Ac")
                || smc.keyExists("F\(index)Tg")
            if hasFan {
                probed = index + 1
            } else if probed > 0 {
                break
            } else {
                break
            }
        }
        return probed
    }

    func getFanInfo(fanIndex: Int, reply: @escaping (FanInfo?) -> Void) {
        guard let smc = smc else { reply(nil); return }
        let name = smc.getStringValue("F\(fanIndex)ID")
            ?? (fanIndex == 0 ? "Left fan" : fanIndex == 1 ? "Right fan" : "Fan \(fanIndex)")
        let minRPM = Int(smc.getValue("F\(fanIndex)Mn") ?? 0)
        let maxRPM = Int(smc.getValue("F\(fanIndex)Mx") ?? 0)
        let currentRPM = Int(smc.getValue("F\(fanIndex)Ac") ?? 0)
        guard minRPM > 0 || maxRPM > 0 || currentRPM > 0 || smc.keyExists("F\(fanIndex)Ac") else {
            reply(nil)
            return
        }
        reply(FanInfo(
            id: fanIndex,
            name: name.isEmpty ? "Fan \(fanIndex)" : name,
            minRPM: minRPM,
            maxRPM: max(maxRPM, minRPM),
            currentRPM: currentRPM
        ))
    }
    func setFanMode(fanIndex: Int, mode: UInt8, reply: @escaping (Error?) -> Void) {
        guard let smc = smc else { reply(makeError(code: .smcOpenFailed, description: "SMC not connected.")); return }
        let targetMode: FanMode = mode == 0 ? .automatic : .forced
        let requestedState = AppliedFanState(mode: targetMode, speed: targetMode == .automatic ? 0 : nil)

        fanStateLock.lock()
        let alreadyApplied = appliedFanStates[fanIndex] == requestedState
        fanStateLock.unlock()
        if alreadyApplied {
            reply(nil)
            return
        }

        logger.log("Request to set fan \(fanIndex) to \(targetMode == .automatic ? "AUTO" : "FORCED") mode.")
        let modeResult = smc.setFanMode(fanIndex, mode: targetMode)
        let speedResult = targetMode == .automatic ? smc.setFanSpeed(fanIndex, speed: 0) : kIOReturnSuccess
        if modeResult == kIOReturnSuccess && speedResult == kIOReturnSuccess {
            fanStateLock.lock()
            appliedFanStates[fanIndex] = requestedState
            fanStateLock.unlock()
            reply(nil)
        } else {
            reply(makeError(code: .smcWriteFailed, description: "Failed to set fan mode."))
        }
    }
    func setFanTargetSpeed(fanIndex: Int, speed: Int, reply: @escaping (Error?) -> Void) {
        guard let smc = smc else { reply(makeError(code: .smcOpenFailed, description: "SMC not connected.")); return }
        fanStateLock.lock()
        let alreadyApplied = appliedFanStates[fanIndex] == AppliedFanState(mode: .forced, speed: speed)
        fanStateLock.unlock()
        if alreadyApplied {
            reply(nil)
            return
        }

        let result = smc.setFanSpeed(fanIndex, speed: speed)
        if result == kIOReturnSuccess {
            fanStateLock.lock()
            appliedFanStates[fanIndex] = AppliedFanState(mode: .forced, speed: speed)
            fanStateLock.unlock()
        }
        reply(result == kIOReturnSuccess ? nil : makeError(code: .smcWriteFailed, description: "Failed to write F\(fanIndex)Tg."))
    }
    func setFanToConstantRPM(fanIndex: Int, speed: Int, reply: @escaping (Error?) -> Void) {
        logger.log("Request to set fan \(fanIndex) to a constant \(speed) RPM.")
        guard let smc = smc else { logger.error("SMC connection not available."); reply(makeError(code: .smcOpenFailed, description: "SMC not connected.")); return }

        fanStateLock.lock()
        let alreadyApplied = appliedFanStates[fanIndex] == AppliedFanState(mode: .forced, speed: speed)
        fanStateLock.unlock()
        if alreadyApplied {
            reply(nil)
            return
        }
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
        fanStateLock.lock()
        appliedFanStates[fanIndex] = AppliedFanState(mode: .forced, speed: speed)
        fanStateLock.unlock()
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

    // MARK: - Sleep Battery Monitoring

    func startSleepBatteryMonitoring(intervalMinutes: Int, chargeLimit: Int, stopChargingWhileAsleep: Bool, logPath: String, reply: @escaping (Error?) -> Void) {
        Task { @MainActor in
            SleepBatteryMonitor.shared.start(
                intervalMinutes: intervalMinutes,
                chargeLimit: chargeLimit,
                stopChargingWhileAsleep: stopChargingWhileAsleep,
                logPath: logPath,
                using: self
            )
            reply(nil)
        }
    }

    func stopSleepBatteryMonitoring(reply: @escaping (Error?) -> Void) {
        Task { @MainActor in
            SleepBatteryMonitor.shared.stop()
            reply(nil)
        }
    }

    // MARK: - Focus Website Blocking (/etc/hosts)

    private static let hostsMarkerStart = "# >>> Sapphire Focus Block >>>"
    private static let hostsMarkerEnd = "# <<< Sapphire Focus Block <<<"

    func writeHostsEntries(_ lines: [String], reply: @escaping (Bool) -> Void) {
        reply(rewriteHosts(replacingWith: lines))
    }

    func removeHostsEntries(reply: @escaping (Bool) -> Void) {
        reply(rewriteHosts(replacingWith: []))
    }

    private func rewriteHosts(replacingWith entries: [String]) -> Bool {
        let path = "/etc/hosts"
        let current = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        var lines = current.components(separatedBy: "\n")
        if let start = lines.firstIndex(of: Self.hostsMarkerStart),
           let end = lines[start...].firstIndex(of: Self.hostsMarkerEnd) {
            lines.removeSubrange(start...end)
        }
        if entries.count > 2 {
            lines.append(contentsOf: entries)
        }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        let newContent = lines.joined(separator: "\n") + "\n"
        guard newContent != current else { return true }

        do {
            try newContent.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            return false
        }

        _ = runPrivilegedCommand("/usr/bin/dscacheutil", args: ["-flushcache"])
        _ = runPrivilegedCommand("/usr/bin/killall", args: ["-HUP", "mDNSResponder"])
        return true
    }
}

// MARK: - Sleep Battery Monitoring

private struct SleepLogEntry: Codable {
    var id: UUID
    let timestamp: Date
    let charge: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isScreenOn: Bool
    let isLowPowerMode: Bool
    let temperature: Double
    let managementState: String
    let ledColor: Int
    let hardwareCharge: Int
    let isSleeping: Bool
    let maxCapacity: Int
    let cycleCount: Int
    let powerConsumption: Double
    let timeRemainingMinutes: Int
}

@MainActor
final class SleepBatteryMonitor {
    static let shared = SleepBatteryMonitor()

    private let monitorID = "com.shariq.sapphireHelper.sleepmonitor" as CFString
    private let wakeEventType = "wake" as CFString
    private let logger = Logger(subsystem: "com.shariq.sapphireHelper", category: "SleepBatteryMonitor")

    private weak var enforcementHelper: Helper?

    private var isActive = false
    private var interval: TimeInterval = 30 * 60
    private var chargeLimit = 100
    private var stopChargingWhileAsleep = false
    private var logPath: String?
    private var observersRegistered = false
    private var lastInhibitState: Bool?

    private init() {}

    // MARK: - Configuration

    func start(intervalMinutes: Int, chargeLimit: Int, stopChargingWhileAsleep: Bool, logPath: String, using helper: Helper) {
        let wasActive = isActive
        enforcementHelper = helper
        self.interval = TimeInterval(max(5, intervalMinutes)) * 60
        self.chargeLimit = max(10, min(100, chargeLimit))
        self.stopChargingWhileAsleep = stopChargingWhileAsleep
        self.logPath = logPath
        lastInhibitState = nil
        isActive = true

        registerObserversIfNeeded()
        scheduleNextWake()

        if !wasActive {
            performSleepWakeCheck()
        }
    }

    func stop() {
        guard isActive else { return }
        logger.log("Stopping sleep battery monitoring; cancelling scheduled wakes.")
        isActive = false
        lastInhibitState = nil
        cancelAllScheduledWakes()
    }

    // MARK: - Sleep / Wake

    private func registerObserversIfNeeded() {
        guard !observersRegistered else { return }
        observersRegistered = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func systemWillSleep() {
        guard isActive else { return }
        scheduleNextWake()
    }

    @objc private func systemDidWake() {
        guard isActive else { return }
        performSleepWakeCheck()
    }

    // MARK: - Wake check

    private func performSleepWakeCheck() {
        guard let snapshot = readBatterySnapshot() else {
            logger.error("Could not read battery snapshot during wake check.")
            scheduleNextWake()
            return
        }
        appendLogEntry(snapshot: snapshot)
        enforceChargePolicy(snapshot: snapshot)
        scheduleNextWake()
    }

    private func enforceChargePolicy(snapshot: BatterySnapshot) {
        guard snapshot.isDisplayAsleep else { return }

        let atOrAboveLimit = snapshot.hardwareCharge >= chargeLimit
        let shouldStop = stopChargingWhileAsleep
            || (chargeLimit < 100 && (atOrAboveLimit || snapshot.isCharging))

        guard let enforcementHelper else { return }

        if enforcementHelper.chargeControlMode == .firmware {
            if chargeLimit < 100 {
                if shouldStop {
                    _ = enforcementHelper.applyFirmwareChargeLimit(upper: chargeLimit)
                } else {
                    _ = enforcementHelper.deactivateFirmwareChargeLimit()
                }
            }
            return
        }

        if shouldStop {
            if lastInhibitState != true {
                enforcementHelper.enableCharging(false) { _ in }
                lastInhibitState = true
            }
        } else {
            if lastInhibitState != false {
                enforcementHelper.enableCharging(true) { _ in }
                lastInhibitState = false
            }
        }
    }

    // MARK: - Scheduling (IOPMSchedulePowerEvent)

    private func scheduleNextWake() {
        guard isActive else { return }
        cancelAllScheduledWakes()
        guard let schedule = IOPMPrivate.IOPMSchedulePowerEvent else {
            logger.error("IOPMSchedulePowerEvent symbol not found")
            return
        }
        let date = Date().addingTimeInterval(interval)
        let result = schedule(date as CFDate, monitorID, wakeEventType)
        if result != kIOReturnSuccess {
            logger.error("IOPMSchedulePowerEvent failed with \(result)")
        } else {
            logger.debug("Armed sleep wake at \(date)")
        }
    }

    private func cancelAllScheduledWakes() {
        guard let copy = IOPMPrivate.IOPMCopyScheduledPowerEvents,
              let events = copy()?.takeRetainedValue() as? [[String: Any]] else { return }
        let cancel = IOPMPrivate.IOPMCancelScheduledPowerEvent
        let myID = monitorID as String
        for event in events {
            guard let appName = event["scheduledby"] as? String, appName == myID else { continue }
            guard let date = event["time"] as? Date else { continue }
            _ = cancel?(date as CFDate, monitorID, wakeEventType)
        }
    }

    // MARK: - Battery snapshot & logging

    private struct BatterySnapshot {
        let charge: Int
        let hardwareCharge: Int
        let isCharging: Bool
        let isPluggedIn: Bool
        let timeToEmpty: Int
        let timeToFull: Int
        let temperature: Double
        let maxCapacity: Int
        let cycleCount: Int
        let isDisplayAsleep: Bool
    }

    private func readBatterySnapshot() -> BatterySnapshot? {
        guard let enforcementHelper,
              let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let powerSource = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, powerSource)?.takeUnretainedValue() as? [String: AnyObject] else {
            return nil
        }

        let charge = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
        let isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int ?? 0
        let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int ?? 0
        let rawCurrent = info["AppleRawCurrentCapacity"] as? Double ?? Double(charge)
        let rawMax = info["AppleRawMaxCapacity"] as? Double ?? 100.0
        let hardwareCharge = rawMax > 0
            ? Int(round(max(0, min(100, rawCurrent / rawMax * 100))))
            : charge

        return BatterySnapshot(
            charge: charge,
            hardwareCharge: hardwareCharge,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            timeToEmpty: timeToEmpty,
            timeToFull: timeToFull,
            temperature: enforcementHelper.readBatteryTemperature(),
            maxCapacity: readIntProperty("AppleRawMaxCapacity") ?? readIntProperty("MaxCapacity") ?? 0,
            cycleCount: readIntProperty("CycleCount") ?? 0,
            isDisplayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0
        )
    }

    private func readIntProperty(_ key: String) -> Int? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if service != 0 { IOObjectRelease(service) } }
        guard service != 0 else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else { return nil }
        return value.takeRetainedValue() as? Int
    }

    private func appendLogEntry(snapshot: BatterySnapshot) {
        guard let logPath else { return }

        let atOrAboveLimit = chargeLimit < 100 && snapshot.hardwareCharge >= chargeLimit
        let entry = SleepLogEntry(
            id: UUID(),
            timestamp: Date(),
            charge: snapshot.charge,
            isCharging: snapshot.isCharging,
            isPluggedIn: snapshot.isPluggedIn,
            isScreenOn: !snapshot.isDisplayAsleep,
            isLowPowerMode: false,
            temperature: snapshot.temperature,
            managementState: atOrAboveLimit ? "Charge Limit" : "Charging",
            ledColor: 0,
            hardwareCharge: snapshot.hardwareCharge,
            isSleeping: snapshot.isDisplayAsleep,
            maxCapacity: snapshot.maxCapacity,
            cycleCount: snapshot.cycleCount,
            powerConsumption: 0,
            timeRemainingMinutes: snapshot.isCharging ? snapshot.timeToFull : snapshot.timeToEmpty
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)

        do {
            let url = URL(fileURLWithPath: logPath)
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: logPath) {
                fileManager.createFile(atPath: logPath, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line)
            trimSleepLogIfNeeded()
        } catch {
            logger.error("Failed to append sleep log entry: \(error.localizedDescription)")
        }
    }

    private func trimSleepLogIfNeeded() {
        guard let logPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)) else { return }
        let lines = data.split(separator: 0x0A)
        guard lines.count > 2000 else { return }
        let trimmed = lines.suffix(2000).joined(separator: Data([0x0A])) + Data([0x0A])
        try? trimmed.write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }
}