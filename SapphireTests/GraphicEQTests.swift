//
//  GraphicEQTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import XCTest
@testable import Sapphire

final class GraphicEQTests: XCTestCase {

    private let rate = 48000.0

    private func responseDB(_ biquad: EQBiquad, _ frequency: Double, _ sampleRate: Double = 48000) -> Double {
        biquad.responseDB(at: 2 * .pi * frequency / sampleRate)
    }

    private func gains(_ value: (Int) -> Double) -> [Double] { (0..<AudioEQ.bandCount).map(value) }

    // MARK: Filter design

    func testPeakingHitsItsGainAtTheCentreAndHalfAtTheBandEdges() {
        let bandwidth = 1000 * GraphicEQDesigner.bandwidthRatio
        let filter = GraphicEQDesigner.peaking(frequency: 1000, bandwidth: bandwidth, gainDB: 12, sampleRate: rate)
        let lower = (-bandwidth + (bandwidth * bandwidth + 4e6).squareRoot()) / 2
        XCTAssertEqual(responseDB(filter, 1000), 12, accuracy: 0.01)
        XCTAssertEqual(responseDB(filter, lower), 6, accuracy: 0.05)
        XCTAssertEqual(responseDB(filter, lower + bandwidth), 6, accuracy: 0.05)
    }

    func testPeakingKeepsItsGainNearNyquist() {
        let filter = GraphicEQDesigner.peaking(frequency: 16000, bandwidth: 16000 * GraphicEQDesigner.bandwidthRatio, gainDB: -9, sampleRate: 44100)
        XCTAssertEqual(responseDB(filter, 16000, 44100), -9, accuracy: 0.01)
    }

    func testZeroGainIsIdentity() {
        XCTAssertTrue(GraphicEQDesigner.peaking(frequency: 100, bandwidth: 30, gainDB: 0, sampleRate: rate).isIdentity)
        XCTAssertTrue(GraphicEQDesigner.design(gains: AudioEQ.flat, bass: 0, sampleRate: rate).isFlat)
    }

    // MARK: Curve accuracy

    private func assertFollowsCurve(_ curve: [Double], tolerance: Double, sampleRate: Double = 48000, file: StaticString = #filePath, line: UInt = #line) {
        let plan = GraphicEQDesigner.plan(gains: curve, bass: 0, sampleRate: sampleRate)
        for band in 0..<AudioEQ.bandCount where AudioEQ.frequencies[band] < 0.46 * sampleRate {
            let measured = GraphicEQDesigner.responseDB(plan.biquads, frequency: AudioEQ.frequencies[band], sampleRate: sampleRate)
            XCTAssertEqual(measured, curve[band], accuracy: tolerance, "band \(AudioEQ.frequencies[band]) Hz", file: file, line: line)
        }
    }

    func testOverlappingBoostsFollowTheDrawnCurveInsteadOfStacking() {
        let bassHeavy = [15, 15, 13.5, 12, 11.6, 11.2, 9.8, 8.5, 6.9, 5.3, 4.9, 4.5, 5.6, 6.7, 3.4] + Array(repeating: 0.0, count: 16)
        assertFollowsCurve(bassHeavy, tolerance: 0.5)
        assertFollowsCurve(bassHeavy, tolerance: 0.5, sampleRate: 44100)
        assertFollowsCurve(gains { _ in 12 }, tolerance: 0.5)
        assertFollowsCurve(gains { $0 % 2 == 0 ? 6 : -6 }, tolerance: 0.5)
    }

    func testPreampCancelsThePeakBoost() {
        let plan = GraphicEQDesigner.plan(gains: gains { _ in 12 }, bass: 0, sampleRate: rate)
        XCTAssertEqual(plan.preampDB, -12, accuracy: 0.5)
        XCTAssertEqual(GraphicEQDesigner.plan(gains: gains { $0 == 17 ? -12 : 0 }, bass: 0, sampleRate: rate).preampDB, 0, accuracy: 0.6)
    }

    func testBandsFarFromAnyChangeGetNoFilter() {
        let plan = GraphicEQDesigner.plan(gains: gains { $0 == 17 ? 6 : 0 }, bass: 0, sampleRate: rate)
        let shaped = plan.biquads.enumerated().filter { !$0.element.isIdentity }.map(\.offset)
        XCTAssertEqual(Set(shaped), Set(15...19))
    }

