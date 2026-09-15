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
    let managementState: ManagementState
    let ledColor: Int
    let hardwareCharge: Int
    let isSleeping: Bool
    let maxCapacity: Int
    let cycleCount: Int

    let powerConsumption: Double
    let timeRemainingMinutes: Int
}

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
        self.logFileURL = logDirURL.appendingPathComponent("battery_log.jsonl")
        self.legacyLogFileURL = logDirURL.appendingPathComponent("battery_log.json")
        self.sleepLogFileURL = logDirURL.appendingPathComponent("battery_sleep_log.jsonl")

        migrateLegacyJSONLogIfNeeded()
    }

    private var cachedEntries: [BatteryLogEntry]?
    private var cachedEntriesDirty = true
    private var bufferedLines: [Data] = []
    private var pendingFlush: Task<Void, Never>?

    private static let appendFlushDelay: Duration = .seconds(5)

    private let legacyLogFileURL: URL
    private let sleepLogFileURL: URL

    // MARK: - Appending (O(1) per entry)

    func logCurrentState() {
        Task(priority: .background) {
            guard let entry = await createLogEntry() else { return }
            appendEntry(entry)
        }
    }

    private func appendEntry(_ entry: BatteryLogEntry) {
        guard let lineData = try? Self.encodeLine(entry) else { return }
        cachedEntriesDirty = true
        bufferedLines.append(Data(lineData))
        scheduleFlushIfNeeded()
    }

    private func scheduleFlushIfNeeded() {
        guard pendingFlush == nil, !bufferedLines.isEmpty else { return }
        let lines = bufferedLines
        bufferedLines = []
        let url = logFileURL
        pendingFlush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.appendFlushDelay)
            guard !Task.isCancelled else {
                self?.pendingFlush = nil
                return
            }
            await Self.writeAppend(lines, to: url)
            self?.pendingFlush = nil
            self?.scheduleFlushIfNeeded()
        }
    }

    private nonisolated static func writeAppend(_ lines: [Data], to url: URL) async {
        await Task.detached(priority: .utility) {
            var payload = Data()
            payload.reserveCapacity(lines.reduce(0) { $0 + $1.count })
            lines.forEach { payload.append($0) }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                if !FileManager.default.createFile(atPath: url.path, contents: payload) {
                    print("[BatteryDataLogger] ERROR: Could not create log file for append.")
                }
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        }.value
    }

    private static func encodeLine(_ entry: BatteryLogEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(0x0A)
        return data
    }

    // MARK: - Migration from legacy JSON array file

    private func migrateLegacyJSONLogIfNeeded() {
        guard !FileManager.default.fileExists(atPath: logFileURL.path),
              FileManager.default.fileExists(atPath: legacyLogFileURL.path) else { return }

        let legacy = decodeLegacyEntries()
        guard !legacy.isEmpty else { return }
        print("[BatteryDataLogger] Migrating \(legacy.count) legacy JSON entries to JSONL…")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var body = Data()
        for entry in legacy {
            if let line = try? encoder.encode(entry) {
                body.append(line)
                body.append(0x0A)
            }
        }
        FileManager.default.createFile(atPath: logFileURL.path, contents: body)
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            try? FileManager.default.removeItem(at: legacyLogFileURL)
        }
    }

    private nonisolated func decodeLegacyEntries() -> [BatteryLogEntry] {
        guard let data = try? Data(contentsOf: legacyLogFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BatteryLogEntry].self, from: data)) ?? []
    }

    // MARK: - Reading

    func readLogFile() -> [BatteryLogEntry] {
        if !cachedEntriesDirty, let cached = cachedEntries {
            var result = cached
            result.append(contentsOf: readSleepLogFile())
            return result
        }

        var entries = decodePersistedEntries()
        pruneOldEntries(&entries)
        cachedEntries = entries
        cachedEntriesDirty = false

        entries.append(contentsOf: readSleepLogFile())
        return entries
    }

    private func decodePersistedEntries() -> [BatteryLogEntry] {
        guard let data = try? Data(contentsOf: logFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var results: [BatteryLogEntry] = []
        results.reserveCapacity(data.count / 220)
        for lineData in data.split(separator: 0x0A) {
            if let entry = try? decoder.decode(BatteryLogEntry.self, from: Data(lineData)) {
                results.append(entry)
            }
        }
        return results
    }

    private func pruneOldEntries(_ entries: inout [BatteryLogEntry]) {
        guard let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return }
        entries.removeAll { $0.timestamp < oneMonthAgo }
    }

    private func readSleepLogFile() -> [BatteryLogEntry] {
        guard let data = try? Data(contentsOf: sleepLogFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(BatteryLogEntry.self, from: Data(line))
        }
    }

    // MARK: - Entry creation

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
        let displayIsAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0

        let temp = await BatteryManager.shared.getBatteryTemperature()
        let hardwareCharge = await BatteryManager.shared.getHardwareBatteryPercentage()
        let maxCapacity = await BatteryManager.shared.getMaxCapacity()
        let cycleCount = await BatteryManager.shared.getCycleCount()

        let powerConsumption = StatsManager.shared.currentStats?.battery?.powerDraw ?? 0.0
        let timeRemainingMinutes = isCharging ? timeToFull : timeToEmpty

        let status = BatteryStatusManager.shared.currentState

        return BatteryLogEntry(
            timestamp: Date(),
            charge: charge,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isScreenOn: !displayIsAsleep,
            isLowPowerMode: PowerModeManager.shared.isLowPowerModeEnabled(),
            temperature: temp,
            managementState: status.managementState,
            ledColor: status.ledColor,
            hardwareCharge: hardwareCharge,
            isSleeping: status.isSleeping,
            maxCapacity: maxCapacity,
            cycleCount: cycleCount,
            powerConsumption: powerConsumption,
            timeRemainingMinutes: timeRemainingMinutes
        )
    }
}