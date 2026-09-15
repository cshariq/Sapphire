//
//  MicrophoneUsageManagerTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import XCTest
@testable import Sapphire

final class MicrophoneUsageManagerTests: XCTestCase {
    func testSapphireProcessTapDoesNotCountAsMicrophoneUse() {
        XCTAssertFalse(MicrophoneUsageFilter.shouldCount(
            processID: 200,
            bundleID: "com.google.Chrome",
            inputDeviceNames: ["Sapphire-com.google.Chrome"],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }

    func testBrowserUsingPhysicalMicrophoneStillCounts() {
        XCTAssertTrue(MicrophoneUsageFilter.shouldCount(
            processID: 200,
            bundleID: "com.google.Chrome",
            inputDeviceNames: ["Sapphire-com.google.Chrome", "MacBook Pro Microphone"],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }

    func testSapphireProcessIsIgnoredEvenWhenCoreAudioOmitsBundleID() {
        XCTAssertFalse(MicrophoneUsageFilter.shouldCount(
            processID: 100,
            bundleID: nil,
            inputDeviceNames: ["MacBook Pro Microphone"],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }

    func testProcessWithoutAnInputDeviceDoesNotCount() {
        XCTAssertFalse(MicrophoneUsageFilter.shouldCount(
            processID: 200,
            bundleID: "com.google.Chrome",
            inputDeviceNames: [],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }
}