//
//  PlaylistView.swift
//  Sapphire
//
//  Material You–inspired playlist detail with client-side column sorting
//  (no Pathfinder hydrate-indexing) and tappable artist / album navigation.
//

import SwiftUI
import Combine

fileprivate let isoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

fileprivate let displayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

class TrackViewModel: ObservableObject, Identifiable {
    let id = UUID()

    let name: String
    let artists: String
    let firstArtistName: String
    let firstArtistURI: String?
    let albumName: String
    let albumURI: String?
    let imageURL: URL?
    let uri: String
    let uid: String?
    let dateAdded: TimeInterval?
    let addedByName: String?
    let playCount: Int?
    let publicationYear: Int?

    @Published var trackDetails: SpotifyTrackDetailsResponse.TrackUnion?

    private var hydrationTask: Task<Void, Never>?
    private let canHydrate: Bool

    init(playlistItem: SpotifyPlaylistDetailsResponse.PlaylistItem) {
        let data = playlistItem.itemV2.data
        self.uid = playlistItem.uid
        self.name = data.name ?? "Unknown Track"
        let artistItems = data.artists?.items ?? []
        self.artists = artistItems.map(\.profile.name).joined(separator: ", ").nilIfEmpty ?? "Unknown Artist"
        self.firstArtistName = artistItems.first?.profile.name ?? "Unknown Artist"
        self.firstArtistURI = artistItems.first?.uri
        self.albumName = data.albumOfTrack?.name ?? "Unknown Album"
        self.albumURI = data.albumOfTrack?.uri
        self.imageURL = data.imageURL
        self.uri = data.uri ?? ""
        // `PlaylistItem.addedAt` is already seconds since 1970 — do not divide again.
        self.dateAdded = playlistItem.addedAt
        self.addedByName = playlistItem.addedByDisplayName
        self.playCount = data.playcountInt
        self.publicationYear = data.albumOfTrack?.publishDate?.year
        self.canHydrate = true
    }

    init(track: SpotifyTrack) {
        self.uid = nil
        self.name = track.name
        self.artists = track.artists.map(\.name).joined(separator: ", ")
        self.firstArtistName = track.artists.first?.name ?? "Unknown Artist"
        self.firstArtistURI = nil
        self.albumName = track.album.name
        self.albumURI = nil
        self.imageURL = track.album.images.first.flatMap { URL(string: $0.url) }
        self.uri = track.uri
        self.dateAdded = nil
        self.addedByName = nil
        self.playCount = nil
        self.publicationYear = nil
        self.canHydrate = false
    }

    func hydrate(completion: (() -> Void)? = nil) {
        guard canHydrate, trackDetails == nil, hydrationTask == nil else {
            completion?()
            return
        }
        hydrationTask = Task { [weak self] in
            guard let self else { return }
            let trackId = self.uri.components(separatedBy: ":").last ?? ""
            guard !trackId.isEmpty else {
                await MainActor.run { completion?(); self.hydrationTask = nil }
                return
            }
            if Task.isCancelled { return }
            let details = await SpotifyPrivateAPIManager.shared.fetchTrackDetails(trackId: trackId)
            if !Task.isCancelled {
                await MainActor.run {
                    self.trackDetails = details
                    completion?()
                    self.hydrationTask = nil
                }
            }
        }
    }

