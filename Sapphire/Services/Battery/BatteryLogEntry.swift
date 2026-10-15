//
//  BatteryLogEntry.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-14.
//

import Foundation
import IOKit.ps
import AppKit
import Combine

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
    let entriesDidChange = PassthroughSubject<Void, Never>()
    private let logFileURL: URL

    private init() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory.")
        }
        let logDirURL = appSupportURL.appendingPathComponent("Sapphire/BatteryLogs")
        self.logFileURL = logDirURL.appendingPathComponent("battery_log.jsonl")
        self.legacyLogFileURL = logDirURL.appendingPathComponent("battery_log.json")
        self.sleepLogFileURL = logDirURL.appendingPathComponent("battery_sleep_log.jsonl")

        let logFile = logFileURL
        let legacyFile = legacyLogFileURL
        Self.ioQueue.async {
            do {
                try FileManager.default.createDirectory(at: logDirURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("[BatteryDataLogger] FATAL: Could not create log directory: \(error)")
            }
            Self.migrateLegacyJSONLogIfNeeded(logFile: logFile, legacyFile: legacyFile)
            _ = Self.loadAndPrune(logFile: logFile, cutoff: Self.retentionCutoff(now: Date()))
        }
    }

    private var cachedEntries: [BatteryLogEntry]?
    private var bufferedLines: [Data] = []
    private var inFlightLines: [Data] = []
    private var pendingFlush: Task<Void, Never>?

    private static let appendFlushDelay: Duration = .seconds(5)

    private nonisolated static let ioQueue = DispatchQueue(label: "com.sapphire.battery-log.io", qos: .utility)

    private let legacyLogFileURL: URL
    private let sleepLogFileURL: URL

    nonisolated static func retentionCutoff(now: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now.addingTimeInterval(-31 * 86_400)
    }

    // MARK: - Appending (O(1) per entry)

    func logCurrentState() {
        Task(priority: .background) {
            guard let entry = await createLogEntry() else { return }
            appendEntry(entry)
        }
    }

    private func appendEntry(_ entry: BatteryLogEntry) {
        guard let lineData = try? Self.encodeLine(entry) else { return }
        cachedEntries?.append(entry)
        bufferedLines.append(lineData)
        scheduleFlushIfNeeded()
    }

    private func scheduleFlushIfNeeded() {
        guard pendingFlush == nil, !bufferedLines.isEmpty else { return }
        let url = logFileURL
        pendingFlush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.appendFlushDelay)
            guard let self else { return }
            let lines = self.bufferedLines
            self.bufferedLines = []
            self.inFlightLines = lines
            await Self.writeAppend(lines, to: url)
            self.inFlightLines = []
            self.entriesDidChange.send()
            self.pendingFlush = nil
            self.scheduleFlushIfNeeded()
        }
    }

    private nonisolated static func writeAppend(_ lines: [Data], to url: URL) async {
        guard !lines.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ioQueue.async {
                defer { continuation.resume() }
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
            }
        }
    }

    private nonisolated static func encodeLine(_ entry: BatteryLogEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(0x0A)
        return data
    }

    // MARK: - Migration from legacy JSON array file

    private nonisolated static func migrateLegacyJSONLogIfNeeded(logFile: URL, legacyFile: URL) {
        guard !FileManager.default.fileExists(atPath: logFile.path),
              FileManager.default.fileExists(atPath: legacyFile.path) else { return }

        let legacy = decodeLegacyEntries(at: legacyFile)
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
        do {
            try body.write(to: logFile, options: .atomic)
            try? FileManager.default.removeItem(at: legacyFile)
        } catch {
            print("[BatteryDataLogger] ERROR: Legacy migration failed: \(error)")
        }
    }

    private nonisolated static func decodeLegacyEntries(at url: URL) -> [BatteryLogEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BatteryLogEntry].self, from: data)) ?? []
    }

    // MARK: - Reading

    func readLogFile() async -> [BatteryLogEntry] {
        let cutoff = Self.retentionCutoff(now: Date())
        let sleepURL = sleepLogFileURL

        var persisted: [BatteryLogEntry]
        if let cached = cachedEntries {
            persisted = cached
            persisted.removeAll { $0.timestamp < cutoff }
            cachedEntries = persisted
        } else {
            let logFile = logFileURL
            let loaded = await withCheckedContinuation { (continuation: CheckedContinuation<[BatteryLogEntry], Never>) in
                Self.ioQueue.async {
                    continuation.resume(returning: Self.loadAndPrune(logFile: logFile, cutoff: cutoff))
                }
            }
            if let cached = cachedEntries {
                persisted = cached
            } else {
                var seen = Set(loaded.map(\.id))
                persisted = loaded
                for entry in (inFlightLines + bufferedLines).compactMap(Self.decodeLine)
                where seen.insert(entry.id).inserted {
                    persisted.append(entry)
                }
                cachedEntries = persisted
            }
        }

        let sleepEntries = await withCheckedContinuation { (continuation: CheckedContinuation<[BatteryLogEntry], Never>) in
            Self.ioQueue.async {
                let entries = Self.decodeLines(in: (try? Data(contentsOf: sleepURL)) ?? Data())
                continuation.resume(returning: entries.filter { $0.timestamp >= cutoff })
            }
        }
        return persisted + sleepEntries
    }

    private nonisolated static func loadAndPrune(logFile: URL, cutoff: Date) -> [BatteryLogEntry] {
        guard let data = try? Data(contentsOf: logFile) else { return [] }
        let result = pruneLog(data, cutoff: cutoff)
        if result.removedLineCount > 0 {
            do {
                try result.keptData.write(to: logFile, options: .atomic)
            } catch {
                print("[BatteryDataLogger] ERROR: Could not rewrite pruned log: \(error)")
            }
        }
        return result.entries
    }

    struct PruneResult {
        var entries: [BatteryLogEntry]
        var keptData: Data
        var removedLineCount: Int
    }

    nonisolated static func pruneLog(_ data: Data, cutoff: Date) -> PruneResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result = PruneResult(entries: [], keptData: Data(), removedLineCount: 0)
        result.entries.reserveCapacity(data.count / 220)
        result.keptData.reserveCapacity(data.count)
        for lineData in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let entry = try? decoder.decode(BatteryLogEntry.self, from: Data(lineData)) else {
                result.keptData.append(contentsOf: lineData)
                result.keptData.append(0x0A)
                continue
            }
            guard entry.timestamp >= cutoff else {
                result.removedLineCount += 1
                continue
            }
            result.entries.append(entry)
            result.keptData.append(contentsOf: lineData)
            result.keptData.append(0x0A)
        }
        return result
    }

    private nonisolated static func decodeLine(_ line: Data) -> BatteryLogEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BatteryLogEntry.self, from: line)
    }

    private nonisolated static func decodeLines(in data: Data) -> [BatteryLogEntry] {
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