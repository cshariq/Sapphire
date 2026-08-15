//
//  SpotifyExtendedAPI.swift
//  Sapphire
//
//  Pathfinder + spclient endpoints captured from Spotify web player traffic.
//

import Foundation
import SwiftUI

// MARK: - Extended Models

struct SpotifyAccountInfo: Decodable, Equatable {
    let product: String
    let country: String
    let onDemand: Bool
    let catalogue: String
    let ads: Bool

    var isPremium: Bool { product.uppercased() == "PREMIUM" }
    var displayProduct: String { isPremium ? "Premium" : "Free" }

    enum CodingKeys: String, CodingKey {
        case product, country
        case onDemand = "onDemand"
        case catalogue, ads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        product = try container.decodeIfPresent(String.self, forKey: .product) ?? "FREE"
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        onDemand = try container.decodeIfPresent(Bool.self, forKey: .onDemand) ?? false
        catalogue = try container.decodeIfPresent(String.self, forKey: .catalogue) ?? "free"
        ads = try container.decodeIfPresent(Bool.self, forKey: .ads) ?? true
    }
}

struct SpotifyExtractedColor: Decodable, Equatable {
    let hex: String
    let isFallback: Bool

    var swiftUIColor: Color {
        Color(hex: hex) ?? .white
    }
}

struct SpotifyDecoratedTrack: Decodable {
    let uri: String
    let name: String
    let albumOfTrack: Album
    let artists: ArtistItems
    let duration: Duration?

    struct Album: Decodable {
        let name: String
        let uri: String?
        let coverArt: CoverArt?

        enum CodingKeys: String, CodingKey { case name, uri, coverArt }

        init(name: String, uri: String?, coverArt: CoverArt?) {
            self.name = name
            self.uri = uri
            self.coverArt = coverArt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Album"
            uri = try container.decodeIfPresent(String.self, forKey: .uri)
            coverArt = try container.decodeIfPresent(CoverArt.self, forKey: .coverArt)
        }
    }

    struct CoverArt: Decodable {
        let sources: [ImageSource]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sources = try container.decodeIfPresent([ImageSource].self, forKey: .sources) ?? []
        }
        enum CodingKeys: String, CodingKey { case sources }
    }

    struct ImageSource: Decodable {
        let url: String
        let width: Int?
        let height: Int?

        enum CodingKeys: String, CodingKey { case url, width, height }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            width = try container.decodeIfPresent(Int.self, forKey: .width)
                ?? container.decodeIfPresent(Int.self, forKey: .height)
            height = try container.decodeIfPresent(Int.self, forKey: .height)
                ?? width
        }
    }

    struct ArtistItems: Decodable {
        let items: [ArtistItem]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([ArtistItem].self, forKey: .items) ?? []
        }
        enum CodingKeys: String, CodingKey { case items }
    }

    struct ArtistItem: Decodable {
        let uri: String?
        let profile: Profile
        struct Profile: Decodable {
            let name: String
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Artist"
            }
            enum CodingKeys: String, CodingKey { case name }
        }
    }

    struct Duration: Decodable {
        let totalMilliseconds: Int
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalMilliseconds = try container.decodeIfPresent(Int.self, forKey: .totalMilliseconds) ?? 0
        }
        enum CodingKeys: String, CodingKey { case totalMilliseconds }
    }

    var imageURL: URL? {
        guard let url = albumOfTrack.coverArt?.sources.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.url,
              !url.isEmpty else { return nil }
        return URL(string: url)
    }

    var artistName: String {
        let names = artists.items.map(\.profile.name)
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }
}

struct SpotifyRecommendedTrack: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let duration: Int
    let popularity: Int?
    let artists: [Artist]
    let album: Album

    struct Artist: Decodable, Hashable {
        let id: String
        let name: String
        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    struct Album: Decodable, Hashable {
        let id: String
        let name: String
        let imageUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case imageUrl = "largeImageUrl"
        }

        init(id: String, name: String, imageUrl: String?) {
            self.id = id
            self.name = name
            self.imageUrl = imageUrl
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        }
    }

    init(id: String, name: String, uri: String, duration: Int, popularity: Int?, artists: [Artist], album: Album) {
        self.id = id
        self.name = name
        self.uri = uri
        self.duration = duration
        self.popularity = popularity
        self.artists = artists
        self.album = album
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        duration = try container.decode(Int.self, forKey: .duration)
        popularity = try container.decodeIfPresent(Int.self, forKey: .popularity)
        artists = try container.decode([Artist].self, forKey: .artists)
        album = try container.decode(Album.self, forKey: .album)
        let originalId = try container.decodeIfPresent(String.self, forKey: .originalId)
        uri = originalId ?? "spotify:track:\(id)"
    }

    enum CodingKeys: String, CodingKey {
        case id, originalId, name, duration, popularity, artists, album
    }

    var imageURL: URL? {
        guard let imageUrl = album.imageUrl else { return nil }
        return URL(string: imageUrl)
    }

    /// Prefer album context for Connect play; falls back to nil for track-as-context resolution.
    var albumURI: String? {
        if album.id.hasPrefix("spotify:album:") { return album.id }
        if album.id.hasPrefix("spotify:") { return album.id }
        if !album.id.isEmpty { return "spotify:album:\(album.id)" }
        return nil
    }
}

struct SpotifyPlaylistPermissions: Decodable {
    let canEditItems: Bool
    let canEditMetadata: Bool
    let canView: Bool
    let basePermission: String

    enum CodingKeys: String, CodingKey {
        case basePermission
        case currentUserCapabilities
    }

    enum CapKeys: String, CodingKey {
        case canEditItems, canEditMetadata, canView
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basePermission = try container.decodeIfPresent(String.self, forKey: .basePermission) ?? "BLOCKED"
        let caps = try container.nestedContainer(keyedBy: CapKeys.self, forKey: .currentUserCapabilities)
        canEditItems = try caps.decodeIfPresent(Bool.self, forKey: .canEditItems) ?? false
        canEditMetadata = try caps.decodeIfPresent(Bool.self, forKey: .canEditMetadata) ?? false
        canView = try caps.decodeIfPresent(Bool.self, forKey: .canView) ?? true
    }
}

struct SpotifyCanvasInfo: Decodable, Equatable {
    let url: String
    let type: String?

    var videoURL: URL? { URL(string: url) }

    /// True when the Canvas payload points at a looping video (`.cnvs.mp4`), not a thumbnail.
    var isPlayableVideo: Bool {
        let lower = url.lowercased()
        if lower.contains(".cnvs.") || lower.hasSuffix(".mp4") || lower.hasSuffix(".webm") {
            return true
        }
        if let type, type.uppercased().contains("VIDEO") {
            return !lower.contains(".thmb.") && !lower.hasSuffix(".jpg") && !lower.hasSuffix(".jpeg") && !lower.hasSuffix(".png")
        }
        return false
    }
}

struct SpotifyArtistConcert: Decodable, Identifiable, Hashable {
    let uri: String
    let title: String
    let startDateIsoString: String
    let city: String
    let venue: String

    var id: String { uri }

    init(uri: String, title: String, startDateIsoString: String, city: String, venue: String) {
        self.uri = uri
        self.title = title
        self.startDateIsoString = startDateIsoString
        self.city = city
        self.venue = venue
    }

    enum CodingKeys: String, CodingKey {
        case uri, title, startDateIsoString, location
    }

    enum LocationKeys: String, CodingKey {
        case city, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decode(String.self, forKey: .uri)
        title = try container.decode(String.self, forKey: .title)
        startDateIsoString = try container.decode(String.self, forKey: .startDateIsoString)
        let location = try container.nestedContainer(keyedBy: LocationKeys.self, forKey: .location)
        city = try location.decodeIfPresent(String.self, forKey: .city) ?? ""
        venue = try location.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

struct SpotifyRecentlyPlayedItem: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
    let ownerName: String
}

struct SpotifyHomeItem: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
    let subtitle: String?
}

struct SpotifyHomeSection: Identifiable, Hashable {
    let id: String
    let title: String?
    let items: [SpotifyHomeItem]

    init?(from section: SpotifyHomeResponse.SectionItem) {
        let uri = section.uri ?? section.data?.uri ?? UUID().uuidString
        let rawItems = section.sectionItems?.items ?? []
        let mapped: [SpotifyHomeItem] = rawItems.compactMap { item in
            let content = item.content?.data
            let entityURI = content?.uri ?? item.uri
            guard let entityURI, !entityURI.isEmpty else { return nil }
            let name = content?.name ?? "Untitled"
            let owner = content?.ownerV2?.data?.name
            let imageURL = content?.resolvedImageURL
            return SpotifyHomeItem(
                id: entityURI,
                name: name,
                uri: entityURI,
                imageURL: imageURL,
                subtitle: owner
            )
        }
        guard !mapped.isEmpty else { return nil }
        self.id = uri
        self.title = section.data?.title ?? section.data?.headerEntity?.data?.profile?.name
        self.items = mapped
    }
}

// MARK: - Home Pathfinder response

struct SpotifyHomeResponse: Decodable {
    let data: DataNode?

    struct DataNode: Decodable {
        let home: HomeNode?
    }

    struct HomeNode: Decodable {
        let greeting: Greeting?
        let sectionContainer: SectionContainer?
    }

    struct Greeting: Decodable {
        let transformedLabel: String?
        let translatedBaseText: String?
    }

    struct SectionContainer: Decodable {
        let sections: Sections?
    }

    struct Sections: Decodable {
        let items: [SectionItem]?
        let totalCount: Int?
    }

    struct SectionItem: Decodable {
        let uri: String?
        let sectionItems: SectionItems?
        let data: SectionData?
    }

    struct SectionData: Decodable {
        let uri: String?
        let title: String?
        let headerEntity: HeaderEntity?
    }

    struct HeaderEntity: Decodable {
        let data: HeaderEntityData?
    }

    struct HeaderEntityData: Decodable {
        let profile: ProfileName?
    }

    struct ProfileName: Decodable {
        let name: String?
    }

    struct SectionItems: Decodable {
        let items: [ContentWrapper]?
        let totalCount: Int?
    }

