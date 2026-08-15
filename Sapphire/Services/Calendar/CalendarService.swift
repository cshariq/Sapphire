//
//  CalendarService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-28.
//

import Foundation
import EventKit

class CalendarService: ObservableObject {
    private let eventStore = EKEventStore()

    @Published var eventsForSelectedDate: [EKEvent] = []
    @Published var remindersForSelectedDate: [EKReminder] = []

    @Published var upcomingEvents: [EKEvent] = []
    @Published var upcomingReminders: [EKReminder] = []

    private var currentlyTrackedDate: Date = Date()

    private let workQueue = DispatchQueue(label: "com.sapphire.calendarQueue", qos: .userInitiated)

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
        requestAccess()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func requestAccess() {
        eventStore.requestFullAccessToEvents { [weak self] (granted, error) in
            if granted && error == nil {
                self?.requestRemindersAccess()
            } else {
                print("[CalendarService] Calendar access denied or error: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    private func requestRemindersAccess() {
        eventStore.requestFullAccessToReminders { [weak self] (granted, error) in
            if granted && error == nil {
                DispatchQueue.main.async {
                    self?.fetchEvents(for: Date())
                    self?.fetchAllUpcomingEvents()
                    self?.fetchReminders(for: Date())
                    self?.fetchAllUpcomingReminders()
                }
            } else {
                 print("[CalendarService] Reminders access denied or error: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    @objc private func eventStoreChanged() {
        fetchEvents(for: currentlyTrackedDate)
        fetchAllUpcomingEvents()
        fetchReminders(for: currentlyTrackedDate)
        fetchAllUpcomingReminders()
    }

    func fetchEvents(for date: Date) {
        self.currentlyTrackedDate = date

        workQueue.async { [weak self] in
            guard let self = self else { return }

            let calendars = self.eventStore.calendars(for: .event)
            let calendar = Calendar.current
            let startDate = calendar.startOfDay(for: date)
            guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return }

            let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)

            let fetchedEvents = self.eventStore.events(matching: predicate)
                .sorted {
                    if $0.isAllDay && !$1.isAllDay {
                        return true
                    }
                    if !$0.isAllDay && $1.isAllDay {
                        return false
                    }
                    return $0.startDate < $1.startDate
                }

            DispatchQueue.main.async {
                self.eventsForSelectedDate = fetchedEvents
            }
        }
    }

    private func fetchAllUpcomingEvents() {
        workQueue.async { [weak self] in
            guard let self = self else { return }

            let calendars = self.eventStore.calendars(for: .event)
            let now = Date()
            guard let twoDaysFromNow = Calendar.current.date(byAdding: .hour, value: 48, to: now) else { return }

            let predicate = self.eventStore.predicateForEvents(withStart: now, end: twoDaysFromNow, calendars: calendars)
            let fetchedEvents = self.eventStore.events(matching: predicate)
                .filter { !$0.isAllDay }
                .sorted { $0.startDate < $1.startDate }

            DispatchQueue.main.async {
                self.upcomingEvents = fetchedEvents
            }
        }
    }

    func fetchReminders(for date: Date) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: startDate, ending: endDate, calendars: nil)

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let self = self else { return }

            self.workQueue.async {
                let sortedReminders = reminders?.sorted(by: {
                    let date1 = $0.dueDateComponents?.date ?? .distantFuture
                    let date2 = $1.dueDateComponents?.date ?? .distantFuture
                    return date1 < date2
                }) ?? []

                DispatchQueue.main.async {
                    self.remindersForSelectedDate = sortedReminders
                }
            }
        }
    }

    private func fetchAllUpcomingReminders() {
        let now = Date()
        guard let twoDaysFromNow = Calendar.current.date(byAdding: .hour, value: 48, to: now) else { return }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: now, ending: twoDaysFromNow, calendars: nil)

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let self = self else { return }

            self.workQueue.async {
                let sortedReminders = reminders?.sorted(by: {
                    let date1 = $0.dueDateComponents?.date ?? .distantFuture
                    let date2 = $1.dueDateComponents?.date ?? .distantFuture
                    return date1 < date2
                }) ?? []

                DispatchQueue.main.async {
                    self.upcomingReminders = sortedReminders
                }
            }
        }
    }
}