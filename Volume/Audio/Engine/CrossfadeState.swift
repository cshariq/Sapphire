//
//  CrossfadeState.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

final class CrossfadeCompletionSignal: @unchecked Sendable {
    private struct State {
        var isSignaled = false
        var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func reset() {
        let continuations = state.withLock { state in
            state.isSignaled = false
            let continuations = Array(state.waiters.values)
            state.waiters.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume(returning: false) }
    }

    func signal() {
        let continuations = state.withLock { state in
            guard !state.isSignaled else { return [CheckedContinuation<Bool, Never>]() }
            state.isSignaled = true
            let continuations = Array(state.waiters.values)
            state.waiters.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume(returning: true) }
    }

    func wait() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediateResult = state.withLock { state -> Bool? in
                    if state.isSignaled { return true }
                    if Task.isCancelled { return false }
                    state.waiters[id] = continuation
                    return nil
                }
                if let immediateResult {
                    continuation.resume(returning: immediateResult)
                }
            }
        } onCancel: {
            let continuation = state.withLock { $0.waiters.removeValue(forKey: id) }
            continuation?.resume(returning: false)
        }
    }
}

enum CrossfadePhase: Int, Equatable {
    case idle = 0
    case warmingUp = 1
    case crossfading = 2
}

struct CrossfadeState: @unchecked Sendable {
    nonisolated(unsafe) var progress: Float = 0

    nonisolated(unsafe) private var _phaseRawValue: Int = 0

    var phase: CrossfadePhase {
        get { CrossfadePhase(rawValue: _phaseRawValue) ?? .idle }
        set { _phaseRawValue = newValue.rawValue }
    }

    var isActive: Bool {
        _phaseRawValue != CrossfadePhase.idle.rawValue
    }

    nonisolated(unsafe) var secondarySampleCount: Int64 = 0

    nonisolated(unsafe) var totalSamples: Int64 = 0

    nonisolated(unsafe) var secondarySamplesProcessed: Int = 0

    static let minimumWarmupSamples: Int = 2048

    init() {}

    // MARK: - Phase Transitions (called from main thread)

    mutating func beginWarmup() {
        progress = 0
        secondarySampleCount = 0
        secondarySamplesProcessed = 0
        totalSamples = 0
        OSMemoryBarrier()
        phase = .warmingUp
    }

    mutating func beginCrossfading() {
        secondarySampleCount = 0
        progress = 0
        OSMemoryBarrier()
        phase = .crossfading
    }

    mutating func complete() {
        progress = 0
        secondarySampleCount = 0
        secondarySamplesProcessed = 0
        totalSamples = 0
        OSMemoryBarrier()
        phase = .idle
    }

    // MARK: - Audio Thread Access

    @inline(__always)
    mutating func updateProgress(samples: Int) -> Float {
        secondarySamplesProcessed += samples
        if phase == .crossfading {
            secondarySampleCount += Int64(samples)
            progress = min(1.0, Float(secondarySampleCount) / Float(max(1, totalSamples)))
        }
        return progress
    }

    var isWarmupComplete: Bool {
        secondarySamplesProcessed >= Self.minimumWarmupSamples
    }

    var isCrossfadeComplete: Bool {
        progress >= 1.0
    }

    @inline(__always)
    var primaryMultiplier: Float {
        switch phase {
        case .idle:
            return progress >= 1.0 ? 0.0 : 1.0
        case .warmingUp:
            return 1.0
        case .crossfading:
            return cos(progress * .pi / 2.0)
        }
    }

    @inline(__always)
    var secondaryMultiplier: Float {
        switch phase {
        case .idle:
            return 1.0
        case .warmingUp:
            return 0.0
        case .crossfading:
            return sin(progress * .pi / 2.0)
        }
    }
}