    func cancelHydration() {
        hydrationTask?.cancel()
        hydrationTask = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct PlaylistView: View {
    let playlist: SpotifyPlaylist
    let isLockScreenMode: Bool

    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject private var navigationManager: LockScreenNavigationManager
    @Binding var navigationStack: [NotchWidgetMode]

    @ObservedObject private var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared

    @State private var viewModels: [TrackViewModel] = []
    @State private var isLoading = false
    @State private var showSpotifyNotOpenAlert = false
    @State private var sortOption: SortOption = .customOrder
    @State private var sortDirection: SortDirection = .ascending
    @State private var isUsingPrivateAPI = true

    private let playlistSortStateKey = "playlistSortDescriptors"

    enum SortOption: String, CaseIterable, Identifiable {
        case customOrder = "Custom order"
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case dateAdded = "Date added"
        case playCount = "Play count"

        var id: String { rawValue }

        /// Matches Web Player sortable columns — all use payload already on playlist items.
        static var playlistColumns: [SortOption] { [.title, .artist, .album, .dateAdded, .playCount] }
    }

    enum SortDirection: String { case ascending, descending }

    init(playlist: SpotifyPlaylist, navigationStack: Binding<[NotchWidgetMode]> = .constant([]), isLockScreenMode: Bool = false) {
        self.playlist = playlist
        self._navigationStack = navigationStack
        self.isLockScreenMode = isLockScreenMode
    }

    private var sortedViewModels: [TrackViewModel] {
        // Default: Spotify's native playlist order from Pathfinder pages.
        // Optional local reordering only applies to currently loaded pages (on-demand).
        if sortOption == .customOrder {
            return sortDirection == .ascending ? viewModels : viewModels.reversed()
        }
        return viewModels.sorted { lhs, rhs in
            let result: ComparisonResult = {
                switch sortOption {
                case .title: return lhs.name.localizedStandardCompare(rhs.name)
                case .artist: return lhs.artists.localizedStandardCompare(rhs.artists)
                case .album: return lhs.albumName.localizedStandardCompare(rhs.albumName)
                case .dateAdded:
                    let l = lhs.dateAdded ?? 0, r = rhs.dateAdded ?? 0
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .playCount:
                    let l = lhs.playCount ?? 0, r = rhs.playCount ?? 0
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .customOrder: return .orderedSame
                }
            }()
            return sortDirection == .ascending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            playlistHero

            columnHeaders
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ZStack {
                if viewModels.isEmpty {
                    if isLoading {
                        ProgressView().scaleEffect(1.2)
                    } else {
                        Text("This playlist is empty.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(sortedViewModels.enumerated()), id: \.element.id) { index, viewModel in
                                PlaylistTrackRow(
                                    index: index + 1,
                                    viewModel: viewModel,
                                    contextUri: playlist.uri,
                                    onPlay: handlePlaybackResult,
                                    onArtist: { openArtist(viewModel) },
                                    onAlbum: { openAlbum(viewModel) },
                                    onAddToQueue: {
                                        Task {
                                            _ = await musicManager.spotifyPrivateAPI.addToQueue(
                                                uri: viewModel.uri,
                                                uid: viewModel.uid,
                                                metadata: [
                                                    "title": viewModel.name,
                                                    "artist_name": viewModel.artists,
                                                    "album_title": viewModel.albumName
                                                ]
                                            )
                                        }
                                    }
                                )
                                .onAppear {
                                    if index >= sortedViewModels.count - 5 {
                                        Task { await spotifyPrivateAPI.loadMorePlaylistTracks() }
                                    }
                                }
                            }

                            if spotifyPrivateAPI.isPlaylistLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 12)
                            } else if spotifyPrivateAPI.playlistHasMore {
                                Text("Scroll for more")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.vertical, 8)
                            }

                            if !spotifyPrivateAPI.playlistRecommendations.isEmpty {
                                Text("Recommended")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 14)
                                    .padding(.horizontal, 4)

                                ForEach(spotifyPrivateAPI.playlistRecommendations) { track in
                                    RecommendedTrackRow(track: track, onPlay: handlePlaybackResult)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 820, height: 360)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.001))
        )
        .task(id: playlist.id) { await loadPlaylistContent() }
        .onReceive(spotifyPrivateAPI.$playlistTrackViewModels.receive(on: DispatchQueue.main)) { models in
            guard isUsingPrivateAPI else { return }
            viewModels = models
        }
        .alert("Spotify App Is Not Open", isPresented: $showSpotifyNotOpenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To control playback with a free account, please open the Spotify desktop app first.")
        }
        .onChange(of: sortOption) { _, _ in saveSortState() }
        .onChange(of: sortDirection) { _, _ in saveSortState() }
        .onAppear { loadSortState() }
    }

