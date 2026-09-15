//
//  LyricsDatabaseKeys.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import CryptoKit
import Foundation

enum LyricsDatabaseKeys {
    private static let featuring = try! NSRegularExpression(
        pattern: #"\s*[(\[](?:feat|ft|featuring)\.?\s[^)\]]*[)\]]"#
    )
    private static let versionSuffix = try! NSRegularExpression(
        pattern: #"\s+-\s+(?:[0-9]{4}\s+)?(?:remaster(?:ed)?|live|radio edit|single version|explicit)(?![A-Za-z0-9_]).*$"#
    )
    private static let nonAlphanumeric = try! NSRegularExpression(pattern: #"[^\p{L}\p{N}]+"#)
    private static let artistSeparator = try! NSRegularExpression(
        pattern: #"\s*(?:,|&|\s(?:feat|ft)\.?\s|\sfeaturing\s)\s*"#,
        options: [.caseInsensitive]
    )

    static func normalize(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.decomposedStringWithCompatibilityMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                scalars.append(scalar)
            }
        }
        var text = String(scalars).lowercased()
        text = replacing(featuring, in: text, with: "")
        text = replacing(versionSuffix, in: text, with: "")
        text = replacing(nonAlphanumeric, in: text, with: " ")
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func primaryArtist(_ artist: String) -> String {
        let range = NSRange(artist.startIndex..., in: artist)
        guard let match = artistSeparator.firstMatch(in: artist, range: range),
              let matchRange = Range(match.range, in: artist) else {
            return artist
        }
        return String(artist[..<matchRange.lowerBound])
    }

    static func metadataKey(title: String, artist: String) -> String? {
        let normalizedTitle = normalize(title)
        let normalizedArtist = normalize(primaryArtist(artist))
        guard !normalizedTitle.isEmpty, !normalizedArtist.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data("\(normalizedTitle)|\(normalizedArtist)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "meta:" + hex.prefix(32)
    }

    static func spotifyKey(_ id: String) -> String { "spotify:\(id)" }
    static func appleMusicKey(_ id: String) -> String { "am:\(id)" }
    static func isrcKey(_ code: String) -> String { "isrc:\(code.uppercased())" }

    private static func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}