//
//  StatsMath.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import Foundation

struct CPUTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32

    init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    init(signedUser user: Int32, system: Int32, idle: Int32, nice: Int32) {
        self.init(
            user: UInt32(bitPattern: user),
            system: UInt32(bitPattern: system),
            idle: UInt32(bitPattern: idle),
            nice: UInt32(bitPattern: nice)
        )
    }
}

struct CPULoadFractions: Equatable {
    var user: Double
    var system: Double
    var nice: Double
    var idle: Double

    var busy: Double { user + system + nice }
}

enum CPUTickMath {
    static func delta(_ current: UInt32, _ previous: UInt32) -> UInt64 {
        UInt64(current &- previous)
    }

    static func load(from previous: CPUTicks, to current: CPUTicks) -> CPULoadFractions? {
        let user = Double(delta(current.user, previous.user))
        let system = Double(delta(current.system, previous.system))
        let idle = Double(delta(current.idle, previous.idle))
        let nice = Double(delta(current.nice, previous.nice))
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return CPULoadFractions(user: user / total, system: system / total, nice: nice / total, idle: idle / total)
    }
}

enum MemoryUsageMath {
    struct Breakdown: Equatable {
        var app: Double
        var wired: Double
        var compressed: Double
        var cache: Double

        var used: Double { app + wired + compressed }
    }

    static func breakdown(
        internalPages: UInt64,
        purgeablePages: UInt64,
        externalPages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        pageSize: UInt64
    ) -> Breakdown {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return Breakdown(
            app: Double(appPages) * Double(pageSize),
            wired: Double(wiredPages) * Double(pageSize),
            compressed: Double(compressedPages) * Double(pageSize),
            cache: Double(purgeablePages + externalPages) * Double(pageSize)
        )
    }

    static func usageFraction(used: Double, total: Double) -> Double {
        guard total > 0, used.isFinite else { return 0 }
        return min(1, max(0, used / total))
    }
}

struct SustainedThresholdGate {
    let duration: TimeInterval
    let cooldown: TimeInterval
    let minimumSamples: Int
    let maximumGap: TimeInterval

    private(set) var windowStart: TimeInterval?
    private(set) var sampleCount = 0
    private var valueSum = 0.0
    private var lastSampleTime: TimeInterval?
    private var lastFired: TimeInterval?

    init(duration: TimeInterval, cooldown: TimeInterval, minimumSamples: Int = 3, maximumGap: TimeInterval = 15) {
        self.duration = duration
        self.cooldown = cooldown
        self.minimumSamples = minimumSamples
        self.maximumGap = maximumGap
    }

    mutating func record(_ value: Double, threshold: Double, at uptime: TimeInterval) -> Double? {
        if let lastSampleTime, uptime <= lastSampleTime { return nil }
        let gap = lastSampleTime.map { uptime - $0 } ?? 0
        lastSampleTime = uptime

        guard value.isFinite, value >= threshold else {
            resetWindow()
            return nil
        }
        if windowStart == nil || gap > maximumGap {
            resetWindow()
            windowStart = uptime
        }
        sampleCount += 1
        valueSum += value

        guard let start = windowStart,
              uptime - start >= duration,
              sampleCount >= minimumSamples else { return nil }
        if let lastFired, uptime - lastFired < cooldown { return nil }

        let average = valueSum / Double(sampleCount)
        lastFired = uptime
        resetWindow()
        return average
    }

    mutating func resetWindow() {
        windowStart = nil
        sampleCount = 0
        valueSum = 0
    }
}

struct LowBatteryLatch {
    static let rearmMargin = 5
    private(set) var hasFired = false

    mutating func update(level: Int, onBattery: Bool, threshold: Int) -> Bool {
        guard onBattery else {
            hasFired = false
            return false
        }
        if level > threshold + Self.rearmMargin { hasFired = false }
        guard level <= threshold, !hasFired else { return false }
        hasFired = true
        return true
    }
}

struct LowDiskLatch {
    private(set) var hasFired = false

    static func rearmMargin(thresholdGB: Double) -> Double {
        max(2, thresholdGB * 0.1)
    }

    mutating func update(freeGB: Double, thresholdGB: Double) -> Bool {
        guard freeGB.isFinite else { return false }
        if freeGB > thresholdGB + Self.rearmMargin(thresholdGB: thresholdGB) { hasFired = false }
        guard freeGB < thresholdGB, !hasFired else { return false }
        hasFired = true
        return true
    }
}

enum NetworkRateMath {
    struct Sample: Equatable {
        var received: UInt64
        var sent: UInt64
        var uptime: TimeInterval
    }

    static func rates(from previous: Sample?, to current: Sample, maximumGap: TimeInterval) -> (down: Double, up: Double)? {
        guard let previous else { return nil }
        let elapsed = current.uptime - previous.uptime
        guard elapsed > 0, elapsed <= maximumGap,
              current.received >= previous.received,
              current.sent >= previous.sent else { return nil }
        return (
            Double(current.received - previous.received) / elapsed,
            Double(current.sent - previous.sent) / elapsed
        )
    }
}