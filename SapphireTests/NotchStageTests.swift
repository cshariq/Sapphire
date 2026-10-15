//
//  NotchStageTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-11
//

import AppKit
import SwiftUI
import XCTest
@testable import Sapphire

@MainActor
final class NotchStageTests: XCTestCase {
    // MARK: Chrome anchoring

    func testChromePiecesPinToTheOutlineEdges() {
        let outline = CGRect(x: 100, y: 0, width: 400, height: 120)
        let size = CGSize(width: 60, height: 32)
        let leading = NotchChromeGeometry.frame(anchor: .leading, inset: 40, top: 4, size: size, outline: outline, scale: 2)
        XCTAssertEqual(leading.minX, 140)
        XCTAssertEqual(leading.minY, 4)
        let trailing = NotchChromeGeometry.frame(anchor: .trailing, inset: 40, top: 0, size: size, outline: outline, scale: 2)
        XCTAssertEqual(trailing.maxX, 460)
        let center = NotchChromeGeometry.frame(anchor: .center, inset: 0, top: 0, size: size, outline: outline, scale: 2)
        XCTAssertEqual(center.midX, outline.midX, accuracy: 0.5)
    }

    func testChromeFramesSitOnThePixelGrid() {
        let outline = CGRect(x: 100.3, y: 0, width: 400.1, height: 120)
        let frame = NotchChromeGeometry.frame(anchor: .leading, inset: 10, top: 0, size: CGSize(width: 20, height: 10), outline: outline, scale: 2)
        XCTAssertEqual(frame.minX * 2, (frame.minX * 2).rounded(), accuracy: 1e-9)
    }

    // MARK: Surface style

    private func inputs(
        appearance: NotchAppearanceSettings,
        state: NotchController.NotchState = .clickExpanded,
        gemini: Bool = false,
        shadowOpacity: Double = 1,
        glass: Bool = true
    ) -> NotchSurfaceStyle.Inputs {
        NotchSurfaceStyle.Inputs(
            appearance: appearance,
            config: ResolvedNotchConfiguration(from: Settings(), screen: NSScreen.screens.first),
            shape: CustomNotchShape(cornerRadius: 40, bottomCornerRadius: 40),
            notchState: state,
            isGeminiActive: gemini,
            isManuallyHidden: false,
            surfaceShadowOpacity: shadowOpacity,
            radialEndRadius: 0,
            systemGlassAvailable: glass
        )
    }

