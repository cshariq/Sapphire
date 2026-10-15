//
//  StatsAndFanPolicyTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import Foundation
import Testing
@testable import Sapphire

struct CPUTickMathTests {
    @Test func deltaWrapsInsteadOfTrapping() {
        #expect(CPUTickMath.delta(5, UInt32.max - 4) == 10)
        #expect(CPUTickMath.delta(100, 40) == 60)
    }

    @Test func loadAcrossCounterWrap() throws {
        let previous = CPUTicks(user: UInt32.max - 9, system: 100, idle: UInt32.max - 19, nice: 0)
        let current = CPUTicks(user: UInt32(10), system: 120, idle: 20, nice: 0)
        let load = try #require(CPUTickMath.load(from: previous, to: current))
        #expect(abs(load.user - 0.25) < 1e-9)
        #expect(abs(load.system - 0.25) < 1e-9)
        #expect(abs(load.idle - 0.5) < 1e-9)
        #expect(abs(load.busy - 0.5) < 1e-9)
    }

    @Test func signedKernelCountersAreReinterpreted() {
        let ticks = CPUTicks(signedUser: -1, system: 0, idle: 0, nice: 0)
        #expect(ticks.user == UInt32.max)
    }

    @Test func noElapsedTicksIsNil() {
        let sample = CPUTicks(user: UInt32(5), system: 5, idle: 5, nice: 5)
        #expect(CPUTickMath.load(from: sample, to: sample) == nil)
    }
}

struct MemoryUsageMathTests {
    @Test func usedIsAppPlusWiredPlusCompressed() {
        let breakdown = MemoryUsageMath.breakdown(
            internalPages: 1_000,
            purgeablePages: 200,
            externalPages: 500,
            wiredPages: 300,
            compressedPages: 100,
            pageSize: 16_384
        )
        #expect(breakdown.app == 800 * 16_384)
        #expect(breakdown.used == (800 + 300 + 100) * 16_384)
        #expect(breakdown.cache == 700 * 16_384)
    }

    @Test func purgeableLargerThanInternalDoesNotUnderflow() {
        let breakdown = MemoryUsageMath.breakdown(
            internalPages: 10, purgeablePages: 50, externalPages: 0,
            wiredPages: 1, compressedPages: 0, pageSize: 4_096
        )
        #expect(breakdown.app == 0)
        #expect(breakdown.used == 4_096)
    }

    @Test func usageFractionMatchesUsedAndIsClamped() {
        #expect(MemoryUsageMath.usageFraction(used: 8, total: 16) == 0.5)
        #expect(MemoryUsageMath.usageFraction(used: 20, total: 16) == 1)
        #expect(MemoryUsageMath.usageFraction(used: 8, total: 0) == 0)
    }

    @Test func ramUsageReportsSameFractionAsUsed() {
        let usage = RAM_Usage(
            total: 16, used: 12, free: 4, active: 0, inactive: 0, wired: 0, compressed: 0,
            app: 0, cache: 0, swap: Swap(total: 0, used: 0, free: 0),
            pressure: Pressure(level: 0, value: .normal)
        )
        #expect(usage.usage == 0.75)
    }
}

struct SustainedThresholdGateTests {
    @Test func firesOnlyAfterSustainedDistinctSamples() {
        var gate = SustainedThresholdGate(duration: 45, cooldown: 600, minimumSamples: 3, maximumGap: 15)
        let r1 = gate.record(95, threshold: 90, at: 100)
        #expect(r1 == nil)
        let r2 = gate.record(95, threshold: 90, at: 110)
        #expect(r2 == nil)
        let r3 = gate.record(95, threshold: 90, at: 110)
        #expect(r3 == nil)
        let r4 = gate.record(95, threshold: 90, at: 120)
        #expect(r4 == nil)
        let r5 = gate.record(95, threshold: 90, at: 130)
        #expect(r5 == nil)
        let r6 = gate.record(95, threshold: 90, at: 140)
        #expect(r6 == nil)
        let r7 = gate.record(95, threshold: 90, at: 145)
        #expect(r7 == 95)
    }

    @Test func dipBelowThresholdRestartsWindow() {
        var gate = SustainedThresholdGate(duration: 30, cooldown: 600, minimumSamples: 2, maximumGap: 15)
        _ = gate.record(95, threshold: 90, at: 0)
        _ = gate.record(95, threshold: 90, at: 10)
        _ = gate.record(50, threshold: 90, at: 20)
        _ = gate.record(95, threshold: 90, at: 30)
        let r8 = gate.record(95, threshold: 90, at: 40)
        #expect(r8 == nil)
        let r9 = gate.record(95, threshold: 90, at: 50)
        #expect(r9 == nil)
        let r10 = gate.record(95, threshold: 90, at: 60)
        #expect(r10 != nil)
    }

    @Test func longGapRestartsWindow() {
        var gate = SustainedThresholdGate(duration: 30, cooldown: 600, minimumSamples: 2, maximumGap: 15)
        _ = gate.record(95, threshold: 90, at: 0)
        _ = gate.record(95, threshold: 90, at: 10)
        let r11 = gate.record(95, threshold: 90, at: 110)
        #expect(r11 == nil)
        let r12 = gate.record(95, threshold: 90, at: 120)
        #expect(r12 == nil)
    }

