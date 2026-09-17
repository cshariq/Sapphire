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
            } else {
                quickStartContent
            }
        }
        .animation(.default, value: timerManager.isRunning)
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

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let displayTime = timerManager.displayTime
                    Text(displayTime.asStopwatchClock)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText(countsDown: timerManager.activeTimer == .system))
                        .animation(.default, value: Int(displayTime))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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

    // MARK: - Quick Start (one-tap Sapphire-owned timers)

    private var quickStartContent: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Self.quickStartPresets, id: \.self) { minutes in
                Button {
                    _ = timerManager.startSapphireTimer(duration: TimeInterval(minutes * 60))
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
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
    }
}