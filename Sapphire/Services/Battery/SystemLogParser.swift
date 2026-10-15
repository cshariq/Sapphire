//
//  SystemLogParser.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-14.
//

import Foundation

class SystemLogParser {

    func parseLogs(from startDate: Date, to endDate: Date) async -> [BatteryLogEntry] {
        var entries: [BatteryLogEntry] = []
        var lastValidCharge: Int? = nil

        for await line in fetchSystemLogStream() {
            guard line.contains("InternalBattery") else { continue }
            guard let entry = parseLine(line) else { continue }
            guard entry.timestamp >= startDate && entry.timestamp <= endDate else { continue }

            if let lastCharge = lastValidCharge {
                let chargeDiff = abs(entry.charge - lastCharge)
                if chargeDiff > 20 && !entry.isCharging {
                    continue
                }
            }

            entries.append(entry)
            lastValidCharge = entry.charge
        }

        return entries
    }

    private func fetchSystemLogStream() -> AsyncStream<String> {
        return AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "log"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            let outHandle = pipe.fileHandleForReading

            let assembler = AssemblerBox()
            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    for line in assembler.value.finish() { continuation.yield(line) }
                    continuation.finish()
                } else {
                    for line in assembler.value.append(data) { continuation.yield(line) }
                }
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                print("[SystemLogParser] Failed to run pmset process: \(error)")
                outHandle.readabilityHandler = nil
                continuation.finish()
            }
        }
    }

    private func parseLine(_ line: String) -> BatteryLogEntry? {
        guard let timestamp = extractTimestamp(from: line) else { return nil }

        let charge = extractIntValue(for: "charge", from: line) ?? 0
        let isCharging = line.contains("AC Power")
        let isScreenOn = (extractIntValue(for: "display", from: line) ?? 0) > 0
        let isLowPowerMode = (extractIntValue(for: "lowpowermode", from: line) ?? 0) == 1

        return BatteryLogEntry(
            timestamp: timestamp,
            charge: charge,
            isCharging: isCharging,
            isPluggedIn: isCharging,
            isScreenOn: isScreenOn,
            isLowPowerMode: isLowPowerMode,
            temperature: -1.0,
            managementState: isCharging ? .charging : .discharging,
            ledColor: -1,
            hardwareCharge: charge,
            isSleeping: false,
            maxCapacity: 0,
            cycleCount: 0,
            powerConsumption: 0.0,
            timeRemainingMinutes: 0
        )
    }

    private final class AssemblerBox: @unchecked Sendable {
        var value = LineChunkAssembler()
    }

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    private func extractTimestamp(from line: String) -> Date? {
        let formatter = timestampFormatter

        if let range = line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}"#, options: .regularExpression) {
            let dateString = String(line[range])
            return formatter.date(from: dateString)
        }
        return nil
    }

    private func extractIntValue(for key: String, from line: String) -> Int? {
        if let range = line.range(of: #"\b\#(key)=(\d+)\b"#, options: .regularExpression) {
            let match = String(line[range])
            let components = match.components(separatedBy: "=")
            if components.count == 2 {
                return Int(components[1])
            }
        }
        return nil
    }
}

struct LineChunkAssembler {
    private var pending = Data()

    mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        var lineStart = pending.startIndex
        while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
            lines.append(Self.decode(pending[lineStart..<newline]))
            lineStart = pending.index(after: newline)
        }
        pending = Data(pending[lineStart...])
        return lines
    }

    mutating func finish() -> [String] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [Self.decode(pending[...])]
    }

    private static func decode(_ bytes: Data.SubSequence) -> String {
        var slice = bytes
        if slice.last == 0x0D { slice = slice.dropLast() }
        return String(decoding: slice, as: UTF8.self)
    }
}