    struct ContentWrapper: Decodable {
        let uri: String?
        let content: ContentNode?
    }

    struct ContentNode: Decodable {
        let data: ContentData?
    }

    struct ContentData: Decodable {
        let uri: String?
        let name: String?
        let description: String?
        let images: FlexibleHomeImage?
        let ownerV2: OwnerWrapper?

        var resolvedImageURL: URL? {
            images?.url
        }
    }

    struct OwnerWrapper: Decodable {
        let data: OwnerData?
    }

    struct OwnerData: Decodable {
        let name: String?
        let uri: String?
    }

    /// Home cards expose images as a URL string, nested sources, or items[].sources[].
    enum FlexibleHomeImage: Decodable {
        case urlString(String)
        case nested(NestedImages)

        struct NestedImages: Decodable {
            let items: [ImageItem]?
            let sources: [ImageSource]?

            struct ImageItem: Decodable {
                let sources: [ImageSource]?
            }

            struct ImageSource: Decodable {
                let url: String?
            }
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let string = try? single.decode(String.self) {
                self = .urlString(string)
                return
            }
            self = .nested(try NestedImages(from: decoder))
        }

        var url: URL? {
            switch self {
            case .urlString(let string):
                return URL(string: string)
            case .nested(let nested):
                if let direct = nested.sources?.compactMap(\.url).first {
                    return URL(string: direct)
                }
                if let nestedURL = nested.items?.compactMap({ $0.sources?.compactMap(\.url).first }).first {
                    return URL(string: nestedURL)
                }
                return nil
            }
        }
    }
}

struct SpotifyArtistMerch: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
    let price: String?
}

struct SpotifyTrackArtistCredit: Identifiable, Hashable {
    let id: String
    let uri: String
    let name: String
    let role: String?
}

struct SpotifyArtistProfile: Equatable {
    let uri: String
    let name: String
    let biography: String
    let monthlyListeners: Int?
    let followers: Int?
    let headerImageURL: URL?
    let avatarURL: URL?
    let isVerified: Bool
    let topCities: [String]
    let merch: [SpotifyArtistMerch]

    init(
        uri: String,
        name: String,
        biography: String,
        monthlyListeners: Int?,
        followers: Int?,
        headerImageURL: URL?,
        avatarURL: URL?,
        isVerified: Bool,
        topCities: [String],
        merch: [SpotifyArtistMerch] = []
    ) {
        self.uri = uri
        self.name = name
        self.biography = biography
        self.monthlyListeners = monthlyListeners
        self.followers = followers
        self.headerImageURL = headerImageURL
        self.avatarURL = avatarURL
        self.isVerified = isVerified
        self.topCities = topCities
        self.merch = merch
    }
}

struct SpotifySimilarAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let artistName: String
    let imageURL: URL?
    let year: Int?
}

enum SpotifyGeohash {
    /// Encode lat/lon to a geohash used by ArtistConcerts Pathfinder queries.
    static func encode(latitude: Double, longitude: Double, precision: Int = 8) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bit = 0
        var ch = 0
        var isLon = true
        while hash.count < precision {
            if isLon {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid { ch = (ch << 1) | 1; lonRange.0 = mid }
                else { ch <<= 1; lonRange.1 = mid }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid { ch = (ch << 1) | 1; latRange.0 = mid }
                else { ch <<= 1; latRange.1 = mid }
            }
            isLon.toggle()
            bit += 1
            if bit == 5 {
                hash.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return hash
    }
}

// MARK: - Color Hex Helper

private extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Extended API

extension SpotifyPrivateAPIManager {

    // Published extended state
    @MainActor
    func publishExtendedState(
        accountInfo: SpotifyAccountInfo? = nil,
        canvas: SpotifyCanvasInfo? = nil,
        concerts: [SpotifyArtistConcert]? = nil,
        recommendations: [SpotifyRecommendedTrack]? = nil,
        recentlyPlayed: [SpotifyRecentlyPlayedItem]? = nil,
        smartShuffleAvailable: Bool? = nil,
        hasUnreadNotifications: Bool? = nil,
        jamSessionActive: Bool? = nil,
        libraryImportEligible: Bool? = nil,
        popularReleases: [SpotifyPopularRelease]? = nil,
        nowPlayingArtist: SpotifyArtistProfile? = nil,
        similarAlbums: [SpotifySimilarAlbum]? = nil,
        relatedTracks: [SpotifyRecommendedTrack]? = nil,
        trackArtistCredits: [SpotifyTrackArtistCredit]? = nil
    ) {
        if let accountInfo { self.accountInfo = accountInfo }
        if let canvas { self.currentCanvas = canvas }
        if let concerts { self.artistConcerts = concerts }
        if let recommendations { self.playlistRecommendations = recommendations }
        if let recentlyPlayed { self.recentlyPlayedItems = recentlyPlayed }
        if let smartShuffleAvailable { self.smartShuffleAvailable = smartShuffleAvailable }
        if let hasUnreadNotifications { self.hasUnreadNotifications = hasUnreadNotifications }
        if let jamSessionActive { self.jamSessionActive = jamSessionActive }
        if let libraryImportEligible { self.libraryImportEligible = libraryImportEligible }
        if let popularReleases { self.popularReleases = popularReleases }
        if let nowPlayingArtist { self.nowPlayingArtist = nowPlayingArtist }
        if let similarAlbums { self.similarAlbums = similarAlbums }
        if let relatedTracks { self.relatedTracks = relatedTracks }
        if let trackArtistCredits { self.trackArtistCredits = trackArtistCredits }
    }

    func refreshExtendedSessionData() async {
        guard isLoggedIn else { return }
        async let account = fetchAccountAttributes()
        async let profile = fetchProfileAttributes()
        async let notifications = fetchUnreadNotificationStatus()
        _ = await (account, profile, notifications)
    }

