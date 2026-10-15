//
//  NotchWindowingTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import SwiftUI
import XCTest
@testable import Sapphire

@MainActor
final class NotchWindowingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)

    private func extent(
        full: Bool = false,
        size: CGSize = CGSize(width: 200, height: 32),
        margin: CGFloat = NotchHostWindowSizer.fittedMargin
    ) -> NotchHostWindowExtent {
        NotchHostWindowExtent(
            isFull: full,
            notchSize: size,
            notchTopOffset: 0,
            collapsedHeight: 32,
            fullBandInset: 4,
            margin: margin
        )
    }

    // MARK: Stage geometry

    func testStageIsPinnedToTheWindowsTopCentre() {
        let frame = NotchStageGeometry.stageFrame(
            containerSize: CGSize(width: 300, height: 80),
            stageSize: CGSize(width: 1728, height: 470),
            backingScale: 2
        )
        XCTAssertEqual(frame.midX, 150, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 80, accuracy: 0.001)
        XCTAssertEqual(frame.size, CGSize(width: 1728, height: 470))
    }

    func testStageOriginSnapsToThePixelGrid() {
        let retina = NotchStageGeometry.stageFrame(
            containerSize: CGSize(width: 301, height: 80),
            stageSize: CGSize(width: 1728, height: 470),
            backingScale: 2
        )
        XCTAssertEqual(retina.minX, -713.5, accuracy: 0.001)
        let standard = NotchStageGeometry.stageFrame(
            containerSize: CGSize(width: 301, height: 80),
            stageSize: CGSize(width: 1728, height: 470),
            backingScale: 1
        )
        XCTAssertEqual(standard.minX, standard.minX.rounded(), accuracy: 0.001)
    }

    func testStagePointIsTopLeftOriginInTheStage() {
        let stage = CGRect(x: -714, y: -390, width: 1728, height: 470)
        let point = NotchStageGeometry.stagePoint(fromContainerPoint: CGPoint(x: 150, y: 70), stageFrame: stage)
        XCTAssertEqual(point.x, 864, accuracy: 0.001)
        XCTAssertEqual(point.y, 10, accuracy: 0.001)
    }

    func testFullWindowAndFittedWindowGiveTheSameStagePointForTheSameScreenPoint() {
        let stageSize = CGSize(width: 1728, height: 470)
        let fullStage = NotchStageGeometry.stageFrame(containerSize: CGSize(width: 1728, height: 470), stageSize: stageSize, backingScale: 2)
        let fittedStage = NotchStageGeometry.stageFrame(containerSize: CGSize(width: 296, height: 80), stageSize: stageSize, backingScale: 2)
        let screenPoint = CGPoint(x: 870, y: 1100)
        let inFull = NotchStageGeometry.stagePoint(fromContainerPoint: CGPoint(x: screenPoint.x - 0, y: screenPoint.y - 647), stageFrame: fullStage)
        let inFitted = NotchStageGeometry.stagePoint(fromContainerPoint: CGPoint(x: screenPoint.x - 716, y: screenPoint.y - 1037), stageFrame: fittedStage)
        XCTAssertEqual(inFull.x, inFitted.x, accuracy: 0.001)
        XCTAssertEqual(inFull.y, inFitted.y, accuracy: 0.001)
    }

    // MARK: Window sizing

    func testFittedFrameHugsTheNotchWithAnEvenWidth() {
        let frame = NotchHostWindowSizer.frame(for: extent(size: CGSize(width: 201, height: 32)), screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(frame.width.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertGreaterThanOrEqual(frame.width, 201 + 2 * NotchHostWindowSizer.fittedMargin)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
        XCTAssertEqual(frame.height, 32 + NotchHostWindowSizer.fittedMargin, accuracy: 0.001)
    }

    func testLargerMarginWidensTheFittedFrame() {
        let base = NotchHostWindowSizer.frame(for: extent(size: CGSize(width: 600, height: 300)), screenFrame: screen, visibleFrame: visible)
        let wide = NotchHostWindowSizer.frame(for: extent(size: CGSize(width: 600, height: 300), margin: 80), screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(wide.width - base.width, 64, accuracy: 1)
        XCTAssertEqual(wide.height - base.height, 32, accuracy: 1)
    }

    func testFullFrameSpansTheScreenWidth() {
        let frame = NotchHostWindowSizer.frame(for: extent(full: true), screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(frame.width, 1728)
        XCTAssertGreaterThanOrEqual(frame.height, ceil(1117 * 0.42))
        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
    }

    func testGrowthLeavesRoomForAnOvershootOfTheWholeTravel() {
        let open = extent(size: CGSize(width: 700, height: 300))
        let grown = NotchHostWindowSizer.growthExtent(open, from: CGSize(width: 200, height: 32))
        XCTAssertEqual(grown.notchSize.width, 1200, accuracy: 0.001)
        XCTAssertEqual(grown.notchSize.height, 568, accuracy: 0.001)
    }

    func testShrinkingNeedsNoGrowthRoom() {
        let closed = extent(size: CGSize(width: 200, height: 32))
        let grown = NotchHostWindowSizer.growthExtent(closed, from: CGSize(width: 700, height: 300))
        XCTAssertEqual(grown.notchSize, closed.notchSize)
    }

    func testStageCoversTheWidestAndTallestWindowAndNeverShrinksOnTheSameScreen() {
        let small = extent()
        let first = NotchHostWindowSizer.stageSize(current: nil, extent: small, windowSize: CGSize(width: 296, height: 80), screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(first.width, 1728)
        XCTAssertGreaterThanOrEqual(first.height, ceil(1117 * 0.42))

        let tall = extent(size: CGSize(width: 700, height: 900))
        let grown = NotchHostWindowSizer.stageSize(current: first, extent: tall, windowSize: CGSize(width: 900, height: 950), screenFrame: screen, visibleFrame: visible)
        XCTAssertGreaterThanOrEqual(grown.height, 950)

        let back = NotchHostWindowSizer.stageSize(current: grown, extent: small, windowSize: CGSize(width: 296, height: 80), screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(back, grown)
    }

    func testStageResetsForAScreenOfAnotherWidth() {
        let other = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
        let size = NotchHostWindowSizer.stageSize(
            current: CGSize(width: 1728, height: 1000),
            extent: extent(),
            windowSize: CGSize(width: 296, height: 80),
            screenFrame: other,
            visibleFrame: other
        )
        XCTAssertEqual(size.width, 2560)
        XCTAssertEqual(size.height, ceil(1440 * 0.42))
    }

    func testSizerUsesTheAssignedDisplayAndNeverAnotherScreen() {
        XCTAssertEqual(NotchHostWindowSizer.screenIndex(assignedDisplayID: 7, displayIDs: [3, 7], windowScreenIndex: 0), 1)
        XCTAssertNil(NotchHostWindowSizer.screenIndex(assignedDisplayID: 9, displayIDs: [3, 7], windowScreenIndex: 0))
        XCTAssertEqual(NotchHostWindowSizer.screenIndex(assignedDisplayID: 0, displayIDs: [3, 7], windowScreenIndex: 1), 1)
        XCTAssertNil(NotchHostWindowSizer.screenIndex(assignedDisplayID: 0, displayIDs: [3, 7], windowScreenIndex: nil))
    }

    // MARK: Multi-display routing

    func testRequestsGoToTheNamedDisplayThenThePointersThenTheFirst() {
        XCTAssertEqual(NotchDisplayTargeting.display(requested: 2, pointer: 3, notchDisplays: [1, 2, 3]), 2)
        XCTAssertEqual(NotchDisplayTargeting.display(requested: 9, pointer: 3, notchDisplays: [1, 2, 3]), 3)
        XCTAssertEqual(NotchDisplayTargeting.display(requested: nil, pointer: 8, notchDisplays: [1, 2, 3]), 1)
        XCTAssertNil(NotchDisplayTargeting.display(requested: nil, pointer: 1, notchDisplays: []))
    }

    func testPointerAtTheTopEdgeBelongsToThatScreen() {
        let frames: [(id: CGDirectDisplayID, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 1728, height: 1117)),
            (2, CGRect(x: 1728, y: 0, width: 2560, height: 1440))
        ]
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 864, y: 1117), in: frames), 1)
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 1728, y: 500), in: frames), 2)
        XCTAssertNil(NotchDisplayTargeting.display(containing: CGPoint(x: -5, y: 500), in: frames))
    }

    func testGesturesGoToTheNotchOnThePointersDisplay() {
        let active: [(id: String, displayID: CGDirectDisplayID?)] = [("a", 1), ("b", 2)]
        XCTAssertEqual(TrackpadGestureRouting.route(active: active, pointerDisplay: 1), "a")
        XCTAssertEqual(TrackpadGestureRouting.route(active: active, pointerDisplay: 2), "b")
        XCTAssertEqual(TrackpadGestureRouting.route(active: active, pointerDisplay: 5), "b")
        XCTAssertNil(TrackpadGestureRouting.route(active: [(id: String, displayID: CGDirectDisplayID?)](), pointerDisplay: 1))
    }

    func testMenuBarStaysSuspendedWhileAnyNotchHoldsIt() {
        final class Source {}
        let a = Source(), b = Source()
        var sources = MenuBarSuspensionSources()
        XCTAssertTrue(sources.set(true, for: ObjectIdentifier(a)))
        XCTAssertFalse(sources.set(true, for: ObjectIdentifier(b)))
        XCTAssertFalse(sources.set(false, for: ObjectIdentifier(a)))
        XCTAssertTrue(sources.isSuspended)
        XCTAssertTrue(sources.set(false, for: ObjectIdentifier(b)))
        XCTAssertFalse(sources.isSuspended)
        XCTAssertFalse(sources.set(false, for: ObjectIdentifier(b)))
    }

    // MARK: Live activity content

    func testFullContentWithANewCornerRadiusIsAnUpdate() {
        let view = AnyView(EmptyView())
        XCTAssertEqual(
            LiveActivityContent.full(view: view, id: "hud", bottomCornerRadius: 25),
            LiveActivityContent.full(view: view, id: "hud", bottomCornerRadius: 25)
        )
        XCTAssertNotEqual(
            LiveActivityContent.full(view: view, id: "hud", bottomCornerRadius: 25),
            LiveActivityContent.full(view: view, id: "hud", bottomCornerRadius: nil)
        )
        XCTAssertNotEqual(
            LiveActivityContent.full(view: view, id: "a"),
            LiveActivityContent.full(view: view, id: "b")
        )
    }
}