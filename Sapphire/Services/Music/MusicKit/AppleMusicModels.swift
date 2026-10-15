//
//  AppleMusicModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-25
//

import Foundation
import MusicKit

// MARK: - Value types the UI renders (decoupled from MusicKit's structs)

struct AppleMusicSearchResults {
    var topResults: [AppleMusicTopResult] = []
    var songs: [AppleMusicSong] = []
    var albums: [AppleMusicAlbum] = []
    var artists: [AppleMusicArtist] = []
    var playlists: [AppleMusicPlaylist] = []
    var stations: [AppleMusicStation] = []
    var musicVideos: [AppleMusicMusicVideo] = []
    var librarySongs: [AppleMusicSong] = []

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
            && stations.isEmpty && librarySongs.isEmpty
    }
}

enum AppleMusicTopResult: Identifiable, Hashable {
    case song(AppleMusicSong)
    case album(AppleMusicAlbum)
    case artist(AppleMusicArtist)
    case playlist(AppleMusicPlaylist)
    case station(AppleMusicStation)

    var id: String {
        switch self {
        case .song(let item): "song:\(item.id)"
        case .album(let item): "album:\(item.id)"
        case .artist(let item): "artist:\(item.id)"
        case .playlist(let item): "playlist:\(item.id)"
        case .station(let item): "station:\(item.id)"
        }
    }
}

struct AppleMusicSong: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    let url: URL?
    var playCount: Int? = nil
    var lastPlayedDate: Date? = nil
    var libraryAddedDate: Date? = nil
    var isExplicit: Bool = false
    var catalogID: String? = nil
}

struct AppleMusicAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let artworkURL: URL?
    let url: URL?
    var releaseDate: Date? = nil
    var trackCount: Int? = nil
    var isSingle: Bool = false
}

struct AppleMusicArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let artworkURL: URL?
    let url: URL?
    var genreNames: [String] = []
}

struct AppleMusicPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let curatorName: String?
    let artworkURL: URL?
    let url: URL?
    var shortDescription: String? = nil
    var isLibrary: Bool = false
}

struct AppleMusicMusicVideo: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    let url: URL?
}

struct AppleMusicStation: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String?
    let artworkURL: URL?
    let url: URL?
    var isLive: Bool = false
}

struct AppleMusicGenre: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AppleMusicShelfItem: Identifiable, Hashable {
    case album(AppleMusicAlbum)
    case playlist(AppleMusicPlaylist)
    case station(AppleMusicStation)

    var id: String {
        switch self {
        case .album(let item): "album:\(item.id)"
        case .playlist(let item): "playlist:\(item.id)"
        case .station(let item): "station:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .album(let item): item.title
        case .playlist(let item): item.name
        case .station(let item): item.name
        }
    }

    var subtitle: String? {
        switch self {
        case .album(let item): item.artistName
        case .playlist(let item): item.curatorName
        case .station(let item): item.tagline
        }
    }

    var artworkURL: URL? {
        switch self {
        case .album(let item): item.artworkURL
        case .playlist(let item): item.artworkURL
        case .station(let item): item.artworkURL
        }
    }
}

struct AppleMusicRecommendationShelf: Identifiable, Hashable {
    let id: String
    let title: String
    let reason: String?
    let items: [AppleMusicShelfItem]
}

struct AppleMusicChartSet: Equatable {
    var songs: [AppleMusicSong] = []
    var albums: [AppleMusicAlbum] = []
    var playlists: [AppleMusicPlaylist] = []
    var musicVideos: [AppleMusicMusicVideo] = []
    var dailyGlobalTop: [AppleMusicPlaylist] = []
    var cityTop: [AppleMusicPlaylist] = []
}

struct AppleMusicReplaySummary: Equatable {
    var playlistName: String? = nil
    var topSongs: [AppleMusicSong] = []
    var topAlbums: [AppleMusicAlbum] = []
    var topArtists: [AppleMusicArtist] = []
}

struct AppleMusicArtistDetail: Equatable {
    let artist: AppleMusicArtist
    var bio: String? = nil
    var topSongs: [AppleMusicSong] = []
    var latestRelease: AppleMusicAlbum? = nil
    var albums: [AppleMusicAlbum] = []
    var singles: [AppleMusicAlbum] = []
    var liveAlbums: [AppleMusicAlbum] = []
    var compilations: [AppleMusicAlbum] = []
    var appearsOn: [AppleMusicAlbum] = []
    var featuredPlaylists: [AppleMusicPlaylist] = []
    var similarArtists: [AppleMusicArtist] = []
    var topMusicVideos: [AppleMusicMusicVideo] = []
    var station: AppleMusicStation? = nil
}

