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

    @State private var presetMinutes: Int = 5
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 5
    @State private var customSeconds: Int = 0
    @State private var useCustomDuration: Bool = false
    @State private var timerLabel: String = ""

    private static let presetMinutesOptions = [1, 3, 5, 10, 15, 30, 60]

    var body: some View {
        VStack(spacing: 16) {
            quickStartSection
            sapphireTimersSection
            systemTimersSection
            systemStopwatchesSection

            if timerManager.activeTimers.isEmpty
                && timerManager.activeStopwatches.isEmpty
                && timerManager.sapphireTimers.isEmpty {
                Text("No Active Timers or Stopwatches")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .frame(minWidth: 350)
        .animation(.default, value: timerManager.activeTimers)
        .animation(.default, value: timerManager.activeStopwatches)
        .animation(.default, value: timerManager.displayTime)
        .animation(.default, value: timerManager.sapphireTimers)
    }

    // MARK: - Quick Start (Sapphire-owned timers)

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Timer")
                .font(.title3.bold())
                .foregroundColor(.orange)

            HStack(spacing: 8) {
                ForEach(Self.presetMinutesOptions, id: \.self) { minutes in
                    Button {
                        useCustomDuration = false
                        presetMinutes = minutes
                    } label: {
                        Text(minutes >= 60 ? "1 hr" : "\(minutes) min")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    !useCustomDuration && presetMinutes == minutes
                                        ? Color.orange.opacity(0.85)
                                        : Color.white.opacity(0.12)
                                )
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            DisclosureGroup(isExpanded: $useCustomDuration) {
                HStack(spacing: 12) {
                    durationStepper(value: $customHours, range: 0...23, label: "hr")
                    durationStepper(value: $customMinutes, range: 0...59, label: "min")
                    durationStepper(value: $customSeconds, range: 0...59, label: "sec")
                }
                .padding(.top, 8)
            } label: {
                Text("Custom Duration")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }

            HStack(spacing: 8) {
                TextField("Label (optional)", text: $timerLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))

                Button {
                    startTimer()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.orange))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(selectedDuration <= 0)
                .opacity(selectedDuration <= 0 ? 0.4 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedDuration: TimeInterval {
        if useCustomDuration {
            return TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
        }
        return TimeInterval(presetMinutes * 60)
    }

    private func durationStepper(value: Binding<Int>, range: ClosedRange<Int>, label: String) -> some View {
        Stepper("\(value.wrappedValue) \(label)", value: value, in: range)
            .font(.system(size: 13, design: .monospaced))
    }

    private func startTimer() {
        let duration = selectedDuration
        guard duration > 0 else { return }
        let label = timerLabel.trimmingCharacters(in: .whitespaces)
        _ = timerManager.startSapphireTimer(duration: duration, label: label.isEmpty ? nil : label)
        timerLabel = ""
    }

    // MARK: - Sapphire-Owned Timers

    @ViewBuilder
    private var sapphireTimersSection: some View {
        let timers = timerManager.sapphireTimers
        if !timers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sapphire Timers")
                        .font(.title3.bold())
                        .foregroundColor(.orange)
                    Spacer()
                    if timers.contains(where: { $0.remainingTime <= 0 }) {
                        Button("Clear Finished") {
                            timerManager.clearFinishedSapphireTimers()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.orange)
                    }
                }

                ForEach(timers) { timer in
                    HStack {
                        Image(systemName: timer.isRunning ? "timer" : "timer.pause")
                            .foregroundColor(timer.isRunning ? .orange : .secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(timer.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(timer.remainingTime.asStopwatchClock)
                                .contentTransition(.numericText(countsDown: true))
                                .font(.system(.title3, design: .monospaced).weight(.medium))
                        }

                        Spacer()

                        if timer.remainingTime <= 0 {
                            Text("Done")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text(timer.isRunning ? "Running" : "Paused")
                                .font(.caption)
                                .foregroundColor(timer.isRunning ? .orange : .secondary)
                        }

                        controls(for: timer)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func controls(for timer: SapphireTimer) -> some View {
        HStack(spacing: 6) {
            if timer.remainingTime <= 0 {
                controlButton("checkmark", accent: .orange) {
                    timerManager.clearFinishedSapphireTimers()
                }
            } else if timer.isRunning {
                controlButton("pause.fill", accent: .orange) {
                    timerManager.pauseSapphireTimer(id: timer.id)
                }
                controlButton("hourglass.badge.plus", accent: .orange) {
                    timerManager.addOneMinuteToSapphireTimer(id: timer.id)
                }
                .help("Add 1 minute")
                controlButton("stop.fill", accent: .red) {
                    timerManager.removeSapphireTimer(id: timer.id)
                }
                .help("Stop timer")
            } else {
                controlButton("play.fill", accent: .green) {
                    timerManager.resumeSapphireTimer(id: timer.id)
                }
                controlButton("stop.fill", accent: .red) {
                    timerManager.removeSapphireTimer(id: timer.id)
                }
                .help("Remove timer")
            }
        }
    }

    private func controlButton(_ systemImage: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(accent.opacity(0.18)))
                .foregroundColor(accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - System Timers & Stopwatches (detected from the Clock app)

    @ViewBuilder
    private var systemTimersSection: some View {
        if !timerManager.activeTimers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Timers")
                    .font(.title3.bold())
                    .foregroundColor(.orange)
                ForEach(timerManager.activeTimers) { timer in
                    HStack {
                        Image(systemName: "timer")
                        Text(timer.remainingTime.asStopwatchClock)
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
    }

    @ViewBuilder
    private var systemStopwatchesSection: some View {
        if !timerManager.activeStopwatches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stopwatches")
                    .font(.title3.bold())
                    .foregroundColor(.green)
                ForEach(timerManager.activeStopwatches) { stopwatch in
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "stopwatch")
                            Text(stopwatch.elapsedTime.asStopwatchClock)
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
                                        Text(stopwatch.laps[index].asStopwatchClock)
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