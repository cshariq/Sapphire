//
//  Helpers.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04.
//

import Foundation
import SwiftUI
import AppKit
import IOKit

public class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue

    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    public func debounce(action: @escaping (() -> Void)) {
        workItem?.cancel()
        let newWorkItem = DispatchWorkItem(block: action)
        workItem = newWorkItem
        queue.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }

    public func cancel() {
        workItem?.cancel()
    }

    func flush() {
        workItem?.perform()
        workItem?.cancel()
        workItem = nil
    }
}

public func haptic(strength: HapticFeedbackType = .strong) {
    if SettingsModel.shared.settings.hapticFeedbackEnabled {
        HapticManager.shared.perform(strength)
    }
}

func relativeTimeAbbreviated(from date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    guard interval >= 60 else { return "just now" }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
    formatter.maximumUnitCount = 1
    formatter.unitsStyle = .short
    formatter.includesTimeRemainingPhrase = false
    formatter.includesApproximationPhrase = false
    guard let formatted = formatter.string(from: interval) else { return "just now" }
    return formatted + " ago"
}

struct RelativeMinuteText: View {
    let date: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Text(relativeTimeAbbreviated(from: date))
        }
    }
}

struct SizeLoggingViewModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            print("[\(label) LOG] Appeared with size: \(geometry.size)")
                        }
                        .onChange(of: geometry.size) { oldSize, newSize in
                            print("[\(label) LOG] Resized to: \(newSize)")
                        }
                }
            )
    }
}

struct SeekButton: View {
    let systemName: String
    let onTap: () -> Void
    let onSeek: (Bool) -> Void
    var onLongPressAction: (() -> Void)? = nil
    var holdAction: MusicLongPressAction? = nil
    var onHoldBegan: ((MusicLongPressAction) -> Void)? = nil
    var onHoldEnded: (() -> Void)? = nil
    var displayedSystemName: String? = nil

    @GestureState private var isPressing = false
    @State private var longPressTimer: Timer?
    @State private var seekTimer: Timer?
    @State private var repeatTimer: Timer?
    @State private var tapIsEligible = false
    @State private var didFireLongPress = false

    private var isForward: Bool {
        systemName.contains("forward")
    }

    private var iconName: String { displayedSystemName ?? systemName }

    var body: some View {
        Image(systemName: iconName)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in
                        state = true
                    }
            )
            .onChange(of: isPressing) { _, nowPressing in
                if nowPressing {
                    tapIsEligible = true
                    didFireLongPress = false
                    longPressTimer?.invalidate()
                    seekTimer?.invalidate()
                    repeatTimer?.invalidate()
                    let timer = Timer(timeInterval: 0.45, repeats: false) { _ in
                        tapIsEligible = false
                        if let onLongPressAction {
                            didFireLongPress = true
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            if let holdAction {
                                onHoldBegan?(holdAction)
                            }
                            onLongPressAction()
                            if holdAction?.isRepeatableWhileHeld == true {
                                let repeating = Timer(timeInterval: 0.55, repeats: true) { _ in
                                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                    onLongPressAction()
                                }
                                RunLoop.main.add(repeating, forMode: .common)
                                repeatTimer = repeating
                            }
                        } else {
                            startSeeking()
                        }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    longPressTimer = timer
                } else {
                    longPressTimer?.invalidate()
                    seekTimer?.invalidate()
                    seekTimer = nil
                    repeatTimer?.invalidate()
                    repeatTimer = nil
                    if didFireLongPress {
                        onHoldEnded?()
                    } else if tapIsEligible {
                        onTap()
                    }
                    didFireLongPress = false
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .blur(radius: (isPressing && !didFireLongPress) ? 3 : 0)
            .scaleEffect(isPressing ? 0.92 : 1.0)
            .opacity((isPressing && !didFireLongPress) ? 0.85 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isPressing)
            .animation(.easeInOut(duration: 0.15), value: iconName)
            .animation(.easeInOut(duration: 0.12), value: didFireLongPress)
    }

    private func startSeeking() {
        seekTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            onSeek(isForward)
        }
        RunLoop.main.add(timer, forMode: .common)
        seekTimer = timer
    }
}

struct BlurButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .blur(radius: configuration.isPressed ? 4 : 0)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct InteractiveProgressBar: View {
    @Binding var value: Double
    var gradient: Gradient
    var onSeek: (Double) -> Void
    var onDragChanged: ((Double) -> Void)? = nil
    var duration: TimeInterval? = nil
    var trackHeight: CGFloat = 10
    var trackColor: Color = Color.secondary.opacity(0.3)
    var glassIntensity: Double = 0.65

    @State private var isDragging = false
    @State private var dragValue: Double = 0.0
    @State private var isHovering = false
    @State private var hoverX: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let displayed = isDragging ? dragValue : value
            let clampedDisplayed = ProgressScrubMath.clampProgress(displayed)
            let hoverProgress = ProgressScrubMath.progress(fromX: hoverX, width: width)
            let pointerProgress = isDragging ? dragValue : hoverProgress
            let thumbSize = ProgressScrubMath.thumbDiameter(trackHeight: trackHeight)
            let showChrome = (isHovering || isDragging) && width > 0
            let tooltipText = ProgressScrubMath.tooltipTime(
                progress: pointerProgress,
                duration: duration ?? 0
            )
            let fillEdgeX = width * CGFloat(clampedDisplayed)
            let thumbColor = ProgressScrubMath.color(at: clampedDisplayed, in: gradient)
            let tooltipX = isDragging ? fillEdgeX : hoverX

