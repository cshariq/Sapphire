//
//  TotpGenerator.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import CryptoKit
import CommonCrypto

func hmacSHA1(key: Data, message: Data) -> Data {
    var result = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
    result.withUnsafeMutableBytes { resultBytes in
        key.withUnsafeBytes { keyBytes in
            message.withUnsafeBytes { messageBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       keyBytes.baseAddress, key.count,
                       messageBytes.baseAddress, message.count,
                       resultBytes.baseAddress)
            }
        }
    }
    return result
}

class TotpGenerator {
    private static var secretCache: (version: Int, secretBytes: Data)?
    private static var cacheExpiry: Date?
    private static let cacheTTL: TimeInterval = 15 * 60

    private static let fallbackSecrets: [Int: Data] = [
        18: Data([70, 60, 33, 57, 92, 120, 90, 33, 32, 62, 62, 55, 126, 93, 66, 35, 108, 68]),
        12: Data([107, 81, 49, 57, 67, 93, 87, 81, 69, 67, 40, 93, 48, 50, 46, 91, 94, 113, 41, 108, 77, 107, 34]),
        11: Data([111, 45, 40, 73, 95, 74, 35, 85, 105, 107, 60, 110, 55, 72, 69, 70, 114, 83, 63, 88, 91]),
        10: Data([61, 110, 58, 98, 35, 79, 117, 69, 102, 72, 92, 102, 69, 93, 41, 101, 42, 75]),
    ]

    private static func getLatestFallbackSecret() -> (version: Int, secretBytes: Data) {
        guard let latestVersion = fallbackSecrets.keys.max(),
              let secretData = fallbackSecrets[latestVersion] else {
            fatalError("Fallback TOTP secrets dictionary is empty.")
        }
        return (latestVersion, secretData)
    }

    static func getLatestTotpSecret() async -> (version: Int, secretBytes: Data) {
        if let cache = secretCache, let expiry = cacheExpiry, Date() < expiry {
            return cache
        }

        do {
            let url = URL(string: "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json")!
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                print("[TotpGenerator] Failed to fetch secrets from GitHub, using fallback.")
                return getLatestFallbackSecret()
            }

            guard let secretsDict = try JSONSerialization.jsonObject(with: data) as? [String: [Int]] else {
                 print("[TotpGenerator] Failed to decode secrets JSON, using fallback.")
                 return getLatestFallbackSecret()
            }

            guard let latestVersionString = secretsDict.keys.max(),
                  let latestVersion = Int(latestVersionString),
                  let secretList = secretsDict[latestVersionString] else {
                print("[TotpGenerator] Failed to find latest secret version in fetched JSON, using fallback.")
                return getLatestFallbackSecret()
            }

            let secretData = Data(secretList.compactMap { UInt8(exactly: $0) })
            secretCache = (latestVersion, secretData)
            cacheExpiry = Date().addingTimeInterval(cacheTTL)
            print("[TotpGenerator] Successfully fetched and cached secret version: \(latestVersion)")
            return (latestVersion, secretData)

        } catch {
            print("[TotpGenerator] Network error fetching secrets: \(error.localizedDescription). Using fallback.")
            return getLatestFallbackSecret()
        }
    }

    static func generateTotp() async -> (totp: String, version: Int) {
        let (version, secretBytes) = await getLatestTotpSecret()

        var transformedBytes: [UInt8] = []
        for (index, byte) in secretBytes.enumerated() {
            transformedBytes.append(byte ^ UInt8((index % 33) + 9))
        }

        let joinedString = transformedBytes.map { String($0) }.joined()

        guard let joinedData = joinedString.data(using: .utf8) else {
            print("[TotpGenerator] Error: Could not convert joined string to data.")
            return ("", 0)
        }

        let hexString = joinedData.map { String(format: "%02x", $0) }.joined()

        guard let keyData = Data(hex: hexString) else {
            print("[TotpGenerator] Error: Could not convert hex string to Data for TOTP key.")
            return ("", 0)
        }

        let base32Secret = base32Encode(data: keyData).replacingOccurrences(of: "=", with: "")
        let totpCode = calculateTOTP(secret: base32Secret, timeInterval: 30, digits: 6)

        return (totpCode, version)
    }

    private static func base32Encode(data: Data) -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var result = ""
        var bits = 0
        var byteBuffer: UInt64 = 0

        for byte in data {
            byteBuffer = (byteBuffer << 8) | UInt64(byte)
            bits += 8

            while bits >= 5 {
                let index = Int((byteBuffer >> (bits - 5)) & 0x1F)
                result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
                bits -= 5
            }
        }

        if bits > 0 {
            let index = Int((byteBuffer << (5 - bits)) & 0x1F)
            result.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
        }

        let paddingNeeded = result.count % 8
        if paddingNeeded != 0 {
            result.append(String(repeating: "=", count: 8 - paddingNeeded))
        }

        return result
    }

    private static func base32Decode(base32String: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let base32Mapping = alphabet.enumerated().reduce(into: [Character: UInt8]()) { map, entry in
            map[entry.element] = UInt8(entry.offset)
        }

        var result = Data()
        var bits = 0
        var byteBuffer: UInt32 = 0

        let strippedString = base32String.replacingOccurrences(of: "=", with: "").uppercased()

        for char in strippedString {
            guard let value = base32Mapping[char] else { return nil }
            byteBuffer = (byteBuffer << 5) | UInt32(value)
            bits += 5

            if bits >= 8 {
                let byte = UInt8((byteBuffer >> (bits - 8)) & 0xFF)
                result.append(byte)
                bits -= 8
            }
        }
        return result
    }

    private static func calculateTOTP(secret: String, timeInterval: TimeInterval, digits: Int) -> String {
        guard let keyData = base32Decode(base32String: secret) else {
            return ""
        }

        let currentUnixTime = Date().timeIntervalSince1970
        let counter = UInt64(floor(currentUnixTime / timeInterval))

        var counterData = Data(count: 8)
        var bigEndianCounter = counter.bigEndian
        counterData.withUnsafeMutableBytes {
            $0.copyBytes(from: withUnsafeBytes(of: &bigEndianCounter) { $0 })
        }

        let authenticationCode = hmacSHA1(key: keyData, message: counterData)
        let hash = Data(authenticationCode)

        let offset = Int(hash.last! & 0x0F)
        let truncatedHash = hash[offset..<(offset + 4)]

        var code: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &code) {
            truncatedHash.copyBytes(to: $0)
        }

        code = UInt32(bigEndian: code) & 0x7FFFFFFF

        let otp = code % UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }
}

extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            let bytes = hex[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}