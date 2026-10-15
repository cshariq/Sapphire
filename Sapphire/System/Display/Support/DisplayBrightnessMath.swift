//
//  DisplayBrightnessMath.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import CoreGraphics
import Foundation

enum BrightnessKeyStep: String, Codable, CaseIterable, Identifiable {
    case full
    case half
    case quarter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: "Full Step"
        case .half: "½ Step"
        case .quarter: "¼ Step"
        }
    }

    var multiplier: Float {
        switch self {
        case .full: 1
        case .half: 0.5
        case .quarter: 0.25
        }
    }

    func stepFraction(basePercent: Int) -> Float {
        let base = (Float(basePercent) / 100).clamped(to: 0.01...1)
        return (base * multiplier).clamped(to: 0.01...1)
    }
}

enum DisplayBrightnessMethod: String, Equatable {
    case native
    case ddc
    case software
    case probing

    var displayName: String {
        switch self {
        case .native: "Native"
        case .ddc: "DDC"
        case .software: "Software"
        case .probing: "Detecting…"
        }
    }
}

struct DisplayBrightnessSplit: Equatable {
    var hardware: Float?
    var gamma: Float
}

enum DisplayBrightnessMath {
    static let minimumGammaFactor: Float = 0.12

    static let extraDimmingShare: Float = 0.25

    static func split(level: Float, hardwareAvailable: Bool, extraDimming: Bool) -> DisplayBrightnessSplit {
        let level = level.clamped(to: 0...1)
        guard hardwareAvailable else {
            return DisplayBrightnessSplit(hardware: nil, gamma: gammaFactor(forSoftwareLevel: level))
        }
        guard extraDimming else {
            return DisplayBrightnessSplit(hardware: level, gamma: 1)
        }
        let share = extraDimmingShare
        if level >= share {
            return DisplayBrightnessSplit(hardware: (level - share) / (1 - share), gamma: 1)
        }
        return DisplayBrightnessSplit(hardware: 0, gamma: gammaFactor(forSoftwareLevel: level / share))
    }

    static func level(forHardware hardware: Float, currentLevel: Float, extraDimming: Bool) -> Float {
        let hardware = hardware.clamped(to: 0...1)
        guard extraDimming else { return hardware }
        let share = extraDimmingShare
        if hardware <= 0 {
            return min(currentLevel.clamped(to: 0...1), share)
        }
        return share + (1 - share) * hardware
    }

    static func gammaFactor(forSoftwareLevel level: Float) -> Float {
        minimumGammaFactor + (1 - minimumGammaFactor) * level.clamped(to: 0...1)
    }

    static func ddcValue(level: Float, minimum: Int, maximum: Int) -> UInt16 {
        let lower = max(0, minimum)
        let upper = min(Int(UInt16.max), maximum)
        guard upper > lower else { return UInt16(clamping: lower) }
        let value = Float(lower) + Float(upper - lower) * level.clamped(to: 0...1)
        return UInt16(clamping: Int(value.rounded()))
    }

    static func nextLevel(from current: Float, step: Float, isUp: Bool, isFine: Bool) -> Float {
        let direction: Float = isUp ? 1 : -1
        if isFine {
            return (current + 0.01 * direction).clamped(to: 0...1)
        }
        return SEStepMath.next(from: current, step: step, direction: direction)
    }

    static func scaled(_ table: [CGGammaValue], by factor: Float) -> [CGGammaValue] {
        table.map { $0 * factor }
    }

    static func tablesMatch(_ current: [CGGammaValue], _ expected: [CGGammaValue], tolerance: Float = 0.005) -> Bool {
        guard !current.isEmpty, current.count == expected.count else { return false }
        for index in current.indices {
            let lhs = min(1, max(0, current[index]))
            let rhs = min(1, max(0, expected[index]))
            if abs(lhs - rhs) > tolerance { return false }
        }
        return true
    }
}

struct LatestValueMailbox<Value> {
    private(set) var pending: Value?
    private(set) var isDraining = false

    mutating func post(_ value: Value) -> Bool {
        pending = value
        guard !isDraining else { return false }
        isDraining = true
        return true
    }

    mutating func take() -> Value? {
        guard let value = pending else {
            isDraining = false
            return nil
        }
        pending = nil
        return value
    }
}

enum DDCPacing {
    static func delay(sinceLastWrite elapsed: TimeInterval?, minimumInterval: TimeInterval) -> TimeInterval {
        guard let elapsed else { return 0 }
        return max(0, minimumInterval - elapsed)
    }
}