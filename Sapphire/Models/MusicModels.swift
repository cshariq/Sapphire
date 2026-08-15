//
//  MusicModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02
//

import Foundation

// MARK: - Flexible JSON number helpers
// Spotify often encodes timestamps/positions as strings in connect-state payloads.

enum SpotifyFlexibleNumber {
    static func decodeInt64<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) -> Int64? {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int64(value) }
        return nil
    }

    static func decodeInt<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }
}

enum SpotifyIDConverter {
    private static let base62Alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Extracts a raw Spotify ID from a URI or bare ID.
    static func rawID(from value: String) -> String {
        if value.hasPrefix("spotify:"), let id = value.split(separator: ":").last {
            return String(id)
        }
        if let url = URL(string: value), url.host?.contains("spotify.com") == true {
            return url.lastPathComponent
        }
        return value
    }

    /// Builds a full Spotify URI (`spotify:track:…`) from a type + ID/URI.
    static func uri(type: String, from value: String) -> String {
        let id = rawID(from: value)
        if value.hasPrefix("spotify:") { return value }
        return "spotify:\(type):\(id)"
    }

    /// Converts a Spotify base62 track/album/artist ID into the hex GID used by metadata/4 APIs.
    static func gid(fromBase62 id: String) -> String? {
        let cleaned = rawID(from: id)
        if cleaned.count == 32, cleaned.allSatisfy(\.isHexDigit) {
            return cleaned.lowercased()
        }
        var value = Array(repeating: 0, count: 16)
        for char in cleaned {
            guard let digit = base62Alphabet.firstIndex(of: char) else { return nil }
            var carry = digit
            for i in stride(from: 15, through: 0, by: -1) {
                let product = value[i] * 62 + carry
                value[i] = product & 0xFF
                carry = product >> 8
            }
            if carry != 0 { return nil }
        }
        return value.map { String(format: "%02x", $0) }.joined()
    }

    /// Converts a hex GID back into a Spotify base62 ID.
    static func base62(fromGID gid: String) -> String? {
        let cleaned = gid.lowercased()
        guard cleaned.count == 32, cleaned.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        var digits = [Int]()
        var remaining = bytes
        while !remaining.allSatisfy({ $0 == 0 }) {
            var quotient = [UInt8]()
            var carry = 0
            for byte in remaining {
                let value = carry * 256 + Int(byte)
                let q = value / 62
                carry = value % 62
                if !quotient.isEmpty || q != 0 {
                    quotient.append(UInt8(q))
                }
            }
            digits.append(carry)
            remaining = quotient
        }
        if digits.isEmpty { return "0" }
        return String(digits.reversed().map { base62Alphabet[$0] })
    }

    /// Percent-encodes Spotify URIs for path/query usage (`:` → `%3A`).
    static func pathEncodedURI(_ uri: String) -> String {
        uri.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))
            ?? uri.replacingOccurrences(of: ":", with: "%3A")
    }
}

// MARK: - Shared Enums

enum RepeatMode: String, Codable {
    case off, context, track

    func next() -> RepeatMode {
        switch self {
        case .off: return .context
        case .context: return .track
        case .track: return .off
        }
    }
}

// MARK: - Official Spotify API Models

struct SpotifyImage: Codable, Hashable {
    let url: String
}
struct SpotifyAlbum: Codable, Hashable {
    let name: String
    let images: [SpotifyImage]
}
struct SpotifyArtist: Codable, Hashable {
    let name: String
}
struct PlaybackState: Codable {
    let device: SpotifyDevice
    let item: SpotifyTrack?
    let isPlaying: Bool
    let progressMs: Int?
    let shuffleState: Bool
    let repeatState: String

    enum CodingKeys: String, CodingKey {
        case device, item, progressMs = "progress_ms", isPlaying = "is_playing"
        case shuffleState = "shuffle_state", repeatState = "repeat_state"
    }
}
struct UserProfile: Codable, Identifiable {
    let id: String
    let displayName: String
    let product: String
    let followers: Followers?

    struct Followers: Codable, Hashable {
        let total: Int?
    }

    enum CodingKeys: String, CodingKey {
        case id, product, followers
        case displayName = "display_name"
    }

    var followerCount: Int? { followers?.total }
}
struct SpotifyUserSimple: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let images: [SpotifyImage]?

    var imageURL: URL? {
        URL(string: images?.first?.url ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case images
    }
}

struct SpotifyTrack: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let album: SpotifyAlbum
    let artists: [SpotifyArtist]
    let durationMs: Int
    let popularity: Int?
    enum CodingKeys: String, CodingKey {
        case id, name, uri, album, artists, popularity
        case durationMs = "duration_ms"
    }
    var imageURL: URL? {
        guard let urlString = album.images.first?.url else { return nil }
        return URL(string: urlString)
    }
}
struct SpotifyPlaylist: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]
    let owner: SpotifyUserSimple
    let collaborators: [SpotifyUserSimple]?

    var imageURL: URL? {
        URL(string: images.first?.url ?? "")
    }
}

