//
//  CalendarViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-27.
//

import Foundation
import SwiftUI

struct MonthGridItem: Identifiable {
    let id = UUID()
    let date: Date
    let isCurrentMonth: Bool
}

class InteractiveCalendarViewModel: ObservableObject {
    @Published var dates: [Date] = []
    @Published var selectedDate: Date {
        didSet {
            generateMonthGrid()
        }
    }
    @Published var monthGrid: [MonthGridItem] = []

    let today: Date = Calendar.current.startOfDay(for: Date())

    var selectedMonthAbbreviated: String {
        selectedDate.format(as: "MMM")
    }

    init() {
        self.selectedDate = self.today
        generateDates()
        generateMonthGrid()
    }

    private func generateDates() {
        let calendar = Calendar.current
        let dateRange = -90...90

        self.dates = dateRange.compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: today)
        }
    }

    private func generateMonthGrid() {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let firstDayOfMonth = monthInterval.start as Date?,
              let firstWeekday = calendar.ordinality(of: .weekday, in: .weekOfYear, for: firstDayOfMonth) else {
            return
        }

        var grid: [MonthGridItem] = []

        let paddingDays = firstWeekday - calendar.firstWeekday
        if paddingDays > 0 {
            for i in (0..<paddingDays).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i - 1, to: firstDayOfMonth) {
                    grid.append(MonthGridItem(date: date, isCurrentMonth: false))
                }
            }
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 0
        for i in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: i, to: firstDayOfMonth) {
                grid.append(MonthGridItem(date: date, isCurrentMonth: true))
            }
        }

        let remainingSlots = 42 - grid.count
        if remainingSlots > 0 {
            guard let lastDayOfMonth = monthInterval.end as Date? else { return }
            for i in 0..<remainingSlots {
                if let date = calendar.date(byAdding: .day, value: i, to: lastDayOfMonth) {
                    grid.append(MonthGridItem(date: date, isCurrentMonth: false))
                }
            }
        }

        self.monthGrid = grid
    }

    func datesInWeek(for date: Date) -> [Date] {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        var dates: [Date] = []
        var currentDate = weekInterval.start

        while currentDate < weekInterval.end {
            dates.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        return dates
    }

    func selectDate(_ date: Date) {
        self.selectedDate = Calendar.current.startOfDay(for: date)
    }
}