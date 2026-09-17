//
//  WindowDragStateTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import XCTest
@testable import Sapphire

@MainActor
final class WindowDragStateTests: XCTestCase {
    func testSnapZoneDismissalLastsUntilTheWindowDragEnds() {
        let state = WindowDragState.shared
        state.endDrag()

        state.beginDrag(bypassModifierIsPressed: false)
        XCTAssertTrue(state.isDragging)
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)

        state.dismissSnapZonesForCurrentDrag()
        XCTAssertTrue(state.isSnapZoneDismissedForCurrentDrag)

        state.endDrag()
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)

        state.beginDrag(bypassModifierIsPressed: false)
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)
        state.endDrag()
    }

    func testSnapZonesCannotBeDismissedOutsideAWindowDrag() {
        let state = WindowDragState.shared
        state.beginDrag(bypassModifierIsPressed: false)
        state.endDrag()

        state.dismissSnapZonesForCurrentDrag()

        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)
    }

    func testCommandBypassModifierIsScopedToTheCurrentWindowDrag() {
        let state = WindowDragState.shared
        state.endDrag()

        state.setSnapZoneBypassModifierPressed(true)
        XCTAssertFalse(state.isSnapZoneBypassModifierPressed)

        state.beginDrag(bypassModifierIsPressed: true)
        XCTAssertTrue(state.isSnapZoneBypassModifierPressed)

        state.setSnapZoneBypassModifierPressed(false)
        XCTAssertFalse(state.isSnapZoneBypassModifierPressed)

        state.setSnapZoneBypassModifierPressed(true)
        state.endDrag()
        XCTAssertFalse(state.isSnapZoneBypassModifierPressed)
    }
}