    func fetchAccountAttributes() async -> SpotifyAccountInfo? {
        do {
            let response: AccountAttributesResponse = try await pathfinderQuery(
                operationName: "accountAttributes",
                variables: [:],
                sendAsBody: true,
                useV2Endpoint: true
            )
            let attrs = response.data.me.account
            let info = SpotifyAccountInfo(
                product: attrs.product,
                country: attrs.country,
                onDemand: attrs.attributes.onDemand ?? false,
                catalogue: attrs.attributes.catalogue ?? "free",
                ads: attrs.attributes.ads ?? true
            )
            publishExtendedState(accountInfo: info)
            return info
        } catch {
            print("[SpotifyExtendedAPI] accountAttributes failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchDynamicColors(for imageURIs: [String]) async -> [String] {
        guard !imageURIs.isEmpty else { return [] }
        do {
            let response: DynamicColorsResponse = try await pathfinderQuery(
                operationName: "getDynamicColorsByUris",
                variables: ["imageUris": imageURIs]
            )
            return response.data.dynamicColors.compactMap { swatch in
                swatch.dark?.textBase?.hex ?? swatch.light?.textBase?.hex ?? swatch.dark?.backgroundBase?.hex
            }
        } catch {
            print("[SpotifyExtendedAPI] getDynamicColorsByUris failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchProfileAttributes() async -> String? {
        do {
            let response: ProfileAttributesResponse = try await pathfinderQuery(
                operationName: "profileAttributes",
                variables: [:]
            )
            let name = response.data.me.profile.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = response.data.me.profile.username
            await MainActor.run {
                guard var profile = self.userProfile else { return }
                if let name, !name.isEmpty {
                    let existing = profile.profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if existing.isEmpty {
                        profile.profile.displayName = name
                        self.userProfile = profile
                    }
                }
            }
            if let username, !username.isEmpty {
                await fetchProfileFollowerCount(username: username)
            } else if let username = userProfile?.profile.username, !username.isEmpty {
                await fetchProfileFollowerCount(username: username)
            }
            return response.data.me.profile.uri ?? response.data.me.profile.username
        } catch {
            print("[SpotifyExtendedAPI] profileAttributes failed: \(error.localizedDescription)")
            if let username = userProfile?.profile.username, !username.isEmpty {
                await fetchProfileFollowerCount(username: username)
            }
            return nil
        }
    }

    /// Public profile view endpoint — returns follower totals for the hub pill.
    func fetchProfileFollowerCount(username: String) async {
        guard let client = wgSpclientClient ?? spclientClient else { return }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let path = "/user-profile-view/v3/profile/\(encoded)?playlist_limit=0&artist_limit=0&episode_limit=0&market=from_token"
        do {
            let response = try await client.get(path: path)
            guard response.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else { return }

            let count: Int? = {
                if let n = json["followers_count"] as? Int { return n }
                if let n = json["followersCount"] as? Int { return n }
                if let n = (json["followers_count"] as? NSNumber)?.intValue { return n }
                if let followers = json["followers"] as? [String: Any] {
                    if let n = followers["total"] as? Int { return n }
                    if let n = followers["count"] as? Int { return n }
                    if let n = (followers["total"] as? NSNumber)?.intValue { return n }
                }
                if let n = json["total_public_playlists_count"] as? Int, json["followers_count"] == nil {
                    // Not followers — ignore
                    return nil
                }
                return nil
            }()

            await MainActor.run {
                if let count {
                    self.profileFollowerCount = count
                }
            }
        } catch {
            print("[SpotifyExtendedAPI] profile follower fetch failed: \(error.localizedDescription)")
        }
    }

    func fetchRelatedTracks(for trackURI: String, limit: Int = 8) async -> [SpotifyRecommendedTrack] {
        do {
            let response: InternalLinkRecommenderResponse = try await pathfinderQuery(
                operationName: "internalLinkRecommenderTrack",
                variables: ["uri": trackURI, "limit": limit]
            )
            let tracks = response.data.seoRecommendedTrack.items.compactMap { item -> SpotifyRecommendedTrack? in
                guard let data = item.data else { return nil }
                return SpotifyRecommendedTrack(
                    id: data.id ?? SpotifyIDConverter.rawID(from: data.uri),
                    name: data.name,
                    uri: data.uri,
                    duration: data.duration?.totalMilliseconds ?? 0,
                    popularity: nil,
                    artists: data.artists?.items.map {
                        .init(id: $0.id ?? SpotifyIDConverter.rawID(from: $0.uri), name: $0.profile.name)
                    } ?? [],
                    album: .init(
                        id: data.albumOfTrack?.uri
                            ?? data.albumOfTrack?.id.map { $0.hasPrefix("spotify:") ? $0 : "spotify:album:\($0)" }
                            ?? "",
                        name: data.name,
                        imageUrl: data.albumOfTrack?.coverArt?.sources.first?.url
                    )
                )
            }
            await MainActor.run {
                guard self.playerState?.track?.uri == trackURI else { return }
                self.publishExtendedState(relatedTracks: tracks)
            }
            return tracks
        } catch {
            print("[SpotifyExtendedAPI] internalLinkRecommenderTrack failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchSimilarAlbums(for trackURI: String, limit: Int = 20) async -> [SpotifySimilarAlbum] {
        do {
            let response: SimilarAlbumsResponse = try await pathfinderQuery(
                operationName: "similarAlbumsBasedOnThisTrack",
                variables: ["uri": trackURI, "limit": limit, "albumsOnly": true]
            )
            let albums = response.data.seoRecommendedTrackAlbum.items.compactMap { item -> SpotifySimilarAlbum? in
                guard let data = item.data else { return nil }
                let image = data.coverArt?.sources.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.url
                return SpotifySimilarAlbum(
                    id: data.uri,
                    name: data.name,
                    uri: data.uri,
                    artistName: data.artists?.items.first?.profile.name ?? "Unknown",
                    imageURL: image.flatMap(URL.init(string:)),
                    year: data.date?.year
                )
            }
            await MainActor.run {
                guard self.playerState?.track?.uri == trackURI else { return }
                self.publishExtendedState(similarAlbums: albums)
            }
            return albums
        } catch {
            print("[SpotifyExtendedAPI] similarAlbumsBasedOnThisTrack failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Album track list via Pathfinder `queryAlbumTracks`.
    func fetchAlbumTracks(albumURI: String, limit: Int = 50) async -> [SpotifyRecommendedTrack] {
        do {
            let response: AlbumTracksResponse = try await pathfinderQuery(
                operationName: "queryAlbumTracks",
                variables: [
                    "uri": albumURI,
                    "offset": 0,
                    "limit": limit
                ]
            )
            return response.data.albumUnion?.tracksV2?.items.compactMap { item -> SpotifyRecommendedTrack? in
                guard let track = item.track ?? item.data else { return nil }
                let uri = track.uri ?? ""
                guard !uri.isEmpty else { return nil }
                return SpotifyRecommendedTrack(
                    id: SpotifyIDConverter.rawID(from: uri),
                    name: track.name ?? "Track",
                    uri: uri,
                    duration: track.duration?.totalMilliseconds ?? 0,
                    popularity: nil,
                    artists: track.artists?.items.map {
                        .init(id: SpotifyIDConverter.rawID(from: $0.uri ?? ""), name: $0.profile?.name ?? $0.profileName ?? "Artist")
                    } ?? [],
                    album: .init(id: SpotifyIDConverter.rawID(from: albumURI), name: "Album", imageUrl: nil)
                )
            } ?? []
        } catch {
            print("[SpotifyExtendedAPI] queryAlbumTracks failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Credits / featured artists for the current track (Pathfinder `queryTrackArtists`).
    func fetchTrackArtists(for trackURI: String) async -> [SpotifyTrackArtistCredit] {
        do {
            let response: TrackArtistsResponse = try await pathfinderQuery(
                operationName: "queryTrackArtists",
                variables: ["trackUri": trackURI]
            )
            let credits = response.data.trackUnion?.artists?.items.compactMap { item -> SpotifyTrackArtistCredit? in
                guard let uri = item.uri ?? item.data?.uri else { return nil }
                let name = item.profile?.name ?? item.data?.profile?.name ?? "Artist"
                return SpotifyTrackArtistCredit(
                    id: uri,
                    uri: uri,
                    name: name,
                    role: item.role ?? item.data?.role
                )
            } ?? []
            publishExtendedState(trackArtistCredits: credits)
            return credits
        } catch {
            print("[SpotifyExtendedAPI] queryTrackArtists failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Whether the user has banned this artist (`collection/v2/contains` set=`artistban`).
    func isArtistBanned(_ artistURI: String) async -> Bool {
        let results = await collectionContains(set: "artistban", uris: [artistURI])
        return results.first ?? false
    }

    func fetchExtractedColors(for imageURIs: [String]) async -> [SpotifyExtractedColor] {
        guard !imageURIs.isEmpty else { return [] }
        // Prefer dynamic colors when available; fall back to extractedColors.
        let dynamic = await fetchDynamicColors(for: imageURIs)
        if !dynamic.isEmpty {
            return dynamic.map { SpotifyExtractedColor(hex: $0, isFallback: false) }
        }
        do {
            let response: ExtractedColorsResponse = try await pathfinderQuery(
                operationName: "fetchExtractedColors",
                variables: ["imageUris": imageURIs],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.extractedColors.map { $0.colorRaw }
        } catch {
            print("[SpotifyExtendedAPI] fetchExtractedColors failed: \(error.localizedDescription)")
            return []
        }
    }

    func areEntitiesInLibrary(uris: [String]) async -> [Bool] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: LibraryLookupResponse = try await pathfinderQuery(
                operationName: "areEntitiesInLibrary",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.lookup.map { $0.data?.saved ?? false }
        } catch {
            print("[SpotifyExtendedAPI] areEntitiesInLibrary failed: \(error.localizedDescription)")
            return Array(repeating: false, count: uris.count)
        }
    }

    func isTrackLiked(uri: String) async -> Bool {
        let contains = await collectionContains(set: "tracks", uris: [uri])
        return contains.first ?? false
    }

    func searchSuggestions(query: String) async -> [SpotifySearchSuggestion] {
        let variables: [String: Any] = [
            "query": query,
            "limit": 30,
            "numberOfTopResults": 30,
            "offset": 0,
            "includeAuthors": true,
            "includeAlbumPreReleases": true,
            "includeEpisodeContentRatingsV2": true
        ]
        do {
            let response: SpotifySearchSuggestionsResponse = try await pathfinderQuery(
                operationName: "searchSuggestions",
                variables: variables,
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            return response.suggestions
        } catch {
            print("[SpotifyExtendedAPI] searchSuggestions failed: \(error.localizedDescription)")
            return []
        }
    }

    func searchTopResults(query: String) async -> SpotifySearchTopResults {
        let variables: [String: Any] = [
            "query": query,
            "limit": 50,
            "offset": 0,
            "numberOfTopResults": 50,
            "includeArtistHasConcertsField": false,
            "includeAudiobooks": true,
            "includeAuthors": true,
            "includePreReleases": true,
            "includeAlbumPreReleases": true,
            "includeEpisodeContentRatingsV2": true,
            "sectionFilters": ["GENERIC", "VIDEO_CONTENT"]
        ]
        do {
            let response: SpotifySearchTopResultsResponse = try await pathfinderQuery(
                operationName: "searchTopResultsList",
                variables: variables,
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            return response.parsed
        } catch {
            print("[SpotifyExtendedAPI] searchTopResultsList failed: \(error.localizedDescription)")
            // Fallback: classic searchDesktop for tracks only.
            if let track = await searchForTrack(title: query, artist: "") {
                return SpotifySearchTopResults(
                    tracks: [
                        SpotifySearchTrack(
                            id: track.id,
                            name: track.name,
                            uri: track.uri,
                            artists: track.artists.map(\.name).joined(separator: ", "),
                            imageURL: track.imageURL
                        )
                    ],
                    artists: [],
                    albums: [],
                    playlists: []
                )
            }
            return .empty
        }
    }

    /// Full artist hub via `queryArtistOverview` (bio, top tracks, discography, featuring).
    func fetchArtistOverview(uri: String) async -> SpotifyArtistOverview? {
        do {
            let response: ArtistOverviewResponse = try await pathfinderQuery(
                operationName: "queryArtistOverview",
                variables: [
                    "uri": uri,
                    "locale": "",
                    "preReleaseV2": true
                ],
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            return response.overview
        } catch {
            print("[SpotifyExtendedAPI] queryArtistOverview failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns whether Spotify metadata reports lyrics for the track.
    func trackHasLyrics(trackId: String) async -> Bool? {
        guard let meta = await fetchTrackMetadata(trackId: trackId) else { return nil }
        return meta.hasLyrics
    }

    func fetchHomeSections() async -> [SpotifyHomeSection] {
        let timeZone = TimeZone.current.identifier
        let variables: [String: Any] = [
            "homeEndUserIntegration": "INTEGRATION_WEB_PLAYER",
            "timeZone": timeZone,
            "sp_t": UUID().uuidString,
            "facet": "",
            "sectionItemsLimit": 20,
            "includeEpisodeContentRatingsV2": true
        ]
        do {
            let response: SpotifyHomeResponse = try await pathfinderQuery(
                operationName: "home",
                variables: variables,
                sendAsBody: true,
                cachePolicy: .fetchIgnoringCacheData,
                useV2Endpoint: true
            )
            let greeting = response.data?.home?.greeting?.transformedLabel
                ?? response.data?.home?.greeting?.translatedBaseText
            let sections = response.data?.home?.sectionContainer?.sections?.items ?? []
            let mapped = sections.compactMap { SpotifyHomeSection(from: $0) }
            await MainActor.run {
                self.homeGreeting = greeting
                self.homeSections = mapped
                // Seed recently-played shelf from the first home section when present.
                if let first = mapped.first, !first.items.isEmpty {
                    self.recentlyPlayedItems = first.items.map {
                        SpotifyRecentlyPlayedItem(
                            id: $0.id,
                            name: $0.name,
                            uri: $0.uri,
                            imageURL: $0.imageURL,
                            ownerName: $0.subtitle ?? ""
                        )
                    }
                }
            }
            return mapped
        } catch {
            print("[SpotifyExtendedAPI] home fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    func decorateContextTracks(uris: [String]) async -> [SpotifyDecoratedTrack] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: DecorateTracksResponse = try await pathfinderQuery(
                operationName: "decorateContextTracks",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.tracks
        } catch {
            print("[SpotifyExtendedAPI] decorateContextTracks failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchPlaylistPermissions(uri: String) async -> SpotifyPlaylistPermissions? {
        do {
            let response: PlaylistPermissionsResponse = try await pathfinderQuery(
                operationName: "playlistPermissions",
                variables: ["uri": uri],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.playlistV2
        } catch {
            print("[SpotifyExtendedAPI] playlistPermissions failed: \(error.localizedDescription)")
            return nil
        }
    }

    func checkSmartShuffleAvailable(uri: String) async -> Bool {
        do {
            let response: SmartShuffleResponse = try await pathfinderQuery(
                operationName: "smartShuffle",
                variables: ["uris": [uri]],
                sendAsBody: true,
                useV2Endpoint: true
            )
            let available = response.data.lookup.first?.data?.smartShuffle?.available ?? false
            publishExtendedState(smartShuffleAvailable: available)
            return available
        } catch {
            print("[SpotifyExtendedAPI] smartShuffle failed: \(error.localizedDescription)")
            return false
        }
    }

    func fetchRecentlyPlayedEntities(uris: [String]) async -> [SpotifyRecentlyPlayedItem] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: RecentlyPlayedResponse = try await pathfinderQuery(
                operationName: "fetchEntitiesForRecentlyPlayed",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            let items = response.data.lookup.compactMap { wrapper -> SpotifyRecentlyPlayedItem? in
                guard let playlist = wrapper.data, let uri = playlist.uri else { return nil }
                let imageURL = playlist.images?.items.first?.sources.first.flatMap { URL(string: $0.url) }
                return SpotifyRecentlyPlayedItem(
                    id: uri,
                    name: playlist.name ?? "Playlist",
                    uri: uri,
                    imageURL: imageURL,
                    ownerName: playlist.ownerV2?.data?.name ?? "Spotify"
                )
            }
            publishExtendedState(recentlyPlayed: items)
            return items
        } catch {
            print("[SpotifyExtendedAPI] fetchEntitiesForRecentlyPlayed failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchCanvas(for trackURI: String) async -> SpotifyCanvasInfo? {
        do {
            let response: CanvasResponse = try await pathfinderQuery(
                operationName: "canvas",
                variables: ["trackUri": trackURI],
                sendAsBody: true,
                useV2Endpoint: true
            )
            guard let canvas = response.data.trackUnion.canvas else {
                await MainActor.run {
                    if self.playerState?.track?.uri == trackURI {
                        self.currentCanvas = nil
                    }
                }
                return nil
            }
            let info = SpotifyCanvasInfo(url: canvas.url, type: canvas.type)
            guard info.isPlayableVideo else {
                print("[SpotifyExtendedAPI] canvas returned non-video URL, ignoring: \(canvas.url)")
                await MainActor.run {
                    if self.playerState?.track?.uri == trackURI {
                        self.currentCanvas = nil
                    }
                }
                return nil
            }
            await MainActor.run {
                guard self.playerState?.track?.uri == trackURI else { return }
                self.publishExtendedState(canvas: info)
            }
            return info
        } catch {
            print("[SpotifyExtendedAPI] canvas failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchArtistConcerts(artistURI: String, trackURI: String) async -> [SpotifyArtistConcert] {
        // Prefer geo-targeted ArtistConcerts when we can resolve a geohash; always enrich NPV artist profile.
        async let npvTask: (SpotifyArtistProfile?, [SpotifyArtistConcert]) = fetchNpvArtist(artistURI: artistURI, trackURI: trackURI)
        async let geoTask = fetchGeoConcerts(artistURI: artistURI)

        let (profile, npvConcerts) = await npvTask
        let geoConcerts = await geoTask
        let concerts = geoConcerts.isEmpty ? npvConcerts : geoConcerts
        if let profile {
            publishExtendedState(concerts: concerts, nowPlayingArtist: profile)
        } else {
            publishExtendedState(concerts: concerts)
        }
        return concerts
    }

    private func fetchNpvArtist(artistURI: String, trackURI: String) async -> (SpotifyArtistProfile?, [SpotifyArtistConcert]) {
        let variables: [String: Any] = [
            "artistUri": artistURI,
            "trackUri": trackURI,
            "contributorsLimit": 10,
            "contributorsOffset": 0,
            "enableRelatedVideos": true,
            "enableRelatedAudioTracks": false
        ]
        do {
            let response: NpvArtistResponse = try await pathfinderQuery(
                operationName: "queryNpvArtist",
                variables: variables
            )
            let union = response.data.artistUnion
            let header = union.headerImage?.data?.sources.max(by: { ($0.maxWidth ?? 0) < ($1.maxWidth ?? 0) })?.url
            let avatar = union.visuals?.avatarImage?.sources?.first?.url
            let profile = SpotifyArtistProfile(
                uri: union.uri ?? artistURI,
                name: union.profile?.name ?? "Artist",
                biography: union.profile?.biography?.text ?? "",
                monthlyListeners: union.stats?.monthlyListeners,
                followers: union.stats?.followers,
                headerImageURL: header.flatMap(URL.init(string:)),
                avatarURL: avatar.flatMap(URL.init(string:)),
                isVerified: union.onPlatformReputationTrait?.verification?.isVerified ?? false,
                topCities: union.stats?.topCities?.items.prefix(3).map(\.city) ?? [],
                merch: union.goods?.merch?.items?.compactMap { item -> SpotifyArtistMerch? in
                    guard let name = item.name, let uri = item.uri else { return nil }
                    return SpotifyArtistMerch(
                        id: uri,
                        name: name,
                        uri: uri,
                        imageURL: item.imageURL.flatMap(URL.init(string:)),
                        price: item.price
                    )
                } ?? []
            )
            let concerts = union.goods?.concerts?.items.compactMap { item -> SpotifyArtistConcert? in
                guard let data = item.data else { return nil }
                return SpotifyArtistConcert(
                    uri: data.uri,
                    title: data.title,
                    startDateIsoString: data.startDateIsoString,
                    city: data.location.city ?? "",
                    venue: data.location.name ?? ""
                )
            } ?? []
            return (profile, concerts)
        } catch {
            print("[SpotifyExtendedAPI] queryNpvArtist failed: \(error.localizedDescription)")
            return (nil, [])
        }
    }

    private func fetchGeoConcerts(artistURI: String) async -> [SpotifyArtistConcert] {
        let geoHash: String
        if let resolved = await fetchUserGeoHash() {
            geoHash = resolved
        } else {
            // Approximate from locale timezone as a soft fallback (NYC-ish default).
            geoHash = "dr5reg"
        }
        do {
            let response: ArtistConcertsResponse = try await pathfinderQuery(
                operationName: "ArtistConcerts",
                variables: [
                    "artistUri": artistURI,
                    "geoHash": geoHash,
                    "includeNearby": true
                ]
            )
            return response.data.artistUnion?.nearby?.concerts?.items.compactMap { item -> SpotifyArtistConcert? in
                guard let data = item.data ?? item.concert else { return nil }
                return SpotifyArtistConcert(
                    uri: data.uri ?? UUID().uuidString,
                    title: data.title ?? data.name ?? "Concert",
                    startDateIsoString: data.startDateIsoString ?? data.date ?? "",
                    city: data.location?.city ?? data.venue?.city ?? "",
                    venue: data.location?.name ?? data.venue?.name ?? ""
                )
            } ?? []
        } catch {
            print("[SpotifyExtendedAPI] ArtistConcerts failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchUserGeoHash() async -> String? {
        do {
            let response: UserLocationResponse = try await pathfinderQuery(
                operationName: "userLocation",
                variables: [:]
            )
            if let hash = response.data.me?.userLocation?.geoHash, !hash.isEmpty {
                return hash
            }
            if let lat = response.data.me?.userLocation?.latitude,
               let lon = response.data.me?.userLocation?.longitude {
                return SpotifyGeohash.encode(latitude: lat, longitude: lon)
            }
        } catch {
            print("[SpotifyExtendedAPI] userLocation failed: \(error.localizedDescription)")
        }
        return nil
    }

    /// Applies Enhance / Smart Shuffle lenses via playlist signals REST API.
    @discardableResult
    func applyPlaylistEnhance(playlistId: String) async -> Bool {
        await MainActor.run { isEnhanceLoading = true }
        defer { Task { @MainActor in self.isEnhanceLoading = false } }
        return await loadPlaylistUsingSignals(playlistId: playlistId)
    }

    /// Play a playlist with Smart Shuffle: enhance lens + Connect shuffle options.
    func playSmartShuffle(playlistURI: String) async -> PlaybackResult {
        let playlistId = SpotifyIDConverter.rawID(from: playlistURI)
        _ = await applyPlaylistEnhance(playlistId: playlistId)
        let result = await connectPlay(
            trackUri: "",
            contextUri: playlistURI,
            trackUid: nil,
            trackIndex: 0
        )
        guard case .success = result else { return result }
        await sendConnectCommand(endpoint: "set_options", extra: ["shuffling_context": true])
        await MainActor.run { self.isSmartShuffleActive = true }
        return .success
    }

    func extendPlaylist(uri: String, skipTrackIDs: [String] = [], numResults: Int = 20) async -> [SpotifyRecommendedTrack] {
        guard let client = wgSpclientClient else { return [] }
        // playlistextender expects raw Base62 track IDs (not spotify:track: URIs).
        let normalizedSkipIDs = skipTrackIDs.map { SpotifyIDConverter.rawID(from: $0) }
        let payload: [String: Any] = [
            "playlistURI": uri.hasPrefix("spotify:") ? uri : "spotify:playlist:\(uri)",
            "trackSkipIDs": normalizedSkipIDs,
            "numResults": numResults
        ]
        do {
            let response = try await client.post(path: "/playlistextender/extendp/", jsonBody: payload)
            let decoded = try JSONDecoder().decode(PlaylistExtenderResponse.self, from: response.body)
            publishExtendedState(recommendations: decoded.recommendedTracks)
            return decoded.recommendedTracks
        } catch {
            print("[SpotifyExtendedAPI] playlistextender failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchUnreadNotificationStatus() async -> Bool {
        guard let client = wgSpclientClient else { return false }
        do {
            let response = try await client.get(
                path: "/gander/v2/GetUserHasUnreadNotification",
                queryItems: [URLQueryItem(name: "postFix", value: "a")]
            )
            let decoded = try JSONDecoder().decode(NotificationResponse.self, from: response.body)
            publishExtendedState(hasUnreadNotifications: decoded.userHasUnreadNotification)
            return decoded.userHasUnreadNotification
        } catch {
            return false
        }
    }

    func fetchTrackMetadata(trackId: String) async -> SpotifyTrackMetadata? {
        let rawId = SpotifyIDConverter.rawID(from: trackId)
        // Legacy `/metadata/4/track` no longer returns audio `file` entries (librespot #1622).
        // Prefer `/extended-metadata/v0/extended-metadata` which still embeds TRACK_V4 with OGG files.
        let extended = await fetchTrackMetadataViaExtended(trackId: rawId)
        if let extended, !extended.allAudioFiles.isEmpty {
            return extended
        }

        guard let client = wgSpclientClient else { return extended }
        let gid = SpotifyIDConverter.gid(fromBase62: rawId) ?? rawId
        do {
            let response = try await client.get(
                path: "/metadata/4/track/\(gid)",
                queryItems: [URLQueryItem(name: "market", value: "from_token")],
                additionalHeaders: [
                    "Accept": "application/json",
                    "App-Platform": "WebPlayer"
                ]
            )
            guard !response.body.isEmpty else {
                print("[SpotifyExtendedAPI] track metadata empty for \(rawId)")
                return extended
            }
            if response.body.first != UInt8(ascii: "{") {
                let snippet = String(data: response.body.prefix(80), encoding: .utf8)
                    ?? "binary(\(response.body.count))"
                print("[SpotifyExtendedAPI] track metadata not JSON for \(rawId): \(snippet)")
                return extended
            }
            let decoder = JSONDecoder()
            do {
                let legacy = try decoder.decode(SpotifyTrackMetadata.self, from: response.body)
                if legacy.allAudioFiles.isEmpty {
                    print("[SpotifyExtendedAPI] legacy metadata has 0 files for \(rawId); extended files=\(extended?.allAudioFiles.count ?? -1)")
                    return extended ?? legacy
                }
                return legacy
            } catch {
                let snippet = String(data: response.body.prefix(240), encoding: .utf8)
                    ?? "<binary \(response.body.count) bytes>"
                print("[SpotifyExtendedAPI] track metadata decode failed for \(rawId) (gid=\(gid)): \(error)\nSnippet: \(snippet)")
                return extended
            }
        } catch {
            print("[SpotifyExtendedAPI] track metadata failed for \(rawId) (gid=\(gid)): \(error.localizedDescription)")
            return extended
        }
    }

    /// librespot-compatible TRACK_V4 fetch via extended-metadata (protobuf).
    private func fetchTrackMetadataViaExtended(trackId: String) async -> SpotifyTrackMetadata? {
        guard let client = wgSpclientClient else { return nil }
        let uri = SpotifyIDConverter.uri(type: "track", from: trackId)

        var query = Data()
        query.append(SpotifyProtoWire.writeVarintField(field: 1, 10)) // ExtensionKind.TRACK_V4

        var entity = Data()
        entity.append(SpotifyProtoWire.writeString(field: 1, uri))
        entity.append(SpotifyProtoWire.writeMessage(field: 2, query))

        var header = Data()
        if let country = accountInfo?.country, !country.isEmpty {
            header.append(SpotifyProtoWire.writeString(field: 1, country))
        }
        if let catalogue = accountInfo?.catalogue, !catalogue.isEmpty {
            header.append(SpotifyProtoWire.writeString(field: 2, catalogue))
        }

        var request = Data()
        if !header.isEmpty {
            request.append(SpotifyProtoWire.writeMessage(field: 1, header))
        }
        request.append(SpotifyProtoWire.writeMessage(field: 2, entity))

        var headers: [String: String] = [
            "Content-Type": "application/x-protobuf",
            "Accept": "application/x-protobuf",
            "app-platform": "Desktop"
        ]

        do {
            let response = try await client.post(
                path: "/extended-metadata/v0/extended-metadata",
                bodyData: request,
                additionalHeaders: headers
            )
            guard response.statusCode == 200, !response.body.isEmpty else {
                print("[SpotifyExtendedAPI] extended-metadata HTTP \(response.statusCode) for \(uri) (\(response.body.count) bytes)")
                return nil
            }
            guard let parsed = SpotifyExtendedMetadataParser.parseTrack(fromBatchedResponse: response.body) else {
                print("[SpotifyExtendedAPI] extended-metadata parse yielded no track for \(uri)")
                return nil
            }
            print("[SpotifyExtendedAPI] extended-metadata files=\(parsed.allAudioFiles.count) for \(uri)")
            return parsed
        } catch {
            print("[SpotifyExtendedAPI] extended-metadata failed for \(uri): \(error.localizedDescription)")
            return nil
        }
    }

    func fetchPlaylistRootlist() async -> [SpotifyPlaylist] {
        guard let client = wgSpclientClient,
              let username = userProfile?.profile.username else { return [] }
        do {
            let response = try await client.get(
                path: "/playlist/v2/user/\(username)/rootlist",
                queryItems: [
                    URLQueryItem(name: "decorate", value: "revision,length,attributes,timestamp,owner,capabilities"),
                    URLQueryItem(name: "bustCache", value: String(Int(Date().timeIntervalSince1970 * 1000)))
                ]
            )
            let decoded = try JSONDecoder().decode(PlaylistRootlistResponse.self, from: response.body)
            return decoded.contents.items.compactMap { item in
                guard let uri = item.uri else { return nil }
                let id = uri.components(separatedBy: ":").last ?? uri
                let imageURL = item.attributes?.picture ?? ""
                let fallbackName = uri.components(separatedBy: ":").last?.uppercased() ?? "Playlist"
                return SpotifyPlaylist(
                    id: id,
                    name: item.name ?? fallbackName,
                    uri: uri,
                    images: [SpotifyImage(url: imageURL)],
                    owner: SpotifyUserSimple(id: username, displayName: userProfile?.profile.displayName ?? username, images: nil),
                    collaborators: nil
                )
            }
        } catch {
            print("[SpotifyExtendedAPI] rootlist failed: \(error.localizedDescription)")
            return []
        }
    }

    func hydrateTracksBatch(_ sparseTracks: [PlayerState.Track]) async -> [PlayerState.Track] {
        guard !sparseTracks.isEmpty else { return sparseTracks }
        var result = sparseTracks
        let uris = sparseTracks.map(\.uri)
        let chunks = uris.chunked(into: 50)

        for (chunkIndex, chunk) in chunks.enumerated() {
            let decorated = await decorateContextTracks(uris: chunk)
            let startIndex = chunkIndex * 50
            for (offset, decoratedTrack) in decorated.enumerated() {
                let index = startIndex + offset
                guard index < result.count else { break }
                result[index] = PlayerState.Track(hydrating: result[index], withDecorated: decoratedTrack)
            }
        }
        return result
    }
}

// MARK: - Response Wrappers

private struct AccountAttributesResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let me: MeNode
    }
    struct MeNode: Decodable {
        let account: AccountNode
    }
    struct AccountNode: Decodable {
        let product: String
        let country: String
        let attributes: AttrNode
    }
    struct AttrNode: Decodable {
        let onDemand: Bool?
        let catalogue: String?
        let ads: Bool?
    }
}

private struct ExtractedColorsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let extractedColors: [ColorNode]
    }
    struct ColorNode: Decodable {
        let colorRaw: SpotifyExtractedColor
    }
}

private struct LibraryLookupResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupItem]
    }
    struct LookupItem: Decodable {
        let data: SavedNode?
    }
    struct SavedNode: Decodable {
        let saved: Bool?
    }
}

private struct DecorateTracksResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let tracks: [SpotifyDecoratedTrack]
    }
}

private struct PlaylistPermissionsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let playlistV2: SpotifyPlaylistPermissions
    }
}

private struct SmartShuffleResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupItem]
    }
    struct LookupItem: Decodable {
        let data: PlaylistData?
    }
    struct PlaylistData: Decodable {
        let smartShuffle: SmartShuffleNode?
    }
    struct SmartShuffleNode: Decodable {
        let available: Bool?
    }
}

private struct RecentlyPlayedResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupWrapper]
    }
    struct LookupWrapper: Decodable {
        let data: PlaylistData?
    }
    struct PlaylistData: Decodable {
        let name: String?
        let uri: String?
        let images: ImageCollection?
        let ownerV2: OwnerWrapper?
    }
    struct ImageCollection: Decodable {
        let items: [ImageItem]
    }
    struct ImageItem: Decodable {
        let sources: [ImageSource]
    }
    struct ImageSource: Decodable {
        let url: String
    }
    struct OwnerWrapper: Decodable {
        let data: OwnerData?
    }
    struct OwnerData: Decodable {
        let name: String?
    }
}

private struct CanvasResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let trackUnion: TrackNode
    }
    struct TrackNode: Decodable {
        let canvas: CanvasNode?
    }
    struct CanvasNode: Decodable {
        let url: String
        let type: String?
    }
}

private struct NpvArtistResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let artistUnion: ArtistNode }
    struct ArtistNode: Decodable {
        let uri: String?
        let profile: ProfileNode?
        let stats: StatsNode?
        let goods: GoodsNode?
        let headerImage: HeaderImage?
        let visuals: VisualsNode?
        let onPlatformReputationTrait: ReputationNode?
    }
    struct ProfileNode: Decodable {
        let name: String?
        let biography: BiographyNode?
    }
    struct BiographyNode: Decodable { let text: String? }
    struct StatsNode: Decodable {
        let followers: Int?
        let monthlyListeners: Int?
        let topCities: TopCities?
    }
    struct TopCities: Decodable { let items: [TopCity] }
    struct TopCity: Decodable { let city: String }
    struct GoodsNode: Decodable {
        let concerts: ConcertCollection?
        let merch: MerchCollection?
    }
    struct ConcertCollection: Decodable { let items: [ConcertItem] }
    struct ConcertItem: Decodable { let data: ConcertData? }
    struct ConcertData: Decodable {
        let uri: String
        let title: String
        let startDateIsoString: String
        let location: LocationNode
    }
    struct LocationNode: Decodable {
        let city: String?
        let name: String?
    }
    struct MerchCollection: Decodable { let items: [MerchItem]? }
    struct MerchItem: Decodable {
        let name: String?
        let uri: String?
        let price: String?
        let imageURL: String?

        enum CodingKeys: String, CodingKey {
            case name, uri, price
            case imageURL = "imageUrl"
            case image
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            uri = try container.decodeIfPresent(String.self, forKey: .uri)
            price = try container.decodeIfPresent(String.self, forKey: .price)
            if let direct = try container.decodeIfPresent(String.self, forKey: .imageURL) {
                imageURL = direct
            } else if let nested = try? container.decodeIfPresent(MerchImage.self, forKey: .image) {
                imageURL = nested.url ?? nested.sources?.first?.url
            } else {
                imageURL = nil
            }
        }

        struct MerchImage: Decodable {
            let url: String?
            let sources: [SimpleSource]?
        }
    }
    struct HeaderImage: Decodable { let data: ImageData? }
    struct ImageData: Decodable { let sources: [ImageSource] }
    struct ImageSource: Decodable {
        let url: String
        let maxWidth: Int?
        let maxHeight: Int?
    }
    struct VisualsNode: Decodable { let avatarImage: AvatarImage? }
    struct AvatarImage: Decodable { let sources: [SimpleSource]? }
    struct SimpleSource: Decodable { let url: String }
    struct ReputationNode: Decodable { let verification: Verification? }
    struct Verification: Decodable {
        let isRegistered: Bool?
        let isVerified: Bool?
    }
}

private struct ArtistConcertsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let artistUnion: ArtistNode? }
    struct ArtistNode: Decodable { let nearby: NearbyNode? }
    struct NearbyNode: Decodable { let concerts: ConcertCollection? }
    struct ConcertCollection: Decodable { let items: [ConcertItem] }
    struct ConcertItem: Decodable {
        let data: ConcertData?
        let concert: ConcertData?
    }
    struct ConcertData: Decodable {
        let uri: String?
        let title: String?
        let name: String?
        let startDateIsoString: String?
        let date: String?
        let location: LocationNode?
        let venue: LocationNode?
    }
    struct LocationNode: Decodable {
        let city: String?
        let name: String?
    }
}

private struct UserLocationResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let me: MeNode? }
    struct MeNode: Decodable { let userLocation: LocationNode? }
    struct LocationNode: Decodable {
        let geoHash: String?
        let latitude: Double?
        let longitude: Double?
    }
}

private struct DynamicColorsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let dynamicColors: [Swatch] }
    struct Swatch: Decodable {
        let bestFit: String?
        let dark: Palette?
        let light: Palette?
    }
    struct Palette: Decodable {
        let textBase: HexColor?
        let backgroundBase: HexColor?
    }
    struct HexColor: Decodable { let hex: String? }
}

private struct ProfileAttributesResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let me: MeNode }
    struct MeNode: Decodable { let profile: ProfileNode }
    struct ProfileNode: Decodable {
        let uri: String?
        let username: String?
        let name: String?
    }
}

private struct InternalLinkRecommenderResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let seoRecommendedTrack: TrackCollection }
    struct TrackCollection: Decodable { let items: [Item] }
    struct Item: Decodable { let data: TrackData? }
    struct TrackData: Decodable {
        let id: String?
        let uri: String
        let name: String
        let duration: DurationNode?
        let artists: ArtistItems?
        let albumOfTrack: AlbumNode?
    }
    struct DurationNode: Decodable { let totalMilliseconds: Int? }
    struct ArtistItems: Decodable { let items: [ArtistItem] }
    struct ArtistItem: Decodable {
        let id: String?
        let uri: String
        let profile: Profile
        struct Profile: Decodable { let name: String }
    }
    struct AlbumNode: Decodable {
        let id: String?
        let uri: String?
        let coverArt: CoverArt?
    }
    struct CoverArt: Decodable { let sources: [Source] }
    struct Source: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }
}

private struct SimilarAlbumsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let seoRecommendedTrackAlbum: AlbumCollection }
    struct AlbumCollection: Decodable { let items: [Item] }
    struct Item: Decodable { let data: AlbumData? }
    struct AlbumData: Decodable {
        let name: String
        let uri: String
        let artists: ArtistItems?
        let coverArt: CoverArt?
        let date: DateNode?
    }
    struct ArtistItems: Decodable { let items: [ArtistItem] }
    struct ArtistItem: Decodable {
        let uri: String?
        let profile: Profile
        struct Profile: Decodable { let name: String }
    }
    struct CoverArt: Decodable { let sources: [Source] }
    struct Source: Decodable {
        let url: String
        let width: Int?
        let height: Int?
    }
    struct DateNode: Decodable { let year: Int? }
}

