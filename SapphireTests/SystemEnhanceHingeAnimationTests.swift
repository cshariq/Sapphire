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

    func testProjectiveGeometryIsIdentityAtActivation() {
        let size = CGSize(width: 1_512, height: 982)
        let projection = SEHingeProjectionGeometry.resolve(
            startAngle: 105,
            currentAngle: 105,
            intensity: 1,
            screenSize: size
        )

        assertPoint(projection.project(.zero), equals: .zero)
        assertPoint(
            projection.project(CGPoint(x: size.width, y: size.height)),
            equals: CGPoint(x: size.width, y: size.height)
        )
    }

    func testProjectiveGeometryPinsHingeAndRecedesFreeEdge() {
        let size = CGSize(width: 1_512, height: 982)
        let projection = SEHingeProjectionGeometry.resolve(
            startAngle: 105,
            currentAngle: 55,
            intensity: 1,
            screenSize: size
        )
        let bottomLeft = projection.project(.zero)
        let bottomRight = projection.project(CGPoint(x: size.width, y: 0))
        let topLeft = projection.project(CGPoint(x: 0, y: size.height))
        let topRight = projection.project(CGPoint(x: size.width, y: size.height))

        XCTAssertEqual(projection.separationRadians, 50 * .pi / 180, accuracy: 0.000_001)
        assertPoint(bottomLeft, equals: .zero)
        assertPoint(bottomRight, equals: CGPoint(x: size.width, y: 0))
        XCTAssertGreaterThan(topLeft.x, 0)
        XCTAssertLessThan(topRight.x, size.width)
        XCTAssertGreaterThan(topLeft.y, 0)
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
        XCTAssertGreaterThan(state.blurRadius, 0)
        XCTAssertGreaterThan(state.dimOpacity, 0)
        XCTAssertTrue(state.shouldShowOverlay)
    }

    func testDuoDefaultsUseRoomLockedRecessionAndStrongEdgeFrost() {
        let settings = Settings()
        XCTAssertEqual(settings.systemEnhanceHingeAnimationActivationAngle, 90)
        XCTAssertEqual(settings.systemEnhanceHingeAnimationIntensity, 1)
        XCTAssertEqual(settings.systemEnhanceHingeAnimationBlur, 135)

        let state = SEHingeAnimationVisualState.resolve(
            angle: 30,
            activationAngle: settings.systemEnhanceHingeAnimationActivationAngle,
            intensity: settings.systemEnhanceHingeAnimationIntensity,
            maximumBlur: settings.systemEnhanceHingeAnimationBlur
        )
        XCTAssertEqual(state.progress, 1, accuracy: 0.000_001)
        XCTAssertEqual(state.blurRadius, 135, accuracy: 0.000_001)
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