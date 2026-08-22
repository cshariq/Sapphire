//
//  KWeightingFilter.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

final class KWeightingFilter: @unchecked Sendable {

    // MARK: - Coefficient storage (Double precision for accuracy)

    private var s1_b0: Float = 1
    private var s1_b1: Float = 0
    private var s1_b2: Float = 0
    private var s1_a1: Float = 0
    private var s1_a2: Float = 0

    private var s2_b0: Float = 1
    private var s2_b1: Float = 0
    private var s2_b2: Float = 0
    private var s2_a1: Float = 0
    private var s2_a2: Float = 0

    // MARK: - State (transposed direct-form II delay elements)

    private var s1_z1: Float = 0
    private var s1_z2: Float = 0

    private var s2_z1: Float = 0
    private var s2_z2: Float = 0

    // MARK: - Initialisation

    init(sampleRate: Float) {
        computeCoefficients(sampleRate: Double(sampleRate))
    }

    // MARK: - Public API

    @inline(__always)
    func processSample(_ sample: Float) -> Float {
        let y1 = s1_b0 * sample + s1_z1
        let nextS1Z1 = s1_b1 * sample - s1_a1 * y1 + s1_z2
        let nextS1Z2 = s1_b2 * sample - s1_a2 * y1
        s1_z1 = nextS1Z1
        s1_z2 = nextS1Z2

        let y2 = s2_b0 * y1 + s2_z1
        let nextS2Z1 = s2_b1 * y1 - s2_a1 * y2 + s2_z2
        let nextS2Z2 = s2_b2 * y1 - s2_a2 * y2
        s2_z1 = nextS2Z1
        s2_z2 = nextS2Z2

        return y2
    }

    func reset() {
        s1_z1 = 0; s1_z2 = 0
        s2_z1 = 0; s2_z2 = 0
    }

    // MARK: - Private helpers

    private func computeCoefficients(sampleRate: Double) {
        let shelfCoeffs = BiquadMath.highShelfCoefficients(
            frequency: 1500.0,
            gainDB: 4.0,
            q: 1.0 / sqrt(2.0),
            sampleRate: sampleRate
        )
        s1_b0 = Float(shelfCoeffs[0])
        s1_b1 = Float(shelfCoeffs[1])
        s1_b2 = Float(shelfCoeffs[2])
        s1_a1 = Float(shelfCoeffs[3])
        s1_a2 = Float(shelfCoeffs[4])

        let hpCoeffs = BiquadMath.highPassCoefficients(
            frequency: 38.0,
            q: 1.0 / sqrt(2.0),
            sampleRate: sampleRate
        )
        s2_b0 = Float(hpCoeffs[0])
        s2_b1 = Float(hpCoeffs[1])
        s2_b2 = Float(hpCoeffs[2])
        s2_a1 = Float(hpCoeffs[3])
        s2_a2 = Float(hpCoeffs[4])
    }
}