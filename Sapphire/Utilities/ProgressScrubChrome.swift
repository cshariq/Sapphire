//
//  ProgressScrubChrome.swift
//  Sapphire
//

import AppKit
import SwiftUI

struct ProgressScrubThumb: View {
    var diameter: CGFloat
    var intensity: Double = 0.65
    var isHovered: Bool = true

    var body: some View {
        let shape = Circle()
        ZStack {
            if #available(macOS 26.0, *), LiquidGlassView.isSystemGlassAvailable {
                LiquidGlassShapeFill(
                    shape: shape,
                    cornerRadius: diameter / 2,
                    intensity: intensity,
                    blendingMode: .withinWindow,
                    appearance: .dark,
                    interaction: isHovered ? .hovered : .normal
                )
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(shape)
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}

struct ProgressScrubTooltip: View {
    var text: String
    var intensity: Double = 0.65

    var body: some View {
        let shape = Capsule()
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    if #available(macOS 26.0, *), LiquidGlassView.isSystemGlassAvailable {
                        LiquidGlassShapeFill(
                            material: .tooltip,
                            shape: shape,
                            intensity: intensity,
                            blendingMode: .withinWindow,
                            appearance: .dark,
                            interaction: .hovered
                        )
                    } else {
                        VisualEffectView(material: .toolTip, blendingMode: .withinWindow)
                            .clipShape(shape)
                        shape.stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
                }
            }
            .allowsHitTesting(false)
    }
}
