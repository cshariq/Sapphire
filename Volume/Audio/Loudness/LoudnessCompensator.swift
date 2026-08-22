//
//  LoudnessCompensator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import Accelerate

final class LoudnessCompensator: BiquadProcessor, @unchecked Sendable {

    // MARK: - Configuration

    private enum LoudnessFilterKind {
        case lowShelf
        case peaking
        case highShelf
    }

    private struct LoudnessFilterDefinition {
        let kind: LoudnessFilterKind
        let frequency: Double
        let q: Double
    }

    private static let filterDefinitions: [LoudnessFilterDefinition] = [
        .init(kind: .lowShelf, frequency: 80, q: 0.707),
        .init(kind: .peaking, frequency: 180, q: 0.7),
        .init(kind: .peaking, frequency: 3200, q: 0.7),
        .init(kind: .highShelf, frequency: 10000, q: 0.85),
    ]
    static let bandFrequencies = filterDefinitions.map(\.frequency)
    static let bandCount = filterDefinitions.count

    private static let fitGridPointCount = 96
    private static let fitIterationCount = 3

    // MARK: - State

    private var _currentPhon: Double = 80.0

    // MARK: - Init

    init(sampleRate: Double) {
        super.init(
            sampleRate: sampleRate,
            maxSections: Self.bandCount,
            category: "LoudnessCompensator",
            initiallyEnabled: false
        )
    }

    // MARK: - Volume Update

    func updateForVolume(_ systemVolume: Float) {
        let phon = ISO226Contours.estimatedPhon(fromSystemVolume: systemVolume)

        guard !isEnabled || abs(phon - _currentPhon) >= 1.0 else { return }
        _currentPhon = phon

        let gains = computeBandGains(phon: phon)

        let allNegligible = gains.allSatisfy { abs($0) < 0.1 }
        if allNegligible {
            setEnabled(false)
            swapSetup(nil)
            return
        }

        let coefficients = Self.coefficientsForBands(gains: gains, sampleRate: sampleRate)
        let newSetup = coefficients.withUnsafeBufferPointer { ptr in
            vDSP_biquad_CreateSetup(ptr.baseAddress!, vDSP_Length(Self.bandCount))
        }
        swapSetup(newSetup)
        setEnabled(true)
    }

    // MARK: - Coefficient Computation

    private func computeBandGains(phon: Double) -> [Float] {
        Self.fittedSectionGains(forPhon: phon, sampleRate: sampleRate)
    }

    static func fittedSectionGains(forPhon phon: Double, sampleRate: Double) -> [Float] {
        let targetCurve = targetCurveDB(forPhon: phon)
        let basisResponses = basisResponsesDB(sampleRate: sampleRate)
        let gramMatrix = gramMatrix(for: basisResponses)

        var sectionGains = [Double](repeating: 0.0, count: bandCount)
        for _ in 0..<fitIterationCount {
            let realized = realizedResponseDB(sectionGains: sectionGains, sampleRate: sampleRate)
            let residual = zip(targetCurve, realized).map { target, fitted in
                target - fitted
            }
            let rhs = basisResponses.map { basis in
                zip(basis, residual).reduce(0.0) { partial, pair in
                    partial + pair.0 * pair.1
                }
            }
            guard let delta = solveLinearSystem(gramMatrix, rhs: rhs) else { break }
            for index in 0..<bandCount {
                sectionGains[index] += delta[index]
            }
        }

        return sectionGains.map(Float.init)
    }

    static func coefficientsForBands(gains: [Float], sampleRate: Double) -> [Double] {
        guard gains.count == bandCount else {
            return (0..<bandCount).flatMap { _ in [1.0, 0.0, 0.0, 0.0, 0.0] }
        }

        var allCoeffs: [Double] = []
        allCoeffs.reserveCapacity(bandCount * 5)
        for (index, filter) in filterDefinitions.enumerated() {
            guard filter.frequency < sampleRate / 2.0 else {
                allCoeffs.append(contentsOf: [1.0, 0.0, 0.0, 0.0, 0.0])
                continue
            }
            let coeffs: [Double]
            switch filter.kind {
            case .lowShelf:
                coeffs = BiquadMath.lowShelfCoefficients(
                    frequency: filter.frequency,
                    gainDB: gains[index],
                    q: filter.q,
                    sampleRate: sampleRate
                )
            case .peaking:
                coeffs = BiquadMath.peakingEQCoefficients(
                    frequency: filter.frequency,
                    gainDB: gains[index],
                    q: filter.q,
                    sampleRate: sampleRate
                )
            case .highShelf:
                coeffs = BiquadMath.highShelfCoefficients(
                    frequency: filter.frequency,
                    gainDB: gains[index],
                    q: filter.q,
                    sampleRate: sampleRate
                )
            }
            allCoeffs.append(contentsOf: coeffs)
        }
        return allCoeffs
    }

    // MARK: - BiquadProcessor Overrides

    override func recomputeCoefficients() -> (coefficients: [Double], sectionCount: Int)? {
        let gains = computeBandGains(phon: _currentPhon)
        let allNegligible = gains.allSatisfy { abs($0) < 0.1 }
        guard !allNegligible else { return nil }
        let coefficients = Self.coefficientsForBands(gains: gains, sampleRate: sampleRate)
        return (coefficients, Self.bandCount)
    }

