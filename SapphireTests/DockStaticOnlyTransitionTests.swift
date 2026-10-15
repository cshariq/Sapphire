//
//  DockStaticOnlyTransitionTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import XCTest
@testable import Sapphire

final class DockStaticOnlyTransitionTests: XCTestCase {
    func testEnablingStaticOnlySuppressesSuggestedAppsWhenTheyAreVisible() {
        XCTAssertTrue(
            DockStaticOnlyTransitionPolicy.shouldSuppressSuggestedApps(
                enabled: true,
                showRecents: true,
                suppressionWasStored: false
            )
        )
    }

    func testEnablingStaticOnlyDoesNotRewriteDisabledSuggestedApps() {
        XCTAssertFalse(
            DockStaticOnlyTransitionPolicy.shouldSuppressSuggestedApps(
                enabled: true,
                showRecents: false,
                suppressionWasStored: false
            )
        )
    }

    func testDisablingStaticOnlyRestoresOnlyAppsSuppressedBySapphire() {
        XCTAssertTrue(
            DockStaticOnlyTransitionPolicy.shouldRestoreSuggestedApps(
                enabled: false,
                suppressionWasStored: true
            )
        )
        XCTAssertFalse(
            DockStaticOnlyTransitionPolicy.shouldRestoreSuggestedApps(
                enabled: false,
                suppressionWasStored: false
            )
        )
        XCTAssertFalse(
            DockStaticOnlyTransitionPolicy.shouldRestoreSuggestedApps(
                enabled: true,
                suppressionWasStored: true
            )
        )
    }
}