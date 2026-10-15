//
//  LayerProgressViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import SwiftUI
import AppKit
import QuartzCore

struct LinearProgressMotion: Equatable {
    var progress: Double
    var date: Date
    var rate: Double

    init(progress: Double, date: Date = Date(), rate: Double = 0) {
        self.progress = progress.isFinite ? progress : 0
        self.date = date
        self.rate = rate.isFinite ? rate : 0
    }

    static let zero = LinearProgressMotion(progress: 0)

    func value(at date: Date) -> Double {
        let raw = progress + rate * date.timeIntervalSince(self.date)
        return min(max(raw, 0), 1)
    }

    func isEquivalent(to other: LinearProgressMotion, tolerance: Double = 0.0015) -> Bool {
        guard abs(rate - other.rate) < 1e-9 else { return false }
        let now = Date()
        return abs(value(at: now) - other.value(at: now)) < tolerance
    }
}

extension CABasicAnimation {
    func limitFrameRateForSlowAdvance() {
        guard duration > 20 else { return }
        preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 15)
    }
}

private enum LinearProgressAnimator {
    static let key = "linearProgress"
    static let catchUpKey = "linearProgressCatchUp"

    static func apply(
        to layer: CALayer,
        keyPath: String,
        motion: LinearProgressMotion,
        presented: Double?,
        catchUp: CFTimeInterval,
        modelValue: (Double) -> Any
    ) {
        let wallNow = Date()
        let mediaNow = layer.convertTime(CACurrentMediaTime(), from: nil)
        let current = motion.value(at: wallNow)

        layer.removeAnimation(forKey: key)
        layer.removeAnimation(forKey: catchUpKey)
        layer.setValue(modelValue(current), forKeyPath: keyPath)

        var steadyStart = mediaNow
        var steadyFrom = current
        if catchUp > 0, let presented, abs(presented - current) > 0.002 {
            let target = motion.value(at: wallNow.addingTimeInterval(catchUp))
            let jump = CABasicAnimation(keyPath: keyPath)
            jump.fromValue = modelValue(presented)
            jump.toValue = modelValue(target)
            jump.duration = catchUp
            jump.timingFunction = CAMediaTimingFunction(name: .linear)
            jump.fillMode = .forwards
            jump.isRemovedOnCompletion = false
            layer.add(jump, forKey: catchUpKey)
            steadyStart = mediaNow + catchUp
            steadyFrom = target
        }

        guard motion.rate != 0 else { return }
        let end: Double = motion.rate > 0 ? 1 : 0
        let duration = (end - steadyFrom) / motion.rate
        guard duration > 0.01, duration.isFinite else { return }
        let steady = CABasicAnimation(keyPath: keyPath)
        steady.fromValue = modelValue(steadyFrom)
        steady.toValue = modelValue(end)
        steady.beginTime = steadyStart
        steady.duration = duration
        steady.timingFunction = CAMediaTimingFunction(name: .linear)
        steady.fillMode = .forwards
        steady.isRemovedOnCompletion = false
        steady.limitFrameRateForSlowAdvance()
        layer.add(steady, forKey: key)
    }
}

// MARK: - Bar

struct LayerProgressBar: NSViewRepresentable {
    var motion: LinearProgressMotion
    var colors: [Color]
    var trackColor: Color
    var barHeight: CGFloat = 10
    var catchUpDuration: CFTimeInterval = 0.5

    func makeNSView(context: Context) -> LayerProgressBarView {
        let view = LayerProgressBarView()
        view.configure(colors: colors, trackColor: trackColor, barHeight: barHeight)
        view.apply(motion, catchUp: 0)
        return view
    }

    func updateNSView(_ nsView: LayerProgressBarView, context: Context) {
        nsView.configure(colors: colors, trackColor: trackColor, barHeight: barHeight)
        nsView.apply(motion, catchUp: catchUpDuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerProgressBarView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: proposal.height ?? barHeight)
    }
}

