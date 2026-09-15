//
//  FullScreenDisplayResolverTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import CoreGraphics
import Foundation
import XCTest
@testable import Sapphire

final class FullScreenDisplayResolverTests: XCTestCase {
    private typealias Resolver = FullScreenDisplayResolver

    private let builtIn = Resolver.Display(
        id: 1,
        uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
        bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        isMain: true
    )
    private let external = Resolver.Display(
        id: 2,
        uuid: "A1B2C3D4-0000-4000-8000-000000000002",
        bounds: CGRect(x: 1728, y: 0, width: 2560, height: 1440),
        isMain: false
    )
    private let ownPID: pid_t = 999

    // MARK: Native Spaces

    func testNativeFullScreenIsScopedToTheDisplayShowingIt() {
        let spaces = [
            spaceEntry(builtIn.uuid!.lowercased(), currentType: 0),
            spaceEntry(external.uuid!, currentType: 4)
        ]

        XCTAssertEqual(
            Resolver.nativeFullScreenDisplays(displays: [builtIn, external], managedDisplaySpaces: spaces),
            [2]
        )
    }

    func testSpanningMainSpaceAppliesToEveryDisplay() {
        XCTAssertEqual(
            Resolver.nativeFullScreenDisplays(
                displays: [builtIn, external],
                managedDisplaySpaces: [spaceEntry("Main", currentType: 4)]
            ),
            [1, 2]
        )
    }

    func testCurrentSpaceFallsBackToIsCurrentFlag() {
        let spaces: [[String: Any]] = [[
            "Display Identifier": builtIn.uuid!,
            "Spaces": [
                ["type": NSNumber(value: 0)],
                ["type": NSNumber(value: 4), "is-current": true]
            ]
        ]]

        XCTAssertEqual(Resolver.nativeFullScreenDisplays(displays: [builtIn], managedDisplaySpaces: spaces), [1])
    }

    func testUnmatchedDisplaysAreNotFullScreen() {
        let spaces = [
            spaceEntry("FFFFFFFF-0000-4000-8000-000000000000", currentType: 4),
            spaceEntry("EEEEEEEE-0000-4000-8000-000000000000", currentType: 4)
        ]

        XCTAssertEqual(
            Resolver.nativeFullScreenDisplays(displays: [builtIn, external], managedDisplaySpaces: spaces),
            []
        )
    }

    // MARK: Borderless windows

    func testBorderlessWindowIsFullScreenOnlyOnTheDisplayItCovers() {
        XCTAssertEqual(
            Resolver.borderlessFullScreenDisplays(
                displays: [builtIn, external],
                windows: [window(external.bounds)],
                ownPID: ownPID
            ),
            [2]
        )
    }

    func testMaximizedWindowBelowTheMenuBarIsNotFullScreen() {
        XCTAssertEqual(
            Resolver.borderlessFullScreenDisplays(
                displays: [builtIn],
                windows: [window(CGRect(x: 0, y: 33, width: 1728, height: 1084))],
                ownPID: ownPID
            ),
            []
        )
    }

    func testLargeWindowInFrontCancelsBorderlessFullScreen() {
        let windows = [
            window(CGRect(x: 0, y: 33, width: 1728, height: 1084), pid: 7),
            window(builtIn.bounds, pid: 8)
        ]

        XCTAssertEqual(
            Resolver.borderlessFullScreenDisplays(displays: [builtIn], windows: windows, ownPID: ownPID),
            []
        )
    }

    func testSmallFloatingWindowDoesNotCancelBorderlessFullScreen() {
        let windows = [
            window(CGRect(x: 100, y: 100, width: 300, height: 200), pid: 7),
            window(builtIn.bounds, pid: 8)
        ]

        XCTAssertEqual(
            Resolver.borderlessFullScreenDisplays(displays: [builtIn], windows: windows, ownPID: ownPID),
            [1]
        )
    }

    func testOwnTransparentAndOverlayWindowsAreIgnored() {
        let windows = [
            window(builtIn.bounds, pid: ownPID),
            window(builtIn.bounds, alpha: 0),
            window(builtIn.bounds, layer: 25)
        ]

        XCTAssertEqual(
            Resolver.borderlessFullScreenDisplays(displays: [builtIn], windows: windows, ownPID: ownPID),
            []
        )
    }

    // MARK: Helpers

    private func spaceEntry(_ identifier: String, currentType: Int) -> [String: Any] {
        [
            "Display Identifier": identifier,
            "Current Space": ["ManagedSpaceID": NSNumber(value: 7), "type": NSNumber(value: currentType)]
        ]
    }

    private func window(_ bounds: CGRect, pid: pid_t = 42, layer: Int = 0, alpha: Double = 1) -> Resolver.Window {
        Resolver.Window(layer: layer, ownerPID: pid, alpha: alpha, bounds: bounds)
    }
}