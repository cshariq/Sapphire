//
//  BatteryHistoryViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-14.
//

import Foundation
import Combine
import SwiftUI

enum TimeRange: Hashable, Identifiable {
    case last24Hours
    case last7Days
    case lastMonth
    case lastYear
    case custom(Date, Date)

    var id: Self { self }

    var displayName: String {
        switch self {
        case .last24Hours: return "24h"
        case .last7Days: return "7d"
        case .lastMonth: return "Month"
        case .lastYear: return "Year"
        case .custom: return "Custom"
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .last24Hours: hasher.combine(0)
        case .last7Days: hasher.combine(1)
        case .lastMonth: hasher.combine(2)
        case .lastYear: hasher.combine(3)
        case .custom: hasher.combine(4)
        }
    }

    static func == (lhs: TimeRange, rhs: TimeRange) -> Bool {
        switch (lhs, rhs) {
        case (.last24Hours, .last24Hours): return true
        case (.last7Days, .last7Days): return true
        case (.lastMonth, .lastMonth): return true
        case (.lastYear, .lastYear): return true
        case (.custom(let a, let b), .custom(let c, let d)): return a == c && b == d
        default: return false
        }
    }
}

@MainActor
class BatteryHistoryViewModel: ObservableObject {
    @Published var chartData: [BatteryLogEntry] = []
    @Published var isLoading: Bool = true

    private var allLogEntries: [BatteryLogEntry] = []
    private let logger = BatteryDataLogger.shared
    private var cancellables = Set<AnyCancellable>()

    init() {}

    func fetchHistory() {
        isLoading = true
        Task(priority: .userInitiated) {
            let logs = logger.readLogFile().sorted { $0.timestamp < $1.timestamp }

            await MainActor.run {
                self.allLogEntries = logs
                self.isLoading = false
            }
        }
    }

    func filterData(for range: TimeRange) {
        let (startDate, endDate) = calculateDateRange(for: range)
        let filteredData = allLogEntries.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
        self.chartData = filteredData
    }

    private func calculateDateRange(for range: TimeRange) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current

        switch range {
        case .last24Hours:
            return (calendar.date(byAdding: .hour, value: -24, to: now)!, now)
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -7, to: now)!, now)
        case .lastMonth:
            return (calendar.date(byAdding: .month, value: -1, to: now)!, now)
        case .lastYear:
            return (calendar.date(byAdding: .year, value: -1, to: now)!, now)
        case .custom(let start, let end):
            return (start, min(end, now))
        }
    }
}