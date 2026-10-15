//
//  NotchLayerSurface.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08
//

import AppKit
import SwiftUI

enum NotchLayerFill: Equatable {
    case solid(NSColor)
    case linearGradient(colors: [NSColor], locations: [CGFloat], start: UnitPoint, end: UnitPoint)
    case radialGradient(colors: [NSColor], locations: [CGFloat], endRadius: CGFloat)

    var isGradient: Bool {
        switch self {
        case .solid: return false
        case .linearGradient, .radialGradient: return true
        }
    }
}

enum NotchLayerScalarAnimation {
    static func make(keyPath: String, from: Any?, to: Any, animation: Animation?) -> CAAnimation? {
        guard let animation, let from else { return nil }
        return make(keyPath: keyPath, from: from, to: to, curve: animation.notchMorphCurve ?? .fallback)
    }

    static func make(keyPath: String, from: Any, to: Any, curve: NotchMorphCurve) -> CAAnimation {
        let made: CABasicAnimation
        switch curve {
        case .spring(let response, let dampingFraction):
            let spring = CASpringAnimation(keyPath: keyPath)
            let omega = 2 * Double.pi / max(response, 0.0001)
            spring.mass = 1
            spring.stiffness = omega * omega
            spring.damping = 2 * dampingFraction * omega
            spring.duration = spring.settlingDuration
            made = spring
        case .timing(let timing, let duration):
            made = CABasicAnimation(keyPath: keyPath)
            made.duration = max(0, duration)
            made.timingFunction = timingFunction(timing)
        }
        made.fromValue = from
        made.toValue = to
        return made
    }

    static func timingFunction(_ timing: NotchMorphTiming) -> CAMediaTimingFunction {
        switch timing {
        case .linear: return CAMediaTimingFunction(controlPoints: 0, 0, 1, 1)
        case .easeIn: return CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1)
        case .easeOut: return CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)
        case .easeInOut: return CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
        case .bezier(let x1, let y1, let x2, let y2):
            return CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
        }
    }

    @discardableResult
    static func set(_ layer: CALayer, _ keyPath: String, to value: Any, equals: (Any?) -> Bool, animation: Animation?) -> CFTimeInterval {
        guard !equals(layer.value(forKeyPath: keyPath)) else { return 0 }
        let from = (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        layer.setValue(value, forKeyPath: keyPath)
        if let made = make(keyPath: keyPath, from: from, to: value, animation: animation) {
            layer.add(made, forKey: keyPath)
            return made.duration
        }
        layer.removeAnimation(forKey: keyPath)
        return 0
    }
}

// MARK: - Layer surface

final class NotchLayerSurfaceView: NSView {
    struct Shadow: Equatable {
        var color: NSColor
        var opacity: Double
        var radius: CGFloat
        var offset: CGSize

        static let none = Shadow(color: .clear, opacity: 0, radius: 0, offset: .zero)
    }

    private let shapeLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let gradientMask = CAShapeLayer()
    private let rimLayer = CAShapeLayer()
    private let rimGradient = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private var glowLayers: [CAShapeLayer] = []
    private var rim: NSColor?

    private var shape: CustomNotchShape?
    private var fill: NotchLayerFill?
    private var surfaceShadow: Shadow = .none
    private var glows: [Shadow] = []
    private var appliedGradientKey: GradientKey?
    private weak var engine: NotchMorphEngine?
    private var appliedOutlineKey: OutlineKey?

    private struct GradientKey: Equatable {
        let fill: NotchLayerFill
        let topDown: Bool
    }

    private struct OutlineKey: Equatable {
        let frame: NotchMorphFrame
        let shape: CustomNotchShape
        let bounds: CGRect
        let topDown: Bool
        let gradient: Bool
        let glowCount: Int
        let rim: Bool
        let windowOrigin: CGPoint?
    }

