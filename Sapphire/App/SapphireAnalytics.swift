//
//  SapphireAnalytics.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

@MainActor
enum SapphireAnalytics {
    private static var isConfigured = false

    static var isEnabled: Bool {
        SettingsModel.shared.settings.googleAnalyticsEnabled
    }

    static func bootstrap() {
        guard isEnabled else { return }
        applyCollectionPreference()
    }

    static func applyCollectionPreference() {
        if isEnabled {
            configureIfNeeded()
        }
        guard isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(isEnabled)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }

        if !isConfigured {
            bootstrap()
        }
        Analytics.logEvent(name, parameters: parameters)
    }

    private static func configureIfNeeded() {
        guard !isConfigured else { return }
        FirebaseApp.configure()
        isConfigured = true
    }
}