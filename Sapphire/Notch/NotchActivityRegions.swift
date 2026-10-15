//
//  NotchActivityRegions.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import AppKit
import SwiftUI

enum NotchActivityRegionSlot: CaseIterable, Hashable {
    case leading
    case trailing
    case bottom
}

struct NotchActivityRegions {
    var leading: AnyView
    var trailing: AnyView
    var bottom: AnyView?
    var identity: AnyHashable
    var bottomKind: String
    var bottomLeading: Bool
    var key: Key
    var horizontalPadding: CGFloat
    var centerGap: CGFloat
    var bandHeight: CGFloat
    var onSizeChange: (CGSize) -> Void

    struct Key: Equatable {
        var content: LiveActivityContent
        var base: NotchContentKey?

        var top: Key {
            guard case .standard(.music, _) = content else { return self }
            return Key(content: .standard(data: .music(bottom: .none), id: "music"), base: base)
        }
    }
}

extension NotchActivityRegions {
    static func bottomKind(for data: StandardActivityData) -> String? {
        guard case .music(let bottom) = data else { return nil }
        switch bottom {
        case .none: return nil
        case .peek: return "peek"
        case .lyrics(let line): return "lyrics-\(line.id.uuidString)"
        case .upNext: return "upNext"
        }
    }

    static func bottomIsLeading(for data: StandardActivityData) -> Bool {
        if case .music(let bottom) = data, case .upNext = bottom { return true }
        return false
    }
}

private struct NotchRegionRowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var notchRegionRowWidth: CGFloat? {
        get { self[NotchRegionRowWidthKey.self] }
        set { self[NotchRegionRowWidthKey.self] = newValue }
    }
}

enum NotchRegionTransitionStyle {
    case notch
    case fold
    case crossfade
}

@MainActor
final class NotchActivityRegionStage {
    private final class Slot {
        let kind: NotchActivityRegionSlot
        var current: NotchHostedContentView?
        var spare: NotchHostedContentView?
        var exiting: [NotchHostedContentView] = []
        var identity: AnyHashable?
        var bottomKind: String?
        var rowWidth: CGFloat?
        var spareFamily: Substring?

        init(kind: NotchActivityRegionSlot) { self.kind = kind }

        var visibleHosts: [NotchHostedContentView] {
            (current.map { [$0] } ?? []) + exiting
        }
    }

    private weak var container: NSView?
    private let wrap: (AnyView) -> AnyView
    private let onNeedsLayout: () -> Void
    private var slots: [NotchActivityRegionSlot: Slot] = [:]
    private var regions: NotchActivityRegions?
    private var lastKey: NotchActivityRegions.Key?
    private var reportedSize: CGSize?
    private(set) var isShowing = false
    private var effect = NotchContentEffect.identity

    private static let switchInDelay: CFTimeInterval = 0.02

    init(container: NSView, wrap: @escaping (AnyView) -> AnyView, onNeedsLayout: @escaping () -> Void) {
        self.container = container
        self.wrap = wrap
        self.onNeedsLayout = onNeedsLayout
        for kind in NotchActivityRegionSlot.allCases { slots[kind] = Slot(kind: kind) }
    }

    var visibleHosts: [(NotchActivityRegionSlot, NotchHostedContentView)] {
        NotchActivityRegionSlot.allCases.flatMap { kind in
            (slots[kind]?.visibleHosts ?? []).map { (kind, $0) }
        }
    }

    var currentHosts: [NotchHostedContentView] {
        NotchActivityRegionSlot.allCases.compactMap { slots[$0]?.current }
    }

    var requiredSize: CGSize? {
        guard let regions, let leading = slots[.leading]?.current, let trailing = slots[.trailing]?.current else { return nil }
        let half = max(leading.frame.width, trailing.frame.width)
        var width = half * 2 + regions.centerGap + regions.horizontalPadding * 2
        var height = regions.bandHeight
        if let bottom = slots[.bottom]?.current {
            width = max(width, bottom.frame.width)
            height += bottom.frame.height
        }
        return CGSize(width: ceil(width), height: ceil(height))
    }

    // MARK: Content