private struct TrackArtistsResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let trackUnion: TrackNode? }
    struct TrackNode: Decodable { let artists: ArtistCollection? }
    struct ArtistCollection: Decodable { let items: [ArtistItem] }
    struct ArtistItem: Decodable {
        let uri: String?
        let role: String?
        let profile: Profile?
        let data: NestedArtist?

        struct Profile: Decodable { let name: String? }
        struct NestedArtist: Decodable {
            let uri: String?
            let role: String?
            let profile: Profile?
        }
    }
}

private struct AlbumTracksResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable { let albumUnion: AlbumNode? }
    struct AlbumNode: Decodable { let tracksV2: TracksNode? }
    struct TracksNode: Decodable { let items: [Item] }
    struct Item: Decodable {
        let track: TrackData?
        let data: TrackData?
    }
    struct TrackData: Decodable {
        let uri: String?
        let name: String?
        let duration: Duration?
        let artists: Artists?
        struct Duration: Decodable { let totalMilliseconds: Int? }
        struct Artists: Decodable { let items: [Artist] }
        struct Artist: Decodable {
            let uri: String?
            let profile: Profile?
            let profileName: String?
            struct Profile: Decodable { let name: String? }
        }
    }
}

private struct PlaylistExtenderResponse: Decodable {
    let recommendedTracks: [SpotifyRecommendedTrack]
}

