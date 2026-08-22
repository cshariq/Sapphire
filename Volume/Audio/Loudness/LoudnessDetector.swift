//
//  LoudnessDetector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

final class LoudnessDetector: @unchecked Sendable {

    // MARK: - Private state

    private var settings: LoudnessEqualizerSettings
    private var sampleRate: Float

    private var ringBuffer: [Float]
    private var writeIndex: Int = 0
    private var hopCounter: Int = 0
    private var runningSquareSum: Float = 0

    private var windowSamples: Int
    private var inverseWindowSamples: Float
    private var hopSamples: Int

    private var attackCoeff: Float
    private var releaseCoeff: Float

    private var smoothedLevel: Float = -120.0

    // MARK: - Init

    init(settings: LoudnessEqualizerSettings, sampleRate: Float) {
        self.settings = settings
        self.sampleRate = sampleRate

        let ws = Int(settings.analysisWindowMs / 1000 * sampleRate)
        windowSamples = max(ws, 1)
        inverseWindowSamples = 1.0 / Float(windowSamples)

        let hs = Int(settings.analysisHopMs / 1000 * sampleRate)
        hopSamples = max(hs, 1)

        ringBuffer = [Float](repeating: 0, count: windowSamples)

        attackCoeff = LoudnessEqualizerMath.timeConstantCoefficient(
            timeMs: settings.detectorAttackMs,
            stepMs: settings.analysisHopMs
        )
        releaseCoeff = LoudnessEqualizerMath.timeConstantCoefficient(
            timeMs: settings.detectorReleaseMs,
            stepMs: settings.analysisHopMs
        )
    }

    // MARK: - Real-time ingest

    func ingest(weightedSample: Float) -> Float? {
        runningSquareSum -= ringBuffer[writeIndex]
        ringBuffer[writeIndex] = weightedSample * weightedSample
        runningSquareSum += ringBuffer[writeIndex]

        writeIndex += 1
        if writeIndex == windowSamples {
            writeIndex = 0
        }

        hopCounter += 1
        if hopCounter >= hopSamples {
            hopCounter = 0
            let meanSquare = runningSquareSum * inverseWindowSamples
            let levelDb = LoudnessEqualizerMath.meanSquareToDb(meanSquare)
            return updateEnvelope(with: levelDb)
        }
        return nil
    }

    // MARK: - Envelope smoothing

    func updateEnvelope(with measuredLevelDb: Float) -> Float {
        let coeff: Float
        if measuredLevelDb > smoothedLevel {
            coeff = attackCoeff
        } else {
            coeff = releaseCoeff
        }
        smoothedLevel += coeff * (measuredLevelDb - smoothedLevel)
        return smoothedLevel
    }

    // MARK: - Reset

    func reset() {
        for i in 0..<ringBuffer.count {
            ringBuffer[i] = 0
        }
        writeIndex = 0
        hopCounter = 0
        runningSquareSum = 0
        smoothedLevel = -120.0
    }
}