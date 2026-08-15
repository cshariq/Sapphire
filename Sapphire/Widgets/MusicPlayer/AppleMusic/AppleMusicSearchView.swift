//
//  AppleMusicSearchView.swift
//  Sapphire
//
//  Discover / Search pane for Apple Music using the free iTunes Search API.
//  No API key required. Opens results in Apple Music via URL scheme.
//

import SwiftUI
import AppKit

// MARK: - iTunes Search API models

private struct ITunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [ITunesTrack]
}

private struct ITunesTrack: Decodable, Identifiable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let collectionName: String?
    let artworkUrl100: String?
    let trackViewUrl: String?
    let previewUrl: String?
    let primaryGenreName: String?
    let releaseDate: String?

    var id: Int { trackId }
    var artworkURL: URL? {
        guard let raw = artworkUrl100 else { return nil }
        // Bump to 300×300 for crisper display
        return URL(string: raw.replacingOccurrences(of: "100x100bb", with: "300x300bb"))
    }
}

// MARK: - View Model

@MainActor
private class AppleMusicSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [ITunesTrack] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    private var searchTask: Task<Void, Never>?

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; hasSearched = false; return }

        searchTask?.cancel()
        isSearching = true
        errorMessage = nil

        searchTask = Task {
            // Small debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                .init(name: "term",    value: trimmed),
                .init(name: "media",   value: "music"),
                .init(name: "entity",  value: "song"),
                .init(name: "limit",   value: "30"),
                .init(name: "country", value: Locale.current.region?.identifier ?? "US"),
            ]
            guard let url = components.url else { return }

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest  = 10
            config.timeoutIntervalForResource = 15

            do {
                let (data, _) = try await URLSession(configuration: config).data(from: url)
                guard !Task.isCancelled else { return }
                let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
                self.results     = decoded.results
                self.isSearching = false
                self.hasSearched = true
            } catch is CancellationError {
                self.isSearching = false
            } catch {
                self.errorMessage = "Search failed: \(error.localizedDescription)"
                self.isSearching = false
                self.hasSearched = true
            }
        }
    }

    func openInAppleMusic(_ track: ITunesTrack) {
        // music:// deep-link plays the track directly in Apple Music
        let encoded = track.trackName
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let artistEncoded = track.artistName
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "music://music.apple.com/search?term=\(encoded)+\(artistEncoded)") {
            NSWorkspace.shared.open(url)
        } else if let fallback = track.trackViewUrl.flatMap(URL.init) {
            NSWorkspace.shared.open(fallback)
        }
    }
}

// MARK: - View

struct AppleMusicSearchView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var vm = AppleMusicSearchViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search Apple Music…", text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .onSubmit { vm.search() }
                    .onChange(of: vm.query) { _, _ in vm.search() }
                if vm.isSearching {
                    ProgressView().controlSize(.small)
                } else if !vm.query.isEmpty {
                    Button {
                        vm.query = ""
                        vm.results = []
                        vm.hasSearched = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Results / placeholder
            Group {
                if let error = vm.errorMessage {
                    centeredPlaceholder(systemImage: "wifi.exclamationmark", label: error)
                } else if vm.isSearching && vm.results.isEmpty {
                    centeredPlaceholder(systemImage: "magnifyingglass", label: "Searching…")
                } else if vm.results.isEmpty && vm.hasSearched {
                    centeredPlaceholder(systemImage: "music.note", label: "No results for \"\(vm.query)\"")
                } else if vm.results.isEmpty {
                    // Seed with current track's artist when idle
                    let seed = musicManager.artist ?? ""
                    centeredPlaceholder(
                        systemImage: "music.quarternote.3",
                        label: seed.isEmpty ? "Search for songs, artists or albums" : "Discover more like \(seed)"
                    )
                    .onAppear {
                        if !seed.isEmpty && vm.query.isEmpty {
                            vm.query = seed
                            vm.search()
                        }
                    }
                } else {
                    resultsList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(vm.results) { track in
                    ITunesTrackRow(track: track) {
                        vm.openInAppleMusic(track)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func centeredPlaceholder(systemImage: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Track Row

private struct ITunesTrackRow: View {
    let track: ITunesTrack
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                CachedAsyncImage(url: track.artworkURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.trackName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
