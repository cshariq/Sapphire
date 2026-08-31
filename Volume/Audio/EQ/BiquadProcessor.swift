//
//  BiquadProcessor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import Accelerate
import Darwin.C
import os

class BiquadProcessor: @unchecked Sendable, BiquadProcessable {

    let logger: Logger

    private(set) var sampleRate: Double

    // MARK: - RT-Safe State

    private nonisolated(unsafe) var _eqSetup: vDSP_biquad_Setup?

    private nonisolated(unsafe) var _isEnabled: Bool

    // MARK: - Pre-allocated Delay Buffers

    private let delayBufferL: UnsafeMutablePointer<Float>
    private let delayBufferR: UnsafeMutablePointer<Float>
    private let delayBufferSize: Int

    var isEnabled: Bool { _isEnabled }

    func setEnabled(_ enabled: Bool) {
        _isEnabled = enabled
    }

    // MARK: - Init / Deinit

    init(sampleRate: Double, maxSections: Int, category: String, initiallyEnabled: Bool = false) {
        self.sampleRate = sampleRate
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: category)
        self._isEnabled = initiallyEnabled
        self.delayBufferSize = (2 * maxSections) + 2

        delayBufferL = .allocate(capacity: delayBufferSize)
        delayBufferL.initialize(repeating: 0, count: delayBufferSize)
        delayBufferR = .allocate(capacity: delayBufferSize)
        delayBufferR.initialize(repeating: 0, count: delayBufferSize)
    }

    deinit {
        if let setup = _eqSetup {
            vDSP_biquad_DestroySetup(setup)
        }
        delayBufferL.deallocate()
        delayBufferR.deallocate()
    }

    // MARK: - Setup Management (main thread)

    func swapSetup(_ newSetup: vDSP_biquad_Setup?) {
        let oldSetup = _eqSetup
        _eqSetup = newSetup
        if let old = oldSetup {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                vDSP_biquad_DestroySetup(old)
            }
        }
    }

    func resetDelayBuffers() {
        let wasEnabled = _isEnabled
        _isEnabled = false
        OSMemoryBarrier()

        memset(delayBufferL, 0, delayBufferSize * MemoryLayout<Float>.size)
        memset(delayBufferR, 0, delayBufferSize * MemoryLayout<Float>.size)

        _isEnabled = wasEnabled
        OSMemoryBarrier()
    }

    func updateSampleRate(_ newRate: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        let oldRate = sampleRate
        guard newRate != sampleRate else { return }
        sampleRate = newRate

        guard let (coefficients, sectionCount) = recomputeCoefficients() else {
            return
        }

        let newSetup = coefficients.withUnsafeBufferPointer { ptr in
            vDSP_biquad_CreateSetup(ptr.baseAddress!, vDSP_Length(sectionCount))
        }

        guard let newSetup else {
            logger.warning("vDSP_biquad_CreateSetup returned nil at \(newRate, format: .fixed(precision: 0))Hz")
            return
        }

        let oldSetup = _eqSetup
        let wasEnabled = _isEnabled
        _isEnabled = false
        OSMemoryBarrier()

        _eqSetup = newSetup
        memset(delayBufferL, 0, delayBufferSize * MemoryLayout<Float>.size)
        memset(delayBufferR, 0, delayBufferSize * MemoryLayout<Float>.size)

        _isEnabled = wasEnabled
        OSMemoryBarrier()

        if let old = oldSetup {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                vDSP_biquad_DestroySetup(old)
            }
        }

        logger.info("Sample rate: \(oldRate, format: .fixed(precision: 0))Hz → \(newRate, format: .fixed(precision: 0))Hz")
    }

    // MARK: - Subclass Hooks

    func recomputeCoefficients() -> (coefficients: [Double], sectionCount: Int)? {
        return nil
    }

    func preProcess(output: UnsafeMutablePointer<Float>, frameCount: Int) {
    }

    // MARK: - Audio Processing (RT-safe)

    func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frameCount: Int) {
        let enabled = _isEnabled
        let setup = _eqSetup

        guard enabled, let setup = setup else {
            if input != UnsafePointer(output) {
                memcpy(output, input, frameCount * 2 * MemoryLayout<Float>.size)
            }
            return
        }

        if input != UnsafePointer(output) {
            memcpy(output, input, frameCount * 2 * MemoryLayout<Float>.size)
        }

        preProcess(output: output, frameCount: frameCount)

        vDSP_biquad(setup, delayBufferL, output, 2, output, 2, vDSP_Length(frameCount))
        vDSP_biquad(setup, delayBufferR, output.advanced(by: 1), 2, output.advanced(by: 1), 2, vDSP_Length(frameCount))

        if output[0].isNaN || output[1].isNaN {
            memset(delayBufferL, 0, delayBufferSize * MemoryLayout<Float>.size)
            memset(delayBufferR, 0, delayBufferSize * MemoryLayout<Float>.size)
            memset(output, 0, frameCount * 2 * MemoryLayout<Float>.size)
        }
    }
}