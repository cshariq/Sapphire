//
//  GraphicEQ.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import Foundation
import os

// MARK: - Biquad

struct EQBiquad: Equatable {
    var b0, b1, b2, a1, a2: Double

    static let identity = EQBiquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    var isIdentity: Bool { self == .identity }

    func magnitudeSquared(at w: Double) -> Double {
        let c1 = cos(w), c2 = cos(2 * w)
        let num = b0 * b0 + b1 * b1 + b2 * b2 + 2 * (b0 * b1 + b1 * b2) * c1 + 2 * b0 * b2 * c2
        let den = 1 + a1 * a1 + a2 * a2 + 2 * (a1 + a1 * a2) * c1 + 2 * a2 * c2
        return num / den
    }

    func responseDB(at w: Double) -> Double {
        10 * log10(max(magnitudeSquared(at: w), 1e-30))
    }
}

// MARK: - Design

enum GraphicEQDesigner {
    static let sectionCount = AudioEQ.bandCount + 1

    static let bandwidthRatio = 1.5 * (pow(2.0, 1.0 / 6.0) - pow(2.0, -1.0 / 6.0))
    static let prototypeGainDB = 12.0
    static let maxBandGainDB = 30.0

    struct Design: Equatable {
        var sections: [EQBiquad]
        var preamp: Double
        var isFlat: Bool { preamp == 1 && sections.allSatisfy(\.isIdentity) }

        static let flat = Design(sections: Array(repeating: .identity, count: GraphicEQDesigner.sectionCount), preamp: 1)
    }

    struct Plan {
        var biquads: [EQBiquad]
        var bandGainsDB: [Double]
        var preampDB: Double
    }

    static func design(gains: [Double], bass: Double, sampleRate: Double) -> Design {
        let plan = plan(gains: gains, bass: bass, sampleRate: sampleRate)
        return Design(sections: plan.biquads, preamp: pow(10, plan.preampDB / 20))
    }

    static func plan(gains rawGains: [Double], bass: Double, sampleRate: Double) -> Plan {
        let gains = AudioEQ.normalize(rawGains)
        let fs = max(sampleRate, 8000)
        var biquads = Array(repeating: EQBiquad.identity, count: sectionCount)
        var bandGains = Array(repeating: 0.0, count: AudioEQ.bandCount)

        let usable = (0..<AudioEQ.bandCount).filter { isUsable(band: $0, sampleRate: fs) }
        let shaped = usable.filter { band in
            (max(0, band - 2)...min(AudioEQ.bandCount - 1, band + 2)).contains { abs(gains[$0]) > 0.01 }
        }
        if !shaped.isEmpty {
            let solved = solveBandGains(targets: gains, bands: shaped, points: usable, sampleRate: fs)
            for (band, gain) in zip(shaped, solved) where abs(gain) > 0.005 {
                bandGains[band] = gain
                biquads[band] = bandFilter(band, gainDB: gain, sampleRate: fs)
            }
        }
        if abs(bass) > 0.01 {
            biquads[AudioEQ.bandCount] = lowShelf(frequency: AudioEQ.bassShelfFrequency, gainDB: bass, sampleRate: fs)
        }

        let peak = peakResponseDB(biquads, sampleRate: fs)
        return Plan(biquads: biquads, bandGainsDB: bandGains, preampDB: peak > 0.05 ? -peak : 0)
    }

    static func responseDB(_ biquads: [EQBiquad], frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * .pi * frequency / sampleRate
        return biquads.reduce(0) { $0 + ($1.isIdentity ? 0 : $1.responseDB(at: w)) }
    }

    // MARK: Bands

    private static func isUsable(band: Int, sampleRate: Double) -> Bool {
        AudioEQ.frequencies[band] < 0.46 * sampleRate
    }

    static func bandFilter(_ band: Int, gainDB: Double, sampleRate: Double) -> EQBiquad {
        let f = AudioEQ.frequencies[band]
        return peaking(frequency: f, bandwidth: f * bandwidthRatio, gainDB: gainDB, sampleRate: sampleRate)
    }

