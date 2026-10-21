import XCTest
@testable import Sapphire

final class LocalizationDisplayFormattingTests: XCTestCase {
    func testEnglishFocusDurationKeepsOriginalCompactUnits() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        for (seconds, expected) in [(0.0, "0m"), (59.9, "0m"), (60.0, "1m"), (3599.0, "59m"), (3600.0, "1h 0m"), (7500.0, "2h 5m")] {
            XCTAssertEqual(FocusInsightsPanel.compact(seconds), expected)
        }
        XCTAssertEqual(FocusInsightsPanel.compactDays(3), "3d")
    }

    func testEnglishSettingsDisplayPreservesPrecisionAndProtocolValues() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        for (value, expected) in [(1000.0, "1000"), (1.2, "1.20"), (0.125, "0.12")] {
            XCTAssertEqual(SettingsIndex.Value.number(value).displayDescription, expected)
        }
        XCTAssertEqual(SettingsIndex.Value.bool(false).displayDescription, "off")
        let entry = try XCTUnwrap(SettingsIndex.byKey["musicLiveActivityWaveformStyle"])
        XCTAssertEqual(entry.displayValue(.text("continuity")), "continuity")
        XCTAssertEqual(entry.displayOption("continuity"), "Continuity")
    }

    func testEnglishCPUPercentageDoesNotIntroduceGrouping() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        for (value, expected) in [(0.0, "0%"), (99.6, "100%"), (1000.0, "1000%"), (1234.0, "1234%")] {
            XCTAssertEqual(DevPercentageFormatting.string(value), expected)
        }
    }

    @MainActor
    func testEnglishClipboardAndSelectionCountsRemainUngrouped() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        for count in [0, 1, 999, 1000, 1002] {
            XCTAssertEqual(ClipboardPlayerView.itemCountDescription(count), "\(count) items")
            XCTAssertEqual(InstalledAppUpdatesBatchBar.selectionSummary(count), count == 0 ? "None selected" : "\(count) selected")
        }
    }

    @MainActor
    func testEnglishFocusCompletionPreservesPluralAndUngroupedCount() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        for count in [0, 1, 2, 1000] {
            let noun = count == 1 ? "block" : "blocks"
            XCTAssertEqual(
                FocusSessionManager.completionMessage(blocks: count, total: "2h 0m"),
                "You finished \(count) \(noun). Total focus today: 2h 0m."
            )
        }
    }

    func testChineseFocusDurationUsesNativeUnitLabels() throws {
        try XCTSkipUnless(ChineseFormatting.isActive)
        XCTAssertEqual(FocusInsightsPanel.compactDays(3), "3天")
        let duration = FocusInsightsPanel.compact(7500)
        XCTAssertFalse(duration.contains("h"))
        XCTAssertFalse(duration.contains("m"))
        XCTAssertTrue(duration.contains("2"))
        XCTAssertTrue(duration.contains("5"))
    }

    func testEmptyStorageSelectionHasNoRemovalMessage() {
        XCTAssertEqual(StorageRemovalConfirmation.message(for: []), "")
    }

    func testEnglishCloudRemovalWarningsKeepOriginalCopy() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        let first = removalEntry("cloud-one.txt", cloud: true)
        let second = removalEntry("cloud-two.txt", cloud: true)
        let local = removalEntry("local.txt", cloud: false)
        let size = Int64(0).formatted(.byteCount(style: .file))
        let cloudWarning = " to the cloud: removal here also removes from iCloud Drive or your cloud storage and from your other devices."
        let cases: [([StorageEntry], String)] = [
            ([local], "local.txt (\(size)) will be moved to the Trash."),
            ([first], "cloud-one.txt (\(size)) will be moved to the Trash. This item syncs" + cloudWarning),
            ([first, second], "2 items (\(size)) will be moved to the Trash. These items sync" + cloudWarning),
            ([first, local], "2 items (\(size)) will be moved to the Trash. 1 of these sync" + cloudWarning)
        ]
        for (entries, expected) in cases {
            XCTAssertEqual(StorageRemovalConfirmation.message(for: entries), expected)
        }
    }

    func testEnglishLargeStorageRemovalCountsRemainUngrouped() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        let cloudEntries = (0..<1001).map { removalEntry("cloud-\($0).txt", cloud: true) }
        let entries = cloudEntries + [removalEntry("local.txt", cloud: false)]
        let size = Int64(0).formatted(.byteCount(style: .file))
        XCTAssertEqual(
            StorageRemovalConfirmation.message(for: entries),
            "1002 items (\(size)) will be moved to the Trash. 1001 of these sync to the cloud: removal here also removes from iCloud Drive or your cloud storage and from your other devices."
        )
    }

    func testEnglishHomebrewUpgradeFailurePreservesFallbackAndSummary() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        XCTAssertEqual(
            HomebrewFailureMessage.upgrade(summary: nil),
            "brew upgrade failed: run it in Terminal for details"
        )
        XCTAssertEqual(
            HomebrewFailureMessage.upgrade(summary: "Download failed: HTTP 503"),
            "brew upgrade failed: Download failed: HTTP 503"
        )
        XCTAssertEqual(HomebrewFailureMessage.upgrade(summary: ""), "brew upgrade failed: ")
    }

    func testEnglishHomebrewUninstallFailurePreservesFallbackAndFinalPeriod() throws {
        try XCTSkipIf(ChineseFormatting.isActive)
        let command = "brew uninstall --cask example"
        XCTAssertEqual(
            HomebrewFailureMessage.uninstall(summary: nil, command: command),
            "Homebrew could not remove the cask receipt: run “brew uninstall --cask example” in Terminal for details."
        )
        XCTAssertEqual(
            HomebrewFailureMessage.uninstall(summary: "Receipt is in use", command: command),
            "Homebrew could not remove the cask receipt: Receipt is in use."
        )
        XCTAssertEqual(
            HomebrewFailureMessage.uninstall(summary: "", command: command),
            "Homebrew could not remove the cask receipt: ."
        )
    }

    private func removalEntry(_ name: String, cloud: Bool) -> StorageEntry {
        let folder = cloud ? "Library/CloudStorage/SapphireLocalizationFixtures" : "SapphireLocalizationFixtures"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folder).appendingPathComponent(name)
        return StorageEntry(url: url, size: 0, isDirectory: false)
    }
}
