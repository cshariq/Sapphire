//
//  ClipboardAndFileToolsTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import Foundation
import Testing
@testable import Sapphire

struct ClipboardAndFileToolsTests {
    // MARK: - Helpers

    private func text(_ id: String, _ body: String, pinned: Bool = false, bytes: Int? = nil) -> ClipboardItem {
        ClipboardItem(
            id: id, preview: body, copiedAt: Date(timeIntervalSince1970: 0), kind: .text,
            textContent: body, imagePNGData: nil, fileURLString: nil, fileBookmarkData: nil,
            isPinned: pinned, byteSize: bytes
        )
    }

    private func file(_ id: String, _ path: String) -> ClipboardItem {
        ClipboardItem(
            id: id, preview: (path as NSString).lastPathComponent, copiedAt: Date(timeIntervalSince1970: 0),
            kind: .file, textContent: nil, imagePNGData: nil, fileURLString: path, fileBookmarkData: nil
        )
    }

    // MARK: - URL cleaning

    @Test func stripsNewTrackingParameters() {
        let dirty = "https://example.com/page?id=7&gbraid=a&wbraid=b&yclid=c&ttclid=d&_hsenc=e&mkt_tok=f&srsltid=g&igshid=h&mc_cid=i&mc_eid=j&utm_custom=k"
        #expect(CleanURLManager.cleanedURL(dirty, extraParams: []) == "https://example.com/page?id=7")
    }

    @Test func keepsMeaningfulParametersAndReturnsNilWhenClean() {
        #expect(CleanURLManager.cleanedURL("https://example.com/search?q=swift&page=2", extraParams: []) == nil)
        #expect(CleanURLManager.cleanedURL("not a url?utm_source=x", extraParams: []) == nil)
    }

    @Test func siIsOnlyStrippedOnHostsThatUseItForTracking() {
        #expect(CleanURLManager.cleanedURL("https://youtu.be/abc?si=XYZ&t=42", extraParams: []) == "https://youtu.be/abc?t=42")
        #expect(CleanURLManager.cleanedURL("https://www.youtube.com/watch?v=abc&si=XYZ&pp=1", extraParams: []) == "https://www.youtube.com/watch?v=abc")
        #expect(CleanURLManager.cleanedURL("https://example.com/?si=keep", extraParams: []) == nil)
    }

    @Test func customParametersAndPercentEncodingSurvive() {
        let cleaned = CleanURLManager.cleanedURL("https://example.com/a?q=a%20b%26c&ref=x", extraParams: ["REF"])
        #expect(cleaned == "https://example.com/a?q=a%20b%26c")
    }

    // MARK: - Retention budget

    @Test func countLimitKeepsNewestAndAllPins() {
        let items = [text("1", "a"), text("2", "b", pinned: true), text("3", "c"), text("4", "d"), text("5", "e", pinned: true)]
        let kept = ClipboardHistoryBudget.retained(items, maxItems: 2, maxBytes: nil).map(\.id)
        #expect(kept == ["1", "2", "3", "5"])
    }

    @Test func byteBudgetEvictsOldestButKeepsNewestEvenIfHuge() {
        let items = [text("1", "x", bytes: 900), text("2", "y", bytes: 200), text("3", "z", bytes: 50)]
        #expect(ClipboardHistoryBudget.retained(items, maxItems: nil, maxBytes: 1000).map(\.id) == ["1", "3"])
        #expect(ClipboardHistoryBudget.retained([text("1", "x", bytes: 5000)], maxItems: nil, maxBytes: 10).map(\.id) == ["1"])
    }

    @Test func noLimitsKeepsEverything() {
        let items = (0..<50).map { text("\($0)", "t\($0)") }
        #expect(ClipboardHistoryBudget.retained(items, maxItems: nil, maxBytes: nil).count == 50)
    }

    @Test func textTruncationRespectsCharacterBoundaries() {
        let (short, cut) = ClipboardTextLimit.truncated("héllo", maxUTF8Bytes: 3)
        #expect(short == "hé")
        #expect(cut)
        let (same, notCut) = ClipboardTextLimit.truncated("abc", maxUTF8Bytes: 3)
        #expect(same == "abc" && !notCut)
        let (emoji, _) = ClipboardTextLimit.truncated("a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", maxUTF8Bytes: 5)
        #expect(emoji == "a")
    }

    // MARK: - Capture filter

    @Test func transientAlwaysIgnoredConcealedFollowsSetting() {
        let ignore = { (types: Set<String>, marked: Bool) in
            ClipboardCaptureFilter.shouldIgnore(types: types, sourceBundleID: nil, frontmostBundleID: nil,
                                                ignoredBundleIDs: [], ignoreMarkedItems: marked)
        }
        #expect(ignore([ClipboardCaptureFilter.transientType], false))
        #expect(ignore([ClipboardCaptureFilter.concealedType], true))
        #expect(!ignore([ClipboardCaptureFilter.concealedType], false))
        #expect(!ignore(["public.utf8-plain-text"], true))
    }

