//
//  MusicWidgetVisibilityTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import XCTest
@testable import Sapphire

final class MusicWidgetVisibilityTests: XCTestCase {
    private func shows(
        _ visibility: MusicWidgetVisibility,
        isEnabled: Bool = true,
        isPlaying: Bool = false,
        hasTrack: Bool = true,
        isClosedSpotifyOnlySource: Bool = false
    ) -> Bool {
        MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: isEnabled,
            visibility: visibility,
            isPlaying: isPlaying,
            hasTrack: hasTrack,
            isClosedSpotifyOnlySource: isClosedSpotifyOnlySource
        )
    }

    func testAlwaysShowsEvenWithNothingLoaded() {
        XCTAssertTrue(shows(.always, hasTrack: false))
        XCTAssertTrue(shows(.always, hasTrack: true, isClosedSpotifyOnlySource: true))
    }

    func testWhenSongLoadedShowsPausedSongsButNotAnEmptyPlayer() {
        XCTAssertTrue(shows(.whenSongLoaded, isPlaying: true))
        XCTAssertTrue(shows(.whenSongLoaded, isPlaying: false, hasTrack: true))
        XCTAssertFalse(shows(.whenSongLoaded, isPlaying: false, hasTrack: false))
    }

    func testWhenSongLoadedHidesTheLastSpotifyTrackAfterSpotifyQuits() {
        XCTAssertFalse(shows(.whenSongLoaded, isPlaying: false, hasTrack: true, isClosedSpotifyOnlySource: true))
        XCTAssertTrue(shows(.whenSongLoaded, isPlaying: true, hasTrack: true, isClosedSpotifyOnlySource: true))
    }

    func testWhilePlayingUsesPlaybackInsteadOfCachedTrackMetadata() {
        XCTAssertFalse(shows(.whilePlaying, isPlaying: false, hasTrack: true))
        XCTAssertTrue(shows(.whilePlaying, isPlaying: true))
    }

    func testDisabledWidgetNeverShows() {
        for visibility in MusicWidgetVisibility.allCases {
            XCTAssertFalse(shows(visibility, isEnabled: false, isPlaying: true))
        }
    }

    func testDefaultKeepsTheWidgetVisible() {
        XCTAssertEqual(Settings().musicWidgetVisibility, .always)
    }

    func testLegacyToggleCombinationsMigrateToOneChoice() throws {
        func migrated(_ legacy: [String: Bool]) throws -> MusicWidgetVisibility {
            var dictionary = try XCTUnwrap(SettingsPersistence.encodeToDictionary(Settings()))
            dictionary.removeValue(forKey: "musicWidgetVisibility")
            for (key, value) in legacy { dictionary[key] = value }
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            return try XCTUnwrap(SettingsPersistence.decodeFromPayload(data)).musicWidgetVisibility
        }

        XCTAssertEqual(try migrated([:]), .always)
        XCTAssertEqual(try migrated(["persistMusicWidgetWhenPaused": true]), .always)
        XCTAssertEqual(try migrated(["persistMusicWidgetWhenPaused": false]), .whenSongLoaded)
        XCTAssertEqual(try migrated(["hideSpotifyWidgetWhenAppClosed": true]), .whenSongLoaded)
        XCTAssertEqual(try migrated(["hideMusicWidgetWhenSpotifyPausedAndIdle": true]), .whilePlaying)
        XCTAssertEqual(try migrated(["hideMusicWidgetWhenNotPlaying": true, "persistMusicWidgetWhenPaused": false]), .whilePlaying)
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

    func testSpaceLimitCanBeBypassedForAnyWidget() {
        let widgets = WidgetLayoutPolicy.fittingWidgets(
            from: [.music, .weather, .calendar, .shortcuts, .agent],
            availableWidth: 1,
            showDividers: true,
            bypassSpaceLimit: true
        )

        XCTAssertEqual(widgets, [.music, .weather, .calendar, .shortcuts])
        XCTAssertTrue(WidgetLayoutPolicy.canFit(
            .calendar,
            in: [.music, .weather],
            availableWidth: 1,
            showDividers: true,
            bypassSpaceLimit: true
        ))
    }

    func testSpaceLimitBypassIsDisabledByDefault() {
        XCTAssertFalse(Settings().bypassWidgetSpaceLimit)
    }

    func testPhoneMediaLiveActivityIsEnabledByDefault() {
        XCTAssertTrue(Settings().continuityPhoneMediaLiveActivityEnabled)
    }

    func testPhoneMediaLyricsInLiveActivityAreDisabledByDefault() {
        XCTAssertFalse(Settings().continuityPhoneMediaLyricsInLiveActivity)
    }

    func testMusicLiveActivityChromeDefaultsFavorContinuityTextWithoutPhoneWaveform() {
        let settings = Settings()
        XCTAssertEqual(settings.musicLiveActivityRightTextMode, .continuityOnly)
        XCTAssertEqual(settings.musicLiveActivityWaveformMode, .continuityOff)
        XCTAssertEqual(settings.musicLiveActivityWaveformStyle, .classic)

        XCTAssertFalse(MusicLiveActivityChromePolicy.showsRightText(mode: settings.musicLiveActivityRightTextMode, isPhoneMedia: false))
        XCTAssertTrue(MusicLiveActivityChromePolicy.showsRightText(mode: settings.musicLiveActivityRightTextMode, isPhoneMedia: true))
        XCTAssertTrue(MusicLiveActivityChromePolicy.showsWaveform(mode: settings.musicLiveActivityWaveformMode, rightTextMode: settings.musicLiveActivityRightTextMode, isPhoneMedia: false))
        XCTAssertFalse(MusicLiveActivityChromePolicy.showsWaveform(mode: settings.musicLiveActivityWaveformMode, rightTextMode: settings.musicLiveActivityRightTextMode, isPhoneMedia: true))
    }

    func testWaveformOffIsClampedUnlessRightTextIsAlways() {
        XCTAssertEqual(
            MusicLiveActivityChromePolicy.resolvedWaveformMode(waveformMode: .off, rightTextMode: .continuityOnly),
            .continuityOff
        )
        XCTAssertEqual(
            MusicLiveActivityChromePolicy.resolvedWaveformMode(waveformMode: .off, rightTextMode: .always),
            .off
        )
        XCTAssertFalse(
            MusicLiveActivityChromePolicy.showsWaveform(mode: .off, rightTextMode: .always, isPhoneMedia: false)
        )
        XCTAssertTrue(
            MusicLiveActivityChromePolicy.showsRightText(mode: .always, isPhoneMedia: false)
        )
    }

    func testAndroidMediaStateAcceptsMissingOptionalCapabilities() throws {
        let data = Data(#"{"sessionId":"android-session","title":"Night Drive","isPlaying":true}"#.utf8)
        let state = try JSONDecoder().decode(ContinuityMediaState.self, from: data)

        XCTAssertEqual(state.sessionId, "android-session")
        XCTAssertEqual(state.title, "Night Drive")
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.positionMs, 0)
        XCTAssertEqual(state.durationMs, 0)
        XCTAssertFalse(state.canSeek)
    }
}