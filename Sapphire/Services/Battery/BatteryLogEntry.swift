//
//  BatteryLogEntry.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-14.
//


//
//
//
//
//
//
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
    let temperature: Double // in Celsius
    let timeToEmpty: Int // in minutes
    let timeToFull: Int // in minutes

    var estimatedTimeRemaining: Int {
        isCharging ? timeToFull : timeToEmpty
    }
}

// MARK: - Data Logger Service
@MainActor
class BatteryDataLogger {
    static let shared = BatteryDataLogger()

    private var loggingTimer: Timer?
    private let logFileURL: URL

    private init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDirURL = appSupportURL.appendingPathComponent("Sapphire/BatteryLogs")

        try? fileManager.createDirectory(at: logDirURL, withIntermediateDirectories: true, attributes: nil)

        self.logFileURL = logDirURL.appendingPathComponent("battery_log.json")
        print("[BatteryDataLogger] Logging to: \(logFileURL.path)")
    }

    func startLogging() {
        stopLogging()

        logCurrentState()

        loggingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.logCurrentState()
        }
        print("[BatteryDataLogger] Started periodic logging every 5 minutes.")
    }

    func stopLogging() {
        loggingTimer?.invalidate()
        loggingTimer = nil
        print("[BatteryDataLogger] Stopped periodic logging.")
    }

    private func logCurrentState() {
        Task(priority: .background) {
            guard let entry = await createLogEntry() else { return }

            var existingLogs = readLogFile()
            existingLogs.append(entry)

            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            let recentLogs = existingLogs.filter { $0.timestamp >= oneMonthAgo }

            writeLogFile(entries: recentLogs)

            print("[BatteryDataLogger] Logged new entry. Total entries: \(recentLogs.count)")
        }
    }

    func readLogFile() -> [BatteryLogEntry] {
        do {
            let data = try Data(contentsOf: logFileURL)
            let entries = try JSONDecoder().decode([BatteryLogEntry].self, from: data)
            return entries
        } catch {
            return []
        }
    }

    private func writeLogFile(entries: [BatteryLogEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: logFileURL, options: .atomic)
        } catch {
            print("[BatteryDataLogger] Error writing to log file: \(error)")
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

        let entry = BatteryLogEntry(
            timestamp: Date(),
            charge: charge,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isScreenOn: !displayIsAsleep,
            isLowPowerMode: PowerModeManager.shared.isLowPowerModeEnabled(),
            temperature: temp,
            timeToEmpty: timeToEmpty,
            timeToFull: timeToFull
        )
        return entry
    }
}