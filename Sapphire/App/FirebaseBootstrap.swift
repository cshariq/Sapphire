//
//  FirebaseBootstrap.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore
import os.log

private let firebaseBootstrapLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Sapphire",
    category: "FirebaseBootstrap"
)

@MainActor
enum FirebaseBootstrap {
    private(set) static var isConfigured = false
    private(set) static var isFirestoreAvailable = false
    private static var isolatedFirestoreAppName: String?

    static func configureIfNeeded() {
        guard !isConfigured else { return }
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif

        var configureError: NSError?
        let configured = SapphireTryObjC({
            FirebaseApp.configure()
        }, &configureError)
        isConfigured = configured
        if !configured {
            firebaseBootstrapLog.error(
                "FirebaseApp.configure failed: \(configureError?.localizedDescription ?? "unknown", privacy: .public)"
            )
            isFirestoreAvailable = false
            return
        }

        prepareFirestore()
    }

    static func firestoreDatabase() -> Firestore? {
        configureIfNeeded()
        guard isConfigured, isFirestoreAvailable else { return nil }
        if let name = isolatedFirestoreAppName, let app = FirebaseApp.app(name: name) {
            return Firestore.firestore(app: app)
        }
        return Firestore.firestore()
    }

    private static func prepareFirestore() {
        let isolate = SapphireInstanceCoordination.shouldIsolateFirestorePersistence()
        var openError: NSError?
        var prepareFailed: String?
        let opened = SapphireTryObjC({
            if isolate {
                let name = "sapphire-isolated-\(ProcessInfo.processInfo.processIdentifier)"
                guard let options = FirebaseApp.app()?.options else {
                    prepareFailed = "Firebase default app is missing"
                    return
                }
                if FirebaseApp.app(name: name) == nil {
                    FirebaseApp.configure(name: name, options: options)
                }
                guard let app = FirebaseApp.app(name: name) else {
                    prepareFailed = "Isolated Firebase app is missing"
                    return
                }
                isolatedFirestoreAppName = name
                let database = Firestore.firestore(app: app)
                let settings = FirestoreSettings()
                settings.cacheSettings = MemoryCacheSettings()
                database.settings = settings
            } else {
                isolatedFirestoreAppName = nil
                _ = Firestore.firestore()
            }
        }, &openError)

        isFirestoreAvailable = opened && prepareFailed == nil
        if isFirestoreAvailable {
            if isolate {
                firebaseBootstrapLog.info("Firestore using isolated in-memory cache (pid \(ProcessInfo.processInfo.processIdentifier))")
            }
        } else {
            let message = prepareFailed ?? openError?.localizedDescription ?? "unknown"
            firebaseBootstrapLog.error("Firestore unavailable: \(message, privacy: .public)")
        }
    }
}