//
//  SpotifyNowPlayingExtras.swift
//  Sapphire
//
//  Artist profile, concerts, and related discovery chips for the notch music player.
//

import SwiftUI
import AppKit

struct SpotifyNowPlayingExtras: View {
    @EnvironmentObject var musicManager: MusicManager

    private var artist: SpotifyArtistProfile? {
        musicManager.spotifyPrivateAPI.nowPlayingArtist
    }

    private var concerts: [SpotifyArtistConcert] {
        musicManager.spotifyPrivateAPI.artistConcerts
    }

    private var related: [SpotifyRecommendedTrack] {
        Array(musicManager.spotifyPrivateAPI.relatedTracks.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let artist {
                HStack(spacing: 10) {
                    if let url = artist.avatarURL ?? artist.headerImageURL {
                        CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                            Circle().fill(Color.white.opacity(0.08))
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(artist.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if artist.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.cyan)
                            }
                        }
                        if let listeners = artist.monthlyListeners {
                            Text(formattedCount(listeners) + " monthly listeners")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            if !concerts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(concerts.prefix(4)) { concert in
                            HStack(spacing: 6) {
                                Image(systemName: "ticket.fill").font(.caption2)
                                Text("\(concert.title) · \(concert.city)")
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            if !related.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(related) { track in
                            Button {
                                Task {
                                    _ = await musicManager.play(trackUri: track.uri, contextUri: nil)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles").font(.caption2)
                                    Text(track.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

struct ArtistProfileCard: View {
    let artist: SpotifyArtistProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let url = artist.avatarURL ?? artist.headerImageURL {
                    CachedAsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(artist.name).font(.headline.bold()).lineLimit(1)
                        if artist.isVerified {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(.cyan)
                        }
                    }
                    if let listeners = artist.monthlyListeners {
                        Text("\(listeners.formatted()) monthly listeners")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !artist.topCities.isEmpty {
                        Text(artist.topCities.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if !artist.biography.isEmpty {
                Text(artist.biography)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SimilarAlbumCard: View {
    let album: SpotifySimilarAlbum
    var onPlay: (PlaybackResult) -> Void
    @EnvironmentObject var musicManager: MusicManager

    var body: some View {
        Button {
            Task {
                onPlay(await musicManager.play(contextUri: album.uri))
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(url: album.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    ZStack {
                        Color.secondary.opacity(0.25)
                        Image(systemName: "opticaldisc")
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(album.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                Text(album.artistName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ConcertCard: View {
    let concert: SpotifyArtistConcert

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "ticket.fill")
                .font(.title3)
                .foregroundColor(.pink)
            Text(concert.title)
                .font(.caption.bold())
                .lineLimit(2)
                .frame(width: 130, alignment: .leading)
            Text(concert.venue.isEmpty ? concert.city : "\(concert.venue), \(concert.city)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(width: 130, alignment: .leading)
            if !concert.startDateIsoString.isEmpty {
                Text(concert.startDateIsoString.prefix(10))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(width: 150, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MerchCard: View {
    let item: SpotifyArtistMerch

    var body: some View {
        Button {
            if let url = URL(string: item.uri) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(url: item.imageURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    ZStack {
                        Color.secondary.opacity(0.25)
                        Image(systemName: "tshirt")
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.name)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .frame(width: 110, alignment: .leading)
                if let price = item.price {
                    Text(price)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