private struct NotificationResponse: Decodable {
    let userHasUnreadNotification: Bool
}

struct SpotifyTrackMetadata: Decodable {
    let gid: String?
    let name: String
    let popularity: Int?
    let duration: Int?
    let canonicalUri: String?
    let hasLyrics: Bool?
    let album: AlbumNode?
    let artist: [ArtistNode]?
    let file: [AudioFile]?
    let alternative: [AlternativeNode]?

    enum CodingKeys: String, CodingKey {
        case gid, name, popularity, duration, album, artist, file, alternative
        case canonicalUri = "canonical_uri"
        case hasLyrics = "has_lyrics"
    }

    init(
        gid: String? = nil,
        name: String,
        popularity: Int? = nil,
        duration: Int? = nil,
        canonicalUri: String? = nil,
        hasLyrics: Bool? = nil,
        album: AlbumNode? = nil,
        artist: [ArtistNode]? = nil,
        file: [AudioFile]? = nil,
        alternative: [AlternativeNode]? = nil
    ) {
        self.gid = gid
        self.name = name
        self.popularity = popularity
        self.duration = duration
        self.canonicalUri = canonicalUri
        self.hasLyrics = hasLyrics
        self.album = album
        self.artist = artist
        self.file = file
        self.alternative = alternative
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gid = try container.decodeIfPresent(String.self, forKey: .gid)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        popularity = Self.decodeFlexibleInt(container, forKey: .popularity)
        duration = Self.decodeFlexibleInt(container, forKey: .duration)
        canonicalUri = try container.decodeIfPresent(String.self, forKey: .canonicalUri)
        hasLyrics = try container.decodeIfPresent(Bool.self, forKey: .hasLyrics)
        album = try container.decodeIfPresent(AlbumNode.self, forKey: .album)
        artist = try container.decodeIfPresent([ArtistNode].self, forKey: .artist)
        file = try container.decodeIfPresent([AudioFile].self, forKey: .file)
        alternative = try container.decodeIfPresent([AlternativeNode].self, forKey: .alternative)
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let v = try? container.decodeIfPresent(Int.self, forKey: key) { return v }
        if let s = try? container.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        if let d = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        return nil
    }

