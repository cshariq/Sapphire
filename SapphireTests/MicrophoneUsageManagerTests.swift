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

    func testUnnamedInputDeviceDoesNotCount() {
        XCTAssertFalse(MicrophoneUsageFilter.shouldCount(
            processID: 200,
            bundleID: "com.google.Chrome",
            inputDeviceNames: [nil, ""],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }

    func testAppleAudioDaemonDoesNotCount() {
        XCTAssertFalse(MicrophoneUsageFilter.shouldCount(
            processID: 200,
            bundleID: "com.apple.controlcenter",
            inputDeviceNames: ["MacBook Pro Microphone"],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
        XCTAssertFalse(MicrophoneUsageFilter.shouldCount(
            processID: 200,
            bundleID: nil,
            inputDeviceNames: ["MacBook Pro Microphone"],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }

    func testDaemonWithEmptyBundleIDDoesNotCount() {
        XCTAssertFalse(MicrophoneUsageFilter.shouldCount(
            processID: 585,
            bundleID: "",
            inputDeviceNames: ["MacBook Pro Microphone"],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }

    func testFaceTimeStillCountsAsMicrophoneUse() {
        XCTAssertTrue(MicrophoneUsageFilter.shouldCount(
            processID: 200,
            bundleID: "com.apple.FaceTime",
            inputDeviceNames: ["MacBook Pro Microphone"],
            ownProcessID: 100,
            ownBundleID: "com.cshariq.Sapphire"
        ))
    }
}