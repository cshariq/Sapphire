//
//  FanCurvePolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import Foundation

enum FanCurvePolicy {
    struct State: Equatable {
        var smoothedTemperature: Double?
        var appliedRPM: Int?
        var appliedAtTemperature: Double?
    }

    static let smoothing = 0.4
    static let coolingHysteresis = 2.0

    static func rpmDeadband(minRPM: Int, maxRPM: Int) -> Int {
        max(100, (maxRPM - minRPM) / 20)
    }

    static func interpolatedRPM(points: [FanCurvePoint], temperature: Double) -> Int? {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard let first = sorted.first, let last = sorted.last, sorted.count >= 2 else { return nil }
        if temperature <= Double(first.temperature) { return first.rpm }
        if temperature >= Double(last.temperature) { return last.rpm }
        for index in 0..<(sorted.count - 1) {
            let lower = sorted[index]
            let upper = sorted[index + 1]
            let lowerTemp = Double(lower.temperature)
            let upperTemp = Double(upper.temperature)
            guard temperature >= lowerTemp, temperature <= upperTemp else { continue }
            let span = upperTemp - lowerTemp
            guard span > 0 else { return upper.rpm }
            let progress = (temperature - lowerTemp) / span
            return lower.rpm + Int((progress * Double(upper.rpm - lower.rpm)).rounded())
        }
        return last.rpm
    }

    static func nextTarget(
        state: inout State,
        temperature: Double,
        points: [FanCurvePoint],
        minRPM: Int,
        maxRPM: Int
    ) -> Int? {
        guard temperature.isFinite else { return nil }
        let smoothed: Double
        if let previous = state.smoothedTemperature {
            smoothed = previous + smoothing * (temperature - previous)
        } else {
            smoothed = temperature
        }
        state.smoothedTemperature = smoothed

        guard let curveRPM = interpolatedRPM(points: points, temperature: smoothed) else { return nil }
        let upperBound = max(minRPM, maxRPM)
        let desired = min(upperBound, max(minRPM, curveRPM))

        guard let applied = state.appliedRPM else {
            return commit(desired, at: smoothed, into: &state)
        }
        if desired == applied { return nil }

        let deadband = rpmDeadband(minRPM: minRPM, maxRPM: upperBound)
        let reachesLimit = desired == upperBound || desired == minRPM

        if desired > applied {
            guard desired - applied >= deadband || reachesLimit else { return nil }
            return commit(desired, at: smoothed, into: &state)
        }

        let reference = state.appliedAtTemperature ?? smoothed
        guard smoothed <= reference - coolingHysteresis else { return nil }
        guard applied - desired >= deadband || reachesLimit else { return nil }
        return commit(desired, at: smoothed, into: &state)
    }

    private static func commit(_ rpm: Int, at temperature: Double, into state: inout State) -> Int {
        state.appliedRPM = rpm
        state.appliedAtTemperature = temperature
        return rpm
    }
}