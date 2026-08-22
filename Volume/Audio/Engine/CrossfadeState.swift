//
//  CrossfadeState.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

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