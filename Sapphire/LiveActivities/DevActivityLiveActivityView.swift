//
//  DevActivityLiveActivityView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12
//

import SwiftUI

struct DevActivityLiveActivityView {

    static func left(for task: DevTask) -> some View {
        DevActivityGlyph(task: task)
    }

    static func right(for task: DevTask, additionalCount: Int) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text(subtitle(for: task, additionalCount: additionalCount))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            DevActivityElapsedLabel(startedAt: task.startedAt, tint: task.tool.tint)
        }
        .foregroundColor(.white.opacity(0.92))
    }

    private static func subtitle(for task: DevTask, additionalCount: Int) -> String {
        if additionalCount > 0 {
            let others = additionalCount == 1 ? "1 more task" : "\(additionalCount) more tasks"
            return task.detail.isEmpty ? others : "\(task.detail) · \(others)"
        }
        return task.detail.isEmpty ? task.kind.displayName : task.detail
    }
}

private struct DevActivityGlyph: View {
    let task: DevTask

    var body: some View {
        ZStack {
            DevActivityPulseCircle(color: NSColor(task.tool.tint.opacity(0.22)))
                .frame(width: 22, height: 22)

            Image(systemName: task.tool.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(task.tool.tint)
        }
        .frame(width: 24, height: 24)
        .id(task.id)
    }
}

private struct DevActivityPulseCircle: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> DevActivityPulseView {
        let view = DevActivityPulseView()
        view.color = color
        return view
    }

    func updateNSView(_ nsView: DevActivityPulseView, context: Context) {
        nsView.color = color
    }
}

private final class DevActivityPulseView: NSView {
    private static let animationKey = "breathing"
    private let circle = CALayer()

    var color: NSColor = .clear {
        didSet {
            guard color != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            circle.backgroundColor = color.cgColor
            CATransaction.commit()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(circle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circle.bounds = CGRect(origin: .zero, size: bounds.size)
        circle.position = CGPoint(x: bounds.midX, y: bounds.midY)
        circle.cornerRadius = min(bounds.width, bounds.height) / 2
        circle.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            circle.removeAnimation(forKey: Self.animationKey)
        } else {
            startPulse()
        }
    }

    private func startPulse() {
        guard circle.animation(forKey: Self.animationKey) == nil else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.12

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.9
        opacity.toValue = 0.45

        let pulse = CAAnimationGroup()
        pulse.animations = [scale, opacity]
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        circle.add(pulse, forKey: Self.animationKey)
    }
}

private struct DevActivityElapsedLabel: View {
    let startedAt: Date
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(DevTaskFormatting.elapsed(context.date.timeIntervalSince(startedAt)))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint.opacity(0.95))
                .contentTransition(.numericText())
        }
        .frame(minWidth: 34, alignment: .trailing)
    }
}