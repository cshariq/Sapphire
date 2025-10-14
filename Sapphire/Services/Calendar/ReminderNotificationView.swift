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

    @State private var isShowing = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange)
                Image(systemName: "checklist")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            }
            .frame(width: 72, height: 72)

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
        .padding(12)
        .padding(.horizontal, 20)
        .padding(.top, 25)
        .scaleEffect(isShowing ? 1 : 0.95)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isShowing = true
            }
        }
    }
}