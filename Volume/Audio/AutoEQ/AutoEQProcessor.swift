//
//  AutoEQProcessor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import Accelerate

final class AutoEQProcessor: BiquadProcessor, @unchecked Sendable {

    private var _currentProfile: AutoEQProfile?

    var currentProfile: AutoEQProfile? { _currentProfile }

    private var _preampEnabled: Bool = true

    private nonisolated(unsafe) var _preampGain: Float = 1.0

    private nonisolated(unsafe) var _filterCount: UInt = 0

    init(sampleRate: Double) {
        super.init(
            sampleRate: sampleRate,
            maxSections: AutoEQProfile.maxFilters,
            category: "AutoEQProcessor"
        )
    }

    // MARK: - Profile Update

    func updateProfile(_ profile: AutoEQProfile?) {
        dispatchPrecondition(condition: .onQueue(.main))
        _currentProfile = profile

        let validated = profile?.validated()
        guard let validated, !validated.filters.isEmpty else {
            setEnabled(false)
            _filterCount = 0
            _preampGain = 1.0
            swapSetup(nil)
            logger.info("AutoEQ disabled — \(profile == nil ? "nil profile" : "no valid filters after validation")")
            return
        }

        let filters = validated.filters
        let coefficients = BiquadMath.coefficientsForAutoEQFilters(
            filters, sampleRate: sampleRate,
            profileOptimizedRate: validated.optimizedSampleRate
        )

        guard let newSetup = coefficients.withUnsafeBufferPointer({ ptr in
            vDSP_biquad_CreateSetup(ptr.baseAddress!, vDSP_Length(filters.count))
        }) else {
            logger.warning("vDSP_biquad_CreateSetup returned nil for \(filters.count) filters — skipping profile update")
            return
        }

        let preampLinear = _preampEnabled ? powf(10.0, validated.preampDB / 20.0) : 1.0

        _preampGain = preampLinear
        _filterCount = UInt(filters.count)
        swapSetup(newSetup)
        setEnabled(true)

        let preampStatus = self._preampEnabled ? "active" : "bypassed"
        logger.info("AutoEQ applied: \"\(validated.name)\" — \(filters.count) filters, preamp \(validated.preampDB, format: .fixed(precision: 1)) dB (\(preampStatus)), gain \(preampLinear, format: .fixed(precision: 3))x, rate \(self.sampleRate, format: .fixed(precision: 0)) Hz")

    }

    // MARK: - Preamp Mode

    func setPreampEnabled(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled != _preampEnabled else { return }
        _preampEnabled = enabled
        logger.info("AutoEQ preamp \(enabled ? "enabled" : "bypassed (limiter-only)")")
        if let profile = _currentProfile {
            updateProfile(profile)
        }
    }

    // MARK: - BiquadProcessor Overrides

    override func recomputeCoefficients() -> (coefficients: [Double], sectionCount: Int)? {
        guard let profile = _currentProfile?.validated(), !profile.filters.isEmpty else { return nil }
        let coefficients = BiquadMath.coefficientsForAutoEQFilters(
            profile.filters, sampleRate: sampleRate,
            profileOptimizedRate: profile.optimizedSampleRate
        )
        return (coefficients, profile.filters.count)
    }

    override func preProcess(output: UnsafeMutablePointer<Float>, frameCount: Int) {
        var preamp = _preampGain
        let sampleCount = frameCount * 2
        vDSP_vsmul(output, 1, &preamp, output, 1, vDSP_Length(sampleCount))
    }
}