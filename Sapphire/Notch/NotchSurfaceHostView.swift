//
//  NotchSurfaceHostView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15
//

import AppKit
import SwiftUI

struct NotchSurfaceStyle: Equatable {
    struct Glass: Equatable {
        var backend: LiquidGlassBackend
        var material: LiquidGlassMaterial
        var tintColor: NSColor?
        var blendingMode: LiquidGlassBlendingMode
        var appearance: LiquidGlassAppearance
        var interaction: LiquidGlassInteraction
        var shadow: LiquidGlassShadow
    }

    var shape: CustomNotchShape
    var glass: Glass?
    var fill: NotchLayerFill?
    var fillShadow: NotchLayerSurfaceView.Shadow
    var glows: [NotchLayerSurfaceView.Shadow]
    var animatesShadowOpacity: Bool
    var rim: NSColor? = nil

    struct Inputs {
        var appearance: NotchAppearanceSettings
        var config: ResolvedNotchConfiguration
        var shape: CustomNotchShape
        var notchState: NotchController.NotchState
        var isGeminiActive: Bool
        var isManuallyHidden: Bool
        var surfaceShadowOpacity: Double
        var radialEndRadius: CGFloat
        var systemGlassAvailable: Bool
    }

    #if DEBUG
    static let profilingDisablesGlass = ProcessInfo.processInfo.environment["SAPPHIRE_PROF_NO_GLASS"] != nil
    #else
    static let profilingDisablesGlass = false
    #endif

    static func resolve(_ input: Inputs) -> NotchSurfaceStyle {
        let appearance = input.appearance
        let config = input.config
        let isOpaqueSolid = appearance.backgroundStyle == .solid && appearance.opacity >= 1
        let shadowRadius: CGFloat = input.notchState == .clickExpanded ? config.expandedShadowRadius : 12
        let shadowYOffset: CGFloat = input.notchState == .clickExpanded ? config.expandedShadowOffsetY : 6
        let shadowHidden = input.notchState == .initial || input.isManuallyHidden

        let nativeShadow: LiquidGlassShadow
        if input.isGeminiActive {
            let color = NSColor.systemPurple.blended(withFraction: 0.5, of: .systemIndigo) ?? .systemPurple
            nativeShadow = LiquidGlassShadow(
                color: color,
                opacity: shadowHidden ? 0 : 0.56,
                radius: shadowRadius,
                offset: CGSize(width: 0, height: shadowYOffset)
            )
        } else {
            nativeShadow = LiquidGlassShadow(
                color: NSColor(config.expandedShadowColor),
                opacity: input.surfaceShadowOpacity,
                radius: shadowRadius,
                offset: CGSize(width: 0, height: shadowYOffset)
            )
        }

        let glassTint: NSColor? = appearance.backgroundStyle == .solid && appearance.opacity > 0
            ? NSColor(appearance.solidColor.color).withAlphaComponent(appearance.opacity)
            : nil

        var style = NotchSurfaceStyle(
            shape: input.shape, glass: nil, fill: nil, fillShadow: .none, glows: [],
            animatesShadowOpacity: !input.isGeminiActive
        )

        if input.systemGlassAvailable, !profilingDisablesGlass, appearance.usesLiquidGlass,
           appearance.mode == .liquidGlass || !isOpaqueSolid {
            let isGlassMode = appearance.mode == .liquidGlass
            let options = appearance.liquidGlassOptions
            style.glass = Glass(
                backend: .automatic,
                material: isGlassMode ? options.material : appearance.liquidGlassStyle,
                tintColor: isGlassMode ? options.tintColor : glassTint,
                blendingMode: .behindWindow,
                appearance: isGlassMode ? options.appearance : .dark,
                interaction: isGlassMode ? options.interaction : .normal,
                shadow: nativeShadow
            )
            if isGlassMode {
                style.fill = .solid(NSColor(srgbRed: 8 / 255, green: 5 / 255, blue: 16 / 255, alpha: 24 / 255))
            } else if appearance.backgroundStyle != .solid {
                style.fill = layerFill(for: appearance, radialEndRadius: input.radialEndRadius)
            }
            return style
        }

        if !isOpaqueSolid, appearance.enableTransparencyBlur {
            style.glass = Glass(
                backend: .visualEffect,
                material: .hud,
                tintColor: glassTint,
                blendingMode: .behindWindow,
                appearance: .dark,
                interaction: .normal,
                shadow: nativeShadow
            )
            if appearance.backgroundStyle != .solid {
                style.fill = layerFill(for: appearance, radialEndRadius: input.radialEndRadius)
            }
            return style
        }

        style.fill = layerFill(for: appearance, radialEndRadius: input.radialEndRadius)
        if config.isFloatingIsland, case .solid(let color)? = style.fill, color.alphaComponent >= 1 {
            let lifted = color.usingColorSpace(.sRGB)?.blended(withFraction: 0.06, of: .white) ?? color
            style.fill = .linearGradient(colors: [color, lifted], locations: [0.55, 1], start: .top, end: .bottom)
            style.rim = NSColor.white.withAlphaComponent(0.1)
        }
        if input.isGeminiActive {
            let opacity = shadowHidden ? 0.0 : 0.75
            style.glows = [
                NotchLayerSurfaceView.Shadow(
                    color: NSColor(Color.purple),
                    opacity: opacity * 0.7,
                    radius: shadowRadius,
                    offset: CGSize(width: -2, height: shadowYOffset)
                ),
                NotchLayerSurfaceView.Shadow(
                    color: NSColor(Color.indigo),
                    opacity: opacity * 0.8,
                    radius: shadowRadius,
                    offset: CGSize(width: 2, height: shadowYOffset)
                ),
            ]
        } else {
            style.fillShadow = NotchLayerSurfaceView.Shadow(
                color: NSColor(config.expandedShadowColor),
                opacity: input.surfaceShadowOpacity,
                radius: shadowRadius,
                offset: CGSize(width: 0, height: shadowYOffset)
            )
            if config.restingShadowOpacity > 0, !input.isManuallyHidden {
                style.glows = [
                    NotchLayerSurfaceView.Shadow(
                        color: .black,
                        opacity: config.restingShadowOpacity,
                        radius: config.restingShadowRadius,
                        offset: CGSize(width: 0, height: config.restingShadowOffsetY)
                    ),
                ]
            }
        }
        return style
    }