    func apply(_ newRegions: NotchActivityRegions?, animated: Bool) {
        guard let newRegions else {
            hideAll(animated: animated)
            return
        }
        let identityChanged = regions?.identity != newRegions.identity || !isShowing
        let keyChanged = lastKey != newRegions.key
        let topKeyChanged = lastKey?.top != newRegions.key.top
        regions = newRegions
        lastKey = newRegions.key
        isShowing = true
        if identityChanged { emptySpares() }

        update(.leading, view: newRegions.leading, switching: identityChanged, keyChanged: topKeyChanged, animated: animated)
        update(.trailing, view: newRegions.trailing, switching: identityChanged, keyChanged: topKeyChanged, animated: animated)

        let bottomSlot = slots[.bottom]!
        if let bottom = newRegions.bottom {
            let previousKind = bottomSlot.bottomKind
            let bottomSwitch = identityChanged || bottomSlot.current == nil || previousKind != newRegions.bottomKind
            let sameFamily = previousKind.map { Self.family($0) == Self.family(newRegions.bottomKind) } ?? false
            let style: NotchRegionTransitionStyle = (bottomSlot.current != nil && sameFamily && !identityChanged) ? .crossfade : .fold
            bottomSlot.bottomKind = newRegions.bottomKind
            let width = newRegions.bottomLeading ? topRowWidth : nil
            let widthChanged = width != bottomSlot.rowWidth
            bottomSlot.rowWidth = width
            let view = AnyView(bottom.environment(\.notchRegionRowWidth, width))
            update(.bottom, view: view, switching: bottomSwitch, keyChanged: keyChanged || widthChanged, animated: animated, style: style, family: Self.family(newRegions.bottomKind))
        } else if let current = bottomSlot.current {
            bottomSlot.current = nil
            bottomSlot.bottomKind = nil
            bottomSlot.rowWidth = nil
            dismiss(current, in: bottomSlot, animated: animated, style: .fold)
        }
        reportSizeIfNeeded()
    }

    private static func family(_ kind: String) -> Substring {
        kind.split(separator: "-", maxSplits: 1).first ?? Substring(kind)
    }

    private var topRowWidth: CGFloat? {
        guard let regions, let leading = slots[.leading]?.current, let trailing = slots[.trailing]?.current else { return nil }
        return ceil(max(leading.frame.width, trailing.frame.width) * 2 + regions.centerGap + regions.horizontalPadding * 2)
    }

    private func update(
        _ kind: NotchActivityRegionSlot,
        view: AnyView,
        switching: Bool,
        keyChanged: Bool,
        animated: Bool,
        style: NotchRegionTransitionStyle = .notch,
        family: Substring? = nil
    ) {
        let slot = slots[kind]!
        if switching || slot.current == nil {
            if let outgoing = slot.current {
                dismiss(outgoing, in: slot, animated: animated, style: style, keeping: style == .crossfade ? family : nil)
            }
            let host = takeSpare(for: slot, family: family)
            slot.current = host
            slot.identity = regions?.identity
            host.setRootView(wrap(view), key: nil)
            host.apply(effect, animation: nil)
            host.setHitTestable(true)
            host.present(fadeDuration: 0, curve: .linear)
            if animated { animateIn(host, slot: kind, style: style) } else { NotchRegionTransition.reset(host) }
        } else if keyChanged, let host = slot.current {
            host.setRootView(wrap(view), key: nil)
        }
    }

    private func takeSpare(for slot: Slot, family: Substring?) -> NotchHostedContentView {
        if let spare = slot.spare, !slot.exiting.contains(where: { $0 === spare }) {
            if slot.spareFamily != nil, slot.spareFamily != family { spare.park() }
            slot.spare = nil
            slot.spareFamily = nil
            return spare
        }
        let host = NotchHostedContentView(rootView: AnyView(EmptyView()), sizing: .fitting)
        host.onFittingSizeChange = { [weak self] in
            self?.reportSizeIfNeeded()
            self?.onNeedsLayout()
        }
        if let container {
            container.addSubview(host, positioned: .below, relativeTo: nil)
        }
        return host
    }

