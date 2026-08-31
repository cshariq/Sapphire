//
//  LockScreenWidgetSurface.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI

struct LockScreenWidgetSurface<S: Shape>: View {
    @EnvironmentObject var settings: SettingsModel

    let shape: S
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if settings.settings.lockScreenLiquidGlassLook {
                LiquidGlassShapeFill(
                    shape: shape,
                    cornerRadius: cornerRadius,
                    intensity: settings.settings.lockScreenLiquidGlassIntensity,
                    blendingMode: .behindWindow,
                    appearance: .dark
                )
                .overlay(
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.18)
                        .allowsHitTesting(false)
                )

                if settings.settings.lockScreenFrostedOverLiquidGlass {
                    frostedOverlay
                } else {
                    glassHighlightLayer
                }
            } else {
                glassyFallback
            }
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

    @ViewBuilder
    private var glassHighlightLayer: some View {
        shape
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 140
                )
            )

        shape
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
    }

    @ViewBuilder
    private var frostedOverlay: some View {
        VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
            .clipShape(shape)

        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            .clipShape(shape)
            .opacity(0.55)

        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.20),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        shape
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.09),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 100
                )
            )

        shape
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.35),
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
    }
}