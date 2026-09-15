//
//  LiquidGlassView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import ObjectiveC
import SwiftUI
import Darwin

// MARK: - Materials (qt-liquid-glass mapping)

enum LiquidGlassMaterial: String, CaseIterable, Identifiable, Hashable {
    case sidebar
    case sheet
    case hud
    case windowBackground
    case popover
    case menu
    case fullscreenUI
    case controlCenter
    case widgets
    case inspector
    case titlebar
    case tooltip
    case frosted
    case clearGlass
    case chromatic

    var id: String { rawValue }

    var variant: Int {
        switch self {
        case .sidebar: return 16
        case .sheet: return 0
        case .hud: return 2
        case .windowBackground: return 1
        case .popover: return 23
        case .menu: return 9
        case .fullscreenUI: return 6
        case .controlCenter: return 8
        case .widgets: return 4
        case .inspector: return 18
        case .titlebar: return 17
        case .tooltip: return 20
        case .frosted: return 11
        case .clearGlass: return 13
        case .chromatic: return 19
        }
    }

    var publicStyle: Int? {
        switch self {
        case .clearGlass, .windowBackground: return 1
        case .sheet, .sidebar, .hud, .popover, .menu, .frosted, .widgets: return 0
        default: return nil
        }
    }

    var fallbackMaterial: NSVisualEffectView.Material {
        switch self {
        case .sidebar, .inspector: return .sidebar
        case .sheet: return .sheet
        case .hud: return .hudWindow
        case .windowBackground: return .underWindowBackground
        case .popover: return .popover
        case .menu, .controlCenter: return .menu
        case .fullscreenUI: return .fullScreenUI
        case .widgets: return .contentBackground
        case .titlebar: return .titlebar
        case .tooltip: return .toolTip
        case .frosted, .clearGlass, .chromatic: return .hudWindow
        }
    }

    static func forIntensity(_ intensity: Double) -> LiquidGlassMaterial {
        switch intensity {
        case ..<0.25: return .clearGlass
        case ..<0.45: return .windowBackground
        case ..<0.7: return .frosted
        case ..<0.85: return .widgets
        default: return .hud
        }
    }
}

enum LiquidGlassBlendingMode: Int, Hashable {
    case behindWindow = 0
    case withinWindow = 1
}

enum LiquidGlassAppearance: Int, Hashable {
    case light = 0
    case dark = 1
    case auto = 2
}

enum LiquidGlassInteraction: Int, Hashable {
    case normal = 0
    case hovered = 1
}

enum LiquidGlassBackend: Hashable {
    case automatic
    case visualEffect
}

struct LiquidGlassShadow: Equatable {
    var color: NSColor = .clear
    var opacity: CGFloat = 0
    var radius: CGFloat = 0
    var offset: CGSize = .zero

    static let none = LiquidGlassShadow()
}

struct LiquidGlassIntensityParams: Equatable {
    var material: LiquidGlassMaterial
    var tintAlpha: CGFloat
    var contentLensing: Int
    var subdued: Int
    var scrim: Int

    static func resolve(_ intensity: Double) -> LiquidGlassIntensityParams {
        let t = max(0, min(1, intensity))
        return LiquidGlassIntensityParams(
            material: .forIntensity(t),
            tintAlpha: CGFloat(0.04 + t * 0.22),
            contentLensing: t < 0.35 ? 0 : 1,
            subdued: t < 0.4 ? 1 : 0,
            scrim: t > 0.85 ? 1 : 0
        )
    }
}

// MARK: - Runtime

private enum GlassRuntime {
    static var isSystemGlassAvailable: Bool {
        NSClassFromString("NSGlassEffectView") != nil
    }

    private static let sendInt64: @convention(c) (AnyObject, Selector, Int64) -> Void = {
        let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")!
        return unsafeBitCast(sym, to: (@convention(c) (AnyObject, Selector, Int64) -> Void).self)
    }()

    private static let sendDouble: @convention(c) (AnyObject, Selector, Double) -> Void = {
        let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")!
        return unsafeBitCast(sym, to: (@convention(c) (AnyObject, Selector, Double) -> Void).self)
    }()

    private static let sendPath: @convention(c) (AnyObject, Selector, CGPath?) -> Void = {
        let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")!
        return unsafeBitCast(sym, to: (@convention(c) (AnyObject, Selector, CGPath?) -> Void).self)
    }()

    private static let customPathSelector = NSSelectorFromString("_setPath:")

    static func supportsCustomPath(_ view: NSView) -> Bool {
        !(view is NSVisualEffectView) && view.responds(to: customPathSelector)
    }

