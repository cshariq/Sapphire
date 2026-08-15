//
//  KeychainHelper.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-15.
//

import Foundation
import Security

class KeychainHelper {
    static let standard = KeychainHelper()
    private let service: String

    private init() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            self.service = bundleIdentifier
        } else {
            self.service = "com.shariq.sapphire"
        }
    }

    func save(_ value: String, forKey account: String) {
        guard let data = value.data(using: .utf8) else { return }

        delete(forKey: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func load(forKey account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == noErr, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        } else {
            return nil
        }
    }

    func delete(forKey account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}