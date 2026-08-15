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

                if settings.settings.lockScreenFrostedOverLiquidGlass {
                    frostedOverlay
                }
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
                    .overlay(
                        shape
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .white.opacity(0.2),
                                        .white.opacity(0.05)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: LockScreenConfiguration.backgroundStrokeWidth
                            )
                            .blur(radius: LockScreenConfiguration.backgroundStrokeBlur)
                    )
            }
        }
    }

    @ViewBuilder
    private var frostedOverlay: some View {
        VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
            .clipShape(shape)

        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            .clipShape(shape)
            .opacity(0.72)

        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        shape
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42),
                        Color.white.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}