//
//  HUDGradientRangeEditor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-28

import SwiftUI

/// A preview of the Gradient HUD style with a handle where color 2 and color 3 take over.
struct HUDGradientRangeEditor: View {
    @Binding var color2Start: Int
    @Binding var color3Start: Int
    let colors: [CGColor]
    let transition: HUDGradientTransition

    /// The narrowest range a color can be squeezed to, in percent.
    private static let minimumRange = 5

    @State private var draft2: Int?
    @State private var draft3: Int?

    private var start2: Int { (draft2 ?? color2Start).clamped(to: Self.minimumRange...(100 - 2 * Self.minimumRange)) }
    private var start3: Int { (draft3 ?? color3Start).clamped(to: (start2 + Self.minimumRange)...(100 - Self.minimumRange)) }

    private var palette: HUDLevelPalette {
        HUDLevelPalette(
            style: .gradient,
            customColor: .clear,
            gradientColors: colors,
            color2Start: start2,
            color3Start: start3,
            transition: transition,
            glows: false,
            glowStrength: 1
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack {
                    Capsule()
                        .fill(LinearGradient(stops: palette.previewStops, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 10)
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    handle(color: Color(cgColor: colors[1]), percent: start2, width: width, centerY: geometry.size.height / 2) { percent in
                        draft2 = percent.clamped(to: Self.minimumRange...(start3 - Self.minimumRange))
                    } commit: {
                        if let draft2 { color2Start = draft2 }
                        draft2 = nil
                    }
                    .accessibilityLabel("Color 2 starts at")
                    .accessibilityValue("\(start2) percent")
                    .accessibilityAdjustableAction { direction in
                        color2Start = (start2 + (direction == .increment ? 1 : -1)).clamped(to: Self.minimumRange...(start3 - Self.minimumRange))
                    }
                    handle(color: Color(cgColor: colors[2]), percent: start3, width: width, centerY: geometry.size.height / 2) { percent in
                        draft3 = percent.clamped(to: (start2 + Self.minimumRange)...(100 - Self.minimumRange))
                    } commit: {
                        if let draft3 { color3Start = draft3 }
                        draft3 = nil
                    }
                    .accessibilityLabel("Color 3 starts at")
                    .accessibilityValue("\(start3) percent")
                    .accessibilityAdjustableAction { direction in
                        color3Start = (start3 + (direction == .increment ? 1 : -1)).clamped(to: (start2 + Self.minimumRange)...(100 - Self.minimumRange))
                    }
                }
                .coordinateSpace(name: "hudGradientBar")
            }
            .frame(height: 22)

            HStack(spacing: 8) {
                rangeLabel(index: 0, range: "0–\(start2 - 1)%")
                rangeLabel(index: 1, range: "\(start2)–\(start3 - 1)%")
                rangeLabel(index: 2, range: "\(start3)–100%")
            }
        }
    }

    private func handle(color: Color, percent: Int, width: CGFloat, centerY: CGFloat, onDrag: @escaping (Int) -> Void, commit: @escaping () -> Void) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().fill(color).padding(4))
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .contentShape(Circle().inset(by: -6))
            .position(x: width * CGFloat(percent) / 100, y: centerY)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("hudGradientBar"))
                    .onChanged { value in
                        guard width > 0 else { return }
                        onDrag(Int((value.location.x / width * 100).rounded()))
                    }
                    .onEnded { _ in commit() }
            )
            .help("Starts at \(percent)%")
    }

    private func rangeLabel(index: Int, range: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(cgColor: colors[index]))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("Color \(index + 1)")
                    .font(.caption.weight(.medium))
                Text(range)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
