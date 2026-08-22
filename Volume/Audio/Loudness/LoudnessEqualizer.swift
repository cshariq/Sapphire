//
//  LoudnessEqualizer.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

final class LoudnessEqualizer: @unchecked Sendable {

    // MARK: - Private state (exclusively RT-thread owned after init)

    private let settings: LoudnessEqualizerSettings
    private let kFilter: KWeightingFilter
    private let detector: LoudnessDetector
    private let gainComputer: GainComputer
    private let gainSmoother: GainSmoother
    private var currentLinearGain: Float

    // MARK: - Init

    init(settings: LoudnessEqualizerSettings, sampleRate: Float) {
        self.settings = settings
        self.kFilter = KWeightingFilter(sampleRate: sampleRate)
        self.detector = LoudnessDetector(settings: settings, sampleRate: sampleRate)
        self.gainComputer = GainComputer(settings: settings)
        self.gainSmoother = GainSmoother(settings: settings, sampleRate: sampleRate)
        self.currentLinearGain = LoudnessEqualizerMath.dbToLinear(self.gainSmoother.currentGainDb)
    }

    // MARK: - Public API

    var isEnabled: Bool { settings.enabled }

    var currentSettings: LoudnessEqualizerSettings { settings }

    func process(
        input: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        let enabled = settings.enabled
        if !enabled {
            if input != UnsafePointer(output) {
                memcpy(output, input, frameCount * channelCount * MemoryLayout<Float>.size)
            }
            return
        }

        var linearGain = currentLinearGain

        if channelCount == 2 {
            for frame in 0..<frameCount {
                let base = frame * 2
                let mono = (input[base] + input[base + 1]) * 0.5
                let weighted = kFilter.processSample(mono)

                if let newLevel = detector.ingest(weightedSample: weighted) {
                    let desiredGain = gainComputer.desiredGainDb(forLevelDb: newLevel)
                    let smoothedGain = gainSmoother.process(targetGainDb: desiredGain)
                    linearGain = LoudnessEqualizerMath.dbToLinear(smoothedGain)
                    currentLinearGain = linearGain
                }

                output[base] = input[base] * linearGain
                output[base + 1] = input[base + 1] * linearGain
            }
            return
        }

        let inverseChannelCount = 1.0 / Float(channelCount)
        for f in 0..<frameCount {
            let base = f * channelCount

            var mono: Float = 0
            for ch in 0..<channelCount {
                mono += input[base + ch]
            }
            mono *= inverseChannelCount

            let weighted = kFilter.processSample(mono)

            if let newLevel = detector.ingest(weightedSample: weighted) {
                let desiredGain = gainComputer.desiredGainDb(forLevelDb: newLevel)
                let smoothedGain = gainSmoother.process(targetGainDb: desiredGain)
                linearGain = LoudnessEqualizerMath.dbToLinear(smoothedGain)
                currentLinearGain = linearGain
            }

            for ch in 0..<channelCount {
                output[base + ch] = input[base + ch] * linearGain
            }
        }
    }
}