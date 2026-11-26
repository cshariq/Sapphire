//
//  HUDLevelPalette.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-28

import SwiftUI

/// The colors and glow of a HUD level bar, resolved from the HUD appearance settings.
struct HUDLevelPalette {
    let style: HUDVisualStyle
    let customColor: Color
    let transition: HUDGradientTransition
    let glows: Bool
    let glowStrength: Double
    /// Where colors 2 and 3 take over, as fractions of the track.
    let color2Start: Double
    let color3Start: Double
    /// Stops spread over the whole track when the fill is a smooth gradient; nil for solid fills.
    private(set) var trackStops: [Gradient.Stop]?

    private let gradient: [OKLab]

    init(
        style: HUDVisualStyle,
        customColor: Color,
        gradientColors: [CGColor],
        color2Start: Int,
        color3Start: Int,
        transition: HUDGradientTransition,
        glows: Bool,
        glowStrength: Double
    ) {
        self.style = style
        self.customColor = customColor
        self.transition = transition
        self.glows = glows
        self.glowStrength = glowStrength
        let start2 = color2Start.clamped(to: 1...98)
        self.color2Start = Double(start2) / 100
        self.color3Start = Double(color3Start.clamped(to: (start2 + 1)...99)) / 100
        self.gradient = gradientColors.map(OKLab.init)
        if style == .gradient && transition == .smooth {
            let palette = self
            trackStops = (0...Self.trackStopCount).map { index in
                let location = Double(index) / Double(Self.trackStopCount)
                return Gradient.Stop(color: palette.blended(at: location).color, location: location)
            }
        }
    }

    /// The bar's color at `level`: the whole fill for solid styles, the leading tip for a smooth gradient.
    func color(at level: Float) -> Color {
        let level = Double(level.clamped(to: 0...1))
        switch style {
        case .white: return .white.opacity(0.7)
        case .color: return customColor
        case .adaptive:
            if level >= 0.9 { return .red }
            if level > 0.6 { return .yellow }
            return .white
        case .gradient:
            return transition == .smooth ? blended(at: level).color : gradient[zone(at: level)].color
        }
    }

    /// The color of the track at `position` (0...1) when it is filled up to `level`.
    func color(atTrackPosition position: Double, level: Float) -> Color {
        trackStops == nil ? color(at: level) : blended(at: position.clamped(to: 0...1)).color
    }

    /// The gradient as it would fill a full track, with hard edges when stepped.
    var previewStops: [Gradient.Stop] {
        if let trackStops { return trackStops }
        let colors = gradient.map(\.color)
        return [
            .init(color: colors[0], location: 0), .init(color: colors[0], location: color2Start),
            .init(color: colors[1], location: color2Start), .init(color: colors[1], location: color3Start),
            .init(color: colors[2], location: color3Start), .init(color: colors[2], location: 1)
        ]
    }

    func glowRadius(at level: Float, maximum: CGFloat) -> CGFloat {
        guard glows else { return 0 }
        return CGFloat(level.clamped(to: 0...1)) * maximum * glowStrength
    }

    private static let trackStopCount = 24

    private func zone(at level: Double) -> Int {
        level < color2Start ? 0 : (level < color3Start ? 1 : 2)
    }

    /// Each color is pure at the middle of its range and blends evenly into its neighbours, crossing over at the range edges.
    private func blended(at position: Double) -> OKLab {
        let centers = [color2Start / 2, (color2Start + color3Start) / 2, (color3Start + 1) / 2]
        if position <= centers[0] { return gradient[0] }
        if position >= centers[2] { return gradient[2] }
        let lower = position < centers[1] ? 0 : 1
        let fraction = (position - centers[lower]) / (centers[lower + 1] - centers[lower])
        return gradient[lower].mixed(with: gradient[lower + 1], by: fraction)
    }
}

extension HUDLevelPalette {
    init(_ settings: TrackedSettings) {
        self.init(
            style: settings.hudVisualStyle,
            customColor: settings.hudCustomColor?.color ?? .accentColor,
            gradientColors: [settings.hudGradientColor1.cgColor, settings.hudGradientColor2.cgColor, settings.hudGradientColor3.cgColor],
            color2Start: settings.hudGradientColor2Start,
            color3Start: settings.hudGradientColor3Start,
            transition: settings.hudGradientTransition,
            glows: settings.hudGlowEnabled,
            glowStrength: settings.hudGlowStrength
        )
    }
}