    // MARK: - Hero

    private var playlistHero: some View {
        HStack(alignment: .center, spacing: 16) {
            CachedAsyncImage(url: playlist.images.first.flatMap { URL(string: $0.url) }) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.2))
                    .overlay(Image(systemName: "music.note.list").font(.title2))
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(playlist.owner.displayName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(spotifyPrivateAPI.playlistTotalCount > 0 ? spotifyPrivateAPI.playlistTotalCount : viewModels.count) songs")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let perms = musicManager.spotifyPrivateAPI.currentPlaylistPermissions {
                        Text(perms.canEditItems ? "Editable" : "View only")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    tonalButton("Play", systemImage: "play.fill") {
                        Task { handlePlaybackResult(await musicManager.play(contextUri: playlist.uri)) }
                    }
                    tonalButton("Shuffle", systemImage: "shuffle") {
                        Task {
                            handlePlaybackResult(await musicManager.play(contextUri: playlist.uri))
                            try? await Task.sleep(for: .milliseconds(400))
                            await musicManager.toggleShuffle()
                        }
                    }
                    if musicManager.spotifyPrivateAPI.smartShuffleAvailable {
                        tonalButton("Smart", systemImage: "sparkles") {
                            Task {
                                handlePlaybackResult(await musicManager.spotifyPrivateAPI.playSmartShuffle(playlistURI: playlist.uri))
                            }
                        }
                    }
                    tonalButton(
                        musicManager.spotifyPrivateAPI.isEnhanceLoading ? "…" : "Enhance",
                        systemImage: "wand.and.stars"
                    ) {
                        Task {
                            let ok = await musicManager.spotifyPrivateAPI.applyPlaylistEnhance(playlistId: playlist.id)
                            if ok { handlePlaybackResult(.success) }
                        }
                    }
                    .disabled(musicManager.spotifyPrivateAPI.isEnhanceLoading)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func tonalButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Column headers (client-side sort)

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 28, alignment: .leading)
                .foregroundStyle(.tertiary)

