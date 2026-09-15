//
//  CircleIconButtonStyle.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import SwiftUI

enum ModernButtonType {
    case prominent, normal, destructive
}

struct CircleIconButtonStyle: ButtonStyle {
    enum Size {
        case regular
        case small
    }

    var type: ModernButtonType
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .small ? 14 : 16, weight: .semibold))
            .foregroundColor(type == .normal ? .primary : .white)
            .frame(width: diameter, height: diameter)
            .background(backgroundColor)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(
                size == .small
                    ? .spring(response: 0.3, dampingFraction: 0.7)
                    : .spring(response: 0.2, dampingFraction: 0.6),
                value: configuration.isPressed
            )
    }

    private var diameter: CGFloat { size == .small ? 32 : 36 }

    private var backgroundColor: Color {
        switch type {
        case .prominent: return .accentColor
        case .normal: return .secondary.opacity(size == .small ? 0.25 : 0.2)
        case .destructive: return .red
        }
    }
}