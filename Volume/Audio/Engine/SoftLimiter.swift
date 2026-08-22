//
//  SoftLimiter.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Accelerate

enum SoftLimiter {

    static let threshold: Float = 0.95

    static let ceiling: Float = 1.0

    @inline(__always)
    static var headroom: Float { ceiling - threshold }

    @inline(__always)
    static func apply(_ sample: Float) -> Float {
        let absSample = abs(sample)

        if absSample <= threshold {
            return sample
        }

        let overshoot = absSample - threshold
        let compressed = threshold + headroom * (overshoot / (overshoot + headroom))

        return sample >= 0 ? compressed : -compressed
    }

    @inline(__always)
    static func processBuffer(_ buffer: UnsafeMutablePointer<Float>, sampleCount: Int) {
        var bufferPeak: Float = 0
        vDSP_maxmgv(buffer, 1, &bufferPeak, vDSP_Length(sampleCount))
        guard bufferPeak > threshold else { return }

        for i in 0..<sampleCount {
            buffer[i] = apply(buffer[i])
        }
    }
}