    static func setCustomPath(_ view: NSView, _ path: CGPath?) {
        guard view.responds(to: customPathSelector) else { return }
        sendPath(view, customPathSelector, path)
    }

    static func makeEffectView(frame: NSRect, backend: LiquidGlassBackend) -> NSView {
        if backend == .automatic,
           let cls = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let view = cls.init(frame: frame)
            view.autoresizingMask = [.width, .height]
            return view
        }
        let visual = NSVisualEffectView(frame: frame)
        visual.blendingMode = .behindWindow
        visual.material = .hudWindow
        visual.state = .active
        visual.autoresizingMask = [.width, .height]
        return visual
    }

    private static func setLongLong(_ view: NSView, selectorName: String, value: Int64) {
        let sel = NSSelectorFromString(selectorName)
        guard view.responds(to: sel) else { return }
        sendInt64(view, sel, value)
    }

    private static func setDouble(_ view: NSView, selectorName: String, value: Double) {
        let sel = NSSelectorFromString(selectorName)
        guard view.responds(to: sel) else { return }
        sendDouble(view, sel, value)
    }

    static func apply(
        to view: NSView,
        material: LiquidGlassMaterial,
        cornerRadius: CGFloat,
        tintColor: NSColor?,
        blendingMode: LiquidGlassBlendingMode,
        appearance: LiquidGlassAppearance,
        interaction: LiquidGlassInteraction,
        contentLensing: Int?,
        scrim: Int?,
        subdued: Int?
    ) {
        if let visual = view as? NSVisualEffectView {
            visual.material = material.fallbackMaterial
            visual.blendingMode = blendingMode == .withinWindow ? .withinWindow : .behindWindow
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerRadius = max(0, cornerRadius)
            visual.layer?.masksToBounds = cornerRadius > 0
            visual.layer?.isOpaque = false
            visual.layer?.backgroundColor = tintColor?.cgColor
            applyAppearance(view, appearance)
            return
        }

        if let style = material.publicStyle {
            setLongLong(view, selectorName: "setStyle:", value: Int64(style))
        }
        setLongLong(view, selectorName: "set_variant:", value: Int64(material.variant))

        setLongLong(view, selectorName: "setBlendingMode:", value: Int64(blendingMode.rawValue))
        setLongLong(view, selectorName: "set_interactionState:", value: Int64(max(0, min(1, interaction.rawValue))))
        setLongLong(view, selectorName: "set_adaptiveAppearance:", value: Int64(appearance.rawValue))

        if let contentLensing {
            setLongLong(view, selectorName: "set_contentLensing:", value: Int64(contentLensing))
        }
        if let scrim {
            setLongLong(view, selectorName: "set_scrimState:", value: Int64(scrim))
        }
        if let subdued {
            setLongLong(view, selectorName: "set_subduedState:", value: Int64(subdued))
        }

        if cornerRadius > 0 {
            setDouble(view, selectorName: "setCornerRadius:", value: Double(cornerRadius))
        } else {
            setDouble(view, selectorName: "setCornerRadius:", value: 0)
        }

        let tintSel = NSSelectorFromString("setTintColor:")
        if view.responds(to: tintSel) {
            view.perform(tintSel, with: tintColor)
        }

        applyAppearance(view, appearance)
    }

    private static let aquaAppearance = NSAppearance(named: .aqua)
    private static let darkAquaAppearance = NSAppearance(named: .darkAqua)

    private static func applyAppearance(_ view: NSView, _ appearance: LiquidGlassAppearance) {
        let target: NSAppearance?
        switch appearance {
        case .light: target = aquaAppearance
        case .dark: target = darkAquaAppearance
        case .auto: target = nil
        }
        if view.appearance !== target { view.appearance = target }
    }

    static func prepareWindowForBehindGlass(_ window: NSWindow?) {
        guard let window else { return }
        if window.isOpaque { window.isOpaque = false }
        if window.backgroundColor != .clear { window.backgroundColor = .clear }
        guard let content = window.contentView else { return }
        if !content.wantsLayer { content.wantsLayer = true }
        guard let layer = content.layer else { return }
        if layer.isOpaque { layer.isOpaque = false }
        let clear = NSColor.clear.cgColor
        if layer.backgroundColor != clear { layer.backgroundColor = clear }
    }
}

// MARK: - Host NSView

