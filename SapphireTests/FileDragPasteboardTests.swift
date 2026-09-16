//
//  FileDragPasteboardTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import AppKit
import XCTest
@testable import Sapphire

@MainActor
final class FileDragPasteboardTests: XCTestCase {
    func testRecognizesAndReadsFileURLs() {
        let pasteboard = NSPasteboard.withUniqueName()
        let fileURL = URL(fileURLWithPath: "/tmp/sapphire-file-drag-test.txt")
        let baselineChangeCount = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])

        XCTAssertTrue(FileDragPasteboard.containsFiles(pasteboard))
        XCTAssertTrue(
            FileDragPasteboard.containsDroppableContent(
                pasteboard,
                newerThan: baselineChangeCount
            )
        )
        XCTAssertEqual(FileDragPasteboard.fileURLs(from: pasteboard), [fileURL])
    }

    func testDoesNotTreatStaleFilePasteboardAsANewDrag() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/stale-file.txt") as NSURL])

        XCTAssertFalse(
            FileDragPasteboard.containsDroppableContent(
                pasteboard,
                newerThan: pasteboard.changeCount
            )
        )
    }

    func testRecognizesLegacyFinderFilenames() {
        let pasteboard = NSPasteboard.withUniqueName()
        let path = "/tmp/sapphire-legacy-drag-test.txt"
        pasteboard.clearContents()
        pasteboard.setPropertyList(
            [path],
            forType: FileDragPasteboard.legacyFilenamesType
        )

        XCTAssertTrue(FileDragPasteboard.containsFiles(pasteboard))
        XCTAssertEqual(
            FileDragPasteboard.fileURLs(from: pasteboard),
            [URL(fileURLWithPath: path)]
        )
    }

    func testRejectsNonFileDragContent() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("not a file", forType: .string)

        XCTAssertFalse(FileDragPasteboard.containsFiles(pasteboard))
        XCTAssertTrue(FileDragPasteboard.fileURLs(from: pasteboard).isEmpty)
    }
}