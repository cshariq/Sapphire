//
//  InputParityLogicTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import Carbon.HIToolbox
import IOKit.hidsystem
import XCTest
@testable import Sapphire

final class QuitProtectionLogicTests: XCTestCase {
    private let q = UInt16(kVK_ANSI_Q)
    private let ms: UInt64 = 1_000_000

    private func rule(_ mode: SEQuitProtectionMode, extra: SEQuitProtectionExtraModifier = .option) -> SEQuitProtectionRule {
        SEQuitProtectionRule(mode: mode, holdInterval: 1, doublePressInterval: 0.5, extraModifier: extra)
    }

    func testExtraModifierModeLetsSystemChordsThrough() {
        var machine = SEQuitProtectionStateMachine()
        let r = rule(.extraModifier, extra: .option)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: [.maskCommand, .maskControl], isRepeat: false, timestamp: 0, rule: r), .pass)
        XCTAssertEqual(machine.keyUp(keyCode: q), .pass)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: [.maskCommand, .maskShift], isRepeat: false, timestamp: 0, rule: r), .pass)
        XCTAssertEqual(machine.keyUp(keyCode: q), .pass)
    }

    func testExtraModifierModeRequiresTheModifier() {
        var machine = SEQuitProtectionStateMachine()
        let r = rule(.extraModifier, extra: .option)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 0, rule: r), .hintExtraModifier)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: true, timestamp: 0, rule: nil), .swallow)
        XCTAssertEqual(machine.keyUp(keyCode: q), .swallow)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: [.maskCommand, .maskAlternate], isRepeat: false, timestamp: 0, rule: r), .grant)
        XCTAssertEqual(machine.keyUp(keyCode: q), .swallow)
    }

    func testControlAsConfiguredModifierClaimsControlCommandQ() {
        var machine = SEQuitProtectionStateMachine()
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: [.maskCommand, .maskControl], isRepeat: false, timestamp: 0, rule: rule(.extraModifier, extra: .control)), .grant)
    }

    func testHoldStartsAndCancelsOnRelease() {
        var machine = SEQuitProtectionStateMachine()
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 0, rule: rule(.hold)), .startHold)
        XCTAssertEqual(machine.keyUp(keyCode: q), .cancelHold)
        XCTAssertFalse(machine.holdElapsed(keyCode: q))
    }

    func testHoldCompletesAndSwallowsTheLaterRelease() {
        var machine = SEQuitProtectionStateMachine()
        _ = machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 0, rule: rule(.hold))
        XCTAssertTrue(machine.holdElapsed(keyCode: q))
        XCTAssertEqual(machine.keyUp(keyCode: q), .swallow)
        XCTAssertTrue(machine.isIdle)
    }

    func testHoldModeIgnoresOtherChords() {
        var machine = SEQuitProtectionStateMachine()
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: [.maskCommand, .maskShift], isRepeat: false, timestamp: 0, rule: rule(.hold)), .pass)
    }

    func testDoublePressWithinAndOutsideTheWindow() {
        var machine = SEQuitProtectionStateMachine()
        let r = rule(.doublePress)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 0, rule: r), .awaitSecondPress)
        _ = machine.keyUp(keyCode: q)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 300 * ms, rule: r), .grant)
        _ = machine.keyUp(keyCode: q)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 1_000 * ms, rule: r), .awaitSecondPress)
        _ = machine.keyUp(keyCode: q)
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 1_600 * ms, rule: r), .awaitSecondPress)
    }

    func testUnprotectedKeyPasses() {
        var machine = SEQuitProtectionStateMachine()
        XCTAssertEqual(machine.keyDown(keyCode: q, flags: .maskCommand, isRepeat: false, timestamp: 0, rule: nil), .pass)
        XCTAssertEqual(machine.keyUp(keyCode: q), .pass)
    }
}

final class ScrollTransformTests: XCTestCase {
    private let ms: UInt64 = 1_000_000

    func testClassifiesTrackpadAndMomentumAsContinuous() {
        XCTAssertEqual(MouseScrollTransform.kind(isContinuous: 0, scrollPhase: 0, momentumPhase: 0), .discreteWheel)
        XCTAssertEqual(MouseScrollTransform.kind(isContinuous: 1, scrollPhase: 0, momentumPhase: 0), .continuous)
        XCTAssertEqual(MouseScrollTransform.kind(isContinuous: 0, scrollPhase: 2, momentumPhase: 0), .continuous)
        XCTAssertEqual(MouseScrollTransform.kind(isContinuous: 0, scrollPhase: 0, momentumPhase: 1), .continuous)
    }