    struct AudioFile: Decodable {
        let fileId: String?
        let format: Int?

        enum CodingKeys: String, CodingKey {
            case fileId = "file_id"
            case format
        }

        init(fileId: String?, format: Int?) {
            self.fileId = fileId
            self.format = format
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fileId = try container.decodeIfPresent(String.self, forKey: .fileId)
            if let intFormat = try container.decodeIfPresent(Int.self, forKey: .format) {
                format = intFormat
            } else if let stringFormat = try container.decodeIfPresent(String.self, forKey: .format) {
                format = Self.parseFormat(stringFormat)
            } else {
                format = nil
            }
        }

        /// Maps librespot / metadata.proto AudioFile.Format names and numeric strings.
        static func parseFormatPublic(_ raw: String) -> Int? { parseFormat(raw) }

        private static func parseFormat(_ raw: String) -> Int? {
            if let n = Int(raw) { return n }
            switch raw.uppercased() {
            case "OGG_VORBIS_96": return 0
            case "OGG_VORBIS_160": return 1
            case "OGG_VORBIS_320": return 2
            case "MP3_256": return 3
            case "MP3_320": return 4
            case "MP3_160": return 5
            case "MP3_96": return 6
            case "MP3_160_ENC": return 7
            case "AAC_24", "MP4_128": return 10
            case "AAC_48", "MP4_128_DUAL": return 12
            case "AAC_160", "MP4_256": return 11
            case "AAC_320", "MP4_256_DUAL": return 13
            default: return nil
            }
        }