    static let noActions: [String: CAAction] = [
        "path": NSNull(), "shadowPath": NSNull(), "fillColor": NSNull(),
        "shadowOpacity": NSNull(), "shadowRadius": NSNull(), "shadowOffset": NSNull(),
        "shadowColor": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
        "colors": NSNull(), "locations": NSNull(), "startPoint": NSNull(), "endPoint": NSNull(),
        "hidden": NSNull(), "mask": NSNull(), "opacity": NSNull(), "transform": NSNull(),
        "sublayerTransform": NSNull(), "cornerRadius": NSNull(), "type": NSNull(),
    ]

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        clipsToBounds = false
        shapeLayer.actions = Self.noActions
        gradientLayer.actions = Self.noActions
        gradientMask.actions = Self.noActions
        shapeLayer.masksToBounds = false
        gradientMask.fillColor = NSColor.black.cgColor
        gradientLayer.mask = gradientMask
        gradientLayer.isHidden = true
        rimLayer.actions = Self.noActions
        rimLayer.fillColor = nil
        rimLayer.lineWidth = 1
        rimLayer.isHidden = true
        rimGradient.actions = Self.noActions
        rimMask.actions = Self.noActions
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 2
        rimGradient.mask = rimMask
        rimGradient.isHidden = true
        gradientLayer.addSublayer(rimGradient)
        layer?.addSublayer(shapeLayer)
        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(rimLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(
        shape: CustomNotchShape,
        engine: NotchMorphEngine,
        fill: NotchLayerFill,
        shadow: Shadow,
        glows: [Shadow] = [],
        rim: NSColor? = nil,
        shadowAnimation: Animation? = nil
    ) {
        if self.engine !== engine {
            self.engine?.removeRenderer(self)
            self.engine = engine
            engine.addRenderer(
                self,
                render: { [weak self] frame in self?.renderOutline(frame) },
                animate: { [weak self] timeline in self?.animateOutline(timeline) }
            )
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.shape != shape {
            self.shape = shape
            appliedOutlineKey = nil
        }
        if fill != self.fill {
            self.fill = fill
            applyFillStyle()
        }
        if shadow != surfaceShadow {
            surfaceShadow = shadow
            applyShadowStyle(animation: shadowAnimation)
        }
        if glows != self.glows {
            self.glows = glows
            applyGlowStyle()
        }
        if rim != self.rim {
            self.rim = rim
            applyRimStyle()
        }
        applyGradientStyleIfNeeded()
        CATransaction.commit()
        renderOutline(engine.currentFrame)
    }

    func setShadowOpacity(_ opacity: Double, animation: Animation?) {
        guard surfaceShadow.opacity != opacity else { return }
        surfaceShadow.opacity = opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyShadowStyle(animation: animation)
        CATransaction.commit()
    }

    func detach() {
        engine?.removeRenderer(self)
        engine = nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyGradientStyleIfNeeded()
        applyShadowStyle()
        applyGlowStyle()
        CATransaction.commit()
        if let engine { renderOutline(engine.currentFrame) }
        if bounds.size != lastLaidOutSize {
            let resized = lastLaidOutSize != nil
            lastLaidOutSize = bounds.size
            if resized, let timeline = engine?.activeTimeline, timeline.end > CACurrentMediaTime() {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                animateOutline(timeline)
                CATransaction.commit()
            }
        }
    }

    private var lastLaidOutSize: CGSize?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let engine, window != nil { renderOutline(engine.currentFrame) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        appliedOutlineKey = nil
        if let engine { renderOutline(engine.currentFrame) }
    }

    private var isTopDown: Bool { shapeLayer.contentsAreFlipped() }

    private var showsGradient: Bool { fill?.isGradient ?? false }

    private var showsLitRim: Bool { rim != nil && showsGradient }

    private func applyRimStyle() {
        let lit = showsLitRim
        rimLayer.strokeColor = rim?.cgColor
        rimLayer.isHidden = rim == nil || lit
        if rim == nil || lit { rimLayer.path = nil }
        rimGradient.isHidden = !lit
        if lit, let rim {
            let base = rim.alphaComponent
            let stops: [(CGFloat, CGFloat)] = [(0, 2.4), (0.3, 0.5), (0.72, 0.5), (1, 1.6)]
            rimGradient.colors = stops.map { rim.withAlphaComponent(min(1, base * $0.1)).cgColor }
            rimGradient.locations = stops.map { NSNumber(value: Double($0.0)) }
        } else {
            rimMask.path = nil
        }
        appliedOutlineKey = nil
    }

    private func applyFillStyle() {
        defer { applyRimStyle() }
        switch fill {
        case .solid(let color):
            shapeLayer.fillColor = color.cgColor
            gradientLayer.isHidden = true
        case .linearGradient, .radialGradient:
            shapeLayer.fillColor = NSColor.clear.cgColor
            gradientLayer.isHidden = false
            appliedGradientKey = nil
        case nil:
            break
        }
        appliedOutlineKey = nil
    }

    private func applyShadowStyle(animation: Animation? = nil) {
        let shadow = surfaceShadow
        shapeLayer.shadowColor = shadow.color.cgColor
        let opacity = Float(max(0, min(1, shadow.opacity)))
        NotchLayerScalarAnimation.set(shapeLayer, "shadowOpacity", to: opacity, equals: { ($0 as? Float) == opacity }, animation: animation)
        NotchLayerScalarAnimation.set(shapeLayer, "shadowRadius", to: shadow.radius, equals: { ($0 as? CGFloat) == shadow.radius }, animation: animation)
        let offset = CGSize(width: shadow.offset.width, height: isTopDown ? shadow.offset.height : -shadow.offset.height)
        NotchLayerScalarAnimation.set(shapeLayer, "shadowOffset", to: offset, equals: { ($0 as? CGSize) == offset }, animation: animation)
    }

    private func applyGlowStyle() {
        while glowLayers.count > glows.count {
            glowLayers.removeLast().removeFromSuperlayer()
            appliedOutlineKey = nil
        }
        while glowLayers.count < glows.count {
            let glow = CAShapeLayer()
            glow.actions = Self.noActions
            glow.masksToBounds = false
            glow.fillColor = NSColor.clear.cgColor
            layer?.insertSublayer(glow, below: shapeLayer)
            glowLayers.append(glow)
            appliedOutlineKey = nil
        }
        for (glow, style) in zip(glowLayers, glows) {
            glow.frame = bounds
            glow.shadowColor = style.color.cgColor
            glow.shadowOpacity = Float(max(0, min(1, style.opacity)))
            glow.shadowRadius = style.radius
            glow.shadowOffset = CGSize(width: style.offset.width, height: isTopDown ? style.offset.height : -style.offset.height)
        }
    }

    private func applyGradientStyleIfNeeded() {
        if shapeLayer.frame != bounds { shapeLayer.frame = bounds }
        if rimLayer.frame != bounds { rimLayer.frame = bounds }
        guard let fill, fill.isGradient else { return }
        let topDown = isTopDown
        let key = GradientKey(fill: fill, topDown: topDown)
        guard key != appliedGradientKey else { return }
        appliedGradientKey = key
        applyRimStyle()
        switch fill {
        case .linearGradient(let colors, let locations, _, _):
            gradientLayer.type = .axial
            gradientLayer.colors = colors.map(\.cgColor)
            gradientLayer.locations = locations.map { NSNumber(value: Double($0)) }
            appliedOutlineKey = nil
        case .radialGradient(let colors, let locations, _):
            gradientLayer.type = .radial
            gradientLayer.colors = colors.map(\.cgColor)
            gradientLayer.locations = locations.map { NSNumber(value: Double($0)) }
            appliedOutlineKey = nil
        case .solid:
            break
        }
    }

    private func gradientPoints(on canvas: GradientCanvas) -> (start: CGPoint, end: CGPoint)? {
        switch fill {
        case .linearGradient(_, _, let start, let end):
            return (canvas.unitPoint(CGPoint(x: start.x, y: start.y)), canvas.unitPoint(CGPoint(x: end.x, y: end.y)))
        case .radialGradient(_, _, let endRadius):
            let size = canvas.frame.size
            guard size.width > 0, size.height > 0 else { return nil }
            let center = canvas.unitPoint(CGPoint(x: 0.5, y: 0.5))
            return (center, CGPoint(x: center.x + endRadius / size.width, y: center.y + endRadius / size.height))
        case .solid, nil:
            return nil
        }
    }

    private func animateOutline(_ timeline: NotchMorphTimeline) {
        guard let style = shape, timeline.frames.count > 1 else { return }
        let topDown = isTopDown
        let gradient = showsGradient
        let canvasHeight = bounds.height
        let empty = CGMutablePath()
        var paths: [Any] = []
        var localBounds: [Any] = []
        var positions: [Any] = []
        var localPaths: [Any] = []
        var startPoints: [Any] = []
        var endPoints: [Any] = []
        var rimStartPoints: [Any] = []
        var rimEndPoints: [Any] = []
        paths.reserveCapacity(timeline.frames.count)

        for frame in timeline.frames {
            let rect = NotchMorphGeometry.outlineRect(for: frame, in: self)
            let topDownPath = NotchMorphGeometry.path(style, values: frame.values, in: rect)
            var path = topDownPath
            if !topDown, let topDownPath {
                var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvasHeight)
                path = topDownPath.copy(using: &flip)
            }
            paths.append(path ?? empty)
            guard gradient else { continue }
            let canvas = GradientCanvas(outline: rect, path: topDownPath, topDown: topDown)
            let layerRect = NotchMorphGeometry.layerRect(canvas.frame, canvasHeight: canvasHeight, topDown: topDown)
            localBounds.append(NSValue(rect: canvas.local))
            positions.append(NSValue(point: CGPoint(x: layerRect.midX, y: layerRect.midY)))
            localPaths.append(topDownPath.flatMap(canvas.localPath) ?? empty)
            if let points = gradientPoints(on: canvas) {
                startPoints.append(NSValue(point: points.start))
                endPoints.append(NSValue(point: points.end))
            }
            rimStartPoints.append(NSValue(point: canvas.unitPoint(CGPoint(x: 0.5, y: 0))))
            rimEndPoints.append(NSValue(point: canvas.unitPoint(CGPoint(x: 0.5, y: 1))))
        }

        let usesUnion = timeline.frames.contains { frame in
            !frame.values.satellites.isEmpty
                || style.islandBarPresence(height: frame.values.height) > 0
        }
        let discrete = usesUnion || !NotchMorphGeometry.pathsInterpolate(paths)
        shapeLayer.add(timeline.animation("path", values: paths, on: shapeLayer, discrete: discrete), forKey: "morph.path")
        shapeLayer.add(timeline.animation("shadowPath", values: paths, on: shapeLayer, discrete: discrete), forKey: "morph.shadowPath")
        for glow in glowLayers {
            glow.add(timeline.animation("path", values: paths, on: glow, discrete: discrete), forKey: "morph.path")
            glow.add(timeline.animation("shadowPath", values: paths, on: glow, discrete: discrete), forKey: "morph.shadowPath")
        }
        if rim != nil, !showsLitRim {
            rimLayer.add(timeline.animation("path", values: paths, on: rimLayer, discrete: discrete), forKey: "morph.path")
        }
        if gradient {
            gradientLayer.add(timeline.animation("bounds", values: localBounds, on: gradientLayer), forKey: "morph.bounds")
            gradientLayer.add(timeline.animation("position", values: positions, on: gradientLayer), forKey: "morph.position")
            gradientMask.add(timeline.animation("bounds", values: localBounds, on: gradientMask), forKey: "morph.bounds")
            let maskPositions = localBounds.map { value -> Any in
                let rect = (value as! NSValue).rectValue
                return NSValue(point: CGPoint(x: rect.midX, y: rect.midY))
            }
            gradientMask.add(timeline.animation("position", values: maskPositions, on: gradientMask), forKey: "morph.position")
            gradientMask.add(
                timeline.animation("path", values: localPaths, on: gradientMask, discrete: discrete),
                forKey: "morph.path"
            )
            if showsLitRim {
                for layer in [rimGradient, rimMask] as [CALayer] {
                    layer.add(timeline.animation("bounds", values: localBounds, on: layer), forKey: "morph.bounds")
                    layer.add(timeline.animation("position", values: maskPositions, on: layer), forKey: "morph.position")
                }
                rimMask.add(timeline.animation("path", values: localPaths, on: rimMask, discrete: discrete), forKey: "morph.path")
                rimGradient.add(timeline.animation("startPoint", values: rimStartPoints, on: rimGradient), forKey: "morph.startPoint")
                rimGradient.add(timeline.animation("endPoint", values: rimEndPoints, on: rimGradient), forKey: "morph.endPoint")
            }
            if startPoints.count == timeline.frames.count {
                gradientLayer.add(timeline.animation("startPoint", values: startPoints, on: gradientLayer), forKey: "morph.startPoint")
                gradientLayer.add(timeline.animation("endPoint", values: endPoints, on: gradientLayer), forKey: "morph.endPoint")
            }
        }
    }

    private func renderOutline(_ frame: NotchMorphFrame) {
        guard let engine, engine.hasTarget, let style = shape else { return }
        let topDown = isTopDown
        let gradient = showsGradient
        let key = OutlineKey(
            frame: NotchMorphFrame(time: 0, values: frame.values, isMoving: frame.isMoving),
            shape: style,
            bounds: bounds,
            topDown: topDown,
            gradient: gradient,
            glowCount: glowLayers.count,
            rim: rim != nil,
            windowOrigin: frame.isMoving ? nil : window.map { _ in convert(CGPoint.zero, to: nil) }
        )
        guard key != appliedOutlineKey else { return }
        appliedOutlineKey = key

        let rect = NotchMorphGeometry.outlineRect(for: frame, in: self)
        let topDownPath = NotchMorphGeometry.path(style, values: frame.values, in: rect)
        var path = topDownPath
        if !topDown, let topDownPath {
            var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
            path = topDownPath.copy(using: &flip)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = path
        shapeLayer.shadowPath = path
        for glow in glowLayers {
            glow.path = path
            glow.shadowPath = path
        }
        if rim != nil, !showsLitRim { rimLayer.path = path }
        if gradient {
            let canvas = GradientCanvas(outline: rect, path: topDownPath, topDown: topDown)
            let layerRect = NotchMorphGeometry.layerRect(canvas.frame, canvasHeight: bounds.height, topDown: topDown)
            let local = canvas.local
            let localPath = topDownPath.flatMap(canvas.localPath)
            gradientLayer.bounds = local
            gradientLayer.position = CGPoint(x: layerRect.midX, y: layerRect.midY)
            gradientMask.frame = local
            gradientMask.path = localPath
            if let points = gradientPoints(on: canvas) {
                gradientLayer.startPoint = points.start
                gradientLayer.endPoint = points.end
            }
            if showsLitRim {
                rimGradient.frame = local
                rimMask.frame = local
                rimMask.path = localPath
                rimGradient.startPoint = canvas.unitPoint(CGPoint(x: 0.5, y: 0))
                rimGradient.endPoint = canvas.unitPoint(CGPoint(x: 0.5, y: 1))
            }
        }
        CATransaction.commit()
    }
}

private struct GradientCanvas {
    let frame: CGRect
    let outline: CGRect
    let topDown: Bool

    init(outline rect: CGRect, path: CGPath?, topDown: Bool) {
        let drawn = path.map { rect.union($0.boundingBoxOfPath) } ?? rect
        frame = drawn
        outline = rect.offsetBy(dx: -drawn.minX, dy: -drawn.minY)
        self.topDown = topDown
    }

    var local: CGRect { CGRect(origin: .zero, size: frame.size) }

    func unitPoint(_ point: CGPoint) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else { return point }
        let x = (outline.minX + point.x * outline.width) / frame.width
        let y = (outline.minY + point.y * outline.height) / frame.height
        return CGPoint(x: x, y: topDown ? y : 1 - y)
    }

    func localPath(_ path: CGPath) -> CGPath? {
        var transform = CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
        if !topDown {
            transform = transform.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: frame.height))
        }
        return path.copy(using: &transform)
    }
}

