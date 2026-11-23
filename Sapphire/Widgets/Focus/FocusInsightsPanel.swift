//
//  FocusInsightsPanel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import SwiftUI

struct FocusInsightsPanel: View {
    @ObservedObject var manager: FocusSessionManager

    private var week: [(label: String, seconds: TimeInterval)] { manager.weeklyData }
    private var maxWeek: TimeInterval { max(week.map(\.seconds).max() ?? 1, 1) }
    private var snapshot: FocusStreakSnapshot { manager.streakSnapshot }

    var body: some View {
        SettingsCard(title: "Overview") {
            HStack(spacing: 10) {
                metric("Today", Self.compact(manager.completedToday))
                metric("Streak", Self.compactDays(snapshot.streak))
                metric("All Time", Self.compact(manager.totalFocusTimeAllTime))
                metric("Average", Self.compact(manager.averageSessionDuration))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider().padding(.leading, 20)

            Text("This Week")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.seconds > 0 ? Color.accentColor : Color.white.opacity(0.08))
                            .frame(height: max(4, CGFloat(day.seconds / maxWeek) * 80))
                        Text(day.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 104)
            .padding(.horizontal)
            .padding(.bottom, 12)

            if !manager.history.isEmpty {
                Divider().padding(.leading, 20)
                Text("Recent Sessions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(Array(manager.history.prefix(5).enumerated()), id: \.element.id) { index, session in
                        HStack {
                            Text(session.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Self.compact(session.actualDuration))
                                .monospacedDigit()
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        if index < min(4, manager.history.count - 1) {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static func compactDays(_ days: Int) -> String {
        guard ChineseFormatting.isActive else { return "\(days)d" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: DateComponents(day: max(0, days))) ?? String(localized: "0d")
    }

    static func compact(_ seconds: TimeInterval) -> String {
        guard ChineseFormatting.isActive else {
            let total = Int(seconds)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            if hours > 0 { return "\(hours)h \(minutes)m" }
            if minutes > 0 { return "\(minutes)m" }
            return "0m"
        }
        let minutes = max(0, Int(seconds.isFinite ? seconds / 60 : 0))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: TimeInterval(minutes * 60)) ?? String(localized: "0m")
    }
}