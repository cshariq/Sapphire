//
//  GainSmoother.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

final class GainSmoother: @unchecked Sendable {
    private var settings: LoudnessEqualizerSettings
    private var attackCoeff: Float
    private var releaseCoeff: Float
    private(set) var currentGainDb: Float = 0

    init(settings: LoudnessEqualizerSettings, sampleRate: Float) {
        self.settings = settings
        let hopMs = settings.analysisHopMs
        self.attackCoeff  = LoudnessEqualizerMath.timeConstantCoefficient(timeMs: settings.gainAttackMs,  stepMs: hopMs)
        self.releaseCoeff = LoudnessEqualizerMath.timeConstantCoefficient(timeMs: settings.gainReleaseMs, stepMs: hopMs)
    }

    func reset(initialGainDb: Float = 0) {
        currentGainDb = initialGainDb
    }

    func process(targetGainDb: Float) -> Float {
        let coeff: Float = targetGainDb < currentGainDb ? attackCoeff : releaseCoeff
        currentGainDb += coeff * (targetGainDb - currentGainDb)
        return currentGainDb
    }
}