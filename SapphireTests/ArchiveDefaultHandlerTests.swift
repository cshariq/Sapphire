//
//  ArchiveDefaultHandlerTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation
import XCTest
@testable import Sapphire

@MainActor
final class ArchiveDefaultHandlerTests: XCTestCase {
    private let sapphireBundleIdentifier = "com.cshariq.sapphire"

    func testAllHandlersMatch() {
        let status = ArchiveExtractor.evaluateDefaultHandlerStatus(
            bundleIdentifier: sapphireBundleIdentifier,
            handlerBundleIdentifiers: [
                sapphireBundleIdentifier,
                sapphireBundleIdentifier,
                sapphireBundleIdentifier,
            ]
        )

        XCTAssertEqual(status.matchingTypeCount, 3)
        XCTAssertEqual(status.totalTypeCount, 3)
        XCTAssertTrue(status.hasAnyMatch)
        XCTAssertTrue(status.isComplete)
    }

    func testPartialHandlerMatch() {
        let status = ArchiveExtractor.evaluateDefaultHandlerStatus(
            bundleIdentifier: sapphireBundleIdentifier,
            handlerBundleIdentifiers: [
                sapphireBundleIdentifier,
                "com.apple.archiveutility",
                sapphireBundleIdentifier,
            ]
        )

        XCTAssertEqual(status.matchingTypeCount, 2)
        XCTAssertEqual(status.totalTypeCount, 3)
        XCTAssertTrue(status.hasAnyMatch)
        XCTAssertFalse(status.isComplete)
    }

    func testNoHandlersMatch() {
        let status = ArchiveExtractor.evaluateDefaultHandlerStatus(
            bundleIdentifier: sapphireBundleIdentifier,
            handlerBundleIdentifiers: [
                "com.apple.archiveutility",
                "com.example.unarchiver",
            ]
        )

        XCTAssertEqual(status.matchingTypeCount, 0)
        XCTAssertEqual(status.totalTypeCount, 2)
        XCTAssertFalse(status.hasAnyMatch)
        XCTAssertFalse(status.isComplete)
    }

    func testNilHandlersCountAsNonMatches() {
        let status = ArchiveExtractor.evaluateDefaultHandlerStatus(
            bundleIdentifier: sapphireBundleIdentifier,
            handlerBundleIdentifiers: [sapphireBundleIdentifier, nil, nil]
        )

        XCTAssertEqual(status.matchingTypeCount, 1)
        XCTAssertEqual(status.totalTypeCount, 3)
        XCTAssertTrue(status.hasAnyMatch)
        XCTAssertFalse(status.isComplete)
    }

    func testBundleIdentifierComparisonIsCaseInsensitive() {
        let status = ArchiveExtractor.evaluateDefaultHandlerStatus(
            bundleIdentifier: sapphireBundleIdentifier,
            handlerBundleIdentifiers: ["COM.CSHARIQ.SAPPHIRE"]
        )

        XCTAssertTrue(status.hasAnyMatch)
        XCTAssertTrue(status.isComplete)
    }

    func testEmptyHandlerListIsNeitherMatchedNorComplete() {
        let status = ArchiveExtractor.evaluateDefaultHandlerStatus(
            bundleIdentifier: sapphireBundleIdentifier,
            handlerBundleIdentifiers: []
        )

        XCTAssertEqual(status.matchingTypeCount, 0)
        XCTAssertEqual(status.totalTypeCount, 0)
        XCTAssertFalse(status.hasAnyMatch)
        XCTAssertFalse(status.isComplete)
    }

    func testArchiveIdentifiersUseCanonicalSevenZipAndDeclaredRARIdentifiers() {
        let identifiers = ArchiveExtractor.defaultArchiveContentTypeIdentifiers

        XCTAssertEqual(identifiers.count, 9)
        XCTAssertEqual(Set(identifiers).count, 9)
        XCTAssertTrue(identifiers.contains("org.7-zip.7-zip-archive"))
        XCTAssertTrue(identifiers.contains("com.rarlab.rar-archive"))
        XCTAssertFalse(identifiers.contains("org.7-zip.7z-archive"))
    }

    func testSapphireBundleImportsRARFilenameType() throws {
        guard Bundle.main.bundleIdentifier == sapphireBundleIdentifier else {
            throw XCTSkip("This contract test requires Sapphire.app as the unit-test host.")
        }

        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations")
                as? [[String: Any]]
        )
        let rarDeclaration = try XCTUnwrap(declarations.first {
            $0["UTTypeIdentifier"] as? String == "com.rarlab.rar-archive"
        })
        let tagSpecification = try XCTUnwrap(
            rarDeclaration["UTTypeTagSpecification"] as? [String: Any]
        )
        let filenameExtensions = try XCTUnwrap(
            tagSpecification["public.filename-extension"] as? [String]
        )

        XCTAssertTrue(filenameExtensions.contains("rar"))
    }
}