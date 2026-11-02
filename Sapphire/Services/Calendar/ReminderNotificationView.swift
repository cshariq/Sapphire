//
//  ReminderNotificationView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-19.
//

import SwiftUI
import EventKit

struct ReminderNotificationView: View {
    let reminder: EKReminder
    let timeUntil: String

    @Environment(LiveActivityManager.self) private var liveActivityManager

    var body: some View {
        CalendarNotificationLayout(
            color: .orange,
            systemImage: "checklist",
            category: String(localized: "Reminder"),
            onDismiss: { liveActivityManager.dismissCalendarNotification() },
            onSnooze: {
                liveActivityManager.snoozeCalendarNotification(
                    reminderIDs: [reminder.calendarItemIdentifier]
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                Text("Due \(timeUntil)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
        }
    }
}