final class LiquidGlassHostView: NSView {
    private struct AppliedConfiguration: Equatable {
        var material: LiquidGlassMaterial
        var cornerRadius: CGFloat
        var tintColor: NSColor?
        var blendingMode: LiquidGlassBlendingMode
        var appearance: LiquidGlassAppearance
        var interaction: LiquidGlassInteraction
        var contentLensing: Int?
        var scrim: Int?
        var subdued: Int?
    }

    private var backend: LiquidGlassBackend
    private var effectView: NSView?
    private var supportsCustomPath = false
    private var currentBlendingMode: LiquidGlassBlendingMode = .behindWindow
    private var appliedConfiguration: AppliedConfiguration?

    private var shapePath: CGPath?
    private var nativeShapePath: CGPath?
    private var appliedShapePath: CGPath?
    private var shapePathProvider: ((CGRect) -> CGPath?)?
    private var shapePathCacheKey: AnyHashable?
    private var shapePathBounds: CGRect = .null
    private var nativeShapeBounds: CGRect = .null
    private var shapeNeedsUpdate = true

    private var fallbackMaskLayer: CAShapeLayer?

    private var requestedShadow: LiquidGlassShadow = .none
    private var appliedShadow: LiquidGlassShadow?
    private var appliedShadowPath: CGPath?

    init(frame frameRect: NSRect, backend: LiquidGlassBackend) {
        self.backend = backend
        super.init(frame: frameRect)
        rebuildEffectView()
    }

    override init(frame frameRect: NSRect) {
        self.backend = .automatic
        super.init(frame: frameRect)
        rebuildEffectView()
    }

    required init?(coder: NSCoder) {
        self.backend = .automatic
        super.init(coder: coder)
        rebuildEffectView()
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard Self.isValid(bounds) else { return }
        if effectView?.frame != bounds { effectView?.frame = bounds }
        applyShapeIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if currentBlendingMode == .behindWindow {
            GlassRuntime.prepareWindowForBehindGlass(window)
        }
    }

    func setBackend(_ backend: LiquidGlassBackend) {
        guard self.backend != backend else { return }
        self.backend = backend
        rebuildEffectView()
    }

    func setShapePath(_ path: CGPath?) {
        shapePathProvider = nil
        shapePathCacheKey = nil
        shapePathBounds = .null
        let validatedPath = Self.validated(path)
        guard validatedPath != shapePath else {
            if nativeShapeBounds != bounds { applyShapeIfNeeded() }
            return
        }
        shapePath = validatedPath
        shapeNeedsUpdate = true
        applyShapeIfNeeded()
    }

    func setShapePathProvider(
        _ provider: ((CGRect) -> CGPath?)?,
        cacheKey: AnyHashable? = nil
    ) {
        if let cacheKey,
           shapePathProvider != nil,
           shapePathCacheKey == cacheKey {
            if shapePathBounds != bounds { applyShapeIfNeeded() }
            return
        }

        shapePathProvider = provider
        shapePathCacheKey = cacheKey
        shapePathBounds = .null
        shapeNeedsUpdate = true
        if provider == nil { shapePath = nil }
        applyShapeIfNeeded()
    }

    func setShadow(_ shadow: LiquidGlassShadow) {
        requestedShadow = shadow
        applyShadowIfNeeded()
    }

    func configure(
        material: LiquidGlassMaterial,
        cornerRadius: CGFloat,
        tintColor: NSColor?,
        blendingMode: LiquidGlassBlendingMode,
        appearance: LiquidGlassAppearance,
        interaction: LiquidGlassInteraction,
        contentLensing: Int?,
        scrim: Int?,
        subdued: Int?
    ) {
        currentBlendingMode = blendingMode
        if effectView == nil { rebuildEffectView() }
        guard let effectView else { return }

        let requested = AppliedConfiguration(
            material: material,
            cornerRadius: cornerRadius,
            tintColor: tintColor,
            blendingMode: blendingMode,
            appearance: appearance,
            interaction: interaction,
            contentLensing: contentLensing,
            scrim: scrim,
            subdued: subdued
        )
        guard requested != appliedConfiguration else {
            applyShapeIfNeeded()
            return
        }
        appliedConfiguration = requested

        GlassRuntime.apply(
            to: effectView,
            material: material,
            cornerRadius: cornerRadius,
            tintColor: tintColor,
            blendingMode: blendingMode,
            appearance: appearance,
            interaction: interaction,
            contentLensing: contentLensing,
            scrim: scrim,
            subdued: subdued
        )

        if blendingMode == .behindWindow {
            GlassRuntime.prepareWindowForBehindGlass(window)
        }
        applyShapeIfNeeded()
    }

