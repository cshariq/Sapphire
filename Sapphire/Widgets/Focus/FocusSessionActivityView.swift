//
//  FocusSessionActivityView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

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
        if showsTimeInsteadOfRing {
            timeContent
        } else {
            ringContent
        }
    }

    private var ringContent: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, focusManager.progress))
                .stroke(
                    AngularGradient(colors: ringColors, center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: focusManager.progress)
        }
        .frame(width: 18, height: 18)
    }

    private var timeContent: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(focusManager.remainingLabel)
                .font(.system(size: 13, design: .monospaced).weight(.semibold))
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: focusManager.remainingSeconds)
            Text(subLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(subLabelColor)
        }
        .padding(.horizontal, 5)
    }

    private var subLabel: String {
        if mode.isActive {
            if SettingsModel.shared.settings.focusDisplayMode == .compact { return "On" }
            return mode.name
        }
        return focusManager.isFocusBlock ? "Focus" : "Break"
    }

    private var subLabelColor: Color {
        if mode.isActive { return .white.opacity(0.85) }
        return focusManager.isFocusBlock ? Color.indigo : Color.orange
    }
}