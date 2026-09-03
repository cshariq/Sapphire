//
//  SapphireAnalytics.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Firebase
import FirebaseAnalytics

enum SapphireAnalytics {
    private static let lock = NSLock()
    private static var isConfigured = false

    static var isEnabled: Bool {
        SettingsModel.shared.settings.googleAnalyticsEnabled
    }

    static func bootstrap() {
        lock.lock()
        defer { lock.unlock() }

        if !isConfigured {
            guard let options = FirebaseOptions.defaultOptions(), !(options.apiKey?.isEmpty ?? true) else {
                // The public repo ships a placeholder GoogleService-Info.plist (empty API key) since
                // the real one is a credential and is gitignored. FirebaseApp.configure() throws an
                // uncaught NSException on an invalid/placeholder config and takes the whole app down,
                // so skip Firebase entirely rather than crash every launch when no real config is present.
                print("[SapphireAnalytics] No valid Firebase configuration found — skipping Firebase initialization.")
                return
            }
            FirebaseApp.configure(options: options)
            isConfigured = true
        }
        applyCollectionPreference()
    }

    static func applyCollectionPreference() {
        guard isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }

        if !isConfigured {
            bootstrap()
        }
        Analytics.logEvent(name, parameters: parameters)
    }
}