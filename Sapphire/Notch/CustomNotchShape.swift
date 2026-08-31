//
//  CustomNotchShape.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-05-12.
//

import SwiftUI

struct CustomNotchShape: Shape {
    static let screenWidthAdjustment: CGFloat =
        (NSScreen.main?.frame.size.width ?? 1728) / 1728
    static let screenHeightAdjustment: CGFloat =
        (NSScreen.main?.frame.size.height ?? 1117) / 1117

    var cornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var isMusicActivity: Bool = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, bottomCornerRadius) }
        set {
            cornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else {
            return Path()
        }

        let adjustedCornerRadius = min(max(0, cornerRadius), rect.height * 0.5, rect.width * 0.5)
        let adjustedBottomCornerRadius = min(max(0, bottomCornerRadius), rect.height * 0.5, rect.width * 0.5)

        let topRadiusBase: CGFloat = isMusicActivity ? 8 :
            (adjustedCornerRadius > 15 ? adjustedCornerRadius - 5 : 8)

        let maxPossibleTopRadiusFromHeight = rect.height > 0 ? rect.height / 2.0 : 0
        let derivedTopRadius = min(topRadiusBase, maxPossibleTopRadiusFromHeight)
        let topRadius = max(0.0, min(derivedTopRadius, rect.width / 2.0))

        let availableWidthForBottomRadii = rect.width - 2 * topRadius
        let availableHeightForBottomRadius = rect.height - topRadius

        let safeBottomRadius = max(
            0.0,
            min(
                adjustedBottomCornerRadius,
                availableWidthForBottomRadii / 2.0,
                availableHeightForBottomRadius
            )
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + topRadius,
                y: rect.maxY - safeBottomRadius
            )
        )
        if safeBottomRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.minX + topRadius + safeBottomRadius,
                    y: rect.maxY - safeBottomRadius
                ),
                radius: safeBottomRadius,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 90),
                clockwise: true
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY))
        }
        path.addLine(
            to: CGPoint(
                x: rect.maxX - topRadius - safeBottomRadius,
                y: rect.maxY
            )
        )
        if safeBottomRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.maxX - topRadius - safeBottomRadius,
                    y: rect.maxY - safeBottomRadius
                ),
                radius: safeBottomRadius,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 0),
                clockwise: true
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY))
        }
        path.addLine(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

    static let horizontalContentPadding: CGFloat = 10

    static func calculateHorizontalPadding() -> CGFloat {
        horizontalContentPadding
    }

    static func adjustValue(_ value: CGFloat, isWidth: Bool = true) -> CGFloat {
        return value * (isWidth ? screenWidthAdjustment : screenHeightAdjustment)
    }
}

struct NotchHorizontalPadding: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, CustomNotchShape.calculateHorizontalPadding())
    }
}

extension View {
    func notchHorizontalPadding() -> some View {
        self.modifier(NotchHorizontalPadding())
    }
}