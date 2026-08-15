//
//  SpotifyEntityDetailViews.swift
//  Sapphire
//
//  Artist and album detail panes opened from playlist rows.
//

import SwiftUI

struct SpotifyArtistDetailView: View {
    let uri: String
    let name: String
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager

    @State private var overview: SpotifyArtistOverview?
    @State private var isLoading = true
    @State private var showSpotifyNotOpenAlert = false

    private var profile: SpotifyArtistProfile? { overview?.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let profile {
                            ArtistProfileCard(artist: profile)
                        }

                        if let tracks = overview?.topTracks, !tracks.isEmpty {
                            sectionTitle("Popular")
                            ForEach(Array(tracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                                artistTrackRow(track, rank: index + 1)
                            }
                        }

                        if let albums = overview?.albums, !albums.isEmpty {
                            sectionTitle("Albums")
                            horizontalAlbums(albums)
                        }

                        if let singles = overview?.singles, !singles.isEmpty {
                            sectionTitle("Singles & EPs")
                            horizontalAlbums(singles)
                        }

                        if let playlists = overview?.featuringPlaylists, !playlists.isEmpty {
                            sectionTitle("Featuring")
                            ForEach(playlists.prefix(8)) { playlist in
                                featuringPlaylistRow(playlist)
                            }
                        }

                        if let related = overview?.relatedArtists, !related.isEmpty {
                            sectionTitle("Fans also like")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(related.prefix(12)) { artist in
                                        Button {
                                            navigationStack.append(
                                                .musicArtistDetail(uri: artist.uri, name: artist.name)
                                            )
                                        } label: {
                                            VStack(spacing: 6) {
                                                CachedAsyncImage(url: artist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { Circle().fill(MaterialChartPalette.surfaceVariant) }
                                                    .frame(width: 64, height: 64)
                                                    .clipShape(Circle())
                                                Text(artist.name)
                                                    .font(.caption.bold())
                                                    .lineLimit(2)
                                                    .frame(width: 72)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if let concerts = overview?.concerts, !concerts.isEmpty {
                            sectionTitle("Concerts")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(concerts.prefix(8)) { ConcertCard(concert: $0) }
                                }
                            }
                        }

                        if let profile, !profile.merch.isEmpty {
                            sectionTitle("Merch")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(profile.merch.prefix(8)) { MerchCard(item: $0) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 820, height: 360)
        .task { await load() }
        .alert("Spotify App Is Not Open", isPresented: $showSpotifyNotOpenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To control playback with a free account, please open the Spotify desktop app first.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile?.name ?? name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    if profile?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.cyan)
                            .font(.system(size: 14))
                    }
                }
                if let listeners = profile?.monthlyListeners {
                    Text("\(listeners.formatted()) monthly listeners")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if let followers = profile?.followers {
                    Text("\(followers.formatted()) followers")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { handle(await musicManager.play(contextUri: uri)) }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
    }

    private func horizontalAlbums(_ albums: [SpotifySearchAlbum]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(albums.prefix(16)) { album in
                    Button {
                        navigationStack.append(.musicAlbumDetail(uri: album.uri, name: album.name))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CachedAsyncImage(url: album.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                placeholder: { RoundedRectangle(cornerRadius: 10).fill(MaterialChartPalette.surfaceVariant) }
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(album.name)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .frame(width: 100, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func artistTrackRow(_ track: SpotifySearchTrack, rank: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            CachedAsyncImage(url: track.imageURL) { $0.resizable() }
                placeholder: { RoundedRectangle(cornerRadius: 6).fill(MaterialChartPalette.surfaceVariant) }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(track.artists)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                Task {
                    _ = await musicManager.spotifyPrivateAPI.addToQueue(
                        uri: track.uri,
                        metadata: ["title": track.name, "artist_name": track.artists]
                    )
                }
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Button {
                Task { handle(await musicManager.play(trackUri: track.uri, contextUri: uri)) }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(MaterialChartPalette.primary.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func featuringPlaylistRow(_ playlist: SpotifySearchPlaylistHit) -> some View {
        Button {
            let id = playlist.uri.components(separatedBy: ":").last ?? playlist.id
            navigationStack.append(
                .musicPlaylistDetail(
                    SpotifyPlaylist(
                        id: id,
                        name: playlist.name,
                        uri: playlist.uri,
                        images: playlist.imageURL.map { [SpotifyImage(url: $0.absoluteString)] } ?? [],
                        owner: SpotifyUserSimple(id: "", displayName: playlist.ownerName ?? "Spotify", images: nil),
                        collaborators: nil
                    )
                )
            )
        } label: {
            HStack(spacing: 10) {
                CachedAsyncImage(url: playlist.imageURL) { $0.resizable() }
                    placeholder: { RoundedRectangle(cornerRadius: 8).fill(MaterialChartPalette.surfaceVariant) }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(playlist.ownerName ?? "Playlist")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        if let result = await musicManager.spotifyPrivateAPI.fetchArtistOverview(uri: uri) {
            overview = result
        } else {
            let trackURI = musicManager.uri ?? musicManager.nowPlayingTrack?.uri ?? "spotify:track:0"
            let concerts = await musicManager.spotifyPrivateAPI.fetchArtistConcerts(
                artistURI: uri,
                trackURI: trackURI
            )
            if let npv = musicManager.spotifyPrivateAPI.nowPlayingArtist, npv.uri == uri || npv.name == name {
                overview = SpotifyArtistOverview(
                    profile: npv,
                    topTracks: [],
                    albums: [],
                    singles: [],
                    featuringPlaylists: [],
                    relatedArtists: [],
                    concerts: concerts
                )
            } else {
                overview = SpotifyArtistOverview(
                    profile: SpotifyArtistProfile(
                        uri: uri,
                        name: name,
                        biography: "",
                        monthlyListeners: nil,
                        followers: nil,
                        headerImageURL: nil,
                        avatarURL: nil,
                        isVerified: false,
                        topCities: [],
                        merch: []
                    ),
                    topTracks: [],
                    albums: [],
                    singles: [],
                    featuringPlaylists: [],
                    relatedArtists: [],
                    concerts: concerts
                )
            }
        }
        isLoading = false
    }

    private func handle(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
    }
}

struct SpotifyAlbumDetailView: View {
    let uri: String
    let name: String
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager

    @State private var tracks: [SpotifyRecommendedTrack] = []
    @State private var isLoading = true
    @State private var showSpotifyNotOpenAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { handle(await musicManager.play(contextUri: uri)) }
                } label: {
                    Label("Play album", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                ContentUnavailableView(
                    "Album tracks",
                    systemImage: "opticaldisc",
                    description: Text("Play the album, or open it in Spotify for the full track list.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(tracks) { track in
                            RecommendedTrackRow(track: track) { handle($0) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 820, height: 360)
        .task { await load() }
        .alert("Spotify App Is Not Open", isPresented: $showSpotifyNotOpenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To control playback with a free account, please open the Spotify desktop app first.")
        }
    }

    private func load() async {
        isLoading = true
        tracks = await musicManager.spotifyPrivateAPI.fetchAlbumTracks(albumURI: uri)
        isLoading = false
    }

    private func handle(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
    }
}
