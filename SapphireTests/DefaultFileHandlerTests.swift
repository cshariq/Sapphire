//
//  DefaultFileHandlerTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-11
//

import Foundation
import XCTest
@testable import Sapphire

final class DefaultFileHandlerTests: XCTestCase {
    private let own = URL(fileURLWithPath: "/Applications/Sapphire.app")
    private let sapphire = "com.cshariq.sapphire"

    func testTheSameBundleIsRecognisedThroughSymlinksAndTrailingSlashes() {
        let viaSymlink = URL(fileURLWithPath: "/tmp/Sapphire.app")
        let resolved = URL(fileURLWithPath: "/private/tmp/Sapphire.app/")
        XCTAssertTrue(DefaultFileHandler.isThisApp(handlerURL: resolved, ownURL: viaSymlink))
        XCTAssertTrue(DefaultFileHandler.isThisApp(handlerURL: own, ownURL: URL(fileURLWithPath: "/Applications/Sapphire.app/")))
        XCTAssertFalse(DefaultFileHandler.isThisApp(handlerURL: nil, ownURL: own))
    }

    func testAnotherCopyOfSapphireIsDetectedOnlyWhenTheBundleIdentifierMatches() {
        let debugCopy = URL(fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData/x/Build/Products/Debug/Sapphire.app")
        XCTAssertTrue(DefaultFileHandler.pointsAtAnotherCopy(
            handlerBundleIdentifier: sapphire, handlerURL: own, ownBundleIdentifier: sapphire, ownURL: debugCopy
        ))
        XCTAssertFalse(DefaultFileHandler.pointsAtAnotherCopy(
            handlerBundleIdentifier: sapphire, handlerURL: own, ownBundleIdentifier: sapphire, ownURL: own
        ), "the running copy is not 'another copy'")
        XCTAssertFalse(DefaultFileHandler.pointsAtAnotherCopy(
            handlerBundleIdentifier: "com.apple.archiveutility", handlerURL: URL(fileURLWithPath: "/System/Applications/Utilities/Archive Utility.app"),
            ownBundleIdentifier: sapphire, ownURL: own
        ), "other apps' associations are left alone")
    }

    func testHandOffPrefersTheSystemAppAndNeverPicksSapphire() {
        let archiveUtility = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app")
        let unarchiver = URL(fileURLWithPath: "/Applications/The Unarchiver.app")
        let ids: [URL: String] = [own: sapphire, archiveUtility: "com.apple.archiveutility", unarchiver: "cx.c3.theunarchiver"]
        let lookup: (URL) -> String? = { ids[$0] }

        XCTAssertEqual(
            DefaultFileHandler.alternative(
                candidates: [own, unarchiver, archiveUtility], preferredBundleIdentifiers: ["com.apple.archiveutility"],
                ownBundleIdentifier: sapphire, bundleIdentifier: lookup
            ),
            archiveUtility
        )
        XCTAssertEqual(
            DefaultFileHandler.alternative(
                candidates: [own, unarchiver], preferredBundleIdentifiers: ["com.apple.archiveutility"],
                ownBundleIdentifier: sapphire, bundleIdentifier: lookup
            ),
            unarchiver
        )
        XCTAssertNil(
            DefaultFileHandler.alternative(
                candidates: [own], preferredBundleIdentifiers: ["com.apple.archiveutility"],
                ownBundleIdentifier: sapphire, bundleIdentifier: lookup
            ),
            "with no other app the hand-off is refused rather than looping back to Sapphire"
        )
    }

    func testFinderMetadataDoesNotMakeAnArchiveLookLikeManyItems() {
        let single = ["Photos/", "Photos/a.jpg", "__MACOSX/", "__MACOSX/Photos/._a.jpg", ".DS_Store"]
        XCTAssertEqual(ArchiveExtractor.topLevelCount(single), 1)
        let several = ["a.txt", "b.txt", "__MACOSX/._a.txt"]
        XCTAssertEqual(ArchiveExtractor.topLevelCount(several), 2)
    }
}