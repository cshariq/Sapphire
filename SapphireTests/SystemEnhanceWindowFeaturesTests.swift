//
//  SystemEnhanceWindowFeaturesTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import XCTest
@testable import Sapphire

// MARK: - Auto-quit decision table

final class SEAutoQuitPolicyTests: XCTestCase {
    private func check(
        enabled: Bool = true,
        excluded: Bool = false,
        protected: Bool = false,
        seen: Bool = true,
        hidden: Bool? = false,
        launchGrace: Bool = false,
        windows: SEAutoQuitWindowReport = .answered(count: 0),
        otherSpaces: SEAutoQuitOtherSpaceReport = .none,
        confirmation: Bool = true
    ) -> SEAutoQuitVerdict {
        SEAutoQuitPolicy.decide(SEAutoQuitCheck(
            isEnabled: enabled,
            isExcluded: excluded,
            isProtected: protected,
            hasSeenWindow: seen,
            isHidden: hidden,
            isWithinLaunchGrace: launchGrace,
            windows: windows,
            otherSpaces: otherSpaces,
            isConfirmation: confirmation
        ))
    }

    func testQuitsOnlyAfterConfirmedZeroWindows() {
        XCTAssertEqual(check(confirmation: false), .confirmLater)
        XCTAssertEqual(check(confirmation: true), .quit)
    }

    func testAnyRemainingWindowKeepsTheApp() {
        XCTAssertEqual(check(windows: .answered(count: 1)), .keep)
    }

    func testUnansweredAXNeverQuits() {
        XCTAssertEqual(check(windows: .unavailable), .keep)
        XCTAssertEqual(check(windows: .unavailable, confirmation: false), .keep)
    }

    func testWindowsOnAnotherSpaceVetoTheQuit() {
        XCTAssertEqual(check(otherSpaces: .present), .keep)
        XCTAssertEqual(check(otherSpaces: .unknown), .keep)
    }

    func testSettingsAndSafetyGates() {
        XCTAssertEqual(check(enabled: false), .keep)
        XCTAssertEqual(check(excluded: true), .keep)
        XCTAssertEqual(check(protected: true), .keep)
        XCTAssertEqual(check(seen: false), .keep)
        XCTAssertEqual(check(hidden: true), .keep)
        XCTAssertEqual(check(hidden: nil), .keep)
    }

    func testLaunchGraceDefersInsteadOfQuitting() {
        XCTAssertEqual(check(launchGrace: true, confirmation: true), .confirmLater)
    }

    func testFinderIsProtected() {
        XCTAssertTrue(SEAutoQuitPolicy.protectedBundleIDs.contains("com.apple.finder"))
    }

    func testWhichWindowsKeepAnAppAlive() {
        let standard = SEAutoQuitWindowFacts(role: "AXWindow", subrole: "AXStandardWindow", isMinimized: false, size: CGSize(width: 800, height: 600))
        XCTAssertTrue(SEAutoQuitPolicy.keepsAppAlive(standard))

        var minimizedPalette = SEAutoQuitWindowFacts(role: "AXWindow", subrole: "AXFloatingWindow", isMinimized: true, size: nil)
        XCTAssertTrue(SEAutoQuitPolicy.keepsAppAlive(minimizedPalette))
        minimizedPalette.isMinimized = false
        XCTAssertFalse(SEAutoQuitPolicy.keepsAppAlive(minimizedPalette))

        XCTAssertTrue(SEAutoQuitPolicy.keepsAppAlive(SEAutoQuitWindowFacts(role: "AXWindow", subrole: "AXDialog", isMinimized: false, size: nil)))
        XCTAssertTrue(SEAutoQuitPolicy.keepsAppAlive(SEAutoQuitWindowFacts(role: "AXWindow", subrole: nil, isMinimized: false, size: nil)))
        XCTAssertFalse(SEAutoQuitPolicy.keepsAppAlive(SEAutoQuitWindowFacts(role: "AXWindow", subrole: "AXUnknown", isMinimized: false, size: CGSize(width: 10, height: 10))))
        XCTAssertFalse(SEAutoQuitPolicy.keepsAppAlive(SEAutoQuitWindowFacts(role: "AXSheet", subrole: nil, isMinimized: false, size: nil)))
    }
}