        var file_id: String? { fileId }
        var formatCode: Int? { format }
    }

    struct AlternativeNode: Decodable {
        let gid: String?
        let file: [AudioFile]?
        init(gid: String? = nil, file: [AudioFile]?) {
            self.gid = gid
            self.file = file
        }
    }

    struct AlbumNode: Decodable {
        let gid: String?
        let name: String
        let coverGroup: CoverGroup?

        enum CodingKeys: String, CodingKey {
            case gid, name
            case coverGroup = "cover_group"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            gid = try container.decodeIfPresent(String.self, forKey: .gid)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Album"
            coverGroup = try container.decodeIfPresent(CoverGroup.self, forKey: .coverGroup)
        }

        struct CoverGroup: Decodable {
            let image: [CoverImage]?
        }

        struct CoverImage: Decodable {
            let fileId: String?
            let size: String?
            let width: Int?
            let height: Int?

            enum CodingKeys: String, CodingKey {
                case size, width, height
                case fileId = "file_id"
            }

            var imageURL: URL? {
                guard let fileId else { return nil }
                return URL(string: "https://i.scdn.co/image/\(fileId)")
            }
        }

        var bestImageURL: URL? {
            let images = coverGroup?.image ?? []
            return images.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.imageURL ?? images.first?.imageURL
        }
    }

    struct ArtistNode: Decodable {
        let gid: String?
        let name: String

        init(gid: String?, name: String) {
            self.gid = gid
            self.name = name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            gid = try container.decodeIfPresent(String.self, forKey: .gid)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Artist"
        }

        enum CodingKeys: String, CodingKey { case gid, name }
    }

    var artistNames: String {
        (artist ?? []).map(\.name).joined(separator: ", ")
    }

    var allAudioFiles: [AudioFile] {
        var files = file ?? []
        for alt in alternative ?? [] {
            files.append(contentsOf: alt.file ?? [])
        }
        return files
    }
}

private struct PlaylistRootlistResponse: Decodable {
    let contents: ContentsNode
    struct ContentsNode: Decodable {
        let items: [RootItem]
    }
    struct RootItem: Decodable {
        let uri: String?
        let name: String?
        let attributes: AttributesNode?
    }
    struct AttributesNode: Decodable {
        let picture: String?
    }
}

// MARK: - Track Hydration from Decorated Data

extension PlayerState.Track {
    init(hydrating sparseTrack: PlayerState.Track, withDecorated details: SpotifyDecoratedTrack) {
        self.uri = sparseTrack.uri
        self.uid = sparseTrack.uid
        var updatedMetadata = sparseTrack.metadata ?? Metadata(
            title: nil, albumTitle: nil, artistName: nil, artistUri: nil,
            imageUrl: nil, imageSmallUrl: nil, imageLargeUrl: nil, imageXlargeUrl: nil,
            contextUri: nil, hidden: nil
        )
        updatedMetadata.title = details.name
        updatedMetadata.albumTitle = details.albumOfTrack.name
        updatedMetadata.artistName = details.artistName
        updatedMetadata.artistUri = details.artists.items.first?.uri
        updatedMetadata.imageUrl = details.imageURL?.absoluteString
        self.metadata = updatedMetadata
    }
}

private extension SpotifyAccountInfo {
    init(product: String, country: String, onDemand: Bool, catalogue: String, ads: Bool) {
        self.product = product
        self.country = country
        self.onDemand = onDemand
        self.catalogue = catalogue
        self.ads = ads
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Search models

struct SpotifySearchSuggestion: Identifiable, Hashable {
    var id: String { uri ?? text }
    let text: String
    let uri: String?
}

struct SpotifySearchTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let artists: String
    let imageURL: URL?
}

struct SpotifySearchArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
}

struct SpotifySearchAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let artistName: String
    let imageURL: URL?
}

struct SpotifySearchPlaylistHit: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let ownerName: String?
    let imageURL: URL?
}

struct SpotifySearchTopResults: Hashable {
    var tracks: [SpotifySearchTrack]
    var artists: [SpotifySearchArtist]
    var albums: [SpotifySearchAlbum]
    var playlists: [SpotifySearchPlaylistHit]

    var isEmpty: Bool { tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty }
    static let empty = SpotifySearchTopResults(tracks: [], artists: [], albums: [], playlists: [])
}

struct SpotifySearchSuggestionsResponse: Decodable {
    let data: DataNode?

    struct DataNode: Decodable {
        let searchV2: SearchV2?
    }
    struct SearchV2: Decodable {
        let topResultsV2: TopResults?
    }
    struct TopResults: Decodable {
        let itemsV2: [Item]?
    }
    struct Item: Decodable {
        let item: Wrapper?
    }
    struct Wrapper: Decodable {
        let data: SuggestionData?
    }
    struct SuggestionData: Decodable {
        let text: String?
        let uri: String?
    }

    var suggestions: [SpotifySearchSuggestion] {
        (data?.searchV2?.topResultsV2?.itemsV2 ?? []).compactMap { row in
            guard let text = row.item?.data?.text, !text.isEmpty else { return nil }
            return SpotifySearchSuggestion(text: text, uri: row.item?.data?.uri)
        }
    }
}

struct SpotifySearchTopResultsResponse: Decodable {
    let data: DataNode?

    struct DataNode: Decodable { let searchV2: SearchV2? }
    struct SearchV2: Decodable {
        let tracksV2: PagedTracks?
        let artists: PagedArtists?
        let albumsV2: PagedAlbums?
        let playlists: PagedPlaylists?
        let topResultsV2: TopBucket?
    }
    struct PagedTracks: Decodable { let items: [TrackItem]? }
    struct TrackItem: Decodable { let item: TrackWrapper? }
    struct TrackWrapper: Decodable { let data: TrackData? }
    struct TrackData: Decodable {
        let uri: String?
        let name: String?
        let artists: ArtistBag?
        let albumOfTrack: AlbumOf?
    }
    struct ArtistBag: Decodable { let items: [ArtistRow]? }
    struct ArtistRow: Decodable { let profile: NameOnly?; let uri: String? }
    struct NameOnly: Decodable { let name: String? }
    struct AlbumOf: Decodable { let coverArt: Cover?; let name: String? }
    struct Cover: Decodable { let sources: [Src]? }
    struct Src: Decodable { let url: String? }

    struct PagedArtists: Decodable { let items: [ArtistItem]? }
    struct ArtistItem: Decodable { let data: ArtistData? }
    struct ArtistData: Decodable {
        let uri: String?
        let profile: NameOnly?
        let visuals: Visuals?
    }
    struct Visuals: Decodable { let avatarImage: Cover? }

    struct PagedAlbums: Decodable { let items: [AlbumItem]? }
    struct AlbumItem: Decodable { let data: AlbumData? }
    struct AlbumData: Decodable {
        let uri: String?
        let name: String?
        let artists: ArtistBag?
        let coverArt: Cover?
    }

    struct PagedPlaylists: Decodable { let items: [PlaylistItem]? }
    struct PlaylistItem: Decodable { let data: PlaylistData? }
    struct PlaylistData: Decodable {
        let uri: String?
        let name: String?
        let ownerV2: Owner?
        let images: SpotifyHomeResponse.FlexibleHomeImage?
    }
    struct Owner: Decodable { let data: NameOnly? }

    struct TopBucket: Decodable { let itemsV2: [TopItem]? }
    struct TopItem: Decodable { let item: TopWrapper? }
    struct TopWrapper: Decodable {
        let data: FlexibleEntity?
    }
    struct FlexibleEntity: Decodable {
        let __typename: String?
        let uri: String?
        let name: String?
        let profile: NameOnly?
        let artists: ArtistBag?
        let coverArt: Cover?
        let visuals: Visuals?
        let ownerV2: Owner?
        let images: SpotifyHomeResponse.FlexibleHomeImage?
        let albumOfTrack: AlbumOf?
    }

    var parsed: SpotifySearchTopResults {
        let search = data?.searchV2
        var tracks: [SpotifySearchTrack] = (search?.tracksV2?.items ?? []).compactMap { item in
            guard let d = item.item?.data, let uri = d.uri, let name = d.name else { return nil }
            return SpotifySearchTrack(
                id: uri,
                name: name,
                uri: uri,
                artists: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                imageURL: URL(string: d.albumOfTrack?.coverArt?.sources?.first?.url ?? "")
            )
        }
        var artists: [SpotifySearchArtist] = (search?.artists?.items ?? []).compactMap { item in
            guard let d = item.data, let uri = d.uri, let name = d.profile?.name else { return nil }
            return SpotifySearchArtist(
                id: uri,
                name: name,
                uri: uri,
                imageURL: URL(string: d.visuals?.avatarImage?.sources?.first?.url ?? "")
            )
        }
        var albums: [SpotifySearchAlbum] = (search?.albumsV2?.items ?? []).compactMap { item in
            guard let d = item.data, let uri = d.uri, let name = d.name else { return nil }
            return SpotifySearchAlbum(
                id: uri,
                name: name,
                uri: uri,
                artistName: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                imageURL: URL(string: d.coverArt?.sources?.first?.url ?? "")
            )
        }
        var playlists: [SpotifySearchPlaylistHit] = (search?.playlists?.items ?? []).compactMap { item in
            guard let d = item.data, let uri = d.uri, let name = d.name else { return nil }
            return SpotifySearchPlaylistHit(
                id: uri,
                name: name,
                uri: uri,
                ownerName: d.ownerV2?.data?.name,
                imageURL: d.images?.url
            )
        }

        // Also harvest topResultsV2 union items when category pages are sparse.
        for top in search?.topResultsV2?.itemsV2 ?? [] {
            guard let d = top.item?.data, let uri = d.uri else { continue }
            let typename = (d.__typename ?? "").lowercased()
            if typename.contains("track"), !tracks.contains(where: { $0.uri == uri }) {
                tracks.append(
                    SpotifySearchTrack(
                        id: uri,
                        name: d.name ?? "Track",
                        uri: uri,
                        artists: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                        imageURL: URL(string: d.albumOfTrack?.coverArt?.sources?.first?.url ?? d.coverArt?.sources?.first?.url ?? "")
                    )
                )
            } else if typename.contains("artist"), !artists.contains(where: { $0.uri == uri }) {
                artists.append(
                    SpotifySearchArtist(
                        id: uri,
                        name: d.profile?.name ?? d.name ?? "Artist",
                        uri: uri,
                        imageURL: URL(string: d.visuals?.avatarImage?.sources?.first?.url ?? "")
                    )
                )
            } else if typename.contains("album"), !albums.contains(where: { $0.uri == uri }) {
                albums.append(
                    SpotifySearchAlbum(
                        id: uri,
                        name: d.name ?? "Album",
                        uri: uri,
                        artistName: (d.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                        imageURL: URL(string: d.coverArt?.sources?.first?.url ?? "")
                    )
                )
            } else if typename.contains("playlist"), !playlists.contains(where: { $0.uri == uri }) {
                playlists.append(
                    SpotifySearchPlaylistHit(
                        id: uri,
                        name: d.name ?? "Playlist",
                        uri: uri,
                        ownerName: d.ownerV2?.data?.name,
                        imageURL: d.images?.url
                    )
                )
            }
        }

        return SpotifySearchTopResults(tracks: tracks, artists: artists, albums: albums, playlists: playlists)
    }
}

// MARK: - Artist overview

struct SpotifyArtistOverview {
    let profile: SpotifyArtistProfile
    let topTracks: [SpotifySearchTrack]
    let albums: [SpotifySearchAlbum]
    let singles: [SpotifySearchAlbum]
    let featuringPlaylists: [SpotifySearchPlaylistHit]
    let relatedArtists: [SpotifySearchArtist]
    let concerts: [SpotifyArtistConcert]
}

struct ArtistOverviewResponse: Decodable {
    let data: DataNode?
    struct DataNode: Decodable { let artistUnion: ArtistUnion? }