struct PlaylistTracksResponse: Codable {
    let items: [PlaylistTrackItem]
}
struct PlaylistTrackItem: Codable {
    let track: SpotifyTrack
}
struct SpotifyDevice: Codable, Identifiable, Hashable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool
    let volumePercent: Int?
    enum CodingKeys: String, CodingKey { case id, name, type, isActive = "is_active", volumePercent = "volume_percent" }
}
struct SpotifyQueue: Codable {
    let currentlyPlaying: SpotifyTrack?
    let queue: [SpotifyTrack]
    enum CodingKeys: String, CodingKey { case currentlyPlaying = "currently_playing", queue }
}
struct SearchResponse: Codable {
    let tracks: TrackSearchResult
}
struct TrackSearchResult: Codable {
    let items: [SpotifyTrack]
}

// MARK: - URI to URL Helper
extension String {
    func toSpotifyImageURL() -> URL? {
        if self.starts(with: "spotify:image:") {
            let imageId = self.replacingOccurrences(of: "spotify:image:", with: "")
            return URL(string: "https://i.scdn.co/image/\(imageId)")
        }
        return URL(string: self)
    }
}

// MARK: - Native User Profile (/api/account-settings/v1/profile)
struct SpotifyNativeUserProfile: Decodable {
    var profile: Profile
    struct Profile: Decodable {
        let email: String?
        let gender: String?
        let birthdate: String?
        let country: String?
        let username: String
        var displayName: String?

        /// Prefer human-readable name over the opaque Spotify user id.
        var friendlyName: String {
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
            return username
        }

        enum CodingKeys: String, CodingKey {
            case email, gender, birthdate, country, username, displayName, name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            email = try container.decodeIfPresent(String.self, forKey: .email)
            gender = try container.decodeIfPresent(String.self, forKey: .gender)
            birthdate = try container.decodeIfPresent(String.self, forKey: .birthdate)
            country = try container.decodeIfPresent(String.self, forKey: .country)
            username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
            // account-settings may use display_name; Pathfinder profileAttributes uses name.
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
                ?? container.decodeIfPresent(String.self, forKey: .name)
        }
    }
}

// MARK: - Native Player State (/connect-state/v1/devices/hobs_...) & WebSocket
struct SpotifyNativePlayerStateResponse: Decodable {
    let activeDeviceId: String?
    let playerState: PlayerState
    let devices: [String: SpotifyNativeDevice]

    enum CodingKeys: String, CodingKey {
        case activeDeviceId, playerState, devices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeDeviceId = try container.decodeIfPresent(String.self, forKey: .activeDeviceId)
        playerState = try container.decodeIfPresent(PlayerState.self, forKey: .playerState) ?? PlayerState()
        devices = try container.decodeIfPresent([String: SpotifyNativeDevice].self, forKey: .devices) ?? [:]
    }

    init(activeDeviceId: String?, playerState: PlayerState, devices: [String: SpotifyNativeDevice]) {
        self.activeDeviceId = activeDeviceId
        self.playerState = playerState
        self.devices = devices
    }
}

struct PlayerState: Decodable {
    var track: Track?
    let isPlaying: Bool?
    let isPaused: Bool?
    let timestamp: Int64?
    let positionAsOfTimestamp: Int?
    let duration: Int?
    let options: Options?
    let prevTracks: [Track]?
    let nextTracks: [Track]?
    let contextUri: String?
    let playOrigin: PlayOrigin?
    let queueRevision: String?

    enum CodingKeys: String, CodingKey {
        case track, isPlaying, isPaused, timestamp, positionAsOfTimestamp, duration
        case options, prevTracks, nextTracks, contextUri, playOrigin
        case queueRevision = "queue_revision"
    }

