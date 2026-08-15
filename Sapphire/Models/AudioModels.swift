//
//  AudioModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import Foundation

enum EQPreset: String, CaseIterable, Identifiable {
    case flat, bassBoost, trebleBoost, vocalBoost, acoustic, rock, custom
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .flat: "Flat"
        case .bassBoost: "Bass Booster"
        case .trebleBoost: "Treble Booster"
        case .vocalBoost: "Vocal Booster"
        case .acoustic: "Acoustic"
        case .rock: "Rock"
        case .custom: "Custom"
        }
    }

    var gainValues: [Double] {
        switch self {
        case .flat:         [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:    [6, 5, 4, 2, 1, 0, 0, 0, 0, 0]
        case .trebleBoost:  [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .vocalBoost:   [0, 0, 0, 1, 2, 3, 3, 2, 1, 0]
        case .acoustic:     [4, 3, 2, 1, 2, 3, 4, 3, 2, 1]
        case .rock:         [5, 4, 2, -1, -2, -1, 2, 4, 5, 4]
        case .custom:       [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}