    private func dismiss(_ host: NotchHostedContentView, in slot: Slot, animated: Bool, style: NotchRegionTransitionStyle = .notch, keeping family: Substring? = nil) {
        host.setHitTestable(false)
        guard animated else {
            park(host, in: slot, keeping: family)
            return
        }
        slot.exiting.append(host)
        let identity = regions?.identity
        NotchRegionTransition.animateOut(host, slot: slot.kind, style: style) { [weak self, weak host] in
            guard let self, let host, slot.current !== host else { return }
            slot.exiting.removeAll { $0 === host }
            let stillWanted = self.isShowing && self.regions?.identity == identity
            self.park(host, in: slot, keeping: stillWanted ? family : nil)
            self.onNeedsLayout()
        }
    }

    private func park(_ host: NotchHostedContentView, in slot: Slot, keeping family: Substring? = nil) {
        slot.exiting.removeAll { $0 === host }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.layer?.isHidden = true
        host.park(keepingContent: family != nil)
        NotchRegionTransition.reset(host)
        CATransaction.commit()
        if slot.spare == nil {
            slot.spare = host
            slot.spareFamily = family
        } else if slot.spare !== host {
            host.removeFromSuperview()
        }
    }

    private func emptySpares() {
        for slot in slots.values where slot.spareFamily != nil {
            slot.spare?.park()
            slot.spareFamily = nil
        }
    }

    private func hideAll(animated: Bool) {
        guard isShowing else { return }
        isShowing = false
        emptySpares()
        for kind in NotchActivityRegionSlot.allCases {
            guard let slot = slots[kind], let current = slot.current else { continue }
            slot.current = nil
            slot.identity = nil
            slot.bottomKind = nil
            dismiss(current, in: slot, animated: animated, style: kind == .bottom ? .fold : .notch)
        }
        regions = nil
        lastKey = nil
        reportedSize = nil
    }

    private func animateIn(_ host: NotchHostedContentView, slot: NotchActivityRegionSlot, style: NotchRegionTransitionStyle) {
        NotchRegionTransition.animateIn(host, slot: slot, style: style, delay: Self.switchInDelay)
    }

    private func reportSizeIfNeeded() {
        guard let regions, let size = requiredSize, size.width > 1, size.height > 1, size != reportedSize else { return }
        reportedSize = size
        let report = regions.onSizeChange
        DispatchQueue.main.async { report(size) }
    }

    // MARK: Effects

    func setEffect(_ effect: NotchContentEffect, animation: Animation?) {
        if effect.scale != zoom {
            zoomFrom = zoom
            zoom = effect.scale
        }
        self.effect = effect
        for host in currentHosts where host.isPresented { host.apply(effect, animation: animation) }
    }

    private var zoom: CGFloat = 1
    private var zoomFrom: CGFloat = 1

    // MARK: Geometry

    func frame(of host: NotchHostedContentView, slot: NotchActivityRegionSlot, outline: CGRect, scale: CGFloat) -> CGRect {
        frame(of: host, slot: slot, outline: outline, zoom: zoom, scale: scale)
    }

    private func frame(of host: NotchHostedContentView, slot: NotchActivityRegionSlot, outline zoomed: CGRect, zoom z: CGFloat, scale: CGFloat) -> CGRect {
        guard let regions else { return host.frame }
        let size = host.frame.size
        let z = max(0.5, z)
        let top = CGPoint(x: zoomed.midX, y: zoomed.minY)
        let outline = CGRect(x: top.x - zoomed.width / z / 2, y: top.y, width: zoomed.width / z, height: zoomed.height / z)
        let x: CGFloat
        let y: CGFloat
        switch slot {
        case .leading:
            x = outline.minX + regions.horizontalPadding
            y = outline.minY + (regions.bandHeight - size.height) / 2
        case .trailing:
            x = outline.maxX - regions.horizontalPadding - size.width
            y = outline.minY + (regions.bandHeight - size.height) / 2
        case .bottom:
            x = regions.bottomLeading ? outline.minX : outline.midX - size.width / 2
            y = outline.minY + regions.bandHeight
        }
        let centre = CGPoint(
            x: top.x + (x + size.width / 2 - top.x) * z,
            y: top.y + (y + size.height / 2 - top.y) * z
        )
        return CGRect(
            x: NotchDisplayMetrics.snapToPixel(centre.x - size.width / 2, scale: scale),
            y: NotchDisplayMetrics.snapToPixel(centre.y - size.height / 2, scale: scale),
            width: size.width,
            height: size.height
        )
    }

