//
//  SapphireBuildFlags.swift
//  Sapphire
//

import Foundation

enum SapphireBuildFlags {
    /// `true` when compiled with `-DSAPPHIRE_FORCE_ONBOARDING`.
    ///
    /// To force onboarding on every launch:
    ///   Xcode → Target → Build Settings → Other Swift Flags → add `-DSAPPHIRE_FORCE_ONBOARDING`
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
