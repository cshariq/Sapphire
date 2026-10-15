//
//  MixerSupport.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import Foundation
import Accelerate

// MARK: - Gain ramp

enum GainRamp {
    static func step(from: Float, to: Float, frames: Int) -> Float {
        guard frames > 0 else { return 0 }
        return (to - from) / Float(frames)
    }

    static func apply(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frames: Int,
        channels: Int,
        from: Float,
        to: Float
    ) {
        guard frames > 0, channels > 0 else { return }
        let total = vDSP_Length(frames * channels)
        if from == to {
            if to == 0 {
                vDSP_vclr(output, 1, total)
            } else if to == 1 {
                if UnsafeRawPointer(input) != UnsafeRawPointer(output) {
                    memmove(output, input, frames * channels * MemoryLayout<Float>.size)
                }
            } else {
                var gain = to
                vDSP_vsmul(input, 1, &gain, output, 1, total)
            }
            return
        }
        var increment = step(from: from, to: to, frames: frames)
        for channel in 0..<channels {
            var start = from
            vDSP_vrampmul(
                input.advanced(by: channel), vDSP_Stride(channels),
                &start, &increment,
                output.advanced(by: channel), vDSP_Stride(channels),
                vDSP_Length(frames)
            )
        }
    }
}

// MARK: - Lookahead peak limiter

final class LookaheadLimiter {
    static let maxChannels = 8

    let lookaheadFrames: Int
    let ceiling: Float
    private let releaseCoefficient: Float

    private let delayLine: UnsafeMutablePointer<Float>
    private var delayChannels = 0
    private var delayIndex = 0

    private let windowCapacity: Int
    private let windowValues: UnsafeMutablePointer<Float>
    private let windowSerials: UnsafeMutablePointer<Int>
    private var windowHead = 0
    private var windowCount = 0
    private var serial = 0

    private let boxcar: UnsafeMutablePointer<Float>
    private var boxcarIndex = 0
    private var boxcarSum: Double

    private let swapScratch: UnsafeMutablePointer<Float>

    private(set) var envelope: Float = 1
    private var framesSinceReduction = Int.max / 2

    init(sampleRate: Double, lookaheadSeconds: Double = 0.003, releaseSeconds: Double = 0.12, ceiling: Float = 0.97) {
        let rate = max(sampleRate, 8000)
        lookaheadFrames = max(16, Int(rate * lookaheadSeconds))
        self.ceiling = ceiling
        releaseCoefficient = 1 - expf(-1 / Float(rate * releaseSeconds))
        delayLine = .allocate(capacity: lookaheadFrames * Self.maxChannels)
        delayLine.initialize(repeating: 0, count: lookaheadFrames * Self.maxChannels)
        windowCapacity = lookaheadFrames + 2
        windowValues = .allocate(capacity: windowCapacity)
        windowValues.initialize(repeating: 1, count: windowCapacity)
        windowSerials = .allocate(capacity: windowCapacity)
        windowSerials.initialize(repeating: 0, count: windowCapacity)
        boxcar = .allocate(capacity: lookaheadFrames)
        boxcar.initialize(repeating: 1, count: lookaheadFrames)
        boxcarSum = Double(lookaheadFrames)
        swapScratch = .allocate(capacity: lookaheadFrames * Self.maxChannels)
        swapScratch.initialize(repeating: 0, count: lookaheadFrames * Self.maxChannels)
    }

    deinit {
        delayLine.deallocate()
        windowValues.deallocate()
        windowSerials.deallocate()
        boxcar.deallocate()
        swapScratch.deallocate()
    }

    var latencyFrames: Int { lookaheadFrames }

    @_optimize(speed)
    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard frames > 0, channels > 0, channels <= Self.maxChannels else { return }
        if channels != delayChannels {
            delayLine.update(repeating: 0, count: lookaheadFrames * Self.maxChannels)
            delayChannels = channels
            delayIndex = 0
        }