    static func layerFill(for appearance: NotchAppearanceSettings, radialEndRadius: CGFloat) -> NotchLayerFill {
        let alpha = CGFloat(max(0, min(1, appearance.opacity)))
        switch appearance.backgroundStyle {
        case .solid:
            let solid = NSColor(appearance.solidColor.color)
            return .solid(solid.withAlphaComponent(solid.alphaComponent * alpha))
        case .gradient, .radial:
            var stops = appearance.gradientColors
                .map { (color: NSColor($0.color), location: CGFloat($0.location)) }
                .sorted { $0.location < $1.location }
            if stops.isEmpty { stops = [(color: .black, location: 0)] }
            let colors = stops.map { $0.color.withAlphaComponent($0.color.alphaComponent * alpha) }
            let locations = stops.map(\.location)
            if appearance.backgroundStyle == .radial {
                return .radialGradient(colors: colors, locations: locations, endRadius: max(0, radialEndRadius))
            }
            let angle = appearance.gradientAngle * .pi / 180
            return .linearGradient(
                colors: colors,
                locations: locations,
                start: UnitPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5),
                end: UnitPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
            )
        }
    }
}

@MainActor
final class NotchSurfaceHostView: NSView {
    private var glassView: LiquidGlassHostView?
    private var glassCoordinator: NotchGlassMorphCoordinator?
    private var fillView: NotchLayerSurfaceView?
    private var style: NotchSurfaceStyle?
    private weak var engine: NotchMorphEngine?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ style: NotchSurfaceStyle, engine: NotchMorphEngine, shadowAnimation: Animation?) {
        self.engine = engine
        let previous = self.style
        self.style = style
        guard previous != style || glassView == nil && style.glass != nil || fillView == nil && style.fill != nil else {
            return
        }

        if let glass = style.glass {
            let view: LiquidGlassHostView
            if let existing = glassView, previous?.glass?.backend == glass.backend {
                view = existing
            } else {
                removeGlass()
                view = LiquidGlassHostView(frame: bounds, backend: glass.backend)
                view.autoresizingMask = [.width, .height]
                let coordinator = NotchGlassMorphCoordinator()
                coordinator.attach(to: view)
                addSubview(view, positioned: .below, relativeTo: fillView)
                glassView = view
                glassCoordinator = coordinator
            }
            view.setBackend(glass.backend)
            view.configure(
                material: glass.material,
                cornerRadius: 0,
                tintColor: glass.tintColor,
                blendingMode: glass.blendingMode,
                appearance: glass.appearance,
                interaction: glass.interaction,
                contentLensing: nil,
                scrim: nil,
                subdued: nil
            )
            view.setShadow(glass.shadow, animation: shadowAnimation)
            glassCoordinator?.update(shape: style.shape, engine: engine)
        } else {
            removeGlass()
        }

        if let fill = style.fill {
            let view: NotchLayerSurfaceView
            if let existing = fillView {
                view = existing
            } else {
                view = NotchLayerSurfaceView(frame: bounds)
                view.autoresizingMask = [.width, .height]
                addSubview(view, positioned: .above, relativeTo: glassView)
                fillView = view
            }
            view.update(
                shape: style.shape,
                engine: engine,
                fill: fill,
                shadow: style.fillShadow,
                glows: style.glows,
                rim: style.rim,
                shadowAnimation: shadowAnimation
            )
        } else if let fillView {
            fillView.detach()
            fillView.removeFromSuperview()
            self.fillView = nil
        }
    }

    func setShadowOpacity(_ opacity: Double, animation: Animation?) {
        guard var style, style.animatesShadowOpacity else { return }
        var changed = false
        if var glass = style.glass, glass.shadow.opacity != CGFloat(opacity) {
            glass.shadow.opacity = CGFloat(opacity)
            style.glass = glass
            glassView?.setShadow(glass.shadow, animation: animation)
            changed = true
        }
        if style.fill != nil, style.glass == nil, style.fillShadow.opacity != opacity {
            style.fillShadow.opacity = opacity
            fillView?.setShadowOpacity(opacity, animation: animation)
            changed = true
        }
        if changed { self.style = style }
    }

    func detach() {
        removeGlass()
        fillView?.detach()
        fillView?.removeFromSuperview()
        fillView = nil
        style = nil
    }

    private func removeGlass() {
        glassCoordinator?.detach()
        glassCoordinator = nil
        glassView?.removeFromSuperview()
        glassView = nil
    }
}