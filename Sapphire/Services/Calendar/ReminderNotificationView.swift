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

    var body: some View {
        CalendarNotificationLayout(color: .orange, systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Due \(timeUntil)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}