        if envelope == 1, framesSinceReduction > 2 * lookaheadFrames {
            var peak: Float = 0
            vDSP_maxmgv(samples, 1, &peak, vDSP_Length(frames * channels))
            if peak <= ceiling {
                delayOnly(samples, frames: frames, channels: channels)
                framesSinceReduction = min(framesSinceReduction + frames, Int.max / 2)
                return
            }
        }

        for frame in 0..<frames {
            let base = frame * channels
            var peak: Float = 0
            for channel in 0..<channels { peak = max(peak, abs(samples[base + channel])) }
            let required: Float = peak > ceiling ? ceiling / peak : 1
            let windowMin = pushRequiredGain(required)
            boxcarSum += Double(windowMin - boxcar[boxcarIndex])
            boxcar[boxcarIndex] = windowMin
            boxcarIndex += 1
            if boxcarIndex == lookaheadFrames { boxcarIndex = 0 }
            let smoothed = min(Float(boxcarSum / Double(lookaheadFrames)), 1)

            if smoothed <= envelope {
                envelope = smoothed
            } else {
                envelope += releaseCoefficient * (smoothed - envelope)
                if envelope > 0.99999, smoothed >= 1 { envelope = 1 }
            }
            if windowMin < 1 { framesSinceReduction = 0 } else { framesSinceReduction += 1 }

            let slot = delayIndex * channels
            for channel in 0..<channels {
                let delayed = delayLine[slot + channel]
                delayLine[slot + channel] = samples[base + channel]
                samples[base + channel] = Self.softKnee(delayed * envelope, ceiling: ceiling)
            }
            delayIndex += 1
            if delayIndex == lookaheadFrames { delayIndex = 0 }
        }
    }

    @inline(__always)
    static func softKnee(_ sample: Float, ceiling: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > ceiling else { return sample }
        let headroom = 1 - ceiling
        let shaped = ceiling + headroom * tanhf((magnitude - ceiling) / headroom)
        return sample < 0 ? -shaped : shaped
    }

    @inline(__always)
    private func pushRequiredGain(_ value: Float) -> Float {
        while windowCount > 0 {
            let back = (windowHead + windowCount - 1) % windowCapacity
            if windowValues[back] >= value { windowCount -= 1 } else { break }
        }
        let insert = (windowHead + windowCount) % windowCapacity
        windowValues[insert] = value
        windowSerials[insert] = serial
        windowCount += 1
        let oldestAllowed = serial - lookaheadFrames
        while windowCount > 0, windowSerials[windowHead] < oldestAllowed {
            windowHead = (windowHead + 1) % windowCapacity
            windowCount -= 1
        }
        serial += 1
        return windowValues[windowHead]
    }

    @inline(__always)
    private func delayOnly(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        let floatBytes = MemoryLayout<Float>.size
        if frames >= lookaheadFrames {
            let tail = lookaheadFrames - delayIndex
            memcpy(swapScratch, delayLine + delayIndex * channels, tail * channels * floatBytes)
            if delayIndex > 0 {
                memcpy(swapScratch + tail * channels, delayLine, delayIndex * channels * floatBytes)
            }
            memcpy(delayLine, samples + (frames - lookaheadFrames) * channels, lookaheadFrames * channels * floatBytes)
            delayIndex = 0
            memmove(samples + lookaheadFrames * channels, samples, (frames - lookaheadFrames) * channels * floatBytes)
            memcpy(samples, swapScratch, lookaheadFrames * channels * floatBytes)
        } else {
            var frame = 0
            while frame < frames {
                let run = min(frames - frame, lookaheadFrames - delayIndex)
                let count = run * channels
                let block = samples + frame * channels
                let slot = delayLine + delayIndex * channels
                memcpy(swapScratch, slot, count * floatBytes)
                memcpy(slot, block, count * floatBytes)
                memcpy(block, swapScratch, count * floatBytes)
                delayIndex += run
                if delayIndex == lookaheadFrames { delayIndex = 0 }
                frame += run
            }
        }
        serial += frames
        windowHead = 0
        windowCount = 0
        boxcarSum = Double(lookaheadFrames)
    }
}

// MARK: - Routing

