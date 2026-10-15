//
//  NotchLifecycleTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import XCTest
@testable import Sapphire

@MainActor
final class NotchLifecycleTests: XCTestCase {
    private typealias Policy = NotchDisplayRefreshPolicy

    private func snapshot(_ displays: [CGDirectDisplayID], targets: [CGDirectDisplayID]) -> Policy.Snapshot {
        Policy.Snapshot(
            displays: displays.map { .init(id: $0, frame: CGRect(x: CGFloat($0) * 2000, y: 0, width: 1728, height: 1117)) },
            targets: targets
        )
    }

    // MARK: Refresh debounce / stability

    func testFirstReadAlwaysReadsAgain() {
        XCTAssertEqual(Policy.step(previous: nil, current: snapshot([1], targets: [1]), reads: 1), .readAgain)
    }

    func testTwoMatchingReadsApply() {
        let a = snapshot([1, 2], targets: [1])
        XCTAssertEqual(Policy.step(previous: a, current: snapshot([2, 1], targets: [1]), reads: 2), .apply)
    }

    func testClamshellWakeWaitsForTheBuiltInDisplay() {
        let externalOnly = snapshot([2], targets: [2])
        let both = snapshot([1, 2], targets: [1])
        XCTAssertEqual(Policy.step(previous: externalOnly, current: both, reads: 2), .readAgain)
        XCTAssertEqual(Policy.step(previous: both, current: both, reads: 3), .apply)
    }

    func testFrameChangeAloneIsNotStable() {
        let a = snapshot([1], targets: [1])
        var b = a
        b.displays[0].frame.size.width = 1512
        XCTAssertEqual(Policy.step(previous: a, current: b, reads: 2), .readAgain)
    }

    func testAKeepsChangingSetIsAppliedEventually() {
        XCTAssertEqual(
            Policy.step(previous: snapshot([1], targets: [1]), current: snapshot([2], targets: [2]), reads: Policy.maxStabilityReads),
            .apply
        )
    }

    func testNoDisplaysNeverTearsTheNotchesDown() {
        let none = snapshot([], targets: [])
        XCTAssertEqual(Policy.step(previous: nil, current: none, reads: 1), .readAgain)
        XCTAssertEqual(Policy.step(previous: none, current: none, reads: 2), .readAgain)
        XCTAssertEqual(Policy.step(previous: none, current: none, reads: Policy.maxStabilityReads), .skip)
    }

    func testDisplaysWithNoNotchTargetStillApply() {
        let off = snapshot([1, 2], targets: [])
        XCTAssertEqual(Policy.step(previous: off, current: off, reads: 2), .apply)
    }

    // MARK: Move instead of destroy + create

    func testFallbackSwapMovesTheWindow() {
        let plan = Policy.plan(windowDisplays: [1], targets: [2])
        XCTAssertEqual(plan.moves, [.init(from: 1, to: 2)])
        XCTAssertTrue(plan.destroy.isEmpty)
        XCTAssertTrue(plan.create.isEmpty)
    }

    func testUnchangedSetDoesNothing() {
        let plan = Policy.plan(windowDisplays: [1, 2], targets: [2, 1])
        XCTAssertEqual(plan, .init(moves: [], destroy: [], create: []))
    }

    func testExtraTargetsCreateAndExtraWindowsDestroy() {
        XCTAssertEqual(Policy.plan(windowDisplays: [1], targets: [1, 3]), .init(moves: [], destroy: [], create: [3]))
        XCTAssertEqual(Policy.plan(windowDisplays: [1, 2], targets: [1]), .init(moves: [], destroy: [2], create: []))
        XCTAssertEqual(
            Policy.plan(windowDisplays: [1, 2], targets: [3]),
            .init(moves: [.init(from: 1, to: 3)], destroy: [2], create: [])
        )
    }

    func testUnassignedAndDuplicateWindowsAreIgnored() {
        XCTAssertEqual(Policy.plan(windowDisplays: [0, 1, 1], targets: [1]), .init(moves: [], destroy: [], create: []))
    }

    // MARK: Overview detection

