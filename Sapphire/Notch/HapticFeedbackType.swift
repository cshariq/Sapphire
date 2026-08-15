//
//  HapticFeedbackType.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-19

import Foundation

public enum HapticFeedbackType {
    case veryWeak
    case weak
    case medium
    case strong

    var actuationID: Int32 {
        switch self {
        case .veryWeak, .weak:
            return 1
        case .medium:
            return 15
        case .strong:
            return 5
        }
    }

    var intensity: Float {
        switch self {
        case .veryWeak:
            return 0.15
        case .weak:
            return 0.3
        case .medium:
            return 0.75
        case .strong:
            return 1.0
        }
    }
}

public final class HapticManager {

    public static let shared = HapticManager()

    private init() {}

    public func perform(_ type: HapticFeedbackType) {
        HTKMultitouchActuator.shared().actuateActuationID(
            type.actuationID,
            intensity: type.intensity
        )
    }
}