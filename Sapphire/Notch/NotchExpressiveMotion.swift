//
//  NotchExpressiveMotion.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-15
//

import SwiftUI

// MARK: - Artwork swap

private struct ArtworkSwapModifier: ViewModifier {
    let scaleX: CGFloat
    let scaleY: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: scaleX, y: scaleY)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var notchArtworkSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ArtworkSwapModifier(scaleX: 0.55, scaleY: 0.55, blur: 12, opacity: 0),
                identity: ArtworkSwapModifier(scaleX: 1, scaleY: 1, blur: 0, opacity: 1)
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.66).delay(0.12)),
            removal: .modifier(
                active: ArtworkSwapModifier(scaleX: 0.12, scaleY: 0.9, blur: 10, opacity: 0),
                identity: ArtworkSwapModifier(scaleX: 1, scaleY: 1, blur: 0, opacity: 1)
            )
            .animation(.easeIn(duration: 0.2))
        )
    }
}

// MARK: - Skip nudge

private struct DirectionalNudgeModifier: ViewModifier {
    let trigger: Int
    let direction: CGFloat

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            SpringKeyframe(direction * 7, duration: 0.11, spring: .snappy)
            SpringKeyframe(0, duration: 0.42, spring: .init(response: 0.38, dampingRatio: 0.52))
        }
    }
}

extension View {
    func notchDirectionalNudge(trigger: Int, direction: CGFloat) -> some View {
        modifier(DirectionalNudgeModifier(trigger: trigger, direction: direction))
    }
}

// MARK: - Hover tile

private struct HoverTileModifier: ViewModifier {
    let size: CGFloat
    let cornerRadius: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.13 : 0))
                    .frame(width: size, height: size)
                    .scaleEffect(isHovering ? 1 : 0.82)
                    .allowsHitTesting(false)
            }
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isHovering = hovering }
            }
    }
}

extension View {
    func notchHoverTile(size: CGFloat, cornerRadius: CGFloat = 14) -> some View {
        modifier(HoverTileModifier(size: size, cornerRadius: cornerRadius))
    }
}