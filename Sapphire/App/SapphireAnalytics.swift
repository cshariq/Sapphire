//
//  SapphireAnalytics.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import FirebaseAnalytics
import FirebaseCrashlytics

@MainActor
enum SapphireAnalytics {
    static var isEnabled: Bool {
        SettingsModel.shared.current.googleAnalyticsEnabled
    }

    private static var isBootstrapped = false
    private static var bootstrapWork: DispatchWorkItem?
    private static var pendingWork: [@MainActor () -> Void] = []
    private static let maximumPendingWork = 32

    static func scheduleBootstrap(after delay: TimeInterval) {
        guard !isBootstrapped else { return }
        bootstrapWork?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { bootstrap() } }
        bootstrapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static func bootstrap() {
        bootstrapWork?.cancel()
        bootstrapWork = nil
        guard !isBootstrapped else { return }
        isBootstrapped = true
        applyCollectionPreference()
        let queued = pendingWork
        pendingWork.removeAll()
        queued.forEach { $0() }
    }

    static func whenReady(_ work: @escaping @MainActor () -> Void) {
        if isBootstrapped {
            work()
        } else if pendingWork.count < maximumPendingWork {
            pendingWork.append(work)
        }
    }

    static func applyCollectionPreference() {
        guard isBootstrapped else { return }
        if isEnabled {
            FirebaseBootstrap.configureIfNeeded()
        }
        SapphirePerformance.setCollectionEnabled(isEnabled)
        guard FirebaseBootstrap.isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(isEnabled)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }
        guard isBootstrapped else {
            let parameterCopy = parameters
            whenReady { logEvent(name, parameters: parameterCopy) }
            return
        }
        if !FirebaseBootstrap.isConfigured {
            applyCollectionPreference()
        }
        Analytics.logEvent(name, parameters: parameters)
    }
}