// MARK: - Finder naming and focus

final class SEFinderHelpersTests: XCTestCase {
    func testAvailableNameKeepsFreeNames() {
        XCTAssertEqual(SEFinderFileNaming.availableName(for: "Report.pdf") { _ in false }, "Report.pdf")
    }

    func testAvailableNameNumbersLikeFinder() {
        let taken: Set<String> = ["Report.pdf", "Report 2.pdf"]
        XCTAssertEqual(SEFinderFileNaming.availableName(for: "Report.pdf") { taken.contains($0) }, "Report 3.pdf")
        XCTAssertEqual(SEFinderFileNaming.availableName(for: "Folder") { $0 == "Folder" }, "Folder 2")
    }

    func testAvailableNameContinuesAnExistingNumber() {
        let taken: Set<String> = ["Photo 4.jpg"]
        XCTAssertEqual(SEFinderFileNaming.availableName(for: "Photo 4.jpg") { taken.contains($0) }, "Photo 5.jpg")
    }

    func testAvailableNameExtensionEdgeCases() {
        XCTAssertEqual(SEFinderFileNaming.availableName(for: ".zshrc") { $0 == ".zshrc" }, ".zshrc 2")
        XCTAssertEqual(SEFinderFileNaming.availableName(for: "archive.tar.gz") { $0 == "archive.tar.gz" }, "archive.tar 2.gz")
        XCTAssertEqual(SEFinderFileNaming.availableName(for: "Notes.") { $0 == "Notes." }, "Notes. 2")
        XCTAssertEqual(SEFinderFileNaming.availableName(for: "2") { $0 == "2" }, "2 2")
    }

    func testMoveIntoItselfIsDetected() {
        let source = URL(fileURLWithPath: "/Users/a/Projects")
        XCTAssertTrue(SEFinderFileNaming.isMoveIntoItself(source: source, folder: URL(fileURLWithPath: "/Users/a/Projects/sub")))
        XCTAssertTrue(SEFinderFileNaming.isMoveIntoItself(source: source, folder: source))
        XCTAssertFalse(SEFinderFileNaming.isMoveIntoItself(source: source, folder: URL(fileURLWithPath: "/Users/a/Projects2")))
    }

    func testFocusClassification() {
        XCTAssertEqual(SEFinderFocus.classify(role: "AXTextField", subrole: nil), .textInput)
        XCTAssertEqual(SEFinderFocus.classify(role: "AXTextField", subrole: "AXSearchField"), .textInput)
        XCTAssertEqual(SEFinderFocus.classify(role: "AXOutline", subrole: nil), .fileList)
        XCTAssertEqual(SEFinderFocus.classify(role: "AXList", subrole: nil), .fileList)
        XCTAssertEqual(SEFinderFocus.classify(role: "AXButton", subrole: nil), .other)
        XCTAssertEqual(SEFinderFocus.classify(role: nil, subrole: nil), .unknown)
    }
}

// MARK: - Dock click gesture

final class SEDockClickGestureTests: XCTestCase {
    func testStillPressIsAClick() {
        XCTAssertTrue(SEDockClickGesture.isClick(down: .zero, up: CGPoint(x: 2, y: 1), farthestTravel: 2, duration: 0.15))
    }

    func testDragIsNotAClick() {
        XCTAssertFalse(SEDockClickGesture.isClick(down: .zero, up: CGPoint(x: 30, y: 0), farthestTravel: 30, duration: 0.2))
        // Dragged away and back: still a drag.
        XCTAssertFalse(SEDockClickGesture.isClick(down: .zero, up: CGPoint(x: 1, y: 0), farthestTravel: 40, duration: 0.3))
    }

