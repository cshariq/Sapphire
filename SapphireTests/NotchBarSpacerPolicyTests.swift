//
//  NotchBarSpacerPolicyTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import XCTest
@testable import Sapphire

final class NotchBarSpacerPolicyTests: XCTestCase {
    // MARK: - Sanitizing

    func testSanitizedWidthTreatsZeroAndNegativeAsAutomatic() {
        XCTAssertEqual(NotchBarSpacerPolicy.sanitizedWidth(0), NotchBarSpacerPolicy.automaticWidth)
        XCTAssertEqual(NotchBarSpacerPolicy.sanitizedWidth(-10), NotchBarSpacerPolicy.automaticWidth)
        XCTAssertEqual(NotchBarSpacerPolicy.sanitizedWidth(.nan), NotchBarSpacerPolicy.automaticWidth)
        XCTAssertEqual(NotchBarSpacerPolicy.sanitizedWidth(.infinity), NotchBarSpacerPolicy.automaticWidth)
    }

    func testSanitizedWidthClampsToUpperBound() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.sanitizedWidth(NotchBarSpacerPolicy.widthRange.upperBound + 500),
            NotchBarSpacerPolicy.widthRange.upperBound
        )
        XCTAssertEqual(NotchBarSpacerPolicy.sanitizedWidth(120), 120)
    }

    // MARK: - Fixed vs automatic detection

    func testHasFixedWidthOnlyForPositiveConfigurations() {
        XCTAssertFalse(NotchBarSpacerPolicy.hasFixedWidth(0))
        XCTAssertFalse(NotchBarSpacerPolicy.hasFixedWidth(-5))
        XCTAssertTrue(NotchBarSpacerPolicy.hasFixedWidth(1))
        XCTAssertTrue(NotchBarSpacerPolicy.hasFixedWidth(200))
    }

    // MARK: - Minimum bar width

    func testMinimumBarWidthInAutomaticModeIsJustItems() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.minimumBarWidth(configuredWidth: 0, itemsWidth: 300),
            300
        )
    }

    func testMinimumBarWidthIncludesFixedSpacer() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.minimumBarWidth(configuredWidth: 60, itemsWidth: 300),
            360
        )
    }

    // MARK: - Resolved spacer width

    func testAutomaticSpacerFillsRemainingBarWidth() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 0, barWidth: 500, itemsWidth: 300),
            200
        )
    }

    func testAutomaticSpacerNeverGoesNegativeWhenItemsOverflowBar() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 0, barWidth: 200, itemsWidth: 300),
            0
        )
    }

    func testFixedSpacerIsHonoredWhenBarIsWideEnough() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 60, barWidth: 500, itemsWidth: 300),
            60
        )
    }

    func testFixedSpacerKeepsBarCompactInsteadOfStretching() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 60, barWidth: 800, itemsWidth: 300),
            60
        )
    }

    // MARK: - Notch floor

    func testMinimumBarWidthReservesTheNotchInAutomaticMode() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.minimumBarWidth(configuredWidth: 0, itemsWidth: 300, minimumSpacerWidth: 200),
            500
        )
    }

    func testMinimumBarWidthUsesTheLargerOfFixedSpacerAndNotch() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.minimumBarWidth(configuredWidth: 60, itemsWidth: 300, minimumSpacerWidth: 200),
            500
        )
        XCTAssertEqual(
            NotchBarSpacerPolicy.minimumBarWidth(configuredWidth: 260, itemsWidth: 300, minimumSpacerWidth: 200),
            560
        )
    }

    func testResolvedSpacerNeverGoesBelowTheNotch() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 0, barWidth: 320, itemsWidth: 300, minimumSpacerWidth: 200),
            200
        )
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 60, barWidth: 800, itemsWidth: 300, minimumSpacerWidth: 200),
            200
        )
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 0, barWidth: 800, itemsWidth: 300, minimumSpacerWidth: 200),
            500
        )
    }

    func testInvalidNotchFloorIsIgnored() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.minimumBarWidth(configuredWidth: 0, itemsWidth: 300, minimumSpacerWidth: .nan),
            300
        )
        XCTAssertEqual(
            NotchBarSpacerPolicy.minimumBarWidth(configuredWidth: 0, itemsWidth: 300, minimumSpacerWidth: -50),
            300
        )
    }

    func testSymmetricItemsWidthReservesTheWiderSideTwice() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.symmetricItemsWidth(leading: 120, trailing: 40, inset: 40),
            320
        )
        XCTAssertEqual(
            NotchBarSpacerPolicy.symmetricItemsWidth(leading: 0, trailing: 0, inset: 40),
            80
        )
    }

    func testFixedSpacerShrinksWhenBarCannotFitItemsAndGap() {
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 60, barWidth: 340, itemsWidth: 300),
            40
        )
        XCTAssertEqual(
            NotchBarSpacerPolicy.resolvedSpacerWidth(configuredWidth: 60, barWidth: 200, itemsWidth: 300),
            0
        )
    }
}