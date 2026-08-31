//
//  KeychainHelper.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-15.
//

import Foundation
import Security

enum KeychainStore {

    static func addItem(
        service: String,
        account: String,
        data: Data,
        accessible: CFString? = nil,
        synchronizable: Bool? = nil
    ) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        if let accessible { query[kSecAttrAccessible as String] = accessible }
        if let synchronizable { query[kSecAttrSynchronizable as String] = synchronizable }
        return SecItemAdd(query as CFDictionary, nil)
    }

    static func copyData(
        service: String,
        account: String,
        accessible: CFString? = nil,
        synchronizable: Bool? = nil
    ) -> (data: Data?, status: OSStatus) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessible { query[kSecAttrAccessible as String] = accessible }
        if let synchronizable { query[kSecAttrSynchronizable as String] = synchronizable }

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        return (status == noErr ? dataTypeRef as? Data : nil, status)
    }

    static func deleteItem(
        service: String,
        account: String,
        accessible: CFString? = nil,
        synchronizable: Bool? = nil
    ) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessible { query[kSecAttrAccessible as String] = accessible }
        if let synchronizable { query[kSecAttrSynchronizable as String] = synchronizable }
        return SecItemDelete(query as CFDictionary)
    }
}

class KeychainHelper {
    static let standard = KeychainHelper()
    private let service: String

    private init() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            self.service = bundleIdentifier
        } else {
            self.service = "com.cshariq.sapphire"
        }
    }

    func save(_ value: String, forKey account: String) {
        guard let data = value.data(using: .utf8) else { return }

        delete(forKey: account)

        KeychainStore.addItem(service: service, account: account, data: data)
    }

    func load(forKey account: String) -> String? {
        let (data, _) = KeychainStore.copyData(service: service, account: account)
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    func delete(forKey account: String) {
        KeychainStore.deleteItem(service: service, account: account)
    }
}