    static func peaking(frequency: Double, bandwidth: Double, gainDB: Double, sampleRate: Double) -> EQBiquad {
        guard abs(gainDB) > 1e-4 else { return .identity }
        let w0 = 2 * .pi * frequency / sampleRate
        let dw = min(2 * .pi * bandwidth / sampleRate, 2 * (0.98 * .pi - w0))
        let g0 = 1.0
        let g = pow(10, gainDB / 20)
        let gb = g.squareRoot()
        let gg = g * g, gbb = gb * gb

        let f = abs(gg - gbb)
        let g00 = abs(gg - g0 * g0)
        let f00 = abs(gbb - g0 * g0)
        let piSq = Double.pi * Double.pi
        let warp = (w0 * w0 - piSq) * (w0 * w0 - piSq)
        let g1 = ((g0 * g0 * warp + gg * f00 * piSq * dw * dw / f) / (warp + f00 * piSq * dw * dw / f)).squareRoot()
        let g01 = abs(gg - g0 * g1)
        let g11 = abs(gg - g1 * g1)
        let f01 = abs(gbb - g0 * g1)
        let f11 = abs(gbb - g1 * g1)
        let tw = tan(w0 / 2)
        let w2 = (g11 / g00).squareRoot() * tw * tw
        let dW = (1 + (f00 / f11).squareRoot() * w2) * tan(dw / 2)
        let c = f11 * dW * dW - 2 * w2 * (f01 - (f00 * f11).squareRoot())
        let d = 2 * w2 * (g01 - (g00 * g11).squareRoot())
        let a = ((c + d) / f).squareRoot()
        let b = ((gg * c + gbb * d) / f).squareRoot()
        let norm = 1 + w2 + a
        return EQBiquad(
            b0: (g1 + g0 * w2 + b) / norm,
            b1: -2 * (g1 - g0 * w2) / norm,
            b2: (g1 - b + g0 * w2) / norm,
            a1: -2 * (1 - w2) / norm,
            a2: (1 + w2 - a) / norm
        )
    }

    static func lowShelf(frequency: Double, gainDB: Double, sampleRate: Double, slope: Double = 0.9) -> EQBiquad {
        guard abs(gainDB) > 1e-4 else { return .identity }
        let A = pow(10, gainDB / 40)
        let w0 = 2 * .pi * frequency / sampleRate
        let cs = cos(w0), sn = sin(w0)
        let alpha = sn / 2 * ((A + 1 / A) * (1 / slope - 1) + 2).squareRoot()
        let t = 2 * A.squareRoot() * alpha
        let a0 = (A + 1) + (A - 1) * cs + t
        return EQBiquad(
            b0: A * ((A + 1) - (A - 1) * cs + t) / a0,
            b1: 2 * A * ((A - 1) - (A + 1) * cs) / a0,
            b2: A * ((A + 1) - (A - 1) * cs - t) / a0,
            a1: -2 * ((A - 1) + (A + 1) * cs) / a0,
            a2: ((A + 1) + (A - 1) * cs - t) / a0
        )
    }

    static func highShelf(frequency: Double, gainDB: Double, sampleRate: Double, slope: Double = 1) -> EQBiquad {
        guard abs(gainDB) > 1e-4 else { return .identity }
        let A = pow(10, gainDB / 40)
        let w0 = 2 * .pi * frequency / sampleRate
        let cs = cos(w0), sn = sin(w0)
        let alpha = sn / 2 * ((A + 1 / A) * (1 / slope - 1) + 2).squareRoot()
        let t = 2 * A.squareRoot() * alpha
        let a0 = (A + 1) - (A - 1) * cs + t
        return EQBiquad(
            b0: A * ((A + 1) + (A - 1) * cs + t) / a0,
            b1: -2 * A * ((A - 1) + (A + 1) * cs) / a0,
            b2: A * ((A + 1) + (A - 1) * cs - t) / a0,
            a1: 2 * ((A - 1) - (A + 1) * cs) / a0,
            a2: ((A + 1) - (A - 1) * cs - t) / a0
        )
    }

    // MARK: Interaction solve

