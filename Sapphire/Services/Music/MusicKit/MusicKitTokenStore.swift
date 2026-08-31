//
//  MusicKitTokenStore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-31
//

import Foundation
import MusicKit
import Security

enum MusicKitTokenStore {

    // MARK: - Config file

    private static var configPlistURL: URL? {
        guard let home = FileManager.default.homeDirectoryForCurrentUser as URL? else { return nil }
        return home.appendingPathComponent(".sapphire/MusicKitConfig.plist")
    }

    private static func configValue(forKey key: String) -> String? {
        guard let url = configPlistURL,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Developer token

    static var developerToken: String {
        if let env = ProcessInfo.processInfo.environment["MUSICKIT_DEVELOPER_TOKEN"],
           !env.isEmpty {
            return env
        }
        if let config = configValue(forKey: "DeveloperToken") {
            return config
        }
        return WeatherAPIKey.musicKitDeveloperToken
    }

    static var hasDeveloperToken: Bool {
        !developerToken.isEmpty
    }

    static var developerTokenExpiry: Date? {
        let parts = developerToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static var userTokenSource: String {
        if let env = ProcessInfo.processInfo.environment["MUSICKIT_USER_TOKEN"], !env.isEmpty {
            return "environment"
        }
        if configValue(forKey: "UserToken") != nil {
            return "~/.sapphire/MusicKitConfig.plist"
        }
        if storedUserToken != nil {
            return "keychain"
        }
        return "none (falls back to MusicKit entitlement)"
    }

    // MARK: - User token

    private static let userTokenKeychainService = "com.cshariq.sapphire"
    private static let userTokenKeychainAccount = "musicKitUserToken"

    static var storedUserToken: String? {
        KeychainHelper.standard.load(forKey: userTokenKeychainAccount)
    }

    static func saveUserToken(_ token: String) {
        guard !token.isEmpty else { return }
        KeychainHelper.standard.save(token, forKey: userTokenKeychainAccount)
    }

    static func clearUserToken() {
        KeychainHelper.standard.delete(forKey: userTokenKeychainAccount)
    }

    static var userTokenOverride: String? {
        if let env = ProcessInfo.processInfo.environment["MUSICKIT_USER_TOKEN"],
           !env.isEmpty {
            return env
        }
        if let config = configValue(forKey: "UserToken") {
            return config
        }
        return storedUserToken
    }

    static func userToken(developerToken: String) async throws -> String {
        if let override = userTokenOverride {
            return override
        }

        guard hasUserTokenEntitlement else {
            print("[AppleMusic] No user token configured and no com.apple.developer.music.user-token entitlement — personalized features unavailable. Set MUSICKIT_USER_TOKEN or ~/.sapphire/MusicKitConfig.plist → UserToken.")
            return ""
        }

        let token = try await DefaultMusicTokenProvider().userToken(for: developerToken, options: [])
        if !token.isEmpty {
            saveUserToken(token)
        }
        return token
    }

    static var hasUserTokenEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.music.user-token" as CFString,
            nil
        ) else { return false }
        return (value as? Bool) ?? false
    }

    static var canObtainUserToken: Bool {
        userTokenOverride != nil || hasUserTokenEntitlement
    }
}