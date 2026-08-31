//
//  FocusWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import SwiftUI

struct FocusWidgetView: View {
    @EnvironmentObject private var focusManager: FocusSessionManager
    @EnvironmentObject private var settings: SettingsModel
    @Environment(\.navigationStack) private var navigationStack

    private var accent: Color { focusManager.isFocusBlock ? .green : .orange }
    private var accentColors: [Color] {
        focusManager.isFocusBlock ? [.green, .mint, .teal] : [.orange, .yellow, .pink]
    }

    private var phaseLabel: String {
        if focusManager.isPaused { return "PAUSED" }
        return focusManager.isFocusBlock ? "FOCUS" : "BREAK"
    }

    private var blockedCount: Int {
        guard focusManager.isBlockingActive else { return 0 }
        return settings.settings.focusBlockedApps.count + settings.settings.focusBlockedWebsites.count
    }

    var body: some View {
        Button {
            Task {
                try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                navigationStack.wrappedValue.append(NotchWidgetMode.focusSessionDetailView)
            }
        } label: {
            ZStack {
                HStack(alignment: .center, spacing: 10) {
                    primaryInfo.layoutPriority(1)
                    secondaryInfo
                }
                .padding(.horizontal, 10)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 200, minHeight: 90)
        .fixedSize()
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .animation(.default, value: focusManager.remainingSeconds)
        .animation(.default, value: focusManager.phase)
    }

    // MARK: - Primary readout

    @ViewBuilder
    private var primaryInfo: some View {
        HStack(spacing: 8) {
            if focusManager.isSessionActive {
                ring
            } else {
                Image(systemName: "moon.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(radius: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(focusManager.isSessionActive ? focusManager.remainingLabel : "Focus")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .id(focusManager.isSessionActive ? focusManager.remainingLabel : "focus")
                    .contentTransition(.numericText(countsDown: focusManager.isSessionActive))
                    .animation(.easeInOut(duration: 0.4), value: focusManager.isSessionActive)

                Text(focusManager.isSessionActive ? phaseLabel : "Ready to focus")
                    .font(.headline).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(focusManager.isSessionActive ? accent : .secondary)

                Text(focusManager.isSessionActive
                     ? (blockedCount > 0 ? "Blocking \(blockedCount) distraction\(blockedCount == 1 ? "" : "s")" : "No distractions blocked")
                     : "\(Int(settings.settings.focusSessionDuration / 60))m · \(FocusSessionManager.format(focusManager.completedToday)) today")
                    .font(.subheadline).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: focusManager.progress)
                .stroke(
                    AngularGradient(colors: accentColors, center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: focusManager.isFocusBlock ? "figure.mind.and.body" : "cup.and.saucer.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accent)
        }
        .frame(width: 44, height: 44)
        .shadow(color: accent.opacity(0.45), radius: 6)
    }

    // MARK: - Secondary stats (streak leads)

    private var secondaryInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            streakRow
            CompactInfoRow(iconName: "sun.max.fill", value: FocusSessionManager.format(focusManager.completedToday))
            CompactInfoRow(
                iconName: focusManager.isSessionActive ? "square.stack.3d.up.fill" : "checkmark.seal.fill",
                value: focusManager.isSessionActive
                    ? "\(focusManager.blocksCompletedThisSession) blocks"
                    : "\(focusManager.history.count) sessions"
            )
        }
        .animation(.easeInOut(duration: 0.4), value: focusManager.isSessionActive)
        .animation(.default, value: focusManager.currentStreak)
    }

    private var streakRow: some View {
        HStack(spacing: 5) {
            StreakFlame(size: 20, isActive: focusManager.currentStreak > 0)

            Text(streakText)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .id(streakText)
        .transition(.opacity)
    }

    private var streakText: String {
        let s = focusManager.currentStreak
        return s == 1 ? "1 day streak" : "\(s) day streak"
    }
}