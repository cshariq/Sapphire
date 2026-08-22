//
//  EQSettings.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

struct EQSettings: Codable, Equatable {
    static let bandCount = 10
    static let maxGainDB: Float = 12.0
    static let minGainDB: Float = -12.0

    static let frequencies: [Double] = [
        31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    var bandGains: [Float]

    var isEnabled: Bool

    init(bandGains: [Float] = Array(repeating: 0, count: 10), isEnabled: Bool = true) {
        self.bandGains = Self.normalizeBands(bandGains)
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([Float].self, forKey: .bandGains)
            ?? Array(repeating: 0, count: Self.bandCount)
        self.bandGains = Self.normalizeBands(decoded)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    private static func normalizeBands(_ gains: [Float]) -> [Float] {
        if gains.count == bandCount { return gains }
        if gains.count > bandCount { return Array(gains.prefix(bandCount)) }
        return gains + Array(repeating: Float(0), count: bandCount - gains.count)
    }

    var clampedGains: [Float] {
        bandGains.map { $0.isFinite ? max(Self.minGainDB, min(Self.maxGainDB, $0)) : 0 }
    }

    static let flat = EQSettings()
}