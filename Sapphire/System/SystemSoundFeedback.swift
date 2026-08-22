//
//  SystemSoundFeedback.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-17.
//

import Foundation

enum SystemSoundFeedback {
    private static let feedbackKey = "com.apple.sound.beep.feedback" as CFString

    static var isVolumeChangeFeedbackEnabled: Bool {
        get {
            guard let value = CFPreferencesCopyValue(
                feedbackKey,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? NSNumber else {
                return false
            }
            return value.boolValue
        }
        set {
            CFPreferencesSetValue(
                feedbackKey,
                newValue as CFBoolean,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            CFPreferencesSynchronize(
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
    }
}