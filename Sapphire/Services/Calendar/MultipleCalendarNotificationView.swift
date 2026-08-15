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

    @State private var isShowing = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            }
            .frame(width: 72, height: 72)

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