// MARK: - Glass

@MainActor
final class NotchGlassMorphCoordinator {
    private weak var view: LiquidGlassHostView?
    private weak var engine: NotchMorphEngine?
    private var shape: CustomNotchShape?

    func attach(to view: LiquidGlassHostView) {
        self.view = view
        view.onLayout = { [weak self] in self?.refresh() }
    }

    func detach() {
        engine?.removeRenderer(self)
        engine = nil
        view?.onLayout = nil
    }

    func update(shape: CustomNotchShape, engine: NotchMorphEngine) {
        if self.engine !== engine {
            self.engine?.removeRenderer(self)
            self.engine = engine
            engine.addRenderer(self) { [weak self] frame in self?.render(frame) }
        }
        if self.shape != shape {
            self.shape = shape
            motionFrame = nil
        }
        refresh()
    }

    private func refresh() {
        guard let engine else { return }
        render(engine.currentFrame)
    }

    private var motionFrame: (generation: UInt64, size: CGSize)?

    private func render(_ frame: NotchMorphFrame) {
        guard let view, let engine, let shape, engine.hasTarget else {
            view?.setExternalShape(nil, in: .zero)
            motionFrame = nil
            return
        }
        guard frame.isMoving else {
            motionFrame = nil
            let rect = NotchMorphGeometry.outlineRect(for: frame, in: view)
            let path = NotchMorphGeometry.path(shape, values: frame.values, in: CGRect(origin: .zero, size: rect.size))
            view.setExternalShape(path, in: path == nil ? .zero : rect)
            return
        }
        var size: CGSize
        if let motionFrame, motionFrame.generation == engine.generation {
            size = motionFrame.size
        } else {
            let peak = engine.peakSize(from: frame.time)
            size = CGSize(width: ceil(peak.width), height: ceil(peak.height))
        }
        size = CGSize(width: max(size.width, ceil(frame.values.width)), height: max(size.height, ceil(frame.values.height)))
        motionFrame = (engine.generation, size)

        let canvasWidth = view.bounds.width
        let glassRect = NotchMorphGeometry.rect(size: size, canvasWidth: canvasWidth).integral
        let outline = NotchMorphGeometry.rect(size: frame.values.size, canvasWidth: canvasWidth)
        let local = outline.offsetBy(dx: -glassRect.minX, dy: -glassRect.minY)
        let path = NotchMorphGeometry.path(shape, values: frame.values, in: local)
        view.setExternalShape(path, in: path == nil ? .zero : glassRect)
    }
}