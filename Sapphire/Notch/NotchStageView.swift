//
//  NotchStageView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-11
//

import AppKit
import SwiftUI

class NotchPassthroughView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

final class NotchClipView: NotchPassthroughView {
    private(set) var presentedRect: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        layer?.actions = NotchLayerSurfaceView.noActions
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ rect: CGRect, cornerRadius: CGFloat, roundsAllCorners: Bool, settled: Bool) {
        presentedRect = rect
        if settled {
            if frame != rect {
                setFrameOrigin(rect.origin)
                setFrameSize(rect.size)
            }
            if bounds.origin != rect.origin { setBoundsOrigin(rect.origin) }
        }
        guard let layer else { return }
        let bounds = CGRect(origin: rect.origin, size: rect.size)
        if layer.bounds != bounds { layer.bounds = bounds }
        if let superlayer = layer.superlayer {
            let position = NotchLayerGeometry.position(
                for: rect,
                anchor: layer.anchorPoint,
                topDown: superlayer.contentsAreFlipped(),
                superHeight: superlayer.bounds.height
            )
            if layer.position != position { layer.position = position }
        }
        if layer.cornerRadius != cornerRadius {
            layer.cornerRadius = cornerRadius
            layer.cornerCurve = .continuous
        }
        let bottom: CACornerMask = layer.contentsAreFlipped()
            ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let corners: CACornerMask = roundsAllCorners
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : bottom
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard presentedRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

@MainActor
final class NotchStageView: NSView {
    let engine: NotchMorphEngine
    private let band = NotchPassthroughView()
    private let surface = NotchSurfaceHostView()
    private let clip = NotchClipView()

    private var activityHost: NotchHostedContentView?
    private lazy var regionStage = NotchActivityRegionStage(
        container: clip,
        wrap: { [unowned self] view in self.environmentWrapped(view) },
        onNeedsLayout: { [weak self] in self?.positionRegions() }
    )
    private lazy var satelliteStage = NotchSatelliteStage(
        container: band,
        wrap: { [unowned self] view in self.environmentWrapped(view) }
    )
    private var planeContainer: NotchWidgetPlaneContainer?
    private var chromeHosts: [NotchChromeSlot: NotchHostedContentView] = [:]
    private var chromePieces: [NotchChromeSlot: NotchChromePiece] = [:]

    private var layoutModel: NotchStageLayout?
    private var surfaceStyle: NotchSurfaceStyle?
    private var activitySize: CGSize = .zero
    private var activityFollows = false
    private var activityBehindPanel = false
    private var planeSize: CGSize = .zero
    private var onTap: (() -> Void)?
    private var signals = NotchStageCoordinator.Values()
    private var presentedFrame: NotchMorphFrame?
    private var presentedRect: CGRect = .zero
    private var isTapCandidate = false

    init(engine: NotchMorphEngine) {
        self.engine = engine
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        band.wantsLayer = true
        surface.autoresizingMask = [.width, .height]
        addSubview(band)
        band.addSubview(surface)
        band.addSubview(clip)
        engine.addRenderer(
            self,
            render: { [weak self] frame in self?.render(frame) },
            animate: { [weak self] timeline in self?.animate(timeline) }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func invalidateIntrinsicContentSize() {}

    func tearDown() {
        engine.removeRenderer(self)
        engine.linkHostDidLeaveWindow(self)
        surface.detach()
        activityHost?.removeFromSuperview()
        activityHost = nil
        regionStage.tearDown()
        satelliteStage.tearDown()
        removePlane()
        for host in chromeHosts.values { host.removeFromSuperview() }
        chromeHosts.removeAll()
        chromePieces.removeAll()
    }

    // MARK: Window

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            engine.setLinkHost(self)
            positionContent()
            render(engine.currentFrame)
        } else {
            engine.linkHostDidLeaveWindow(self)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        positionContent()
        render(engine.currentFrame)
    }

    override func layout() {
        super.layout()
        layoutBand()
        positionContent()
        render(engine.currentFrame)
        replayTimelineIfNeeded()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutBand()
        positionContent()
        render(engine.currentFrame)
        replayTimelineIfNeeded()
    }

    private var needsTimelineReplay = false

    private func replayTimelineIfNeeded() {
        guard needsTimelineReplay else { return }
        needsTimelineReplay = false
        guard let timeline = engine.activeTimeline, timeline.end > CACurrentMediaTime() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        animate(timeline)
        CATransaction.commit()
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? layoutModel?.displayScale ?? 2
    }

    private func layoutBand() {
        let inset = max(0, layoutModel?.topInset ?? 0)
        let frame = CGRect(x: 0, y: inset, width: bounds.width, height: max(0, bounds.height - inset))
        if band.frame.size != frame.size, engine.activeTimeline != nil { needsTimelineReplay = true }
        if band.frame != frame { band.frame = frame }
        if surface.frame != band.bounds { surface.frame = band.bounds }
    }

    // MARK: Content

    func apply(_ content: NotchStageContent) {
        let layoutChanged = content.layout != layoutModel
        layoutModel = content.layout
        if layoutChanged { layoutBand() }

        var style = content.surface
        if style.animatesShadowOpacity {
            style.fillShadow.opacity = signals.surfaceShadowOpacity
            style.glass?.shadow.opacity = CGFloat(signals.surfaceShadowOpacity)
        }
        surfaceStyle = style
        surface.apply(style, engine: engine, shadowAnimation: nil)

        applyRegions(content)
        satelliteStage.apply(content.satellites, layout: content.layout.satelliteLayout)
        applyActivity(content)
        hideRegionsBehindPanel()
        applyPlane(content)
        applyChrome(content.chrome)
        onTap = content.onTap

        positionContent()
        render(engine.currentFrame)
    }

    private func environmentWrapped(_ view: AnyView) -> AnyView {
        guard let layoutModel else { return view }
        return AnyView(
            view.notchHostEnvironment(bandHeight: layoutModel.bandHeight, displayScale: layoutModel.displayScale)
        )
    }

    private func applyRegions(_ content: NotchStageContent) {
        activityBehindPanel = content.activityBehindPanel
        defer {
            hideRegionsBehindPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.engine.activeTimeline == nil else { return }
                self.settleContentVisibility()
            }
        }
        let follows = content.activityFollowsOutline
        if activityFollows != follows, content.activity == nil {
            activityFollows = follows
            if !follows {
                activityHost?.follower.reset()
                for host in regionStage.currentHosts { host.follower.reset() }
            }
        }
        let wasShowing = regionStage.isShowing
        let previousHosts = Set(regionStage.currentHosts.map(ObjectIdentifier.init))
        regionStage.apply(content.activityRegions, animated: window != nil)
        guard content.activityRegions != nil else { return }
        regionStage.setEffect(signals.activity, animation: nil)
        positionRegions()
        let newHosts = regionStage.currentHosts.filter { !previousHosts.contains(ObjectIdentifier($0)) }
        guard !newHosts.isEmpty, activityFollows || !wasShowing else { return }
        if let timeline = engine.activeTimeline {
            regionStage.animatePositions(timeline, rects: timeline.frames.map { NotchMorphGeometry.outlineRect(for: $0, in: band) }, scale: backingScale)
        } else if activityFollows, !activityBehindPanel, !wasShowing {
            for host in newHosts { host.follower.hideUntilDriven() }
        }
    }

    private func positionRegions() {
        guard regionStage.isShowing || !regionStage.visibleHosts.isEmpty else { return }
        let settled = !(presentedFrame?.isMoving ?? false)
        regionStage.position(in: presentedRect, settled: settled, scale: backingScale)
    }

    private func applyActivity(_ content: NotchStageContent) {
        guard let activity = content.activity else {
            if let activityHost, activityHost.isPresented { activityHost.park() }
            return
        }
        activitySize = content.activitySize
        if activityFollows != content.activityFollowsOutline {
            activityFollows = content.activityFollowsOutline
            if !activityFollows { activityHost?.follower.reset() }
        }
        let host: NotchHostedContentView
        if let existing = activityHost {
            host = existing
        } else {
            host = NotchHostedContentView(rootView: AnyView(EmptyView()), sizing: .fixed)
            activityHost = host
        }
        if host.superview !== clip {
            host.removeFromSuperview()
            clip.addSubview(host, positioned: .below, relativeTo: nil)
        }
        let appearing = !host.isPresented
        if appearing {
            host.apply(signals.activity, animation: nil)
            host.present(fadeDuration: 0, curve: .linear)
        }
        host.setRootView(environmentWrapped(activity), key: content.activityKey)
        if appearing, activityFollows {
            if let timeline = engine.activeTimeline {
                positionContent()
                followActivity(timeline)
            } else {
                host.follower.hideUntilDriven()
            }
        }
    }

    private func applyPlane(_ content: NotchStageContent) {
        guard let plane = content.plane else {
            removePlane()
            return
        }
        planeSize = content.planeSize
        if let planeContainer, planeContainer.plane === plane {
            planeContainer.entranceStiffness = content.planeEntranceStiffness
            planeContainer.entranceDamping = content.planeEntranceDamping
            planeContainer.followsOutline = content.planeFollowsOutline
            if !content.planeFollowsOutline { releaseChromeFollow() }
            return
        }
        removePlane()
        let container = NotchWidgetPlaneContainer(plane: plane)
        container.entranceStiffness = content.planeEntranceStiffness
        container.entranceDamping = content.planeEntranceDamping
        container.followsOutline = content.planeFollowsOutline
        container.frame = planeFrame()
        defer {
            if let timeline = engine.activeTimeline {
                container.animateFollow(timeline, outlines: timeline.frames.map { $0.values.size })
            }
        }
        let chromeHostIDs = Set(chromeHosts.values.map(ObjectIdentifier.init))
        if let lowestChrome = clip.subviews.first(where: { chromeHostIDs.contains(ObjectIdentifier($0)) }) {
            clip.addSubview(container, positioned: .below, relativeTo: lowestChrome)
        } else {
            clip.addSubview(container, positioned: .below, relativeTo: nil)
        }
        planeContainer = container
    }

    private func releaseChromeFollow() {
        for host in chromeHosts.values where host.isPresented && !host.follower.isDriving {
            host.follower.reset()
        }
    }

    private func hideRegionsBehindPanel() {
        guard activityBehindPanel else { return }
        var hosts = regionStage.currentHosts
        if let activityHost, activityHost.isPresented { hosts.append(activityHost) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for host in hosts { host.hosting.setTrackingSuppressed(true) }
        for host in hosts where !host.follower.isDriving {
            guard let layer = host.followView.layer, layer.opacity > 0 else { continue }
            layer.removeAnimation(forKey: "follow.opacity")
            layer.opacity = 0
        }
        CATransaction.commit()
    }

    private func settleContentVisibility() {
        if activityBehindPanel {
            hideRegionsBehindPanel()
        } else {
            revealRegionsAtRest()
        }
    }

    private func revealRegionsAtRest() {
        guard !activityBehindPanel else { return }
        var hosts = regionStage.currentHosts
        if let activityHost, activityHost.isPresented { hosts.append(activityHost) }
        for host in hosts { host.setHitTestable(true) }
        for host in hosts where !host.follower.isDriving {
            host.follower.reset()
        }
    }

    private func removePlane() {
        guard let container = planeContainer else { return }
        container.detachPlane()
        container.removeFromSuperview()
        planeContainer = nil
        revealRegionsAtRest()
    }

    private func applyChrome(_ pieces: [NotchChromeSlot: NotchChromePiece]) {
        for slot in NotchChromeSlot.allCases {
            if let piece = pieces[slot] {
                let root = environmentWrapped(piece.view)
                let host: NotchHostedContentView
                if let existing = chromeHosts[slot] {
                    host = existing
                } else {
                    host = NotchHostedContentView(rootView: AnyView(EmptyView()), sizing: piece.width == .fitting ? .fitting : .fixed)
                    host.onFittingSizeChange = { [weak self] in self?.positionChrome() }
                    clip.addSubview(host, positioned: .above, relativeTo: nil)
                    chromeHosts[slot] = host
                }
                let appearing = !host.isPresented
                chromePieces[slot] = piece
                host.setHitTestable(piece.hitTestable)
                host.setRootView(root, key: piece.key)
                if appearing {
                    if slot == .hud { host.apply(signals.hud, animation: nil) }
                    positionChrome(slot: slot, host: host, in: presentedRect, settled: true)
                    host.present(fadeDuration: piece.fade.inDuration, curve: piece.fade.curve)
                    if planeContainer?.followsOutline == true {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        host.followView.layer?.opacity = 0
                        CATransaction.commit()
                    }
                }
            } else if let host = chromeHosts[slot], host.isPresented {
                let fade = chromePieces[slot]?.fade ?? .icons
                host.dismiss(fadeDuration: fade.outDuration, curve: fade.curve) { [weak self, weak host] in
                    guard let self, let host, self.chromeHosts[slot] === host, !host.isPresented else { return }
                    host.park()
                    self.chromePieces[slot] = nil
                }
            }
        }
    }

    // MARK: Signals

    func applySignals(_ values: NotchStageCoordinator.Values, animation: Animation?) {
        signals = values
        setSurfaceShadowOpacity(values.surfaceShadowOpacity, animation: animation)
        setActivityEffect(values.activity, animation: animation)
        setHUDEffect(values.hud, animation: animation)
    }

    func setSurfaceShadowOpacity(_ opacity: Double, animation: Animation?) {
        signals.surfaceShadowOpacity = opacity
        surface.setShadowOpacity(opacity, animation: animation)
        if var style = surfaceStyle, style.animatesShadowOpacity {
            style.fillShadow.opacity = opacity
            style.glass?.shadow.opacity = CGFloat(opacity)
            surfaceStyle = style
        }
    }

    func setActivityEffect(_ effect: NotchContentEffect, animation: Animation?) {
        signals.activity = effect
        if let activityHost, activityHost.isPresented { activityHost.apply(effect, animation: animation) }
        regionStage.setEffect(effect, animation: animation)
    }

    func setHUDEffect(_ effect: NotchContentEffect, animation: Animation?) {
        signals.hud = effect
        if let host = chromeHosts[.hud], host.isPresented { host.apply(effect, animation: animation) }
    }

    // MARK: Geometry

    private var canvasWidth: CGFloat { band.bounds.width }

    private func centeredFrame(for size: CGSize) -> CGRect {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let x = NotchDisplayMetrics.centeredOriginX(width: width, midX: canvasWidth / 2, scale: backingScale)
        return CGRect(x: x, y: 0, width: width, height: height)
    }

    private func planeFrame() -> CGRect {
        let size = planeSize.width > 1 && planeSize.height > 1 ? planeSize : (layoutModel?.outlineSize ?? .zero)
        return centeredFrame(for: size)
    }

    private func positionContent() {
        if let activityHost, activityHost.isPresented {
            let frame = centeredFrame(for: activitySize.width > 0 ? activitySize : (layoutModel?.outlineSize ?? .zero))
            if activityHost.frame != frame { activityHost.frame = frame }
        }
        if let planeContainer {
            let frame = planeFrame()
            if planeContainer.frame != frame { planeContainer.frame = frame }
        }
        positionChrome()
        positionRegions()
    }

    private func positionChrome() {
        let settled = !(presentedFrame?.isMoving ?? false)
        for (slot, host) in chromeHosts where host.isPresented {
            positionChrome(slot: slot, host: host, in: presentedRect, settled: settled)
        }
    }

    private func positionChrome(slot: NotchChromeSlot, host: NotchHostedContentView, in rect: CGRect, settled: Bool) {
        guard let piece = chromePieces[slot] else { return }
        let scale = backingScale
        var size = host.frame.size
        if piece.width == .outline {
            size = CGSize(
                width: max(0, layoutModel?.outlineSize.width ?? rect.width),
                height: piece.height ?? max(size.height, host.preferredContentSize.height)
            )
            if host.frame.size != size { host.setFrameSize(size) }
        }
        let frame = NotchChromeGeometry.frame(
            anchor: piece.anchor,
            inset: piece.inset,
            top: piece.top,
            bottom: piece.bottom,
            size: size,
            outline: rect,
            scale: scale
        )
        if settled {
            host.settle(at: frame.origin)
        } else {
            host.presentOrigin(frame.origin)
        }
    }

    // MARK: Rendering

    private func render(_ frame: NotchMorphFrame) {
        presentedFrame = frame
        guard engine.hasTarget else { return }
        let rect = NotchMorphGeometry.outlineRect(for: frame, in: band)
        presentedRect = rect
        let cornerRadius: CGFloat
        let roundsAllCorners: Bool
        if let layoutModel, layoutModel.isFloatingIsland {
            cornerRadius = islandClipRadius(rect, values: frame.values)
            roundsAllCorners = true
        } else {
            cornerRadius = min(rect.height / 2, rect.width / 2, frame.values.bottomCornerRadius)
            roundsAllCorners = false
        }
        clip.present(clipRect(rect, values: frame.values), cornerRadius: max(0, cornerRadius), roundsAllCorners: roundsAllCorners, settled: !frame.isMoving)
        planeContainer?.followOutline(rect, isMoving: frame.isMoving)
        for (slot, host) in chromeHosts where host.isPresented {
            positionChrome(slot: slot, host: host, in: rect, settled: !frame.isMoving)
        }
        regionStage.position(in: rect, settled: !frame.isMoving, scale: backingScale)
        satelliteStage.render(frame.values, outline: rect, final: engine.activeTimeline == nil)
        if let layer = islandBarContentLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = islandBarContentOpacity(height: rect.height)
            CATransaction.commit()
        }
    }

    private func clipRect(_ rect: CGRect, values: NotchMorphValues) -> CGRect {
        guard let style = surfaceStyle?.shape else { return rect }
        let inset = NotchMorphGeometry.shape(style, values: values).shoulderInset(in: rect)
        guard inset > 0, rect.width > inset * 2 else { return rect }
        return rect.insetBy(dx: inset, dy: 0)
    }

    private func islandClipRadius(_ rect: CGRect, values: NotchMorphValues) -> CGFloat {
        guard let style = surfaceStyle?.shape else {
            return min(rect.height / 2, rect.width / 2, values.bottomCornerRadius)
        }
        let shape = NotchMorphGeometry.shape(style, values: values)
        return shape.islandCardRadius(shape.islandCardRect(in: rect))
    }

    private var islandBarContentLayer: CALayer? {
        guard let host = chromeHosts[.islandBar], host.isPresented else { return nil }
        return host.transitionView.layer
    }

    private func islandBarContentOpacity(height: CGFloat) -> Float {
        guard let shape = surfaceStyle?.shape else { return 1 }
        let presence = shape.islandBarPresence(height: height)
        let t = min(1, max(0, (presence - 0.35) / 0.55))
        return Float(t * t * (3 - 2 * t))
    }

    // MARK: Timelines

    private func animate(_ timeline: NotchMorphTimeline) {
        guard engine.hasTarget, timeline.frames.count > 1 else { return }
        let rects = timeline.frames.map { NotchMorphGeometry.outlineRect(for: $0, in: band) }

        if let layer = clip.layer, let superlayer = layer.superlayer {
            let topDown = superlayer.contentsAreFlipped()
            let superHeight = superlayer.bounds.height
            var bounds: [Any] = []
            var positions: [Any] = []
            var radii: [Any] = []
            for (outline, frame) in zip(rects, timeline.frames) {
                let rect = clipRect(outline, values: frame.values)
                bounds.append(NSValue(rect: CGRect(origin: rect.origin, size: rect.size)))
                positions.append(NSValue(point: NotchLayerGeometry.position(
                    for: rect, anchor: layer.anchorPoint, topDown: topDown, superHeight: superHeight
                )))
                let limit = min(rect.height / 2, rect.width / 2)
                let radius = layoutModel?.isFloatingIsland == true
                    ? islandClipRadius(rect, values: frame.values)
                    : min(limit, frame.values.bottomCornerRadius)
                radii.append(NSNumber(value: Double(max(0, radius))))
            }
            layer.add(timeline.animation("bounds", values: bounds, on: layer), forKey: "morph.bounds")
            layer.add(timeline.animation("position", values: positions, on: layer), forKey: "morph.position")
            layer.add(timeline.animation("cornerRadius", values: radii, on: layer), forKey: "morph.cornerRadius")
        }

        let scale = backingScale
        for (slot, host) in chromeHosts where host.isPresented {
            guard let piece = chromePieces[slot], let layer = host.layer, let superlayer = layer.superlayer else { continue }
            let topDown = superlayer.contentsAreFlipped()
            let size = host.frame.size
            let positions = rects.map { rect -> Any in
                let frame = NotchChromeGeometry.frame(
                    anchor: piece.anchor, inset: piece.inset, top: piece.top, bottom: piece.bottom, size: size, outline: rect, scale: scale
                )
                return NSValue(point: NotchLayerGeometry.position(
                    for: frame, anchor: layer.anchorPoint, topDown: topDown, superHeight: rect.height
                ))
            }
            layer.add(timeline.animation("position", values: positions, on: layer), forKey: "morph.position")
        }

        regionStage.animatePositions(timeline, rects: rects, scale: scale)
        satelliteStage.animate(timeline, rects: rects)
        if let layer = islandBarContentLayer {
            let opacities = rects.map { NSNumber(value: islandBarContentOpacity(height: $0.height)) }
            layer.add(timeline.animation("opacity", values: opacities, on: layer), forKey: "islandBar.opacity")
        }

        let sizes = timeline.frames.map { $0.values.size }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, timeline.end - CACurrentMediaTime()) + 0.08) { [weak self] in
            self?.settleContentVisibility()
        }
        if playRegionPanelMorph(timeline, rects: rects, sizes: sizes) {
        } else {
            planeContainer?.animateFollow(timeline, outlines: sizes)
            followActivity(timeline)
            hideRegionsBehindPanel()
        }

        if let plane = planeContainer, plane.followsOutline, plane.bounds.height > 48 {
            for (slot, host) in chromeHosts where chromePieces[slot] != nil && !host.isHidden {
                host.follower.animate(
                    timeline, outlines: sizes, layoutSize: plane.bounds.size,
                    scalesContent: false, blurHeight: host.frame.height
                )
            }
        }
    }

    private func playRegionPanelMorph(_ timeline: NotchMorphTimeline, rects: [CGRect], sizes: [CGSize]) -> Bool {
        guard activityFollows, regionStage.isShowing, let activity = regionStage.requiredSize,
              let plane = planeContainer, plane.followsOutline, plane.bounds.height > 48,
              let first = sizes.first, let last = sizes.last, let firstRect = rects.first, let lastRect = rects.last else {
            return false
        }
        let panel = plane.bounds.size
        func distance(_ a: CGSize, _ b: CGSize) -> CGFloat {
            max(abs(log(max(a.width, 1) / max(b.width, 1))), abs(log(max(a.height, 1) / max(b.height, 1))))
        }
        let opening = distance(last, panel) < 0.15 && distance(first, panel) > 0.15
        let closing = distance(last, activity) < 0.25 && distance(last, activity) < distance(last, panel)
            && distance(first, activity) > 0.2
        guard opening || closing else { return false }
        let closedRect = opening ? firstRect : lastRect
        let span = activity.width - panel.width
        guard abs(span) > 1 else { return false }
        let arrival = sizes.map { ($0.width - panel.width) / span }

        plane.animateFollow(timeline, outlines: sizes)
        regionStage.animatePanelMorph(timeline, rects: rects, arrival: arrival, closedRect: closedRect, scale: backingScale)
        return true
    }

    private func followActivity(_ timeline: NotchMorphTimeline) {
        guard activityFollows, let host = activityHost, host.isPresented else { return }
        var panelSpan: CGFloat?
        if let plane = planeContainer, plane.followsOutline, plane.bounds.height > 48 {
            panelSpan = abs(log(max(plane.bounds.width, 1) / max(host.frame.width, 1)))
        }
        host.follower.animate(
            timeline,
            outlines: timeline.frames.map { $0.values.size },
            layoutSize: host.frame.size,
            crossFadeSpan: panelSpan
        )
    }

    // MARK: Inspection

    var presentedClipFrame: CGRect { clip.presentedRect }

    var settledClipFrame: CGRect { clip.frame }

    var clipLayerGeometry: (bounds: CGRect, position: CGPoint)? {
        clip.layer.map { (bounds: $0.bounds, position: $0.position) }
    }

    func chromeFrame(for slot: NotchChromeSlot) -> CGRect? {
        guard let host = chromeHosts[slot], host.isPresented else { return nil }
        return host.frame
    }

    func stagePointIsInsideOutline(_ point: CGPoint) -> Bool {
        outlineContains(band.convert(point, from: self))
    }

    // MARK: Hit testing and taps

    private func outlineContains(_ pointInBand: CGPoint) -> Bool {
        guard let presentedFrame, let shape = surfaceStyle?.shape, presentedRect.width > 0, presentedRect.height > 0 else {
            return false
        }
        guard presentedRect.contains(pointInBand) else { return false }
        guard let path = NotchMorphGeometry.path(shape, values: presentedFrame.values, in: presentedRect) else { return false }
        return path.contains(pointInBand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit, hit !== self { return hit }
        guard onTap != nil, bounds.contains(convert(point, from: superview)) else { return nil }
        let inBand = band.convert(point, from: superview)
        return outlineContains(inBand) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let inBand = band.convert(event.locationInWindow, from: nil)
        isTapCandidate = outlineContains(inBand)
        #if DEBUG
        NSLog("CLICK-TRACE stage down inBand=%@ presented=%@ candidate=%d", NSStringFromPoint(inBand), NSStringFromRect(presentedRect), isTapCandidate ? 1 : 0)
        #endif
    }

    override func mouseDragged(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard isTapCandidate else { return }
        isTapCandidate = false
        let inBand = band.convert(event.locationInWindow, from: nil)
        #if DEBUG
        NSLog("CLICK-TRACE stage up inBand=%@ contains=%d", NSStringFromPoint(inBand), outlineContains(inBand) ? 1 : 0)
        #endif
        guard outlineContains(inBand) else { return }
        onTap?()
    }
}