    func testInversionFlipsAllRepresentations() {
        var carry = WheelLineCarry()
        let result = MouseScrollTransform.transform(
            WheelDeltas(lineY: 1, fixedY: 1, pointY: 10),
            flags: [],
            settings: WheelTransformSettings(invertVertical: true),
            carry: &carry,
            timestamp: 1
        )
        XCTAssertEqual(result.deltas.lineY, -1)
        XCTAssertEqual(result.deltas.fixedY, -1)
        XCTAssertEqual(result.deltas.pointY, -10)
    }

    func testSlowSpeedCarriesFractionalLines() {
        var carry = WheelLineCarry()
        let settings = WheelTransformSettings(speed: 0.5)
        var lines: [Int64] = []
        for step in 1...4 {
            lines.append(MouseScrollTransform.transform(WheelDeltas(lineY: 1, fixedY: 1, pointY: 10), flags: [], settings: settings, carry: &carry, timestamp: UInt64(step) * 10 * ms).deltas.lineY)
        }
        XCTAssertEqual(lines.reduce(0, +), 2)
        XCTAssertTrue(lines.allSatisfy { $0 == 0 || $0 == 1 })
    }

    func testLinearIgnoresAccelerationAndKeepsDirection() {
        var carry = WheelLineCarry()
        let settings = WheelTransformSettings(linear: true, linesPerNotch: 3)
        let fast = MouseScrollTransform.transform(WheelDeltas(lineY: -7, fixedY: -6.5, pointY: -65), flags: [], settings: settings, carry: &carry, timestamp: 1)
        XCTAssertEqual(fast.deltas.lineY, -3)
        XCTAssertEqual(fast.deltas.fixedY, -3)
        XCTAssertEqual(fast.deltas.pointY, -30, accuracy: 0.001)
    }

    func testLinearFractionalNotchesAddUp() {
        var carry = WheelLineCarry()
        let settings = WheelTransformSettings(linear: true, linesPerNotch: 1.5)
        let first = MouseScrollTransform.transform(WheelDeltas(lineY: 1, fixedY: 1, pointY: 10), flags: [], settings: settings, carry: &carry, timestamp: 10 * ms)
        let second = MouseScrollTransform.transform(WheelDeltas(lineY: 1, fixedY: 1, pointY: 10), flags: [], settings: settings, carry: &carry, timestamp: 20 * ms)
        XCTAssertEqual(first.deltas.lineY + second.deltas.lineY, 3)
    }

    func testCarryResetsOnReversalAndIdle() {
        var carry = WheelLineCarry()
        _ = carry.lines(y: 0.7, x: 0, timestamp: 10 * ms)
        XCTAssertEqual(carry.lines(y: -0.7, x: 0, timestamp: 20 * ms).y, 0)
        XCTAssertEqual(carry.y, -0.7, accuracy: 0.0001)
        _ = carry.lines(y: 0.7, x: 0, timestamp: 30 * ms)
        XCTAssertEqual(carry.lines(y: 0.7, x: 0, timestamp: 2_000 * ms).y, 0)
    }

    func testSidewaysModifierMovesVerticalToHorizontalAndClearsFlag() {
        var carry = WheelLineCarry()
        let result = MouseScrollTransform.transform(
            WheelDeltas(lineY: 1, fixedY: 1, pointY: 10),
            flags: .maskAlternate,
            settings: WheelTransformSettings(sidewaysModifier: .maskAlternate),
            carry: &carry,
            timestamp: 1
        )
        XCTAssertEqual(result.deltas.lineY, 0)
        XCTAssertEqual(result.deltas.lineX, 1)
        XCTAssertEqual(result.deltas.pointX, 10)
        XCTAssertEqual(result.flagsToClear, .maskAlternate)
    }

    func testIdentitySettingsAreDetected() {
        XCTAssertTrue(WheelTransformSettings().isIdentity)
        XCTAssertFalse(WheelTransformSettings(speed: 2).isIdentity)
    }

    func testGlideEmitsExactlyTheDistanceAndFinishes() {
        var glide = ScrollGlide(timeConstant: 0.05)
        glide.add(y: 100, x: -37)
        var totalY = 0, totalX = 0, frames = 0
        while !glide.isFinished, frames < 1_000 {
            let step = glide.step(dt: 1.0 / 120)
            totalY += Int(step.y)
            totalX += Int(step.x)
            frames += 1
        }
        XCTAssertTrue(glide.isFinished)
        XCTAssertEqual(totalY, 100)
        XCTAssertEqual(totalX, -37)
        XCTAssertLessThan(frames, 120)
    }