    init(
        track: Track? = nil,
        isPlaying: Bool? = nil,
        isPaused: Bool? = nil,
        timestamp: Int64? = nil,
        positionAsOfTimestamp: Int? = nil,
        duration: Int? = nil,
        options: Options? = nil,
        prevTracks: [Track]? = nil,
        nextTracks: [Track]? = nil,
        contextUri: String? = nil,
        playOrigin: PlayOrigin? = nil,
        queueRevision: String? = nil
    ) {
        self.track = track
        self.isPlaying = isPlaying
        self.isPaused = isPaused
        self.timestamp = timestamp
        self.positionAsOfTimestamp = positionAsOfTimestamp
        self.duration = duration
        self.options = options
        self.prevTracks = prevTracks
        self.nextTracks = nextTracks
        self.contextUri = contextUri
        self.playOrigin = playOrigin
        self.queueRevision = queueRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        track = try container.decodeIfPresent(Track.self, forKey: .track)
        isPlaying = try container.decodeIfPresent(Bool.self, forKey: .isPlaying)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused)
        timestamp = SpotifyFlexibleNumber.decodeInt64(from: container, forKey: .timestamp)
        positionAsOfTimestamp = SpotifyFlexibleNumber.decodeInt(from: container, forKey: .positionAsOfTimestamp)
        duration = SpotifyFlexibleNumber.decodeInt(from: container, forKey: .duration)
        options = try container.decodeIfPresent(Options.self, forKey: .options)
        prevTracks = try container.decodeIfPresent([Track].self, forKey: .prevTracks)
        nextTracks = try container.decodeIfPresent([Track].self, forKey: .nextTracks)
        contextUri = try container.decodeIfPresent(String.self, forKey: .contextUri)
        playOrigin = try container.decodeIfPresent(PlayOrigin.self, forKey: .playOrigin)
        queueRevision = try container.decodeIfPresent(String.self, forKey: .queueRevision)
    }

    /// Connect-state realtime position (ms): when paused use the sample; otherwise advance by wall-clock delta.
    func realtimePositionMilliseconds(at now: Date = Date()) -> Int? {
        guard let sampleMs = positionAsOfTimestamp, let timestamp else { return nil }
        let paused = (isPaused == true) || (isPlaying == false)
        if paused { return sampleMs }
        let sampleEpochSeconds = TimeInterval(timestamp) / 1000.0
        let elapsed = max(0, now.timeIntervalSince1970 - sampleEpochSeconds)
        let live = sampleMs + Int(elapsed * 1000.0)
        if let duration, duration > 0 { return min(live, duration) }
        return live
    }

    var isActivelyPlaying: Bool {
        if isPaused == true { return false }
        if isPlaying == true { return true }
        if isPlaying == false { return false }
        // Some Connect payloads only include is_paused.
        if isPaused == false { return true }
        return false
    }

    struct Options: Decodable {
        let shufflingContext: Bool?
        let repeatingContext: Bool?
        let repeatingTrack: Bool?
    }

    struct Track: Decodable, Hashable {
        let uri: String
        let uid: String
        var metadata: Metadata?

        enum CodingKeys: String, CodingKey {
            case uri, uid, metadata
        }

        init(uri: String, uid: String, metadata: Metadata?) {
            self.uri = uri
            self.uid = uid
            self.metadata = metadata
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
            uid = try container.decodeIfPresent(String.self, forKey: .uid) ?? UUID().uuidString
            metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
        }

        struct Metadata: Decodable, Hashable {
            var title: String?
            var albumTitle: String?
            var artistName: String?
            var artistUri: String?
            var imageUrl: String?
            var imageSmallUrl: String?
            var imageLargeUrl: String?
            var imageXlargeUrl: String?
            let contextUri: String?
            let hidden: String?

            var imageURL: URL? {
                let urlString = (imageUrl ?? imageLargeUrl ?? imageSmallUrl ?? imageXlargeUrl)?
                    .replacingOccurrences(of: "spotify:image:", with: "https://i.scdn.co/image/")
                return URL(string: urlString ?? "")
            }
        }
    }
}

extension PlayerState.Track {
    init(hydrating sparseTrack: PlayerState.Track, withDetails details: SpotifyTrackDetailsResponse.TrackUnion) {
        self.uri = sparseTrack.uri
        self.uid = sparseTrack.uid

        var updatedMetadata = sparseTrack.metadata ?? Metadata(title: nil, albumTitle: nil, artistName: nil, artistUri: nil, imageUrl: nil, imageSmallUrl: nil, imageLargeUrl: nil, imageXlargeUrl: nil, contextUri: nil, hidden: nil)

        let allArtistItems = (details.artists?.items ?? []) + (details.otherArtists?.items ?? [])

        if !allArtistItems.isEmpty {
            updatedMetadata.artistUri = allArtistItems.first?.uri
            updatedMetadata.artistName = allArtistItems.map { $0.profile.name }.joined(separator: ", ")
        }

        updatedMetadata.title = details.name
        updatedMetadata.albumTitle = details.albumOfTrack?.name

        let bestImage = details.albumOfTrack?.coverArt.sources.max { ($0.width ?? 0) < ($1.width ?? 0) }
        updatedMetadata.imageUrl = bestImage?.url

        self.metadata = updatedMetadata
    }
}

// MARK: - Device and Capabilities (Expanded Models)

struct Hifi: Decodable, Hashable {
    let deviceSupported: Bool?
}

