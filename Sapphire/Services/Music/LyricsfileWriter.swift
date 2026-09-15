//
//  LyricsfileWriter.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import Foundation

enum LyricsfileWriter {
    static func document(title: String, artist: String, album: String?, lines: [LyricLine]) -> String {
        var out = ["version: '1.0'", "metadata:", "  title: \(quote(title))", "  artist: \(quote(artist))"]
        if let album, !album.isEmpty { out.append("  album: \(quote(album))") }
        out.append("  instrumental: false")

        guard !lines.isEmpty else {
            out.append("lines: []")
            return out.joined(separator: "\n") + "\n"
        }

        out.append("lines:")
        for line in lines {
            let start = milliseconds(line.timestamp)
            out.append("  - text: \(quote(line.text))")
            out.append("    start_ms: \(start)")
            if let end = line.endTimestamp { out.append("    end_ms: \(max(start, milliseconds(end)))") }
            guard !line.words.isEmpty else { continue }
            out.append("    words:")
            for word in line.words {
                let wordStart = milliseconds(word.timestamp)
                out.append("      - text: \(quote(word.text))")
                out.append("        start_ms: \(wordStart)")
                if let end = word.endTimestamp { out.append("        end_ms: \(max(wordStart, milliseconds(end)))") }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func quote(_ value: String) -> String {
        let singleLine = value.unicodeScalars.map { scalar -> String in
            if CharacterSet.newlines.contains(scalar) { return " " }
            if CharacterSet.controlCharacters.contains(scalar) { return "" }
            return String(scalar)
        }.joined()
        return "'" + singleLine.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite else { return 0 }
        return max(0, Int((seconds * 1000).rounded()))
    }
}