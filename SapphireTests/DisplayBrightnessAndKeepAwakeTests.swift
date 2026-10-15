//
//  DisplayBrightnessAndKeepAwakeTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import XCTest
@testable import Sapphire

final class DisplayBrightnessMathTests: XCTestCase {
    // MARK: - Coalescing

    func testMailboxStartsOneDrainAndKeepsOnlyTheNewestValue() {
        var mailbox = LatestValueMailbox<Int>()
        XCTAssertTrue(mailbox.post(1), "the first post starts a drain")
        XCTAssertFalse(mailbox.post(2), "a drain is already running")
        XCTAssertFalse(mailbox.post(3))

        XCTAssertEqual(mailbox.take(), 3, "older values are dropped, not queued")
        XCTAssertNil(mailbox.take())
        XCTAssertFalse(mailbox.isDraining)
    }

    func testMailboxPostDuringDrainIsPickedUpBeforeTheDrainEnds() {
        var mailbox = LatestValueMailbox<Int>()
        XCTAssertTrue(mailbox.post(10))
        XCTAssertEqual(mailbox.take(), 10)
        XCTAssertFalse(mailbox.post(20))
        XCTAssertEqual(mailbox.take(), 20)
        XCTAssertNil(mailbox.take())
        XCTAssertTrue(mailbox.post(30))
    }

    func testPacingWaitsOnlyForTheRemainderOfTheInterval() {
        XCTAssertEqual(DDCPacing.delay(sinceLastWrite: nil, minimumInterval: 0.05), 0)
        XCTAssertEqual(DDCPacing.delay(sinceLastWrite: 0.02, minimumInterval: 0.05), 0.03, accuracy: 0.0001)
        XCTAssertEqual(DDCPacing.delay(sinceLastWrite: 0.2, minimumInterval: 0.05), 0)
    }

    // MARK: - Gamma

    func testGammaScalingMultipliesEveryEntry() {
        XCTAssertEqual(DisplayBrightnessMath.scaled([0, 0.5, 1], by: 0.5), [0, 0.25, 0.5])
        XCTAssertEqual(DisplayBrightnessMath.scaled([0.25, 1], by: 1.5), [0.375, 1.5])
    }

    func testTablesMatchComparesClippedValuesWithinTolerance() {
        XCTAssertTrue(DisplayBrightnessMath.tablesMatch([0, 0.5, 1], [0.001, 0.502, 1]))
        XCTAssertFalse(DisplayBrightnessMath.tablesMatch([0, 0.5, 1], [0, 0.6, 1]))
        XCTAssertTrue(DisplayBrightnessMath.tablesMatch([0.5, 1], [0.5, 1.4]))
        XCTAssertFalse(DisplayBrightnessMath.tablesMatch([], []))
        XCTAssertFalse(DisplayBrightnessMath.tablesMatch([0.5], [0.5, 1]))
    }

    func testSoftwareOnlyDimmingNeverGoesBlack() {
        let off = DisplayBrightnessMath.split(level: 0, hardwareAvailable: false, extraDimming: false)
        XCTAssertNil(off.hardware)
        XCTAssertEqual(off.gamma, DisplayBrightnessMath.minimumGammaFactor)
        XCTAssertGreaterThan(off.gamma, 0)

        let full = DisplayBrightnessMath.split(level: 1, hardwareAvailable: false, extraDimming: false)
        XCTAssertEqual(full.gamma, 1)
    }

    func testHardwareWithoutExtraDimmingLeavesGammaAlone() {
        let split = DisplayBrightnessMath.split(level: 0.4, hardwareAvailable: true, extraDimming: false)
        XCTAssertEqual(split.hardware, 0.4)
        XCTAssertEqual(split.gamma, 1)
    }