struct SpotifyNativeDevice: Decodable, Hashable, Identifiable {
    var id: String { deviceId }
    let canPlay: Bool
    let volume: Int?
    let name: String
    let deviceId: String
    let deviceType: String
    let spircVersion: String?
    let deviceSoftwareVersion: String?
    let model: String?
    let brand: String
    let capabilities: Capabilities

    enum CodingKeys: String, CodingKey {
        case canPlay, volume, name, deviceId, deviceType
        case spircVersion, deviceSoftwareVersion, model, brand, capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canPlay = try container.decodeIfPresent(Bool.self, forKey: .canPlay) ?? false
        if let intVolume = try? container.decodeIfPresent(Int.self, forKey: .volume) {
            volume = intVolume
        } else if let doubleVolume = try? container.decodeIfPresent(Double.self, forKey: .volume) {
            volume = Int(doubleVolume)
        } else {
            volume = nil
        }
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Device"
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? UUID().uuidString
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType) ?? "UNKNOWN"
        spircVersion = try container.decodeIfPresent(String.self, forKey: .spircVersion)
        deviceSoftwareVersion = try container.decodeIfPresent(String.self, forKey: .deviceSoftwareVersion)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? "unknown"
        capabilities = try container.decodeIfPresent(Capabilities.self, forKey: .capabilities) ?? Capabilities()
    }
}

struct Capabilities: Decodable, Hashable {
    let canBePlayer: Bool
    let isControllable: Bool
    let gaiaEqConnectId: Bool?
    let supportsLogout: Bool?
    let isObservable: Bool?
    let volumeSteps: Int?
    let supportedTypes: [String]?
    let commandAcks: Bool?
    let supportsRename: Bool?
    let supportsPlaylistV2: Bool?
    let supportsExternalEpisodes: Bool?
    let supportsSetBackendMetadata: Bool?
    let supportsTransferCommand: Bool?
    let supportsCommandRequest: Bool?
    let supportsGzipPushes: Bool?
    let supportsSetOptionsCommand: Bool?
    let supportsHifi: Hifi?
    let supportsDj: Bool?

    init(
        canBePlayer: Bool = false,
        isControllable: Bool = false,
        gaiaEqConnectId: Bool? = nil,
        supportsLogout: Bool? = nil,
        isObservable: Bool? = nil,
        volumeSteps: Int? = nil,
        supportedTypes: [String]? = nil,
        commandAcks: Bool? = nil,
        supportsRename: Bool? = nil,
        supportsPlaylistV2: Bool? = nil,
        supportsExternalEpisodes: Bool? = nil,
        supportsSetBackendMetadata: Bool? = nil,
        supportsTransferCommand: Bool? = nil,
        supportsCommandRequest: Bool? = nil,
        supportsGzipPushes: Bool? = nil,
        supportsSetOptionsCommand: Bool? = nil,
        supportsHifi: Hifi? = nil,
        supportsDj: Bool? = nil
    ) {
        self.canBePlayer = canBePlayer
        self.isControllable = isControllable
        self.gaiaEqConnectId = gaiaEqConnectId
        self.supportsLogout = supportsLogout
        self.isObservable = isObservable
        self.volumeSteps = volumeSteps
        self.supportedTypes = supportedTypes
        self.commandAcks = commandAcks
        self.supportsRename = supportsRename
        self.supportsPlaylistV2 = supportsPlaylistV2
        self.supportsExternalEpisodes = supportsExternalEpisodes
        self.supportsSetBackendMetadata = supportsSetBackendMetadata
        self.supportsTransferCommand = supportsTransferCommand
        self.supportsCommandRequest = supportsCommandRequest
        self.supportsGzipPushes = supportsGzipPushes
        self.supportsSetOptionsCommand = supportsSetOptionsCommand
        self.supportsHifi = supportsHifi
        self.supportsDj = supportsDj
    }

