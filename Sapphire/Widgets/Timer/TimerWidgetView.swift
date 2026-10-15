//
//  TimerWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-04
//

import AppKit
import SwiftUI

struct TimerWidgetView: View {
    @EnvironmentObject private var timerManager: TimerManager
    @Environment(\.navigationStack) private var navigationStack
    @State private var selectedMinutes = 15

    private var accentColor: Color { timerManager.activeTimer == .stopwatch ? .green : .orange }
    private var iconName: String { timerManager.activeTimer == .stopwatch ? "stopwatch" : "timer" }

    var body: some View {
        Group {
            if timerManager.isRunning { activeContent } else { timerPicker }
        }
        .animation(.snappy(duration: 0.25), value: timerManager.isRunning)
    }

    private var activeContent: some View {
        Button(action: openDetail) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accentColor)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(timerManager.displayTime.asStopwatchClock)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
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

    private var timerPicker: some View {
        VStack(spacing: 5) {
            TimerDurationRuler(minutes: $selectedMinutes, range: 1...60, compact: true)
                .frame(width: 250, height: 49)
            HStack(spacing: 12) {
                Button {
                    _ = timerManager.startSapphireTimer(duration: TimeInterval(selectedMinutes * 60))
                } label: {
                    Text("Start Timer")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .frame(height: 29)
                        .background(Capsule().fill(Color.orange.opacity(0.22)))
                }
                .buttonStyle(TimerPillButtonStyle())
                .foregroundColor(.orange)
                .help("Start a \(selectedMinutes) minute timer")

                Spacer(minLength: 0)

                Button(action: openDetail) {
                    LayerNumericText(
                        text: String(format: "%d:00", selectedMinutes),
                        font: Self.pickerFont,
                        color: Self.pickerColor,
                        duration: 0.18
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Timers")
            }
            .frame(width: 234)
        }
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
    }

    private static let pickerFont: NSFont = {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 25, weight: .light)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: 25) ?? base
    }()

    private static let pickerColor = NSColor.notchResolved(.orange)

    private func openDetail() {
        Task {
            try? await Task.sleep(for: .seconds(NotchConfiguration.primaryWidgetSwitchDelay))
            navigationStack.wrappedValue.append(.timerDetailView)
        }
    }
}

struct TimerDurationRuler: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    var compact = false
    @State private var dragStartMinutes: Int?
    @State private var dragOffset: CGFloat = 0

    private var tickSpacing: CGFloat { compact ? 10 : 14 }
    private var minorHeight: CGFloat { compact ? 19 : 27 }
    private var majorHeight: CGFloat { compact ? 25 : 35 }
    private var pointerLaneHeight: CGFloat { compact ? 11 : 15 }

    var body: some View {
        GeometryReader { geometry in
            let midpoint = geometry.size.width / 2
            let rulerHeight = geometry.size.height - pointerLaneHeight
            ZStack(alignment: .topLeading) {
                ForEach(range, id: \.self) { value in
                    let x = midpoint + CGFloat(value - minutes) * tickSpacing + dragOffset
                    let isMajor = value % 5 == 0
                    if x > -tickSpacing, x < geometry.size.width + tickSpacing {
                        VStack(spacing: compact ? 3 : 5) {
                            if isMajor {
                                Text("\(value)")
                                    .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.orange.opacity(value == minutes ? 1 : 0.68))
                                    .frame(width: 30)
                            } else {
                                Color.clear.frame(width: 30, height: compact ? 11 : 13)
                            }
                            Capsule()
                                .fill(Color.orange.opacity(value == minutes ? 1 : (isMajor ? 0.88 : 0.7)))
                                .frame(width: value == minutes ? 2.5 : 2, height: isMajor ? majorHeight : minorHeight)
                                .shadow(color: .orange.opacity(value == minutes ? 0.75 : 0.32), radius: 2)
                        }
                        .position(x: x, y: rulerHeight / 2)
                    }
                }
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.12),
                        .init(color: .white, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(alignment: .bottom) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundColor(.orange)
                    .shadow(color: .orange.opacity(0.55), radius: 2)
                    .offset(y: compact ? 4 : 5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartMinutes ?? minutes
                        if dragStartMinutes == nil { dragStartMinutes = minutes }
                        let delta = Int((-value.translation.width / tickSpacing).rounded())
                        let nextMinutes = min(range.upperBound, max(range.lowerBound, start + delta))
                        dragOffset = value.translation.width + CGFloat(nextMinutes - start) * tickSpacing
                        if nextMinutes != minutes {
                            minutes = nextMinutes
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    }
                    .onEnded { value in
                        let currentMinutes = minutes
                        let start = dragStartMinutes ?? currentMinutes
                        let projectedDelta = Int((-value.predictedEndTranslation.width / tickSpacing).rounded())
                        let projectedMinutes = min(range.upperBound, max(range.lowerBound, start + projectedDelta))

                        dragOffset += CGFloat(projectedMinutes - currentMinutes) * tickSpacing
                        minutes = projectedMinutes
                        dragStartMinutes = nil
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.12)) {
                            dragOffset = 0
                        }
                    }
            )
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer duration")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = min(range.upperBound, minutes + 1)
            case .decrement: minutes = max(range.lowerBound, minutes - 1)
            @unknown default: break
            }
        }
    }
}

struct TimerPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}