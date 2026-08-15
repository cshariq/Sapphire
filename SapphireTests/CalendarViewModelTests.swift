//
//  CalendarViewModelTests.swift
//  SapphireTests
//

import AppKit
import Foundation
import Testing
@testable import Sapphire

@MainActor
struct CalendarViewModelTests {
    @Test func dayChangeAdvancesCurrentSelectionAndDateStrip() {
        let calendarSource = CalendarSource(timeZone: timeZone("America/Los_Angeles"))
        let clock = TestClock(date(2026, 8, 11, hour: 12, calendar: calendarSource.calendar))
        let notificationCenter = NotificationCenter()
        let viewModel = makeViewModel(
            calendarSource: calendarSource,
            clock: clock,
            notificationCenter: notificationCenter
        )

        let august12 = date(2026, 8, 12, calendar: calendarSource.calendar)
        clock.now = date(2026, 8, 12, hour: 12, calendar: calendarSource.calendar)
        notificationCenter.post(name: .NSCalendarDayChanged, object: nil)

        #expect(viewModel.today == august12)
        #expect(viewModel.selectedDate == august12)
        #expect(viewModel.dates.count == 181)
        #expect(viewModel.dates[90] == august12)
    }

    @Test func dayChangePreservesExplicitSelection() {
        let calendarSource = CalendarSource(timeZone: timeZone("America/Los_Angeles"))
        let clock = TestClock(date(2026, 8, 11, hour: 12, calendar: calendarSource.calendar))
        let notificationCenter = NotificationCenter()
        let viewModel = makeViewModel(
            calendarSource: calendarSource,
            clock: clock,
            notificationCenter: notificationCenter
        )
        let explicitSelection = date(2026, 8, 8, calendar: calendarSource.calendar)
        viewModel.selectDate(explicitSelection)

        let august12 = date(2026, 8, 12, calendar: calendarSource.calendar)
        clock.now = date(2026, 8, 12, hour: 12, calendar: calendarSource.calendar)
        notificationCenter.post(name: .NSCalendarDayChanged, object: nil)

        #expect(viewModel.today == august12)
        #expect(viewModel.selectedDate == explicitSelection)
        #expect(viewModel.dates[90] == august12)
    }

    @Test func timeZoneChangeUsesNewLocalStartOfDay() {
        let calendarSource = CalendarSource(timeZone: timeZone("America/Los_Angeles"))
        let instant = Date(timeIntervalSince1970: 1_786_494_600) // 2026-08-12 00:30:00 UTC
        let clock = TestClock(instant)
        let notificationCenter = NotificationCenter()
        let viewModel = makeViewModel(
            calendarSource: calendarSource,
            clock: clock,
            notificationCenter: notificationCenter
        )

        let oldToday = calendarSource.calendar.startOfDay(for: instant)
        calendarSource.timeZone = timeZone("Asia/Tokyo")
        let newToday = calendarSource.calendar.startOfDay(for: instant)
        notificationCenter.post(name: .NSSystemTimeZoneDidChange, object: nil)

        #expect(newToday != oldToday)
        #expect(viewModel.today == newToday)
        #expect(viewModel.selectedDate == newToday)
        #expect(viewModel.dates[90] == newToday)
    }

    @Test func unchangedDayKeepsSelectionAndGeneratedRangeStable() {
        let calendarSource = CalendarSource(timeZone: timeZone("America/Los_Angeles"))
        let clock = TestClock(date(2026, 8, 11, hour: 9, calendar: calendarSource.calendar))
        let notificationCenter = NotificationCenter()
        let viewModel = makeViewModel(
            calendarSource: calendarSource,
            clock: clock,
            notificationCenter: notificationCenter
        )
        let originalToday = viewModel.today
        let originalSelection = viewModel.selectedDate
        let originalDates = viewModel.dates
        let originalGridIDs = viewModel.monthGrid.map(\.id)

        clock.now = date(2026, 8, 11, hour: 21, calendar: calendarSource.calendar)
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(viewModel.today == originalToday)
        #expect(viewModel.selectedDate == originalSelection)
        #expect(viewModel.dates == originalDates)
        #expect(viewModel.monthGrid.map(\.id) == originalGridIDs)
    }

    @Test func notificationObserversDoNotRetainReleasedViewModel() {
        let calendarSource = CalendarSource(timeZone: timeZone("America/Los_Angeles"))
        let clock = TestClock(date(2026, 8, 11, hour: 12, calendar: calendarSource.calendar))
        let notificationCenter = NotificationCenter()
        let workspaceNotificationCenter = NotificationCenter()
        weak var weakViewModel: InteractiveCalendarViewModel?

        do {
            let viewModel = makeViewModel(
                calendarSource: calendarSource,
                clock: clock,
                notificationCenter: notificationCenter,
                workspaceNotificationCenter: workspaceNotificationCenter
            )
            weakViewModel = viewModel
            #expect(weakViewModel != nil)
        }

        let readsAfterRelease = clock.readCount
        notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(weakViewModel == nil)
        #expect(clock.readCount == readsAfterRelease)
    }

    private func makeViewModel(
        calendarSource: CalendarSource,
        clock: TestClock,
        notificationCenter: NotificationCenter,
        workspaceNotificationCenter: NotificationCenter = NotificationCenter()
    ) -> InteractiveCalendarViewModel {
        InteractiveCalendarViewModel(
            calendar: { calendarSource.calendar },
            now: { clock.currentDate() },
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func timeZone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)!
    }
}

private final class CalendarSource {
    var timeZone: TimeZone

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }
}

private final class TestClock {
    var now: Date
    private(set) var readCount = 0

    init(_ now: Date) {
        self.now = now
    }

    func currentDate() -> Date {
        readCount += 1
        return now
    }
}
