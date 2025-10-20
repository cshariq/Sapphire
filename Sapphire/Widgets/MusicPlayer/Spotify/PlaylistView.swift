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
    let playlistItem: SpotifyPlaylistDetailsResponse.PlaylistItem
    @Published var trackDetails: SpotifyTrackDetailsResponse.TrackUnion?
    private var isHydrating = false

    var id: String { playlistItem.uid }

    init(playlistItem: SpotifyPlaylistDetailsResponse.PlaylistItem) {
        self.playlistItem = playlistItem
    }

    func hydrate(completion: (() -> Void)? = nil) {
        guard !isHydrating, trackDetails == nil else {
            completion?()
            return
        }
        isHydrating = true

        Task {
            guard let trackUri = playlistItem.itemV2.data.uri, let trackId = trackUri.components(separatedBy: ":").last else {
                await MainActor.run {
                    self.isHydrating = false
                    completion?()
                }
                return
            }

            let details = await SpotifyPrivateAPIManager.shared.fetchTrackDetails(trackId: trackId)

            await MainActor.run {
                self.trackDetails = details
                self.isHydrating = false
                completion?()
            }
        }
    }
}

struct PlaylistView: View {
    let playlist: SpotifyPlaylist
    let isLockScreenMode: Bool

    @StateObject private var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared
    @EnvironmentObject private var musicManager: MusicManager

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

    private let playlistSortStateKey = "playlistSortDescriptors"

    init(playlist: SpotifyPlaylist, isLockScreenMode: Bool = false) {
        self.playlist = playlist
        self.isLockScreenMode = isLockScreenMode
    }