    func testGlideReversalDropsTheOldDistance() {
        var glide = ScrollGlide(timeConstant: 0.05)
        glide.add(y: 100, x: 0)
        _ = glide.step(dt: 1.0 / 120)
        glide.add(y: -40, x: 0)
        XCTAssertEqual(glide.remainingY, -40)
    }
}

final class FilterLogicTests: XCTestCase {
    private let ms: UInt64 = 1_000_000

    func testClickChatterMeasuredFromRelease() {
        var filter = ClickChatterFilter()
        let p = CGPoint(x: 10, y: 10)
        XCTAssertFalse(filter.down(button: 0, timestamp: 0, point: p, windowNanoseconds: 80 * ms, hasModifiers: false))
        XCTAssertFalse(filter.up(button: 0, timestamp: 500 * ms, point: p))
        XCTAssertTrue(filter.down(button: 0, timestamp: 530 * ms, point: p, windowNanoseconds: 80 * ms, hasModifiers: false))
        XCTAssertTrue(filter.up(button: 0, timestamp: 540 * ms, point: p))
        XCTAssertFalse(filter.down(button: 0, timestamp: 700 * ms, point: p, windowNanoseconds: 80 * ms, hasModifiers: false))
    }

    func testAcceptedDownsUpIsNeverSwallowed() {
        var filter = ClickChatterFilter()
        let p = CGPoint.zero
        XCTAssertFalse(filter.down(button: 1, timestamp: 0, point: p, windowNanoseconds: 80 * ms, hasModifiers: false))
        XCTAssertFalse(filter.up(button: 1, timestamp: 10 * ms, point: p))
        XCTAssertFalse(filter.down(button: 2, timestamp: 20 * ms, point: p, windowNanoseconds: 80 * ms, hasModifiers: false))
        XCTAssertFalse(filter.up(button: 2, timestamp: 30 * ms, point: p))
    }

    func testClickFarAwayOrWithModifiersIsKept() {
        var filter = ClickChatterFilter()
        _ = filter.down(button: 0, timestamp: 0, point: .zero, windowNanoseconds: 80 * ms, hasModifiers: false)
        _ = filter.up(button: 0, timestamp: 10 * ms, point: .zero)
        XCTAssertFalse(filter.down(button: 0, timestamp: 20 * ms, point: CGPoint(x: 100, y: 0), windowNanoseconds: 80 * ms, hasModifiers: false))
        _ = filter.up(button: 0, timestamp: 30 * ms, point: CGPoint(x: 100, y: 0))
        XCTAssertFalse(filter.down(button: 0, timestamp: 40 * ms, point: CGPoint(x: 100, y: 0), windowNanoseconds: 80 * ms, hasModifiers: true))
    }

    func testKeyChatterIsPerKey() {
        var filter = KeyChatterFilter()
        let a: UInt16 = 0, b: UInt16 = 11
        XCTAssertFalse(filter.keyDown(keyCode: a, timestamp: 0, isRepeat: false, windowNanoseconds: 45 * ms))
        XCTAssertFalse(filter.keyUp(keyCode: a, timestamp: 50 * ms))
        XCTAssertFalse(filter.keyDown(keyCode: b, timestamp: 55 * ms, isRepeat: false, windowNanoseconds: 45 * ms))
        XCTAssertFalse(filter.keyUp(keyCode: b, timestamp: 60 * ms))
        XCTAssertTrue(filter.keyDown(keyCode: a, timestamp: 70 * ms, isRepeat: false, windowNanoseconds: 45 * ms))
        XCTAssertTrue(filter.keyDown(keyCode: a, timestamp: 75 * ms, isRepeat: true, windowNanoseconds: 45 * ms))
        XCTAssertTrue(filter.keyUp(keyCode: a, timestamp: 80 * ms))
        XCTAssertFalse(filter.keyDown(keyCode: a, timestamp: 200 * ms, isRepeat: false, windowNanoseconds: 45 * ms))
    }

    func testPerKeyWindowOverride() {
        XCTAssertEqual(KeyChatterFilter.window(for: 14, global: 0.045, overrides: [14: 0.1]), 100 * ms)
        XCTAssertEqual(KeyChatterFilter.window(for: 15, global: 0.045, overrides: [14: 0.1]), 45 * ms)
        XCTAssertEqual(KeyChatterFilter.window(for: 14, global: 0.045, overrides: [14: 0]), 0)
    }