enum NotchChromeGeometry {
    static func frame(
        anchor: NotchChromePiece.Anchor,
        inset: CGFloat,
        top: CGFloat,
        bottom: CGFloat? = nil,
        size: CGSize,
        outline: CGRect,
        scale: CGFloat
    ) -> CGRect {
        let x: CGFloat
        switch anchor {
        case .leading: x = outline.minX + inset
        case .trailing: x = outline.maxX - inset - size.width
        case .center: x = outline.midX - size.width / 2
        }
        return CGRect(
            x: NotchDisplayMetrics.snapToPixel(x, scale: scale),
            y: NotchDisplayMetrics.snapToPixel(bottom.map { outline.maxY - $0 - size.height } ?? outline.minY + top, scale: scale),
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
final class NotchOutlineFollower {
    struct Effect: Equatable {
        var scale: CGFloat
        var opacity: Float
        var blurRadius: CGFloat

        static let identity = Effect(scale: 1, opacity: 1, blurRadius: 0)
    }

    static let maximumBlurRadius: CGFloat = 30
    static let minimumFollowScale: CGFloat = 0.82
    static let maximumFollowScale: CGFloat = 1.2
    static let minimumCrossFadeSpan: CGFloat = 0.25
    private static let blurFilterName = "followBlur"

    private weak var layer: CALayer?
    private var blurInstalled = false
    private var generation = 0
    private(set) var isDriving = false
    private var drivingSpan: CGFloat = 0

    init(layer: CALayer?) {
        self.layer = layer
    }

    static func scale(outline: CGSize, layout: CGSize) -> CGFloat {
        guard layout.width > 1, layout.height > 1 else { return 1 }
        return max(0.01, outline.width / layout.width)
    }

    static func blurLimit(forHeight height: CGFloat) -> CGFloat {
        min(maximumBlurRadius, max(9, height * 0.28))
    }

    static func effect(scale: CGFloat, span: CGFloat, ridesOvershoot: Bool, blurLimit: CGFloat = maximumBlurRadius) -> Effect {
        let distance = abs(log(max(scale, 0.001)))
        let presence = 1 - min(1, distance / max(span, 0.05))
        let opacity = smoothstep(0.2, 0.7, presence)
        let blur = blurLimit * (1 - smoothstep(0.55, 0.985, presence))
        var shown = scale
        if shown > 1, !ridesOvershoot { shown = 1 + (shown - 1) * 0.5 }
        shown = min(max(shown, minimumFollowScale), maximumFollowScale)
        return Effect(scale: shown, opacity: Float(opacity), blurRadius: blur)
    }

    func animate(
        _ timeline: NotchMorphTimeline,
        outlines: [CGSize],
        layoutSize: CGSize,
        scalesContent: Bool = true,
        blurHeight: CGFloat? = nil,
        crossFadeSpan: CGFloat? = nil
    ) {
        guard let layer, outlines.count == timeline.frames.count, outlines.count > 1,
              layoutSize.width > 1, layoutSize.height > 1 else { return }
        let scales = outlines.map { Self.scale(outline: $0, layout: layoutSize) }
        let first = scales[0]
        let last = scales[scales.count - 1]
        var span = max(abs(log(first)), abs(log(last)), crossFadeSpan ?? 0)
        if isDriving { span = max(span, drivingSpan) }
        guard span >= Self.minimumCrossFadeSpan else {
            reset()
            return
        }
        let leaving = abs(log(first)) < abs(log(last))
        let limit = Self.blurLimit(forHeight: blurHeight ?? layoutSize.height)
        let effects = scales.map { Self.effect(scale: $0, span: span, ridesOvershoot: leaving, blurLimit: limit) }
        drivingSpan = span
        let bounds = layer.bounds
        let flipped = layer.contentsAreFlipped()
        let anchor = layer.anchorPoint
        play(
            timeline,
            transforms: scalesContent
                ? effects.map { Self.topCentredScale($0.scale, bounds: bounds, anchor: anchor, flipped: flipped) }
                : nil,
            opacities: effects.map(\.opacity),
            blurs: effects.map(\.blurRadius)
        )
    }

    func play(_ timeline: NotchMorphTimeline, transforms: [CATransform3D]?, opacities: [Float], blurs: [CGFloat]) {
        guard let layer, opacities.count == timeline.frames.count, blurs.count == timeline.frames.count else { return }
        var opacities = opacities
        var blurs = blurs
        let leaving = (opacities.first ?? 0) > 0.99 && (opacities.last ?? 1) < 0.01
        if leaving, let peak = blurs.max(), peak > 0.05 {
            let step = NotchMorphTimeline.step
            for i in opacities.indices {
                let t = Double(i) * step
                let hold = 1 - Self.smoothstep(Self.leaveFadeStart, Self.leaveFadeEnd, t)
                opacities[i] = max(opacities[i], Float(hold))
                blurs[i] = max(blurs[i], peak * Self.smoothstep(0, Self.leaveBlurRamp, t))
            }
        }
        generation += 1
        isDriving = true
        let needsBlur = blurs.contains { $0 > 0.05 }
        if needsBlur { installBlur(on: layer) }
        let finalBlur = blurs.last ?? 0

        if let transforms, transforms.count == timeline.frames.count, let last = transforms.last {
            layer.sublayerTransform = last
            layer.add(timeline.animation(
                "sublayerTransform", values: transforms.map { NSValue(caTransform3D: $0) }, on: layer
            ), forKey: "follow.transform")
        }
        layer.opacity = opacities.last ?? 1
        layer.add(timeline.animation("opacity", values: opacities.map { NSNumber(value: $0) }, on: layer), forKey: "follow.opacity")
        var blurEnd = timeline.end
        if needsBlur {
            let keyPath = "filters.\(Self.blurFilterName).inputRadius"
            layer.setValue(finalBlur, forKeyPath: keyPath)
            let arriving = (opacities.first ?? 1) < 0.5 && (opacities.last ?? 0) > 0.99
            if arriving, let peak = blurs.max() {
                let tail = Self.focusPull(blurs, peak: peak)
                let animation = CAKeyframeAnimation(keyPath: keyPath)
                animation.values = tail.map { NSNumber(value: Double($0)) }
                animation.calculationMode = .linear
                animation.duration = NotchMorphTimeline.step * Double(max(1, tail.count - 1))
                animation.beginTime = layer.convertTime(timeline.begin, from: nil)
                animation.fillMode = .backwards
                layer.add(animation, forKey: "follow.blur")
                blurEnd = timeline.begin + animation.duration
            } else {
                layer.add(timeline.animation(keyPath, values: blurs.map { NSNumber(value: Double($0)) }, on: layer), forKey: "follow.blur")
            }
        }

        let generation = generation
        let settle = max(timeline.end, blurEnd)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, settle - CACurrentMediaTime()) + 0.05) { [weak self] in
            guard let self, self.generation == generation, let layer = self.layer else { return }
            self.isDriving = false
            guard finalBlur < 0.05, self.blurInstalled else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.filters = nil
            self.blurInstalled = false
            CATransaction.commit()
        }
    }

    static let leaveBlurRamp: CFTimeInterval = 0.1
    static let leaveFadeStart: CFTimeInterval = 0.06
    static let leaveFadeEnd: CFTimeInterval = 0.24

    static let focusPullDelay: CFTimeInterval = 0.03
    static let focusPullDuration: CFTimeInterval = 0.28

    static func focusPull(_ blurs: [CGFloat], peak: CGFloat) -> [CGFloat] {
        let step = NotchMorphTimeline.step
        let count = max(blurs.count, Int(ceil((focusPullDelay + focusPullDuration) / step)) + 1)
        return (0..<count).map { i in
            let t = Double(i) * step
            let progress = min(1, max(0, (t - focusPullDelay) / focusPullDuration))
            let eased = 1 - pow(1 - progress, 3)
            let pull = peak * CGFloat(1 - eased)
            let follow = i < blurs.count ? blurs[i] : 0
            return max(pull, follow)
        }
    }

    static func mapping(scale: CGFloat, from: CGPoint, to: CGPoint, bounds: CGRect, anchor: CGPoint, flipped: Bool) -> CATransform3D {
        func anchored(_ point: CGPoint) -> CGPoint {
            let y = flipped ? point.y : bounds.height - point.y
            return CGPoint(x: point.x - bounds.width * anchor.x, y: y - bounds.height * anchor.y)
        }
        let source = anchored(from)
        let target = anchored(to)
        let transform = CATransform3DMakeTranslation(target.x - source.x * scale, target.y - source.y * scale, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    func hideUntilDriven(timeout: TimeInterval = 0.12) {
        guard let layer else { return }
        generation += 1
        let generation = generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.generation == generation, !self.isDriving else { return }
            self.reset()
        }
    }

    func reset() {
        generation += 1
        isDriving = false
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "follow.transform")
        layer.removeAnimation(forKey: "follow.opacity")
        layer.removeAnimation(forKey: "follow.blur")
        layer.sublayerTransform = CATransform3DIdentity
        layer.opacity = 1
        if blurInstalled {
            layer.filters = nil
            blurInstalled = false
        }
        CATransaction.commit()
    }

    private func installBlur(on layer: CALayer) {
        guard !blurInstalled, let filter = Self.makeBlurFilter() else { return }
        layer.filters = [filter]
        blurInstalled = true
    }

    private static func makeBlurFilter() -> NSObject? {
        if let cls = NSClassFromString("CAFilter") as? NSObject.Type,
           let filter = cls.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?.takeUnretainedValue() as? NSObject {
            filter.setValue(blurFilterName, forKey: "name")
            filter.setValue(0, forKey: "inputRadius")
            return filter
        }
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.name = blurFilterName
        blur.setValue(0, forKey: kCIInputRadiusKey)
        return blur
    }

    static func topCentredScale(_ scale: CGFloat, bounds: CGRect, anchor: CGPoint, flipped: Bool) -> CATransform3D {
        guard abs(scale - 1) > 1e-4 else { return CATransform3DIdentity }
        let pivotX = bounds.midX - bounds.width * anchor.x
        let topY = (flipped ? bounds.minY : bounds.maxY) - bounds.height * anchor.y
        var transform = CATransform3DMakeTranslation(pivotX, topY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -pivotX, -topY, 0)
    }

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}