    func position(in outline: CGRect, settled: Bool, scale: CGFloat) {
        for (slot, host) in visibleHosts {
            let origin = frame(of: host, slot: slot, outline: outline, scale: scale).origin
            if settled { host.settle(at: origin) } else { host.presentOrigin(origin) }
        }
    }

    func animatePositions(_ timeline: NotchMorphTimeline, rects: [CGRect], scale: CGFloat) {
        let w0 = rects.first?.width ?? 0, w1 = rects.last?.width ?? 0
        let zooms = rects.map { rect -> CGFloat in
            guard abs(w1 - w0) > 1 else { return zoom }
            return zoomFrom + (zoom - zoomFrom) * (rect.width - w0) / (w1 - w0)
        }
        zoomFrom = zoom
        for (slot, host) in visibleHosts {
            guard let layer = host.layer, let superlayer = layer.superlayer else { continue }
            let topDown = superlayer.contentsAreFlipped()
            let positions = zip(rects, zooms).map { rect, z -> Any in
                NSValue(point: NotchLayerGeometry.position(
                    for: frame(of: host, slot: slot, outline: rect, zoom: z, scale: scale),
                    anchor: layer.anchorPoint,
                    topDown: topDown,
                    superHeight: rect.height
                ))
            }
            layer.add(timeline.animation("position", values: positions, on: layer), forKey: "morph.position")
        }
    }

    func host(for slot: NotchActivityRegionSlot) -> NotchHostedContentView? {
        slots[slot]?.current
    }

    func animatePanelMorph(_ timeline: NotchMorphTimeline, rects: [CGRect], arrival: [CGFloat], closedRect: CGRect, scale: CGFloat) {
        guard rects.count == timeline.frames.count, arrival.count == rects.count else { return }
        let centre = CGPoint(x: closedRect.midX, y: closedRect.minY)
        let leaving = (arrival.first ?? 1) > (arrival.last ?? 0)
        for kind in NotchActivityRegionSlot.allCases {
            guard let host = slots[kind]?.current, host.isPresented,
                  let layer = host.layer, let superlayer = layer.superlayer,
                  let followLayer = host.followView.layer else { continue }
            let topDown = superlayer.contentsAreFlipped()
            let size = host.frame.size
            let closed = frame(of: host, slot: kind, outline: closedRect, scale: scale)
            let limit = max(12, NotchOutlineFollower.blurLimit(forHeight: max(size.height, 24)))
            let pieceCentre = CGPoint(x: size.width / 2, y: size.height / 2)

            var positions: [Any] = []
            var transforms: [CATransform3D] = []
            var opacities: [Float] = []
            var blurs: [CGFloat] = []
            positions.reserveCapacity(rects.count)
            for (index, (rect, h)) in zip(rects, arrival).enumerated() {
                let presence = min(1, max(0, h))
                let t = CGFloat(Double(index) * NotchMorphTimeline.step)
                let shown: CGFloat = leaving
                    ? 1 - NotchOutlineFollower.smoothstep(0, Self.fadeOutDuration, t)
                    : NotchOutlineFollower.smoothstep(Self.fadeInDelay, Self.fadeInDelay + Self.fadeInDuration, t)
                let zoom = 1 + Self.panelMorphGrowth * (1 - presence)
                let sink = min(max(0, rect.height - closedRect.height) * 0.25, Self.panelMorphSink)
                let mid = CGPoint(x: closed.midX, y: closed.midY)
                let moved = CGPoint(
                    x: centre.x + (mid.x - centre.x) * zoom,
                    y: centre.y + (mid.y - centre.y) * zoom + sink
                )
                let origin = CGPoint(x: moved.x - size.width / 2, y: moved.y - size.height / 2)
                positions.append(NSValue(point: NotchLayerGeometry.position(
                    for: CGRect(origin: origin, size: size),
                    anchor: layer.anchorPoint,
                    topDown: topDown,
                    superHeight: rect.height
                )))
                transforms.append(NotchOutlineFollower.mapping(
                    scale: zoom, from: pieceCentre, to: pieceCentre,
                    bounds: followLayer.bounds, anchor: followLayer.anchorPoint,
                    flipped: followLayer.contentsAreFlipped()
                ))
                opacities.append(Float(shown))
                blurs.append(limit * (1 - shown))
            }
            layer.add(timeline.animation("position", values: positions, on: layer), forKey: "morph.position")
            host.follower.play(timeline, transforms: transforms, opacities: opacities, blurs: blurs)
        }
    }