            sortHeader(.title, width: nil, alignment: .leading)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text("Added by")
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)

            sortHeader(.dateAdded, width: 96, alignment: .trailing)
            sortHeader(.playCount, width: 64, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .textCase(.uppercase)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sortHeader(_ option: SortOption, width: CGFloat?, alignment: Alignment) -> some View {
        Button {
            if sortOption == option {
                sortDirection = sortDirection == .ascending ? .descending : .ascending
            } else {
                sortOption = option
                sortDirection = option == .playCount || option == .dateAdded ? .descending : .ascending
            }
            Task { await musicManager.spotifyPrivateAPI.logSortTelemetry() }
        } label: {
            HStack(spacing: 3) {
                Text(option.rawValue)
                if sortOption == option {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(sortOption == option ? Color.accentColor : Color.secondary)
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private func openArtist(_ viewModel: TrackViewModel) {
        guard let uri = viewModel.firstArtistURI, !uri.isEmpty else { return }
        push(.musicArtistDetail(uri: uri, name: viewModel.firstArtistName))
    }

    private func openAlbum(_ viewModel: TrackViewModel) {
        guard let uri = viewModel.albumURI, !uri.isEmpty else { return }
        push(.musicAlbumDetail(uri: uri, name: viewModel.albumName))
    }

    private func push(_ mode: NotchWidgetMode) {
        if isLockScreenMode {
            // Lock-screen path currently uses playlist-only nav; fall back to notch stack when available.
            navigationStack.append(mode)
        } else {
            navigationStack.append(mode)
        }
    }

    // MARK: - Load / sort persistence

    private func loadPlaylistContent() async {
        isLoading = true
        viewModels = []
        if spotifyPrivateAPI.isLoggedIn {
            isUsingPrivateAPI = true
            spotifyPrivateAPI.playlistTrackViewModels = []
            if playlist.uri.contains(":collection") || playlist.uri.contains(":tracks") {
                await spotifyPrivateAPI.loadLikedSongs(for: playlist)
            } else {
                await spotifyPrivateAPI.loadPlaylist(playlistId: playlist.id)
            }
        } else if musicManager.spotifyOfficialAPI.isAuthenticated {
            isUsingPrivateAPI = false
            if !(playlist.uri.contains(":collection") || playlist.uri.contains(":tracks")),
               let tracks = await musicManager.spotifyOfficialAPI.fetchPlaylistTracks(playlistID: playlist.id) {
                viewModels = tracks.map { TrackViewModel(track: $0) }
            }
        }
        isLoading = false
        loadSortState()
    }

    private func loadSortState() {
        guard let saved = UserDefaults.standard.dictionary(forKey: playlistSortStateKey) as? [String: [String: String]],
              let entry = saved[playlist.id],
              let optionRaw = entry["option"],
              let option = SortOption(rawValue: optionRaw) else { return }
        sortOption = option
        if let dir = entry["direction"], let direction = SortDirection(rawValue: dir) {
            sortDirection = direction
        }
    }

    private func saveSortState() {
        var saved = UserDefaults.standard.dictionary(forKey: playlistSortStateKey) as? [String: [String: String]] ?? [:]
        saved[playlist.id] = ["option": sortOption.rawValue, "direction": sortDirection.rawValue]
        UserDefaults.standard.set(saved, forKey: playlistSortStateKey)
    }

    private func handlePlaybackResult(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result { showSpotifyNotOpenAlert = true }
    }
}

// MARK: - Track row

private struct PlaylistTrackRow: View {
    let index: Int
    @ObservedObject var viewModel: TrackViewModel
    let contextUri: String
    var onPlay: (PlaybackResult) -> Void
    var onArtist: () -> Void
    var onAlbum: () -> Void
    var onAddToQueue: () -> Void

    @EnvironmentObject var musicManager: MusicManager
    @State private var isHovered = false

    private static let exactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private var dateAddedString: String? {
        guard let timestamp = viewModel.dateAdded else { return nil }
        return Self.exactDateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Text("\(index)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 0 : 1)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(isHovered ? 1 : 0)
            }
            .frame(width: 28, alignment: .leading)

            HStack(spacing: 10) {
                CachedAsyncImage(url: viewModel.imageURL) { $0.resizable() } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.2))
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Button(action: onArtist) {
                            Text(viewModel.artists)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.firstArtistURI == nil)
                        Text("·").foregroundStyle(.quaternary)
                        Button(action: onAlbum) {
                            Text(viewModel.albumName)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.albumURI == nil)
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text(viewModel.addedByName ?? "—")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Text(dateAddedString ?? "—")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 96, alignment: .trailing)

            Group {
                if let count = viewModel.playCount {
                    PlayCountIndicator(playCount: count)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            Task {
                onPlay(await musicManager.play(
                    trackUri: viewModel.uri,
                    contextUri: contextUri,
                    trackUid: viewModel.uid,
                    trackIndex: nil
                ))
            }
        }
        .contextMenu {
            Button("Add to Queue", action: onAddToQueue)
            Button("Play") {
                Task {
                    onPlay(await musicManager.play(
                        trackUri: viewModel.uri,
                        contextUri: contextUri,
                        trackUid: viewModel.uid,
                        trackIndex: nil
                    ))
                }
            }
        }
    }
}

extension TimeInterval {
    fileprivate func timeAgoDisplay() -> String {
        let date = Date(timeIntervalSince1970: self)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
