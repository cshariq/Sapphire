//
//  TimerDetailView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-26
//

import SwiftUI

struct TimerDetailView: View {
    @EnvironmentObject var timerManager: TimerManager
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        VStack(spacing: 16) {
            if timerManager.activeTimers.isEmpty && timerManager.activeStopwatches.isEmpty {
                Text("No Active Timers or Stopwatches")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
            } else {
                if !timerManager.activeTimers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timers")
                            .font(.title3.bold())
                            .foregroundColor(.orange)
                        ForEach(timerManager.activeTimers) { timer in
                            HStack {
                                Image(systemName: "timer")
                                Text(formatTime(timer.remainingTime))
                                    .contentTransition(.numericText(countsDown: true))
                                Spacer()
                                Text(timer.state == .system ? "Running" : "Paused")
                                    .font(.caption)
                                    .foregroundColor(timer.state == .system ? .orange : .secondary)

                            }
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .buttonStyle(.plain)
                            .font(.title3)
                        }
                    }
                }

                if !timerManager.activeStopwatches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stopwatches")
                            .font(.title3.bold())
                            .foregroundColor(.green)
                        ForEach(timerManager.activeStopwatches) { stopwatch in
                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: "stopwatch")
                                    Text(formatTime(stopwatch.elapsedTime))
                                        .contentTransition(.numericText())
                                    Spacer()
                                    Text(stopwatch.state == .stopwatch ? "Running" : "Paused")
                                        .font(.caption)
                                        .foregroundColor(stopwatch.state == .stopwatch ? .green : .secondary)
                                }
                                .font(.system(.body, design: .monospaced).weight(.medium))
                                .font(.title3)

                                if !stopwatch.laps.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(stopwatch.laps.indices.reversed(), id: \.self) { index in
                                            HStack {
                                                Text("Lap \(index + 1)")
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Text(formatTime(stopwatch.laps[index]))
                                            }
                                            .font(.system(.callout, design: .monospaced))
                                        }
                                    }
                                    .padding(.leading, 28)
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 350)
        .animation(.default, value: timerManager.activeTimers)
        .animation(.default, value: timerManager.activeStopwatches)
        .animation(.default, value: timerManager.displayTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}