//
//  TrustedWatchStore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-11-23
//

import Combine
import CoreBluetooth
import CryptoKit
import Foundation

struct TrustedWatch: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var keyBase64: String
    var addedAt: Date
}

/// Watch state carried in each advertisement and covered by its token.
struct TrustedWatchFlags: OptionSet, Equatable {
    let rawValue: UInt8
    static let onWrist = TrustedWatchFlags(rawValue: 1 << 0)
    static let unlocked = TrustedWatchFlags(rawValue: 1 << 1)
}

@MainActor
final class TrustedWatchStore: ObservableObject {
    static let shared = TrustedWatchStore()

    static let serviceUUID = CBUUID(string: "5A9F0001-6E3B-4C2D-9A71-3B8E2F4D1C70")
    private nonisolated static let protocolVersion: UInt8 = 1
    private nonisolated static let tokenLength = 8
    private nonisolated static let tokenPeriod: TimeInterval = 30
    private static let account = "SapphireTrustedWatches"

    @Published private(set) var watches: [TrustedWatch] = []

    private init() { load() }

    func register(id: String, name: String, keyBase64: String) {
        guard UUID(uuidString: id) != nil,
              let key = Data(base64Encoded: keyBase64), key.count >= 32 else { return }
        let watch = TrustedWatch(id: id, name: name, keyBase64: keyBase64, addedAt: Date())
        if let index = watches.firstIndex(where: { $0.id == id }) {
            watches[index] = watch
        } else {
            watches.append(watch)
        }
        persist()
    }

    func remove(id: String) {
        watches.removeAll { $0.id == id }
        persist()
    }

    func watch(id: String) -> TrustedWatch? { watches.first { $0.id == id } }

    /// Service data layout: version (1) | flags (1) | token (8), where the token is the first 8 bytes of
    /// HMAC-SHA256(key, 30-second counter as big-endian UInt64 || flags). Returns the flags when the token verifies.
    nonisolated static func verify(serviceData: Data, keyBase64: String, now: Date = Date()) -> TrustedWatchFlags? {
        let bytes = [UInt8](serviceData)
        guard bytes.count == 2 + tokenLength, bytes[0] == protocolVersion,
              let keyData = Data(base64Encoded: keyBase64) else { return nil }
        let flags = bytes[1]
        let token = Data(bytes[2...])
        let key = SymmetricKey(data: keyData)
        let counter = Int64(now.timeIntervalSince1970 / tokenPeriod)
        for candidate in [counter, counter - 1, counter + 1] {
            var message = Data()
            withUnsafeBytes(of: UInt64(candidate).bigEndian) { message.append(contentsOf: $0) }
            message.append(flags)
            let mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: key)).prefix(tokenLength)
            if mac == token { return TrustedWatchFlags(rawValue: flags) }
        }
        return nil
    }

    private func load() {
        guard let encrypted = KeychainManager.shared.load(for: Self.account),
              let data = CryptoManager.shared.decrypt(data: encrypted),
              let decoded = try? JSONDecoder().decode([TrustedWatch].self, from: data) else { return }
        watches = decoded
    }

    private func persist() {
        if watches.isEmpty {
            _ = KeychainManager.shared.delete(for: Self.account)
            return
        }
        guard let data = try? JSONEncoder().encode(watches),
              let encrypted = CryptoManager.shared.encrypt(data: data) else { return }
        _ = KeychainManager.shared.save(key: encrypted, for: Self.account)
    }
}
