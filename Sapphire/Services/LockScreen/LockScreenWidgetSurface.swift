//
//  LockScreenWidgetSurface.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI

struct LockScreenWidgetSurface<S: Shape>: View {
    @ObservedSettings var settings: SettingsObserver

    let shape: S
    var cacheKey: String = "card"

    var body: some View {
        if settings.settings.lockScreenLiquidGlassLook {
            LockScreenLiquidGlass(options: settings.settings.lockScreenGlass, shape: shape, cacheKey: cacheKey)
        } else {
            glassyFallback
        }
    }

    @ViewBuilder
    private var glassyFallback: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(shape)

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 120
                    )
                )

            shape
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.25),
                            .white.opacity(0.06),
                            .white.opacity(0.12)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: LockScreenConfiguration.backgroundStrokeWidth
                )
                .blur(radius: LockScreenConfiguration.backgroundStrokeBlur)
        }
    }
}

struct LockScreenLiquidGlass<S: Shape>: View {
    let options: LiquidGlassOptions
    let shape: S
    var cacheKey: String = "card"

    var body: some View {
        LiquidGlassShapeFill(
            material: options.material,
            shape: shape,
            tint: options.tintColor.map(Color.init(nsColor:)),
            blendingMode: .behindWindow,
            appearance: options.appearance,
            interaction: options.interaction,
            shapePathCacheKey: AnyHashable("lock-screen-\(cacheKey)-\(options.cornerRadius)")
        )
        .overlay(
            shape
                .fill(Color(red: 8 / 255, green: 5 / 255, blue: 16 / 255, opacity: 24 / 255))
                .allowsHitTesting(false)
        )
    }
}

struct LockScreenCardSurface: View {
    @ObservedSettings var settings: SettingsObserver

    var body: some View {
        LockScreenWidgetSurface(
            shape: RoundedRectangle(cornerRadius: settings.settings.lockScreenGlass.cornerRadius, style: .continuous)
        )
    }
}