    func testExtraDimmingUsesSoftwareBelowTheHardwareMinimum() {
        let share = DisplayBrightnessMath.extraDimmingShare

        let top = DisplayBrightnessMath.split(level: 1, hardwareAvailable: true, extraDimming: true)
        XCTAssertEqual(top.hardware, 1)
        XCTAssertEqual(top.gamma, 1)

        let boundary = DisplayBrightnessMath.split(level: share, hardwareAvailable: true, extraDimming: true)
        XCTAssertEqual(boundary.hardware ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(boundary.gamma, 1, accuracy: 0.0001)

        let dim = DisplayBrightnessMath.split(level: share / 2, hardwareAvailable: true, extraDimming: true)
        XCTAssertEqual(dim.hardware, 0)
        XCTAssertLessThan(dim.gamma, 1)
        XCTAssertGreaterThan(dim.gamma, DisplayBrightnessMath.minimumGammaFactor)
    }

    func testReadBackLevelRoundTripsThroughTheSplit() {
        for level: Float in [0.3, 0.5, 0.9, 1] {
            let split = DisplayBrightnessMath.split(level: level, hardwareAvailable: true, extraDimming: true)
            let restored = DisplayBrightnessMath.level(forHardware: split.hardware ?? 0, currentLevel: 0, extraDimming: true)
            XCTAssertEqual(restored, level, accuracy: 0.0001)
        }
        XCTAssertEqual(DisplayBrightnessMath.level(forHardware: 0, currentLevel: 0.1, extraDimming: true), 0.1, accuracy: 0.0001)
        XCTAssertEqual(DisplayBrightnessMath.level(forHardware: 0.6, currentLevel: 0, extraDimming: false), 0.6)
    }

    func testDDCValueMapsOntoTheMonitorRange() {
        XCTAssertEqual(DisplayBrightnessMath.ddcValue(level: 0, minimum: 0, maximum: 100), 0)
        XCTAssertEqual(DisplayBrightnessMath.ddcValue(level: 1, minimum: 0, maximum: 100), 100)
        XCTAssertEqual(DisplayBrightnessMath.ddcValue(level: 0.5, minimum: 10, maximum: 90), 50)
        XCTAssertEqual(DisplayBrightnessMath.ddcValue(level: 2, minimum: 0, maximum: 100), 100)
        XCTAssertEqual(DisplayBrightnessMath.ddcValue(level: 1, minimum: 50, maximum: 20), 50)
    }

    // MARK: - Steps

    func testKeyStepFractions() {
        XCTAssertEqual(BrightnessKeyStep.full.stepFraction(basePercent: 8), 0.08, accuracy: 0.0001)
        XCTAssertEqual(BrightnessKeyStep.half.stepFraction(basePercent: 8), 0.04, accuracy: 0.0001)
        XCTAssertEqual(BrightnessKeyStep.quarter.stepFraction(basePercent: 8), 0.02, accuracy: 0.0001)
        XCTAssertEqual(BrightnessKeyStep.quarter.stepFraction(basePercent: 1), 0.01, accuracy: 0.0001)
        XCTAssertEqual(BrightnessKeyStep.full.stepFraction(basePercent: 500), 1, accuracy: 0.0001)
    }

    func testNextLevelSnapsToTheStepGridAndClamps() {
        XCTAssertEqual(DisplayBrightnessMath.nextLevel(from: 0.5, step: 0.25, isUp: true, isFine: false), 0.75, accuracy: 0.0001)
        XCTAssertEqual(DisplayBrightnessMath.nextLevel(from: 0.9, step: 0.25, isUp: true, isFine: false), 1, accuracy: 0.0001)
        XCTAssertEqual(DisplayBrightnessMath.nextLevel(from: 0.1, step: 0.25, isUp: false, isFine: false), 0, accuracy: 0.0001)
        XCTAssertEqual(DisplayBrightnessMath.nextLevel(from: 0.5, step: 0.25, isUp: false, isFine: true), 0.49, accuracy: 0.0001)
        XCTAssertEqual(DisplayBrightnessMath.nextLevel(from: 1, step: 0.25, isUp: true, isFine: true), 1, accuracy: 0.0001)
    }
}

final class KeepAwakeTriggerEvaluatorTests: XCTestCase {
    func testNothingEnabledNeverKeepsAwake() {
        var state = KeepAwakeTriggerState()
        state.onACPower = true
        state.externalDisplayConnected = true
        state.watchedAppRunning = true
        XCTAssertFalse(KeepAwakeTriggerEvaluator.shouldKeepAwake(KeepAwakeTriggerConfiguration(), state))
    }

    func testEachTriggerOnlyCountsWhenEnabled() {
        var state = KeepAwakeTriggerState()
        state.onACPower = true
        XCTAssertTrue(KeepAwakeTriggerEvaluator.shouldKeepAwake(.init(whileOnACPower: true), state))
        XCTAssertFalse(KeepAwakeTriggerEvaluator.shouldKeepAwake(.init(whileExternalDisplay: true), state))

        state = KeepAwakeTriggerState()
        state.externalDisplayConnected = true
        XCTAssertTrue(KeepAwakeTriggerEvaluator.shouldKeepAwake(.init(whileExternalDisplay: true), state))

        state = KeepAwakeTriggerState()
        state.watchedAppRunning = true
        XCTAssertTrue(KeepAwakeTriggerEvaluator.shouldKeepAwake(.init(whileAppsRun: true, appBundleIDs: ["com.example.app"]), state))
    }

    func testAppTriggerWithoutAppsIsOff() {
        let configuration = KeepAwakeTriggerConfiguration(whileAppsRun: true, appBundleIDs: [])
        XCTAssertFalse(configuration.hasAnyTrigger)
        var state = KeepAwakeTriggerState()
        state.watchedAppRunning = true
        XCTAssertFalse(KeepAwakeTriggerEvaluator.shouldKeepAwake(configuration, state))
    }

    func testLockPausesTriggersOnlyWhenAskedTo() {
        var state = KeepAwakeTriggerState()
        state.onACPower = true
        state.screenLocked = true
        XCTAssertTrue(KeepAwakeTriggerEvaluator.shouldKeepAwake(.init(whileOnACPower: true), state))
        XCTAssertFalse(KeepAwakeTriggerEvaluator.shouldKeepAwake(.init(whileOnACPower: true, pauseWhenLocked: true), state))
        XCTAssertTrue(KeepAwakeTriggerConfiguration(whileOnACPower: true, pauseWhenLocked: true).watchesLock)
        XCTAssertFalse(KeepAwakeTriggerConfiguration(pauseWhenLocked: true).watchesLock)
    }

    func testOnlyRealExternalDisplaysCount() {
        XCTAssertFalse(KeepAwakeTriggerEvaluator.hasExternalDisplay([(isBuiltIn: true, isVirtual: false)]))
        XCTAssertFalse(KeepAwakeTriggerEvaluator.hasExternalDisplay([(isBuiltIn: true, isVirtual: false), (isBuiltIn: false, isVirtual: true)]))
        XCTAssertTrue(KeepAwakeTriggerEvaluator.hasExternalDisplay([(isBuiltIn: false, isVirtual: false)]))
        XCTAssertFalse(KeepAwakeTriggerEvaluator.hasExternalDisplay([]))
    }
}