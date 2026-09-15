//
//  CalendarNotificationView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-19.
//

import SwiftUI
import EventKit

struct CalendarNotificationLayout<Details: View>: View {
    let color: Color
    let systemImage: String
    let details: Details

    @State private var isShowing = false

    init(color: Color, systemImage: String, @ViewBuilder details: () -> Details) {
        self.color = color
        self.systemImage = systemImage
        self.details = details()
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color)
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            }
            .frame(width: 72, height: 72)

            details
        }
        .padding(12)
        .padding(.horizontal, 20)
        .padding(.top, NotchConfiguration.universalHeight)
        .scaleEffect(isShowing ? 1 : 0.95)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isShowing = true
            }
        }
    }
}

struct CalendarNotificationView: View {
    let event: EKEvent
    let timeUntil: String

    var body: some View {
        CalendarNotificationLayout(color: .accentColor, systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Starts \(timeUntil)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}