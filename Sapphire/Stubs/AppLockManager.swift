//
//  AppLockManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var failedAttempts: [AppLockFailedAttempt] = []

    private init() {}

    func refresh() {}
    func authenticateAndUnlock() async -> Bool { false }
    func authenticateAndUnlock(bundleID: String, method: AppLockAuthMethod = .auto) async -> Bool { false }
    func authenticateSettingsAccess(method: AppLockAuthMethod = .auto) async -> Bool { false }
    func verifyPassword(_ password: String, for bundleID: String) -> Bool { false }
    func clearFailedAttempts() { failedAttempts.removeAll() }

    var hasPasswordFallback: Bool { false }
}

enum AppLockAuthMethod {
    case auto
    case faceID
    case touchID
}

struct AppLockFailedAttempt: Codable, Identifiable {
    let id: UUID
    let bundleID: String
    let appName: String
    let timestamp: Date
    let method: String
}
#endif