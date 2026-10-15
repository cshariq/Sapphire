//
//  MixerSupportTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import XCTest
import AppKit
@testable import Sapphire

final class MixerSupportTests: XCTestCase {

    // MARK: Limiter

    func testLimiterKeepsBoostedPeaksUnderCeilingWithoutHardClipping() {
        let limiter = LookaheadLimiter(sampleRate: 48000, lookaheadSeconds: 0.002)
        let frames = 4800
        var buffer = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let value = 2.0 * sinf(2 * .pi * 1000 * Float(frame) / 48000)
            buffer[frame * 2] = value
            buffer[frame * 2 + 1] = value
        }
        buffer.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, frames: frames, channels: 2) }
        let peak = buffer.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 1.0)
        XCTAssertGreaterThan(peak, 0.9, "the limiter should not crush the signal")
        let atCeiling = buffer.filter { abs($0) >= limiter.ceiling - 1e-6 }.count
        XCTAssertLessThan(atCeiling, buffer.count / 10)
    }

    func testLimiterPassesQuietAudioThroughDelayedOnly() {
        let limiter = LookaheadLimiter(sampleRate: 48000, lookaheadSeconds: 0.002)
        let delay = limiter.latencyFrames
        let frames = 1024
        var buffer = (0..<frames).map { Float($0 % 50) / 100 }
        let input = buffer
        buffer.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, frames: frames, channels: 1) }
        for index in 0..<delay { XCTAssertEqual(buffer[index], 0) }
        for index in delay..<frames { XCTAssertEqual(buffer[index], input[index - delay], accuracy: 1e-6) }
        XCTAssertEqual(limiter.envelope, 1)
    }

    func testLimiterGainComesDownBeforeTheTransientLeavesTheDelay() {
        let limiter = LookaheadLimiter(sampleRate: 48000, lookaheadSeconds: 0.002)
        let frames = 2048
        var buffer = [Float](repeating: 0.1, count: frames)
        buffer[1000] = 3.0
        buffer.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, frames: frames, channels: 1) }
        let delayedSpike = buffer[1000 + limiter.latencyFrames]
        XCTAssertLessThanOrEqual(abs(delayedSpike), 1.0)
        XCTAssertGreaterThan(abs(delayedSpike), 0.9)
    }

    func testSoftKneeIsContinuousAndBounded() {
        XCTAssertEqual(LookaheadLimiter.softKnee(0.5, ceiling: 0.97), 0.5)
        XCTAssertEqual(LookaheadLimiter.softKnee(0.97, ceiling: 0.97), 0.97, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(LookaheadLimiter.softKnee(10, ceiling: 0.97), 1.0)
        XCTAssertEqual(LookaheadLimiter.softKnee(-10, ceiling: 0.97), -LookaheadLimiter.softKnee(10, ceiling: 0.97))
    }

    // MARK: Ramp

    func testGainRampIsLinearAcrossTheBuffer() {
        let frames = 4
        let input = [Float](repeating: 1, count: frames * 2)
        var output = [Float](repeating: 0, count: frames * 2)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                GainRamp.apply(input: inPtr.baseAddress!, output: outPtr.baseAddress!, frames: frames, channels: 2, from: 0, to: 1)
            }
        }
        XCTAssertEqual(output, [0, 0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75])
        XCTAssertEqual(GainRamp.step(from: 1, to: 0.5, frames: 10), -0.05, accuracy: 1e-6)
        XCTAssertEqual(GainRamp.step(from: 1, to: 0.5, frames: 0), 0)
    }

    func testUnchangedGainIsAPlainScale() {
        let input: [Float] = [0.5, -0.5, 1, -1]
        var output = [Float](repeating: 0, count: 4)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                GainRamp.apply(input: inPtr.baseAddress!, output: outPtr.baseAddress!, frames: 2, channels: 2, from: 2, to: 2)
            }
        }
        XCTAssertEqual(output, [1, -1, 2, -2])
    }

    // MARK: Routing

    func testRouteFallsBackToMixerOutputsWhileItsDeviceIsUnplugged() {
        let available: Set<String> = ["speakers", "dac"]
        XCTAssertEqual(MixerRouting.targetUIDs(route: "airpods", availableUIDs: available, globalOutputUIDs: ["speakers"]), ["speakers"])
        XCTAssertEqual(MixerRouting.targetUIDs(route: "dac", availableUIDs: available, globalOutputUIDs: ["speakers"]), ["dac"])
        XCTAssertEqual(MixerRouting.targetUIDs(route: nil, availableUIDs: available, globalOutputUIDs: ["speakers", "dac"]), ["speakers", "dac"])
    }

    func testRouteToTheCurrentOutputNeedsNoTap() {
        let available: Set<String> = ["speakers", "dac"]
        XCTAssertFalse(MixerRouting.routeRequiresTap(route: "speakers", availableUIDs: available, globalOutputUIDs: ["speakers"]))
        XCTAssertTrue(MixerRouting.routeRequiresTap(route: "dac", availableUIDs: available, globalOutputUIDs: ["speakers"]))
        XCTAssertFalse(MixerRouting.routeRequiresTap(route: "gone", availableUIDs: available, globalOutputUIDs: ["speakers"]))
    }

    func testGlobalOutputsUseConnectedSelectionElseDefault() {
        XCTAssertEqual(MixerRouting.globalOutputUIDs(selectedUIDs: ["a", "gone"], availableUIDs: ["a", "b"], defaultUID: "b"), ["a"])
        XCTAssertEqual(MixerRouting.globalOutputUIDs(selectedUIDs: ["gone"], availableUIDs: ["a", "b"], defaultUID: "b"), ["b"])
        XCTAssertEqual(MixerRouting.globalOutputUIDs(selectedUIDs: [], availableUIDs: [], defaultUID: nil), [])
    }

    // MARK: Mailbox

    func testMailboxCoalescesToTheLatestPlanAndDropsDuplicates() {
        var mailbox = LatestOnlyMailbox<Int>()
        XCTAssertTrue(mailbox.post(1))
        XCTAssertFalse(mailbox.post(2), "a drain is already scheduled")
        XCTAssertEqual(mailbox.take(), 2)
        mailbox.markApplied(2)
        XCTAssertNil(mailbox.take())
        XCTAssertFalse(mailbox.isDraining)
        XCTAssertTrue(mailbox.post(2))
        XCTAssertNil(mailbox.take(), "same as the applied plan")
        XCTAssertTrue(mailbox.post(2, force: true))
        XCTAssertEqual(mailbox.take(), 2)
    }

    func testForcedRebuildKeepsANewerPendingPlan() {
        var mailbox = LatestOnlyMailbox<Int>()
        XCTAssertTrue(mailbox.post(1))
        XCTAssertEqual(mailbox.take(), 1)
        mailbox.markApplied(1)
        XCTAssertNil(mailbox.take())
        XCTAssertTrue(mailbox.post(2))
        XCTAssertFalse(mailbox.forceRebuild(fallback: 1), "a drain is already scheduled")
        XCTAssertEqual(mailbox.take(), 2)
        mailbox.markApplied(2)
        XCTAssertNil(mailbox.take())
        XCTAssertTrue(mailbox.forceRebuild(fallback: 2))
        XCTAssertEqual(mailbox.take(), 2)
        var empty = LatestOnlyMailbox<Int>()
        XCTAssertFalse(empty.forceRebuild(fallback: nil))
    }

    // MARK: Watchdog

    func testWatchdogRebuildsOnceThenFailsOpen() {
        var state = TapWatchdogState()
        XCTAssertEqual(state.observe(renderCount: 10), .healthy)
        XCTAssertEqual(state.observe(renderCount: 10), .waiting)
        XCTAssertEqual(state.observe(renderCount: 10), .rebuild)
        state.lastRenderCount = 0
        XCTAssertEqual(state.observe(renderCount: 0), .waiting)
        XCTAssertEqual(state.observe(renderCount: 0), .failOpen)
    }

    func testWatchdogForgivesAfterALongHealthyRun() {
        var state = TapWatchdogState(rebuilds: 1)
        for count in 1...UInt64(TapWatchdogState.healthyChecksToForgive) {
            XCTAssertEqual(state.observe(renderCount: count), .healthy)
        }
        XCTAssertEqual(state.rebuilds, 0)
    }

    // MARK: Ordering

    func testPinnedAppsComeFirstAndHiddenAppsAreRemoved() {
        var ordering = MixerAppOrdering()
        ordering.togglePin("c")
        ordering.hide("b")
        XCTAssertEqual(ordering.arrange(["a", "b", "c", "d"]), ["c", "a", "d"])
        ordering.unhide("b")
        XCTAssertEqual(ordering.arrange(["a", "b", "c"]), ["c", "a", "b"])
    }

    func testMovingAnAppReordersPins() {
        var ordering = MixerAppOrdering(pinned: ["a", "b"])
        ordering.move("b", offset: -1, visible: ["a", "b", "c"])
        XCTAssertEqual(ordering.pinned, ["b", "a"])
        ordering.move("c", offset: -1, visible: ["a", "b", "c"])
        XCTAssertEqual(ordering.arrange(["a", "b", "c"]), ["b", "c", "a"])
    }

    func testHidingUnpins() {
        var ordering = MixerAppOrdering(pinned: ["a"])
        ordering.hide("a")
        XCTAssertFalse(ordering.isPinned("a"))
        ordering.unhideAll()
        XCTAssertTrue(ordering.hidden.isEmpty)
    }

    // MARK: Output switching

    func testOutputCycleStepsThroughConnectedChoices() {
        let available: Set<String> = ["a", "b", "c"]
        XCTAssertEqual(OutputCycle.next(currentUID: "a", chosenUIDs: ["a", "b", "c"], availableUIDs: available), "b")
        XCTAssertEqual(OutputCycle.next(currentUID: "c", chosenUIDs: ["a", "b", "c"], availableUIDs: available), "a")
        XCTAssertEqual(OutputCycle.next(currentUID: "a", chosenUIDs: ["a", "gone", "c"], availableUIDs: available), "c")
        XCTAssertEqual(OutputCycle.next(currentUID: "x", chosenUIDs: ["b", "c"], availableUIDs: available), "b")
        XCTAssertNil(OutputCycle.next(currentUID: "a", chosenUIDs: ["a"], availableUIDs: available))
        XCTAssertNil(OutputCycle.next(currentUID: "a", chosenUIDs: [], availableUIDs: available))
    }

    func testHeadphoneDisconnectLowersSpeakersAndReconnectRestores() {
        let headphones = HeadphoneDisconnectPolicy.OutputState(uid: "bt", isHeadphones: true, isBuiltInSpeaker: false)
        let speakers = HeadphoneDisconnectPolicy.OutputState(uid: "spk", isHeadphones: false, isBuiltInSpeaker: true)
        XCTAssertEqual(HeadphoneDisconnectPolicy.decide(previous: headphones, current: speakers, previousStillConnected: false,
                                                        speakerVolume: 0.8, targetLevel: 0.25, hasSavedVolume: false),
                       .lower(speakerUID: "spk", level: 0.25))
        XCTAssertEqual(HeadphoneDisconnectPolicy.decide(previous: headphones, current: speakers, previousStillConnected: true,
                                                        speakerVolume: 0.8, targetLevel: 0.25, hasSavedVolume: false), .none)
        XCTAssertEqual(HeadphoneDisconnectPolicy.decide(previous: headphones, current: speakers, previousStillConnected: false,
                                                        speakerVolume: 0.2, targetLevel: 0.25, hasSavedVolume: false), .none)
        XCTAssertEqual(HeadphoneDisconnectPolicy.decide(previous: speakers, current: headphones, previousStillConnected: true,
                                                        speakerVolume: nil, targetLevel: 0.25, hasSavedVolume: true),
                       .restore(speakerUID: "spk"))
    }

    func testWiredHeadphonesOnTheSameJackLowerSpeakers() {
        let jackHeadphones = HeadphoneDisconnectPolicy.OutputState(uid: "builtin", isHeadphones: true, isBuiltInSpeaker: false)
        let jackSpeakers = HeadphoneDisconnectPolicy.OutputState(uid: "builtin", isHeadphones: false, isBuiltInSpeaker: true)
        XCTAssertEqual(HeadphoneDisconnectPolicy.decide(previous: jackHeadphones, current: jackSpeakers, previousStillConnected: true,
                                                        speakerVolume: 0.6, targetLevel: 0.3, hasSavedVolume: false),
                       .lower(speakerUID: "builtin", level: 0.3))
    }

    func testPreferredInputIsRestoredOnlyWhenConnectedAndNotAlreadyDefault() {
        XCTAssertEqual(PreferredInputPolicy.deviceToSelect(preferredUID: "usb", currentDefaultUID: "airpods", availableUIDs: ["usb", "airpods"]), "usb")
        XCTAssertNil(PreferredInputPolicy.deviceToSelect(preferredUID: "usb", currentDefaultUID: "usb", availableUIDs: ["usb"]))
        XCTAssertNil(PreferredInputPolicy.deviceToSelect(preferredUID: "usb", currentDefaultUID: "airpods", availableUIDs: ["airpods"]))
        XCTAssertNil(PreferredInputPolicy.deviceToSelect(preferredUID: nil, currentDefaultUID: "airpods", availableUIDs: ["airpods"]))
    }

    // MARK: Meter

    func testMeterReleasesOneReadingPerInterval() {
        var meter = MeterAccumulator(sampleRate: 48000, updatesPerSecond: 20)
        XCTAssertEqual(meter.intervalFrames, 2400)
        var readings: [MeterAccumulator.Reading] = []
        for _ in 0..<10 {
            if let reading = meter.add(sumOfSquares: 1024 * 0.25, peak: 0.5, sampleCount: 1024, frameCount: 512) {
                readings.append(reading)
            }
        }
        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings[0].rms, 0.5, accuracy: 1e-6)
        XCTAssertEqual(readings[0].peak, 0.5)
    }

    // MARK: Hotkeys

    func testHotkeyMatchingIsExact() {
        let table = AudioHotkeyTable()
        let commandOption = AudioHotkeyTable.modifierMask([.command, .option] as NSEvent.ModifierFlags)
        table.replace(with: [AudioHotkeyTable.Trigger(keyCode: 46, modifiers: commandOption): .toggleMicMute])
        XCTAssertEqual(table.action(keyCode: 46, flags: [.maskCommand, .maskAlternate]), .toggleMicMute)
        XCTAssertEqual(table.action(keyCode: 46, flags: [.maskCommand, .maskAlternate, .maskAlphaShift, .maskSecondaryFn]), .toggleMicMute)
        XCTAssertNil(table.action(keyCode: 46, flags: [.maskCommand, .maskAlternate, .maskShift]))
        XCTAssertNil(table.action(keyCode: 46, flags: [.maskCommand]))
    }
}