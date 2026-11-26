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

    /// Cuts and boosts sit in separate banks so adaptive headroom can shrink just the boosts.
    /// `preamp` is the static pre-cut of the fixed modes; `headroomFloor` < 1 switches the adaptive
    /// follower on and bounds how far it may turn the level down.
    struct Design: Equatable {
        var cutSections: [EQBiquad]
        var boostSections: [EQBiquad]
        var preamp: Double
        var headroomFloor: Double
        var sampleRate: Double
        var isFlat: Bool { preamp == 1 && cutSections.allSatisfy(\.isIdentity) && boostSections.allSatisfy(\.isIdentity) }

        static let flat: Design = {
            let bank = Array(repeating: EQBiquad.identity, count: GraphicEQDesigner.sectionCount)
            return Design(cutSections: bank, boostSections: bank, preamp: 1, headroomFloor: 1, sampleRate: 48000)
        }()
    }

    struct Plan {
        var biquads: [EQBiquad]
        var bandGainsDB: [Double]
        var peakBoostDB: Double
    }

    /// `trimDB` is a pre-cut shared across a device (Raise Output Volume): the design cuts by whichever
    /// is larger, its own peak boost or the trim, so every app on the device sits at the same level.
    static func design(gains: [Double], bass: Double, sampleRate: Double, headroom: EQHeadroomMode = .fixed, trimDB: Double = 0) -> Design {
        let plan = plan(gains: gains, bass: bass, sampleRate: sampleRate)
        var cuts = Array(repeating: EQBiquad.identity, count: sectionCount), boosts = cuts
        for (index, biquad) in plan.biquads.enumerated() where !biquad.isIdentity {
            let gain = index < AudioEQ.bandCount ? plan.bandGainsDB[index] : bass
            if gain > 0 { boosts[index] = biquad } else { cuts[index] = biquad }
        }
        let rate = max(sampleRate, 8000)
        if headroom == .adaptive {
            let floor = plan.peakBoostDB > 0 ? pow(10, -(plan.peakBoostDB + 1) / 20) : 1
            return Design(cutSections: cuts, boostSections: boosts, preamp: 1, headroomFloor: floor, sampleRate: rate)
        }
        let cutDB = max(plan.peakBoostDB, trimDB)
        let preamp = cutDB > 0.05 ? pow(10, -cutDB / 20) : 1
        return Design(cutSections: cuts, boostSections: boosts, preamp: preamp, headroomFloor: 1, sampleRate: rate)
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
        return Plan(biquads: biquads, bandGainsDB: bandGains, peakBoostDB: peak > 0.05 ? peak : 0)
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
    // Slots [0, bankSize) hold cuts, [bankSize, capacity) boosts; a band that changes sign glides
    // out of one slot and into the other.
    static let bankSize = GraphicEQDesigner.sectionCount
    static let capacity = 2 * bankSize
    static let rampStepFrames = 32
    static let rampSteps = 48
    static let blockFrames = 512

    // Headroom follower: just under the output limiter's 0.97 so it rarely has to act.
    static let headroomCeiling = 0.944
    static let headroomChunkFrames = 32
    static let headroomHoldSeconds = 1.0
    static let headroomReleaseDBPerSecond = 2.0
    static let headroomRecoverDBPerSecond = 40.0
    // Boosts shrink toward the cut-only signal before the level is touched, but keep at least this share.
    static let minimumBoostDepth = 0.25
    static let boostDepthReleasePerSecond = 0.25
    static let boostDepthRecoverPerSecond = 20.0

    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private let pending: UnsafeMutablePointer<EQBiquad>
    private var pendingPreamp = 1.0
    private var pendingFloor = 1.0
    private var pendingSampleRate = 48000.0
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
    private let dry: UnsafeMutablePointer<SIMD2<Double>>
    private var activeCount = 0
    private var activeCutCount = 0
    private var rampRemaining = 0
    private var preamp = 1.0
    private var preampTarget = 1.0

    private var headroomFloor = 1.0
    private var headroomGain = 1.0
    private var headroomHoldFrames = 0
    private var headroomHoldRemaining = 0
    private var releaseLogPerFrame = 0.0
    private var recoverLogPerFrame = 0.0
    private var boostDepth = 1.0
    private var depthHoldRemaining = 0
    private var depthReleasePerFrame = 0.0
    private var depthRecoverPerFrame = 0.0

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
        dry = .allocate(capacity: Self.blockFrames); dry.initialize(repeating: .zero, count: Self.blockFrames)
    }

    deinit {
        lock.deinitialize(count: 1); lock.deallocate()
        pending.deallocate(); current.deallocate(); target.deallocate()
        z1.deallocate(); z2.deallocate(); enabled.deallocate(); retiring.deallocate()
        activeList.deallocate(); block.deallocate(); dry.deallocate()
    }

    func post(_ design: GraphicEQDesigner.Design) {
        os_unfair_lock_lock(lock)
        for i in 0..<Self.bankSize {
            pending[i] = i < design.cutSections.count ? design.cutSections[i] : .identity
            pending[Self.bankSize + i] = i < design.boostSections.count ? design.boostSections[i] : .identity
        }
        pendingPreamp = design.preamp
        pendingFloor = design.headroomFloor
        pendingSampleRate = design.sampleRate
        pendingVersion &+= 1
        os_unfair_lock_unlock(lock)
    }

    var isTransparent: Bool {
        activeCount == 0 && rampRemaining == 0 && preamp == 1 && headroomGain == 1 && boostDepth == 1
    }

    var activeSectionCount: Int { activeCount }

    /// Level the headroom follower is applying right now (1 = none).
    var currentHeadroomGain: Double { headroomGain }

    /// Share of the boosts currently applied (1 = full curve).
    var currentBoostDepth: Double { boostDepth }

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

            let managesHeadroom = headroomFloor < 1 || headroomGain < 1 || boostDepth < 1
            runSections(from: 0, to: activeCutCount, frames: frames)
            if managesHeadroom { dry.update(from: block, count: frames) }
            runSections(from: activeCutCount, to: activeCount, frames: frames)
            if managesHeadroom { followHeadroom(frames: frames) }

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

    @_optimize(speed)
    private func runSections(from first: Int, to end: Int, frames: Int) {
        var j = first
        if frames >= 4 {
            while j + 4 <= end {
                runFour(activeList[j], activeList[j + 1], activeList[j + 2], activeList[j + 3], frames: frames)
                j += 4
            }
        }
        while j < end {
            runOne(activeList[j], frames: frames)
            j += 1
        }
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

    /// Keeps boosted peaks under full scale without turning the track down: the boosts shrink first
    /// (mixing back toward the cut-only signal in `dry`), and only once they're at their minimum depth does
    /// the level drop. Both act per chunk with a ramped attack, a one-second hold and a slow release so they
    /// sit still instead of pumping with the beat, and neither pushes below what the cut-only signal peaks at.
    @_optimize(speed)
    private func followHeadroom(frames: Int) {
        let block = self.block, dry = self.dry, ceiling = Self.headroomCeiling
        var start = 0
        while start < frames {
            let end = min(start + Self.headroomChunkFrames, frames)
            let count = Double(end - start)

            var depthLimit = 1.0
            for n in start..<end {
                let x = dry[n], w = block[n]
                for c in 0..<2 {
                    let bound = max(ceiling, abs(x[c]))
                    guard abs(w[c]) > bound else { continue }
                    let boost = w[c] - x[c]
                    depthLimit = min(depthLimit, (bound - (boost > 0 ? x[c] : -x[c])) / abs(boost))
                }
            }

            let depth = boostDepth
            var nextDepth: Double
            if depth > depthLimit {
                nextDepth = max(depthLimit, Self.minimumBoostDepth)
                depthHoldRemaining = headroomHoldFrames
            } else if headroomFloor >= 1 {
                nextDepth = min(depth + depthRecoverPerFrame * count, 1, depthLimit)
            } else if depthHoldRemaining > 0 {
                depthHoldRemaining -= end - start
                nextDepth = depth
            } else if headroomGain < 1 {
                nextDepth = depth
            } else {
                nextDepth = min(depth + depthReleasePerFrame * count, 1, depthLimit)
            }
            if nextDepth > 0.99999 { nextDepth = 1 }

            if depth != 1 || nextDepth != 1 {
                let step = (nextDepth - depth) / count
                var a = depth
                for n in start..<end { a += step; block[n] = dry[n] + (block[n] - dry[n]) * a }
            }
            boostDepth = nextDepth

            var gainLimit = Double.infinity
            for n in start..<end {
                let x = dry[n], y = block[n]
                for c in 0..<2 where abs(y[c]) > ceiling {
                    gainLimit = min(gainLimit, max(ceiling, abs(x[c])) / abs(y[c]))
                }
            }

            let gain = headroomGain
            var next: Double
            if gain > gainLimit, nextDepth <= Self.minimumBoostDepth {
                next = max(gainLimit, headroomFloor)
                headroomHoldRemaining = headroomHoldFrames
            } else if gain < headroomFloor {
                next = min(gain * exp(recoverLogPerFrame * count), headroomFloor, max(gainLimit, gain))
            } else if headroomHoldRemaining > 0 {
                headroomHoldRemaining -= end - start
                next = gain
            } else {
                next = min(gain * exp(releaseLogPerFrame * count), 1, max(gainLimit, gain))
            }
            if next > 0.99999 { next = 1 }

            if gain != 1 || next != 1 {
                let step = (next - gain) / count
                var g = gain
                for n in start..<end { g += step; block[n] *= g }
            }
            headroomGain = next
            start = end
        }
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
        headroomFloor = pendingFloor
        let rate = pendingSampleRate
        os_unfair_lock_unlock(lock)

        headroomHoldFrames = Int(rate * Self.headroomHoldSeconds)
        releaseLogPerFrame = Self.headroomReleaseDBPerSecond / 20 * log(10) / rate
        recoverLogPerFrame = Self.headroomRecoverDBPerSecond / 20 * log(10) / rate
        depthReleasePerFrame = Self.boostDepthReleasePerSecond / rate
        depthRecoverPerFrame = Self.boostDepthRecoverPerSecond / rate

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
        activeCutCount = 0
        for i in 0..<Self.capacity where enabled[i] {
            activeList[activeCount] = i
            activeCount += 1
            if i < Self.bankSize { activeCutCount = activeCount }
        }
    }
}