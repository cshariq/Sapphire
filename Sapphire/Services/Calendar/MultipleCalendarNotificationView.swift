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

    var body: some View {
        CalendarNotificationLayout(color: .accentColor, systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(events.count) Events")
                    .font(.headline)
                    .fontWeight(.bold)

                Text("Starting \(timeUntil)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let firstEvent = events.first {
                    Text("Next: \(firstEvent.title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}