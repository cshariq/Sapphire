//
//  BatteryHistoryViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-14.
//


//
//
//
//
//

import Foundation
import Combine

@MainActor
class BatteryHistoryViewModel: ObservableObject {

    // MARK: - Published Properties for UI
    @Published var chartData: [BatteryLogEntry] = []
    @Published var summaryStats: SummaryStats = .empty
    @Published var isLoading: Bool = true
    @Published var selectedTimeRange: TimeRange = .last24Hours {
        didSet {
            if oldValue != selectedTimeRange {
                fetchHistory()
            }
        }
    }

    // MARK: - Services
    private let logger = BatteryDataLogger.shared
    private let parser = SystemLogParser()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Data Models
    enum TimeRange: String, CaseIterable, Identifiable {
        case last24Hours = "24 Hours"
        case last7Days = "7 Days"
        var id: String { self.rawValue }
    }

    struct SummaryStats {
        let screenOnTime: TimeInterval
        let chargeCycles: Double
        let avgTemp: Double
        static let empty = SummaryStats(screenOnTime: 0, chargeCycles: 0, avgTemp: 0)
    }

    init() {
        fetchHistory()
    }

    func fetchHistory() {
        isLoading = true

        Task(priority: .userInitiated) {
            let (startDate, _) = getTimeRangeDates()

            async let appLogs = logger.readLogFile().filter { $0.timestamp >= startDate }
            async let systemLogs = await parser.parseLogs(from: startDate, to: Date())

            let mergedData = await merge(appLogs: appLogs, systemLogs: systemLogs)
            let sortedData = mergedData.sorted { $0.timestamp < $1.timestamp }

            let stats = calculateSummary(for: sortedData)

            DispatchQueue.main.async {
                self.chartData = sortedData
                self.summaryStats = stats
                self.isLoading = false
            }
        }
    }

    private func merge(appLogs: [BatteryLogEntry], systemLogs: [BatteryLogEntry]) -> [BatteryLogEntry] {
        var merged = appLogs
        let appLogTimestamps = Set(appLogs.map { $0.timestamp })

        for log in systemLogs {
            let isDuplicate = appLogTimestamps.contains { abs($0.timeIntervalSince(log.timestamp)) < 240 }
            if !isDuplicate {
                merged.append(log)
            }
        }
        return merged
    }

    private func calculateSummary(for data: [BatteryLogEntry]) -> SummaryStats {
        guard !data.isEmpty else { return .empty }

        var screenOnTime: TimeInterval = 0
        for i in 0..<(data.count - 1) {
            if data[i].isScreenOn {
                screenOnTime += data[i+1].timestamp.timeIntervalSince(data[i].timestamp)
            }
        }

        var totalChargeAdded = 0
        var lastCharge = data.first!.charge
        for entry in data {
            if entry.isCharging && entry.charge > lastCharge {
                totalChargeAdded += (entry.charge - lastCharge)
            }
            lastCharge = entry.charge
        }

        let tempLogs = data.filter { $0.temperature > 0 }
        let avgTemp = tempLogs.reduce(0.0) { $0 + $1.temperature } / Double(tempLogs.count)

        return SummaryStats(
            screenOnTime: screenOnTime,
            chargeCycles: Double(totalChargeAdded) / 100.0,
            avgTemp: avgTemp.isNaN ? 0 : avgTemp
        )
    }

    private func getTimeRangeDates() -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        let startDate: Date

        switch selectedTimeRange {
        case .last24Hours:
            startDate = calendar.date(byAdding: .hour, value: -24, to: now)!
        case .last7Days:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        }
        return (startDate, now)
    }
}