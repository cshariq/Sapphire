//
//  CryptoManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-26
//

import Foundation
import CryptoKit

final class CryptoManager: @unchecked Sendable {
    static let shared = CryptoManager()
    private let keyAccount = "SapphireEncryptionMasterKey"
    private let fallbackKeyAccount = "SapphireEncryptionMasterKey.fallback"
    private let keyLock = NSLock()
    private var cachedKey: SymmetricKey?

    private init() {}

    private func getEncryptionKey() -> SymmetricKey? {
        keyLock.lock()
        defer { keyLock.unlock() }

        if let cachedKey { return cachedKey }

        if let keyData = KeychainManager.shared.load(for: keyAccount) {
            let key = SymmetricKey(data: keyData)
            cachedKey = key
            return key
        }
        if let keyData = KeychainManager.shared.load(for: fallbackKeyAccount) {
            let key = SymmetricKey(data: keyData)
            cachedKey = key
            return key
        }

        let newKey = SymmetricKey(size: .bits256)
        let newKeyData = newKey.withUnsafeBytes { Data($0) }

        guard KeychainManager.shared.save(key: newKeyData, for: keyAccount)
                || KeychainManager.shared.save(key: newKeyData, for: fallbackKeyAccount) else {
            print("[CryptoManager] Failed to persist a new encryption key.")
            return nil
        }
        cachedKey = newKey
        return newKey
    }

    func encrypt(data: Data) -> Data? {
        guard let key = getEncryptionKey() else {
            print(" Encryption failed: No encryption key available")
            return nil
        }

        do {
            let sealedBox = try ChaChaPoly.seal(data, using: key)
            return sealedBox.combined
        } catch {
            print(" Encryption failed: \(error)")
            return nil
        }
    }

    func decrypt(data: Data) -> Data? {
        guard let key = getEncryptionKey() else {
            print(" Decryption failed: No encryption key available")
            return nil
        }

        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: data)
            let decryptedData = try ChaChaPoly.open(sealedBox, using: key)
            return decryptedData
        } catch let error as CryptoKit.CryptoKitError {
            switch error {
            case .authenticationFailure:
                print(" Decryption failed: authenticationFailure - Key doesn't match the encrypted data")
            default:
                print(" Decryption failed: \(error)")
            }
            return nil
        } catch {
            print(" Decryption failed: \(error)")
            return nil
        }
    }

    func deleteKey() {
        keyLock.lock()
        defer { keyLock.unlock() }
        cachedKey = nil
        _ = KeychainManager.shared.delete(for: keyAccount)
        _ = KeychainManager.shared.delete(for: fallbackKeyAccount)
        print(" Encryption key deleted from Keychain.")
    }
}