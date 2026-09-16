//
//  NotchSurfaceBackground.swift
//  Sapphire
//
//  Created by Raadfxrd on 2026-09-15

import SwiftUI
import AppKit

/// The notch's background surface. It only depends on the values below, so wrapping it in
/// `.equatable()` lets SwiftUI skip it when `NotchController` updates for unrelated reasons.
struct NotchSurfaceBackground: View, Equatable {
    let appearance: NotchAppearanceSettings
    let config: ResolvedNotchConfiguration
    let shape: CustomNotchShape
    let notchState: NotchController.NotchState
    let isGeminiActive: Bool
    let isManuallyHidden: Bool
    let surfaceShadowOpacity: Double
    let radialEndRadius: CGFloat

    var body: some View {
        let isOpaqueSolid = appearance.backgroundStyle == .solid && appearance.opacity >= 1
        let fillStyle = fillMaterial.opacity(appearance.opacity)

        if #available(macOS 26.0, *), appearance.usesLiquidGlass, !isOpaqueSolid {
            ZStack {
                LiquidGlassShapeView(
                    backend: .automatic,
                    material: appearance.liquidGlassStyle,
                    shape: shape,
                    tintColor: glassTint,
                    blendingMode: .behindWindow,
                    appearance: .dark,
                    interaction: .normal,
                    shadow: nativeSurfaceShadow
                )
                .allowsHitTesting(false)

                if appearance.backgroundStyle != .solid {
                    shape.fill(fillStyle)
                }
            }
        } else if !isOpaqueSolid, appearance.enableTransparencyBlur {
            ZStack {
                LiquidGlassShapeView(
                    backend: .visualEffect,
                    material: .hud,
                    shape: shape,
                    tintColor: glassTint,
                    blendingMode: .behindWindow,
                    appearance: .dark,
                    interaction: .normal,
                    shadow: nativeSurfaceShadow
                )
                .allowsHitTesting(false)

                if appearance.backgroundStyle != .solid {
                    shape.fill(fillStyle)
                }
            }
        } else {
            directlyPaintedSurface(fillStyle: fillStyle)
        }
    }

    private var shadowRadius: CGFloat {
        notchState == .clickExpanded ? config.expandedShadowRadius : 12
    }

    private var shadowYOffset: CGFloat {
        notchState == .clickExpanded ? config.expandedShadowOffsetY : 6
    }

    private var nativeSurfaceShadow: LiquidGlassShadow {
        if isGeminiActive {
            let color = NSColor.systemPurple.blended(withFraction: 0.5, of: .systemIndigo)
                ?? .systemPurple
            return LiquidGlassShadow(
                color: color,
                opacity: notchState == .initial || isManuallyHidden ? 0 : 0.56,
                radius: shadowRadius,
                offset: CGSize(width: 0, height: shadowYOffset)
            )
        }

        return LiquidGlassShadow(
            color: NSColor(config.expandedShadowColor),
            opacity: surfaceShadowOpacity,
            radius: shadowRadius,
            offset: CGSize(width: 0, height: shadowYOffset)
        )
    }

    @ViewBuilder
    private func directlyPaintedSurface(fillStyle: some ShapeStyle) -> some View {
        if isGeminiActive {
            let opacity = notchState == .initial || isManuallyHidden ? 0.0 : 0.75
            shape
                .fill(fillStyle)
                .shadow(color: .purple.opacity(opacity * 0.7), radius: shadowRadius, x: -2, y: shadowYOffset)
                .shadow(color: .indigo.opacity(opacity * 0.8), radius: shadowRadius, x: 2, y: shadowYOffset)
        } else {
            shape
                .fill(fillStyle)
                .shadow(
                    color: config.expandedShadowColor.opacity(surfaceShadowOpacity),
                    radius: shadowRadius,
                    y: shadowYOffset
                )
        }
    }

    private var glassTint: NSColor? {
        guard appearance.backgroundStyle == .solid, appearance.opacity > 0 else { return nil }
        return NSColor(appearance.solidColor.color).withAlphaComponent(appearance.opacity)
    }

    private var fillMaterial: AnyShapeStyle {
        switch appearance.backgroundStyle {
        case .solid:
            return AnyShapeStyle(appearance.solidColor.color)
        case .gradient:
            let stops = appearance.gradientColors
                .map { Gradient.Stop(color: $0.color, location: $0.location) }
                .sorted { $0.location < $1.location }
            let angle = appearance.gradientAngle * .pi / 180
            let startPoint = UnitPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5)
            let endPoint = UnitPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
            return AnyShapeStyle(LinearGradient(
                gradient: Gradient(stops: stops.isEmpty ? [Gradient.Stop(color: .black, location: 0)] : stops),
                startPoint: startPoint,
                endPoint: endPoint
            ))
        case .radial:
            let stops = appearance.gradientColors
                .map { Gradient.Stop(color: $0.color, location: $0.location) }
                .sorted { $0.location < $1.location }
            return AnyShapeStyle(RadialGradient(
                gradient: Gradient(stops: stops.isEmpty ? [Gradient.Stop(color: .black, location: 0)] : stops),
                center: .center,
                startRadius: 0,
                endRadius: radialEndRadius
            ))
        }
    }
}