    private static func cascadeMagnitude(coefficients: [Double], sectionCount: Int, omega: Double) -> Double {
        let cosW = cos(omega)
        let sinW = sin(omega)
        let cos2W = cos(2.0 * omega)
        let sin2W = sin(2.0 * omega)

        var magnitude = 1.0
        for offset in stride(from: 0, to: sectionCount * 5, by: 5) {
            let numeratorReal = coefficients[offset] + coefficients[offset + 1] * cosW + coefficients[offset + 2] * cos2W
            let numeratorImag = -(coefficients[offset + 1] * sinW + coefficients[offset + 2] * sin2W)
            let denominatorReal = 1.0 + coefficients[offset + 3] * cosW + coefficients[offset + 4] * cos2W
            let denominatorImag = -(coefficients[offset + 3] * sinW + coefficients[offset + 4] * sin2W)

            let numeratorMagnitudeSquared = numeratorReal * numeratorReal + numeratorImag * numeratorImag
            let denominatorMagnitudeSquared = denominatorReal * denominatorReal + denominatorImag * denominatorImag
            magnitude *= sqrt(numeratorMagnitudeSquared / denominatorMagnitudeSquared)
        }

        return magnitude
    }

    private static func targetCurveDB(forPhon phon: Double) -> [Double] {
        let compensation = ISO226Contours.compensationGains(atPhon: phon)
        let fitFrequencies = fitGridFrequencies()
        return fitFrequencies.map { frequency in
            ISO226Contours.interpolateCompensation(compensation, atFrequency: frequency)
        }
    }

    private static func basisResponsesDB(sampleRate: Double) -> [[Double]] {
        let fitFrequencies = fitGridFrequencies()
        return filterDefinitions.map { filter in
            let coefficients: [Double]
            switch filter.kind {
            case .lowShelf:
                coefficients = BiquadMath.lowShelfCoefficients(
                    frequency: filter.frequency,
                    gainDB: 1.0,
                    q: filter.q,
                    sampleRate: sampleRate
                )
            case .peaking:
                coefficients = BiquadMath.peakingEQCoefficients(
                    frequency: filter.frequency,
                    gainDB: 1.0,
                    q: filter.q,
                    sampleRate: sampleRate
                )
            case .highShelf:
                coefficients = BiquadMath.highShelfCoefficients(
                    frequency: filter.frequency,
                    gainDB: 1.0,
                    q: filter.q,
                    sampleRate: sampleRate
                )
            }

            return fitFrequencies.map { frequency in
                let omega = 2.0 * Double.pi * frequency / sampleRate
                return 20.0 * log10(cascadeMagnitude(coefficients: coefficients, sectionCount: 1, omega: omega))
            }
        }
    }

    private static func realizedResponseDB(sectionGains: [Double], sampleRate: Double) -> [Double] {
        let coefficients = coefficientsForBands(gains: sectionGains.map(Float.init), sampleRate: sampleRate)
        return fitGridFrequencies().map { frequency in
            let omega = 2.0 * Double.pi * frequency / sampleRate
            return 20.0 * log10(cascadeMagnitude(coefficients: coefficients, sectionCount: bandCount, omega: omega))
        }
    }

    private static func fitGridFrequencies() -> [Double] {
        (0..<fitGridPointCount).map { index in
            20.0 * pow(20_000.0 / 20.0, Double(index) / Double(fitGridPointCount - 1))
        }
    }

    private static func gramMatrix(for basisResponses: [[Double]]) -> [[Double]] {
        (0..<bandCount).map { row in
            (0..<bandCount).map { column in
                zip(basisResponses[row], basisResponses[column]).reduce(0.0) { partial, pair in
                    partial + pair.0 * pair.1
                }
            }
        }
    }

    private static func solveLinearSystem(_ matrix: [[Double]], rhs: [Double]) -> [Double]? {
        var augmented = matrix.enumerated().map { index, row in
            row + [rhs[index]]
        }
        let size = rhs.count

        for pivotIndex in 0..<size {
            let bestPivotIndex = (pivotIndex..<size).max { lhs, rhsIndex in
                abs(augmented[lhs][pivotIndex]) < abs(augmented[rhsIndex][pivotIndex])
            } ?? pivotIndex

            guard abs(augmented[bestPivotIndex][pivotIndex]) > 1e-12 else {
                return nil
            }

            if bestPivotIndex != pivotIndex {
                augmented.swapAt(bestPivotIndex, pivotIndex)
            }

            let pivot = augmented[pivotIndex][pivotIndex]
            for column in pivotIndex...size {
                augmented[pivotIndex][column] /= pivot
            }

            for row in 0..<size where row != pivotIndex {
                let factor = augmented[row][pivotIndex]
                guard factor != 0 else { continue }
                for column in pivotIndex...size {
                    augmented[row][column] -= factor * augmented[pivotIndex][column]
                }
            }
        }

        return (0..<size).map { augmented[$0][size] }
    }

}