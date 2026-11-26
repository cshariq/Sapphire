//
//  MarqueeText.swift
//  Sapphire
//

import AppKit
import SwiftUI

/// A single-line text that scrolls when it doesn't fit. The truncated `Text` still drives layout;
/// the scrolling copy is a Core Animation strip so the render server runs the motion, not SwiftUI.
struct MarqueeText: View {
    let text: Text
    let speed: CGFloat
    let pause: TimeInterval
    let gap: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fittedWidth: CGFloat = 0
    @State private var naturalWidth: CGFloat = 0

    init(_ text: Text, speed: CGFloat = 30, pause: TimeInterval = 2.5, gap: CGFloat = 32) {
        self.text = text
        self.speed = speed
        self.pause = pause
        self.gap = gap
    }

    private var overflows: Bool {
        !reduceMotion && naturalWidth > fittedWidth + 0.5
    }

    var body: some View {
        text
            .lineLimit(1)
            .opacity(overflows ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fittedWidth = $0 }
            .background(alignment: .leading) {
                text
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if overflows {
                    MarqueeStrip(text: text, textWidth: naturalWidth, style: .init(speed: speed, pause: pause, gap: gap))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
    }
}

private struct MarqueeStrip: NSViewRepresentable {
    let text: Text
    let textWidth: CGFloat
    let style: MarqueeStripView.Style

    func makeNSView(context: Context) -> MarqueeStripView {
        MarqueeStripView()
    }

    func updateNSView(_ view: MarqueeStripView, context: Context) {
        view.show(
            MarqueeStripView.Content(
                text: text,
                gap: style.gap,
                colorScheme: context.environment.colorScheme,
                font: context.environment.font
            ),
            textWidth: textWidth,
            style: style
        )
    }
}

final class MarqueeStripView: NSView {
    struct Style: Equatable {
        let speed: CGFloat
        let pause: TimeInterval
        let gap: CGFloat
    }

    struct Content: Equatable {
        let text: Text
        let gap: CGFloat
        let colorScheme: ColorScheme
        let font: Font?
    }

    private struct Motion: Equatable {
        let width: CGFloat
        let textWidth: CGFloat
        let scale: CGFloat
        let style: Style
    }

    private static let fadeWidth: CGFloat = 14
    private static let fadeRamp: CFTimeInterval = 0.3

    private let strip = NSView()
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private let fade = CAGradientLayer()
    private var content: Content?
    private var textWidth: CGFloat = 0
    private var style: Style?
    private var motion: Motion?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        strip.wantsLayer = true
        host.sizingOptions = []
        strip.addSubview(host)
        addSubview(strip)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = Self.restingColors
        layer?.mask = fade
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ content: Content, textWidth: CGFloat, style: Style) {
        guard content != self.content || textWidth != self.textWidth || style != self.style else { return }
        if content != self.content {
            self.content = content
            host.rootView = AnyView(
                HStack(spacing: content.gap) {
                    content.text.lineLimit(1)
                    content.text.lineLimit(1)
                }
                .fixedSize()
                .environment(\.colorScheme, content.colorScheme)
                .environment(\.font, content.font)
            )
        }
        self.textWidth = textWidth
        self.style = style
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let stripSize = CGSize(width: textWidth * 2 + (style?.gap ?? 0), height: bounds.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.frame = CGRect(origin: .zero, size: stripSize)
        strip.frame = CGRect(origin: .zero, size: stripSize)
        fade.frame = bounds
        let edge = bounds.width > 0 ? min(Self.fadeWidth / bounds.width, 0.25) : 0
        fade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        CATransaction.commit()

        installMotionIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        motion = nil
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func installMotionIfNeeded() {
        guard let style, let stripLayer = strip.layer, let window else { return }
        let scale = window.backingScaleFactor
        let next = Motion(width: bounds.width, textWidth: textWidth, scale: scale, style: style)
        guard next != motion else { return }
        motion = next

        stripLayer.removeAnimation(forKey: "marquee")
        fade.removeAnimation(forKey: "marquee")

        let distance = ((textWidth + style.gap) * scale).rounded() / scale
        guard bounds.width > 0, textWidth > bounds.width, style.speed > 0 else { return }

        let slide = CFTimeInterval(distance / style.speed)
        let cycle = style.pause + slide
        let ramp = min(Self.fadeRamp, slide / 4)
        let moveStart = NSNumber(value: style.pause / cycle)

        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [CGFloat(0), 0, -distance]
        scroll.keyTimes = [0, moveStart, 1]
        scroll.duration = cycle
        scroll.repeatCount = .infinity
        scroll.isRemovedOnCompletion = false

        // The left edge only fades while the text is moving, so the first letters sit clean at rest.
        let edges = CAKeyframeAnimation(keyPath: "colors")
        edges.values = [Self.restingColors, Self.restingColors, Self.movingColors, Self.movingColors, Self.restingColors]
        edges.keyTimes = [
            0,
            moveStart,
            NSNumber(value: (style.pause + ramp) / cycle),
            NSNumber(value: (cycle - ramp) / cycle),
            1,
        ]
        edges.duration = cycle
        edges.repeatCount = .infinity
        edges.isRemovedOnCompletion = false

        CATransaction.begin()
        stripLayer.add(scroll, forKey: "marquee")
        fade.add(edges, forKey: "marquee")
        CATransaction.commit()
    }

    private static let opaque = CGColor(gray: 0, alpha: 1)
    private static let clear = CGColor(gray: 0, alpha: 0)
    private static let restingColors = [opaque, opaque, opaque, clear]
    private static let movingColors = [clear, opaque, opaque, clear]
}
