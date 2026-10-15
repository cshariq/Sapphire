//
//  AppleMusicLyricsProvider.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-13

import Foundation
import MusicKit

@MainActor
final class AppleMusicLyricsProvider {
    static let shared = AppleMusicLyricsProvider()

    private var cache = BoundedLRUCache<String, [LyricLine]?>(capacity: 48)
    private var storefront: String?
    private var deniedByApple = false

    private init() {}

    var isAvailable: Bool { !deniedByApple && MusicAuthorization.currentStatus == .authorized }

    func lyrics(title: String, artist: String, duration: TimeInterval?) async -> [LyricLine]? {
        guard isAvailable else { return nil }
        let cacheKey = "\(LyricsDatabaseKeys.normalize(title))|\(LyricsDatabaseKeys.normalize(LyricsDatabaseKeys.primaryArtist(artist)))"
        if let cached = cache.value(for: cacheKey) { return cached }
        let started = Date()
        let lines = await fetch(title: title, artist: artist, duration: duration)
        cache.set(lines, for: cacheKey)
        LyricsLog.info(
            "Apple Music lyrics for '\(title)': \(lines.map { "\($0.count) lines, \($0.filter(\.hasWordTiming).count) word-synced" } ?? "none") (\(Int(Date().timeIntervalSince(started) * 1000))ms)"
        )
        return lines
    }

    private func fetch(title: String, artist: String, duration: TimeInterval?) async -> [LyricLine]? {
        guard let songID = await catalogSongID(title: title, artist: artist, duration: duration) else { return nil }
        do {
            if storefront == nil { storefront = try await MusicDataRequest.currentCountryCode }
            guard let storefront else { return nil }
            for endpoint in ["syllable-lyrics", "lyrics"] {
                guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(storefront)/songs/\(songID)/\(endpoint)") else { continue }
                do {
                    let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
                    guard let ttml = Self.ttml(in: response.data) else {
                        LyricsLog.info("Apple Music lyrics: \(endpoint) for song \(songID) had no TTML (\(response.data.count) bytes)")
                        continue
                    }
                    guard let lines = AppleMusicTTMLParser.lines(from: ttml) else {
                        LyricsLog.error("Apple Music lyrics: \(endpoint) TTML for song \(songID) did not parse")
                        continue
                    }
                    return lines
                } catch let error as MusicDataRequest.Error where error.status == 400 && error.code == 40012 {
                    deniedByApple = true
                    LyricsLog.info("Apple Music lyrics: Apple doesn't grant lyric access to Sapphire's MusicKit token; not asking again this session")
                    return nil
                } catch {
                    LyricsLog.info("Apple Music lyrics: \(endpoint) for song \(songID) failed: \(String(describing: error))")
                }
            }
        } catch {
            LyricsLog.error("Apple Music lyrics: storefront lookup failed: \(error.localizedDescription)")
        }
        return nil
    }

    private func catalogSongID(title: String, artist: String, duration: TimeInterval?) async -> String? {
        let wantedTitle = LyricsDatabaseKeys.normalize(title)
        let wantedArtist = LyricsDatabaseKeys.normalize(LyricsDatabaseKeys.primaryArtist(artist))
        var request = MusicCatalogSearchRequest(term: "\(title) \(LyricsDatabaseKeys.primaryArtist(artist))", types: [Song.self])
        request.limit = 10
        let songs: MusicItemCollection<Song>
        do {
            songs = try await request.response().songs
        } catch {
            LyricsLog.info("Apple Music lyrics: catalog search failed: \(String(describing: error))")
            return nil
        }
        let match = songs.first { song in
            guard LyricsDatabaseKeys.normalize(song.title) == wantedTitle else { return false }
            let artistName = LyricsDatabaseKeys.normalize(song.artistName)
            guard artistName.contains(wantedArtist) || wantedArtist.contains(artistName) else { return false }
            guard let duration, duration > 0, let length = song.duration else { return true }
            return abs(length - duration) <= 4
        }
        if match == nil {
            LyricsLog.info(
                "Apple Music lyrics: no catalog match for '\(title)' among \(songs.count): \(songs.prefix(3).map { "\($0.title) — \($0.artistName) (\(Int($0.duration ?? 0))s)" }.joined(separator: "; "))"
            )
        }
        return match?.id.rawValue
    }

    static func ttml(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["data"] as? [[String: Any]],
              let attributes = entries.first?["attributes"] as? [String: Any] else { return nil }
        return (attributes["ttml"] as? String) ?? (attributes["ttmlLocalizations"] as? String)
    }
}