//
//  RoundedCard.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import SwiftUI

extension View {
    func roundedCard<Fill: ShapeStyle, Stroke: ShapeStyle>(
        fill: Fill,
        cornerRadius: CGFloat,
        stroke: Stroke,
        lineWidth: CGFloat = 1
    ) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: lineWidth)
            )
    }
}