    private static func solveBandGains(targets: [Double], bands: [Int], points pointBands: [Int], sampleRate: Double) -> [Double] {
        var points: [Double] = []
        var pointTargets: [Double] = []
        for (index, band) in pointBands.enumerated() {
            points.append(AudioEQ.frequencies[band])
            pointTargets.append(targets[band])
            if index + 1 < pointBands.count {
                let next = pointBands[index + 1]
                points.append((AudioEQ.frequencies[band] * AudioEQ.frequencies[next]).squareRoot())
                pointTargets.append((targets[band] + targets[next]) / 2)
            }
        }
        let omegas = points.map { 2 * .pi * $0 / sampleRate }

        func matrix(prototypes: [Double]) -> [[Double]] {
            omegas.map { w in
                zip(bands, prototypes).map { band, gain in
                    bandFilter(band, gainDB: gain, sampleRate: sampleRate).responseDB(at: w) / gain
                }
            }
        }

        let first = leastSquares(matrix(prototypes: Array(repeating: prototypeGainDB, count: bands.count)), pointTargets)
        let prototypes = first.map { abs($0) < 1 ? ($0 < 0 ? -1 : 1) : $0 }
        let second = leastSquares(matrix(prototypes: prototypes), pointTargets)
        return second.map { min(max($0, -maxBandGainDB), maxBandGainDB) }
    }

    private static func leastSquares(_ b: [[Double]], _ t: [Double], lambda: Double = 1e-3) -> [Double] {
        let n = b.first?.count ?? 0
        guard n > 0 else { return [] }
        var m = Array(repeating: Array(repeating: 0.0, count: n + 1), count: n)
        for row in 0..<b.count {
            let r = b[row]
            for i in 0..<n {
                m[i][n] += r[i] * t[row]
                for j in 0..<n { m[i][j] += r[i] * r[j] }
            }
        }
        for i in 0..<n { m[i][i] += lambda }

        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<n where abs(m[row][col]) > abs(m[pivot][col]) { pivot = row }
            if pivot != col { m.swapAt(pivot, col) }
            let p = m[col][col]
            guard abs(p) > 1e-12 else { continue }
            for row in (col + 1)..<n {
                let factor = m[row][col] / p
                guard factor != 0 else { continue }
                for j in col...n { m[row][j] -= factor * m[col][j] }
            }
        }
        var x = Array(repeating: 0.0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = m[i][n]
            for j in (i + 1)..<n { sum -= m[i][j] * x[j] }
            x[i] = abs(m[i][i]) > 1e-12 ? sum / m[i][i] : 0
        }
        return x
    }

    // MARK: Headroom

    private static func peakResponseDB(_ biquads: [EQBiquad], sampleRate: Double) -> Double {
        let active = biquads.filter { !$0.isIdentity }
        guard !active.isEmpty else { return 0 }
        let low = log(15.0), high = log(min(21000, 0.495 * sampleRate))
        let steps = 480
        var peak = -Double.infinity
        for step in 0...steps {
            let f = exp(low + (high - low) * Double(step) / Double(steps))
            let w = 2 * .pi * f / sampleRate
            var power = 1.0
            for biquad in active { power *= biquad.magnitudeSquared(at: w) }
            peak = max(peak, 10 * log10(power))
        }
        return peak
    }
}

// MARK: - Realtime processor

final class GraphicEQProcessor {
    static let capacity = GraphicEQDesigner.sectionCount
    static let rampStepFrames = 32
    static let rampSteps = 48
    static let blockFrames = 512

    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private let pending: UnsafeMutablePointer<EQBiquad>
    private var pendingPreamp = 1.0
    private var pendingVersion: UInt64 = 0

    private var appliedVersion: UInt64 = 0
    private let current: UnsafeMutablePointer<EQBiquad>
    private let target: UnsafeMutablePointer<EQBiquad>
    private let z1: UnsafeMutablePointer<SIMD2<Double>>
    private let z2: UnsafeMutablePointer<SIMD2<Double>>
    private let enabled: UnsafeMutablePointer<Bool>
    private let retiring: UnsafeMutablePointer<Bool>
    private let activeList: UnsafeMutablePointer<Int>
    private let block: UnsafeMutablePointer<SIMD2<Double>>
    private var activeCount = 0
    private var preamp = 1.0
    private var preampTarget = 1.0
    private var rampRemaining = 0

