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
                HStack(spacing: 6) {
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
                    .help("Start a \(selectedMinutes) minute timer")

                    Button(action: openDetail) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 29, height: 29)
                            .background(Circle().fill(Color.orange.opacity(0.14)))
                    }
                    .buttonStyle(TimerPillButtonStyle())
                    .help("Open Timers")
                    .accessibilityLabel("Open Timers")
                }
                .foregroundColor(.orange)

                Spacer(minLength: 0)

                LayerNumericText(
                    text: String(format: "%d:00", selectedMinutes),
                    font: Self.pickerFont,
                    color: Self.pickerColor,
                    duration: 0.18
                )
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
    @State private var scrollTranslation: CGFloat = 0

    private var tickSpacing: CGFloat { compact ? 10 : 14 }
    private var minorHeight: CGFloat { compact ? 19 : 27 }
    private var majorHeight: CGFloat { compact ? 25 : 35 }
    private var pointerLaneHeight: CGFloat { compact ? 11 : 15 }

    private static let settleAnimation = Animation.spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.12)

    var body: some View {
        GeometryReader { geometry in
            let midpoint = geometry.size.width / 2
            let rulerHeight = geometry.size.height - pointerLaneHeight
            ZStack(alignment: .topLeading) {
                ForEach(range, id: \.self) { value in
                    let x = midpoint + CGFloat(value - minutes) * tickSpacing + dragOffset
                    if x > -tickSpacing * 4, x < geometry.size.width + tickSpacing * 4 {
                        tick(value, focus: max(0, 1 - abs(x - midpoint) / tickSpacing))
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
                    .onChanged { value in track(value.translation.width) }
                    .onEnded { value in
                        if abs(value.translation.width) < 2, abs(value.translation.height) < 2 {
                            // A click on a tick picks it.
                            settle(on: minutes + Int(((value.location.x - midpoint) / tickSpacing).rounded()))
                        } else {
                            settle(projectedTranslation: value.predictedEndTranslation.width)
                        }
                    }
            )
            .overlay(
                TimerRulerScrollCapture(
                    onScroll: { delta in
                        scrollTranslation += delta
                        track(scrollTranslation)
                    },
                    onScrollEnd: { settle() },
                    onStep: { steps in settle(on: minutes + steps) }
                )
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

    /// `focus` is 1 for the bar right over the pointer and fades out one tick away, so the glow
    /// slides between bars while the ruler moves.
    private func tick(_ value: Int, focus: CGFloat) -> some View {
        let isMajor = value % 5 == 0
        return VStack(spacing: compact ? 3 : 5) {
            if isMajor {
                Text("\(value)")
                    .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
                    .foregroundColor(.orange.opacity(0.68 + 0.32 * focus))
                    .frame(width: 30)
            } else {
                Color.clear.frame(width: 30, height: compact ? 11 : 13)
            }
            Capsule()
                .fill(Color.orange.opacity((isMajor ? 0.88 : 0.7) + (isMajor ? 0.12 : 0.3) * focus))
                .overlay(Capsule().fill(Color.white.opacity(0.6 * focus)))
                .frame(width: 2, height: isMajor ? majorHeight : minorHeight)
                .scaleEffect(x: 1 + 0.6 * focus, y: 1 + 0.16 * focus)
                .shadow(color: .orange.opacity(0.32 + 0.63 * focus), radius: 2 + 2 * focus)
                .shadow(color: .orange.opacity(0.75 * focus), radius: 8 * focus)
        }
    }

    private func clamped(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// Follows a drag or scroll that has moved the ruler's content by `translation` points.
    private func track(_ translation: CGFloat) {
        let start = dragStartMinutes ?? minutes
        if dragStartMinutes == nil { dragStartMinutes = minutes }
        let next = clamped(start + Int((-translation / tickSpacing).rounded()))
        dragOffset = rubberBanded(translation + CGFloat(next - start) * tickSpacing)
        if next != minutes {
            minutes = next
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// Past either end the content stretches with resistance instead of sliding freely.
    private func rubberBanded(_ offset: CGFloat) -> CGFloat {
        let free = tickSpacing / 2
        guard abs(offset) > free else { return offset }
        let reach = tickSpacing * 3
        let excess = abs(offset) - free
        let stretched = free + reach * (1 - 1 / (excess / reach + 1))
        return offset < 0 ? -stretched : stretched
    }

    private func settle(projectedTranslation: CGFloat) {
        let start = dragStartMinutes ?? minutes
        settle(on: start + Int((-projectedTranslation / tickSpacing).rounded()))
    }

    /// Snaps the bar nearest the pointer under it, after moving to `target` when given.
    private func settle(on target: Int? = nil) {
        let next = clamped(target ?? minutes)
        if next != minutes {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        dragStartMinutes = nil
        scrollTranslation = 0
        withAnimation(Self.settleAnimation) {
            minutes = next
            dragOffset = 0
        }
    }
}

/// Two-finger scrolls on either axis and mouse-wheel clicks over the ruler slide it, without
/// pressing. While it takes them the notch's own swipe gestures leave them alone.
private struct TimerRulerScrollCapture: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onScrollEnd: () -> Void
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> TimerRulerScrollView {
        TimerRulerScrollView()
    }

    func updateNSView(_ view: TimerRulerScrollView, context: Context) {
        view.onScroll = onScroll
        view.onScrollEnd = onScrollEnd
        view.onStep = onStep
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TimerRulerScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 10, height: proposal.height ?? 10)
    }

    static func dismantleNSView(_ view: TimerRulerScrollView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class TimerRulerScrollView: NSView, NotchScrollClaiming {
    var onScroll: (CGFloat) -> Void = { _ in }
    var onScrollEnd: () -> Void = {}
    var onStep: (Int) -> Void = { _ in }

    private var monitor: Any?
    private var isTracking = false
    /// The last gesture lifted here, so its momentum is ours even if it starts late.
    private var ownsMomentum = false
    private var didScroll = false
    private var isHorizontal: Bool?
    private var lastEventTime: CFTimeInterval = 0
    private var pendingEnd: DispatchWorkItem?

    /// How long a lifted gesture waits for momentum before the ruler snaps.
    private static let momentumWait: TimeInterval = 0.06
    /// A gesture that stops sending events (its window lost them) is over.
    private static let staleGesture: CFTimeInterval = 0.5

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopMonitoring() } else { startMonitoring() }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        NotchScrollClaims.add(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.claimsScroll(event) else { return false }
                self.handle(event)
                return true
            }
            return consumed ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotchScrollClaims.remove(self)
        pendingEnd?.cancel()
        pendingEnd = nil
        isTracking = false
        ownsMomentum = false
        didScroll = false
    }

    func claimsScroll(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let isFresh = CACurrentMediaTime() - lastEventTime < Self.staleGesture
        if isTracking {
            if isFresh { return true }
            finishGesture()
        }
        if ownsMomentum, !event.momentumPhase.isEmpty, isFresh { return true }
        // Only a gesture that starts here; momentum or a scroll that slid in belongs elsewhere.
        guard event.momentumPhase.isEmpty,
              event.phase.isEmpty || !event.phase.isDisjoint(with: [.began, .mayBegin]),
              isEffectivelyVisible else { return false }
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    private var isEffectivelyVisible: Bool {
        var view: NSView? = self
        while let current = view {
            if current.isHidden || current.alphaValue < 0.05 || (current.layer?.opacity ?? 1) < 0.05 { return false }
            view = current.superview
        }
        return true
    }

    private func handle(_ event: NSEvent) {
        lastEventTime = CACurrentMediaTime()
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        guard event.hasPreciseScrollingDeltas else {
            // A wheel click is one minute; faster spins move more.
            let delta = abs(dx) > abs(dy) ? dx : dy
            guard delta != 0 else { return }
            let steps = max(1, Int(abs(delta).rounded()))
            onStep(delta > 0 ? -steps : steps)
            return
        }

        if !event.phase.isDisjoint(with: [.began, .mayBegin]) {
            pendingEnd?.cancel()
            pendingEnd = nil
            isTracking = true
            ownsMomentum = false
            isHorizontal = nil
        }
        if event.momentumPhase.contains(.began) {
            pendingEnd?.cancel()
            pendingEnd = nil
            isTracking = true
        }

        if dx != 0 || dy != 0 {
            let horizontal = isHorizontal ?? (abs(dx) >= abs(dy))
            isHorizontal = horizontal
            didScroll = true
            onScroll(horizontal ? dx : dy)
        }

        if !event.momentumPhase.isDisjoint(with: [.ended, .cancelled]) {
            ownsMomentum = false
            finishGesture()
        } else if !event.phase.isDisjoint(with: [.ended, .cancelled]) {
            ownsMomentum = true
            let end = DispatchWorkItem { [weak self] in self?.finishGesture() }
            pendingEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.momentumWait, execute: end)
        }
    }

    private func finishGesture() {
        pendingEnd?.cancel()
        pendingEnd = nil
        isTracking = false
        isHorizontal = nil
        if didScroll {
            didScroll = false
            onScrollEnd()
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