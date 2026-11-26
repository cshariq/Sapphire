//
//  SystemEnhanceHingeAnimationTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import XCTest
@testable import Sapphire

final class SystemEnhanceHingeAnimationTests: XCTestCase {
    func testDesktopIsUntouchedAtAndAboveActivationAngle() {
        for angle in [105.0, 120.0, 180.0] {
            let state = SEHingeAnimationVisualState.resolve(
                angle: angle,
                activationAngle: 105,
                intensity: 1,
                maximumBlur: 18
            )

            XCTAssertEqual(state.progress, 0, accuracy: 0.000_001)
            XCTAssertFalse(state.shouldShowOverlay)
        }
    }

    func testPartialAdjustmentContinuouslyBuildsFold() {
        let shallow = state(angle: 85)
        let middle = state(angle: 55)
        let deep = state(angle: 20)

        XCTAssertGreaterThan(shallow.progress, 0)
        XCTAssertLessThan(shallow.progress, middle.progress)
        XCTAssertLessThan(middle.progress, deep.progress)
        XCTAssertLessThan(shallow.blurRadius, middle.blurRadius)
        XCTAssertLessThan(middle.blurRadius, deep.blurRadius)
        XCTAssertTrue(middle.shouldShowOverlay)
    }

    func testOpeningAndClosingResolveToTheSamePhysicalPose() {
        let closing = [100.0, 80.0, 62.0].map(state)
        let opening = [62.0, 80.0, 100.0].map(state)

        XCTAssertEqual(closing[0], opening[2])
        XCTAssertEqual(closing[1], opening[1])
        XCTAssertEqual(closing[2], opening[0])
    }

    func testClosedSafetyRangeRemovesCaptureAndOverlay() {
        for angle in [0.0, 2.0, 4.0] {
            let state = self.state(angle: angle)
            XCTAssertFalse(state.isInCaptureRange)
            XCTAssertFalse(state.shouldShowOverlay)
        }
    }

    func testCapturePrewarmsBeforeVisualActivation() {
        let state = self.state(angle: 112)
        XCTAssertEqual(state.progress, 0, accuracy: 0.000_001)
        XCTAssertTrue(state.isInCaptureRange)
        XCTAssertFalse(state.shouldShowOverlay)
    }

    func testRoomLockIsIdentityAtActivation() {
        let size = CGSize(width: 1_512, height: 982)
        let projection = SEHingeProjectionGeometry.resolve(lockRadians: 0, screenSize: size)

        assertPoint(projection.picturePoint(forScreenPoint: .zero), equals: .zero)
        assertPoint(
            projection.picturePoint(forScreenPoint: CGPoint(x: size.width, y: size.height)),
            equals: CGPoint(x: size.width, y: size.height)
        )
    }

    func testRoomLockPinsHingeAndWidensFreeEdgeView() {
        let size = CGSize(width: 1_512, height: 982)
        let projection = SEHingeProjectionGeometry.resolve(lockRadians: 50 * .pi / 180, screenSize: size)
        let bottomLeft = projection.picturePoint(forScreenPoint: .zero)
        let bottomRight = projection.picturePoint(forScreenPoint: CGPoint(x: size.width, y: 0))
        let topLeft = projection.picturePoint(forScreenPoint: CGPoint(x: 0, y: size.height))
        let topRight = projection.picturePoint(forScreenPoint: CGPoint(x: size.width, y: size.height))

        assertPoint(bottomLeft, equals: .zero)
        assertPoint(bottomRight, equals: CGPoint(x: size.width, y: 0))
        // The lid's top edge has swung toward the viewer, so like a window held closer it shows a wider band of
        // the picture, centred, and a lower one: the picture's top rows are hidden behind the closing lid.
        XCTAssertLessThan(topLeft.x, 0)
        XCTAssertGreaterThan(topRight.x, size.width)
        XCTAssertEqual(topLeft.x + topRight.x, size.width, accuracy: 0.000_001)
        XCTAssertGreaterThan(topLeft.y, 0)
        XCTAssertLessThan(topLeft.y, size.height)
        XCTAssertEqual(topLeft.y, topRight.y, accuracy: 0.000_001)
    }

    func testMotionEstimatorFillsTheGapBetweenSensorReports() {
        var estimator = SEHingeMotionEstimator()
        estimator.update(angle: 90, at: 10)
        estimator.update(angle: 89, at: 10.1)

        let betweenReports = estimator.predictedAngle(at: 10.15)
        XCTAssertLessThan(betweenReports, 89)
        XCTAssertGreaterThan(betweenReports, 88)

        estimator.update(angle: 89, at: 10.33)
        XCTAssertEqual(estimator.predictedAngle(at: 10.34), 89, accuracy: 0.000_001)
    }

