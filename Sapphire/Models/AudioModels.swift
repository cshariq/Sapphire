//
//  AudioModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import Foundation

enum AudioEQ {
    static let bandCount = 31
    static let displayedBandCountDefaultsKey = "SapphireEQDisplayedBandCount"

    static let frequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200,
        250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000,
        2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    static let gainRange: ClosedRange<Double> = -15...15

    static let bassRange: ClosedRange<Double> = -12...12

    static let bassShelfFrequency: Double = 105

    static var flat: [Double] { Array(repeating: 0.0, count: bandCount) }

    static func label(for frequency: Double) -> String {
        if frequency >= 1000 {
            let k = frequency / 1000
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        return frequency == frequency.rounded() ? "\(Int(frequency))" : String(format: "%.0f", frequency)
    }

    static let labelledBandIndices: [Int] = {
        var indices = stride(from: 0, to: bandCount, by: 4).map { $0 }
        if indices.last != bandCount - 1 { indices.append(bandCount - 1) }
        return indices
    }()

    static func normalize(_ gains: [Double]) -> [Double] {
        if gains.count == bandCount { return gains }
        guard gains.count > 1 else { return flat }
        return (0..<bandCount).map { index in
            let position = Double(index) / Double(bandCount - 1) * Double(gains.count - 1)
            let lower = Int(position.rounded(.down))
            let upper = Swift.min(lower + 1, gains.count - 1)
            let fraction = position - Double(lower)
            return gains[lower] * (1 - fraction) + gains[upper] * fraction
        }
    }

    static func displayedGains(from gains: [Double], layout: AudioEQBandLayout) -> [Double] {
        let normalized = normalize(gains)
        return layout.canonicalIndices.map { normalized[$0] }
    }

    static func canonicalGains(from displayedGains: [Double], layout: AudioEQBandLayout) -> [Double] {
        guard displayedGains.count == layout.canonicalIndices.count else {
            return normalize(displayedGains)
        }
        guard layout != .thirtyOne else { return normalize(displayedGains) }

        return (0..<bandCount).map { canonicalIndex in
            guard let upperPosition = layout.canonicalIndices.firstIndex(where: { $0 >= canonicalIndex }) else {
                return displayedGains.last ?? 0
            }
            let upperIndex = layout.canonicalIndices[upperPosition]
            guard upperPosition > 0, upperIndex != canonicalIndex else {
                return displayedGains[upperPosition]
            }

            let lowerPosition = upperPosition - 1
            let lowerIndex = layout.canonicalIndices[lowerPosition]
            let fraction = Double(canonicalIndex - lowerIndex) / Double(upperIndex - lowerIndex)
            return displayedGains[lowerPosition] * (1 - fraction) + displayedGains[upperPosition] * fraction
        }
    }
}

/// How the EQ makes room for its boosts so they can't clip.
enum EQHeadroomMode: String, CaseIterable, Identifiable {
    /// A fixed pre-cut equal to the curve's biggest boost. Never moves, so the level never rides.
    case fixed
    /// The same fixed pre-cut, shared by every app on the device, with the device's own output volume
    /// raised by that amount so the track plays as loud as it did without the EQ.
    case raiseOutputVolume
    /// No pre-cut; boosts shrink (and only then the level drops) when a peak would pass full scale.
    case adaptive

    static let defaultsKey = "SapphireEQHeadroomMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixed: String(localized: "Steady Level")
        case .raiseOutputVolume: String(localized: "Raise Output Volume")
        case .adaptive: String(localized: "Adaptive")
        }
    }

    var detail: String {
        switch self {
        case .fixed: String(localized: "Turns the EQ'd audio down by its biggest boost. Quieter, but the level never moves.")
        case .raiseOutputVolume: String(localized: "Turns the audio down by the biggest boost and raises the device volume by the same amount, so it stays as loud. The system volume will read higher.")
        case .adaptive: String(localized: "Plays boosts at full strength and only eases them back on loud peaks. Loudest, but the level can move.")
        }
    }

    static var current: EQHeadroomMode {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(EQHeadroomMode.init(rawValue:)) ?? .fixed
    }
}

enum AudioEQBandLayout: Int, CaseIterable, Identifiable {
    case ten = 10
    case fifteen = 15
    case thirtyOne = 31

    var id: Int { rawValue }
    var displayName: String { "\(rawValue) Bands" }

