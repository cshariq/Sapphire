//
//  MediaAndMemoryUtilitiesTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import XCTest
@testable import Sapphire

final class MediaApplicationIdentityTests: XCTestCase {
    func testCanonicalBundleIDMapsKnownHelperProcesses() {
        let mappings = [
            "com.apple.WebKit.GPU": "com.apple.Safari",
            "com.apple.WebKit.WebContent": "com.apple.Safari",
            "com.google.Chrome.helper": "com.google.Chrome",
            "com.google.Chrome.helper.GPU": "com.google.Chrome",
            "com.microsoft.edgemac.helper": "com.microsoft.edgemac",
            "com.microsoft.edgemac.helper.Renderer": "com.microsoft.edgemac",
            "company.thebrowser.Browser.helper": "company.thebrowser.Browser"
        ]

        for (helperBundleID, applicationBundleID) in mappings {
            XCTAssertEqual(
                MediaApplicationIdentity.canonicalBundleID(helperBundleID),
                applicationBundleID
            )
        }
    }

    func testCanonicalBundleIDPreservesNilAndUnknownIdentifiers() {
        XCTAssertNil(MediaApplicationIdentity.canonicalBundleID(nil))
        XCTAssertEqual(
            MediaApplicationIdentity.canonicalBundleID("com.spotify.client"),
            "com.spotify.client"
        )
    }
}

final class SystemMemorySnapshotTests: XCTestCase {
    func testSnapshotSumsSelectedPageBucketsInBytes() throws {
        let snapshot = try XCTUnwrap(
            SystemMemorySnapshot(
                totalBytes: 20_480,
                pageSize: 1_024,
                activePages: 2,
                wiredPages: 3,
                compressedPages: 4,
                speculativePages: 1
            )
        )

        XCTAssertEqual(snapshot.totalBytes, 20_480)
        XCTAssertEqual(snapshot.usedBytes, 10_240)
        XCTAssertEqual(snapshot.usedFraction, 0.5, accuracy: 0.000_001)
    }

    func testSnapshotCapsUsedBytesAtPhysicalMemory() throws {
        let snapshot = try XCTUnwrap(
            SystemMemorySnapshot(
                totalBytes: 8_192,
                pageSize: 4_096,
                activePages: 2,
                wiredPages: 2,
                compressedPages: 2,
                speculativePages: 2
            )
        )

        XCTAssertEqual(snapshot.usedBytes, snapshot.totalBytes)
        XCTAssertEqual(snapshot.usedFraction, 1)
    }

    func testSnapshotRejectsInvalidCapacityOrPageSize() {
        XCTAssertNil(
            SystemMemorySnapshot(
                totalBytes: 0,
                pageSize: 4_096,
                activePages: 1,
                wiredPages: 0,
                compressedPages: 0,
                speculativePages: 0
            )
        )
        XCTAssertNil(
            SystemMemorySnapshot(
                totalBytes: 4_096,
                pageSize: 0,
                activePages: 1,
                wiredPages: 0,
                compressedPages: 0,
                speculativePages: 0
            )
        )
    }
}