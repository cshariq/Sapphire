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

    @GestureState private var isPressing = false
    @State private var longPressTimer: Timer?
    @State private var seekTimer: Timer?
    @State private var tapIsEligible = false

    private var isForward: Bool {
        systemName.contains("forward")
    }

    var body: some View {
        Image(systemName: systemName)
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
                    longPressTimer?.invalidate()
                    longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        tapIsEligible = false
                        startSeeking()
                    }
                } else {
                    longPressTimer?.invalidate()
                    seekTimer?.invalidate()
                    seekTimer = nil
                    if tapIsEligible {
                        onTap()
                    }
                }
            }
            .blur(radius: isPressing ? 4 : 0)
            .scaleEffect(isPressing ? 0.9 : 1.0)
            .opacity(isPressing ? 0.8 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isPressing)
    }

    private func startSeeking() {
        seekTimer?.invalidate()
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            onSeek(isForward)
        }
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
            }.onEnded { gestureValue in
                let finalProgress = min(max(0, gestureValue.location.x / geometry.size.width), 1)
                onSeek(finalProgress)
                isDragging = false
            })
            .animation(isDragging ? .none : .linear(duration: 0.5), value: value)
        }
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
    private var metrics: (color: Color, bars: [CGFloat]) {
        if playCount > 500_000_000 { return (.green, [5, 7, 9, 11]) }
        if playCount > 100_000_000 { return (.yellow, [5, 7, 9, 7]) }
        if playCount > 10_000_000 { return (.secondary, [5, 7, 7, 5]) }
        return (.secondary.opacity(0.3), [5, 5, 5, 5])
    }
    private func formatNumber(_ n: Int) -> String {
        let num = Double(n)
        if num >= 1_000_000_000 { return String(format: "%.1fB", num / 1_000_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000 { return String(format: "%.1fK", num / 1_000).replacingOccurrences(of: ".0", with: "") }
        return "\(n)"
    }
    var body: some View {
        let TMetrics = metrics
        HStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) { ForEach(0..<4) { index in Capsule().fill(TMetrics.bars.indices.contains(index) ? TMetrics.color : Color.clear).frame(width: 3, height: TMetrics.bars.indices.contains(index) ? TMetrics.bars[index] : 5) } }
            Text(formatNumber(playCount)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(TMetrics.color.opacity(0.8))
        }.help("Total Plays: \(playCount.formatted())")
    }
}

struct PopularityIndicator: View {
    let popularity: Int
    private var color: Color { if popularity >= 75 { return .green }; if popularity >= 40 { return .yellow }; return .secondary }
    private var estimatedPlays: Int { let p = Double(popularity); let basePlays = pow(p / 10, 4) * 100; let randomFactor = Double.random(in: 0.8...1.2); return Int(basePlays * randomFactor) }
    private func formatNumber(_ n: Int) -> String { let num = Double(n); if num >= 1_000_000_000 { return String(format: "%.1fB", num / 1_000_000_000).replacingOccurrences(of: ".0", with: "") }; if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000).replacingOccurrences(of: ".0", with: "") }; if num >= 1_000 { return String(format: "%.1fK", num / 1_000).replacingOccurrences(of: ".0", with: "") }; return "\(n)" }
    var body: some View {
        HStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) { ForEach(0..<4) { index in Capsule().fill(popularity > (index * 25) ? color : Color.secondary.opacity(0.3)).frame(width: 3, height: CGFloat(index * 2 + 5)) } }
            Text(formatNumber(estimatedPlays)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(color.opacity(0.8))
        }.help("Popularity Score: \(popularity)/100")
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