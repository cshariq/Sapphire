//
//  NotchHostedContentView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-11
//

import AppKit
import SwiftUI

struct NotchContentEffect: Equatable {
    var opacity: Double = 1
    var blurRadius: CGFloat = 0
    var scale: CGFloat = 1

    static let identity = NotchContentEffect()
}

struct NotchHostEnvironment: ViewModifier {
    let bandHeight: CGFloat
    let displayScale: CGFloat

    func body(content: Content) -> some View {
        content
            .environment(\.notchBandHeight, bandHeight)
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
            .environment(\.displayScale, displayScale)
            .environment(\.appearsActive, true)
            .environment(\.controlActiveState, .key)
    }
}

extension View {
    func notchHostEnvironment(bandHeight: CGFloat, displayScale: CGFloat) -> some View {
        modifier(NotchHostEnvironment(bandHeight: bandHeight, displayScale: displayScale))
    }
}

final class NotchGatedHostingView: NSHostingView<AnyView>, PointerTrackingGated {
    private lazy var trackingGate = PointerTrackingGate(view: self)
    var onIntrinsicSizeChange: (() -> Void)?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        (window as? DynamicFocusWindow)?.unregisterPointerTrackingClient(self)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window as? DynamicFocusWindow {
            window.registerPointerTrackingClient(self)
        } else {
            setPointerTrackingEnabled(true)
        }
    }

    override func addTrackingArea(_ trackingArea: NSTrackingArea) {
        guard trackingGate.shouldInstall(trackingArea) else { return }
        super.addTrackingArea(trackingArea)
    }

    override func removeTrackingArea(_ trackingArea: NSTrackingArea) {
        trackingGate.didRemove(trackingArea)
        super.removeTrackingArea(trackingArea)
    }

    func setPointerTrackingEnabled(_ enabled: Bool) {
        windowAllowsTracking = enabled
        applyTracking()
    }

    func setTrackingSuppressed(_ suppressed: Bool) {
        guard suppressed != trackingSuppressed else { return }
        trackingSuppressed = suppressed
        applyTracking()
    }

    private var windowAllowsTracking = true
    private var trackingSuppressed = false

    private func applyTracking() {
        trackingGate.setOpen(windowAllowsTracking && !trackingSuppressed) { super.addTrackingArea($0) }
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var safeAreaRect: NSRect { bounds }
}

@MainActor
final class NotchHostedContentView: NSView {
    enum Sizing {
        case fixed
        case fitting
    }

    let hosting: NotchGatedHostingView
    let followView = NotchPassthroughView()
    let transitionView = NotchPassthroughView()
    private(set) lazy var follower = NotchOutlineFollower(layer: followView.layer)
    let sizing: Sizing
    private(set) var effect = NotchContentEffect.identity
    private(set) var isPresented = true
    var contentKey: NotchContentKey?
    private var hitTestable = true
    private var blurFilterInstalled = false
    private var blurRemovalGeneration = 0
    private var removalGeneration = 0
    var onFittingSizeChange: (() -> Void)?

    private static let blurFilterName = "notchContentBlur"

