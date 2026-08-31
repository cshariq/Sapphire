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

    private let service = "com.shariq.Sapphire.faceid.keychain"

    func save(key: Data, for account: String) -> Bool {
        delete(for: account)

        let status = KeychainStore.addItem(
            service: service,
            account: account,
            data: key,
            accessible: kSecAttrAccessibleAfterFirstUnlock,
            synchronizable: false
        )

        if status != errSecSuccess {
            print("[KeychainManager] failed to save key: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")")
            return false
        }

        return true
    }

    func load(for account: String) -> Data? {
        let (data, status) = KeychainStore.copyData(
            service: service,
            account: account,
            accessible: kSecAttrAccessibleAfterFirstUnlock,
            synchronizable: false
        )

        if data == nil {
            print("[KeychainManager] failed to load key for \(account): \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")")
            return nil
        }

        return data
    }

    func delete(for account: String) -> Bool {
        let status = KeychainStore.deleteItem(
            service: service,
            account: account,
            accessible: kSecAttrAccessibleAfterFirstUnlock,
            synchronizable: false
        )
        let success = (status == errSecSuccess || status == errSecItemNotFound)

        if success {
            print("[KeychainManager] successfully deleted key for \(account)")
        } else {
            print("[KeychainManager] failed to delete key for \(account): \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")")
        }

        return success
    }
}