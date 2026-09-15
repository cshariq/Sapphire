//
//  TimerWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-04
//

import SwiftUI

struct TimerWidgetView: View {
    @EnvironmentObject private var timerManager: TimerManager
    @Environment(\.navigationStack) private var navigationStack

    @State private var showQuickStart = false

    private static let quickStartPresets: [Int] = [1, 5, 10, 30, 60]

    private var accentColor: Color {
        timerManager.activeTimer == .stopwatch ? .green : .orange
    }

    private var iconName: String {
        switch timerManager.activeTimer {
        case .stopwatch: return "stopwatch"
        case .system: return "timer"
        case .none: return "timer"
        }
    }

    var body: some View {
        Group {
            if timerManager.isRunning {
                activeContent
            } else if showQuickStart {
                quickStartContent
            } else {
                idleContent
            }
        }
        .animation(.default, value: timerManager.isRunning)
        .animation(.default, value: timerManager.displayTime)
        .animation(.default, value: showQuickStart)
    }

    // MARK: - Running (tap to open the full timer detail view)

    private var activeContent: some View {
        Button {
            Task {
                try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                navigationStack.wrappedValue.append(NotchWidgetMode.timerDetailView)
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accentColor)

                Text(timerManager.displayTime.asStopwatchClock)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText(countsDown: timerManager.activeTimer == .system))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .frame(height: 32)
        .fixedSize()
        .foregroundColor(.white)
        .contentShape(Rectangle())
        .help("Open Timers")
    }

    // MARK: - Idle (tap to expand quick-start presets)

    private var idleContent: some View {
        Button {
            showQuickStart = true
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))

                Text("No Timer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .frame(height: 32)
        .fixedSize()
        .contentShape(Rectangle())
        .help("Set a Timer")
    }

    // MARK: - Quick Start (one-tap Sapphire-owned timers)

    private var quickStartContent: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Self.quickStartPresets, id: \.self) { minutes in
                Button {
                    timerManager.startSapphireTimer(duration: TimeInterval(minutes * 60))
                    showQuickStart = false
                } label: {
                    Text(minutes >= 60 ? "1h" : "\(minutes)m")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Start \(minutes) minute timer")
            }

            Button {
                Task {
                    showQuickStart = false
                    try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
                    navigationStack.wrappedValue.append(NotchWidgetMode.timerDetailView)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Custom Duration…")

            Button {
                showQuickStart = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
    }
}