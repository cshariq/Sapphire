//
//  DebugMode.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-20.
//

import SwiftUI

final class DebugMode: ObservableObject {
    static let shared = DebugMode()

    static let requiredTapCount = 5

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
        }
    }

    @Published var systemEnhanceLogging: Bool {
        didSet {
            UserDefaults.standard.set(systemEnhanceLogging, forKey: Self.seLoggingKey)
        }
    }

    private static let storageKey = "SapphireDebugModeEnabled"
    private static let seLoggingKey = "SapphireSystemEnhanceLogging"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.storageKey)
        systemEnhanceLogging = UserDefaults.standard.bool(forKey: Self.seLoggingKey)
    }
}