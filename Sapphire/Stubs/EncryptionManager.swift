//
//  EncryptionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation
import CryptoKit

final class EncryptionManager {
    static let shared = EncryptionManager()

    private let key: SymmetricKey

    private init() {
        let tag = "com.cshariq.sapphire.stub-encryption-key"
        if let stored = UserDefaults.standard.data(forKey: tag) {
            key = SymmetricKey(data: stored)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            UserDefaults.standard.set(newKey.withUnsafeBytes { Data($0) }, forKey: tag)
            key = newKey
        }
    }

    func encrypt(_ data: Data) throws -> Data {
        try AES.GCM.seal(data, using: key).combined!
    }

    func decrypt(_ data: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
    }
}
#endif