    enum CodingKeys: String, CodingKey {
        case canBePlayer, isControllable, gaiaEqConnectId, supportsLogout, isObservable
        case volumeSteps, supportedTypes, commandAcks, supportsRename, supportsPlaylistV2
        case supportsExternalEpisodes, supportsSetBackendMetadata, supportsTransferCommand
        case supportsCommandRequest, supportsGzipPushes, supportsSetOptionsCommand, supportsHifi, supportsDj
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canBePlayer = try container.decodeIfPresent(Bool.self, forKey: .canBePlayer) ?? false
        isControllable = try container.decodeIfPresent(Bool.self, forKey: .isControllable) ?? false
        gaiaEqConnectId = try container.decodeIfPresent(Bool.self, forKey: .gaiaEqConnectId)
        supportsLogout = try container.decodeIfPresent(Bool.self, forKey: .supportsLogout)
        isObservable = try container.decodeIfPresent(Bool.self, forKey: .isObservable)
        volumeSteps = try container.decodeIfPresent(Int.self, forKey: .volumeSteps)
        supportedTypes = try container.decodeIfPresent([String].self, forKey: .supportedTypes)
        commandAcks = try container.decodeIfPresent(Bool.self, forKey: .commandAcks)
        supportsRename = try container.decodeIfPresent(Bool.self, forKey: .supportsRename)
        supportsPlaylistV2 = try container.decodeIfPresent(Bool.self, forKey: .supportsPlaylistV2)
        supportsExternalEpisodes = try container.decodeIfPresent(Bool.self, forKey: .supportsExternalEpisodes)
        supportsSetBackendMetadata = try container.decodeIfPresent(Bool.self, forKey: .supportsSetBackendMetadata)
        supportsTransferCommand = try container.decodeIfPresent(Bool.self, forKey: .supportsTransferCommand)
        supportsCommandRequest = try container.decodeIfPresent(Bool.self, forKey: .supportsCommandRequest)
        supportsGzipPushes = try container.decodeIfPresent(Bool.self, forKey: .supportsGzipPushes)
        supportsSetOptionsCommand = try container.decodeIfPresent(Bool.self, forKey: .supportsSetOptionsCommand)
        if let hifi = try? container.decodeIfPresent(Hifi.self, forKey: .supportsHifi) {
            supportsHifi = hifi
        } else {
            supportsHifi = nil
        }
        supportsDj = try container.decodeIfPresent(Bool.self, forKey: .supportsDj)
    }
}

// MARK: - Track Details Response (/pathfinder/v1/query?operationName=getTrack)
struct SpotifyTrackDetailsResponse: Decodable {
    let data: DataResponse

    struct DataResponse: Decodable {
        let trackUnion: TrackUnion
    }

    struct TrackUnion: Decodable, Equatable {
        let uri: String
        let name: String
        let playcount: String?
        let albumOfTrack: AlbumOfTrack?
        let artists: ArtistCollection?
        let otherArtists: ArtistCollection?

        var playcountInt: Int? {
            guard let playcount = self.playcount, let count = Int(playcount) else { return nil }
            return count
        }

        enum CodingKeys: String, CodingKey {
            case uri, name, playcount, albumOfTrack, otherArtists
            case artists = "firstArtist"
        }

        static func == (lhs: TrackUnion, rhs: TrackUnion) -> Bool {
            return lhs.uri == rhs.uri
        }
    }

    struct AlbumOfTrack: Decodable {
        let name: String
        let coverArt: CoverArt
        let publishDate: SpotifyPlaylistDetailsResponse.PublishDate?

        enum CodingKeys: String, CodingKey {
            case name, coverArt
            case publishDate = "date"
        }
    }

    struct CoverArt: Decodable, Hashable {
        let sources: [ImageSource]

        var bestImageURL: URL? {
            let bestSource = sources.max { ($0.width ?? 0) * ($0.height ?? 0) < ($1.width ?? 0) * ($1.height ?? 0) } ?? sources.first
            return bestSource?.url?.toSpotifyImageURL()
        }
    }

    struct ImageSource: Decodable, Hashable {
        let url: String?
        let width: Int?
        let height: Int?
    }
}

fileprivate let spotifyDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

fileprivate let spotifyISO8601Fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

fileprivate let spotifyISO8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

enum SpotifyDateParsing {
    static func timeInterval(from isoString: String) -> TimeInterval? {
        if let date = spotifyISO8601Fractional.date(from: isoString)
            ?? spotifyISO8601.date(from: isoString)
            ?? spotifyDateFormatter.date(from: isoString) {
            return date.timeIntervalSince1970
        }
        return nil
    }
}

// MARK: - Playlist Details Response (/pathfinder/v1/query?operationName=fetchPlaylist)
struct SpotifyPlaylistDetailsResponse: Decodable {
    var data: DataResponse?

    struct DataResponse: Decodable {
        var playlistV2: PlaylistV2?

        enum CodingKeys: String, CodingKey {
            case playlistV2
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let playlistObjectContainer = try? container.nestedContainer(keyedBy: PlaylistV2.TypenameCodingKeys.self, forKey: .playlistV2) {
                let typename = try? playlistObjectContainer.decode(String.self, forKey: .typename)

                if typename == "Playlist" {
                    self.playlistV2 = try? container.decode(PlaylistV2.self, forKey: .playlistV2)
                } else {
                    self.playlistV2 = nil
                }
            } else {
                self.playlistV2 = nil
            }
        }
    }

    struct PlaylistV2: Decodable {
        let name: String
        var uri: String?
        var content: Content

        enum TypenameCodingKeys: String, CodingKey {
            case typename = "__typename"
        }

