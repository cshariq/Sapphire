//
//  CalendarViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-27.
//

import Foundation
import AppKit
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
    @Published private(set) var today: Date

    private var currentCalendar: Calendar
    private let now: () -> Date
    private var notificationObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private(set) var calendarStartOfWeek: Day

    var selectedMonthAbbreviated: String {
        selectedDate.format(as: "MMM")
    }

    init(
        calendarStartOfWeek: Day = .sunday,
        calendar: @escaping () -> Calendar = { Calendar.current },
        now: @escaping () -> Date = { Date() },
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.calendarStartOfWeek = calendarStartOfWeek
        self.now = now

        var cal = Calendar.current
        cal.firstWeekday = calendarStartOfWeek.firstWeekday
        self.currentCalendar = cal

        let currentDay = cal.startOfDay(for: now())
        self.today = currentDay
        self.selectedDate = currentDay

        generateDates(using: cal)
        generateMonthGrid(using: cal)
        observeCurrentDayChanges(
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    deinit {
        notificationObservers.forEach { observer in
            observer.center.removeObserver(observer.token)
        }
    }

    private func generateDates(using calendar: Calendar) {
        let dateRange = -90...90

        self.dates = dateRange.compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: today)
        }
    }

    func updateStartOfWeek(_ day: Day) {
        guard day != calendarStartOfWeek else { return }
        calendarStartOfWeek = day
        var cal = Calendar.current
        cal.firstWeekday = day.firstWeekday
        currentCalendar = cal
        generateDates(using: cal)
        generateMonthGrid(using: cal)
    }

    private func generateMonthGrid(using calendar: Calendar? = nil) {
        let calendar = calendar ?? currentCalendar
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

    private func observeCurrentDayChanges(
        notificationCenter: NotificationCenter,
        workspaceNotificationCenter: NotificationCenter
    ) {
        observe(
            [.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange,
             NSApplication.didBecomeActiveNotification],
            in: notificationCenter
        )
        observe([NSWorkspace.didWakeNotification], in: workspaceNotificationCenter)
    }

    private func observe(_ names: [Notification.Name], in center: NotificationCenter) {
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.refreshCurrentDay(for: notification.name)
            }
            notificationObservers.append((center, token))
        }
    }

    private func refreshCurrentDay(for notificationName: Notification.Name) {
        let calendar = currentCalendar
        let currentDay = calendar.startOfDay(for: now())
        guard currentDay != today else { return }

        let wasFollowingToday = selectedDate == today
        today = currentDay
        generateDates(using: calendar)

        if wasFollowingToday {
            selectedDate = currentDay
        } else if notificationName == .NSSystemTimeZoneDidChange {
            generateMonthGrid(using: calendar)
        }
    }

    func datesInWeek(for date: Date) -> [Date] {
        let calendar = currentCalendar
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
        self.selectedDate = currentCalendar.startOfDay(for: date)
    }
}