    private func rebuildEffectView() {
        effectView?.removeFromSuperview()
        appliedConfiguration = nil
        appliedShapePath = nil
        nativeShapePath = nil
        nativeShapeBounds = .null
        shapeNeedsUpdate = true
        appliedShadow = nil
        appliedShadowPath = nil

        let glass = GlassRuntime.makeEffectView(frame: bounds, backend: backend)
        supportsCustomPath = GlassRuntime.supportsCustomPath(glass)
        glass.wantsLayer = true
        glass.layer?.isOpaque = false
        glass.layer?.masksToBounds = false
        addSubview(glass, positioned: .below, relativeTo: nil)
        effectView = glass
        applyShapeIfNeeded()
    }

    private func applyShapeIfNeeded() {
        let bounds = self.bounds
        guard Self.isValid(bounds), !bounds.isEmpty else {
            clearShape()
            return
        }

        if let provider = shapePathProvider, shapePathBounds != bounds {
            shapePathBounds = bounds
            shapePath = Self.validated(provider(bounds))
            shapeNeedsUpdate = true
        }

        guard let sourcePath = shapePath,
              let effectView else {
            clearShape()
            return
        }

        guard shapeNeedsUpdate || nativeShapeBounds != bounds || appliedShapePath == nil else {
            applyShadowIfNeeded()
            return
        }
        guard let path = Self.appKitPath(from: sourcePath, in: bounds) else {
            clearShape()
            return
        }
        nativeShapePath = path
        nativeShapeBounds = bounds
        shapeNeedsUpdate = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if supportsCustomPath {
            if path != appliedShapePath {
                GlassRuntime.setCustomPath(effectView, path)
                appliedShapePath = path
            }
            if effectView.layer?.mask != nil { effectView.layer?.mask = nil }
        } else {
            let mask = fallbackMaskLayer ?? {
                let layer = CAShapeLayer()
                layer.fillColor = NSColor.black.cgColor
                layer.backgroundColor = nil
                fallbackMaskLayer = layer
                return layer
            }()
            if mask.frame != bounds { mask.frame = bounds }
            if mask.path != path { mask.path = path }
            if effectView.layer?.mask !== mask { effectView.layer?.mask = mask }
            appliedShapePath = path
        }

        CATransaction.commit()
        applyShadowIfNeeded()
    }

    private func clearShape() {
        if supportsCustomPath, let effectView, appliedShapePath != nil {
            GlassRuntime.setCustomPath(effectView, nil)
        }
        effectView?.layer?.mask = nil
        nativeShapePath = nil
        nativeShapeBounds = .null
        shapeNeedsUpdate = false
        appliedShapePath = nil
        applyShadowIfNeeded()
    }

    private func applyShadowIfNeeded() {
        guard let layer = effectView?.layer else { return }
        let requestedOpacity = max(0, min(1, requestedShadow.opacity))
        let path = requestedOpacity > 0 ? nativeShapePath : nil
        let opacity = path == nil ? 0 : requestedOpacity
        guard appliedShadow != requestedShadow || appliedShadowPath != path else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowColor = requestedShadow.color.cgColor
        layer.shadowOpacity = Float(opacity)
        layer.shadowRadius = max(0, requestedShadow.radius)
        layer.shadowOffset = CGSize(
            width: requestedShadow.offset.width,
            height: -requestedShadow.offset.height
        )
        layer.shadowPath = path
        CATransaction.commit()

        appliedShadow = requestedShadow
        appliedShadowPath = path
    }

    private static func validated(_ path: CGPath?) -> CGPath? {
        guard let path, !path.isEmpty else { return nil }
        let box = path.boundingBox
        guard isValid(box) else { return nil }
        return path
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }

    private static func appKitPath(from path: CGPath, in bounds: CGRect) -> CGPath? {
        var flip = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: bounds.minX,
            ty: bounds.minY + bounds.maxY
        )
        return path.copy(using: &flip)
    }
}

// MARK: - SwiftUI

struct LiquidGlassView: NSViewRepresentable {
    var backend: LiquidGlassBackend = .automatic
    var material: LiquidGlassMaterial = .frosted
    var cornerRadius: CGFloat = 0
    var tintColor: NSColor? = nil
    var blendingMode: LiquidGlassBlendingMode = .behindWindow
    var appearance: LiquidGlassAppearance = .auto
    var interaction: LiquidGlassInteraction = .normal
    var contentLensing: Int? = 1
    var scrim: Int? = nil
    var subdued: Int? = nil
    var shapePath: CGPath? = nil
    var shapePathProvider: ((CGRect) -> CGPath?)? = nil
    var shapePathCacheKey: AnyHashable? = nil
    var shadow: LiquidGlassShadow = .none

