import XCTest
@testable import Sapphire

final class LocalizationNavigationTests: XCTestCase {
    private var language: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    func testChineseAndEnglishNamesFindTheSameSettingsPages() {
        var queries: [(String, SettingsSection)] = [("Music", .music), ("Battery", .battery), ("File Shelf", .fileShelf)]
        if language.hasPrefix("zh-Hant") {
            queries += [("音樂", .music), ("電池", .battery), ("檔案", .fileShelf)]
        }
        for (query, expected) in queries {
            XCTAssertTrue(SettingsSection.sidebarGroups(matching: query).flatMap(\.sections).contains(expected), query)
        }
    }

    func testEnglishSearchUsesOnlyTheOriginalTerms() throws {
        try XCTSkipUnless(language == "en")
        for section in SettingsSection.allCases {
            XCTAssertEqual(section.localizedSearchKeywords, [section.label], section.rawValue)
        }
        XCTAssertTrue(SettingsSection.sidebarGroups(matching: "音樂").isEmpty)
    }

    func testSearchTrimsWhitespaceAndIgnoresEnglishCase() {
        XCTAssertEqual(SettingsSection.sidebarGroups(matching: "  mUsIc \n").flatMap(\.sections), SettingsSection.sidebarGroups(matching: "music").flatMap(\.sections))
        XCTAssertEqual(SettingsSection.sidebarGroups(matching: " \n").map(\.id), SettingsSection.sidebarGroups.map(\.id))
        XCTAssertTrue(SettingsSection.sidebarGroups(matching: "a-setting-that-does-not-exist").isEmpty)
    }

    func testSidebarGroupIdentityIsIndependentOfItsDisplayTitle() {
        let expectedIDs = ["general", "notch", "widgetsAndContent", "systemAndUtilities", "focusAndSecurity", "about"]
        XCTAssertEqual(SettingsSection.sidebarGroups.map(\.id), expectedIDs)
        for group in SettingsSection.sidebarGroups {
            let translated = SettingsSidebarGroup(id: group.id, title: "已翻譯的標題", sections: group.sections)
            XCTAssertEqual(translated.id, group.id)
        }
        XCTAssertEqual(SettingsSection.sidebarGroups(matching: "Music").map(\.id), ["widgetsAndContent"])
    }

    func testSidebarHasEverySupportedSectionExactlyOnce() {
        for includesOverview in [false, true] {
            let sections = SettingsSection.sidebarGroups(includingOverview: includesOverview).flatMap(\.sections)
            let expected = SettingsSection.allCases.filter { includesOverview || $0 != .overview }
            XCTAssertEqual(sections.count, expected.count)
            XCTAssertEqual(Set(sections), Set(expected))
        }
        XCTAssertEqual(
            SettingsSection.sidebarGroups.flatMap(\.sections).contains(.overview),
            SettingsAssistant.isSupported
        )
    }

    func testSettingsIndexSearchesTranslatedAndEnglishTitles() throws {
        let entry = try XCTUnwrap(SettingsIndex.byKey["launchAtLogin"])
        XCTAssertEqual(entry.englishTitle, "Launch at Login")
        XCTAssertTrue(SettingsIndex.search(entry.englishTitle).contains { $0.key == entry.key })
        XCTAssertTrue(SettingsIndex.search(entry.displayTitle).contains { $0.key == entry.key })
        if language.hasPrefix("zh") {
            XCTAssertNotEqual(entry.displayTitle, entry.englishTitle)
            let partialTitle = String(entry.displayTitle.suffix(2))
            XCTAssertTrue(SettingsIndex.search(partialTitle, limit: 100).contains { $0.key == entry.key })
        }
    }

    func testLocalizedSettingsLabelsKeepStoredValuesUsableForUndo() throws {
        let entry = try XCTUnwrap(SettingsIndex.byKey["animationProfile"])
        XCTAssertEqual(entry.displayOption("fluid"), AnimationProfile.fluid.displayName)
        let original = Settings()
        let (updated, change) = try SettingsIndex.applying(key: entry.key, rawValue: "fluid", to: original).get()
        XCTAssertEqual(updated.animationProfile, .fluid)
        XCTAssertEqual(change.newValue.description, "fluid")
        let (restored, _) = try SettingsIndex.applying(key: entry.key, rawValue: change.oldValue.description, to: updated).get()
        XCTAssertEqual(restored.animationProfile, original.animationProfile)
        XCTAssertEqual(SettingsIndex.Value.bool(true).description, "on")
        XCTAssertEqual(SettingsIndex.Value.bool(true).displayDescription, ChineseFormatting.isActive ? String(localized: "On") : "on")
    }

    func testAssistantRecognizesChineseQuestionPunctuation() {
        XCTAssertTrue(SettingsAssistant.isQuestion("可以在全螢幕時隱藏瀏海區域嗎？"))
    }

    func testSettingsIndexShowsCompleteQuotedTitleFromTheSettingsPane() throws {
        let entry = try XCTUnwrap(SettingsIndex.byKey["bluetoothUnlockPauseMusicOnLock"])
        XCTAssertEqual(entry.displayTitle, String(localized: "Pause \"Now Playing\" while Locked"))
        XCTAssertEqual(entry.englishTitle, "Pause \\")
        XCTAssertEqual(entry.key, "bluetoothUnlockPauseMusicOnLock")
    }

    func testIndexDisplayCatalogCoversEverySetting() {
        XCTAssertEqual(Set(SettingsIndex.localizedTitles.keys), Set(SettingsIndex.entries.map(\.key)))
    }

    func testSavedIdentifiersStillDecodeWithoutUsingDisplayNames() throws {
        XCTAssertEqual(SettingsSection(rawValue: "fileShelf"), .fileShelf)
        XCTAssertEqual(SettingsSection(rawValue: "keyboardShortcuts"), .keyboardShortcuts)
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(WidgetSwitchEffect.self, from: Data("\"bouncy\"".utf8)), .bouncy)
        XCTAssertEqual(try decoder.decode(SnapZoneViewMode.self, from: Data("\"multi\"".utf8)), .multi)
        XCTAssertEqual(try decoder.decode(NotchBackgroundStyle.self, from: Data("\"radial\"".utf8)), .radial)
    }
}
