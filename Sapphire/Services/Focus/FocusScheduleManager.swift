//
//  FocusScheduleManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-27.
//

import Foundation
import Combine
import AppKit
import UserNotifications

enum FocusScheduleRepeat: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekdays, weekly, custom, monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .custom: return "Specific days"
        case .monthly: return "Monthly"
        }
    }
}

struct ScheduledFocusSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var startTime: Date = Date()
    var repeatInterval: FocusScheduleRepeat = .daily
    var repeatWeekdays: [Int]? = nil
    var duration: TimeInterval = 25 * 60
    var isActive: Bool = true
    var lastFiredDate: Date?

    private static let weekdayShort = [
        "", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
    ]

    var sortedDisplayWeekdays: [Int] {
        let days = repeatWeekdays ?? []
        return [2, 3, 4, 5, 6, 7, 1].filter { days.contains($0) }
    }

    func customRepeats(on weekday: Int) -> Bool {
        guard repeatInterval == .custom else { return true }
        let days = repeatWeekdays ?? []
        return days.isEmpty || days.contains(weekday)
    }

    var repeatDescription: String {
        guard repeatInterval == .custom else { return repeatInterval.displayName }
        let days = sortedDisplayWeekdays
        guard !days.isEmpty else { return "Every day" }
        return days.map { Self.weekdayShort[$0] }.joined(separator: ", ")
    }
}

@MainActor
final class FocusScheduleManager: ObservableObject {
    static let shared = FocusScheduleManager()

    private static let graceWindow: TimeInterval = 4 * 60
    private static let checkInterval: TimeInterval = 30

    private let settings = SettingsModel.shared
    private let sessionManager = FocusSessionManager.shared
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSchedules()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wokeUp),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func wokeUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            Task { @MainActor in
                self?.checkSchedules()
            }
        }
    }

    // MARK: - Firing

    func checkSchedules() {
        let now = Date()
        var schedules = settings.settings.scheduledFocusSessions
        var changed = false

        for index in schedules.indices {
            guard schedules[index].isActive else { continue }
            guard !sessionManager.isSessionActive else { break }
            guard shouldFire(schedules[index], now: now) else { continue }
            fire(&schedules[index])
            changed = true
        }

        if changed {
            settings.settings.scheduledFocusSessions = schedules
        }
    }

    private func shouldFire(_ schedule: ScheduledFocusSession, now: Date) -> Bool {
        let cal = Calendar.current
        let sched = cal.dateComponents([.hour, .minute], from: schedule.startTime)
        guard let hour = sched.hour, let minute = sched.minute else { return false }

        guard let candidate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return false }

        let timeSince = now.timeIntervalSince(candidate)
        guard timeSince >= 0, timeSince <= Self.graceWindow else { return false }

        switch schedule.repeatInterval {
        case .once:
            return true
        case .daily:
            return !hasFired(schedule, on: candidate)
        case .weekdays:
            guard let weekday = cal.dateComponents([.weekday], from: now).weekday,
                  (2...6).contains(weekday) else { return false }
            return !hasFired(schedule, on: candidate)
        case .weekly:
            guard cal.component(.weekday, from: now) == cal.component(.weekday, from: schedule.startTime) else { return false }
            return !hasFired(schedule, on: candidate)
        case .custom:
            guard schedule.customRepeats(on: cal.component(.weekday, from: now)) else { return false }
            return !hasFired(schedule, on: candidate)
        case .monthly:
            guard cal.component(.day, from: now) == cal.component(.day, from: schedule.startTime) else { return false }
            return !hasFired(schedule, on: candidate)
        }
    }

    private func hasFired(_ schedule: ScheduledFocusSession, on date: Date) -> Bool {
        guard let last = schedule.lastFiredDate else { return false }
        return Calendar.current.isDate(last, inSameDayAs: date)
    }

    private func fire(_ schedule: inout ScheduledFocusSession) {
        schedule.lastFiredDate = Date()
        if schedule.repeatInterval == .once {
            schedule.isActive = false
        }
        print("[FocusScheduleManager] Starting scheduled focus session (\(schedule.repeatInterval.displayName), \(Int(schedule.duration / 60)) min).")
        sessionManager.startFocusSession(duration: schedule.duration)
        postStartedNotification(duration: schedule.duration)
    }

    private func postStartedNotification(duration: TimeInterval) {
        guard settings.settings.focusNotificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Focus session started "
            content.body = "Your scheduled focus session is running for \(Int(duration / 60)) minutes. Stay focused!"
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: - UI helpers

    func nextFireDate(for schedule: ScheduledFocusSession) -> Date? {
        let cal = Calendar.current
        let sched = cal.dateComponents([.hour, .minute], from: schedule.startTime)
        guard let hour = sched.hour, let minute = sched.minute else { return nil }

        guard var date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) else { return nil }
        for _ in 0..<400 {
            if date > Date(), matchesOccurrence(schedule, date: date) {
                return date
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        }
        return nil
    }

    private func matchesOccurrence(_ schedule: ScheduledFocusSession, date: Date) -> Bool {
        let cal = Calendar.current
        switch schedule.repeatInterval {
        case .once, .daily:
            return true
        case .weekdays:
            guard let weekday = cal.dateComponents([.weekday], from: date).weekday else { return false }
            return (2...6).contains(weekday)
        case .weekly:
            return cal.component(.weekday, from: date) == cal.component(.weekday, from: schedule.startTime)
        case .custom:
            return schedule.customRepeats(on: cal.component(.weekday, from: date))
        case .monthly:
            return cal.component(.day, from: date) == cal.component(.day, from: schedule.startTime)
        }
    }
}