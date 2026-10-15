//
//  CallAudioAttributionTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26

import XCTest
@testable import Sapphire

final class CallAudioAttributionTests: XCTestCase {
    private let bothRunning: (String) -> Bool = { ["com.apple.FaceTime", "com.apple.mobilephone"].contains($0) }

    func testFaceTimeCallAudioIsAttributedToFaceTime() {
        XCTAssertEqual(CallAudioAttribution.callingApp(
            forDaemonBundleID: "com.apple.avconferenced",
            frontmostBundleID: "com.apple.Safari",
            isRunning: { $0 == "com.apple.FaceTime" }
        ), "com.apple.FaceTime")
    }

    func testFrontmostCallingAppWinsWhenBothAreRunning() {
        XCTAssertEqual(CallAudioAttribution.callingApp(
            forDaemonBundleID: "com.apple.avconferenced",
            frontmostBundleID: "com.apple.mobilephone",
            isRunning: bothRunning
        ), "com.apple.mobilephone")
    }

    func testRingtoneDaemonIsAttributedToCallingApp() {
        XCTAssertEqual(CallAudioAttribution.callingApp(
            forDaemonBundleID: "com.apple.TelephonyUtilities",
            frontmostBundleID: nil,
            isRunning: bothRunning
        ), "com.apple.FaceTime")
    }

    func testCallDaemonWithoutCallingAppIsNotAttributed() {
        XCTAssertNil(CallAudioAttribution.callingApp(
            forDaemonBundleID: "com.apple.avconferenced",
            frontmostBundleID: nil,
            isRunning: { _ in false }
        ))
    }

    func testOtherDaemonsAreNotAttributed() {
        XCTAssertNil(CallAudioAttribution.callingApp(
            forDaemonBundleID: "com.apple.historicalaudiod",
            frontmostBundleID: "com.apple.FaceTime",
            isRunning: bothRunning
        ))
        XCTAssertNil(CallAudioAttribution.callingApp(
            forDaemonBundleID: nil,
            frontmostBundleID: "com.apple.FaceTime",
            isRunning: bothRunning
        ))
    }
}