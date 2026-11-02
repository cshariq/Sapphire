//
//  MusicSettingsTabs.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-26

import AppKit
import MusicKit
import SwiftUI

enum MusicSettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case player = "Player"
    case features = "Features"
    case accounts = "Accounts"
    case lyrics = "Lyrics"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: String(localized: "General")
        case .player: String(localized: "Player")
        case .features: String(localized: "Features")
        case .accounts: String(localized: "Accounts")
        case .lyrics: String(localized: "Lyrics")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .player: return "play.rectangle"
        case .features: return "sparkles"
        case .accounts: return "person.crop.circle"
        case .lyrics: return "quote.bubble"
        }
    }
}

// MARK: - Player features (shared by Spotify and Apple Music)

struct MusicPlayerFeaturesCard: View {
    @EditingSettings var settings: SettingsEditingSession
    let isSpotifyAvailable: Bool

    enum Service {
        case spotify, appleMusic

        var title: String { self == .spotify ? "Spotify" : "Apple Music" }
        var color: Color { self == .spotify ? .green : .pink }
        var icon: String { self == .spotify ? "dot.radiowaves.left.and.right" : "music.note" }
    }

    var body: some View {
        SettingsCard(
            title: "Player Features",
            description: "Extras shown in the music player. Each one applies to every service that supports it."
        ) {
            if !isSpotifyAvailable {
                InfoContainer(
                    text: "Spotify extras need the Spotify Private API login in the Accounts tab. Apple Music extras work without it.",
                    iconName: "info.circle",
                    color: .blue
                )
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            row("Artist Profile",
                "Show the artist's picture next to their name. Spotify adds the verified check and monthly listeners; Apple Music adds genre, release year and your play count.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowArtistProfile)
            Divider().padding(.leading, 20)
            row("Popularity",
                "Show the track's popularity score. Apple Music scores come from stats.fm and need no login.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.showPopularityInMusicPlayer)
            Divider().padding(.leading, 20)
            row("Next Song",
                "Show the upcoming track from the queue under the now-playing title.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowNextSong)
            Divider().padding(.leading, 20)
            row("Next Song Album Art",
                "Show album art beside the upcoming track in the live activity.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowNextSongAlbumArt)
                .disabled(!settings.settings.spotifyShowNextSong)
            Divider().padding(.leading, 20)
            row("Suggested Songs",
                "Show song chips you can play from the music player: related tracks on Spotify, more by the artist on Apple Music.",
                services: [.spotify, .appleMusic],
                isOn: $settings.settings.spotifyShowSuggestedSongs)
            Divider().padding(.leading, 20)
            row("Concert Tickets",
                "Show a compact tickets button when nearby concerts are available for the artist.",
                services: [.spotify],
                isOn: $settings.settings.spotifyShowConcertTickets)
            Divider().padding(.leading, 20)
            row("Account Badge",
                "Show the Premium / Free account badge next to the track title.",
                services: [.spotify],
                isOn: $settings.settings.spotifyShowAccountBadge)
        }
    }

    private func row(_ title: LocalizedStringKey, _ description: LocalizedStringKey, services: [Service], isOn: Binding<Bool>) -> some View {
        let available = services.contains(.appleMusic) || isSpotifyAvailable
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(services, id: \.title) { service in
                        StatusCapsuleLabel(title: Text(verbatim: service.title), color: service.color, icon: service.icon)
                    }
                }
            }
            Spacer(minLength: 8)
            SettingsSwitch(title: title, isOn: isOn)
        }
        .padding()
        .disabled(!available)
        .opacity(available ? 1 : 0.5)
    }
}

// MARK: - Apple Music account

struct AppleMusicAccountCard: View {
    private var musicKit: MusicKitAppleMusicManager { .shared }
    @State private var isRequesting = false

    private var account: AppleMusicAccountState { musicKit.account }

    var body: some View {
        SettingsCard(
            title: "Apple Music",
            description: "Sapphire uses MusicKit for Apple Music artwork, artist details, the queue and your library. No login is needed beyond Apple Music access."
        ) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon).foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                    if let detail = statusDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                actionButton
            }
            .padding()
        }
        .onAppear { musicKit.refreshAuthorizationStatus() }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch account.authorization {
        case .notDetermined:
            Button(isRequesting ? String(localized: "Requesting…") : String(localized: "Allow Access")) {
                isRequesting = true
                Task {
                    await AppleMusicManager.shared.requestAuthorization()
                    isRequesting = false
                }
            }
            .disabled(isRequesting)
        case .denied, .restricted:
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                    NSWorkspace.shared.open(url)
                }
            }
        default:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch account.authorization {
        case .authorized: return account.canPlayCatalogContent ? String(localized: "Connected · Apple Music subscription") : String(localized: "Connected · no subscription")
        case .notDetermined: return String(localized: "Not connected")
        case .denied: return String(localized: "Access is off")
        case .restricted: return String(localized: "Access is restricted")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private var statusDetail: String? {
        if let error = account.lastError { return error }
        switch account.authorization {
        case .authorized:
            return account.canPlayCatalogContent ? nil : String(localized: "Library and Music.app playback work; catalog playback needs a subscription.")
        case .notDetermined:
            return String(localized: "Allow access to show artwork, artist profiles and Up Next for Apple Music.")
        case .denied, .restricted:
            return String(localized: "Turn on Sapphire in System Settings › Privacy & Security › Media & Apple Music.")
        @unknown default:
            return nil
        }
    }

    private var statusIcon: String {
        switch account.authorization {
        case .authorized: return "checkmark.circle.fill"
        case .notDetermined: return "circle.dashed"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch account.authorization {
        case .authorized: return .green
        case .notDetermined: return .secondary
        default: return .orange
        }
    }
}