enum MixerRouting {
    static func targetUIDs(route: String?, availableUIDs: Set<String>, globalOutputUIDs: [String]) -> [String] {
        if let route, availableUIDs.contains(route) { return [route] }
        return globalOutputUIDs
    }

    static func globalOutputUIDs(selectedUIDs: [String], availableUIDs: Set<String>, defaultUID: String?) -> [String] {
        let connected = selectedUIDs.filter { availableUIDs.contains($0) }
        if !connected.isEmpty { return connected }
        if let defaultUID { return [defaultUID] }
        return []
    }

    static func routeRequiresTap(route: String?, availableUIDs: Set<String>, globalOutputUIDs: [String]) -> Bool {
        guard let route, availableUIDs.contains(route) else { return false }
        return globalOutputUIDs != [route]
    }
}

// MARK: - Build mailbox

struct LatestOnlyMailbox<Value: Equatable> {
    private(set) var pending: Value?
    private(set) var lastApplied: Value?
    private(set) var isDraining = false
    private var forceNext = false

    mutating func post(_ value: Value, force: Bool = false) -> Bool {
        pending = value
        if force { forceNext = true }
        guard !isDraining else { return false }
        isDraining = true
        return true
    }

    mutating func take() -> Value? {
        guard let value = pending else {
            isDraining = false
            return nil
        }
        pending = nil
        if value == lastApplied && !forceNext {
            isDraining = false
            return nil
        }
        forceNext = false
        return value
    }

    mutating func forceRebuild(fallback: Value?) -> Bool {
        guard let value = pending ?? fallback else { return false }
        return post(value, force: true)
    }

    var hasNewer: Bool { pending != nil }

    mutating func markApplied(_ value: Value) { lastApplied = value }

    mutating func invalidateApplied() { lastApplied = nil }
}

// MARK: - Tap watchdog

struct TapWatchdogState: Equatable {
    var lastRenderCount: UInt64 = 0
    var stalledChecks = 0
    var healthyChecks = 0
    var rebuilds = 0

    enum Verdict: Equatable { case healthy, waiting, rebuild, failOpen }

    static let stallChecksBeforeAction = 2
    static let healthyChecksToForgive = 30

    mutating func observe(renderCount: UInt64) -> Verdict {
        if renderCount != lastRenderCount {
            lastRenderCount = renderCount
            stalledChecks = 0
            healthyChecks += 1
            if healthyChecks >= Self.healthyChecksToForgive { rebuilds = 0 }
            return .healthy
        }
        healthyChecks = 0
        stalledChecks += 1
        guard stalledChecks >= Self.stallChecksBeforeAction else { return .waiting }
        stalledChecks = 0
        if rebuilds == 0 {
            rebuilds += 1
            return .rebuild
        }
        return .failOpen
    }
}

// MARK: - App ordering, pins, hidden apps

struct MixerAppOrdering: Codable, Equatable {
    var pinned: [String] = []
    var hidden: Set<String> = []

    func isPinned(_ bundleID: String) -> Bool { pinned.contains(bundleID) }
    func isHidden(_ bundleID: String) -> Bool { hidden.contains(bundleID) }

    func arrange(_ naturalOrder: [String]) -> [String] {
        let visible = naturalOrder.filter { !hidden.contains($0) }
        let present = Set(visible)
        let pinnedPresent = pinned.filter { present.contains($0) }
        let pinnedSet = Set(pinnedPresent)
        return pinnedPresent + visible.filter { !pinnedSet.contains($0) }
    }

    mutating func togglePin(_ bundleID: String) {
        if let index = pinned.firstIndex(of: bundleID) {
            pinned.remove(at: index)
        } else {
            pinned.append(bundleID)
        }
    }

    mutating func move(_ bundleID: String, offset: Int, visible: [String]) {
        guard offset != 0 else { return }
        if !pinned.contains(bundleID) { pinned.append(bundleID) }
        let visiblePinned = arrange(visible).filter { pinned.contains($0) }
        guard let position = visiblePinned.firstIndex(of: bundleID) else { return }
        let target = min(max(position + offset, 0), visiblePinned.count - 1)
        guard target != position else { return }
        let neighbor = visiblePinned[target]
        guard let from = pinned.firstIndex(of: bundleID), let to = pinned.firstIndex(of: neighbor) else { return }
        pinned.swapAt(from, to)
    }