    private var sortedViewModels: [TrackViewModel] {
        if sortOption == .defaultOrder {
            return sortDirection == .ascending ? spotifyPrivateAPI.playlistTrackViewModels : spotifyPrivateAPI.playlistTrackViewModels.reversed()
        }

        return spotifyPrivateAPI.playlistTrackViewModels.sorted { lhs, rhs in
            let result: ComparisonResult = {
                switch sortOption {
                case .title:
                    let l = lhs.trackDetails?.name ?? lhs.playlistItem.itemV2.data.name
                    let r = rhs.trackDetails?.name ?? rhs.playlistItem.itemV2.data.name
                    return l.localizedStandardCompare(r)
                case .artist:
                    let l = lhs.trackDetails?.artists.items.first?.profile.name ?? lhs.playlistItem.itemV2.data.artists.items.first?.profile.name ?? ""
                    let r = rhs.trackDetails?.artists.items.first?.profile.name ?? rhs.playlistItem.itemV2.data.artists.items.first?.profile.name ?? ""
                    return l.localizedStandardCompare(r)
                case .album:
                    let l = lhs.trackDetails?.albumOfTrack.name ?? lhs.playlistItem.itemV2.data.albumOfTrack.name
                    let r = rhs.trackDetails?.albumOfTrack.name ?? rhs.playlistItem.itemV2.data.albumOfTrack.name
                    return l.localizedStandardCompare(r)
                case .dateAdded:
                    let l = lhs.playlistItem.addedAt ?? 0
                    let r = rhs.playlistItem.addedAt ?? 0
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .publicationDate:
                    let l = lhs.trackDetails?.albumOfTrack.publishDate?.year ?? 0
                    let r = rhs.trackDetails?.albumOfTrack.publishDate?.year ?? 0
                    if l == 0 && r != 0 { return .orderedDescending }
                    if l != 0 && r == 0 { return .orderedAscending }
                    return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
                case .playCount:
                    let l = lhs.trackDetails?.playcountInt ?? lhs.playlistItem.itemV2.data.playcountInt ?? 0
                    let r = rhs.trackDetails?.playcountInt ?? rhs.playlistItem.itemV2.data.playcountInt ?? 0
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
                if spotifyPrivateAPI.playlistTrackViewModels.isEmpty {
                    if spotifyPrivateAPI.isPlaylistLoading {
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
            spotifyPrivateAPI.playlistTrackViewModels = []
            if playlist.uri.contains(":collection") || playlist.uri.contains(":tracks") {
                await spotifyPrivateAPI.loadLikedSongs(for: playlist)
            } else {
                await spotifyPrivateAPI.loadPlaylist(playlistId: playlist.id)
            }
            loadSortState()
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
        guard sortOption.requiresHydration, !isIndexing else { return }

        let viewModels = spotifyPrivateAPI.playlistTrackViewModels
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
                            ForEach(PlaylistView.SortOption.allCases) { option in
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

    private var name: String { viewModel.trackDetails?.name ?? viewModel.playlistItem.itemV2.data.name }
    private var artists: String {
        let allArtists = (viewModel.trackDetails?.artists.items ?? []) + (viewModel.trackDetails?.otherArtists.items ?? [])
        if !allArtists.isEmpty { return allArtists.map { $0.profile.name }.joined(separator: ", ") }
        return viewModel.playlistItem.itemV2.data.artists.items.map { $0.profile.name }.joined(separator: ", ")
    }
    private var imageURL: URL? { viewModel.trackDetails?.albumOfTrack.coverArt.bestImageURL ?? viewModel.playlistItem.itemV2.data.imageURL }
    private var uri: String { viewModel.trackDetails?.uri ?? viewModel.playlistItem.itemV2.data.uri! }
    private var playCount: Int? { viewModel.trackDetails?.playcountInt ?? viewModel.playlistItem.itemV2.data.playcountInt }

    private var dateAddedString: String? {
        guard let timestamp = viewModel.playlistItem.addedAt else { return nil }
        return timestamp.timeAgoDisplay()
    }

    private var albumName: String? {
        viewModel.trackDetails?.albumOfTrack.name
    }

    private var formattedPublicationDate: String? {
        guard let isoString = viewModel.trackDetails?.albumOfTrack.publishDate?.isoString,
              let date = isoDateFormatter.date(from: isoString) else {
            return viewModel.trackDetails?.albumOfTrack.publishDate?.year.map { String($0) }
        }
        return displayDateFormatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                CachedAsyncImage(url: imageURL) { $0.resizable() } placeholder: { ZStack { Color.secondary.opacity(0.3); Image(systemName: "music.note") } }
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
                Text(name).fontWeight(.medium).lineLimit(1)
                Text(artists).font(.subheadline).foregroundColor(.secondary).lineLimit(1)

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

                if let count = playCount {
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
            let result = await musicManager.play(
                trackUri: self.uri,
                contextUri: self.contextUri,
                trackUid: viewModel.id,
                trackIndex: musicManager.spotifyPrivateAPI.selectedPlaylist?.content.items.firstIndex(where: { $0.uid == viewModel.id })
            )
            onPlay(result)
        }
    }
}

fileprivate struct PlayCountIndicator: View {
    let playCount: Int

    private var metrics: (color: Color, bars: [CGFloat]) {
        if playCount > 500_000_000 { return (.green, [5, 7, 9, 11]) }
        if playCount > 100_000_000 { return (.yellow, [5, 7, 9, 7]) }
        if playCount > 10_000_000 { return (.secondary, [5, 7, 7, 5]) }
        return (.secondary.opacity(0.3), [5, 5, 5, 5])
    }

    private func formatNumber(_ n: Int) -> String {
        let num = Double(n)
        if num >= 1_000_000_000 { return String(format: "%.1fB", num / 1_000_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000).replacingOccurrences(of: ".0", with: "") }
        if num >= 1_000 { return String(format: "%.1fK", num / 1_000).replacingOccurrences(of: ".0", with: "") }
        return "\(n)"
    }

    var body: some View {
        let TMetrics = metrics
        HStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(TMetrics.bars.indices.contains(index) ? TMetrics.color : Color.clear)
                        .frame(width: 3, height: TMetrics.bars.indices.contains(index) ? TMetrics.bars[index] : 5)
                }
            }
            Text(formatNumber(playCount))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(TMetrics.color.opacity(0.8))
        }
        .help("Total Plays: \(playCount.formatted())")
    }
}

fileprivate struct PopularityIndicator: View {
    let popularity: Int
    private var color: Color { if popularity >= 75 { return .green }; if popularity >= 40 { return .yellow }; return .secondary }
    private var estimatedPlays: Int { let p = Double(popularity); let basePlays = pow(p / 10, 4) * 100; let randomFactor = Double.random(in: 0.8...1.2); return Int(basePlays * randomFactor) }
    private func formatNumber(_ n: Int) -> String { let num = Double(n); if num >= 1_000_000_000 { return String(format: "%.1fB", num / 1_000_000_000).replacingOccurrences(of: ".0", with: "") }; if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000).replacingOccurrences(of: ".0", with: "") }; if num >= 1_000 { return String(format: "%.1fK", num / 1_000).replacingOccurrences(of: ".0", with: "") }; return "\(n)" }
    var body: some View {
        HStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) { ForEach(0..<4) { index in Capsule().fill(popularity > (index * 25) ? color : Color.secondary.opacity(0.3)).frame(width: 3, height: CGFloat(index * 2 + 5)) } }
            Text(formatNumber(estimatedPlays)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(color.opacity(0.8))
        }.help("Popularity Score: \(popularity)/100")
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