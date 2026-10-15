//
//  SettingsIndexTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26

import XCTest
@testable import Sapphire

final class SettingsIndexTests: XCTestCase {
    func testSearchFindsSettingsByTheirUITitles() {
        XCTAssertTrue(SettingsIndex.search("full screen activity visibility").contains { $0.key == "fullScreenActivityVisibility" })
        XCTAssertTrue(SettingsIndex.search("music waveform bars").contains { $0.key == "waveformBarCount" })
        XCTAssertTrue(SettingsIndex.search("low battery notification").contains { $0.key == "lowBatteryNotificationPercentage" })
    }

    func testIndexNeverListsCredentials() {
        let leaked = SettingsIndex.entries.filter { $0.key.range(of: "token|secret|password|apikey", options: [.regularExpression, .caseInsensitive]) != nil }
        XCTAssertEqual(leaked.map(\.key), [])
    }

    func testTogglesABoolFromNaturalWords() throws {
        var settings = Settings()
        settings.hideNotchInFullScreen = false
        let (updated, change) = try SettingsIndex.applying(key: "hideNotchInFullScreen", rawValue: "on", to: settings).get()
        XCTAssertTrue(updated.hideNotchInFullScreen)
        XCTAssertEqual(change.oldValue, .bool(false))
        XCTAssertEqual(change.newValue, .bool(true))
    }

    func testClampsNumbersToTheUIRange() throws {
        let (updated, _) = try SettingsIndex.applying(key: "waveformBarCount", rawValue: "12", to: Settings()).get()
        XCTAssertEqual(updated.waveformBarCount, 6)
    }

    func testKeepsDecimalsForDecimalSettings() throws {
        var settings = Settings()
        settings.waveformBarThickness = 4.0
        let (updated, _) = try SettingsIndex.applying(key: "waveformBarThickness", rawValue: "2.5", to: settings).get()
        XCTAssertEqual(updated.waveformBarThickness, 2.5, accuracy: 0.001)
    }

    func testRoundsForWholeNumberSettings() throws {
        let (updated, _) = try SettingsIndex.applying(key: "lowBatteryNotificationPercentage", rawValue: "15.6", to: Settings()).get()
        XCTAssertEqual(updated.lowBatteryNotificationPercentage, 16)
    }

    func testAcceptsOnlyKnownChoices() throws {
        let (updated, _) = try SettingsIndex.applying(key: "musicLiveActivityWaveformStyle", rawValue: "Continuity", to: Settings()).get()
        XCTAssertEqual(updated.musicLiveActivityWaveformStyle, .continuity)
        XCTAssertThrowsError(try SettingsIndex.applying(key: "musicLiveActivityWaveformStyle", rawValue: "sparkly", to: Settings()).get())
    }

    func testRejectsUnknownKeysAndBadValues() {
        XCTAssertThrowsError(try SettingsIndex.applying(key: "notARealSetting", rawValue: "on", to: Settings()).get())
        XCTAssertThrowsError(try SettingsIndex.applying(key: "hideNotchInFullScreen", rawValue: "maybe", to: Settings()).get())
    }

    func testChangingOneSettingLeavesTheRestAlone() throws {
        let original = Settings()
        var (updated, _) = try SettingsIndex.applying(key: "hideNotchWhenInactive", rawValue: "on", to: original).get()
        updated.hideNotchWhenInactive = original.hideNotchWhenInactive
        let differing = SettingsField.all.filter { $0.differs(original, updated) }.map { String(describing: $0.keyPath) }
        XCTAssertEqual(differing, [])
    }

    func testUndoRestoresTheOldValue() throws {
        let original = Settings()
        let (changed, change) = try SettingsIndex.applying(key: "waveformBarCount", rawValue: "5", to: original).get()
        let (restored, _) = try SettingsIndex.applying(key: change.entry.key, rawValue: change.oldValue.description, to: changed).get()
        XCTAssertEqual(restored.waveformBarCount, original.waveformBarCount)
    }