    private static let panelMorphGrowth: CGFloat = 0.5
    private static let fadeOutDuration: CGFloat = 0.34
    private static let fadeInDelay: CGFloat = 0.06
    private static let fadeInDuration: CGFloat = 0.32
    private static let panelMorphSink: CGFloat = 24

    func tearDown() {
        for slot in slots.values {
            for host in [slot.current, slot.spare].compactMap({ $0 }) + slot.exiting { host.removeFromSuperview() }
            slot.current = nil
            slot.spare = nil
            slot.exiting.removeAll()
        }
    }
}

@MainActor
enum NotchRegionTransition {
    private static let blurName = "regionBlur"
    private static let blurRadius: CGFloat = 14
    private static let collapsedScale: CGFloat = 0.55
    private static let notchwardDrift: CGFloat = 10
    private static let response: Double = 0.36
    private static let damping: Double = 0.88
    private static let outDuration: CFTimeInterval = 0.2

    private static func collapsedTransform(for slot: NotchActivityRegionSlot, style: NotchRegionTransitionStyle, in layer: CALayer) -> CATransform3D {
        switch style {
        case .crossfade: return CATransform3DIdentity
        case .fold: return foldedTransform(in: layer)
        case .notch: return collapsedTransform(for: slot, in: layer)
        }
    }

    private static func foldedTransform(in layer: CALayer) -> CATransform3D {
        let bounds = layer.bounds
        let flipped = layer.contentsAreFlipped()
        let px = bounds.width / 2 - bounds.width * layer.anchorPoint.x
        let top = flipped ? 0 : bounds.height
        let py = top - bounds.height * layer.anchorPoint.y
        var transform = CATransform3DIdentity
        transform.m34 = -1 / max(160, bounds.height * 5)
        transform = CATransform3DTranslate(transform, px, py, 0)
        transform = CATransform3DRotate(transform, (flipped ? 1 : -1) * foldAngle, 1, 0, 0)
        return CATransform3DTranslate(transform, -px, -py, 0)
    }

    private static let foldAngle: CGFloat = 82 * .pi / 180

    private static func collapsedTransform(for slot: NotchActivityRegionSlot, in layer: CALayer) -> CATransform3D {
        let bounds = layer.bounds
        let pivot: CGPoint
        let sx: CGFloat
        let sy: CGFloat
        switch slot {
        case .leading:
            pivot = CGPoint(x: bounds.width + notchwardDrift, y: bounds.height / 2)
            sx = collapsedScale; sy = collapsedScale
        case .trailing:
            pivot = CGPoint(x: -notchwardDrift, y: bounds.height / 2)
            sx = collapsedScale; sy = collapsedScale
        case .bottom:
            pivot = CGPoint(x: bounds.width / 2, y: -notchwardDrift)
            sx = 0.82; sy = 0.82
        }
        return scale(sx: sx, sy: sy, about: pivot, in: layer)
    }

    private static func scale(sx: CGFloat, sy: CGFloat, about pivot: CGPoint, in layer: CALayer) -> CATransform3D {
        let bounds = layer.bounds
        let flipped = layer.contentsAreFlipped()
        let px = pivot.x - bounds.width * layer.anchorPoint.x
        let top = flipped ? pivot.y : bounds.height - pivot.y
        let py = top - bounds.height * layer.anchorPoint.y
        var transform = CATransform3DMakeTranslation(px, py, 0)
        transform = CATransform3DScale(transform, sx, sy, 1)
        return CATransform3DTranslate(transform, -px, -py, 0)
    }

