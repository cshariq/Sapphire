//
//  LayerGradientProgressRing.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import SwiftUI
import AppKit
import QuartzCore

extension LinearProgressMotion {
    @MainActor
    static func focusBlock(_ manager: FocusSessionManager, minimum: Double = 0) -> LinearProgressMotion {
        let now = Date()
        let rate = manager.isRunning && manager.totalSeconds > 0 ? 1 / manager.totalSeconds : 0
        return LinearProgressMotion(progress: max(minimum, manager.progress(at: now)), date: now, rate: rate)
    }
}

extension NSColor {
    static func notchResolved(_ color: Color) -> NSColor {
        var resolved = NSColor(color)
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB) ?? resolved
        }
        return resolved
    }
}

struct LayerGradientProgressRing: NSViewRepresentable {
    var motion: LinearProgressMotion
    var lineWidth: CGFloat
    var trackLineWidth: CGFloat? = nil
    var trackColor: Color = Color.white.opacity(0.18)
    var colors: [Color]
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    var shadowIncludesTrack = false
    var catchUpDuration: CFTimeInterval = 0.25

    func makeNSView(context: Context) -> LayerGradientProgressRingView {
        let view = LayerGradientProgressRingView()
        view.configure(self)
        view.apply(motion, catchUp: 0)
        return view
    }

    func updateNSView(_ nsView: LayerGradientProgressRingView, context: Context) {
        nsView.configure(self)
        nsView.apply(motion, catchUp: catchUpDuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerGradientProgressRingView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 16, height: proposal.height ?? 16)
    }
}

final class LayerGradientProgressRingView: NSView {
    private struct Style: Equatable {
        var lineWidth: CGFloat
        var trackLineWidth: CGFloat
        var trackColor: Color
        var colors: [Color]
        var shadowColor: Color
        var shadowRadius: CGFloat
        var shadowIncludesTrack: Bool
    }

    private static let animationKey = "linearProgress"
    private static let catchUpKey = "linearProgressCatchUp"

    private let ringLayer = CALayer()
    private let trackLayer = CAShapeLayer()
    private let activeLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let arcMask = CAShapeLayer()
    private var motion: LinearProgressMotion?
    private var style: Style?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        let noActions: [String: CAAction] = [
            "path": NSNull(), "strokeEnd": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(),
            "frame": NSNull(), "bounds": NSNull(), "position": NSNull(), "colors": NSNull(),
            "shadowColor": NSNull(), "shadowRadius": NSNull(), "shadowOpacity": NSNull()
        ]
        for sub in [ringLayer, trackLayer, activeLayer, gradientLayer, arcMask] as [CALayer] {
            sub.actions = noActions
        }
        trackLayer.fillColor = nil
        arcMask.fillColor = nil
        arcMask.strokeColor = NSColor.black.cgColor
        arcMask.lineCap = .round
        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.mask = arcMask
        activeLayer.addSublayer(gradientLayer)
        ringLayer.addSublayer(trackLayer)
        ringLayer.addSublayer(activeLayer)
        layer?.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ ring: LayerGradientProgressRing) {
        let next = Style(
            lineWidth: ring.lineWidth,
            trackLineWidth: ring.trackLineWidth ?? ring.lineWidth,
            trackColor: ring.trackColor,
            colors: ring.colors.isEmpty ? [.white] : ring.colors,
            shadowColor: ring.shadowColor,
            shadowRadius: ring.shadowRadius,
            shadowIncludesTrack: ring.shadowIncludesTrack
        )
        guard next != style else { return }
        style = next
        resolveStyle()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveStyle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let motion { self.motion = nil; apply(motion, catchUp: 0) }
    }

    private func resolveStyle() {
        guard let style else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.lineWidth = style.trackLineWidth
        arcMask.lineWidth = style.lineWidth
        effectiveAppearance.performAsCurrentDrawingAppearance {
            trackLayer.strokeColor = NSColor(style.trackColor).cgColor
            let colors = style.colors.count == 1 ? [style.colors[0], style.colors[0]] : style.colors
            gradientLayer.colors = colors.map { NSColor($0).cgColor }
            let shadowed = style.shadowIncludesTrack ? ringLayer : activeLayer
            let plain = style.shadowIncludesTrack ? activeLayer : ringLayer
            plain.shadowOpacity = 0
            if style.shadowRadius > 0 {
                shadowed.shadowColor = NSColor(style.shadowColor).cgColor
                shadowed.shadowOpacity = 1
                shadowed.shadowRadius = style.shadowRadius
                shadowed.shadowOffset = .zero
            } else {
                shadowed.shadowOpacity = 0
            }
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        guard let style else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let radius = side / 2
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        ringLayer.frame = bounds
        trackLayer.frame = bounds
        trackLayer.path = path
        activeLayer.frame = bounds
        let pad = style.lineWidth
        gradientLayer.frame = bounds.insetBy(dx: -pad, dy: -pad)
        arcMask.frame = gradientLayer.bounds
        let maskPath = CGMutablePath()
        maskPath.addArc(center: CGPoint(x: gradientLayer.bounds.midX, y: gradientLayer.bounds.midY), radius: radius,
                        startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        arcMask.path = maskPath
        CATransaction.commit()
    }

    func apply(_ motion: LinearProgressMotion, catchUp: CFTimeInterval) {
        if let current = self.motion, current.isEquivalent(to: motion) { return }
        let presented: Double? = self.motion == nil ? nil : Double((arcMask.presentation() ?? arcMask).strokeEnd)
        self.motion = motion
        let catchUp = window == nil ? 0 : catchUp

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let wallNow = Date()
        let mediaNow = arcMask.convertTime(CACurrentMediaTime(), from: nil)
        let current = motion.value(at: wallNow)
        arcMask.removeAnimation(forKey: Self.animationKey)
        arcMask.removeAnimation(forKey: Self.catchUpKey)
        arcMask.strokeEnd = CGFloat(current)

        var steadyStart = mediaNow
        var steadyFrom = current
        if catchUp > 0, let presented, abs(presented - current) > 0.002 {
            let target = motion.value(at: wallNow.addingTimeInterval(catchUp))
            let jump = CABasicAnimation(keyPath: "strokeEnd")
            jump.fromValue = CGFloat(presented)
            jump.toValue = CGFloat(target)
            jump.duration = catchUp
            jump.timingFunction = CAMediaTimingFunction(name: .linear)
            jump.fillMode = .forwards
            jump.isRemovedOnCompletion = false
            arcMask.add(jump, forKey: Self.catchUpKey)
            steadyStart = mediaNow + catchUp
            steadyFrom = target
        }

        if motion.rate != 0 {
            let end: Double = motion.rate > 0 ? 1 : 0
            let duration = (end - steadyFrom) / motion.rate
            if duration > 0.01, duration.isFinite {
                let steady = CABasicAnimation(keyPath: "strokeEnd")
                steady.fromValue = CGFloat(steadyFrom)
                steady.toValue = CGFloat(end)
                steady.beginTime = steadyStart
                steady.duration = duration
                steady.timingFunction = CAMediaTimingFunction(name: .linear)
                steady.fillMode = .forwards
                steady.isRemovedOnCompletion = false
                steady.limitFrameRateForSlowAdvance()
                arcMask.add(steady, forKey: Self.animationKey)
            }
        }
        CATransaction.commit()
    }
}