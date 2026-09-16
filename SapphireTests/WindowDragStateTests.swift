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

        state.beginDrag()
        XCTAssertTrue(state.isDragging)
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)

        state.dismissSnapZonesForCurrentDrag()
        XCTAssertTrue(state.isSnapZoneDismissedForCurrentDrag)

        state.endDrag()
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)

        state.beginDrag()
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)
        state.endDrag()
    }

    func testSnapZonesCannotBeDismissedOutsideAWindowDrag() {
        let state = WindowDragState.shared
        state.beginDrag()
        state.endDrag()

        state.dismissSnapZonesForCurrentDrag()

        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.isSnapZoneDismissedForCurrentDrag)
    }
}