    static func animateIn(_ host: NotchHostedContentView, slot: NotchActivityRegionSlot, style: NotchRegionTransitionStyle, delay: CFTimeInterval) {
        guard let layer = host.transitionView.layer else { return }
        let begin = CACurrentMediaTime() + delay
        let collapsed = collapsedTransform(for: slot, style: style, in: layer)
        let spring: (String, Any, Any, CFTimeInterval) -> CAAnimation = { keyPath, from, to, begin in
            switch style {
            case .fold: return Self.spring(keyPath, from: from, to: to, begin: begin, response: 0.46, damping: 0.74)
            case .crossfade: return Self.spring(keyPath, from: from, to: to, begin: begin, response: 0.3, damping: 1)
            case .notch: return Self.spring(keyPath, from: from, to: to, begin: begin, response: response, damping: damping)
            }
        }
        let radius = style == .crossfade ? blurRadius * 0.5 : blurRadius
        let blurPath = "filters.\(blurName).inputRadius"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        installBlur(on: layer)
        layer.opacity = 1
        layer.sublayerTransform = CATransform3DIdentity
        layer.setValue(0, forKeyPath: blurPath)
        if style != .crossfade {
            layer.add(spring("sublayerTransform", NSValue(caTransform3D: collapsed), NSValue(caTransform3D: CATransform3DIdentity), begin), forKey: "region.transform")
        } else {
            layer.removeAnimation(forKey: "region.transform")
        }
        layer.add(spring("opacity", Float(0), Float(1), begin), forKey: "region.opacity")
        layer.add(spring(blurPath, radius, CGFloat(0), begin), forKey: "region.blur")
        CATransaction.commit()
        let settle = delay + 0.9
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak host] in
            guard let host, host.isPresented, let layer = host.transitionView.layer,
                  layer.animation(forKey: "region.blur") == nil else { return }
            removeBlur(from: layer)
        }
    }

    static func animateOut(_ host: NotchHostedContentView, slot: NotchActivityRegionSlot, style: NotchRegionTransitionStyle, completion: @escaping () -> Void) {
        guard let layer = host.transitionView.layer else {
            completion()
            return
        }
        let presented = layer.presentation() ?? layer
        let collapsed = collapsedTransform(for: slot, style: style, in: layer)
        let blurPath = "filters.\(blurName).inputRadius"
        let fromBlur = (presented.value(forKeyPath: blurPath) as? NSNumber)?.doubleValue ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        installBlur(on: layer)
        let fromTransform = presented.sublayerTransform
        let fromOpacity = presented.opacity
        layer.removeAllAnimations()
        layer.sublayerTransform = collapsed
        layer.opacity = 0
        layer.setValue(blurRadius, forKeyPath: blurPath)
        layer.add(ease("sublayerTransform", from: NSValue(caTransform3D: fromTransform), to: NSValue(caTransform3D: collapsed)), forKey: "region.transform")
        layer.add(ease("opacity", from: fromOpacity, to: Float(0)), forKey: "region.opacity")
        layer.add(ease(blurPath, from: fromBlur, to: blurRadius), forKey: "region.blur")
        CATransaction.commit()
    }

    static func reset(_ host: NotchHostedContentView) {
        guard let layer = host.transitionView.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.sublayerTransform = CATransform3DIdentity
        layer.opacity = 1
        removeBlur(from: layer)
        CATransaction.commit()
    }

    private static func spring(_ keyPath: String, from: Any, to: Any, begin: CFTimeInterval, response: Double, damping: Double) -> CAAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        let omega = 2 * Double.pi / response
        animation.mass = 1
        animation.stiffness = omega * omega
        animation.damping = 2 * damping * omega
        animation.duration = animation.settlingDuration
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = begin
        animation.fillMode = .backwards
        return animation
    }

    private static func ease(_ keyPath: String, from: Any, to: Any) -> CAAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.duration = outDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        animation.fromValue = from
        animation.toValue = to
        return animation
    }

    private static func installBlur(on layer: CALayer) {
        if let filters = layer.filters, filters.contains(where: { ($0 as? NSObject)?.value(forKey: "name") as? String == blurName }) {
            return
        }
        if let cls = NSClassFromString("CAFilter") as? NSObject.Type,
           let filter = cls.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject {
            filter.setValue(blurName, forKey: "name")
            filter.setValue(0, forKey: "inputRadius")
            layer.filters = [filter]
        } else if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.name = blurName
            blur.setValue(0, forKey: kCIInputRadiusKey)
            layer.filters = [blur]
        }
    }

    private static func removeBlur(from layer: CALayer) {
        guard layer.filters != nil else { return }
        layer.filters = nil
    }
}