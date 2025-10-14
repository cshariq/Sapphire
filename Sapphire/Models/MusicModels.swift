//
//  MusicModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02
//

import Foundation

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
    enum CodingKeys: String, CodingKey {
        case id, product, displayName = "display_name"
    }
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
    let profile: Profile
    struct Profile: Decodable {
        let email: String, gender: String, birthdate: String, country: String, username: String, displayName: String?
    }
}

// MARK: - Native Player State (/connect-state/v1/devices/hobs_...) & WebSocket
struct SpotifyNativePlayerStateResponse: Decodable {
    let activeDeviceId: String?
    let playerState: PlayerState
    let devices: [String: SpotifyNativeDevice]
}

struct PlayerState: Decodable {
    var track: Track?
    let isPlaying: Bool?
    let isPaused: Bool?
    let options: Options?
    let prevTracks: [Track]?
    let nextTracks: [Track]?
    let contextUri: String?
    let playOrigin: PlayOrigin?

    struct Options: Decodable {
        let shufflingContext: Bool
        let repeatingContext: Bool
        let repeatingTrack: Bool
    }

    struct Track: Decodable, Hashable {
        let uri: String
        let uid: String
        var metadata: Metadata?

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

        let allArtistItems = details.artists.items + details.otherArtists.items

        if !allArtistItems.isEmpty {
            updatedMetadata.artistUri = allArtistItems.first?.uri
            updatedMetadata.artistName = allArtistItems.map { $0.profile.name }.joined(separator: ", ")
        }

        updatedMetadata.title = details.name
        updatedMetadata.albumTitle = details.albumOfTrack.name

        let bestImage = details.albumOfTrack.coverArt.sources.max { ($0.width ?? 0) < ($1.width ?? 0) }
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
        let albumOfTrack: AlbumOfTrack
        let artists: ArtistCollection
        let otherArtists: ArtistCollection

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

        struct Content: Decodable {
            let totalCount: Int
            var items: [PlaylistItem]
        }
    }

    struct PlaylistItem: Decodable, Equatable {
        let uid: String
        let itemV2: ItemV2
        let addedAtInfo: AddedAt?

        enum CodingKeys: String, CodingKey {
            case uid, itemV2, addedAtInfo = "addedAt"
        }

        var addedAt: TimeInterval? {
            guard let isoString = addedAtInfo?.isoString else { return nil }
            return spotifyDateFormatter.date(from: isoString)?.timeIntervalSince1970
        }

        static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
            return lhs.uid == rhs.uid
        }
    }

    struct AddedAt: Decodable {
        let isoString: String
    }

    struct ItemV2: Decodable {
        var data: ItemData
    }

    struct ItemData: Decodable {
        var uri: String?
        let name: String
        let albumOfTrack: AlbumOfTrack
        let artists: ArtistCollection
        let playcount: String?

        var playcountInt: Int? {
            guard let playcount = self.playcount, let count = Int(playcount) else { return nil }
            return count
        }

        var imageURL: URL? {
            return albumOfTrack.coverArt.bestImageURL
        }
    }

    struct ImageCollection: Decodable {
        let items: [ImageItem]?
        let sources: [ImageSource]?

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
        let name: String
        let coverArt: ImageCollection
        let publishDate: PublishDate?
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
    struct Library: Decodable { let items: [LibraryItem]? }
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
        return spotifyDateFormatter.date(from: isoString)?.timeIntervalSince1970
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
    let name: String
    let albumOfTrack: NativeAlbumOfTrack
    let artists: NativeArtists
    let duration: NativeDuration
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