    func testPointerRestFiresOnceAfterDelay() {
        var rest = PointerRestDebouncer()
        rest.noteMove(at: 0, location: .zero, modifiersHeld: false)
        XCTAssertFalse(rest.takeRest(now: 100 * ms, delay: 500 * ms))
        XCTAssertTrue(rest.takeRest(now: 500 * ms, delay: 500 * ms))
        XCTAssertFalse(rest.takeRest(now: 900 * ms, delay: 500 * ms))
        rest.noteMove(at: 1_000 * ms, location: .zero, modifiersHeld: true)
        XCTAssertFalse(rest.takeRest(now: 2_000 * ms, delay: 500 * ms))
        rest.noteButtonDown(at: 3_000 * ms)
        XCTAssertEqual(rest.restDeadline(delay: 100 * ms), 3_600 * ms)
    }
}

final class SuperKeyAndMappingTests: XCTestCase {
    private let ms: UInt64 = 1_000_000
    private let rightCommand = SESuperKeyKey.rightCommand.trigger
    private let rCmdCode = CGKeyCode(kVK_RightCommand)

    func testReleaseIsSeenDespiteSyntheticLeftCommand() {
        var machine = SuperKeyStateMachine()
        let down = CGEventFlags.maskCommand.rawValue | SuperKeyDeviceMask.rightCommand
        XCTAssertEqual(machine.flagsChanged(keyCode: rCmdCode, rawFlags: down, trigger: rightCommand, excluded: false, timestamp: 0).effect, .beginHold)
        let up = CGEventFlags.maskCommand.rawValue | SuperKeyDeviceMask.leftCommand
        let result = machine.flagsChanged(keyCode: rCmdCode, rawFlags: up, trigger: rightCommand, excluded: false, timestamp: 100 * ms)
        XCTAssertEqual(result.effect, .endHold(fireTapAction: true))
        XCTAssertFalse(machine.isHeld)
    }

    func testClickWhileHeldCountsAsUse() {
        var machine = SuperKeyStateMachine()
        _ = machine.flagsChanged(keyCode: rCmdCode, rawFlags: SuperKeyDeviceMask.rightCommand, trigger: rightCommand, excluded: false, timestamp: 0)
        machine.pointerDown()
        XCTAssertEqual(machine.flagsChanged(keyCode: rCmdCode, rawFlags: 0, trigger: rightCommand, excluded: false, timestamp: 50 * ms).effect, .endHold(fireTapAction: false))
    }

    func testLongHoldDoesNotFireTapAction() {
        var machine = SuperKeyStateMachine()
        _ = machine.flagsChanged(keyCode: rCmdCode, rawFlags: SuperKeyDeviceMask.rightCommand, trigger: rightCommand, excluded: false, timestamp: 0)
        XCTAssertEqual(machine.flagsChanged(keyCode: rCmdCode, rawFlags: 0, trigger: rightCommand, excluded: false, timestamp: 900 * ms).effect, .endHold(fireTapAction: false))
    }

    func testExcludedAppPassesThePressAndRelease() {
        var machine = SuperKeyStateMachine()
        XCTAssertEqual(machine.flagsChanged(keyCode: rCmdCode, rawFlags: SuperKeyDeviceMask.rightCommand, trigger: rightCommand, excluded: true, timestamp: 0), .pass)
        XCTAssertEqual(machine.flagsChanged(keyCode: rCmdCode, rawFlags: 0, trigger: rightCommand, excluded: false, timestamp: 10 * ms), .pass)
        XCTAssertFalse(machine.isPassingThrough)
    }

    func testCapsLockKeyTriggerSwallowsRepeats() {
        var machine = SuperKeyStateMachine()
        let trigger = SESuperKeyKey.capsLock.trigger
        let code = CapsLockKeyMapping.remappedKeyCode
        XCTAssertEqual(machine.keyDown(keyCode: code, isRepeat: false, trigger: trigger, excluded: false, timestamp: 0).effect, .beginHold)
        XCTAssertEqual(machine.keyDown(keyCode: code, isRepeat: true, trigger: trigger, excluded: false, timestamp: 10 * ms), .swallow)
        XCTAssertEqual(machine.keyDown(keyCode: 0, isRepeat: false, trigger: trigger, excluded: false, timestamp: 20 * ms), .pass)
        XCTAssertEqual(machine.keyUp(keyCode: code, trigger: trigger, timestamp: 30 * ms).effect, .endHold(fireTapAction: false))
    }