    func testDefaultAppearanceIsAFlatBlackFillThatCarriesTheShadow() {
        let appearance = NotchController.resolveAppearance(
            NotchAppearanceSettings(), isExpandedLiveActivity: false, fadeStartLocation: 1
        ) { false }
        let style = NotchSurfaceStyle.resolve(inputs(appearance: appearance, shadowOpacity: 0.6))
        XCTAssertNil(style.glass)
        guard case .solid(let color)? = style.fill else { return XCTFail("expected a solid fill") }
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 1e-6)
        XCTAssertEqual(style.fillShadow.opacity, 0.6)
        XCTAssertTrue(style.animatesShadowOpacity)
    }

    func testBottomFadeOverGlassBecomesAGradientWash() {
        var settings = NotchAppearanceSettings()
        settings.bottomFadeEnabled = true
        let appearance = NotchController.resolveAppearance(
            settings, isExpandedLiveActivity: true, fadeStartLocation: 0.3
        ) { true }
        let style = NotchSurfaceStyle.resolve(inputs(appearance: appearance, state: .autoExpanded))
        XCTAssertNotNil(style.glass, "a translucent surface sits on glass when the system has it")
        guard case .linearGradient(let colors, let locations, _, _)? = style.fill else {
            return XCTFail("expected a gradient wash")
        }
        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(locations.first ?? -1, 0.3, accuracy: 1e-6)
        XCTAssertEqual(style.fillShadow, .none, "the glass casts the shadow, not the wash")
    }

    func testWithoutSystemGlassATranslucentSurfaceFallsBackToAVisualEffectView() {
        var settings = NotchAppearanceSettings()
        settings.mode = .blur
        let appearance = NotchController.resolveAppearance(settings, isExpandedLiveActivity: false, fadeStartLocation: 1) { false }
        let style = NotchSurfaceStyle.resolve(inputs(appearance: appearance, glass: false))
        XCTAssertEqual(style.glass?.backend, .visualEffect)
    }

    func testGeminiPaintsTwoGlowsAndKeepsTheShadowFixed() {
        let appearance = NotchController.resolveAppearance(NotchAppearanceSettings(), isExpandedLiveActivity: false, fadeStartLocation: 1) { false }
        let style = NotchSurfaceStyle.resolve(inputs(appearance: appearance, gemini: true))
        XCTAssertEqual(style.glows.count, 2)
        XCTAssertFalse(style.animatesShadowOpacity)
        XCTAssertEqual(style.glows.map(\.offset.width), [-2, 2])
        let collapsed = NotchSurfaceStyle.resolve(inputs(appearance: appearance, state: .initial, gemini: true))
        XCTAssertEqual(collapsed.glows.map(\.opacity), [0, 0], "the glow is off while the notch is closed")
    }

    // MARK: Window sizer

    func testAWindowCarriedOverFromAnotherScreenDoesNotKeepItsOldSize() {
        let screen = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertTrue(NotchHostWindowSizer.isWithin(NSRect(x: 700, y: 1000, width: 300, height: 100), screen))
        XCTAssertFalse(NotchHostWindowSizer.isWithin(NSRect(x: 1800, y: 1000, width: 300, height: 100), screen))
        XCTAssertFalse(NotchHostWindowSizer.isWithin(.zero, screen))
    }

    // MARK: Stage

    private func makeStage() -> (NSWindow, NotchStageView, NotchMorphEngine) {
        let engine = NotchMorphEngine()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let stage = NotchStageView(engine: engine)
        stage.frame = NSRect(x: 0, y: 0, width: 1000, height: 400)
        window.contentView = stage
        window.orderFrontRegardless()
        return (window, stage, engine)
    }

    private func content(outline: CGSize, chrome: [NotchChromeSlot: NotchChromePiece] = [:], onTap: @escaping () -> Void = {}) -> NotchStageContent {
        var content = NotchStageContent(
            layout: NotchStageLayout(
                topInset: 0, bandHeight: 32, displayScale: 2,
                isFloatingIsland: false, floatingIslandCornerRadius: 38, outlineSize: outline
            ),
            surface: NotchSurfaceStyle(
                shape: CustomNotchShape(cornerRadius: 40, bottomCornerRadius: 40),
                glass: nil, fill: .solid(.black), fillShadow: .none, glows: [], animatesShadowOpacity: true
            )
        )
        content.chrome = chrome
        content.onTap = onTap
        return content
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testClipFollowsTheEngineAndSettlesOnTheTarget() throws {
        let (window, stage, engine) = makeStage()
        defer { window.orderOut(nil) }
        stage.apply(content(outline: CGSize(width: 200, height: 32)))
        engine.setTargets(.size, 200, 32, animation: nil)
        engine.setTargets(.radii, 10, 10, animation: nil)
        pump(0.1)
        XCTAssertEqual(stage.presentedClipFrame, CGRect(x: 400, y: 0, width: 200, height: 32))

        engine.setTargets(.size, 600, 200, animation: .notchMorphSpring(response: 0.3, dampingFraction: 0.9))
        pump(0.08)
        let midway = stage.presentedClipFrame
        try XCTSkipIf(midway.width == 200 || midway.width == 600, "no display link frame was rendered")
        XCTAssertGreaterThan(midway.width, 200)
        XCTAssertLessThan(midway.width, 600)
        XCTAssertEqual(midway.midX, 500, accuracy: 0.5, "the outline grows from the centre")

        pump(1.2)
        XCTAssertEqual(stage.presentedClipFrame, CGRect(x: 200, y: 0, width: 600, height: 200))
        XCTAssertEqual(stage.settledClipFrame, stage.presentedClipFrame, "the view frame catches up once the motion settles")
    }

    func testClipMovesAtTheLayerLevelWhileAnimating() throws {
        let (window, stage, engine) = makeStage()
        defer { window.orderOut(nil) }
        stage.apply(content(outline: CGSize(width: 200, height: 32)))
        engine.setTargets(.size, 200, 32, animation: nil)
        engine.setTargets(.radii, 10, 10, animation: nil)
        pump(0.1)
        let rest = try XCTUnwrap(stage.clipLayerGeometry)
        XCTAssertEqual(rest.bounds, CGRect(x: 400, y: 0, width: 200, height: 32))

        engine.setTargets(.size, 600, 200, animation: .notchMorphSpring(response: 0.3, dampingFraction: 0.9))
        pump(0.08)
        let moving = try XCTUnwrap(stage.clipLayerGeometry)
        try XCTSkipIf(moving.bounds.width == 200 || moving.bounds.width == 600, "no display link frame was rendered")
        XCTAssertEqual(stage.settledClipFrame.width, 200, "the view frame does not change while the outline moves")
        XCTAssertEqual(moving.bounds.size, stage.presentedClipFrame.size)

        pump(1.2)
        let settled = try XCTUnwrap(stage.clipLayerGeometry)
        XCTAssertEqual(stage.settledClipFrame, CGRect(x: 200, y: 0, width: 600, height: 200))
        XCTAssertEqual(settled.bounds, CGRect(x: 200, y: 0, width: 600, height: 200))
    }

    func testLayerPositionMathsMatchesAppKit() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let parent = NotchPassthroughView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        parent.wantsLayer = true
        let clip = NotchClipView(frame: NSRect(x: 10, y: 20, width: 100, height: 40))
        parent.addSubview(clip)
        window.contentView = parent
        window.orderFrontRegardless()
        window.displayIfNeeded()
        pump(0.1)

        for rect in [CGRect(x: 10, y: 20, width: 100, height: 40), CGRect(x: 250, y: 0, width: 300, height: 120)] {
            clip.frame = rect
            window.displayIfNeeded()
            pump(0.05)
            let layer = try XCTUnwrap(clip.layer)
            let superlayer = try XCTUnwrap(layer.superlayer, "AppKit has hosted the clip layer")
            let expected = NotchLayerGeometry.position(
                for: rect,
                anchor: layer.anchorPoint,
                topDown: superlayer.contentsAreFlipped(),
                superHeight: superlayer.bounds.height
            )
            XCTAssertEqual(layer.position.x, expected.x, accuracy: 0.001)
            XCTAssertEqual(layer.position.y, expected.y, accuracy: 0.001)
        }
    }

    func testChromeHostsHugTheirContentAndRideTheEdges() throws {
        let (window, stage, engine) = makeStage()
        defer { window.orderOut(nil) }
        let piece = NotchChromePiece(
            anchor: .leading, inset: 40, top: 0,
            view: AnyView(Color.red.frame(width: 50, height: 30))
        )
        let trailing = NotchChromePiece(
            anchor: .trailing, inset: 40, top: 0,
            view: AnyView(Color.blue.frame(width: 70, height: 30))
        )
        stage.apply(content(outline: CGSize(width: 600, height: 200), chrome: [.leadingIcons: piece, .trailingIcons: trailing]))
        engine.setTargets(.size, 600, 200, animation: nil)
        engine.setTargets(.radii, 40, 40, animation: nil)
        pump(0.2)

        let leading = try XCTUnwrap(stage.chromeFrame(for: .leadingIcons))
        XCTAssertEqual(leading.size, CGSize(width: 50, height: 30))
        XCTAssertEqual(leading.minX, 200 + 40)
        let right = try XCTUnwrap(stage.chromeFrame(for: .trailingIcons))
        XCTAssertEqual(right.maxX, 800 - 40)

        stage.apply(content(outline: CGSize(width: 600, height: 200)))
        pump(0.4)
        XCTAssertNil(stage.chromeFrame(for: .leadingIcons), "dismissed chrome is parked after its fade")

        stage.apply(content(outline: CGSize(width: 600, height: 200), chrome: [.leadingIcons: piece]))
        pump(0.2)
        let again = try XCTUnwrap(stage.chromeFrame(for: .leadingIcons), "a parked host comes back for the next appearance")
        XCTAssertEqual(again.minX, 200 + 40)
    }

    func testBlurAnimationStartsFromTheRadiusSetInTheSameTurn() throws {
        let (window, stage, _) = makeStage()
        defer { window.orderOut(nil) }
        let host = NotchHostedContentView(rootView: AnyView(Text("Sample")), sizing: .fixed)
        host.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        stage.addSubview(host)
        pump(0.1)

        host.apply(blurRadius: 40, animation: nil)
        host.apply(blurRadius: 0, animation: .notchMorphTiming(.easeOut, duration: 0.5))
        let animation = try XCTUnwrap(
            host.layer?.animation(forKey: "filters.notchContentBlur.inputRadius") as? CABasicAnimation,
            "the un-blur runs as a layer animation"
        )
        XCTAssertEqual((animation.fromValue as? NSNumber)?.doubleValue, 40, "it starts from the radius that was just set")
        XCTAssertEqual((animation.toValue as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual(host.layer?.filters?.count, 1)

        pump(0.7)
        XCTAssertNil(host.layer?.filters, "the filter is dropped once the blur has gone")
    }

    func testOnlyPointsInsideTheOutlineAreTappable() {
        let (window, stage, engine) = makeStage()
        defer { window.orderOut(nil) }
        stage.apply(content(outline: CGSize(width: 200, height: 32), onTap: {}))
        engine.setTargets(.size, 200, 32, animation: nil)
        engine.setTargets(.radii, 10, 10, animation: nil)
        pump(0.1)
        XCTAssertTrue(stage.stagePointIsInsideOutline(CGPoint(x: 500, y: 16)))
        XCTAssertFalse(stage.stagePointIsInsideOutline(CGPoint(x: 500, y: 60)))
        XCTAssertFalse(stage.stagePointIsInsideOutline(CGPoint(x: 100, y: 16)))
        XCTAssertFalse(stage.stagePointIsInsideOutline(CGPoint(x: 598, y: 31)), "the rounded bottom corner is outside the shape")
    }
}