    init(rootView: AnyView, sizing: Sizing) {
        self.sizing = sizing
        hosting = NotchGatedHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = false
        layer?.actions = NotchLayerSurfaceView.noActions
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        if sizing == .fitting {
            hosting.sizingOptions = [.intrinsicContentSize]
            hosting.onIntrinsicSizeChange = { [weak self] in self?.fittingSizeDidChange() }
        }
        followView.wantsLayer = true
        followView.layerUsesCoreImageFilters = true
        followView.layer?.actions = NotchLayerSurfaceView.noActions
        followView.autoresizingMask = [.width, .height]
        followView.frame = bounds
        addSubview(followView)
        transitionView.wantsLayer = true
        transitionView.layerUsesCoreImageFilters = true
        transitionView.layer?.actions = NotchLayerSurfaceView.noActions
        transitionView.autoresizingMask = [.width, .height]
        transitionView.frame = followView.bounds
        followView.addSubview(transitionView)
        hosting.frame = transitionView.bounds
        transitionView.addSubview(hosting)
        applyFittingSizeIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func invalidateIntrinsicContentSize() {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestable, isPresented else { return nil }
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    func setHitTestable(_ enabled: Bool) {
        hitTestable = enabled
        hosting.setTrackingSuppressed(!enabled || !isPresented)
    }

    func setRootView(_ view: AnyView, key: NotchContentKey? = nil) {
        if let key, key == contentKey { return }
        contentKey = key
        hosting.rootView = view
        applyFittingSizeIfNeeded()
    }

    func park(keepingContent: Bool = false) {
        isHidden = true
        isPresented = false
        if !keepingContent {
            contentKey = nil
            hosting.rootView = AnyView(EmptyView())
        }
        hosting.setTrackingSuppressed(true)
        follower.reset()
        if let layer {
            layer.removeAllAnimations()
            layer.opacity = Float(max(0, min(1, effect.opacity)))
        }
    }

    // MARK: Motion

    func presentOrigin(_ origin: CGPoint) {
        guard let layer, let superlayer = layer.superlayer else {
            setFrameOrigin(origin)
            return
        }
        let rect = CGRect(origin: origin, size: frame.size)
        layer.position = NotchLayerGeometry.position(
            for: rect,
            anchor: layer.anchorPoint,
            topDown: superlayer.contentsAreFlipped(),
            superHeight: superlayer.bounds.height
        )
    }

    func settle(at origin: CGPoint) {
        if frame.origin != origin { setFrameOrigin(origin) }
        presentOrigin(origin)
    }

    // MARK: Size

    var preferredContentSize: CGSize {
        let size = hosting.intrinsicContentSize
        var fitting: CGSize?
        func fitted() -> CGSize {
            if let fitting { return fitting }
            let measured = hosting.fittingSize
            fitting = measured
            return measured
        }
        let width = size.width == NSView.noIntrinsicMetric ? fitted().width : size.width
        let height = size.height == NSView.noIntrinsicMetric ? fitted().height : size.height
        return CGSize(width: max(0, ceil(width)), height: max(0, ceil(height)))
    }

    private func applyFittingSizeIfNeeded() {
        guard sizing == .fitting else { return }
        let size = preferredContentSize
        guard size != frame.size else { return }
        setFrameSize(size)
        followView.frame = bounds
        transitionView.frame = followView.bounds
        hosting.frame = transitionView.bounds
    }

    private var pendingFittingSizeCheck = false

    private func fittingSizeDidChange() {
        guard sizing == .fitting, !pendingFittingSizeCheck else { return }
        pendingFittingSizeCheck = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingFittingSizeCheck = false
            let before = self.frame.size
            self.applyFittingSizeIfNeeded()
            if before != self.frame.size { self.onFittingSizeChange?() }
        }
    }

    // MARK: Effects

    func apply(opacity: Double, animation: Animation?) {
        guard let layer else { return }
        effect.opacity = opacity
        let value = Float(max(0, min(1, opacity)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NotchLayerScalarAnimation.set(layer, "opacity", to: value, equals: { ($0 as? Float) == value }, animation: animation)
        CATransaction.commit()
    }

    func apply(scale: CGFloat, animation: Animation?) {
        guard let layer else { return }
        effect.scale = scale
        let transform = NSValue(caTransform3D: Self.scaleTransform(scale, in: layer.bounds))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NotchLayerScalarAnimation.set(
            layer,
            "sublayerTransform",
            to: transform,
            equals: { ($0 as? NSValue).map { CATransform3DEqualToTransform($0.caTransform3DValue, transform.caTransform3DValue) } ?? false },
            animation: animation
        )
        CATransaction.commit()
    }

    func apply(blurRadius: CGFloat, animation: Animation?) {
        guard let layer else { return }
        let previous = max(0, effect.blurRadius)
        effect.blurRadius = blurRadius
        let radius = max(0, blurRadius)
        blurRemovalGeneration += 1
        let generation = blurRemovalGeneration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard radius > 0 || blurFilterInstalled else { return }
        if !blurFilterInstalled {
            guard let blur = Self.makeBlurFilter() else { return }
            layer.filters = [blur]
            blurFilterInstalled = true
        }
        let keyPath = "filters.\(Self.blurFilterName).inputRadius"
        let presented = (layer.presentation()?.value(forKeyPath: keyPath) as? NSNumber)?.doubleValue
        let from = CGFloat(presented ?? Double(previous))
        layer.setValue(radius, forKeyPath: keyPath)
        var duration: CFTimeInterval = 0
        if let animation, abs(from - radius) > 1e-6 {
            let made = NotchLayerScalarAnimation.make(keyPath: keyPath, from: from, to: radius, curve: animation.notchMorphCurve ?? .fallback)
            layer.add(made, forKey: keyPath)
            duration = made.duration
        } else {
            layer.removeAnimation(forKey: keyPath)
        }
        if radius == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
                guard let self, self.blurRemovalGeneration == generation, self.effect.blurRadius == 0 else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.layer?.filters = nil
                self.blurFilterInstalled = false
                CATransaction.commit()
            }
        }
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

    func apply(_ effect: NotchContentEffect, animation: Animation?) {
        if effect.opacity != self.effect.opacity { apply(opacity: effect.opacity, animation: animation) }
        if effect.scale != self.effect.scale { apply(scale: effect.scale, animation: animation) }
        if effect.blurRadius != self.effect.blurRadius { apply(blurRadius: effect.blurRadius, animation: animation) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed, effect.scale != 1, let layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.sublayerTransform = Self.scaleTransform(effect.scale, in: layer.bounds)
            CATransaction.commit()
        }
    }

    static func scaleTransform(_ scale: CGFloat, in bounds: CGRect) -> CATransform3D {
        guard scale != 1 else { return CATransform3DIdentity }
        var transform = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -bounds.midX, -bounds.midY, 0)
    }

    // MARK: Presentation

    func present(fadeDuration: CFTimeInterval, curve: NotchMorphTiming) {
        follower.reset()
        removalGeneration += 1
        isPresented = true
        isHidden = false
        hosting.setTrackingSuppressed(!hitTestable)
        guard let layer else { return }
        layer.isHidden = false
        let target = Float(max(0, min(1, effect.opacity)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "notchDismiss")
        layer.opacity = target
        guard fadeDuration > 0 else {
            CATransaction.commit()
            return
        }
        let fade = NotchLayerScalarAnimation.make(
            keyPath: "opacity", from: Float(0), to: target, curve: .timing(curve, duration: fadeDuration)
        )
        layer.add(fade, forKey: "notchPresent")
        CATransaction.commit()
    }

    func dismiss(fadeDuration: CFTimeInterval, curve: NotchMorphTiming, completion: @escaping () -> Void) {
        guard isPresented else { return }
        isPresented = false
        removalGeneration += 1
        let generation = removalGeneration
        guard let layer, fadeDuration > 0 else {
            completion()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let from = (layer.presentation() ?? layer).opacity
        layer.removeAnimation(forKey: "notchPresent")
        layer.opacity = 0
        let fade = NotchLayerScalarAnimation.make(
            keyPath: "opacity", from: from, to: Float(0), curve: .timing(curve, duration: fadeDuration)
        )
        layer.add(fade, forKey: "notchDismiss")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration + 0.02) { [weak self] in
            guard let self, self.removalGeneration == generation, !self.isPresented else { return }
            completion()
        }
    }
}

enum NotchLayerGeometry {
    static func position(for rect: CGRect, anchor: CGPoint, topDown: Bool, superHeight: CGFloat) -> CGPoint {
        let x = rect.minX + rect.width * anchor.x
        if topDown {
            return CGPoint(x: x, y: rect.minY + rect.height * anchor.y)
        }
        return CGPoint(x: x, y: superHeight - rect.maxY + rect.height * anchor.y)
    }
}