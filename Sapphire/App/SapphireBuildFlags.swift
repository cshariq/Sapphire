//
//  SapphireBuildFlags.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation

enum SapphireBuildFlags {
    static var forceOnboarding: Bool {
        #if SAPPHIRE_FORCE_ONBOARDING
        return true
        #else
        return false
        #endif
    }
}

enum OnboardingLaunchPolicy {
    static var shouldShowOnboarding: Bool {
        if SapphireBuildFlags.forceOnboarding {
            return true
        }
        if UserDefaults.standard.bool(forKey: "forceOnboarding") {
            return true
        }
        return !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
}