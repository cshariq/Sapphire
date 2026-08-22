//
//  BiquadMath.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

enum BiquadMath {
    static let graphicEQQ: Double = 1.4

    static func peakingEQCoefficients(
        frequency: Double,
        gainDB: Float,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cosW
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cosW
        let a2 = 1.0 - alpha / A

        return [
            b0 / a0,
            b1 / a0,
            b2 / a0,
            a1 / a0,
            a2 / a0
        ]
    }

    static func lowShelfCoefficients(
        frequency: Double,
        gainDB: Float,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)
        let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha

        let b0 = A * ((A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha)
        let b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW)
        let b2 = A * ((A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha)
        let a0 = (A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha
        let a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW)
        let a2 = (A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    static func highShelfCoefficients(
        frequency: Double,
        gainDB: Float,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)
        let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha

        let b0 = A * ((A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha)
        let b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW)
        let b2 = A * ((A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha)
        let a0 = (A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha
        let a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW)
        let a2 = (A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    static func highPassCoefficients(
        frequency: Double,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        let b0 =  (1.0 + cosW) / 2.0
        let b1 = -(1.0 + cosW)
        let b2 =  (1.0 + cosW) / 2.0
        let a0 =  1.0 + alpha
        let a1 = -2.0 * cosW
        let a2 =  1.0 - alpha

        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    static func preWarpFrequency(
        _ freq: Double,
        from sourceRate: Double,
        to targetRate: Double
    ) -> Double {
        let fAnalog = (sourceRate / .pi) * tan(.pi * freq / sourceRate)
        return (targetRate / .pi) * atan(.pi * fAnalog / targetRate)
    }

    static func coefficientsForAutoEQFilters(
        _ filters: [AutoEQFilter],
        sampleRate: Double,
        profileOptimizedRate: Double = 48000
    ) -> [Double] {
        var allCoeffs: [Double] = []
        allCoeffs.reserveCapacity(filters.count * 5)

        let needsPreWarp = abs(profileOptimizedRate - sampleRate) > 1.0

        for filter in filters {
            var frequency = filter.frequency

            if needsPreWarp {
                frequency = preWarpFrequency(frequency, from: profileOptimizedRate, to: sampleRate)
            }

            if frequency <= 0 || frequency >= sampleRate / 2.0 {
                allCoeffs.append(contentsOf: [1.0, 0.0, 0.0, 0.0, 0.0])
                continue
            }

            let coeffs: [Double]
            switch filter.type {
            case .peaking:
                coeffs = peakingEQCoefficients(
                    frequency: frequency, gainDB: filter.gainDB,
                    q: filter.q, sampleRate: sampleRate)
            case .lowShelf:
                coeffs = lowShelfCoefficients(
                    frequency: frequency, gainDB: filter.gainDB,
                    q: filter.q, sampleRate: sampleRate)
            case .highShelf:
                coeffs = highShelfCoefficients(
                    frequency: frequency, gainDB: filter.gainDB,
                    q: filter.q, sampleRate: sampleRate)
            }
            allCoeffs.append(contentsOf: coeffs)
        }

        return allCoeffs
    }

    static func coefficientsForAllBands(
        gains: [Float],
        sampleRate: Double
    ) -> [Double] {
        guard gains.count == EQSettings.bandCount else {
            return (0..<EQSettings.bandCount).flatMap { _ in [1.0, 0.0, 0.0, 0.0, 0.0] }
        }

        var allCoeffs: [Double] = []
        allCoeffs.reserveCapacity(50)

        for (index, frequency) in EQSettings.frequencies.enumerated() {
            if frequency >= sampleRate / 2.0 {
                allCoeffs.append(contentsOf: [1.0, 0.0, 0.0, 0.0, 0.0])
                continue
            }
            let bandCoeffs = peakingEQCoefficients(
                frequency: frequency,
                gainDB: gains[index],
                q: graphicEQQ,
                sampleRate: sampleRate
            )
            allCoeffs.append(contentsOf: bandCoeffs)
        }

        return allCoeffs
    }
}