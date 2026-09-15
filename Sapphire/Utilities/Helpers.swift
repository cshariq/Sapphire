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

@MainActor
enum FloatingPanelPositioning {
    static func preferredAnchor() -> NSPoint {
        if let caretPoint = CaretPositionTracker.anchorPoint() {
            return caretPoint
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.midX, y: visible.midY)
    }

    static func topLeftOrigin(for size: NSSize, below anchor: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return topLeftOrigin(for: size, below: anchor, in: visible)
    }

    static func topLeftOrigin(for size: NSSize, below anchor: NSPoint, in visible: NSRect) -> NSPoint {
        var origin = NSPoint(x: anchor.x, y: anchor.y - 6)

        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        if origin.y - size.height < visible.minY + 8 {
            origin.y = min(anchor.y + size.height + 6, visible.maxY - 6)
        }
        origin.y = max(visible.minY + size.height + 8, min(origin.y, visible.maxY - 8))
        return origin
    }

    static func preferredPickerTopLeftOrigin(for size: NSSize) -> NSPoint {
        if let caret = CaretPositionTracker.caretInfo(), caret.isExact {
            return topLeftOrigin(for: size, below: caret.anchorPoint)
        }

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return centeredTopLeftOrigin(for: size, in: visible)
    }

    static func centeredTopLeftOrigin(for size: NSSize, in visible: NSRect) -> NSPoint {
        let horizontalInset: CGFloat = 8
        let verticalInset: CGFloat = 8
        let centered = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY + size.height / 2
        )
        return NSPoint(
            x: max(visible.minX + horizontalInset, min(centered.x, visible.maxX - size.width - horizontalInset)),
            y: max(visible.minY + size.height + verticalInset, min(centered.y, visible.maxY - verticalInset))
        )
    }
}

public class Debouncer {
    private struct PendingAction {
        let generation: UInt64
        let item: DispatchWorkItem
        let action: () -> Void
    }

    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var pending: PendingAction?

    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    public func debounce(action: @escaping (() -> Void)) {
        lock.lock()
        pending?.item.cancel()
        generation &+= 1
        let scheduledGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            self?.execute(generation: scheduledGeneration)
        }
        pending = PendingAction(
            generation: scheduledGeneration,
            item: item,
            action: action
        )
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func cancel() {
        lock.lock()
        pending?.item.cancel()
        pending = nil
        lock.unlock()
    }

    func flush() {
        lock.lock()
        guard let pending else {
            lock.unlock()
            return
        }
        self.pending = nil
        pending.item.cancel()
        lock.unlock()

        pending.action()
    }

    private func execute(generation: UInt64) {
        lock.lock()
        guard let pending, pending.generation == generation else {
            lock.unlock()
            return
        }
        self.pending = nil
        let action = pending.action
        lock.unlock()

        action()
    }

    deinit {
        cancel()
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
    @State private var isDragging = false
    @State private var dragValue: Double = 0.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 10)
                Rectangle().fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)).frame(width: geometry.size.width * CGFloat(isDragging ? dragValue : value), height: 10)
            }
            .clipShape(Capsule())
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gestureValue in
                if !isDragging { isDragging = true; dragValue = value }
                let newProgress = min(max(0, gestureValue.location.x / geometry.size.width), 1)
                self.dragValue = newProgress
                onDragChanged?(newProgress)
            }.onEnded { gestureValue in
                let finalProgress = min(max(0, gestureValue.location.x / geometry.size.width), 1)
                onSeek(finalProgress)
                value = finalProgress
                isDragging = false
            })
            .animation(isDragging ? .none : .linear(duration: 0.5), value: value)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var isEmphasized = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
        if nsView.isEmphasized != isEmphasized { nsView.isEmphasized = isEmphasized }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSVisualEffectView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 10, height: proposal.height ?? 10)
    }
}

extension Int {
    var compactFormatted: String {
        let value = Double(self)
        for (threshold, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] where value >= threshold {
            return String(format: "%.1f", value / threshold).replacingOccurrences(of: ".0", with: "") + suffix
        }
        return "\(self)"
    }
}

private struct MusicStatPill: View {
    let systemImage: String
    let text: String
    let color: Color
    let help: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 7, weight: .black))
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
        .help(help)
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
    var body: some View {
        MusicStatPill(
            systemImage: "play.fill",
            text: playCount.compactFormatted,
            color: color,
            help: "Total Plays: \(playCount.formatted())"
        )
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
    var body: some View {
        MusicStatPill(
            systemImage: "chart.line.uptrend.xyaxis",
            text: estimatedPlays.compactFormatted,
            color: color,
            help: "Popularity Score: \(popularity)/100"
        )
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

@MainActor
enum TransferMetricsFormatter {
    private static let secondsFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static let minuteSecondFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    nonisolated static func speed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    static func eta(currentBytes: Int64, totalBytes: Int64?, bytesPerSecond: Double) -> String? {
        guard bytesPerSecond > 0,
              let totalBytes,
              totalBytes > currentBytes else { return nil }
        let seconds = Double(totalBytes - currentBytes) / bytesPerSecond
        guard seconds.isFinite, seconds > 0 else { return nil }
        let formatter = seconds >= 60 ? minuteSecondFormatter : secondsFormatter
        return formatter.string(from: seconds)
    }
}

enum ByteFormatter {
    nonisolated static func string(_ bytes: Int64, style: ByteCountFormatter.CountStyle = .file) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: style)
    }
}

extension Float {
    init?(data: Data) {
        guard data.count == MemoryLayout<Float>.size else { return nil }
        self = data.withUnsafeBytes { $0.load(as: Float.self) }
    }
}

typealias FourCharCode = String