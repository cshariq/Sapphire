//
//  FocusWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import AppKit
import SwiftUI

struct FocusWidgetView: View {
    @EnvironmentObject private var focusManager: FocusSessionManager
    @ObservedSettings private var settings: SettingsObserver
    @Environment(\.navigationStack) private var navigationStack

    private var accent: Color { focusManager.isFocusBlock ? .green : .orange }
    private var accentColors: [Color] {
        focusManager.isFocusBlock ? [.green, .mint, .teal] : [.orange, .yellow, .pink]
    }

    private var phaseLabel: String {
        if focusManager.isPaused { return String(localized: "PAUSED") }
        return focusManager.isFocusBlock ? String(localized: "FOCUS") : String(localized: "BREAK")
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
        .animation(.default, value: focusManager.phase)
    }

    // MARK: - Primary readout

    @ViewBuilder
    private var primaryInfo: some View {
        HStack(spacing: 8) {
            if focusManager.isSessionActive {
                FocusWidgetTimerRing(
                    focusManager: focusManager,
                    accent: accent,
                    accentColors: accentColors
                )
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
                Group {
                    if focusManager.isSessionActive {
                        FocusWidgetCountdownText(focusManager: focusManager)
                    } else {
                        Text("Focus")
                    }
                }
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.4), value: focusManager.isSessionActive)

                Text(focusManager.isSessionActive ? phaseLabel : String(localized: "Ready to focus"))
                    .font(.headline).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(focusManager.isSessionActive ? accent : .secondary)

                Text(sessionSummary)
                    .font(.subheadline).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var sessionSummary: String {
        guard focusManager.isSessionActive else {
            return String(localized: "\(Int(settings.settings.focusSessionDuration / 60))m · \(FocusSessionManager.format(focusManager.completedToday)) today")
        }
        if blockedCount == 0 { return String(localized: "No distractions blocked") }
        if blockedCount == 1 { return String(localized: "Blocking 1 distraction") }
        return String(localized: "Blocking \(blockedCount) distractions")
    }

    // MARK: - Secondary stats (streak leads)

    private var secondaryInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            streakRow
            CompactInfoRow(iconName: "sun.max.fill", value: FocusSessionManager.format(focusManager.completedToday))
            CompactInfoRow(
                iconName: focusManager.isSessionActive ? "square.stack.3d.up.fill" : "checkmark.seal.fill",
                value: focusManager.isSessionActive
                    ? String(localized: "\(focusManager.blocksCompletedThisSession) blocks")
                    : String(localized: "\(String(focusManager.history.count)) sessions")
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
        return s == 1 ? String(localized: "1 day streak") : String(localized: "\(String(s)) day streak")
    }
}

@MainActor
private struct FocusWidgetTimerRing: View {
    @ObservedObject var focusManager: FocusSessionManager
    let accent: Color
    let accentColors: [Color]

    var body: some View {
        ZStack {
            LayerGradientProgressRing(
                motion: .focusBlock(focusManager),
                lineWidth: 4,
                colors: accentColors,
                shadowColor: accent.opacity(0.45),
                shadowRadius: 6,
                shadowIncludesTrack: true
            )
            Image(systemName: focusManager.isFocusBlock ? "figure.mind.and.body" : "cup.and.saucer.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accent)
                .shadow(color: accent.opacity(0.45), radius: 6)
        }
        .frame(width: 44, height: 44)
    }
}

@MainActor
private struct FocusWidgetCountdownText: View {
    let focusManager: FocusSessionManager

    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: 30, weight: .bold)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: 30) ?? base
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LayerNumericText(
                text: FocusSessionManager.format(focusManager.remaining(at: context.date)),
                font: Self.font,
                color: .white
            )
        }
    }
}