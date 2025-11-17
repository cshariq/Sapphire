//
//  CryptoManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-26
//

import Foundation
import CryptoKit

class CryptoManager {
    static let shared = CryptoManager()
    private let keyAccount = "SapphireEncryptionMasterKey"

    private init() {}

    private func getEncryptionKey() -> SymmetricKey? {
        if let keyData = KeychainManager.shared.load(for: keyAccount) {
            print(" Successfully loaded existing encryption key from keychain")
            return SymmetricKey(data: keyData)
        }

        print("️ No existing encryption key found in keychain, creating new key")

        let newKey = SymmetricKey(size: .bits256)
        let newKeyData = newKey.withUnsafeBytes { Data($0) }

        let saveSuccessful = KeychainManager.shared.save(key: newKeyData, for: keyAccount)
        if saveSuccessful {
            print(" New encryption key created and saved to Keychain.")
            return newKey
        } else {
            print(" CRITICAL: Failed to save new encryption key to Keychain.")

            let fallbackSaveSuccessful = KeychainManager.shared.save(key: newKeyData, for: keyAccount + ".fallback")
            if fallbackSaveSuccessful {
                print(" Fallback: New encryption key saved using alternate account name")
                return newKey
            }

            return nil
        }
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
        _ = KeychainManager.shared.delete(for: keyAccount)
        print(" Encryption key deleted from Keychain.")
    }
}