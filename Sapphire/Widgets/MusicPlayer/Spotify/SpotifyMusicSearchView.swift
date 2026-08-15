//
//  SpotifyMusicSearchView.swift
//  Sapphire
//
//  Pathfinder searchSuggestions + searchTopResultsList for the music pane.
//

import SwiftUI

struct SpotifyMusicSearchView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var onPlaySuccess: () -> Void = {}
    /// When set, shown instead of the default empty search prompt (e.g. Discover home shelves).
    var emptyReplacement: (() -> AnyView)? = nil
    var autofocusSearch: Bool = true

    @EnvironmentObject var musicManager: MusicManager

    @State private var query = ""
    @State private var suggestions: [SpotifySearchSuggestion] = []
    @State private var results: SpotifySearchTopResults = .empty
    @State private var isSearching = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                NotchSearchField(
                    placeholder: "Search songs, artists, albums…",
                    text: $query,
                    autofocus: autofocusSearch
                )
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .onChange(of: query) { _, newValue in
                    scheduleSearch(newValue)
                }
                if !query.isEmpty {
                    Button {
                        query = ""
                        suggestions = []
                        results = .empty
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.surfaceContainer)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.cardGradient(for: MaterialChartPalette.primary))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MaterialChartPalette.primary.opacity(0.2), lineWidth: 1)
            )

            if isSearching && results.isEmpty && suggestions.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let emptyReplacement {
                    emptyReplacement()
                } else {
                    CustomUnavailableView(
                        title: "Search Spotify",
                        systemImage: "magnifyingglass",
                        description: "Find tracks, artists, albums, and playlists."
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !suggestions.isEmpty {
                            Text("Suggestions")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            FlowWrap(items: suggestions.prefix(8).map(\.text)) { text in
                                Button {
                                    query = text
                                    scheduleSearch(text, immediate: true)
                                } label: {
                                    Text(text)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(MaterialChartPalette.primary.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !results.tracks.isEmpty {
                            sectionHeader("Songs")
                            ForEach(results.tracks.prefix(8)) { track in
                                searchTrackRow(track)
                            }
                        }
                        if !results.artists.isEmpty {
                            sectionHeader("Artists")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(results.artists.prefix(12)) { artist in
                                        Button {
                                            navigationStack.append(
                                                .musicArtistDetail(uri: artist.uri, name: artist.name)
                                            )
                                        } label: {
                                            VStack(spacing: 6) {
                                                CachedAsyncImage(url: artist.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { Circle().fill(MaterialChartPalette.surfaceVariant) }
                                                    .frame(width: 72, height: 72)
                                                    .clipShape(Circle())
                                                Text(artist.name)
                                                    .font(.caption.bold())
                                                    .lineLimit(2)
                                                    .frame(width: 80)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !results.albums.isEmpty {
                            sectionHeader("Albums")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(results.albums.prefix(12)) { album in
                                        Button {
                                            navigationStack.append(
                                                .musicAlbumDetail(uri: album.uri, name: album.name)
                                            )
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                CachedAsyncImage(url: album.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) }
                                                    placeholder: { RoundedRectangle(cornerRadius: 10).fill(MaterialChartPalette.surfaceVariant) }
                                                    .frame(width: 100, height: 100)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                Text(album.name).font(.caption.bold()).lineLimit(2).frame(width: 100, alignment: .leading)
                                                Text(album.artistName).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 100, alignment: .leading)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !results.playlists.isEmpty {
                            sectionHeader("Playlists")
                            ForEach(results.playlists.prefix(8)) { playlist in
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
                                            Text(playlist.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                                            Text(playlist.ownerName ?? "Playlist")
                                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Button {
                                            Task {
                                                let result = await musicManager.play(contextUri: playlist.uri)
                                                if case .success = result { onPlaySuccess() }
                                            }
                                        } label: {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .frame(width: 28, height: 28)
                                                .background(MaterialChartPalette.primary.opacity(0.16), in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func searchTrackRow(_ track: SpotifySearchTrack) -> some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: track.imageURL) { $0.resizable() }
                placeholder: { RoundedRectangle(cornerRadius: 8).fill(MaterialChartPalette.surfaceVariant) }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(track.artists).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
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
                Task {
                    let result = await musicManager.play(trackUri: track.uri, contextUri: nil)
                    if case .success = result { onPlaySuccess() }
                }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(MaterialChartPalette.secondary.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.surfaceContainer)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: MaterialChartPalette.secondary))
            }
        )
    }

    private func scheduleSearch(_ raw: String, immediate: Bool = false) {
        debounceTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            results = .empty
            isSearching = false
            return
        }
        debounceTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(280))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            async let sugg = musicManager.spotifyPrivateAPI.searchSuggestions(query: trimmed)
            async let top = musicManager.spotifyPrivateAPI.searchTopResults(query: trimmed)
            let (s, t) = await (sugg, top)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = s
                results = t
                isSearching = false
            }
        }
    }
}

/// Simple wrapping HStack for suggestion chips.
private struct FlowWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // Notch width is fixed — a horizontal scroll is more reliable than a custom wrap layout.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { content($0) }
            }
        }
    }
}
