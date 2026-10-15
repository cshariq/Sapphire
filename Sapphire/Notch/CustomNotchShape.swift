//
//  CustomNotchShape.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-05-12.
//

import SwiftUI

struct CustomNotchShape: Shape, Hashable {
    var cornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var isMusicActivity: Bool = false
    var isFloatingIsland: Bool = false
    var floatingIslandCornerRadius: CGFloat = Self.floatingIslandExpandedCornerRadius
    var isNotchless: Bool = false
    var islandBarSize: CGSize = .zero
    var islandBarGap: CGFloat = 0
    var islandCollapsedHeight: CGFloat = 0
    var satellites = NotchSatellitePresence.none
    var satelliteLayout = NotchSatelliteLayout.none

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
        let main = mainPath(in: rect)
        guard !satellites.isEmpty, satelliteLayout.diameter > 0 else { return main }
        var path = main
        for slot in NotchSatelliteSlot.allCases {
            let presence = satellites[slot]
            guard presence > 0.001 else { continue }
            let bubble = satelliteLayout.rect(slot: slot, presence: presence, outline: rect)
            let anchor = satelliteLayout.anchor(of: slot, outline: rect)
            let inside = slot.isTrailing ? bubble.maxX <= anchor.maxX - 0.5 : bubble.minX >= anchor.minX + 0.5
            if inside { continue }
            let neck = satelliteLayout.neck(slot: slot, bubble: bubble, anchor: anchor)
            let apart = slot.isTrailing ? bubble.minX > anchor.maxX + 0.5 : bubble.maxX < anchor.minX - 0.5
            if apart && neck == nil {
                path.addPath(Circle().path(in: bubble))
                continue
            }
            path = path.union(Circle().path(in: bubble))
            if let neck { path = path.union(neck) }
        }
        return path
    }

    func shoulderInset(in rect: CGRect) -> CGFloat {
        guard !isFloatingIsland, rect.width.isFinite, rect.height.isFinite else { return 0 }
        if isNotchless {
            return min(Self.notchlessShoulderRadius(cornerRadius: cornerRadius), rect.height / 2, rect.width / 4)
        }
        return hardwareShoulderRadius(in: rect)
    }

    private func hardwareShoulderRadius(in rect: CGRect) -> CGFloat {
        let adjustedCornerRadius = min(max(0, cornerRadius), rect.height * 0.5, rect.width * 0.5)
        let topRadiusBase: CGFloat = isMusicActivity ? 8 :
            (adjustedCornerRadius > 15 ? adjustedCornerRadius - 5 : 8)
        let maxPossibleTopRadiusFromHeight = rect.height > 0 ? rect.height / 2.0 : 0
        let derivedTopRadius = min(topRadiusBase, maxPossibleTopRadiusFromHeight)
        return max(0.0, min(derivedTopRadius, rect.width / 2.0))
    }

    private func mainPath(in rect: CGRect) -> Path {
        if isFloatingIsland {
            return islandPath(in: rect)
        }

        if isNotchless {
            return notchlessPath(in: rect)
        }

        let adjustedBottomCornerRadius = min(max(0, bottomCornerRadius), rect.height * 0.5, rect.width * 0.5)
        let topRadius = hardwareShoulderRadius(in: rect)

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

    // MARK: Floating island

    func islandBarPresence(height: CGFloat) -> CGFloat {
        guard islandBarSize.width > 0, islandBarSize.height > 0 else { return 0 }
        let t = (height - islandCollapsedHeight - Self.islandBarEmergeStart) / Self.islandBarEmergeSpan
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    static let islandBarEmergeStart: CGFloat = 26
    static let islandBarEmergeSpan: CGFloat = 64

    private func islandPath(in rect: CGRect) -> Path {
        let presence = islandBarPresence(height: rect.height)
        let barHeight = min(islandBarSize.height, rect.height / 2)
        guard presence > 0, barHeight > 0 else {
            return RoundedRectangle(cornerRadius: islandCardRadius(rect), style: .continuous).path(in: rect)
        }

        let card = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(barHeight, rect.height - (islandBarGap + barHeight) * presence)
        )
        var path = RoundedRectangle(cornerRadius: islandCardRadius(card), style: .continuous).path(in: card)

        let cardRadius = islandCardRadius(card)
        let flatBottom = card.width - 2 * min(cardRadius * Self.continuousCornerExtent, card.width / 2)
        let fullWidth = min(islandBarSize.width, rect.width)
        let barWidth = max(barHeight, min(fullWidth, max(flatBottom, 0) + fullWidth * presence) * (0.5 + 0.5 * presence))
        let bar = CGRect(x: rect.midX - barWidth / 2, y: rect.maxY - barHeight, width: barWidth, height: barHeight)
        let neck = Self.islandNeck(card: card, cardRadius: cardRadius, bar: bar, gap: islandBarGap)
        if neck == nil, bar.minY > card.maxY + 0.5 {
            path.addPath(Capsule(style: .continuous).path(in: bar))
            return path
        }
        path = path.union(Capsule(style: .continuous).path(in: bar))
        if let neck { path = path.union(neck) }
        return path
    }

    func islandCardRadius(_ rect: CGRect) -> CGFloat {
        let animated = bottomCornerRadius > 0 ? bottomCornerRadius : floatingIslandCornerRadius
        let openness = min(1, max(0, (animated - floatingIslandCornerRadius * 0.6) / (floatingIslandCornerRadius * 0.4)))
        let proportional = min(Self.islandMaximumCardRadius, max(floatingIslandCornerRadius, rect.height * Self.islandCardRadiusPerHeight))
        let radius = animated + (max(animated, proportional) - animated) * openness
        return min(rect.height / 2, rect.width / 2, radius)
    }

    static let islandCardRadiusPerHeight: CGFloat = 0.2
    static let islandMaximumCardRadius: CGFloat = 52

    func islandCardRect(in rect: CGRect) -> CGRect {
        let presence = islandBarPresence(height: rect.height)
        let barHeight = min(islandBarSize.height, rect.height / 2)
        guard presence > 0, barHeight > 0 else { return rect }
        return CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(barHeight, rect.height - (islandBarGap + barHeight) * presence)
        )
    }

    private static func islandNeck(card: CGRect, cardRadius: CGFloat, bar: CGRect, gap: CGFloat) -> Path? {
        let radius = bar.height / 2
        let straightHalf = max(0, bar.width / 2 - radius)
        let midX = bar.midX
        let separation = bar.minY - card.maxY
        let release = max(gap * 0.85, 1)
        guard separation < release, card.maxY < bar.maxY - 0.5 else { return nil }

        func barHalfWidth(at y: CGFloat) -> CGFloat {
            let dy = min(abs(y - bar.midY), radius)
            return straightHalf + (radius * radius - dy * dy).squareRoot()
        }

        var path = Path()
        if separation < 0 {
            let junction = barHalfWidth(at: card.maxY)
            let flatHalf = card.width / 2 - min(cardRadius * continuousCornerExtent, card.width / 2)
            let fillet = min(7, flatHalf - junction)
            guard fillet >= 1 else { return nil }
            let below = min(card.maxY + fillet, bar.maxY)
            let lower = barHalfWidth(at: below)
            for side: CGFloat in [-1, 1] {
                path.move(to: CGPoint(x: midX + side * (junction + fillet), y: card.maxY - 1))
                path.addLine(to: CGPoint(x: midX + side * (junction + fillet), y: card.maxY))
                path.addQuadCurve(
                    to: CGPoint(x: midX + side * lower, y: below),
                    control: CGPoint(x: midX + side * junction, y: card.maxY)
                )
                path.addLine(to: CGPoint(x: midX, y: below))
                path.addLine(to: CGPoint(x: midX, y: card.maxY - 1))
                path.closeSubpath()
            }
            return path
        }

        let s = separation / release
        let pinch = pow(1 - s, 1.6)
        let top = card.maxY - 1
        let bottom = bar.minY + min(4, radius)
        let topHalf = straightHalf * pinch + 6 * (1 - s)
        let bottomHalf = straightHalf * pinch
        let waist = straightHalf * pinch * (1 - s)
        guard topHalf > 0.5, bottomHalf > 0.5 else { return nil }
        let height = bottom - top
        path.move(to: CGPoint(x: midX - topHalf, y: top))
        path.addCurve(
            to: CGPoint(x: midX - bottomHalf, y: bottom),
            control1: CGPoint(x: midX - waist, y: top + height * 0.45),
            control2: CGPoint(x: midX - waist, y: top + height * 0.55)
        )
        path.addLine(to: CGPoint(x: midX + bottomHalf, y: bottom))
        path.addCurve(
            to: CGPoint(x: midX + topHalf, y: top),
            control1: CGPoint(x: midX + waist, y: top + height * 0.55),
            control2: CGPoint(x: midX + waist, y: top + height * 0.45)
        )
        path.closeSubpath()
        return path
    }

    // MARK: Notchless notch

    private func notchlessPath(in rect: CGRect) -> Path {
        let shoulder = min(
            Self.notchlessShoulderRadius(cornerRadius: cornerRadius),
            rect.height / 2,
            rect.width / 4
        )
        let body = rect.insetBy(dx: shoulder, dy: 0)
        let extent = Self.continuousCornerExtent
        let bottom = max(0, min(bottomCornerRadius, (body.height - shoulder) / extent, body.width / 2 / extent))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        Self.addShoulder(to: &path, from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: body.minX, y: rect.minY + shoulder))
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - bottom * extent))
        Self.addContinuousCorner(to: &path, corner: CGPoint(x: body.minX, y: body.maxY), incoming: CGVector(dx: 0, dy: -1), outgoing: CGVector(dx: 1, dy: 0), radius: bottom)
        path.addLine(to: CGPoint(x: body.maxX - bottom * extent, y: body.maxY))
        Self.addContinuousCorner(to: &path, corner: CGPoint(x: body.maxX, y: body.maxY), incoming: CGVector(dx: -1, dy: 0), outgoing: CGVector(dx: 0, dy: -1), radius: bottom)
        path.addLine(to: CGPoint(x: body.maxX, y: rect.minY + shoulder))
        Self.addShoulder(to: &path, from: CGPoint(x: body.maxX, y: rect.minY + shoulder), to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    static func notchlessShoulderRadius(cornerRadius: CGFloat) -> CGFloat {
        min(max(cornerRadius * 0.4, 6), 12)
    }

    private static func addShoulder(to path: inout Path, from start: CGPoint, to end: CGPoint) {
        let k: CGFloat = 0.5523
        let leavingTop = start.y < end.y
        let dx = end.x - start.x
        let dy = end.y - start.y
        if leavingTop {
            path.addCurve(to: end, control1: CGPoint(x: start.x + dx * k, y: start.y), control2: CGPoint(x: end.x, y: end.y - dy * k))
        } else {
            path.addCurve(to: end, control1: CGPoint(x: start.x, y: start.y + dy * k), control2: CGPoint(x: end.x - dx * k, y: end.y))
        }
    }

    static let continuousCornerExtent: CGFloat = 1.52866483

    private static func addContinuousCorner(to path: inout Path, corner: CGPoint, incoming a: CGVector, outgoing b: CGVector, radius r: CGFloat) {
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: corner.x + (a.dx * u + b.dx * v) * r, y: corner.y + (a.dy * u + b.dy * v) * r)
        }
        path.addCurve(to: point(0.63149399, 0.07491139), control1: point(1.08849296, 0), control2: point(0.86840694, 0))
        path.addCurve(to: point(0.07491139, 0.63149399), control1: point(0.37282383, 0.16905956), control2: point(0.16905956, 0.37282383))
        path.addCurve(to: point(0, continuousCornerExtent), control1: point(0, 0.86840694), control2: point(0, 1.08849296))
    }

    static let horizontalContentPadding: CGFloat = 10
    static let floatingIslandExpandedCornerRadius: CGFloat = 32

    static func calculateHorizontalPadding() -> CGFloat {
        horizontalContentPadding
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

// MARK: - Satellites

struct NotchSatelliteSlot: Hashable, CaseIterable {
    let index: Int

    static let count = 5
    static let allCases = (0..<count).map(NotchSatelliteSlot.init(index:))

    var isTrailing: Bool { index % 2 == 0 }
    var ring: Int { index / 2 }
    var inner: NotchSatelliteSlot? { ring > 0 ? NotchSatelliteSlot(index: index - 2) : nil }
}

struct NotchSatellitePresence: Hashable {
    private var values = SIMD8<Double>(repeating: 0)

    static let none = NotchSatellitePresence()

    static func showing(_ count: Int) -> NotchSatellitePresence {
        var presence = NotchSatellitePresence()
        for slot in NotchSatelliteSlot.allCases where slot.index < count { presence[slot] = 1 }
        return presence
    }

    subscript(slot: NotchSatelliteSlot) -> CGFloat {
        get { CGFloat(values[slot.index]) }
        set { values[slot.index] = Double(newValue) }
    }

    var isEmpty: Bool { NotchSatelliteSlot.allCases.allSatisfy { self[$0] <= 0.001 } }
    var count: Int { NotchSatelliteSlot.allCases.filter { self[$0] > 0 }.count }
}

struct NotchSatelliteLayout: Hashable {
    var diameter: CGFloat
    var gap: CGFloat
    var centerY: CGFloat

    static let none = NotchSatelliteLayout(diameter: 0, gap: 0, centerY: 0)

    func reach(count: Int) -> CGFloat {
        let rings = (count + 1) / 2
        return CGFloat(rings) * (gap + diameter)
    }

    func anchor(of slot: NotchSatelliteSlot, outline: CGRect) -> CGRect {
        guard let inner = slot.inner else { return outline }
        return restingRect(slot: inner, outline: outline)
    }

    func rect(slot: NotchSatelliteSlot, presence: CGFloat, outline: CGRect) -> CGRect {
        let p = max(0, presence)
        let size = diameter * (0.5 + 0.5 * min(p, 1.08))
        let tucked = diameter / 2
        let apart = gap + diameter / 2
        let distance = -tucked + (apart + tucked) * p
        let ringOffset = CGFloat(slot.ring) * (gap + diameter)
        let centerX = slot.isTrailing
            ? outline.maxX + ringOffset + distance
            : outline.minX - ringOffset - distance
        let centerY = outline.minY + self.centerY
        return CGRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size)
    }

    func restingRect(slot: NotchSatelliteSlot, outline: CGRect) -> CGRect {
        rect(slot: slot, presence: 1, outline: outline)
    }

    func neck(slot: NotchSatelliteSlot, bubble: CGRect, anchor outline: CGRect) -> Path? {
        let trailing = slot.isTrailing
        let separation = trailing ? bubble.minX - outline.maxX : outline.minX - bubble.maxX
        let release = max(gap * 0.9, 1)
        guard separation > -bubble.width * 0.25, separation < release else { return nil }
        let s = max(0, separation) / release
        let half = bubble.height / 2
        let waist = half * 0.55 * pow(1 - s, 1.4)
        guard waist > 0.4 else { return nil }
        let dir: CGFloat = trailing ? 1 : -1
        let notchEnd = trailing ? outline.maxX : outline.minX
        let bubbleEdge = trailing ? bubble.minX : bubble.maxX
        let x0 = notchEnd - dir * min(outline.height / 2, half)
        let x1 = bubble.midX
        let anchorHalf = half * 0.7
        let midY = bubble.midY
        var path = Path()
        path.move(to: CGPoint(x: x0, y: midY - anchorHalf))
        path.addCurve(
            to: CGPoint(x: x1, y: midY - anchorHalf),
            control1: CGPoint(x: notchEnd, y: midY - waist),
            control2: CGPoint(x: bubbleEdge, y: midY - waist)
        )
        path.addLine(to: CGPoint(x: x1, y: midY + anchorHalf))
        path.addCurve(
            to: CGPoint(x: x0, y: midY + anchorHalf),
            control1: CGPoint(x: bubbleEdge, y: midY + waist),
            control2: CGPoint(x: notchEnd, y: midY + waist)
        )
        path.closeSubpath()
        return path
    }
}