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

    static func makeEffectView(frame: NSRect) -> NSView {
        if let cls = NSClassFromString("NSGlassEffectView") as? NSView.Type {
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
            if cornerRadius > 0 {
                visual.wantsLayer = true
                visual.layer?.cornerRadius = cornerRadius
                visual.layer?.masksToBounds = true
                visual.layer?.isOpaque = false
            }
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

    private static func applyAppearance(_ view: NSView, _ appearance: LiquidGlassAppearance) {
        switch appearance {
        case .light: view.appearance = NSAppearance(named: .aqua)
        case .dark: view.appearance = NSAppearance(named: .darkAqua)
        case .auto: view.appearance = nil
        }
    }

    static func prepareWindowForBehindGlass(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.isOpaque = false
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

// MARK: - Host NSView

final class LiquidGlassHostView: NSView {
    private var effectView: NSView?
    private var currentBlendingMode: LiquidGlassBlendingMode = .behindWindow
    private var maskCGPath: CGPath?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        rebuildEffectView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        rebuildEffectView()
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        effectView?.frame = bounds
        applyPathMaskIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if currentBlendingMode == .behindWindow {
            GlassRuntime.prepareWindowForBehindGlass(window)
        }
    }

    func setMaskPath(_ path: CGPath?) {
        maskCGPath = path
        applyPathMaskIfNeeded()
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
        applyPathMaskIfNeeded()
    }

    private func rebuildEffectView() {
        effectView?.removeFromSuperview()
        let glass = GlassRuntime.makeEffectView(frame: bounds)
        addSubview(glass, positioned: .below, relativeTo: nil)
        effectView = glass
    }

    private func applyPathMaskIfNeeded() {
        guard let path = maskCGPath else {
            layer?.mask = nil
            return
        }

        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        let layerPath = path.copy(using: &flip) ?? path

        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = layerPath
        mask.fillColor = NSColor.black.cgColor
        layer?.mask = mask
        layer?.masksToBounds = true
    }
}

// MARK: - SwiftUI

struct LiquidGlassView: NSViewRepresentable {
    var material: LiquidGlassMaterial = .frosted
    var cornerRadius: CGFloat = 0
    var tintColor: NSColor? = nil
    var blendingMode: LiquidGlassBlendingMode = .behindWindow
    var appearance: LiquidGlassAppearance = .auto
    var interaction: LiquidGlassInteraction = .normal
    var contentLensing: Int? = 1
    var scrim: Int? = nil
    var subdued: Int? = nil
    var maskPath: CGPath? = nil

    func makeNSView(context: Context) -> LiquidGlassHostView {
        let view = LiquidGlassHostView(frame: .zero)
        view.setMaskPath(maskPath)
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
        return view
    }

    func updateNSView(_ nsView: LiquidGlassHostView, context: Context) {
        nsView.setMaskPath(maskPath)
        nsView.configure(
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
    }

    static var isSystemGlassAvailable: Bool { GlassRuntime.isSystemGlassAvailable }
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
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let path = shape.path(in: rect)
            LiquidGlassView(
                material: resolvedMaterial,
                cornerRadius: cornerRadius,
                tintColor: resolvedTint(alpha: params.tintAlpha),
                blendingMode: blendingMode,
                appearance: appearance,
                interaction: interaction,
                contentLensing: params.contentLensing,
                scrim: params.scrim,
                subdued: params.subdued,
                maskPath: path.cgPath
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
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