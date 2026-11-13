//
//  FocusSessionActivityView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import AppKit
import SwiftUI

@MainActor
struct FocusSessionActivityView {
    static func left() -> some View {
        FocusSessionActivitySideView(side: .left)
    }

    static func right() -> some View {
        FocusSessionActivitySideView(side: .right)
    }
}

@MainActor
private struct FocusSessionActivitySideView: View {
    @ObservedObject private var focusManager = FocusSessionManager.shared
    let side: Side

    enum Side { case left, right }

    private var settings: Settings { SettingsModel.shared.settings }
    private var mode: FocusStatus { FocusModeManager.shared.currentStatus }
    private var showsTimeInsteadOfRing: Bool { settings.focusSessionLiveActivityShowTime }

    private var ringColors: [Color] {
        focusManager.isFocusBlock ? [.indigo, .purple, .blue] : [.orange, .yellow, .pink]
    }

    var body: some View {
        if side == .left {
            leftContent
        } else {
            rightContent
        }
    }

    // MARK: - Left: indigo moon

    private var leftContent: some View {
        ZStack {
            Image(systemName: "moon.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.95), Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Right: completing ring (or time)

    @ViewBuilder
    private var rightContent: some View {
        FocusSessionActivityClockView(
            focusManager: focusManager,
            showsTimeInsteadOfRing: showsTimeInsteadOfRing,
            ringColors: ringColors,
            mode: mode,
            displayMode: settings.focusDisplayMode
        )
    }
}

@MainActor
private struct FocusSessionActivityClockView: View {
    @ObservedObject var focusManager: FocusSessionManager
    let showsTimeInsteadOfRing: Bool
    let ringColors: [Color]
    let mode: FocusStatus
    let displayMode: FocusDisplayMode

    private static let clockFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    @ViewBuilder
    var body: some View {
        if showsTimeInsteadOfRing {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .trailing, spacing: 0) {
                    LayerNumericText(
                        text: FocusSessionManager.format(focusManager.remaining(at: context.date)),
                        font: Self.clockFont,
                        color: TimerActivityView.primaryTextColor
                    )
                    Text(subLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(subLabelColor)
                }
                .padding(.horizontal, 5)
            }
        } else {
            LayerGradientProgressRing(
                motion: .focusBlock(focusManager, minimum: 0.001),
                lineWidth: 2.5,
                trackLineWidth: 5,
                trackColor: Color.white.opacity(0.22),
                colors: ringColors,
                catchUpDuration: 0.5
            )
            .frame(width: 18, height: 18)
        }
    }

    private var subLabel: String {
        if mode.isActive {
            if displayMode == .compact { return String(localized: "On") }
            return mode.name
        }
        return focusManager.isFocusBlock ? String(localized: "Focus") : String(localized: "Break")
    }

    private var subLabelColor: Color {
        if mode.isActive { return .white.opacity(0.85) }
        return focusManager.isFocusBlock ? Color.indigo : Color.orange
    }
}