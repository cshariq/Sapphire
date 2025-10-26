//
//  BatteryLogEntry.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-14.
//

import Foundation
import IOKit.ps
import AppKit

// MARK: - Data Model
struct BatteryLogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    let timestamp: Date
    let charge: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isScreenOn: Bool
    let isLowPowerMode: Bool
    let temperature: Double
    let timeToEmpty: Int
    let timeToFull: Int
    let managementState: ManagementState
    let ledColor: Int
    let hardwareCharge: Int
    let isSleeping: Bool

    var estimatedTimeRemaining: Int { isCharging ? timeToFull : timeToEmpty }
}

// MARK: - Data Logger Service
@MainActor
class BatteryDataLogger {
    static let shared = BatteryDataLogger()
    private let logFileURL: URL

    private init() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory.")
        }
        let logDirURL = appSupportURL.appendingPathComponent("Sapphire/BatteryLogs")

        do {
            try fileManager.createDirectory(at: logDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("[BatteryDataLogger] FATAL: Could not create log directory: \(error)")
        }
        self.logFileURL = logDirURL.appendingPathComponent("battery_log.json")
        print("[BatteryDataLogger] Logging to: \(logFileURL.path)")

        if !fileManager.fileExists(atPath: logFileURL.path) {
            print("[BatteryDataLogger] Log file does not exist. Creating a new empty log file.")
            writeLogFile(entries: [])
        }
    }

    func logCurrentState() {
        Task(priority: .background) {
            guard let entry = await createLogEntry() else { return }
            var existingLogs = readLogFile()
            existingLogs.append(entry)
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            let recentLogs = existingLogs.filter { $0.timestamp >= oneMonthAgo }
            writeLogFile(entries: recentLogs)
            print("[BatteryDataLogger] Logged new entry. Total entries now: \(recentLogs.count)")
        }
    }

    func readLogFile() -> [BatteryLogEntry] {
        do {
            let data = try Data(contentsOf: logFileURL)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let entries = try decoder.decode([BatteryLogEntry].self, from: data)
            return entries
        } catch {
            print("[BatteryDataLogger] -------------------------------------------------")
            print("[BatteryDataLogger] ERROR: Could not read or decode log file.")
            print("[BatteryDataLogger] Error: \(error)")
            if let decodingError = error as? DecodingError {
                print("[BatteryDataLogger] Decoding Error Details: \(decodingError)")
            }
            print("[BatteryDataLogger] -------------------------------------------------")
            return []
        }
    }

    private func writeLogFile(entries: [BatteryLogEntry]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: logFileURL, options: .atomic)
        } catch {
            print("[BatteryDataLogger] ERROR writing to log file: \(error)")
        }
    }

    private func createLogEntry() async -> BatteryLogEntry? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
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
        let temp = await BatteryManager.shared.getBatteryTemperature()
        let displayIsAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0

        let status = BatteryStatusManager.shared.currentState
        let hardwareCharge = BatteryManager.shared.getHardwareBatteryPercentage()

        return BatteryLogEntry(
            timestamp: Date(),
            charge: charge,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isScreenOn: !displayIsAsleep,
            isLowPowerMode: PowerModeManager.shared.isLowPowerModeEnabled(),
            temperature: temp,
            timeToEmpty: timeToEmpty,
            timeToFull: timeToFull,
            managementState: status.managementState,
            ledColor: status.ledColor,
            hardwareCharge: hardwareCharge,
            isSleeping: status.isSleeping
        )
    }
}