        enum CodingKeys: String, CodingKey {
            case name, uri, content
        }

        init(name: String, uri: String?, content: Content) {
            self.name = name
            self.uri = uri
            self.content = content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Playlist"
            uri = try container.decodeIfPresent(String.self, forKey: .uri)
            content = try container.decodeIfPresent(Content.self, forKey: .content) ?? Content(totalCount: 0, items: [])
        }

        struct Content: Decodable {
            let totalCount: Int
            var items: [PlaylistItem]

            enum CodingKeys: String, CodingKey {
                case totalCount, items
            }

            init(totalCount: Int, items: [PlaylistItem]) {
                self.totalCount = totalCount
                self.items = items
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
                items = try container.decodeIfPresent([PlaylistItem].self, forKey: .items) ?? []
            }
        }
    }

    struct PlaylistItem: Decodable, Equatable {
        let uid: String
        let itemV2: ItemV2
        let addedAtInfo: AddedAt?
        let addedBy: AddedByWrapper?

        enum CodingKeys: String, CodingKey {
            case uid, itemV2, addedAtInfo = "addedAt", addedBy
        }

        init(uid: String, itemV2: ItemV2, addedAtInfo: AddedAt?, addedBy: AddedByWrapper? = nil) {
            self.uid = uid
            self.itemV2 = itemV2
            self.addedAtInfo = addedAtInfo
            self.addedBy = addedBy
        }

        var addedAt: TimeInterval? {
            guard let isoString = addedAtInfo?.isoString else { return nil }
            return SpotifyDateParsing.timeInterval(from: isoString)
        }

        var addedByDisplayName: String? {
            let data = addedBy?.data
            let name = data?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty { return name }
            let username = data?.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let username, !username.isEmpty { return username }
            return nil
        }

        static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
            return lhs.uid == rhs.uid
        }
    }

    struct AddedByWrapper: Decodable {
        let data: AddedByUser?
    }

    struct AddedByUser: Decodable {
        let name: String?
        let username: String?
        let uri: String?

        enum CodingKeys: String, CodingKey {
            case name, username, uri, profile
        }

        enum ProfileKeys: String, CodingKey {
            case name, username, uri
        }

        init(name: String?, username: String?, uri: String?) {
            self.name = name
            self.username = username
            self.uri = uri
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let profile = try? container.nestedContainer(keyedBy: ProfileKeys.self, forKey: .profile) {
                name = try profile.decodeIfPresent(String.self, forKey: .name)
                    ?? container.decodeIfPresent(String.self, forKey: .name)
                username = try profile.decodeIfPresent(String.self, forKey: .username)
                    ?? container.decodeIfPresent(String.self, forKey: .username)
                uri = try profile.decodeIfPresent(String.self, forKey: .uri)
                    ?? container.decodeIfPresent(String.self, forKey: .uri)
            } else {
                name = try container.decodeIfPresent(String.self, forKey: .name)
                username = try container.decodeIfPresent(String.self, forKey: .username)
                uri = try container.decodeIfPresent(String.self, forKey: .uri)
            }
        }
    }

    struct AddedAt: Decodable {
        let isoString: String

        enum CodingKeys: String, CodingKey { case isoString }

        init(isoString: String) { self.isoString = isoString }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self),
               let iso = try container.decodeIfPresent(String.self, forKey: .isoString) {
                isoString = iso
                return
            }
            let single = try decoder.singleValueContainer()
            if let iso = try? single.decode(String.self) {
                isoString = iso
            } else {
                isoString = ""
            }
        }
    }

    struct ItemV2: Decodable {
        var data: ItemData
    }

    struct ItemData: Decodable {
        var uri: String?
        let name: String?
        let albumOfTrack: AlbumOfTrack?
        let artists: ArtistCollection?
        let playcount: String?

        var playcountInt: Int? {
            guard let playcount = self.playcount, let count = Int(playcount) else { return nil }
            return count
        }

        var imageURL: URL? {
            return albumOfTrack?.coverArt.bestImageURL
        }
    }

    struct ImageCollection: Decodable {
        let items: [ImageItem]?
        let sources: [ImageSource]?

        static let empty = ImageCollection(items: nil, sources: nil)

        var bestImageURL: URL? {
            if let directSources = sources, let url = directSources.first?.url {
                return url.toSpotifyImageURL()
            }
            if let itemSources = items?.first?.sources, let url = itemSources.first?.url {
                return url.toSpotifyImageURL()
            }
            return nil
        }
    }

    struct ImageItem: Decodable {
        let sources: [ImageSource]?
    }

    struct AlbumOfTrack: Decodable {
        let uri: String?
        let name: String
        let coverArt: ImageCollection
        let publishDate: PublishDate?

        enum CodingKeys: String, CodingKey {
            case uri, name, coverArt
            case publishDate = "date"
        }

        init(uri: String? = nil, name: String, coverArt: ImageCollection, publishDate: PublishDate? = nil) {
            self.uri = uri
            self.name = name
            self.coverArt = coverArt
            self.publishDate = publishDate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uri = try container.decodeIfPresent(String.self, forKey: .uri)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Album"
            coverArt = try container.decodeIfPresent(ImageCollection.self, forKey: .coverArt) ?? .empty
            publishDate = try container.decodeIfPresent(PublishDate.self, forKey: .publishDate)
        }
    }

    struct PublishDate: Decodable {
        let year: Int?
        let isoString: String?
    }
}