    func testOverviewWindowPredicate() {
        let screens = [CGSize(width: 1728, height: 1117), CGSize(width: 2560, height: 1440)]
        func isOverview(_ owner: String?, _ layer: Int?, alpha: Double? = nil, _ size: CGSize?) -> Bool {
            NotchHostWindowSizer.isOverviewWindow(owner: owner, layer: layer, alpha: alpha, size: size, screenSizes: screens)
        }
        XCTAssertTrue(isOverview("WindowManager", 19, CGSize(width: 1728, height: 1117)))
        XCTAssertTrue(isOverview("WindowManager", 19, CGSize(width: 2560, height: 1440)))
        XCTAssertFalse(isOverview("WindowManager", 19, CGSize(width: 220, height: 900)))
        XCTAssertFalse(isOverview("WindowManager", 14, CGSize(width: 1728, height: 128)))
        XCTAssertFalse(isOverview("Dock", 20, CGSize(width: 1728, height: 1117)))
        XCTAssertFalse(isOverview("WindowManager", -2147483624, CGSize(width: 1728, height: 1117)))
        XCTAssertFalse(isOverview("Finder", 19, CGSize(width: 1728, height: 1117)))
        XCTAssertFalse(isOverview(nil, 19, CGSize(width: 1728, height: 1117)))
        XCTAssertFalse(isOverview("WindowManager", 19, alpha: 0, CGSize(width: 1728, height: 1117)))
        XCTAssertFalse(isOverview("WindowManager", 19, nil))
    }

    // MARK: Pixel snapping

    func testCenteredWindowIsOnPixelsOnAnOddScaledMode() {
        let screen = CGRect(x: 0, y: 0, width: 1365, height: 768)
        let frame = NotchHostWindowSizer.centered(width: 296, height: 80, screenFrame: screen, scale: 1)
        XCTAssertEqual(frame.minX, frame.minX.rounded(), accuracy: 0.0001)
        XCTAssertEqual(frame.width.truncatingRemainder(dividingBy: 2), 0, accuracy: 0.0001)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
    }

    func testCenteredWindowNeverNarrowerThanAsked() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        for width in stride(from: CGFloat(200), through: 260, by: 0.25) {
            for scale in [CGFloat(1), 2] {
                let frame = NotchHostWindowSizer.centered(width: width, height: 80, screenFrame: screen, scale: scale)
                XCTAssertGreaterThanOrEqual(frame.width, width)
                XCTAssertEqual((frame.width * scale).truncatingRemainder(dividingBy: 2), 0, accuracy: 0.0001)
                XCTAssertEqual((frame.minX * scale), (frame.minX * scale).rounded(), accuracy: 0.0001)
            }
        }
    }

    func testStageAndWindowCentresAgree() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let window = NotchHostWindowSizer.centered(width: 297, height: 80, screenFrame: screen, scale: 2)
        let stage = NotchStageGeometry.stageFrame(
            containerSize: window.size,
            stageSize: CGSize(width: 1728, height: 470),
            backingScale: 2
        )
        XCTAssertEqual(window.minX + stage.midX, screen.midX, accuracy: 0.0001)
    }

    func testFittedAndFullWindowsPutTheNotchOnTheSamePixelsOnAnOdd1xMode() {
        let screen = CGRect(x: 0, y: 0, width: 1365, height: 768)
        let extent = NotchHostWindowExtent(
            isFull: false, notchSize: CGSize(width: 186, height: 24), notchTopOffset: 0,
            collapsedHeight: 24, fullBandInset: 0
        )
        let stage = NotchHostWindowSizer.stageSize(
            current: nil, extent: extent, windowSize: CGSize(width: 1365, height: 400),
            screenFrame: screen, visibleFrame: screen, scale: 1
        )
        XCTAssertEqual(stage.width.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertGreaterThanOrEqual(stage.width, 1365)
        func notchMinX(windowFrame: CGRect) -> CGFloat {
            let stageFrame = NotchStageGeometry.stageFrame(containerSize: windowFrame.size, stageSize: stage, backingScale: 1)
            return windowFrame.minX + stageFrame.minX + (stage.width - 186) / 2
        }
        let fitted = NotchHostWindowSizer.centered(width: 186 + 96, height: 80, screenFrame: screen, scale: 1)
        let full = CGRect(x: 0, y: 0, width: 1365, height: 400)
        XCTAssertEqual(notchMinX(windowFrame: fitted), notchMinX(windowFrame: full))
        XCTAssertEqual(notchMinX(windowFrame: fitted), notchMinX(windowFrame: fitted).rounded())
    }

    func testSnappedTargetsAreNeverSmaller() {
        let hover = CGSize(width: 204 * 1.1, height: 32 * 1.1)
        for scale in [CGFloat(1), 2] {
            let snapped = NotchDisplayMetrics.snappedSize(atLeast: hover, scale: scale)
            XCTAssertGreaterThanOrEqual(snapped.width, hover.width)
            XCTAssertGreaterThanOrEqual(snapped.height, hover.height)
            XCTAssertEqual((snapped.width * scale).truncatingRemainder(dividingBy: 2), 0, accuracy: 0.0001)
            XCTAssertEqual(snapped.height * scale, (snapped.height * scale).rounded(), accuracy: 0.0001)
        }
        XCTAssertEqual(NotchDisplayMetrics.snappedSize(atLeast: CGSize(width: 200, height: 32), scale: 2), CGSize(width: 200, height: 32))
    }
}