import XCTest
@testable import Sapphire

final class LocalizationNavigationTests: XCTestCase {
    private var language: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    func testChineseAndEnglishNamesFindTheSameSettingsPages() {
        var queries: [(String, SettingsSection)] = [("Music", .music), ("Battery", .battery), ("File Shelf", .fileShelf)]
        if language.hasPrefix("zh-Hans") {
            queries += [("音乐", .music), ("电池", .battery), ("文件", .fileShelf)]
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
        XCTAssertTrue(SettingsSection.sidebarGroups(matching: "音乐").isEmpty)
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
            let translated = SettingsSidebarGroup(id: group.id, title: "已翻译的标题", sections: group.sections)
            XCTAssertEqual(translated.id, group.id)
        }
        XCTAssertEqual(SettingsSection.sidebarGroups(matching: "Music").map(\.id), ["widgetsAndContent"])
    }

    func testSidebarHasEverySectionExactlyOnce() {
        let sections = SettingsSection.sidebarGroups.flatMap(\.sections)
        XCTAssertEqual(sections.count, SettingsSection.allCases.count)
        XCTAssertEqual(Set(sections), Set(SettingsSection.allCases))
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
