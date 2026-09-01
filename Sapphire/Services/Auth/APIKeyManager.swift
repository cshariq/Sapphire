//
//  APIKeyManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import Security

extension Notification.Name {
    static let apiKeyManagerSpotifyCredentialsChanged = Notification.Name("apiKeyManagerSpotifyCredentialsChanged")
}

final class APIKeyManager {
    static let shared = APIKeyManager()

    private let keychain = KeychainHelper.standard
    private let legacyMigrationDefaultsKey = "apiKeysMigratedFromUserDefaults_v1"

    private let geminiKeychainKey = "gemini_api_key"
    private let hackClubKeychainKey = "hackclub_api_key"
    private let openAIKeychainKey = "openai_api_key"
    private let anthropicKeychainKey = "anthropic_api_key"
    private let openRouterKeychainKey = "openrouter_api_key"
    private let xaiKeychainKey = "xai_api_key"
    private let nvidiaKeychainKey = "nvidia_api_key"
    private let spotifyClientIdKeychainKey = "spotify_client_id"
    private let spotifyClientSecretKeychainKey = "spotify_client_secret"
    private let shopifyStoreDomainKeychainKey = "shopify_store_domain"
    private let shopifyAdminTokenKeychainKey = "shopify_admin_token"

    private init() {
        migrateLegacyUserDefaultsKeysIfNeeded()
        migrateMisplacedProviderKeysIfNeeded()
    }

    private func migrateMisplacedProviderKeysIfNeeded() {
        let gemini = loadKey(keychainKey: geminiKeychainKey) ?? ""
        guard !gemini.isEmpty else { return }

        if gemini.hasPrefix("sk-hc-") {
            let hackClub = loadKey(keychainKey: hackClubKeychainKey) ?? ""
            if hackClub.isEmpty {
                saveKey(gemini, keychainKey: hackClubKeychainKey)
            }
            keychain.delete(forKey: geminiKeychainKey)
            return
        }

        if gemini.hasPrefix("sk-or-") {
            let openRouter = loadKey(keychainKey: openRouterKeychainKey) ?? ""
            if openRouter.isEmpty {
                saveKey(gemini, keychainKey: openRouterKeychainKey)
            }
            keychain.delete(forKey: geminiKeychainKey)
        }
    }

