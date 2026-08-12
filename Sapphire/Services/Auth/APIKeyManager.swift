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
    private let defaults = UserDefaults.standard

    private let geminiKeychainKey = "gemini_api_key"
    private let geminiUserDefaultsKeys = ["geminiAPIKey", "intelligenceApiKey"]

    private let hackClubKeychainKey = "hackclub_api_key"
    private let hackClubUserDefaultsKey = "hackClubAPIKey"

    private let openAIKeychainKey = "openai_api_key"
    private let openAIUserDefaultsKey = "openAIAPIKey"

    private let anthropicKeychainKey = "anthropic_api_key"
    private let anthropicUserDefaultsKey = "anthropicAPIKey"

    private let openRouterKeychainKey = "openrouter_api_key"
    private let openRouterUserDefaultsKey = "openRouterAPIKey"

    private let xaiKeychainKey = "xai_api_key"
    private let xaiUserDefaultsKey = "xaiAPIKey"

    private let nvidiaKeychainKey = "nvidia_api_key"
    private let nvidiaUserDefaultsKey = "nvidiaAPIKey"

    private let spotifyClientIdKeychainKey = "spotify_client_id"
    private let spotifyClientIdUserDefaultsKey = "spotifyClientId"

    private let spotifyClientSecretKeychainKey = "spotify_client_secret"
    private let spotifyClientSecretUserDefaultsKey = "spotifyClientSecret"

    private init() {
        migrateExistingKeys()
    }

    private func migrateExistingKeys() {
        if keychain.load(forKey: geminiKeychainKey) == nil {
            for udKey in geminiUserDefaultsKeys {
                if let existing = defaults.string(forKey: udKey), !existing.isEmpty {
                    keychain.save(existing, forKey: geminiKeychainKey)
                    break
                }
            }
        }
        for udKey in geminiUserDefaultsKeys {
            defaults.removeObject(forKey: udKey)
        }
        migrateIfNeeded(keychainKey: hackClubKeychainKey, defaultsKey: hackClubUserDefaultsKey)
        migrateIfNeeded(keychainKey: openAIKeychainKey, defaultsKey: openAIUserDefaultsKey)
        migrateIfNeeded(keychainKey: anthropicKeychainKey, defaultsKey: anthropicUserDefaultsKey)
        migrateIfNeeded(keychainKey: openRouterKeychainKey, defaultsKey: openRouterUserDefaultsKey)
        migrateIfNeeded(keychainKey: xaiKeychainKey, defaultsKey: xaiUserDefaultsKey)
        migrateIfNeeded(keychainKey: nvidiaKeychainKey, defaultsKey: nvidiaUserDefaultsKey)
        migrateIfNeeded(keychainKey: spotifyClientIdKeychainKey, defaultsKey: spotifyClientIdUserDefaultsKey)
        migrateIfNeeded(keychainKey: spotifyClientSecretKeychainKey, defaultsKey: spotifyClientSecretUserDefaultsKey)
    }

    private func migrateIfNeeded(keychainKey: String, defaultsKey: String) {
        if keychain.load(forKey: keychainKey) == nil,
           let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            keychain.save(existing, forKey: keychainKey)
        }
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - Gemini API Key
    var geminiAPIKey: String {
        get { loadKey(keychainKey: geminiKeychainKey, defaultsKeys: geminiUserDefaultsKeys) }
        set { saveKey(newValue, keychainKey: geminiKeychainKey, defaultsKeys: geminiUserDefaultsKeys) }
    }

    // MARK: - Hack Club API Key
    var hackClubAPIKey: String {
        get { loadKey(keychainKey: hackClubKeychainKey, defaultsKeys: [hackClubUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: hackClubKeychainKey, defaultsKeys: [hackClubUserDefaultsKey]) }
    }

    // MARK: - OpenAI
    var openAIAPIKey: String {
        get { loadKey(keychainKey: openAIKeychainKey, defaultsKeys: [openAIUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: openAIKeychainKey, defaultsKeys: [openAIUserDefaultsKey]) }
    }

    // MARK: - Anthropic
    var anthropicAPIKey: String {
        get { loadKey(keychainKey: anthropicKeychainKey, defaultsKeys: [anthropicUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: anthropicKeychainKey, defaultsKeys: [anthropicUserDefaultsKey]) }
    }

    // MARK: - OpenRouter
    var openRouterAPIKey: String {
        get { loadKey(keychainKey: openRouterKeychainKey, defaultsKeys: [openRouterUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: openRouterKeychainKey, defaultsKeys: [openRouterUserDefaultsKey]) }
    }

    // MARK: - xAI
    var xaiAPIKey: String {
        get { loadKey(keychainKey: xaiKeychainKey, defaultsKeys: [xaiUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: xaiKeychainKey, defaultsKeys: [xaiUserDefaultsKey]) }
    }

    // MARK: - NVIDIA NIM
    var nvidiaAPIKey: String {
        get { loadKey(keychainKey: nvidiaKeychainKey, defaultsKeys: [nvidiaUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: nvidiaKeychainKey, defaultsKeys: [nvidiaUserDefaultsKey]) }
    }

    // MARK: - Spotify
    var spotifyClientId: String {
        get { loadKey(keychainKey: spotifyClientIdKeychainKey, defaultsKeys: [spotifyClientIdUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: spotifyClientIdKeychainKey, defaultsKeys: [spotifyClientIdUserDefaultsKey]) }
    }

    var spotifyClientSecret: String {
        get { loadKey(keychainKey: spotifyClientSecretKeychainKey, defaultsKeys: [spotifyClientSecretUserDefaultsKey]) }
        set { saveKey(newValue, keychainKey: spotifyClientSecretKeychainKey, defaultsKeys: [spotifyClientSecretUserDefaultsKey]) }
    }

    private func loadKey(keychainKey: String, defaultsKeys: [String]) -> String {
        if let keychainKey = keychain.load(forKey: keychainKey) {
            return keychainKey
        }
        return ""
    }

    private func saveKey(_ newValue: String, keychainKey: String, defaultsKeys: [String]) {
        if newValue.isEmpty {
            keychain.delete(forKey: keychainKey)
        } else {
            keychain.save(newValue, forKey: keychainKey)
        }
        if keychainKey == spotifyClientIdKeychainKey || keychainKey == spotifyClientSecretKeychainKey {
            NotificationCenter.default.post(name: .apiKeyManagerSpotifyCredentialsChanged, object: nil)
        }
    }

    var hasGeminiKey: Bool { !geminiAPIKey.isEmpty }
    var hasHackClubKey: Bool { !hackClubAPIKey.isEmpty }
    var hasOpenAIKey: Bool { !openAIAPIKey.isEmpty }
    var hasAnthropicKey: Bool { !anthropicAPIKey.isEmpty }
    var hasOpenRouterKey: Bool { !openRouterAPIKey.isEmpty }
    var hasXAIKey: Bool { !xaiAPIKey.isEmpty }
    var hasSpotifyCredentials: Bool { !spotifyClientId.isEmpty && !spotifyClientSecret.isEmpty }
}