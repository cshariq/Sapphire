//
//  FirebaseBootstrap.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import FirebaseAppCheck
import FirebaseCore

@MainActor
enum FirebaseBootstrap {
    private(set) static var isConfigured = false

    static func configureIfNeeded() {
        guard !isConfigured else { return }
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif
        FirebaseApp.configure()
        isConfigured = true
    }
}