    var canonicalIndices: [Int] {
        switch self {
        case .ten:
            return [2, 5, 8, 11, 14, 17, 20, 23, 26, 29]
        case .fifteen:
            return Array(stride(from: 1, through: 29, by: 2))
        case .thirtyOne:
            return Array(0..<AudioEQ.bandCount)
        }
    }

    var frequencies: [Double] {
        canonicalIndices.map { AudioEQ.frequencies[$0] }
    }

    static func resolved(from rawValue: Int) -> AudioEQBandLayout {
        AudioEQBandLayout(rawValue: rawValue) ?? .thirtyOne
    }
}

enum EQPreset: String, CaseIterable, Identifiable {
    case flat, bassBoost, trebleBoost, vocalBoost, acoustic, rock, electronic, hipHop, podcast, loudness, custom
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .flat: String(localized: "Flat")
        case .bassBoost: String(localized: "Bass Booster")
        case .trebleBoost: String(localized: "Treble Booster")
        case .vocalBoost: String(localized: "Vocal Booster")
        case .acoustic: String(localized: "Acoustic")
        case .rock: String(localized: "Rock")
        case .electronic: String(localized: "Electronic")
        case .hipHop: String(localized: "Hip-Hop")
        case .podcast: String(localized: "Podcast")
        case .loudness: String(localized: "Loudness")
        case .custom: String(localized: "Custom")
        }
    }

    var gainValues: [Double] {
        switch self {
        case .flat:
            return AudioEQ.flat
        case .bassBoost:
            return [7, 7, 6.5, 6, 5.5, 5, 4.5, 4, 3.25, 2.5, 1.75, 1, 0.5, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .trebleBoost:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0.5, 1, 1.75, 2.5, 3.25, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7]
        case .vocalBoost:
            return [-2, -2, -2, -1.75, -1.5, -1.25, -1, -0.5, 0, 0, 0.5, 1, 1.5, 2, 2.5,
                    3, 3.5, 3.75, 3.75, 3.5, 3, 2.5, 2, 1.25, 0.5, 0, -0.5, -1, -1.5, -1.5, -1.5]
        case .acoustic:
            return [3.5, 3.5, 3.25, 3, 2.5, 2, 1.5, 1.25, 1, 1, 1.25, 1.5, 1.75, 2, 2,
                    2.25, 2.5, 2.75, 2.75, 2.5, 2.25, 2.25, 2.5, 2.75, 3, 3, 2.75, 2.5, 2.75, 3.25, 3.5]
        case .rock:
            return [5, 5, 4.75, 4.25, 3.5, 2.5, 1.5, 0.5, -0.5, -1.25, -2, -2.25, -2, -1.5, -0.75,
                    0, 0.75, 1.5, 2, 2.5, 3, 3.25, 3.5, 3.75, 4, 4.25, 4.25, 4, 3.5, 3.25, 3.25]
        case .electronic:
            return [6, 6, 5.5, 5, 4.25, 3.25, 2, 1, 0, -0.5, -1, -1, -0.5, 0, 0.5,
                    1, 1.5, 2, 2.25, 2.5, 2.75, 3, 3.25, 3.5, 3.75, 4, 4.25, 4.5, 4.75, 5, 5]
        case .hipHop:
            return [7, 6.75, 6.25, 5.5, 4.5, 3.5, 2.5, 1.5, 0.75, 0.25, 0, -0.25, -0.25, 0, 0.25,
                    0.75, 1.25, 1.75, 2, 2, 1.75, 1.5, 1.25, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3]
        case .podcast:
            return [-6, -6, -5.5, -5, -4, -3, -2, -1, 0, 0.5, 1, 1.75, 2.5, 3, 3.25,
                    3.5, 3.5, 3.25, 3, 2.5, 2, 1.5, 1, 0.5, 0, -0.5, -1.5, -2.5, -3.5, -4, -4]
        case .loudness:
            return [6.5, 6.5, 6, 5.25, 4.25, 3, 1.75, 0.75, 0, -0.5, -0.75, -1, -1, -0.75, -0.5,
                    -0.25, 0, 0.25, 0.5, 1, 1.75, 2.5, 3.25, 4, 4.75, 5.25, 5.75, 6, 6.25, 6.5, 6.5]
        case .custom:
            return AudioEQ.flat
        }
    }
}