    func testCapsLockMappingKeepsOtherEntriesAndRestoresOriginal() {
        let src = kIOHIDKeyboardModifierMappingSrcKey, dst = kIOHIDKeyboardModifierMappingDstKey
        let other: [String: Int64] = [src: 0x7_0000_00E0, dst: 0x7_0000_00E3]
        let userCaps: [String: Int64] = [src: CapsLockKeyMapping.capsLockUsage, dst: 0x7_0000_0029]
        let applied = CapsLockKeyMapping.applyingRemap(to: [other, userCaps])
        XCTAssertEqual(CapsLockKeyMapping.capsLockDestination(in: applied), CapsLockKeyMapping.f18Usage)
        XCTAssertTrue(applied.contains(other))
        let restored = CapsLockKeyMapping.removingRemap(from: applied, originalDestination: 0x7_0000_0029)
        XCTAssertEqual(Set(restored.map { $0[dst] ?? 0 }), [0x7_0000_00E3, 0x7_0000_0029])
        XCTAssertEqual(CapsLockKeyMapping.removingRemap(from: CapsLockKeyMapping.applyingRemap(to: []), originalDestination: nil), [])
    }
}

final class MouseButtonAndKeymapTests: XCTestCase {
    func testNoneLeavesTheClickAlone() {
        XCTAssertNil(MouseControlManager.resolvedAction(plain: .none, modified: .none, modifierHeld: false))
        XCTAssertNil(MouseControlManager.resolvedAction(plain: .none, modified: .copy, modifierHeld: false))
        XCTAssertEqual(MouseControlManager.resolvedAction(plain: .none, modified: .copy, modifierHeld: true), .copy)
        XCTAssertEqual(MouseControlManager.resolvedAction(plain: .back, modified: .none, modifierHeld: true), .back)
    }

    func testResolvesBracketThroughOptionOnGermanStyleLayout() {
        let resolved = MouseShortcutKeymap.resolve(character: "[") { keyCode, state in
            if keyCode == 23 { return state == UInt32(optionKey >> 8) ? "[" : "5" }
            return nil
        }
        XCTAssertEqual(resolved?.keyCode, 23)
        XCTAssertEqual(resolved?.extraFlags, .maskAlternate)
    }

    func testPrefersUnmodifiedKeyAndMatchesLettersCaseInsensitively() {
        let resolved = MouseShortcutKeymap.resolve(character: "C") { keyCode, state in
            keyCode == 8 && state == 0 ? "c" : nil
        }
        XCTAssertEqual(resolved?.keyCode, 8)
        XCTAssertEqual(resolved?.extraFlags, [])
    }

    func testEventClockConvertsTicksButKeepsNanoseconds() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks: UInt64 = 1_000_000
        let ns = ticks * UInt64(info.numer) / UInt64(info.denom)
        XCTAssertEqual(InputEventClock.normalize(ticks, ticksNow: ticks + 10, nanosecondsNow: ns + 10), info.numer == info.denom ? ticks : ns)
        XCTAssertEqual(InputEventClock.normalize(ns, ticksNow: ticks, nanosecondsNow: ns + 10), ns)
    }

    func testFocusHitTestSkipsWhenAlreadyKeyAndBlocksNonNormalLayers() {
        let list: [[String: Any]] = [
            [kCGWindowNumber as String: 5, kCGWindowOwnerPID as String: 10, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 100, height: 100).dictionaryRepresentation],
            [kCGWindowNumber as String: 6, kCGWindowOwnerPID as String: 20, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 400, height: 400).dictionaryRepresentation],
        ]
        let overFront = FocusFollowsMouseManager.hitTest(list, point: CGPoint(x: 50, y: 50), frontmostPID: 10)
        XCTAssertEqual(overFront?.target.windowID, 5)
        XCTAssertEqual(overFront?.frontmostTopWindowID, 5)
        let overOther = FocusFollowsMouseManager.hitTest(list, point: CGPoint(x: 300, y: 300), frontmostPID: 10)
        XCTAssertEqual(overOther?.target.ownerPID, 20)

        let dock: [[String: Any]] = [
            [kCGWindowNumber as String: 1, kCGWindowOwnerPID as String: 30, kCGWindowLayer as String: 20,
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 400, height: 400).dictionaryRepresentation],
        ] + list
        XCTAssertNil(FocusFollowsMouseManager.hitTest(dock, point: CGPoint(x: 50, y: 50), frontmostPID: 10))
    }
}