struct AppleMusicAlbumDetail: Equatable {
    let album: AppleMusicAlbum
    var notes: String? = nil
    var copyright: String? = nil
    var recordLabel: String? = nil
    var genreNames: [String] = []
    var audioBadges: [AppleMusicAudioBadge] = []
    var tracks: [AppleMusicSong] = []
    var relatedAlbums: [AppleMusicAlbum] = []
    var otherVersions: [AppleMusicAlbum] = []
    var appearsOn: [AppleMusicPlaylist] = []
}

struct AppleMusicPlaylistDetail: Equatable {
    let playlist: AppleMusicPlaylist
    var tracks: [AppleMusicSong] = []
    var featuredArtists: [AppleMusicArtist] = []
    var moreByCurator: [AppleMusicPlaylist] = []
}

enum AppleMusicAudioBadge: String, Hashable, CaseIterable {
    case dolbyAtmos = "Dolby Atmos"
    case lossless = "Lossless"
    case hiResLossless = "Hi-Res Lossless"
    case spatial = "Spatial"
    case appleDigitalMaster = "Apple Digital Master"

    var systemImage: String {
        switch self {
        case .dolbyAtmos, .spatial: "hifispeaker.2.fill"
        case .lossless, .hiResLossless: "waveform"
        case .appleDigitalMaster: "checkmark.seal.fill"
        }
    }
}

struct AppleMusicNowPlayingDetails: Equatable {
    var song: AppleMusicSong? = nil
    var artist: AppleMusicArtist? = nil
    var album: AppleMusicAlbum? = nil
    var composer: String? = nil
    var genreNames: [String] = []
    var releaseDate: Date? = nil
    var audioBadges: [AppleMusicAudioBadge] = []
    var hasLyrics: Bool = false
    var isInLibrary: Bool = false
    var isFavorited: Bool? = nil
    var isDisliked: Bool? = nil
    var playCount: Int? = nil
    var lastPlayedDate: Date? = nil
    var libraryAddedDate: Date? = nil
    var hasStation: Bool = false
    var moreByArtist: [AppleMusicSong] = []
    var similarArtists: [AppleMusicArtist] = []
    var relatedAlbums: [AppleMusicAlbum] = []
}

struct AppleMusicAccountState: Equatable {
    var authorization: MusicAuthorization.Status = .notDetermined
    var canPlayCatalogContent = false
    var canBecomeSubscriber = false
    var hasCloudLibraryEnabled = false
    var countryCode: String? = nil
    var lastError: String? = nil

    var isAuthorized: Bool { authorization == .authorized }
}

// MARK: - Library artwork

enum AppleMusicArtworkRegistry {
    private static let lock = NSLock()
    private static var artworks: [String: Artwork] = [:]

    static func isMusicKitURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme != "http" && scheme != "https" && scheme != "file"
    }

    static func register(_ artwork: Artwork, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        if artworks.count > 4000 { artworks.removeAll(keepingCapacity: true) }
        artworks[url.absoluteString] = artwork
    }

    static func artwork(for url: URL) -> Artwork? {
        lock.lock(); defer { lock.unlock() }
        return artworks[url.absoluteString]
    }
}

// MARK: - MusicKit → value-type mapping

enum AppleMusicMapper {
    static func artworkURL(_ artwork: Artwork?, size: Int = 300) -> URL? {
        guard let artwork, let url = artwork.url(width: size, height: size) else { return nil }
        switch url.scheme?.lowercased() {
        case "http", "https", "file":
            return url
        default:
            AppleMusicArtworkRegistry.register(artwork, for: url)
            return url
        }
    }

    static func song(_ song: Song) -> AppleMusicSong {
        AppleMusicSong(
            id: song.id.rawValue,
            title: song.title,
            artistName: song.artistName,
            albumTitle: song.albumTitle,
            artworkURL: artworkURL(song.artwork),
            duration: song.duration,
            url: song.url,
            playCount: song.playCount,
            lastPlayedDate: song.lastPlayedDate,
            libraryAddedDate: song.libraryAddedDate,
            isExplicit: song.contentRating == .explicit,
            catalogID: catalogID(song.id.rawValue, playParameters: song.playParameters)
        )
    }

