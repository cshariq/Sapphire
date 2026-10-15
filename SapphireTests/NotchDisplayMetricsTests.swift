//
//  NotchDisplayMetricsTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import XCTest
@testable import Sapphire

@MainActor
final class NotchDisplayMetricsTests: XCTestCase {
    private let notched = NotchDisplayMetrics.Input(
        displayID: 1,
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1084),
        safeAreaTop: 32,
        leftArea: CGRect(x: 0, y: 1085, width: 771.5, height: 32),
        rightArea: CGRect(x: 956.5, y: 1085, width: 771.5, height: 32),
        scale: 2
    )

    private func external(
        id: CGDirectDisplayID = 2,
        frame: CGRect = CGRect(x: 1728, y: 0, width: 2560, height: 1440),
        menuBarGap: CGFloat = 25,
        dockHeight: CGFloat = 0,
        scale: CGFloat = 1
    ) -> NotchDisplayMetrics.Input {
        NotchDisplayMetrics.Input(
            displayID: id,
            frame: frame,
            visibleFrame: CGRect(
                x: frame.minX,
                y: frame.minY + dockHeight,
                width: frame.width,
                height: frame.height - menuBarGap - dockHeight
            ),
            scale: scale
        )
    }

    private func resolve(_ input: NotchDisplayMetrics.Input, cache: MenuBarHeightCache = MenuBarHeightCache(), thickness: CGFloat = 22) -> NotchDisplayMetrics {
        NotchDisplayMetrics.resolve(input, cache: cache, statusBarThickness: thickness)
    }

    // MARK: Height

    func testNotchedDisplayUsesTheSafeAreaAndCameraWidth() {
        let metrics = resolve(notched)
        XCTAssertEqual(metrics.cameraWidth, 185)
        XCTAssertEqual(metrics.closedSize.height, 32)
        XCTAssertEqual(metrics.closedSize.width, 189)
    }

    func testNotchedDisplayKeepsItsHeightWithTheMenuBarHidden() {
        var hidden = notched
        hidden.visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertEqual(resolve(hidden).closedSize.height, 32)
    }

    func testNotchlessHeightIsTheMenuBarWithoutItsSeparator() {
        XCTAssertEqual(resolve(external()).menuBarHeight, 24)
    }

    func testABottomDockIsNotMenuBar() {
        let metrics = resolve(external(dockHeight: 70))
        XCTAssertEqual(metrics.menuBarHeight, 24)
        XCTAssertEqual(NotchDisplayMetrics.menuBarGap(
            frame: CGRect(x: 0, y: 0, width: 100, height: 1000),
            visibleFrame: CGRect(x: 0, y: 70, width: 100, height: 905)
        ), 25)
    }

    func testHiddenMenuBarKeepsTheLastGoodHeightForThatMode() {
        let cache = MenuBarHeightCache()
        XCTAssertEqual(resolve(external(menuBarGap: 31), cache: cache).menuBarHeight, 30)
        XCTAssertEqual(resolve(external(menuBarGap: 0), cache: cache).menuBarHeight, 30)
        let otherMode = external(frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080), menuBarGap: 0)
        XCTAssertEqual(resolve(otherMode, cache: cache).menuBarHeight, 24)
    }

    func testImplausibleGapFallsBackToStatusBarThicknessOnlyWhenLarger() {
        XCTAssertEqual(resolve(external(menuBarGap: 200), thickness: 22).menuBarHeight, 24)
        XCTAssertEqual(resolve(external(menuBarGap: 0), thickness: 28).menuBarHeight, 28)
    }

    // MARK: Width

    func testNotchlessWidthComesFromTheBarHeight() {
        XCTAssertEqual(resolve(external()).closedSize.width, 150)
        let builtInAir = external(id: 3, frame: CGRect(x: 0, y: 0, width: 1470, height: 956), scale: 2)
        XCTAssertEqual(resolve(builtInAir).closedSize.width, 150)
    }

    // MARK: Pixel snapping

    func testSnapping() {
        XCTAssertEqual(NotchDisplayMetrics.snapToPixel(31.8, scale: 2), 32)
        XCTAssertEqual(NotchDisplayMetrics.snapToPixel(23.3, scale: 2), 23.5)
        XCTAssertEqual(NotchDisplayMetrics.snapToPixel(23.3, scale: 1), 23)
        XCTAssertEqual(NotchDisplayMetrics.snapToEvenPixels(151, scale: 1), 152)
        XCTAssertEqual(NotchDisplayMetrics.snapToEvenPixels(150.7, scale: 2), 151)
        let width = NotchDisplayMetrics.snapToEvenPixels(187.3, scale: 2)
        let x = NotchDisplayMetrics.centeredOriginX(width: width, midX: 864, scale: 2)
        XCTAssertEqual(x * 2, (x * 2).rounded())
        XCTAssertEqual((x + width) * 2, ((x + width) * 2).rounded())
        XCTAssertEqual(x + width / 2, 864)
        XCTAssertEqual(
            NotchDisplayMetrics.snappedSize(CGSize(width: 300.3, height: 80.2), scale: 2),
            CGSize(width: 300, height: 80)
        )
    }

    // MARK: Custom sizes

    func testCustomSizeCannotUncoverTheCamera() {
        let metrics = resolve(notched)
        let size = NotchDisplayMetrics.resolvedClosedSize(
            measured: metrics, customWidth: 120, customHeight: 20,
            isFloatingIsland: false, floatingIslandMinimumHeight: 32
        )
        XCTAssertEqual(size, CGSize(width: 189, height: 32))
        let wider = NotchDisplayMetrics.resolvedClosedSize(
            measured: metrics, customWidth: 240, customHeight: 40,
            isFloatingIsland: false, floatingIslandMinimumHeight: 32
        )
        XCTAssertEqual(wider, CGSize(width: 240, height: 40))
    }

    func testFloatingIslandIsALittleTallerThanTheMenuBarAtDynamicIslandProportions() {
        let metrics = resolve(external(menuBarGap: 30, scale: 2))
        let size = NotchDisplayMetrics.resolvedClosedSize(
            measured: metrics, customWidth: 0, customHeight: 0,
            isFloatingIsland: true, floatingIslandMinimumHeight: 30
        )
        XCTAssertEqual(size, CGSize(width: 109, height: 31))
        let customWidth = NotchDisplayMetrics.resolvedClosedSize(
            measured: metrics, customWidth: 200, customHeight: 0,
            isFloatingIsland: true, floatingIslandMinimumHeight: 30
        )
        XCTAssertEqual(customWidth, CGSize(width: 200, height: 31))
    }

    func testFloatingIslandMinimumAppliesAfterTheOverride() {
        let metrics = resolve(external())
        let size = NotchDisplayMetrics.resolvedClosedSize(
            measured: metrics, customWidth: 0, customHeight: 20,
            isFloatingIsland: true, floatingIslandMinimumHeight: 30
        )
        XCTAssertEqual(size, CGSize(width: 106, height: 30))
        let notIsland = NotchDisplayMetrics.resolvedClosedSize(
            measured: metrics, customWidth: 100, customHeight: 20,
            isFloatingIsland: false, floatingIslandMinimumHeight: 32
        )
        XCTAssertEqual(notIsland, CGSize(width: 100, height: 20))
    }

    func testFloatingIslandTopInsetCentresOnlyInATallerBar() {
        XCTAssertEqual(NotchDisplayMetrics.floatingIslandTopInset(userOffset: 8, islandHeight: 32, menuBarHeight: 24, scale: 2), 8)
        XCTAssertEqual(NotchDisplayMetrics.floatingIslandTopInset(userOffset: 0, islandHeight: 32, menuBarHeight: 37, scale: 2), 0)
        XCTAssertEqual(NotchDisplayMetrics.floatingIslandTopInset(userOffset: 8.3, islandHeight: 32, menuBarHeight: 24, scale: 2), 8.5)
        XCTAssertEqual(NotchDisplayMetrics.floatingIslandTopInset(userOffset: -4, islandHeight: 32, menuBarHeight: 24, scale: 2), 0)
    }

    // MARK: Pointer → display

    func testStackedDisplaysBoundaryBelongsToTheLowerDisplay() {
        let frames: [(id: CGDirectDisplayID, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 1117, width: 2560, height: 1440)),
            (2, CGRect(x: 0, y: 0, width: 1728, height: 1117))
        ]
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 800, y: 1117), in: frames), 2)
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 800, y: 1117.5), in: frames), 1)
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 800, y: 2557), in: frames), 1)
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 800, y: 0), in: frames), 2)
    }

    func testSideBySideBoundaryBelongsToTheRightDisplay() {
        let frames: [(id: CGDirectDisplayID, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 1728, height: 1117)),
            (2, CGRect(x: 1728, y: 0, width: 2560, height: 1440))
        ]
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 1728, y: 1117), in: frames), 2)
        XCTAssertEqual(NotchDisplayTargeting.display(containing: CGPoint(x: 1727.5, y: 1117), in: frames), 1)
    }

    // MARK: Per-display settings keys

    func testDisplaysWithSerialsKeepTheirKeys() {
        XCTAssertEqual(DisplaySettingsKey.key(vendor: 1552, model: 41000, serial: 77, uuid: "ABC", displayID: 1), "v1552-m41000-s77")
        XCTAssertEqual(DisplaySettingsKey.key(vendor: nil, model: nil, serial: nil, uuid: "ABC", displayID: 9), "id-9")
    }

    func testIdenticalSerialLessMonitorsGetDistinctKeysAndReadTheOldOne() {
        let left = DisplaySettingsKey.key(vendor: 4268, model: 1234, serial: nil, uuid: "AAAA-1", displayID: 3)
        let right = DisplaySettingsKey.key(vendor: 4268, model: 1234, serial: nil, uuid: "BBBB-2", displayID: 4)
        XCTAssertNotEqual(left, right)
        XCTAssertEqual(DisplaySettingsKey.legacyKey(for: left), "v4268-m1234")
        XCTAssertNil(DisplaySettingsKey.legacyKey(for: "v1552-m41000-s77"))
        XCTAssertNil(DisplaySettingsKey.legacyKey(for: "id-9"))

        var stored = ["v4268-m1234": 10]
        XCTAssertEqual(DisplaySettingsKey.value(in: stored, for: left), 10)
        stored[right] = 20
        XCTAssertEqual(DisplaySettingsKey.value(in: stored, for: right), 20)
        XCTAssertEqual(DisplaySettingsKey.value(in: stored, for: left), 10)
        XCTAssertNil(DisplaySettingsKey.value(in: stored, for: nil))
    }

    func testPerDisplayNotchSizeReadsTheLegacyKey() {
        var settings = Settings()
        settings.perDisplayNotchSize["v4268-m1234"] = NotchSizeOverride(width: 222, height: 0)
        let key = DisplaySettingsKey.key(vendor: 4268, model: 1234, serial: nil, uuid: "AAAA-1", displayID: 3)
        XCTAssertEqual(settings.resolvedNotchWidth(forDisplayID: key), 222)
    }

    // MARK: Widget fitting

    func testWidgetRowWidthFollowsTheNotchDisplay() {
        XCTAssertEqual(WidgetLayoutPolicy.availableBarWidth(forScreenWidth: 2560), 2560 * 0.72 - 140)
        XCTAssertEqual(WidgetLayoutPolicy.availableBarWidth(notchDisplayWidth: 600), 360)
    }

    func testResettingOneIdenticalMonitorKeepsItsTwinsValue() {
        let left = DisplaySettingsKey.key(vendor: 4268, model: 1234, serial: nil, uuid: "AAAA-1", displayID: 3)
        let right = DisplaySettingsKey.key(vendor: 4268, model: 1234, serial: nil, uuid: "BBBB-2", displayID: 4)
        var stored = ["v4268-m1234": 10]
        DisplaySettingsKey.removeValue(from: &stored, for: left, connectedKeys: [left, right])
        XCTAssertNil(DisplaySettingsKey.value(in: stored, for: left))
        XCTAssertEqual(DisplaySettingsKey.value(in: stored, for: right), 10)
        stored = ["v4268-m1234": 10, right: 20]
        DisplaySettingsKey.removeValue(from: &stored, for: left, connectedKeys: [left, right])
        XCTAssertEqual(stored, [right: 20])
    }
}