//
//  CalendarService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-28.
//

import Foundation
import EventKit
import AppKit

class CalendarService: ObservableObject {
    private let eventStore = EKEventStore()

    @Published var eventsForSelectedDate: [EKEvent] = []
    @Published var remindersForSelectedDate: [EKReminder] = []

    @Published var upcomingEvents: [EKEvent] = []
    @Published var upcomingReminders: [EKReminder] = []

    private var currentlyTrackedDate: Date = Date()

    private let workQueue = DispatchQueue(label: "com.sapphire.calendarQueue", qos: .userInitiated)
    private var selectedEventsGeneration = 0
    private var upcomingEventsGeneration = 0
    private var selectedRemindersGeneration = 0
    private var upcomingRemindersGeneration = 0
    private var eventStoreRefreshWorkItem: DispatchWorkItem?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        eventStoreRefreshWorkItem?.cancel()
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.eventStoreRefreshWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let selectedDate = self.currentlyTrackedDate
                self.fetchEvents(for: selectedDate)
                self.fetchAllUpcomingEvents()
                self.fetchReminders(for: selectedDate)
                self.fetchAllUpcomingReminders()
            }
            self.eventStoreRefreshWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        }
    }

    @objc private func applicationDidBecomeActive() {
        fetchEvents(for: currentlyTrackedDate)
        fetchAllUpcomingEvents()
    }

    private func visibleEventCalendars() -> [EKCalendar] {
        let calendarPreferences = UserDefaults.standard.persistentDomain(
            forName: CalendarVisibilityFilter.calendarPreferencesDomain
        )

        return eventStore.calendars(for: .event).filter {
            CalendarVisibilityFilter.isVisible(
                calendarIdentifier: $0.calendarIdentifier,
                calendarPreferences: calendarPreferences
            )
        }
    }

    func fetchEvents(for date: Date) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchEvents(for: date) }
            return
        }

        self.currentlyTrackedDate = date
        selectedEventsGeneration &+= 1
        let generation = selectedEventsGeneration

        workQueue.async { [weak self] in
            guard let self = self else { return }

            let calendars = self.visibleEventCalendars()
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
                guard self.selectedEventsGeneration == generation else { return }
                self.eventsForSelectedDate = fetchedEvents
            }
        }
    }

    private func fetchAllUpcomingEvents() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchAllUpcomingEvents() }
            return
        }

        upcomingEventsGeneration &+= 1
        let generation = upcomingEventsGeneration
        workQueue.async { [weak self] in
            guard let self = self else { return }

            let calendars = self.visibleEventCalendars()
            let now = Date()
            guard let twoDaysFromNow = Calendar.current.date(byAdding: .hour, value: 48, to: now) else { return }

            let predicate = self.eventStore.predicateForEvents(withStart: now, end: twoDaysFromNow, calendars: calendars)
            let fetchedEvents = self.eventStore.events(matching: predicate)
                .filter { !$0.isAllDay }
                .sorted { $0.startDate < $1.startDate }

            DispatchQueue.main.async {
                guard self.upcomingEventsGeneration == generation else { return }
                self.upcomingEvents = fetchedEvents
            }
        }
    }

    func fetchReminders(for date: Date) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchReminders(for: date) }
            return
        }

        currentlyTrackedDate = date
        selectedRemindersGeneration &+= 1
        let generation = selectedRemindersGeneration
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
                    guard self.selectedRemindersGeneration == generation else { return }
                    self.remindersForSelectedDate = sortedReminders
                }
            }
        }
    }

    private func fetchAllUpcomingReminders() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchAllUpcomingReminders() }
            return
        }

        upcomingRemindersGeneration &+= 1
        let generation = upcomingRemindersGeneration
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
                    guard self.upcomingRemindersGeneration == generation else { return }
                    self.upcomingReminders = sortedReminders
                }
            }
        }
    }
}