//
//  SongInfoService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-13

import FirebaseFirestore
import Foundation

struct SongInfo: Decodable, Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?
    let albumType: String?
    let released: String?
    let durationMs: Int?
    let isrcs: [String]?
    let musicBrainzID: String?
    let writing: [String: [String]]?
    let production: [String: [String]]?
    let language: String?
    let releases: Int?

    enum CodingKeys: String, CodingKey {
        case title = "t", artist = "a", album = "al", albumType = "at", released = "y", durationMs = "d"
        case isrcs = "isrc", musicBrainzID = "mb", writing = "w", production = "p", language = "l", releases = "r"
    }

    struct CreditSection: Identifiable, Equatable {
        let title: String
        let names: [String]
        var id: String { title }
    }

    var creditSections: [CreditSection] {
        func names(_ roles: [String], in credits: [String: [String]]?) -> [String] {
            var seen = Set<String>()
            return roles.flatMap { credits?[$0] ?? [] }.filter { seen.insert($0).inserted }
        }
        return [
            CreditSection(title: "Written By", names: names(["writer", "composer", "lyricist", "librettist"], in: writing)),
            CreditSection(title: "Produced By", names: names(["producer"], in: production)),
            CreditSection(title: "Mixing", names: names(["mix"], in: production)),
            CreditSection(title: "Mastering", names: names(["mastering"], in: production)),
            CreditSection(title: "Engineering", names: names(["recording", "engineer", "audio"], in: production)),
        ].filter { !$0.names.isEmpty }
    }

    var releaseYear: String? { released.map { String($0.prefix(4)) } }

    var languageName: String? {
        language.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
    }
}

@MainActor
final class SongInfoService {
    static let shared = SongInfoService()
    nonisolated static let collection = "songs"

    private var memory = BoundedLRUCache<String, SongInfo?>(capacity: 32)

    private init() {}

    func info(title: String, artist: String) async -> SongInfo? {
        guard let key = LyricsDatabase.key(title: title, artist: artist) else { return nil }
        if let cached = memory.value(for: key) { return cached }
        let info = await Self.fetch(key: key)
        memory.set(info, for: key)
        return info
    }

    private nonisolated static func fetch(key: String) async -> SongInfo? {
        let cacheKey = "\(collection):\(key)"
        switch LyricsDatabaseDiskCache.entry(for: cacheKey) {
        case .document(let data): return decode(data)
        case .missing: return nil
        case nil: break
        }
        guard let database = await MainActor.run(body: { FirebaseBootstrap.firestoreDatabase() }) else { return nil }
        do {
            let data = try await database.collection(collection).document(key).getDocument().data()
            LyricsDatabaseDiskCache.store(data, for: cacheKey)
            return data.flatMap(decode)
        } catch {
            LyricsLog.error("Song info lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static func decode(_ data: [String: Any]) -> SongInfo? {
        guard let packed = data["i"] as? Data, let json = LyricsDatabaseDocument.inflate(packed) else { return nil }
        return try? JSONDecoder().decode(SongInfo.self, from: json)
    }
}