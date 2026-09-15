//
//  MusicWidgetVisibilityTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import XCTest
@testable import Sapphire

final class MusicWidgetVisibilityTests: XCTestCase {
    func testHideWhenNotPlayingUsesPlaybackInsteadOfCachedTrackMetadata() {
        XCTAssertFalse(MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: true,
            hideWhenNotPlaying: true,
            isPlaying: false,
            hidePausedSpotifyWhenIdle: false,
            isSpotifyPausedWithNoOtherPlayback: false
        ))

        XCTAssertTrue(MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: true,
            hideWhenNotPlaying: true,
            isPlaying: true,
            hidePausedSpotifyWhenIdle: false,
            isSpotifyPausedWithNoOtherPlayback: false
        ))
    }

    func testPausedSpotifyRuleCanHideWithoutGeneralPlaybackRule() {
        XCTAssertFalse(MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: true,
            hideWhenNotPlaying: false,
            isPlaying: false,
            hidePausedSpotifyWhenIdle: true,
            isSpotifyPausedWithNoOtherPlayback: true
        ))
    }

    func testDisabledWidgetNeverShows() {
        XCTAssertFalse(MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: false,
            hideWhenNotPlaying: false,
            isPlaying: true,
            hidePausedSpotifyWhenIdle: false,
            isSpotifyPausedWithNoOtherPlayback: false
        ))
    }

    func testLayoutKeepsLookingForSmallerWidgetsAfterOneDoesNotFit() {
        let widgets = WidgetLayoutPolicy.fittingWidgets(
            from: [.weather, .calendar, .shortcuts],
            availableWidth: 350,
            showDividers: false
        )

        XCTAssertEqual(widgets, [.weather, .shortcuts])
    }

    func testSmallerWidgetCanBeEnabledAfterAnOversizedCandidate() {
        XCTAssertTrue(WidgetLayoutPolicy.canFit(
            .shortcuts,
            in: [.weather, .calendar],
            availableWidth: 350,
            showDividers: false
        ))
    }

    func testMusicDoesNotConsumeSupplementaryWidgetCapacity() {
        let widgets = WidgetLayoutPolicy.fittingWidgets(
            from: [.music, .weather, .sports, .shortcuts],
            availableWidth: 450,
            showDividers: false
        )

        XCTAssertEqual(WidgetLayoutPolicy.capacityWidth(for: .music), 0)
        XCTAssertEqual(widgets, [.music, .weather, .sports])
    }
}