    @Test func ignoredAppsMatchSourceOrFrontmostCaseInsensitively() {
        #expect(ClipboardCaptureFilter.shouldIgnore(types: [], sourceBundleID: "COM.1password.1password", frontmostBundleID: nil,
                                                    ignoredBundleIDs: ["com.1password.1password"], ignoreMarkedItems: true))
        #expect(ClipboardCaptureFilter.shouldIgnore(types: [], sourceBundleID: nil, frontmostBundleID: "com.bitwarden.desktop",
                                                    ignoredBundleIDs: ["com.bitwarden.desktop"], ignoreMarkedItems: true))
        #expect(!ClipboardCaptureFilter.shouldIgnore(types: [], sourceBundleID: nil, frontmostBundleID: "com.apple.Safari",
                                                     ignoredBundleIDs: ["com.bitwarden.desktop"], ignoreMarkedItems: true))
    }

    // MARK: - Search

    @Test func searchMatchesTextPathAndDiacritics() {
        let items = [text("1", "Café menu"), file("2", "/Users/me/Reports/q3.pdf"), text("3", "unrelated")]
        #expect(ClipboardSearch.filter(items, kinds: nil, query: "cafe").map(\.id) == ["1"])
        #expect(ClipboardSearch.filter(items, kinds: nil, query: "reports").map(\.id) == ["2"])
        #expect(ClipboardSearch.filter(items, kinds: [.text], query: "").map(\.id) == ["1", "3"])
    }

    @Test func searchCacheReusesAndNarrowsUntilRevisionChanges() {
        var cache = ClipboardSearchCache()
        let items = [text("1", "apple pie"), text("2", "apricot"), text("3", "banana")]
        #expect(cache.results(for: items, revision: 1, kinds: nil, query: "ap").map(\.id) == ["1", "2"])
        #expect(cache.fullScans == 1)
        #expect(cache.results(for: items, revision: 1, kinds: nil, query: "ap").map(\.id) == ["1", "2"])
        #expect(cache.results(for: items, revision: 1, kinds: nil, query: "app").map(\.id) == ["1"])
        #expect(cache.fullScans == 1)
        let changed = items + [text("4", "apple juice")]
        #expect(cache.results(for: changed, revision: 2, kinds: nil, query: "app").map(\.id) == ["1", "4"])
        #expect(cache.fullScans == 2)
    }

    @Test func equalityReflectsVisibleChanges() {
        let base = text("1", "hello")
        #expect(base == base.with(pinned: false))
        #expect(base != base.with(pinned: true))
        let moved = file("2", "/a/b.txt").with(fileURL: URL(fileURLWithPath: "/c/b.txt"), bookmark: nil)
        #expect(moved != file("2", "/a/b.txt"))
    }

    @Test func multiPastePlans() {
        #expect(ClipboardMultiPaste.plan(for: [text("1", "a"), text("2", "b")]) == .joinedText("a\nb"))
        #expect(ClipboardMultiPaste.plan(for: [text("1", "a"), file("2", "/x/y")]) == .items([.text("a"), .file(path: "/x/y")]))
        #expect(ClipboardMultiPaste.plan(for: []) == nil)
    }

    // MARK: - Unique naming

    @Test func uniqueNamesNeverReuseExisting() {
        let taken: Set<String> = ["Report.pdf", "Report 2.pdf"]
        #expect(UniqueFileName.candidate(base: "Report", pathExtension: "pdf") { taken.contains($0) } == "Report 3.pdf")
        #expect(UniqueFileName.candidate(base: "Report", pathExtension: "png") { taken.contains($0) } == "Report.png")
        #expect(UniqueFileName.candidate(base: "", pathExtension: "") { _ in false } == "Untitled")
        #expect(UniqueFileName.copyName(for: "my_file_v2.mov") == "my_file_v2 Copy.mov")
    }

    @Test func shelfLocations() {
        #expect(FileShelfManager.isInside(URL(fileURLWithPath: "/a/b/c.txt"), URL(fileURLWithPath: "/a/b")))
        #expect(!FileShelfManager.isInside(URL(fileURLWithPath: "/a/bc/c.txt"), URL(fileURLWithPath: "/a/b")))
        #expect(FileShelfManager.isVolatileLocation(FileManager.default.temporaryDirectory.appendingPathComponent("x.png")))
        #expect(!FileShelfManager.isVolatileLocation(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/x.png")))
    }
}