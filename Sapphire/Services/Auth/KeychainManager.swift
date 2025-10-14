//
//  KeychainManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-07
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    private let service = "com.cshariq.Sapphire.faceid.keychain"

    func save(key: Data, for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: false
        ]

        delete(for: account)

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            print("[KeychainManager] failed to save key: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")")
            return false
        }

        return true
    }

    func load(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: false
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            return dataTypeRef as? Data
        } else {
            print("[KeychainManager] failed to load key for \(account): \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")")
            return nil
        }
    }

    func delete(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: false
        ]

        let status = SecItemDelete(query as CFDictionary)
        let success = (status == errSecSuccess || status == errSecItemNotFound)

        if success {
            print("[KeychainManager] successfully deleted key for \(account)")
        } else {
            print("[KeychainManager] failed to delete key for \(account): \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")")
        }

        return success
    }
}