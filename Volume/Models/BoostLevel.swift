//
//  BoostLevel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

enum BoostLevel: Float, CaseIterable, Codable {
    case x1 = 1.0
    case x2 = 2.0
    case x3 = 3.0
    case x4 = 4.0

    var label: String {
        switch self {
        case .x1: "1x"
        case .x2: "2x"
        case .x3: "3x"
        case .x4: "4x"
        }
    }

    var next: BoostLevel {
        switch self {
        case .x1: .x2
        case .x2: .x3
        case .x3: .x4
        case .x4: .x1
        }
    }

    var isBoosted: Bool { self != .x1 }
}