// MARK: - User Library Response (/pathfinder/v1/query?operationName=libraryV3)
struct UserLibraryResponse: Decodable {
    let data: DataClass?
    struct DataClass: Decodable { let me: Me? }
    struct Me: Decodable { let libraryV3: Library? }
    struct Library: Decodable {
        let items: [LibraryItem]?
        let availableSortOrders: [SortOrder]?
        let selectedSortOrder: SortOrder?
        let availableFilters: [LibraryFilter]?
    }
    struct SortOrder: Decodable, Hashable, Identifiable {
        let id: String
        let name: String
    }
    struct LibraryFilter: Decodable, Hashable, Identifiable {
        let id: String
        let name: String
    }
    struct LibraryItem: Decodable { let item: ItemWrapper? }
    struct ItemWrapper: Decodable { let data: LibraryItemType? }

    enum LibraryItemType: Decodable {
        case playlist(PlaylistData)
        case pseudoPlaylist(PseudoPlaylistData)
        case artist(ArtistData)
        case album(AlbumData)
        case show(ShowData)
        case unknown

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try? container.decode(String.self, forKey: .typename)

            let singleValueContainer = try decoder.singleValueContainer()
            switch type {
            case "Playlist":
                self = .playlist(try singleValueContainer.decode(PlaylistData.self))
            case "PseudoPlaylist":
                self = .pseudoPlaylist(try singleValueContainer.decode(PseudoPlaylistData.self))
            case "Artist":
                self = .artist(try singleValueContainer.decode(ArtistData.self))
            case "Album":
                self = .album(try singleValueContainer.decode(AlbumData.self))
            case "Show":
                self = .show(try singleValueContainer.decode(ShowData.self))
            default:
                self = .unknown
            }
        }
    }

    struct PlaylistData: Decodable {
        let uri: String?, name: String?, description: String?, images: Images?, ownerV2: OwnerV2?
        struct Images: Decodable {
            let items: [ImageItem]?
            struct ImageItem: Decodable { let sources: [ImageSource]? }
        }
        struct OwnerV2: Decodable {
            let data: OwnerData?
            struct OwnerData: Decodable { let name: String? }
        }
    }

    struct PseudoPlaylistData: Decodable {
        let uri: String?, name: String?, count: Int?, image: ImageContainer?
        struct ImageContainer: Decodable { let sources: [ImageSource]? }
    }

    struct ArtistData: Decodable {
        let uri: String?, name: String?, visuals: Visuals?
        struct Visuals: Decodable {
            let items: [AvatarImage]?
            struct AvatarImage: Decodable { let sources: [ImageSource]? }
        }
    }

    struct AlbumData: Decodable {
        let uri: String?, name: String?, artists: Artists?, coverArt: CoverArt?
        struct Artists: Decodable { let items: [ArtistItem]? }
        struct CoverArt: Decodable { let sources: [ImageSource]? }
    }

    struct ShowData: Decodable {
        let uri: String?, name: String?, publisher: Publisher?, coverArt: CoverArt?
        struct Publisher: Decodable { let name: String? }
        struct CoverArt: Decodable { let sources: [ImageSource]? }
    }
}

// MARK: - Liked Songs Response
struct LikedSongsResponse: Decodable {
    let data: DataClass
    struct DataClass: Decodable { let me: Me }
    struct Me: Decodable { let library: Library }
    struct Library: Decodable { let tracks: TrackPage }
}

struct TrackPage: Decodable {
    let totalCount: Int
    let items: [LikedSongItem]
}

struct LikedSongItem: Decodable {
    let track: TrackWrapper
    let addedAtInfo: SpotifyPlaylistDetailsResponse.AddedAt?

    enum CodingKeys: String, CodingKey {
        case track, addedAtInfo = "addedAt"
    }

    var addedAt: TimeInterval? {
        guard let isoString = addedAtInfo?.isoString else { return nil }
        return SpotifyDateParsing.timeInterval(from: isoString)
    }
}

struct TrackWrapper: Decodable {
    let uri: String
    let data: SpotifyPlaylistDetailsResponse.ItemData