    static func isValidGoogleGeminiAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("AIza") { return true }
        let thirdPartyPrefixes = ["sk-hc-", "sk-or-", "sk-ant-", "sk-proj-", "sk-"]
        return !thirdPartyPrefixes.contains(where: { trimmed.hasPrefix($0) })
    }

    var googleGeminiAPIKey: String {
        let key = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidGoogleGeminiAPIKey(key) else { return "" }
        return key
    }

    private func migrateLegacyUserDefaultsKeysIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: legacyMigrationDefaultsKey) else { return }

        let defaults = UserDefaults.standard
        let migrations: [(keychainKey: String, userDefaultsKeys: [String])] = [
            (geminiKeychainKey, ["geminiAPIKey", "intelligenceApiKey", "geminiApiKey"]),
            (hackClubKeychainKey, ["hackClubAPIKey"]),
            (openAIKeychainKey, ["openAIAPIKey"]),
            (anthropicKeychainKey, ["anthropicAPIKey"]),
            (openRouterKeychainKey, ["openRouterAPIKey"]),
            (xaiKeychainKey, ["xaiAPIKey"]),
            (nvidiaKeychainKey, ["nvidiaAPIKey"]),
            (spotifyClientIdKeychainKey, ["spotifyClientId"]),
            (spotifyClientSecretKeychainKey, ["spotifyClientSecret"]),
        ]

        for migration in migrations {
            guard keychain.load(forKey: migration.keychainKey) == nil else { continue }
            for userDefaultsKey in migration.userDefaultsKeys {
                guard let existing = defaults.string(forKey: userDefaultsKey), !existing.isEmpty else { continue }
                keychain.save(existing, forKey: migration.keychainKey)
                break
            }
        }

        for migration in migrations {
            for userDefaultsKey in migration.userDefaultsKeys {
                defaults.removeObject(forKey: userDefaultsKey)
            }
        }

        defaults.set(true, forKey: legacyMigrationDefaultsKey)
    }

    // MARK: - Gemini API Key
    var geminiAPIKey: String {
        get { loadKey(keychainKey: geminiKeychainKey) }
        set { saveKey(newValue, keychainKey: geminiKeychainKey) }
    }

    // MARK: - Hack Club API Key
    var hackClubAPIKey: String {
        get { loadKey(keychainKey: hackClubKeychainKey) }
        set { saveKey(newValue, keychainKey: hackClubKeychainKey) }
    }

    // MARK: - OpenAI
    var openAIAPIKey: String {
        get { loadKey(keychainKey: openAIKeychainKey) }
        set { saveKey(newValue, keychainKey: openAIKeychainKey) }
    }

    // MARK: - Anthropic
    var anthropicAPIKey: String {
        get { loadKey(keychainKey: anthropicKeychainKey) }
        set { saveKey(newValue, keychainKey: anthropicKeychainKey) }
    }

    // MARK: - OpenRouter
    var openRouterAPIKey: String {
        get { loadKey(keychainKey: openRouterKeychainKey) }
        set { saveKey(newValue, keychainKey: openRouterKeychainKey) }
    }

    // MARK: - xAI
    var xaiAPIKey: String {
        get { loadKey(keychainKey: xaiKeychainKey) }
        set { saveKey(newValue, keychainKey: xaiKeychainKey) }
    }

    // MARK: - NVIDIA NIM
    var nvidiaAPIKey: String {
        get { loadKey(keychainKey: nvidiaKeychainKey) }
        set { saveKey(newValue, keychainKey: nvidiaKeychainKey) }
    }

    // MARK: - Shopify
    var shopifyStoreDomain: String {
        get { loadKey(keychainKey: shopifyStoreDomainKeychainKey) }
        set { saveKey(newValue, keychainKey: shopifyStoreDomainKeychainKey) }
    }

    var shopifyAdminToken: String {
        get { loadKey(keychainKey: shopifyAdminTokenKeychainKey) }
        set { saveKey(newValue, keychainKey: shopifyAdminTokenKeychainKey) }
    }

    // MARK: - Spotify
    var spotifyClientId: String {
        get { loadKey(keychainKey: spotifyClientIdKeychainKey) }
        set { saveKey(newValue, keychainKey: spotifyClientIdKeychainKey) }
    }

    var spotifyClientSecret: String {
        get { loadKey(keychainKey: spotifyClientSecretKeychainKey) }
        set { saveKey(newValue, keychainKey: spotifyClientSecretKeychainKey) }
    }

    private func loadKey(keychainKey: String) -> String {
        keychain.load(forKey: keychainKey) ?? ""
    }

    private func saveKey(_ newValue: String, keychainKey: String) {
        if newValue.isEmpty {
            keychain.delete(forKey: keychainKey)
        } else {
            keychain.save(newValue, forKey: keychainKey)
        }

        if keychainKey == spotifyClientIdKeychainKey || keychainKey == spotifyClientSecretKeychainKey {
            NotificationCenter.default.post(name: .apiKeyManagerSpotifyCredentialsChanged, object: nil)
        }
    }

    var hasGeminiKey: Bool { !googleGeminiAPIKey.isEmpty }
    var hasHackClubKey: Bool { !hackClubAPIKey.isEmpty }
    var hasOpenAIKey: Bool { !openAIAPIKey.isEmpty }
    var hasAnthropicKey: Bool { !anthropicAPIKey.isEmpty }
    var hasOpenRouterKey: Bool { !openRouterAPIKey.isEmpty }
    var hasXAIKey: Bool { !xaiAPIKey.isEmpty }
    var hasSpotifyCredentials: Bool { !spotifyClientId.isEmpty && !spotifyClientSecret.isEmpty }
}