    init() {
        let n = Self.capacity
        lock = .allocate(capacity: 1); lock.initialize(to: os_unfair_lock_s())
        pending = .allocate(capacity: n); pending.initialize(repeating: .identity, count: n)
        current = .allocate(capacity: n); current.initialize(repeating: .identity, count: n)
        target = .allocate(capacity: n); target.initialize(repeating: .identity, count: n)
        z1 = .allocate(capacity: n); z1.initialize(repeating: .zero, count: n)
        z2 = .allocate(capacity: n); z2.initialize(repeating: .zero, count: n)
        enabled = .allocate(capacity: n); enabled.initialize(repeating: false, count: n)
        retiring = .allocate(capacity: n); retiring.initialize(repeating: false, count: n)
        activeList = .allocate(capacity: n); activeList.initialize(repeating: 0, count: n)
        block = .allocate(capacity: Self.blockFrames); block.initialize(repeating: .zero, count: Self.blockFrames)
    }

    deinit {
        lock.deinitialize(count: 1); lock.deallocate()
        pending.deallocate(); current.deallocate(); target.deallocate()
        z1.deallocate(); z2.deallocate(); enabled.deallocate(); retiring.deallocate()
        activeList.deallocate(); block.deallocate()
    }

    func post(_ design: GraphicEQDesigner.Design) {
        os_unfair_lock_lock(lock)
        for i in 0..<Self.capacity {
            pending[i] = i < design.sections.count ? design.sections[i] : .identity
        }
        pendingPreamp = design.preamp
        pendingVersion &+= 1
        os_unfair_lock_unlock(lock)
    }

    var isTransparent: Bool { activeCount == 0 && rampRemaining == 0 && preamp == 1 }

    var activeSectionCount: Int { activeCount }

