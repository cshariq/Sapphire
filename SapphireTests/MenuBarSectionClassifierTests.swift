//
//  MenuBarSectionClassifierTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import ApplicationServices
import XCTest
@testable import Sapphire

final class MenuBarSectionClassifierTests: XCTestCase {
    private typealias Placement = MenuBarSectionClassifier.Placement

    func testItemsAreClassifiedByDividerPositions() {
        let result = MenuBarSectionClassifier.classify(
            [
                Placement(key: "com.example.far", midX: 900),
                Placement(key: "com.example.middle", midX: 1100),
                Placement(key: "com.example.near", midX: 1300),
            ],
            hiddenDividerMidX: 1200,
            alwaysHiddenDividerMidX: 1000
        )
        XCTAssertEqual(result, [
            "com.example.far": .alwaysHidden,
            "com.example.middle": .hidden,
            "com.example.near": .shown,
        ])
    }

    func testNothingIsLearnedWithoutTheHiddenDivider() {
        let result = MenuBarSectionClassifier.classify(
            [Placement(key: "com.example.app", midX: 100)],
            hiddenDividerMidX: nil,
            alwaysHiddenDividerMidX: 50
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testWithoutAlwaysHiddenDividerEverythingLeftIsHidden() {
        let result = MenuBarSectionClassifier.classify(
            [Placement(key: "com.example.app", midX: 100)],
            hiddenDividerMidX: 500,
            alwaysHiddenDividerMidX: nil
        )
        XCTAssertEqual(result, ["com.example.app": .hidden])
    }

    func testAnAppStraddlingADividerTakesItsMostVisibleSection() {
        let result = MenuBarSectionClassifier.classify(
            [
                Placement(key: "com.example.stats", midX: 1100),
                Placement(key: "com.example.stats", midX: 1300),
                Placement(key: "com.example.stats", midX: 900),
            ],
            hiddenDividerMidX: 1200,
            alwaysHiddenDividerMidX: 1000
        )
        XCTAssertEqual(result, ["com.example.stats": .shown])
    }

    func testSystemItemsMapFromMenuExtraIdentifiers() {
        XCTAssertEqual(MenuBarSystemItem(menuExtraIdentifier: "com.apple.menuextra.clock"), .clock)
        XCTAssertEqual(MenuBarSystemItem(menuExtraIdentifier: "com.apple.menuextra.controlcenter"), .controlCenter)
        XCTAssertEqual(MenuBarSystemItem(menuExtraIdentifier: "com.apple.menuextra.wifi"), .wifi)
        XCTAssertEqual(MenuBarSystemItem(menuExtraIdentifier: "com.apple.menuextra.battery"), .battery)
        XCTAssertNil(MenuBarSystemItem(menuExtraIdentifier: "com.apple.menuextra.focusmode"))
    }

    func testSystemItemRawValuesMatchMenuBarAgent() {
        XCTAssertEqual(MenuBarSystemItem.battery.rawValue, 0)
        XCTAssertEqual(MenuBarSystemItem.clock.rawValue, 2)
        XCTAssertEqual(MenuBarSystemItem.controlCenter.rawValue, 8)
        XCTAssertEqual(MenuBarSystemItem.allCases.count, 9)
    }

    func testPrimaryActionEncodingCheck() {
        XCTAssertTrue(MenuBarAgentHost.isSupportedAddTargetEncoding("v40@0:8@16:24Q32"))
        XCTAssertTrue(MenuBarAgentHost.isSupportedAddTargetEncoding("v@:@:Q"))
        XCTAssertFalse(MenuBarAgentHost.isSupportedAddTargetEncoding("v32@0:8@16:24"))
    }

    func testOverflowedItemsUnderAWiderItemAreNotOnTheBar() {
        let element = AXUIElementCreateApplication(getpid())
        func item(_ x: CGFloat, _ width: CGFloat) -> MenuBarAgentHost.DrawnItem {
            .init(ownerPID: 1, frame: CGRect(x: x, y: 0, width: width, height: 33), systemIdentifier: nil, ownIdentifier: nil, element: element)
        }
        let divider = item(780, 571)
        let overflowed = item(1329, 22)
        let shown = item(1413, 54)
        XCTAssertEqual(MenuBarAgentHost.onBar([divider, overflowed, shown]), [divider, shown])
    }
}