    static func catalogID(_ id: String, playParameters: PlayParameters?) -> String? {
        if AppleMusicSystemQueue.isCatalogID(id) { return id }
        guard let playParameters,
              let data = try? JSONEncoder().encode(playParameters),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["catalogId", "reportingId", "purchasedId"] {
            if let value = object[key] as? String, AppleMusicSystemQueue.isCatalogID(value) { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    static func song(_ track: Track) -> AppleMusicSong? {
        switch track {
        case .song(let song): return self.song(song)
        case .musicVideo: return nil
        @unknown default: return nil
        }
    }

    static func album(_ album: Album) -> AppleMusicAlbum {
        AppleMusicAlbum(
            id: album.id.rawValue,
            title: album.title,
            artistName: album.artistName,
            artworkURL: artworkURL(album.artwork),
            url: album.url,
            releaseDate: album.releaseDate,
            trackCount: album.trackCount,
            isSingle: album.isSingle ?? false
        )
    }

    static func artist(_ artist: Artist) -> AppleMusicArtist {
        AppleMusicArtist(
            id: artist.id.rawValue,
            name: artist.name,
            artworkURL: artworkURL(artist.artwork),
            url: artist.url,
            genreNames: artist.genreNames ?? []
        )
    }

    static func playlist(_ playlist: Playlist, isLibrary: Bool = false) -> AppleMusicPlaylist {
        AppleMusicPlaylist(
            id: playlist.id.rawValue,
            name: playlist.name,
            curatorName: playlist.curatorName,
            artworkURL: artworkURL(playlist.artwork),
            url: playlist.url,
            shortDescription: playlist.shortDescription,
            isLibrary: isLibrary
        )
    }

    static func station(_ station: Station) -> AppleMusicStation {
        AppleMusicStation(
            id: station.id.rawValue,
            name: station.name,
            tagline: station.editorialNotes?.short ?? station.stationProviderName,
            artworkURL: artworkURL(station.artwork),
            url: station.url,
            isLive: station.isLive
        )
    }

    static func musicVideo(_ video: MusicVideo) -> AppleMusicMusicVideo {
        AppleMusicMusicVideo(
            id: video.id.rawValue,
            title: video.title,
            artistName: video.artistName,
            albumTitle: video.albumTitle,
            artworkURL: artworkURL(video.artwork),
            duration: video.duration,
            url: video.url
        )
    }

    static func shelfItem(_ item: MusicPersonalRecommendation.Item) -> AppleMusicShelfItem? {
        switch item {
        case .album(let album): return .album(self.album(album))
        case .playlist(let playlist): return .playlist(self.playlist(playlist))
        case .station(let station): return .station(self.station(station))
        @unknown default: return nil
        }
    }

    static func shelfItem(_ item: RecentlyPlayedMusicItem) -> AppleMusicShelfItem? {
        switch item {
        case .album(let album): return .album(self.album(album))
        case .playlist(let playlist): return .playlist(self.playlist(playlist))
        case .station(let station): return .station(self.station(station))
        @unknown default: return nil
        }
    }

    static func badges(variants: [AudioVariant]?, isDigitalMaster: Bool?) -> [AppleMusicAudioBadge] {
        var badges: [AppleMusicAudioBadge] = []
        for variant in variants ?? [] {
            let badge: AppleMusicAudioBadge?
            switch variant {
            case .dolbyAtmos: badge = .dolbyAtmos
            case .highResolutionLossless: badge = .hiResLossless
            case .lossless: badge = .lossless
            case .spatialAudio: badge = .spatial
            default: badge = nil
            }
            if let badge, !badges.contains(badge) { badges.append(badge) }
        }
        if badges.contains(.hiResLossless) { badges.removeAll { $0 == .lossless } }
        if isDigitalMaster == true { badges.append(.appleDigitalMaster) }
        return badges
    }

    static func matchKey(_ string: String) -> String {
        var value = string.lowercased()
        for marker in [" (feat.", " [feat.", " (with ", " - single", " - ep", " (remaster", " - remaster"] {
            if let range = value.range(of: marker) { value = String(value[..<range.lowerBound]) }
        }
        return value.filter { $0.isLetter || $0.isNumber }
    }
}