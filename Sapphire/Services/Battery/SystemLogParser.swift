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
            let outHandle = pipe.fileHandleForReading

            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else if let line = String(data: data, encoding: .utf8) {
                    line.enumerateLines { line, _ in continuation.yield(line) }
                }
            }

            process.terminationHandler = { _ in
                outHandle.readabilityHandler = nil
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                print("[SystemLogParser] Failed to run pmset process: \(error)")
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

    private func extractTimestamp(from line: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

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