    mutating func hide(_ bundleID: String) {
        hidden.insert(bundleID)
        pinned.removeAll { $0 == bundleID }
    }

    mutating func unhide(_ bundleID: String) { hidden.remove(bundleID) }

    mutating func unhideAll() { hidden.removeAll() }
}

// MARK: - Output switching

enum OutputCycle {
    static func next(currentUID: String?, chosenUIDs: [String], availableUIDs: Set<String>) -> String? {
        let candidates = chosenUIDs.filter { availableUIDs.contains($0) }
        guard !candidates.isEmpty else { return nil }
        guard let currentUID, let index = candidates.firstIndex(of: currentUID) else { return candidates[0] }
        let next = candidates[(index + 1) % candidates.count]
        return next == currentUID ? nil : next
    }
}

enum HeadphoneDisconnectPolicy {
    struct OutputState: Equatable {
        var uid: String
        var isHeadphones: Bool
        var isBuiltInSpeaker: Bool
    }

    enum Action: Equatable {
        case none
        case lower(speakerUID: String, level: Float)
        case restore(speakerUID: String)
    }

    static func decide(
        previous: OutputState?,
        current: OutputState,
        previousStillConnected: Bool,
        speakerVolume: Float?,
        targetLevel: Float,
        hasSavedVolume: Bool
    ) -> Action {
        guard let previous else { return .none }
        if previous.uid == current.uid {
            if previous.isHeadphones && current.isBuiltInSpeaker,
               let speakerVolume, speakerVolume > targetLevel {
                return .lower(speakerUID: current.uid, level: targetLevel)
            }
            return .none
        }
        if previous.isHeadphones, !previousStillConnected, current.isBuiltInSpeaker {
            guard let speakerVolume, speakerVolume > targetLevel else { return .none }
            return .lower(speakerUID: current.uid, level: targetLevel)
        }
        if previous.isBuiltInSpeaker, current.isHeadphones, hasSavedVolume {
            return .restore(speakerUID: previous.uid)
        }
        return .none
    }

    static func looksLikeHeadphones(name: String, transportIsBluetooth: Bool, dataSourceIsHeadphones: Bool) -> Bool {
        if dataSourceIsHeadphones { return true }
        let lowered = name.lowercased()
        let markers = ["headphone", "airpods", "buds", "earphone", "headset", "beats", "wh-", "wf-", "bose qc"]
        if markers.contains(where: lowered.contains) { return true }
        return transportIsBluetooth && !lowered.contains("speaker") && !lowered.contains("homepod")
    }
}

enum PreferredInputPolicy {
    static func deviceToSelect(preferredUID: String?, currentDefaultUID: String?, availableUIDs: Set<String>) -> String? {
        guard let preferredUID, availableUIDs.contains(preferredUID), preferredUID != currentDefaultUID else { return nil }
        return preferredUID
    }
}

// MARK: - Meter throttling

struct MeterAccumulator {
    let intervalFrames: Int
    private var sumOfSquares: Float = 0
    private var peak: Float = 0
    private var samples = 0
    private var frames = 0

    init(sampleRate: Double, updatesPerSecond: Double = 20) {
        intervalFrames = max(1, Int(max(sampleRate, 8000) / updatesPerSecond))
    }

    struct Reading: Equatable {
        var rms: Float
        var peak: Float
    }

    mutating func add(sumOfSquares: Float, peak: Float, sampleCount: Int, frameCount: Int) -> Reading? {
        guard sampleCount > 0 else { return nil }
        self.sumOfSquares += sumOfSquares
        self.peak = max(self.peak, peak)
        samples += sampleCount
        frames += frameCount
        guard frames >= intervalFrames else { return nil }
        let reading = Reading(rms: (self.sumOfSquares / Float(samples)).squareRoot(), peak: self.peak)
        self.sumOfSquares = 0
        self.peak = 0
        samples = 0
        frames = 0
        return reading
    }
}