    func testBandsAboveNyquistAreDropped() {
        let plan = GraphicEQDesigner.plan(gains: gains { _ in 6 }, bass: 0, sampleRate: 16000)
        for band in 0..<AudioEQ.bandCount where AudioEQ.frequencies[band] >= 0.46 * 16000 {
            XCTAssertTrue(plan.biquads[band].isIdentity)
        }
    }

    // MARK: Processing

    private func sine(_ frequency: Double, frames: Int, amplitude: Float = 0.1) -> [Float] {
        (0..<frames).flatMap { frame -> [Float] in
            let value = amplitude * Float(sin(2 * .pi * frequency * Double(frame) / rate))
            return [value, value]
        }
    }

    func testFlatProcessorLeavesSamplesUntouched() {
        let processor = GraphicEQProcessor()
        let input = sine(440, frames: 1024)
        var buffer = input
        buffer.withUnsafeMutableBufferPointer { processor.process($0.baseAddress!, frames: 1024) }
        XCTAssertEqual(buffer, input)
        XCTAssertTrue(processor.isTransparent)
    }

    func testBoostedBandReachesItsDesignedLevel() {
        let processor = GraphicEQProcessor()
        processor.post(GraphicEQDesigner.design(gains: gains { $0 == 17 ? 12 : 0 }, bass: 0, sampleRate: rate))
        var buffer = sine(1000, frames: 24000)
        buffer.withUnsafeMutableBufferPointer { processor.process($0.baseAddress!, frames: 24000) }
        let tailPeak = buffer.suffix(4800).map(abs).max() ?? 0
        XCTAssertEqual(Double(tailPeak), 0.1, accuracy: 0.01)
    }

    func testDesignChangesGlideWithoutClicks() {
        let processor = GraphicEQProcessor()
        let frames = 96000
        var buffer = sine(60, frames: frames)
        let changes: [Int: [Double]] = [
            0: gains { $0 == 5 ? 12 : 0 },
            40: gains { $0 == 5 ? -12 : 0 },
            70: gains { $0 == 5 ? -12 : ($0 == 17 ? 9 : 0) },
            110: AudioEQ.flat,
        ]
        buffer.withUnsafeMutableBufferPointer { pointer in
            for block in 0..<(frames / 480) {
                if let curve = changes[block] { processor.post(GraphicEQDesigner.design(gains: curve, bass: 0, sampleRate: rate)) }
                processor.process(pointer.baseAddress! + block * 960, frames: 480)
            }
        }
        var worst: Float = 0
        for frame in 2..<frames {
            worst = max(worst, abs(buffer[frame * 2] - 2 * buffer[(frame - 1) * 2] + buffer[(frame - 2) * 2]))
        }
        XCTAssertLessThan(worst, 0.002)
    }

    func testRemovedBandsRingOutThenTheProcessorGoesTransparent() {
        let processor = GraphicEQProcessor()
        processor.post(GraphicEQDesigner.design(gains: gains { $0 == 3 ? 10 : 0 }, bass: 4, sampleRate: rate))
        var buffer = sine(40, frames: 4800)
        buffer.withUnsafeMutableBufferPointer { processor.process($0.baseAddress!, frames: 4800) }
        processor.post(.flat)
        var silence = [Float](repeating: 0, count: 2 * 48000)
        silence.withUnsafeMutableBufferPointer { pointer in
            for block in 0..<100 { processor.process(pointer.baseAddress! + block * 960, frames: 480) }
        }
        XCTAssertTrue(processor.isTransparent)
        XCTAssertLessThan(silence.suffix(960).map(abs).max() ?? 1, 1e-9)
    }

    // MARK: Limiter

    func testLimiterNeverPassesAPeakAboveTheCeiling() {
        let limiter = LookaheadLimiter(sampleRate: rate, lookaheadSeconds: 0.002)
        var generator = SystemRandomNumberGenerator()
        let frames = 48000
        var buffer = (0..<frames * 2).map { index -> Float in
            let burst: Float = (index / 3000) % 3 == 0 ? 4 : 0.5
            return burst * Float.random(in: -1...1, using: &generator)
        }
        buffer.withUnsafeMutableBufferPointer { limiter.process($0.baseAddress!, frames: frames, channels: 2) }
        XCTAssertLessThanOrEqual(buffer.map(abs).max() ?? 0, limiter.ceiling + 1e-5)
    }
}