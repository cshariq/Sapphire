//
//  ISO226Contours.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

enum ISO226Contours {

    // MARK: - ISO 226:2023 Table 1

    static let frequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
        2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500
    ]

    static let loudnessPerceptionExponents: [Double] = [
        0.635, 0.602, 0.569, 0.537, 0.509, 0.482, 0.456, 0.433, 0.412, 0.391,
        0.373, 0.357, 0.343, 0.330, 0.320, 0.311, 0.303, 0.300, 0.295, 0.292,
        0.290, 0.290, 0.289, 0.289, 0.289, 0.293, 0.303, 0.323, 0.354
    ]

    static let transferMagnitudesDB: [Double] = [
        -31.5, -27.2, -23.1, -19.3, -16.1, -13.1, -10.4, -8.2, -6.3, -4.6,
        -3.2, -2.1, -1.2, -0.5, 0.0, 0.4, 0.5, 0.0, -2.7, -4.2,
        -1.2, 1.4, 2.3, 1.0, -2.3, -7.2, -11.2, -10.9, -3.5
    ]

    static let hearingThresholdsDB: [Double] = [
        78.1, 68.7, 59.5, 51.1, 44.0, 37.5, 31.5, 26.5, 22.1, 17.9,
        14.4, 11.4, 8.6, 6.2, 4.4, 3.0, 2.2, 2.4, 3.5, 1.7,
        -1.3, -4.2, -6.0, -5.4, -1.5, 6.0, 12.6, 13.9, 12.3
    ]

    static let referenceLoudnessExponent: Double = 0.300
    static let defaultReferencePhon: Double = 80.0

    private static let referenceFrequencyIndex = 17
    private static let referenceSoundPressureSquaredPa: Double = 4e-10
    private static let supportedPhonRange = 20.0...90.0
    private static let estimatedPhonRange = 20.0...defaultReferencePhon

    // MARK: - Volume → Phon Mapping

    static func estimatedPhon(fromSystemVolume volume: Float) -> Double {
        let v = Double(max(0.0, min(1.0, volume)))
        return estimatedPhonRange.lowerBound
            + (defaultReferencePhon - estimatedPhonRange.lowerBound) * pow(v, 0.5)
    }

    // MARK: - Normative Contour Computation

    static func contourSPL(atPhon phon: Double) -> [Double] {
        let clampedPhon = min(max(phon, supportedPhonRange.lowerBound), supportedPhonRange.upperBound)
        let referenceThresholdDB = hearingThresholdsDB[referenceFrequencyIndex]
        return zip(loudnessPerceptionExponents, zip(transferMagnitudesDB, hearingThresholdsDB)).map {
            alphaF, pair in
            let (lu, tf) = pair

            let excitation =
                pow(referenceSoundPressureSquaredPa, referenceLoudnessExponent - alphaF) *
                (pow(10.0, (referenceLoudnessExponent * clampedPhon) / 10.0) -
                 pow(10.0, (referenceLoudnessExponent * referenceThresholdDB) / 10.0)) +
                pow(10.0, (referenceLoudnessExponent * (tf + lu)) / 10.0)

            return (10.0 / alphaF) * log10(excitation) - lu
        }
    }

    static func compensationGains(
        atPhon phon: Double,
        referencePhon: Double = defaultReferencePhon,
        amount: Double = 1.0,
        maxGainDB: Double = .greatestFiniteMagnitude
    ) -> [Double] {
        let clampedAmount = min(max(amount, 0.0), 1.0)
        let referenceContour = contourSPL(atPhon: referencePhon)
        let currentContour = contourSPL(atPhon: phon)
        let referenceAtOneKilohertz = referenceContour[referenceFrequencyIndex]
        let currentAtOneKilohertz = currentContour[referenceFrequencyIndex]

        return zip(referenceContour, currentContour).map { reference, current in
            let gain = ((current - currentAtOneKilohertz) - (reference - referenceAtOneKilohertz)) * clampedAmount
            return max(-maxGainDB, min(maxGainDB, gain))
        }
    }

    static func requiredHeadroomDB(forCompensationGains gains: [Double]) -> Double {
        max(0.0, gains.max() ?? 0.0)
    }

    // MARK: - Non-normative Interpolation

    static func interpolateCompensation(_ gains: [Double], atFrequency frequency: Double) -> Double {
        guard gains.count == frequencies.count else { return 0.0 }

        let logFrequency = log(frequency)
        let logFrequencies = frequencies.map { log($0) }

        if logFrequency <= logFrequencies.first! { return gains.first! }
        if logFrequency >= logFrequencies.last! { return gains.last! }

        var lowerIndex = 0
        for index in 0..<(logFrequencies.count - 1) where logFrequencies[index + 1] >= logFrequency {
            lowerIndex = index
            break
        }

        let upperIndex = lowerIndex + 1
        let t = (logFrequency - logFrequencies[lowerIndex]) / (logFrequencies[upperIndex] - logFrequencies[lowerIndex])
        return gains[lowerIndex] + t * (gains[upperIndex] - gains[lowerIndex])
    }
}