    enum CodingKeys: String, CodingKey {
        case uri = "_uri"
        case data
    }
}

// MARK: - Artist Details Response (/pathfinder/v1/query?operationName=queryArtistOverview)
struct ArtistDetailsResponse: Decodable {
    let data: DataClass
    struct DataClass: Decodable { let artistUnion: ArtistUnion }
    struct ArtistUnion: Decodable {
        let id: String, uri: String, profile: Profile, visuals: Visuals
        struct Profile: Decodable {
            let name: String, biography: Biography
            struct Biography: Decodable { let text: String }
        }
        struct Visuals: Decodable {
            let avatarImage: AvatarImage?
            struct AvatarImage: Decodable { let sources: [ImageSource] }
        }
    }
}

// MARK: - Shared/Generic Sub-Models
struct ArtistCollection: Decodable, Hashable {
    let items: [ArtistItem]
}
struct ImageSource: Decodable, Hashable { let url: String }
struct ArtistItem: Decodable, Hashable {
    let uri: String
    let profile: Profile
    struct Profile: Decodable, Hashable { let name: String }
}

struct PlayOrigin: Codable {
    let featureIdentifier: String?
    let featureVersion: String?
    let referrerIdentifier: String?
    let deviceIdentifier: String?
}

// MARK: - Authentication Models

struct AccessTokenResponse: Codable {
    let clientId: String?
    let accessToken: String?
    let accessTokenExpirationTimestampMs: Int?
    let isAnonymous: Bool?
}

struct ClientTokenResponse: Codable {
    let responseType: String
    let grantedToken: GrantedToken
}

struct GrantedToken: Codable {
    let token: String
    let expiresAfterSeconds: Int
    let refreshAfterSeconds: Int
    let domains: [DomainInfo]
}

struct DomainInfo: Codable {
    let domain: String
}

struct LoginData: Codable {
    let redirectUrl: String?
}

// MARK: - TOTP Models
struct RemoteTotpSecrets: Decodable {
    let secrets: [String: [Int]]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.secrets = try container.decode([String: [Int]].self)
    }
}

// MARK: - Helper Models
struct AirPlayDevice: Identifiable, Hashable, Equatable {
    var id: String { name }
    let name: String
    let kind: MusicEAPD
    let isSelected: Bool
    let volume: Int?

    var iconName: String {
        switch kind {
        case .computer: return "desktopcomputer"
        case .airPortExpress: return "airplayaudio"
        case .appleTV: return "appletv"
        case .homePod: return "homepod.2.fill"
        case .bluetoothDevice: return "headphones"
        default: return "speaker.fill"
        }
    }
}

struct ActiveSpotifyDeviceState {
    let name: String
    let type: String
    let volumePercent: Int?
    let iconName: String
    let canControlVolume: Bool
}

enum PlaybackResult {
    case success
    case failure(reason: String)
    case requiresPremium
    case requiresSpotifyAppOpen
}

// MARK: - Native Search Response Models
struct NativeSearchResponse: Decodable {
    let data: NativeSearchData?
}

struct NativeSearchData: Decodable {
    let searchV2: NativeSearchV2?
}

struct NativeSearchV2: Decodable {
    let tracksV2: NativeTracksV2?
}

struct NativeTracksV2: Decodable {
    let totalCount: Int
    let items: [NativeSearchItem]?
}

struct NativeSearchItem: Decodable {
    let itemV2: NativeSearchItemData

    enum CodingKeys: String, CodingKey {
        case itemV2 = "item"
    }
}

struct NativeSearchItemData: Decodable {
    let data: NativeTrackData
}

struct NativeTrackData: Decodable {
    let uri: String
    let name: String?
    let albumOfTrack: NativeAlbumOfTrack?
    let artists: NativeArtists?
    let duration: NativeDuration?
}

struct NativeAlbumOfTrack: Decodable {
    let name: String
    let coverArt: NativeCoverArt
}

struct NativeCoverArt: Decodable {
    let sources: [NativeArtSource]
}

struct NativeArtSource: Decodable {
    let url: String
}

struct NativeArtists: Decodable {
    let items: [NativeArtistItem]
}

struct NativeArtistItem: Decodable {
    let profile: NativeArtistProfile
}

struct NativeArtistProfile: Decodable {
    let name: String
}

struct NativeDuration: Decodable {
    let totalMilliseconds: Int
}

struct HydratedPlaylistItem: Identifiable, Hashable {
    static func == (lhs: HydratedPlaylistItem, rhs: HydratedPlaylistItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String { playlistItem.uid }

    let playlistItem: SpotifyPlaylistDetailsResponse.PlaylistItem
    let trackDetails: SpotifyTrackDetailsResponse.TrackUnion?
}
