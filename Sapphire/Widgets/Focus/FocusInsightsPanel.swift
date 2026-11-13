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
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            HStack(spacing: 12) {
                metric("Today", Self.compact(manager.completedToday), "sun.max.fill", .orange)
                metric("Streak", Self.compactDays(snapshot.streak), "flame.fill", .orange)
                metric("All time", Self.compact(manager.totalFocusTimeAllTime), "clock.fill", .purple)
                metric("Avg", Self.compact(manager.averageSessionDuration), "gauge.with.dots.needle.33percent", .cyan)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 14)

            Divider().opacity(0.25).padding(.horizontal, 16)

            Text("This week")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            GeometryReader { geo in
                let barWidth = max(8, (geo.size.width - CGFloat(max(week.count - 1, 0)) * 8) / CGFloat(max(week.count, 1)))
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    day.seconds > 0
                                    ? LinearGradient(
                                        colors: [Color.purple.opacity(0.95), Color.indigo.opacity(0.75)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                      )
                                    : LinearGradient(
                                        colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.06)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                      )
                                )
                                .frame(
                                    width: barWidth,
                                    height: max(6, CGFloat(day.seconds / maxWeek) * 88)
                                )
                            Text(day.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 118)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if !manager.history.isEmpty {
                Divider().opacity(0.25).padding(.horizontal, 16)
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    ForEach(Array(manager.history.prefix(5).enumerated()), id: \.element.id) { index, session in
                        HStack {
                            Text(session.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Self.compact(session.actualDuration))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        if index < min(4, manager.history.count - 1) {
                            Divider().opacity(0.2).padding(.leading, 16)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .modifier(SettingsContainerModifier())
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insights")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 14)
            Text("One place for how you’ve been focusing — not three competing charts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
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