            ZStack {
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor)

                    Capsule()
                        .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, fillEdgeX))

                    if showChrome, hoverProgress > clampedDisplayed {
                        let start = fillEdgeX
                        let end = width * CGFloat(hoverProgress)
                        Capsule()
                            .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                            .opacity(0.35)
                            .frame(width: max(0, end - start))
                            .offset(x: start)
                    }
                }
                .frame(height: trackHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transaction { transaction in
                    if !isDragging {
                        transaction.animation = nil
                    }
                }

                if showChrome {
                    ProgressScrubThumb(diameter: thumbSize, color: thumbColor)
                        .position(x: fillEdgeX, y: geometry.size.height / 2)
                        .transition(.opacity)

                    if let tooltipText {
                        ProgressScrubTooltip(text: tooltipText, intensity: glassIntensity)
                            .position(
                                x: tooltipX,
                                y: geometry.size.height / 2 - thumbSize / 2 - 16
                            )
                            .transition(.opacity)
                    }
                }
            }
            .compositingGroup()
            .background {
                ScrubHoverTracker { hovering, x in
                    if hovering {
                        isHovering = true
                        hoverX = max(0, min(x, width))
                    } else if !isDragging {
                        isHovering = false
                    }
                }
            }
            .background(CursorRectView(cursor: .pointingHand))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gestureValue in
                        if !isDragging {
                            isDragging = true
                            dragValue = value
                        }
                        let newProgress = ProgressScrubMath.progress(
                            fromX: gestureValue.location.x,
                            width: width
                        )
                        dragValue = newProgress
                        hoverX = gestureValue.location.x
                        onDragChanged?(newProgress)
                    }
                    .onEnded { gestureValue in
                        let finalProgress = ProgressScrubMath.progress(
                            fromX: gestureValue.location.x,
                            width: width
                        )
                        dragValue = finalProgress
                        onSeek(finalProgress)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            value = finalProgress
                            isDragging = false
                        }
                    }
            )
        }
    }
}

/// AppKit cursor rects — `NSCursor.set()` from SwiftUI hover is reset by the system.
private struct CursorRectView: NSViewRepresentable {
    var cursor: NSCursor

    func makeNSView(context: Context) -> CursorHostingView {
        CursorHostingView(cursor: cursor)
    }

    func updateNSView(_ nsView: CursorHostingView, context: Context) {
        guard nsView.cursor != cursor else { return }
        nsView.cursor = cursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    final class CursorHostingView: NSView {
        var cursor: NSCursor

        init(cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct PlayCountIndicator: View {
    let playCount: Int
    private var color: Color {
        if playCount > 500_000_000 { return .green }
        if playCount > 100_000_000 { return .yellow }
        if playCount > 10_000_000 { return .secondary }
        return .secondary.opacity(0.5)
    }
    private func formatNumber(_ n: Int) -> String {
        let num = Double(n)
        if num >= 1_000_000_000 { return String(format: "%.1fB", num / 1_000_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000 { return String(format: "%.1fK", num / 1_000).replacingOccurrences(of: ".0", with: "") }
        return "\(n)"
    }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 7, weight: .black))
            Text(formatNumber(playCount))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
        .help("Total Plays: \(playCount.formatted())")
    }
}

struct PopularityIndicator: View {
    let popularity: Int
    private var color: Color {
        if popularity >= 75 { return .green }
        if popularity >= 40 { return .yellow }
        return .secondary
    }
    private var estimatedPlays: Int {
        let p = Double(popularity)
        let basePlays = pow(p / 10, 4) * 100
        let randomFactor = Double.random(in: 0.8...1.2)
        return Int(basePlays * randomFactor)
    }
    private func formatNumber(_ n: Int) -> String {
        let num = Double(n)
        if num >= 1_000_000_000 { return String(format: "%.1fB", num / 1_000_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000 { return String(format: "%.1fK", num / 1_000).replacingOccurrences(of: ".0", with: "") }
        return "\(n)"
    }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 7, weight: .black))
            Text(formatNumber(estimatedPlays))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
        .help("Popularity Score: \(popularity)/100")
    }
}

import Foundation

public enum DataSizeBase: String {
    case bit
    case byte
}

public struct Units {
    public let bytes: Int64

    public var kilobytes: Double {
        return Double(bytes) / 1024
    }

    public var megabytes: Double {
        return kilobytes / 1024
    }

    public var gigabytes: Double {
        return megabytes / 1024
    }

    public init(bytes: Int64) {
        self.bytes = bytes
    }

    public func getReadableSpeed(base: DataSizeBase = .byte) -> String {
        let b = base == .bit ? bytes * 8 : bytes

        if b < 1024 {
            return "\(b) B/s"
        } else if b < 1024 * 1024 {
            return String(format: "%.1f KB/s", Double(b) / 1024.0)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", Double(b) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.1f GB/s", Double(b) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}

extension Float {
    init?(data: Data) {
        guard data.count == MemoryLayout<Float>.size else { return nil }
        self = data.withUnsafeBytes { $0.load(as: Float.self) }
    }
}

typealias FourCharCode = String