    func testLongPressIsNotAClick() {
        XCTAssertFalse(SEDockClickGesture.isClick(down: .zero, up: .zero, farthestTravel: 0, duration: 0.9))
        XCTAssertFalse(SEDockClickGesture.isClick(down: .zero, up: .zero, farthestTravel: 0, duration: -1))
    }

    func testModifiedClicksStayNative() {
        XCTAssertTrue(SEDockClickGesture.isPlainClick([]))
        XCTAssertTrue(SEDockClickGesture.isPlainClick(.maskSecondaryFn))
        XCTAssertFalse(SEDockClickGesture.isPlainClick(.maskCommand))
        XCTAssertFalse(SEDockClickGesture.isPlainClick(.maskAlternate))
        XCTAssertFalse(SEDockClickGesture.isPlainClick(.maskControl))
    }
}

// MARK: - Green maximize prefilter

final class SEGreenMaximizePrefilterTests: XCTestCase {
    private let ownPID: pid_t = 999

    private func window(_ id: CGWindowID, pid: pid_t, _ bounds: CGRect, layer: Int = 0, alpha: Double = 1) -> SEGreenMaximizeWindowInfo {
        SEGreenMaximizeWindowInfo(windowID: id, pid: pid, bounds: bounds, layer: layer, alpha: alpha)
    }

    func testZoomCornerOfTopWindowPasses() {
        let windows = [window(1, pid: 10, CGRect(x: 100, y: 100, width: 800, height: 600))]
        let hit = SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 155, y: 112), in: windows, ownPID: ownPID)
        XCTAssertEqual(hit?.windowID, 1)
    }

    func testClicksOutsideTheCornerAreIgnored() {
        let windows = [window(1, pid: 10, CGRect(x: 100, y: 100, width: 800, height: 600))]
        XCTAssertNil(SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 500, y: 112), in: windows, ownPID: ownPID))
        XCTAssertNil(SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 155, y: 400), in: windows, ownPID: ownPID))
        XCTAssertNil(SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 10, y: 10), in: windows, ownPID: ownPID))
    }

    func testBackgroundWindowCornerPassesWhenUncovered() {
        let windows = [
            window(1, pid: 10, CGRect(x: 600, y: 100, width: 400, height: 400)),
            window(2, pid: 20, CGRect(x: 100, y: 100, width: 800, height: 600)),
        ]
        XCTAssertEqual(SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 155, y: 112), in: windows, ownPID: ownPID)?.windowID, 2)
    }

    func testCoveringWindowsBlockTheClick() {
        let menu = window(1, pid: 30, CGRect(x: 120, y: 90, width: 200, height: 300), layer: 101)
        let covering = window(2, pid: 10, CGRect(x: 0, y: 0, width: 400, height: 400))
        let target = window(3, pid: 20, CGRect(x: 100, y: 100, width: 800, height: 600))
        XCTAssertNil(SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 155, y: 112), in: [menu, target], ownPID: ownPID))
        // The top window's own corner is elsewhere, so the click is in its content.
        XCTAssertNil(SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 155, y: 112), in: [covering, target], ownPID: ownPID))
    }

    func testOwnAndTransparentOverlaysAreSkipped() {
        let overlay = window(1, pid: ownPID, CGRect(x: 0, y: 0, width: 2000, height: 2000), layer: 25)
        let invisible = window(2, pid: 40, CGRect(x: 0, y: 0, width: 2000, height: 2000), alpha: 0)
        let target = window(3, pid: 20, CGRect(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(SEGreenMaximizePrefilter.candidate(at: CGPoint(x: 155, y: 112), in: [overlay, invisible, target], ownPID: ownPID)?.windowID, 3)
    }

    func testOptionClickStaysNative() {
        XCTAssertTrue(SEGreenMaximizePrefilter.isPlainClick([]))
        XCTAssertFalse(SEGreenMaximizePrefilter.isPlainClick(.maskAlternate))
    }
}