    @_optimize(speed)
    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int) {
        pickUpPendingDesign()
        guard !isTransparent, frames > 0 else { return }

        var offset = 0
        while offset < frames {
            let start = preamp
            let n: Int
            if rampRemaining > 0 {
                n = min(Self.rampStepFrames, frames - offset)
                advanceRamp()
            } else {
                n = min(Self.blockFrames, frames - offset)
            }
            render(samples.advanced(by: offset * 2), frames: n, gain: start, gainEnd: preamp)
            offset += n
        }
    }

    // MARK: Rendering

    @_optimize(speed)
    private func render(_ samples: UnsafeMutablePointer<Float>, frames: Int, gain start: Double, gainEnd: Double) {
        let block = self.block
        samples.withMemoryRebound(to: SIMD2<Float>.self, capacity: frames) { frame in
            if start == gainEnd {
                for n in 0..<frames { block[n] = SIMD2<Double>(frame[n]) * start }
            } else {
                let step = (gainEnd - start) / Double(frames)
                var gain = start
                for n in 0..<frames { block[n] = SIMD2<Double>(frame[n]) * gain; gain += step }
            }

            var j = 0
            if frames >= 4 {
                while j + 4 <= activeCount {
                    runFour(activeList[j], activeList[j + 1], activeList[j + 2], activeList[j + 3], frames: frames)
                    j += 4
                }
            }
            while j < activeCount {
                runOne(activeList[j], frames: frames)
                j += 1
            }

            for n in 0..<frames { frame[n] = SIMD2<Float>(block[n]) }
        }

        var dropped = false
        for j in 0..<activeCount {
            let i = activeList[j]
            let energy = (z1[i] * z1[i] + z2[i] * z2[i]).max()
            if retiring[i], rampRemaining == 0, energy < 1e-18 {
                enabled[i] = false
                retiring[i] = false
                dropped = true
            }
            if energy < 1e-40 || !enabled[i] { z1[i] = .zero; z2[i] = .zero }
        }
        if dropped { rebuildActiveList() }
    }

    @inline(__always)
    private static func tick(_ c: EQBiquad, _ x: SIMD2<Double>, _ s1: inout SIMD2<Double>, _ s2: inout SIMD2<Double>) -> SIMD2<Double> {
        let y = c.b0 * x + s1
        s1 = c.b1 * x - c.a1 * y + s2
        s2 = c.b2 * x - c.a2 * y
        return y
    }

    @_optimize(speed)
    private func runOne(_ i: Int, frames: Int) {
        let c = current[i]
        var s1 = z1[i], s2 = z2[i]
        for n in 0..<frames { block[n] = Self.tick(c, block[n], &s1, &s2) }
        z1[i] = s1; z2[i] = s2
    }

    @_optimize(speed)
    private func runFour(_ i0: Int, _ i1: Int, _ i2: Int, _ i3: Int, frames: Int) {
        let b = block
        let c0 = current[i0], c1 = current[i1], c2 = current[i2], c3 = current[i3]
        var p1 = z1[i0], p2 = z2[i0], q1 = z1[i1], q2 = z2[i1]
        var r1 = z1[i2], r2 = z2[i2], u1 = z1[i3], u2 = z2[i3]

        b[0] = Self.tick(c0, b[0], &p1, &p2)
        b[1] = Self.tick(c0, b[1], &p1, &p2); b[0] = Self.tick(c1, b[0], &q1, &q2)
        b[2] = Self.tick(c0, b[2], &p1, &p2); b[1] = Self.tick(c1, b[1], &q1, &q2); b[0] = Self.tick(c2, b[0], &r1, &r2)
        var n = 3
        while n < frames {
            let y0 = Self.tick(c0, b[n], &p1, &p2)
            let y1 = Self.tick(c1, b[n - 1], &q1, &q2)
            let y2 = Self.tick(c2, b[n - 2], &r1, &r2)
            let y3 = Self.tick(c3, b[n - 3], &u1, &u2)
            b[n] = y0; b[n - 1] = y1; b[n - 2] = y2; b[n - 3] = y3
            n += 1
        }
        let last = frames - 1
        b[last] = Self.tick(c1, b[last], &q1, &q2); b[last - 1] = Self.tick(c2, b[last - 1], &r1, &r2); b[last - 2] = Self.tick(c3, b[last - 2], &u1, &u2)
        b[last] = Self.tick(c2, b[last], &r1, &r2); b[last - 1] = Self.tick(c3, b[last - 1], &u1, &u2)
        b[last] = Self.tick(c3, b[last], &u1, &u2)

        z1[i0] = p1; z2[i0] = p2; z1[i1] = q1; z2[i1] = q2
        z1[i2] = r1; z2[i2] = r2; z1[i3] = u1; z2[i3] = u2
    }

    // MARK: Parameter changes

    private static func transparent(poles c: EQBiquad) -> EQBiquad {
        EQBiquad(b0: 1, b1: c.a1, b2: c.a2, a1: c.a1, a2: c.a2)
    }

    private func pickUpPendingDesign() {
        guard os_unfair_lock_trylock(lock) else { return }
        guard pendingVersion != appliedVersion else { os_unfair_lock_unlock(lock); return }
        appliedVersion = pendingVersion
        for i in 0..<Self.capacity { target[i] = pending[i] }
        preampTarget = pendingPreamp
        os_unfair_lock_unlock(lock)

        for i in 0..<Self.capacity {
            if target[i].isIdentity {
                retiring[i] = enabled[i]
                if enabled[i] { target[i] = Self.transparent(poles: current[i]) }
            } else {
                retiring[i] = false
                if !enabled[i] {
                    current[i] = Self.transparent(poles: target[i])
                    z1[i] = .zero; z2[i] = .zero
                    enabled[i] = true
                }
            }
        }
        rebuildActiveList()
        rampRemaining = Self.rampSteps
    }

    private func advanceRamp() {
        let fraction = 1 / Double(rampRemaining)
        for j in 0..<activeCount {
            let i = activeList[j]
            var c = current[i]
            let t = target[i]
            c.b0 += (t.b0 - c.b0) * fraction
            c.b1 += (t.b1 - c.b1) * fraction
            c.b2 += (t.b2 - c.b2) * fraction
            c.a1 += (t.a1 - c.a1) * fraction
            c.a2 += (t.a2 - c.a2) * fraction
            current[i] = c
        }
        preamp += (preampTarget - preamp) * fraction
        rampRemaining -= 1
        guard rampRemaining == 0 else { return }

        preamp = preampTarget
        for i in 0..<Self.capacity where enabled[i] { current[i] = target[i] }
    }

    private func rebuildActiveList() {
        activeCount = 0
        for i in 0..<Self.capacity where enabled[i] {
            activeList[activeCount] = i
            activeCount += 1
        }
    }
}