    @Test func cooldownSuppressesRepeatAlerts() {
        var gate = SustainedThresholdGate(duration: 10, cooldown: 100, minimumSamples: 2, maximumGap: 15)
        _ = gate.record(95, threshold: 90, at: 0)
        let r13 = gate.record(95, threshold: 90, at: 10)
        #expect(r13 != nil)
        _ = gate.record(95, threshold: 90, at: 20)
        let r14 = gate.record(95, threshold: 90, at: 30)
        #expect(r14 == nil)
        _ = gate.record(95, threshold: 90, at: 105)
        let r15 = gate.record(95, threshold: 90, at: 115)
        #expect(r15 != nil)
    }
}

struct LowBatteryLatchTests {
    @Test func firesOncePerDischarge() {
        var latch = LowBatteryLatch()
        let r16 = latch.update(level: 30, onBattery: true, threshold: 15)
        #expect(!r16)
        let r17 = latch.update(level: 15, onBattery: true, threshold: 15)
        #expect(r17)
        let r18 = latch.update(level: 14, onBattery: true, threshold: 15)
        #expect(!r18)
        let r19 = latch.update(level: 14, onBattery: false, threshold: 15)
        #expect(!r19)
        let r20 = latch.update(level: 13, onBattery: true, threshold: 15)
        #expect(r20)
    }
}

struct NetworkRateMathTests {
    @Test func ratesAndRebaselines() throws {
        let first = NetworkRateMath.Sample(received: 1_000, sent: 500, uptime: 10)
        #expect(NetworkRateMath.rates(from: nil, to: first, maximumGap: 3) == nil)

        let second = NetworkRateMath.Sample(received: 3_000, sent: 1_500, uptime: 12)
        let rates = try #require(NetworkRateMath.rates(from: first, to: second, maximumGap: 3))
        #expect(rates.down == 1_000)
        #expect(rates.up == 500)

        let afterGap = NetworkRateMath.Sample(received: 9_000, sent: 9_000, uptime: 30)
        #expect(NetworkRateMath.rates(from: second, to: afterGap, maximumGap: 3) == nil)

        let reset = NetworkRateMath.Sample(received: 10, sent: 10, uptime: 13)
        #expect(NetworkRateMath.rates(from: second, to: reset, maximumGap: 3) == nil)
    }
}

struct FanCurvePolicyTests {
    private let points = [
        FanCurvePoint(temperature: 40, rpm: 1_200),
        FanCurvePoint(temperature: 80, rpm: 5_200)
    ]

    @Test func interpolatesAndClamps() {
        #expect(FanCurvePolicy.interpolatedRPM(points: points, temperature: 30) == 1_200)
        #expect(FanCurvePolicy.interpolatedRPM(points: points, temperature: 60) == 3_200)
        #expect(FanCurvePolicy.interpolatedRPM(points: points, temperature: 90) == 5_200)
        #expect(FanCurvePolicy.interpolatedRPM(points: [points[0]], temperature: 60) == nil)
    }

    @Test func firstReadingAlwaysWrites() {
        var state = FanCurvePolicy.State()
        let r21 = FanCurvePolicy.nextTarget(state: &state, temperature: 60, points: points, minRPM: 1_200, maxRPM: 5_200)
        #expect(r21 == 3_200)
    }

    @Test func smallWobbleDoesNotWrite() {
        var state = FanCurvePolicy.State()
        _ = FanCurvePolicy.nextTarget(state: &state, temperature: 60, points: points, minRPM: 1_200, maxRPM: 5_200)
        for temperature in [60.5, 59.6, 60.8, 59.4, 60.2] {
            let r22 = FanCurvePolicy.nextTarget(state: &state, temperature: temperature, points: points, minRPM: 1_200, maxRPM: 5_200)
            #expect(r22 == nil)
        }
    }

    @Test func risingTemperatureRaisesSpeed() throws {
        var state = FanCurvePolicy.State()
        _ = FanCurvePolicy.nextTarget(state: &state, temperature: 60, points: points, minRPM: 1_200, maxRPM: 5_200)
        var written: Int?
        for _ in 0..<6 where written == nil {
            written = FanCurvePolicy.nextTarget(state: &state, temperature: 70, points: points, minRPM: 1_200, maxRPM: 5_200)
        }
        let rpm = try #require(written)
        #expect(rpm > 3_200)
    }

    @Test func coolingNeedsHysteresisBeforeSlowingDown() {
        var state = FanCurvePolicy.State()
        _ = FanCurvePolicy.nextTarget(state: &state, temperature: 70, points: points, minRPM: 1_200, maxRPM: 5_200)
        var smoothedState = state
        let r23 = FanCurvePolicy.nextTarget(state: &smoothedState, temperature: 69, points: points, minRPM: 1_200, maxRPM: 5_200)
        #expect(r23 == nil)
        var lowered: Int?
        for _ in 0..<10 where lowered == nil {
            lowered = FanCurvePolicy.nextTarget(state: &state, temperature: 55, points: points, minRPM: 1_200, maxRPM: 5_200)
        }
        #expect((lowered ?? 5_200) < 4_200)
    }

    @Test func targetsStayWithinFanLimits() {
        var state = FanCurvePolicy.State()
        let curve = [FanCurvePoint(temperature: 40, rpm: 0), FanCurvePoint(temperature: 80, rpm: 9_000)]
        let r24 = FanCurvePolicy.nextTarget(state: &state, temperature: 30, points: curve, minRPM: 1_200, maxRPM: 5_200)
        #expect(r24 == 1_200)
        var hot = FanCurvePolicy.State()
        let r25 = FanCurvePolicy.nextTarget(state: &hot, temperature: 95, points: curve, minRPM: 1_200, maxRPM: 5_200)
        #expect(r25 == 5_200)
    }
}