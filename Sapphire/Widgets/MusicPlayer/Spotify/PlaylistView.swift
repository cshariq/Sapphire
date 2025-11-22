//
//  PlaylistView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-26.
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
    // MARK: - Properties
    let id = UUID()

    let name: String
    let artists: String
    let albumName: String
    let imageURL: URL?
    let uri: String
    let uid: String?

    let dateAdded: TimeInterval?
    let playCount: Int?
    let publicationYear: Int?
    let publicationDateISO: String?

    @Published var trackDetails: SpotifyTrackDetailsResponse.TrackUnion?

    private var hydrationTask: Task<Void, Never>?
    private let canHydrate: Bool

    // MARK: - Initializers

    init(playlistItem: SpotifyPlaylistDetailsResponse.PlaylistItem) {
        self.uid = playlistItem.uid
        self.name = playlistItem.itemV2.data.name
        self.artists = playlistItem.itemV2.data.artists.items.map { $0.profile.name }.joined(separator: ", ")
        self.albumName = playlistItem.itemV2.data.albumOfTrack.name
        self.imageURL = playlistItem.itemV2.data.imageURL
        self.uri = playlistItem.itemV2.data.uri ?? ""
        self.dateAdded = playlistItem.addedAt.map { $0 / 1000.0 }
        self.playCount = playlistItem.itemV2.data.playcountInt
        self.publicationYear = nil
        self.publicationDateISO = nil
        self.canHydrate = true
    }

    init(track: SpotifyTrack) {
        self.uid = nil
        self.name = track.name
        self.artists = track.artists.map { $0.name }.joined(separator: ", ")
        self.albumName = track.album.name
        self.imageURL = track.album.images.first.flatMap { URL(string: $0.url) }
        self.uri = track.uri
        self.dateAdded = nil
        self.playCount = nil
        self.publicationYear = nil
        self.publicationDateISO = nil
        self.canHydrate = false
    }

    // MARK: - Hydration

    func hydrate(completion: (() -> Void)? = nil) {
        guard canHydrate, trackDetails == nil, hydrationTask == nil else {
            completion?()
            return
        }

        hydrationTask = Task { [weak self] in
            guard let self = self else { return }

            let trackId = self.uri.components(separatedBy: ":").last ?? ""
            guard !trackId.isEmpty else {
                await MainActor.run {
                    completion?()
                    self.hydrationTask = nil
                }
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

struct PlaylistView: View {
    let playlist: SpotifyPlaylist
    let isLockScreenMode: Bool

    @StateObject private var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared
    @EnvironmentObject private var musicManager: MusicManager

    @State private var viewModels: [TrackViewModel] = []
    @State private var isLoading = false

    @State private var showSpotifyNotOpenAlert = false

    enum SortOption: String, CaseIterable, Identifiable {
        case defaultOrder = "Default"
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case dateAdded = "Date Added"
        case publicationDate = "Published"
        case playCount = "Play Count"
        var id: String { self.rawValue }

        var requiresHydration: Bool {
            switch self {
            case .album, .publicationDate, .playCount:
                return true
            default:
                return false
            }
        }
    }

    enum SortDirection {
        case ascending, descending
    }

    @State private var sortOption: SortOption = .defaultOrder
    @State private var sortDirection: SortDirection = .ascending

    @State private var isIndexing: Bool = false
    @State private var indexingProgress: Double = 0.0

    @State private var isUsingPrivateAPI = true

    private let playlistSortStateKey = "playlistSortDescriptors"

    init(playlist: SpotifyPlaylist, isLockScreenMode: Bool = false) {
        self.playlist = playlist
        self.isLockScreenMode = isLockScreenMode
    }

    private var availableSortOptions: [SortOption] {
        if isUsingPrivateAPI {
            return SortOption.allCases
        } else {
            return [.defaultOrder, .title, .artist, .album]
        }
    }

    private var sortedViewModels: [TrackViewModel] {
        if sortOption == .defaultOrder {
            return sortDirection == .ascending ? viewModels : viewModels.reversed()
        }

        return viewModels.sorted { lhs, rhs in
            let result: ComparisonResult = {
                switch sortOption {
                case .title:
                    return lhs.name.localizedStandardCompare(rhs.name)
                case .artist:
                    return lhs.artists.localizedStandardCompare(rhs.artists)
                case .album:
                    return lhs.albumName.localizedStandardCompare(rhs.albumName)
                case .dateAdded:
                    let l = lhs.dateAdded ?? 0
                    let r = rhs.dateAdded ?? 0
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .publicationDate:
                    let l = lhs.trackDetails?.albumOfTrack.publishDate?.year ?? 0
                    let r = rhs.trackDetails?.albumOfTrack.publishDate?.year ?? 0
                    if l == 0 && r != 0 { return .orderedDescending }
                    if l != 0 && r == 0 { return .orderedAscending }
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .playCount:
                    let l = lhs.playCount ?? 0
                    let r = rhs.playCount ?? 0
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .defaultOrder:
                    return .orderedSame
                }
            }()

            return sortDirection == .ascending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistHeaderView(
                playlist: playlist,
                sortOption: $sortOption,
                sortDirection: $sortDirection,
                isIndexing: isIndexing,
                availableSortOptions: availableSortOptions,
                onPlay: handlePlaybackResult
            )

            if isIndexing {
                VStack(spacing: 2) {
                    Text("Indexing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    ProgressView(value: indexingProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 5)
                .transition(.opacity)
            }

            ZStack {
                if viewModels.isEmpty {
                    if isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(1.5).frame(maxHeight: .infinity)
                    } else {
                        Text("This playlist is empty.").foregroundColor(.secondary).frame(maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(sortedViewModels) { viewModel in
                                UnifiedTrackRow(
                                    viewModel: viewModel,
                                    contextUri: playlist.uri,
                                    onPlay: handlePlaybackResult
                                )
                                .onAppear { viewModel.hydrate() }
                                .onDisappear { viewModel.cancelHydration() }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .frame(width: 800, height: 350)
        .task(id: playlist.id) {
            await loadPlaylistContent()
        }
        .alert("Spotify App Is Not Open", isPresented: $showSpotifyNotOpenAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To control playback with a free account, please open the Spotify desktop app first.")
        }
        .onChange(of: sortOption) { _, newSortOption in
            saveSortState()
            startIndexingIfNeeded(for: newSortOption)
        }
        .onChange(of: sortDirection) { _, _ in
            saveSortState()
        }
        .animation(.default, value: isIndexing)
    }

    private func loadPlaylistContent() async {
        isLoading = true
        self.viewModels = []

        if spotifyPrivateAPI.isLoggedIn {
            isUsingPrivateAPI = true
            spotifyPrivateAPI.playlistTrackViewModels = []
            if playlist.uri.contains(":collection") || playlist.uri.contains(":tracks") {
                await spotifyPrivateAPI.loadLikedSongs(for: playlist)
            } else {
                await spotifyPrivateAPI.loadPlaylist(playlistId: playlist.id)
            }
            self.viewModels = spotifyPrivateAPI.playlistTrackViewModels
        } else if musicManager.spotifyOfficialAPI.isAuthenticated {
            isUsingPrivateAPI = false
            if !(playlist.uri.contains(":collection") || playlist.uri.contains(":tracks")) {
                if let tracks = await musicManager.spotifyOfficialAPI.fetchPlaylistTracks(playlistID: playlist.id) {
                    self.viewModels = tracks.map { TrackViewModel(track: $0) }
                }
            }
        }

        isLoading = false
        loadSortState()
        if !availableSortOptions.contains(sortOption) {
            sortOption = .defaultOrder
        }
    }

    private func handlePlaybackResult(_ result: PlaybackResult) {
        if case .requiresSpotifyAppOpen = result {
            showSpotifyNotOpenAlert = true
        }
    }

    private func loadSortState() {
        guard let savedDescriptors = UserDefaults.standard.dictionary(forKey: playlistSortStateKey) as? [String: [String: String]],
              let descriptor = savedDescriptors[playlist.id],
              let optionRawValue = descriptor["option"],
              let directionRawValue = descriptor["direction"],
              let option = SortOption(rawValue: optionRawValue) else {
            self.sortOption = .defaultOrder
            self.sortDirection = .ascending
            return
        }

        self.sortOption = option
        self.sortDirection = (directionRawValue == "descending") ? .descending : .ascending
    }

    private func saveSortState() {
        var savedDescriptors = UserDefaults.standard.dictionary(forKey: playlistSortStateKey) as? [String: [String: String]] ?? [:]
        let directionString = (sortDirection == .descending) ? "descending" : "ascending"
        let newDescriptor = ["option": sortOption.rawValue, "direction": directionString]
        savedDescriptors[playlist.id] = newDescriptor
        UserDefaults.standard.set(savedDescriptors, forKey: playlistSortStateKey)
    }

    private func startIndexingIfNeeded(for sortOption: SortOption) {
        guard isUsingPrivateAPI, sortOption.requiresHydration, !isIndexing else { return }

        isIndexing = true
        indexingProgress = 0.0

        Task(priority: .userInitiated) {
            try? await Task.sleep(for: .nanoseconds(1))

            let unhydratedViewModels = viewModels.filter { $0.trackDetails == nil }

            guard !unhydratedViewModels.isEmpty else {
                await MainActor.run { isIndexing = false }
                return
            }

            let totalToHydrate = Double(unhydratedViewModels.count)
            var hydratedCount = 0.0

            await withTaskGroup(of: Void.self) { group in
                for viewModel in unhydratedViewModels {
                    group.addTask {
                        await withCheckedContinuation { continuation in
                            viewModel.hydrate {
                                continuation.resume()
                            }
                        }
                        await MainActor.run {
                            hydratedCount += 1
                            indexingProgress = hydratedCount / totalToHydrate
                        }
                    }
                }
            }

            await MainActor.run {
                isIndexing = false
            }
        }
    }
}

private struct PlaylistHeaderView: View {
    let playlist: SpotifyPlaylist
    @Binding var sortOption: PlaylistView.SortOption
    @Binding var sortDirection: PlaylistView.SortDirection
    let isIndexing: Bool
    let availableSortOptions: [PlaylistView.SortOption]
    let onPlay: (PlaybackResult) -> Void

    @EnvironmentObject private var musicManager: MusicManager

    private var collaboratorImages: [URL?] {
        var urls = [playlist.owner.imageURL]
        if let collaborators = playlist.collaborators {
            urls.append(contentsOf: collaborators.map { $0.imageURL })
        }
        return urls
    }

    var body: some View {
        HStack(spacing: 15) {
            CachedAsyncImage(url: playlist.imageURL) { $0.resizable() } placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note.list") } }
                .frame(width: 80, height: 80)
                .cornerRadius(12)
                .shadow(radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.title2.bold())
                    .lineLimit(2)

                HStack(spacing: -8) {
                    ForEach(collaboratorImages.indices, id: \.self) { index in
                        CachedAsyncImage(url: collaboratorImages[index]) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                            Image(systemName: "person.circle.fill").foregroundColor(.secondary)
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 2))
                    }
                    Text("By \(playlist.owner.displayName)")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 12)
                }

                HStack(spacing: 8) {
                    Button(action: { Task { onPlay(await musicManager.play(contextUri: playlist.uri)) } }) {
                        Label("Play", systemImage: "play.fill")
                    }

                    Button(action: {
                        Task {
                            onPlay(await musicManager.play(contextUri: playlist.uri))
                            try? await Task.sleep(for: .seconds(0.5))
                            await musicManager.toggleShuffle()
                        }
                    }) {
                        Label("Shuffle", systemImage: "shuffle")
                    }

                    Menu {
                        Picker("Sort by", selection: $sortOption) {
                            ForEach(availableSortOptions) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down.circle")
                    }
                    .pickerStyle(.inline)
                    .disabled(isIndexing)

                    Button {
                        sortDirection = sortDirection == .ascending ? .descending : .ascending
                    } label: {
                        Label("Direction", systemImage: sortDirection == .ascending ? "arrow.up" : "arrow.down")
                    }
                    .disabled(isIndexing)
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(CapsuleButtonStyle())
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut, value: sortOption)
        .animation(.easeInOut, value: sortDirection)
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct UnifiedTrackRow: View {
    @ObservedObject var viewModel: TrackViewModel
    let contextUri: String
    var onPlay: (PlaybackResult) -> Void
    @State private var isHovered = false
    @EnvironmentObject var musicManager: MusicManager

    private var dateAddedString: String? {
        guard let timestamp = viewModel.dateAdded else { return nil }
        return timestamp.timeAgoDisplay()
    }

    private var albumName: String? {
        viewModel.trackDetails?.albumOfTrack.name ?? viewModel.albumName
    }

    private var formattedPublicationDate: String? {
        guard let isoString = viewModel.trackDetails?.albumOfTrack.publishDate?.isoString else {
            return viewModel.publicationYear.map { String($0) } ??
                   (viewModel.trackDetails?.albumOfTrack.publishDate?.year.map { String($0) })
        }
        guard let date = isoDateFormatter.date(from: isoString) else { return nil }
        return displayDateFormatter.string(from: date)
    }

    private var finalPlayCount: Int? {
        viewModel.trackDetails?.playcountInt ?? viewModel.playCount
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                CachedAsyncImage(url: viewModel.imageURL) { $0.resizable() } placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note") } }
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)

                if isHovered {
                    Color.black.opacity(0.5)
                        .cornerRadius(6)
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.name).fontWeight(.medium).lineLimit(1)
                Text(viewModel.artists).font(.subheadline).foregroundColor(.secondary).lineLimit(1)

                if let albumName = albumName {
                    HStack(spacing: 4) {
                        Text(albumName)
                        if let fullDate = formattedPublicationDate {
                            Text("•")
                            Text(fullDate)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.trackDetails)

            Spacer()

            HStack(spacing: 20) {
                if let dateAdded = dateAddedString {
                    Text(dateAdded)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.8))
                        .frame(width: 40, alignment: .trailing)
                        .help("Date Added")
                }

                if let count = finalPlayCount {
                    PlayCountIndicator(playCount: count)
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(isHovered ? 0.1 : 0.05))
        .cornerRadius(10)
        .onHover { hovering in self.isHovered = hovering }
        .onTapGesture { performPlayback() }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func performPlayback() {
        Task {
            let index = musicManager.spotifyPrivateAPI.selectedPlaylist?.content.items.firstIndex(where: { $0.uid == viewModel.uid })
            let result = await musicManager.play(
                trackUri: viewModel.uri,
                contextUri: self.contextUri,
                trackUid: viewModel.uid,
                trackIndex: index
            )
            onPlay(result)
        }
    }
}

fileprivate extension TimeInterval {
    func timeAgoDisplay() -> String {
        let date = Date(timeIntervalSince1970: self)
        let secondsAgo = Int(Date().timeIntervalSince(date))

        let minute = 60
        let hour = 60 * minute
        let day = 24 * hour
        let week = 7 * day
        let month = 4 * week
        let year = 12 * month

        if secondsAgo < minute { return "\(secondsAgo)s" }
        else if secondsAgo < hour { return "\(secondsAgo / minute)m" }
        else if secondsAgo < day { return "\(secondsAgo / hour)h" }
        else if secondsAgo < week { return "\(secondsAgo / day)d" }
        else if secondsAgo < month { return "\(secondsAgo / week)w" }
        else if secondsAgo < year { return "\(secondsAgo / month)mo" }
        else { return "\(secondsAgo / year)y" }
    }
}