/// Colors are blended in OKLab so a gradient keeps its brightness through the middle instead of going muddy.
private struct OKLab {
    var l, a, b, alpha: Double

    init(_ cgColor: CGColor) {
        let srgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.extendedSRGB)!, intent: .defaultIntent, options: nil)
        let c = (srgb?.components ?? [1, 1, 1, 1]).map(Double.init)
        let (r, g, bl) = (Self.linear(c[0]), Self.linear(c[1]), Self.linear(c[2]))
        let lms = [
            cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl),
            cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl),
            cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        ]
        l = 0.2104542553 * lms[0] + 0.7936177850 * lms[1] - 0.0040720468 * lms[2]
        a = 1.9779984951 * lms[0] - 2.4285922050 * lms[1] + 0.4505937099 * lms[2]
        b = 0.0259040371 * lms[0] + 0.7827717662 * lms[1] - 0.8086757660 * lms[2]
        alpha = c.count > 3 ? c[3] : 1
    }

    private init(l: Double, a: Double, b: Double, alpha: Double) {
        (self.l, self.a, self.b, self.alpha) = (l, a, b, alpha)
    }

    func mixed(with other: OKLab, by fraction: Double) -> OKLab {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * fraction }
        return OKLab(l: mix(l, other.l), a: mix(a, other.a), b: mix(b, other.b), alpha: mix(alpha, other.alpha))
    }

    var color: Color {
        let lms = [
            pow(l + 0.3963377774 * a + 0.2158037573 * b, 3),
            pow(l - 0.1055613458 * a - 0.0638541728 * b, 3),
            pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        ]
        let r = 4.0767416621 * lms[0] - 3.3077115913 * lms[1] + 0.2309699292 * lms[2]
        let g = -1.2684380046 * lms[0] + 2.6097574011 * lms[1] - 0.3413193965 * lms[2]
        let bl = -0.0041960863 * lms[0] - 0.7034186147 * lms[1] + 1.7076147010 * lms[2]
        return Color(.sRGB, red: Self.gamma(r), green: Self.gamma(g), blue: Self.gamma(bl), opacity: alpha)
    }

    private static func linear(_ c: Double) -> Double {
        abs(c) <= 0.04045 ? c / 12.92 : copysign(pow((abs(c) + 0.055) / 1.055, 2.4), c)
    }

    private static func gamma(_ c: Double) -> Double {
        let c = c.clamped(to: 0...1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

/// The filled part of a HUD track. A smooth gradient spans the whole track, so raising the level reveals more of it instead of stretching it.
struct HUDTrackFill: View {
    let color: Color
    let stops: [Gradient.Stop]?
    let level: CGFloat
    let length: CGFloat
    var axis: Axis = .horizontal

    var body: some View {
        let vertical = axis == .vertical
        let filled = max(0, length * level.clamped(to: 0...1))
        Group {
            if let stops {
                LinearGradient(stops: stops, startPoint: vertical ? .bottom : .leading, endPoint: vertical ? .top : .trailing)
                    .frame(width: vertical ? nil : length, height: vertical ? length : nil)
            } else {
                color
            }
        }
        .frame(width: vertical ? nil : filled, height: vertical ? filled : nil, alignment: vertical ? .bottom : .leading)
        .clipShape(Capsule())
    }
}

extension View {
    /// Light behind a HUD track: a colored shadow for solid fills, and a blurred copy of the fill for gradients so each part glows in its own color.
    func hudTrackGlow(color: Color, stops: [Gradient.Stop]?, level: CGFloat, axis: Axis = .horizontal, radius: CGFloat) -> some View {
        background(alignment: axis == .vertical ? .bottom : .leading) {
            if let stops, radius > 0 {
                GeometryReader { geometry in
                    HUDTrackFill(color: color, stops: stops, level: level, length: axis == .vertical ? geometry.size.height : geometry.size.width, axis: axis)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: axis == .vertical ? .bottom : .leading)
                }
                // A blur at 0.6× spreads about as far and as bright as a shadow of the full radius.
                .blur(radius: radius * 0.6)
            }
        }
        .shadow(color: stops == nil ? color.opacity(0.9) : .clear, radius: radius)
    }
}