final class LayerProgressBarView: NSView {
    private let clipLayer = CALayer()
    private let trackLayer = CALayer()
    private let fillLayer = CAGradientLayer()
    private var motion: LinearProgressMotion?
    private var colors: [Color] = []
    private var trackColor: Color = .clear
    private var barHeight: CGFloat = 10

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        clipLayer.masksToBounds = true
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.endPoint = CGPoint(x: 1, y: 0.5)
        for sub in [clipLayer, trackLayer, fillLayer] as [CALayer] {
            sub.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull(), "colors": NSNull(), "cornerRadius": NSNull()]
        }
        clipLayer.addSublayer(trackLayer)
        clipLayer.addSublayer(fillLayer)
        layer?.addSublayer(clipLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(colors: [Color], trackColor: Color, barHeight: CGFloat) {
        guard colors != self.colors || trackColor != self.trackColor || barHeight != self.barHeight else { return }
        self.colors = colors
        self.trackColor = trackColor
        self.barHeight = barHeight
        resolveColors()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let motion { self.motion = nil; apply(motion, catchUp: 0) }
    }

    private func resolveColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            trackLayer.backgroundColor = NSColor(trackColor).cgColor
            let fills = colors.isEmpty ? [Color.white] : colors
            fillLayer.colors = (fills.count == 1 ? [fills[0], fills[0]] : fills).map { NSColor($0).cgColor }
        }
        CATransaction.commit()
    }

    private var fillWidth: CGFloat { clipLayer.bounds.width }

    override func layout() {
        super.layout()
        let height = min(barHeight, bounds.height)
        let rect = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        guard clipLayer.frame != rect else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clipLayer.frame = rect
        clipLayer.cornerRadius = height / 2
        trackLayer.frame = clipLayer.bounds
        fillLayer.position = CGPoint(x: 0, y: rect.height / 2)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: fillLayer.bounds.width, height: rect.height)
        CATransaction.commit()
        if let motion {
            self.motion = nil
            apply(motion, catchUp: 0)
        }
    }

    private func presentedProgress() -> Double? {
        guard motion != nil, fillWidth > 0 else { return nil }
        let width = (fillLayer.presentation() ?? fillLayer).bounds.width
        return Double(width / fillWidth)
    }

    func apply(_ motion: LinearProgressMotion, catchUp: CFTimeInterval) {
        if let current = self.motion, current.isEquivalent(to: motion) { return }
        let presented = presentedProgress()
        self.motion = motion
        let width = fillWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        LinearProgressAnimator.apply(
            to: fillLayer,
            keyPath: "bounds.size.width",
            motion: motion,
            presented: presented,
            catchUp: window == nil ? 0 : catchUp,
            modelValue: { CGFloat($0) * width }
        )
        CATransaction.commit()
    }
}

// MARK: - Ring

struct LayerProgressRing: NSViewRepresentable {
    var motion: LinearProgressMotion
    var lineWidth: CGFloat
    var trackLineWidth: CGFloat? = nil
    var trackColor: Color = Color.white.opacity(0.18)
    var activeColor: Color
    var lineCap: CAShapeLayerLineCap = .round
    var catchUpDuration: CFTimeInterval = 0.25

    func makeNSView(context: Context) -> LayerProgressRingView {
        let view = LayerProgressRingView()
        view.configure(self)
        view.apply(motion, catchUp: 0)
        return view
    }

    func updateNSView(_ nsView: LayerProgressRingView, context: Context) {
        nsView.configure(self)
        nsView.apply(motion, catchUp: catchUpDuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LayerProgressRingView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 16, height: proposal.height ?? 16)
    }
}

final class LayerProgressRingView: NSView {
    private let trackLayer = CAShapeLayer()
    private let activeLayer = CAShapeLayer()
    private var motion: LinearProgressMotion?
    private var style: (lineWidth: CGFloat, trackLineWidth: CGFloat, track: Color, active: Color, cap: CAShapeLayerLineCap)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        for shape in [trackLayer, activeLayer] {
            shape.fillColor = nil
            shape.actions = ["path": NSNull(), "strokeEnd": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(), "frame": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(shape)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ ring: LayerProgressRing) {
        let next = (ring.lineWidth, ring.trackLineWidth ?? ring.lineWidth, ring.trackColor, ring.activeColor, ring.lineCap)
        if let style, style.0 == next.0, style.1 == next.1, style.2 == next.2, style.3 == next.3, style.4 == next.4 { return }
        style = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.lineWidth = next.1
        activeLayer.lineWidth = next.0
        activeLayer.lineCap = next.4
        CATransaction.commit()
        resolveColors()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let motion { self.motion = nil; apply(motion, catchUp: 0) }
    }

    private func resolveColors() {
        guard let style else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            trackLayer.strokeColor = NSColor(style.track).cgColor
            activeLayer.strokeColor = NSColor(style.active).cgColor
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = side / 2
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        for shape in [trackLayer, activeLayer] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
    }

    func apply(_ motion: LinearProgressMotion, catchUp: CFTimeInterval) {
        if let current = self.motion, current.isEquivalent(to: motion) { return }
        let presented: Double? = self.motion == nil ? nil : Double((activeLayer.presentation() ?? activeLayer).strokeEnd)
        self.motion = motion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        LinearProgressAnimator.apply(
            to: activeLayer,
            keyPath: "strokeEnd",
            motion: motion,
            presented: presented,
            catchUp: window == nil ? 0 : catchUp,
            modelValue: { CGFloat($0) }
        )
        CATransaction.commit()
    }
}