    func testSearchFindsSettingsFromEverydayQuestions() {
        let expectations: [(String, Set<String>)] = [
            ("Can I hide the notch when I'm in a full screen app?", ["hideNotchInFullScreen"]),
            ("How do I make the notch smaller?", ["notchWidth", "notchHeight"]),
            ("Make it start when I log in", ["launchAtLogin"]),
            ("Show the weather in Fahrenheit", ["weatherUseCelsius"]),
            ("Can I see my CPU usage in the menu bar?", ["monitoringReadoutShowCPU"]),
            ("How do I stop Sapphire from showing the volume popup?", ["enableVolumeHUD"]),
            ("Can Sapphire unzip files automatically?", ["archiveExtractorEnabled"]),
            ("Show notifications from iMessage in the notch", ["iMessageNotificationsEnabled"]),
            ("how many clipboard items are kept", ["clipboardHistoryLimit"]),
        ]
        for (question, expected) in expectations {
            let found = Set(SettingsIndex.search(question, limit: 8).map(\.key))
            XCTAssertFalse(found.isDisjoint(with: expected), "\(question) -> \(found.sorted())")
        }
    }

    func testSearchMatchesWordStartsNotFragments() {
        let found = SettingsIndex.search("save battery", limit: 8).map(\.key)
        XCTAssertFalse(found.contains("bluetoothUnlockUseScreensaver"))
    }

    func testNotchSizeChangeAppliesToEveryDisplay() throws {
        var original = Settings()
        original.perDisplayNotchSize = ["display-a": NotchSizeOverride(width: 220, height: 32)]
        original.perDisplayFullScreenBehavior = ["display-a": FullScreenBehavior(hideNotch: false)]
        let (wider, _) = try SettingsIndex.applying(key: "notchWidth", rawValue: "260", to: original).get()
        XCTAssertEqual(wider.perDisplayNotchSize["display-a"]?.width, 260)
        XCTAssertEqual(wider.perDisplayNotchSize["display-a"]?.height, 32)
        let (hidden, _) = try SettingsIndex.applying(key: "hideNotchInFullScreen", rawValue: "on", to: original).get()
        XCTAssertEqual(hidden.perDisplayFullScreenBehavior["display-a"]?.hideNotch, true)
    }

    func testQuestionsNeverReadAsChangeRequests() {
        for question in ["Can I hide the notch in full screen?", "How do I turn on lyrics", "Is there a dark mode", "turn off dimming?"] {
            XCTAssertTrue(SettingsAssistant.isQuestion(question), question)
        }
        for request in ["Disable extra display dimming", "turn on launch at login", "Can you turn off extra dimming?", "please hide the notch"] {
            XCTAssertFalse(SettingsAssistant.isQuestion(request), request)
        }
    }

    func testToggleDirectionComesFromTheWording() {
        XCTAssertEqual(SettingsAssistant.impliedToggle(in: "Turn off extra dimming", title: "Extra Dimming"), false)
        XCTAssertEqual(SettingsAssistant.impliedToggle(in: "Can you disable extra dimming?", title: "Extra Dimming"), false)
        XCTAssertEqual(SettingsAssistant.impliedToggle(in: "enable launch at login", title: "Launch at Login"), true)
        XCTAssertEqual(SettingsAssistant.impliedToggle(in: "Hide the notch in full screen", title: "Hide Notch in Full Screen"), true)
        XCTAssertEqual(SettingsAssistant.impliedToggle(in: "show the notch in full screen", title: "Hide Notch in Full Screen"), false)
        XCTAssertNil(SettingsAssistant.impliedToggle(in: "extra dimming", title: "Extra Dimming"))
    }

    func testSearchDoesNotMatchInsideLongerWords() {
        let found = SettingsIndex.search("turn off extra dimming", limit: 8).map(\.key)
        XCTAssertEqual(found.first, "displayExtraDimming")
        XCTAssertFalse(found.contains { $0.hasPrefix("archive") })
    }

    func testHumanizesKeysWithoutUITitles() {
        XCTAssertEqual(SettingsIndex.humanized("hideNotchWhenInactive"), "Hide notch when inactive")
    }
}