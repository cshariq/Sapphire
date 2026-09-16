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
    let category: String
    let onDismiss: () -> Void
    let onSnooze: () -> Void
    let details: Details

    @State private var isShowing = false

    init(
        color: Color,
        systemImage: String,
        category: String,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        @ViewBuilder details: () -> Details
    ) {
        self.color = color
        self.systemImage = systemImage
        self.category = category
        self.onDismiss = onDismiss
        self.onSnooze = onSnooze
        self.details = details()
    }

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 0.75)
                        }

                    Image(systemName: systemImage)
                        .font(.system(size: 23, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .shadow(color: color.opacity(0.28), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 5) {
                    Text(category.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.15)
                        .foregroundStyle(color)

                    details
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 9) {
                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CalendarActivityButtonStyle())
                .help("Dismiss this notification")

                Button(action: onSnooze) {
                    Label("Snooze 5 min", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CalendarActivityButtonStyle(color: color, isProminent: true))
                .help("Show this notification again in five minutes")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 15)
        .padding(.top, NotchConfiguration.universalHeight)
        .frame(width: 390)
        .scaleEffect(isShowing ? 1 : 0.97)
        .opacity(isShowing ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                isShowing = true
            }
        }
    }
}

private struct CalendarActivityButtonStyle: ButtonStyle {
    var color: Color = .white
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(isProminent ? .white : .white.opacity(0.88))
            .padding(.vertical, 9)
            .background {
                Capsule()
                    .fill(isProminent ? color.opacity(0.9) : .white.opacity(0.1))
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(isProminent ? 0.16 : 0.1), lineWidth: 0.75)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct CalendarNotificationView: View {
    let event: EKEvent
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
                    eventIDs: [event.eventIdentifier].compactMap { $0 }
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
                Text("Starts \(timeUntil)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "location.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
        }
    }
}