    struct ArtistUnion: Decodable {
        let uri: String?
        let profile: Profile?
        let visuals: Visuals?
        let stats: Stats?
        let discography: Discography?
        let relatedContent: Related?
        let goods: Goods?
        let onPlatformReputationTrait: Reputation?

        struct Profile: Decodable {
            let name: String?
            let biography: Bio?
            struct Bio: Decodable { let text: String? }
        }
        struct Visuals: Decodable {
            let avatarImage: Img?
            let headerImage: Img?
            struct Img: Decodable { let sources: [Src]?; let extractedColors: Extracted? }
            struct Src: Decodable { let url: String? }
            struct Extracted: Decodable { let colorDark: Hex?; struct Hex: Decodable { let hex: String? } }
        }
        struct Stats: Decodable {
            let monthlyListeners: Int?
            let followers: Int?
            let topCities: TopCities?
            struct TopCities: Decodable { let items: [City]? }
            struct City: Decodable { let city: String? }
        }
        struct Reputation: Decodable {
            let verification: Verification?
            struct Verification: Decodable { let isVerified: Bool? }
        }

        struct Discography: Decodable {
            let topTracks: TopTracks?
            let albums: Releases?
            let singles: Releases?
            struct TopTracks: Decodable { let items: [TopItem]? }
            struct TopItem: Decodable { let track: TrackWrap?; let uid: String? }
            struct TrackWrap: Decodable { let uri: String?; let name: String?; let playcount: String?; let album: AlbumWrap?; let artists: Artists? }
            struct AlbumWrap: Decodable { let name: String?; let coverArt: Cover? }
            struct Cover: Decodable { let sources: [Src]?; struct Src: Decodable { let url: String? } }
            struct Artists: Decodable { let items: [AItem]?; struct AItem: Decodable { let profile: P?; struct P: Decodable { let name: String? } } }
            struct Releases: Decodable { let items: [ReleaseItem]? }
            struct ReleaseItem: Decodable {
                let uri: String?
                let name: String?
                let coverArt: Cover?
                let releases: Nested?
                struct Nested: Decodable { let items: [Release]? }
            }
            struct Release: Decodable { let uri: String?; let name: String?; let coverArt: Cover? }
        }

        struct Related: Decodable {
            let featuringV2: Featuring?
            let relatedArtists: RelatedArtists?
            struct Featuring: Decodable { let items: [FeatItem]? }
            struct FeatItem: Decodable {
                let playlist: PlaylistData?
                struct PlaylistData: Decodable {
                    let uri: String?
                    let name: String?
                    let images: SpotifyHomeResponse.FlexibleHomeImage?
                    let ownerV2: Owner?
                }
                struct Owner: Decodable {
                    let data: Name?
                    struct Name: Decodable { let name: String? }
                }
            }
            struct RelatedArtists: Decodable { let items: [RelArtist]? }
            struct RelArtist: Decodable {
                let uri: String?
                let profile: Name?
                let visuals: Visuals?
                struct Name: Decodable { let name: String? }
            }
        }

        struct Goods: Decodable {
            let merch: MerchList?
            let concerts: ConcertList?
            struct MerchList: Decodable { let items: [MerchItem]? }
            struct MerchItem: Decodable {
                let name: String?
                let uri: String?
                let imageURL: String?
                let price: String?

                enum CodingKeys: String, CodingKey {
                    case name, uri, price
                    case imageURL = "imageUrl"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    name = try container.decodeIfPresent(String.self, forKey: .name)
                    uri = try container.decodeIfPresent(String.self, forKey: .uri)
                    price = try container.decodeIfPresent(String.self, forKey: .price)
                    if let direct = try container.decodeIfPresent(String.self, forKey: .imageURL) {
                        imageURL = direct
                    } else {
                        imageURL = nil
                    }
                }
            }
            struct ConcertList: Decodable { let items: [ConcertItem]? }
            struct ConcertItem: Decodable { let data: ConcertData? }
            struct ConcertData: Decodable {
                let uri: String?
                let title: String?
                let startDateIsoString: String?
                let location: Loc?
                struct Loc: Decodable { let city: String?; let name: String? }
            }
        }
    }

    var overview: SpotifyArtistOverview? {
        guard let union = data?.artistUnion else { return nil }
        let uri = union.uri ?? ""
        let name = union.profile?.name ?? "Artist"
        let bio = union.profile?.biography?.text ?? ""
        let avatar = union.visuals?.avatarImage?.sources?.first?.url.flatMap(URL.init(string:))
        let header = union.visuals?.headerImage?.sources?.first?.url.flatMap(URL.init(string:))
        let cities = (union.stats?.topCities?.items ?? []).compactMap(\.city)
        let merch: [SpotifyArtistMerch] = (union.goods?.merch?.items ?? []).compactMap { item in
            guard let mName = item.name, let mURI = item.uri else { return nil }
            return SpotifyArtistMerch(
                id: mURI,
                name: mName,
                uri: mURI,
                imageURL: item.imageURL.flatMap(URL.init(string:)),
                price: item.price
            )
        }
        let profile = SpotifyArtistProfile(
            uri: uri,
            name: name,
            biography: bio,
            monthlyListeners: union.stats?.monthlyListeners,
            followers: union.stats?.followers,
            headerImageURL: header,
            avatarURL: avatar,
            isVerified: union.onPlatformReputationTrait?.verification?.isVerified ?? false,
            topCities: cities,
            merch: merch
        )
        let topTracks: [SpotifySearchTrack] = (union.discography?.topTracks?.items ?? []).compactMap { item in
            guard let t = item.track, let tURI = t.uri, let tName = t.name else { return nil }
            return SpotifySearchTrack(
                id: tURI,
                name: tName,
                uri: tURI,
                artists: (t.artists?.items ?? []).compactMap { $0.profile?.name }.joined(separator: ", "),
                imageURL: t.album?.coverArt?.sources?.first?.url.flatMap(URL.init(string:))
            )
        }
        func releases(from block: ArtistUnion.Discography.Releases?) -> [SpotifySearchAlbum] {
            (block?.items ?? []).flatMap { item -> [ArtistUnion.Discography.Release] in
                if let nested = item.releases?.items, !nested.isEmpty { return nested }
                if let uri = item.uri, let name = item.name {
                    return [ArtistUnion.Discography.Release(uri: uri, name: name, coverArt: item.coverArt)]
                }
                return []
            }.compactMap { rel in
                guard let rURI = rel.uri, let rName = rel.name else { return nil }
                return SpotifySearchAlbum(
                    id: rURI,
                    name: rName,
                    uri: rURI,
                    artistName: name,
                    imageURL: rel.coverArt?.sources?.first?.url.flatMap(URL.init(string:))
                )
            }
        }
        let featuring: [SpotifySearchPlaylistHit] = (union.relatedContent?.featuringV2?.items ?? []).compactMap { item in
            guard let p = item.playlist, let pURI = p.uri, let pName = p.name else { return nil }
            return SpotifySearchPlaylistHit(
                id: pURI,
                name: pName,
                uri: pURI,
                ownerName: p.ownerV2?.data?.name,
                imageURL: p.images?.url
            )
        }
        let related: [SpotifySearchArtist] = (union.relatedContent?.relatedArtists?.items ?? []).compactMap { item in
            guard let aURI = item.uri, let aName = item.profile?.name else { return nil }
            return SpotifySearchArtist(
                id: aURI,
                name: aName,
                uri: aURI,
                imageURL: item.visuals?.avatarImage?.sources?.first?.url.flatMap(URL.init(string:))
            )
        }
        let concerts: [SpotifyArtistConcert] = (union.goods?.concerts?.items ?? []).compactMap { item in
            guard let data = item.data else { return nil }
            return SpotifyArtistConcert(
                uri: data.uri ?? UUID().uuidString,
                title: data.title ?? "Concert",
                startDateIsoString: data.startDateIsoString ?? "",
                city: data.location?.city ?? "",
                venue: data.location?.name ?? ""
            )
        }
        return SpotifyArtistOverview(
            profile: profile,
            topTracks: topTracks,
            albums: releases(from: union.discography?.albums),
            singles: releases(from: union.discography?.singles),
            featuringPlaylists: featuring,
            relatedArtists: related,
            concerts: concerts
        )
    }
}