    func makeNSView(context: Context) -> LiquidGlassHostView {
        let view = LiquidGlassHostView(frame: .zero, backend: backend)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: LiquidGlassHostView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: LiquidGlassHostView) {
        view.setBackend(backend)
        if let shapePathProvider {
            view.setShapePathProvider(shapePathProvider, cacheKey: shapePathCacheKey)
        } else {
            view.setShapePath(shapePath)
        }
        view.configure(
            material: material,
            cornerRadius: cornerRadius,
            tintColor: tintColor,
            blendingMode: blendingMode,
            appearance: appearance,
            interaction: interaction,
            contentLensing: contentLensing,
            scrim: scrim,
            subdued: subdued
        )
        view.setShadow(shadow)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LiquidGlassHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 10, height: proposal.height ?? 10)
    }

    static var isSystemGlassAvailable: Bool { GlassRuntime.isSystemGlassAvailable }
}

struct LiquidGlassShapeView<S: Shape & Hashable>: View, Animatable {
    var backend: LiquidGlassBackend = .automatic
    var material: LiquidGlassMaterial = .frosted
    var shape: S
    var tintColor: NSColor? = nil
    var blendingMode: LiquidGlassBlendingMode = .behindWindow
    var appearance: LiquidGlassAppearance = .auto
    var interaction: LiquidGlassInteraction = .normal
    var contentLensing: Int? = 1
    var scrim: Int? = nil
    var subdued: Int? = nil
    var shadow: LiquidGlassShadow = .none

    var animatableData: AnimatablePair<
        S.AnimatableData,
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    > {
        get {
            AnimatablePair(
                shape.animatableData,
                AnimatablePair(
                    shadow.opacity,
                    AnimatablePair(
                        shadow.radius,
                        AnimatablePair(shadow.offset.width, shadow.offset.height)
                    )
                )
            )
        }
        set {
            shape.animatableData = newValue.first
            shadow.opacity = newValue.second.first
            shadow.radius = newValue.second.second.first
            shadow.offset = CGSize(
                width: newValue.second.second.second.first,
                height: newValue.second.second.second.second
            )
        }
    }

    var body: some View {
        let shape = self.shape
        LiquidGlassView(
            backend: backend,
            material: material,
            cornerRadius: 0,
            tintColor: tintColor,
            blendingMode: blendingMode,
            appearance: appearance,
            interaction: interaction,
            contentLensing: contentLensing,
            scrim: scrim,
            subdued: subdued,
            shapePathProvider: { rect in
                guard rect.width > 0, rect.height > 0,
                      rect.width.isFinite, rect.height.isFinite else { return nil }
                return shape.path(in: CGRect(origin: .zero, size: rect.size)).cgPath
            },
            shapePathCacheKey: AnyHashable(shape),
            shadow: shadow
        )
    }
}

struct LiquidGlassShapeFill<S: Shape>: View {
    var material: LiquidGlassMaterial? = nil
    var shape: S
    var cornerRadius: CGFloat = 0
    var tint: Color? = nil
    var intensity: Double = 0.65
    var blendingMode: LiquidGlassBlendingMode = .behindWindow
    var appearance: LiquidGlassAppearance = .auto
    var interaction: LiquidGlassInteraction = .normal

    var body: some View {
        let params = LiquidGlassIntensityParams.resolve(intensity)
        let resolvedMaterial = material ?? params.material
        let shape = self.shape
        let tintNSColor = resolvedTint(alpha: params.tintAlpha)

        LiquidGlassView(
            material: resolvedMaterial,
            cornerRadius: 0,
            tintColor: tintNSColor,
            blendingMode: blendingMode,
            appearance: appearance,
            interaction: interaction,
            contentLensing: params.contentLensing,
            scrim: params.scrim,
            subdued: params.subdued,
            shapePathProvider: { rect in
                guard rect.width > 0, rect.height > 0,
                      rect.width.isFinite, rect.height.isFinite else { return nil }
                return shape.path(in: CGRect(origin: .zero, size: rect.size)).cgPath
            }
        )
        .allowsHitTesting(false)
    }

    private func resolvedTint(alpha: CGFloat) -> NSColor? {
        if let tint { return NSColor(tint) }
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(alpha * 0.85)
        case .light:
            return NSColor.black.withAlphaComponent(alpha * 0.35)
        case .auto:
            return NSColor.white.withAlphaComponent(alpha)
        }
    }
}