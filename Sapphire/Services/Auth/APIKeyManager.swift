import Foundation
import Security

final class APIKeyManager {
    static let shared = APIKeyManager()

    private let keychain = KeychainHelper.standard
    private let defaults = UserDefaults.standard

    private let geminiKeychainKey = "gemini_api_key"
    private let geminiUserDefaultsKeys = ["geminiAPIKey", "intelligenceApiKey"]

    private let hackClubKeychainKey = "hackclub_api_key"
    private let hackClubUserDefaultsKey = "hackClubAPIKey"

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
        if keychain.load(forKey: hackClubKeychainKey) == nil {
            if let existing = defaults.string(forKey: hackClubUserDefaultsKey), !existing.isEmpty {
                keychain.save(existing, forKey: hackClubKeychainKey)
            }
        }
    }

    // MARK: - Gemini API Key
    var geminiAPIKey: String {
        get {
            if let keychainKey = keychain.load(forKey: geminiKeychainKey) {
                return keychainKey
            }
            for udKey in geminiUserDefaultsKeys {
                if let existing = defaults.string(forKey: udKey), !existing.isEmpty {
                    keychain.save(existing, forKey: geminiKeychainKey)
                    return existing
                }
            }
            return ""
        }
        set {
            if newValue.isEmpty {
                keychain.delete(forKey: geminiKeychainKey)
            } else {
                keychain.save(newValue, forKey: geminiKeychainKey)
            }
            for udKey in geminiUserDefaultsKeys {
                defaults.set(newValue, forKey: udKey)
            }
        }
    }

    // MARK: - Hack Club API Key
    var hackClubAPIKey: String {
        get {
            if let keychainKey = keychain.load(forKey: hackClubKeychainKey) {
                return keychainKey
            }
            if let existing = defaults.string(forKey: hackClubUserDefaultsKey), !existing.isEmpty {
                keychain.save(existing, forKey: hackClubKeychainKey)
                return existing
            }
            return ""
        }
        set {
            if newValue.isEmpty {
                keychain.delete(forKey: hackClubKeychainKey)
            } else {
                keychain.save(newValue, forKey: hackClubKeychainKey)
            }
            defaults.set(newValue, forKey: hackClubUserDefaultsKey)
        }
    }

    var hasGeminiKey: Bool { !geminiAPIKey.isEmpty }
    var hasHackClubKey: Bool { !hackClubAPIKey.isEmpty }
}
