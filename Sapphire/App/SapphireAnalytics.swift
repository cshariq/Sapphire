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
    private static var configurationAttempted = false

    static var isEnabled: Bool {
        SettingsModel.shared.settings.googleAnalyticsEnabled
    }

    /// Real Firebase plists include a non-empty `API_KEY`. Our stub does not.
    private static var hasValidFirebaseOptions: Bool {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = NSDictionary(contentsOfFile: path),
              let apiKey = options["API_KEY"] as? String else {
            return false
        }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func bootstrap() {
        lock.lock()
        defer { lock.unlock() }

        if !configurationAttempted {
            configurationAttempted = true
            if hasValidFirebaseOptions {
                FirebaseApp.configure()
                isConfigured = true
            } else {
                print("[SapphireAnalytics] Skipping Firebase — GoogleService-Info.plist has no API_KEY (stub build).")
            }
        }
        applyCollectionPreference()
    }

    static func applyCollectionPreference() {
        guard isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isEnabled, isConfigured else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}