    func testFollowTargetLeadsAMovingLidAndSettlesWhenItStops() {
        var estimator = SEHingeMotionEstimator()
        for step in 0..<6 {
            estimator.update(angle: 90 - Double(step) * 2, at: 30 + Double(step) / 60)
        }
        let moving = estimator.followTarget(at: 30 + 5.0 / 60 + 0.01, springFrequency: 26)
        XCTAssertLessThan(moving, 80)
        XCTAssertGreaterThan(moving, 80 - 30)

        let stopped = estimator.followTarget(at: 30 + 5.0 / 60 + 0.3, springFrequency: 26)
        XCTAssertEqual(stopped, 80, accuracy: 0.000_001)
    }

    func testMotionEstimatorChangesDirectionWithoutOldMomentum() {
        var estimator = SEHingeMotionEstimator()
        estimator.update(angle: 90, at: 20)
        estimator.update(angle: 88, at: 20.1)
        estimator.update(angle: 89, at: 20.2)

        XCTAssertGreaterThan(estimator.angularVelocity, 0)
        XCTAssertGreaterThan(estimator.predictedAngle(at: 20.25), 89)
    }

    func testReduceMotionKeepsFrostAndDimmingButRemovesPerspective() {
        let state = SEHingeAnimationVisualState.resolve(
            angle: 45,
            activationAngle: 105,
            intensity: 1,
            maximumBlur: 18,
            reduceMotion: true
        )

        XCTAssertFalse(state.perspectiveEnabled)
        XCTAssertEqual(state.lockRadians, 0)
        XCTAssertGreaterThan(state.blurRadius, 0)
        XCTAssertLessThan(state.hingeBrightness, 1)
        XCTAssertTrue(state.shouldShowOverlay)
    }

    func testDuoDefaultsReachFullFrostAndHalfBrightnessWhenFolded() {
        let settings = Settings()
        XCTAssertEqual(settings.systemEnhanceHingeAnimationActivationAngle, 90)
        XCTAssertEqual(settings.systemEnhanceHingeAnimationIntensity, 1)
        XCTAssertEqual(settings.systemEnhanceHingeAnimationBlur, 135)

        let state = SEHingeAnimationVisualState.resolve(
            angle: SEHingeAnimationVisualState.foldedAngle,
            activationAngle: settings.systemEnhanceHingeAnimationActivationAngle,
            intensity: settings.systemEnhanceHingeAnimationIntensity,
            maximumBlur: settings.systemEnhanceHingeAnimationBlur
        )
        XCTAssertEqual(state.progress, 1, accuracy: 0.000_001)
        XCTAssertEqual(state.blurRadius, 135 * SEHingeAnimationVisualState.blurScale, accuracy: 0.000_001)
        XCTAssertEqual(state.hingeBrightness, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(state.edgeDarkening, 0.5, accuracy: 0.000_001)
    }

    func testPanelFadesOutToBlackBeforeTheLidCloses() {
        let fadeStart = state(angle: SEHingeAnimationVisualState.fadeOutAngle)
        let folded = state(angle: SEHingeAnimationVisualState.foldedAngle)
        let nearlyShut = state(angle: SEHingeAnimationVisualState.blackoutAngle)

        XCTAssertEqual(fadeStart.closure, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(folded.closure, 0)
        XCTAssertLessThan(folded.closure, 1)
        XCTAssertEqual(nearlyShut.closure, 1, accuracy: 0.000_001)
        XCTAssertTrue(nearlyShut.shouldShowOverlay)
    }

    func testFreeEdgeFadesEarlyInTheFold() {
        let earlyFold = state(angle: 90)
        XCTAssertGreaterThan(earlyFold.edgeDarkening, 0.25)
        XCTAssertGreaterThan(earlyFold.hingeBrightness, 0.95)
    }

    func testMalformedInputsFallBackToSafeFiniteValues() {
        let state = SEHingeAnimationVisualState.resolve(
            angle: .nan,
            activationAngle: .infinity,
            intensity: .nan,
            maximumBlur: -.infinity
        )

        XCTAssertTrue(state.progress.isFinite)
        XCTAssertTrue(state.blurRadius.isFinite)
        XCTAssertFalse(state.shouldShowOverlay)
    }

    func testNewSettingsRoundTrip() throws {
        var settings = Settings()
        settings.systemEnhanceHingeAnimationEnabled = true
        settings.systemEnhanceHingeAnimationActivationAngle = 97
        settings.systemEnhanceHingeAnimationIntensity = 1.25
        settings.systemEnhanceHingeAnimationBlur = 24

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertTrue(decoded.systemEnhanceHingeAnimationEnabled)
        XCTAssertEqual(decoded.systemEnhanceHingeAnimationActivationAngle, 97)
        XCTAssertEqual(decoded.systemEnhanceHingeAnimationIntensity, 1.25)
        XCTAssertEqual(decoded.systemEnhanceHingeAnimationBlur, 24)
    }

    private func state(angle: Double) -> SEHingeAnimationVisualState {
        SEHingeAnimationVisualState.resolve(
            angle: angle,
            activationAngle: 105,
            intensity: 1,
            maximumBlur: 18
        )
    }

    private func assertPoint(
        _ point: CGPoint,
        equals expected: CGPoint,
        accuracy: CGFloat = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(point.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.y, expected.y, accuracy: accuracy, file: file, line: line)
    }
}