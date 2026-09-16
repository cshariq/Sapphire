//
//  MultipleCalendarNotificationView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-01.
//

import SwiftUI
import EventKit

struct MultipleCalendarNotificationView: View {
    let events: [EKEvent]
    let timeUntil: String

    @EnvironmentObject private var liveActivityManager: LiveActivityManager

    var body: some View {
        CalendarNotificationLayout(
            color: .red,
            systemImage: "calendar.badge.clock",
            category: "Calendar",
            onDismiss: { liveActivityManager.dismissCalendarNotification() },
            onSnooze: {
                liveActivityManager.snoozeCalendarNotification(
                    eventIDs: events.compactMap(\.eventIdentifier)
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(events.count) Events")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))

                Text("Starting \(timeUntil)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))

                if let firstEvent = events.first {
                    Text("Next: \(firstEvent.title)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
        }
    }
}