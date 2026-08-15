//
//  SpotifyConnectCommands.swift
//  Sapphire
//
//  Connect playback helpers. Sapphire is a hidden controller — audio always
//  plays on an external Spotify device (desktop app, phone, speaker).
//

import Foundation

struct SpotifyColorLyrics: Decodable {
    let lyrics: LyricsBlock?

    struct LyricsBlock: Decodable {
        let syncType: String?
        let lines: [Line]

        struct Line: Decodable {
            let startTimeMs: String
            let words: String
            let endTimeMs: String?

            enum CodingKeys: String, CodingKey {
                case startTimeMs, words, endTimeMs
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let stringValue = try? container.decode(String.self, forKey: .startTimeMs) {
                    startTimeMs = stringValue
                } else if let intValue = try? container.decode(Int.self, forKey: .startTimeMs) {
                    startTimeMs = String(intValue)
                } else if let doubleValue = try? container.decode(Double.self, forKey: .startTimeMs) {
                    startTimeMs = String(Int(doubleValue))
                } else {
                    startTimeMs = "0"
                }
                words = try container.decodeIfPresent(String.self, forKey: .words) ?? ""
                if let endString = try? container.decode(String.self, forKey: .endTimeMs) {
                    endTimeMs = endString
                } else if let endInt = try? container.decode(Int.self, forKey: .endTimeMs) {
                    endTimeMs = String(endInt)
                } else {
                    endTimeMs = nil
                }
            }
        }
    }
}

struct SpotifyClipTranscript: Decodable {
    let words: [TranscriptWord]?
    let speakers: [TranscriptSpeaker]?

    struct TranscriptWord: Decodable {
        let text: String?
        let startTimeMs: Int?
        let endTimeMs: Int?
    }

    struct TranscriptSpeaker: Decodable {
        let id: String?
        let name: String?
    }
}

struct SpotifyJamSession: Decodable {
    let session: SessionInfo?

    struct SessionInfo: Decodable {
        let id: String?
        let isActive: Bool?
    }
}

struct SpotifyPopularRelease: Identifiable, Hashable {
    let id: String
    let name: String
    let uri: String
    let imageURL: URL?
}


extension SpotifyPrivateAPIManager {

    // MARK: Connect Playback

    /// Play on an external Connect speaker. Sapphire itself is never the target.
    @discardableResult
    func connectPlay(
        trackUri: String,
        contextUri: String?,
        trackUid: String? = nil,
        trackIndex: Int? = nil
    ) async -> PlaybackResult {
        guard isLoggedIn, let deviceId = controllerDeviceID else {
            return .failure(reason: "Spotify private API is not logged in.")
        }

        do {
            let resolvedTrackURI = trackUri.isEmpty ? (playerState?.track?.uri ?? trackUri) : trackUri
            // Skip cluster refresh when WebSocket already populated devices.
            if devices.isEmpty || activePlayerDeviceID == nil {
                try? await refreshPlayerAndDeviceState()
            }
            guard let playbackDevice = preferredExternalPlaybackDeviceID(excluding: deviceId) else {
                let reason = "Open the Spotify desktop app or another speaker to play audio."
                await MainActor.run {
                    self.isConnectStreamingSession = false
                    self.deviceTransferNotice = reason
                }
                return .failure(reason: reason)
            }

            let fromDevice = activePlayerDeviceID ?? deviceId
            if fromDevice != playbackDevice {
                try await transferDevice(from: fromDevice, to: playbackDevice)
            }

            let playTrackURI = trackUri.isEmpty ? resolvedTrackURI : trackUri
            // Track-as-context often fails on Connect; prefer an album/playlist context when given,
            // otherwise resolve the album URI for single-track / suggested plays.
            let resolvedContext = await resolvePlayContextURI(
                trackUri: playTrackURI,
                preferredContextURI: contextUri
            )
            try await pythonCompatiblePlay(
                trackUri: playTrackURI,
                contextUri: resolvedContext,
                trackUid: trackUid,
                trackIndex: trackIndex,
                targetDeviceID: playbackDevice
            )
            let deviceName = devices.first(where: { $0.deviceId == playbackDevice })?.name ?? "another device"
            await MainActor.run {
                self.isConnectStreamingSession = true
                self.deviceTransferNotice = "Playing on \(deviceName)."
                self.scheduleDeviceTransferNoticeClear()
            }
            print("[SpotifyConnect] Playback on \(deviceName) (\(playbackDevice.prefix(8))…)")
            return .success
        } catch {
            print("[SpotifyConnect] play failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isConnectStreamingSession = false
                self.deviceTransferNotice = "Couldn’t start playback: \(error.localizedDescription)"
                self.scheduleDeviceTransferNoticeClear()
            }
            return .failure(reason: error.localizedDescription)
        }
    }

    func preferredExternalPlaybackDeviceID(excluding deviceId: String) -> String? {
        // Prefer the currently active speaker if it isn't Sapphire.
        if let active = activePlayerDeviceID,
           active != deviceId,
           active != controllerDeviceID,
           devices.contains(where: { $0.deviceId == active }) {
            return active
        }

        let ranked = devices.filter { $0.deviceId != deviceId && $0.deviceId != controllerDeviceID }
        // Prefer Spotify desktop / computer on this Mac (actual speakers) over phones.
        if let desktop = ranked.first(where: { device in
            let name = device.name.lowercased()
            let type = device.deviceType.lowercased()
            guard !name.contains("sapphire") else { return false }
            return type == "computer" || name.contains("mac") || name == "spotify"
        }) {
            return desktop.deviceId
        }
        if let phone = ranked.first(where: { device in
            let name = device.name.lowercased()
            let type = device.deviceType.lowercased()
            return !name.contains("sapphire") && (type.contains("smartphone") || type.contains("tablet") || name.contains("iphone"))
        }) {
            return phone.deviceId
        }
        return ranked.first(where: { !$0.name.lowercased().contains("sapphire") })?.deviceId
            ?? ranked.first?.deviceId
    }

    /// Prefer a real album/playlist context; track-as-context is unreliable for Connect play.
    private func resolvePlayContextURI(trackUri: String, preferredContextURI: String?) async -> String {
        if let preferred = preferredContextURI?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty,
           !preferred.contains(":track:") {
            return preferred
        }
        if let preferred = preferredContextURI, preferred.contains(":album:") || preferred.contains(":playlist:") {
            return preferred
        }

        // Resolve album from track metadata when suggestions only pass a track URI.
        if !trackUri.isEmpty {
            let decorated = await decorateContextTracks(uris: [trackUri])
            if let albumURI = decorated.first?.albumOfTrack.uri, !albumURI.isEmpty {
                return albumURI
            }
        }

        // Last resort: track URI itself (some devices still accept it).
        return preferredContextURI ?? trackUri
    }

    func connectSeek(to seconds: TimeInterval) async {
        let clamped = max(0, seconds)
        let ms = Int(clamped * 1000)
        await sendConnectCommand(endpoint: "seek_to", extra: ["value": ms])
    }

    func connectSkipNext() async {
        await sendConnectCommand(endpoint: "skip_next")
    }

    func connectSkipPrevious() async {
        await sendConnectCommand(endpoint: "skip_prev")
    }

    /// Append a track to the Connect queue via `add_to_queue`.
    func addToQueue(uri: String, uid: String? = nil, metadata: [String: String] = [:]) async -> Bool {
        var meta = metadata
        if meta["title"] == nil { meta["title"] = "Queued Track" }
        let trackUID = uid ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var extra: [String: Any] = [
            "track": [
                "uri": uri,
                "uid": trackUID,
                "metadata": meta,
                "provider": "queue"
            ] as [String: Any]
        ]
        if let revision = playerState?.queueRevision {
            extra["queue_revision"] = revision
        }
        let ok = await sendConnectCommandReturning(endpoint: "add_to_queue", extra: extra)
        if ok {
            // Optimistic local append so UI updates before cluster refresh.
            let optimistic = PlayerState.Track(
                uri: uri,
                uid: trackUID,
                metadata: .init(
                    title: meta["title"],
                    albumTitle: meta["album_title"],
                    artistName: meta["artist_name"],
                    artistUri: nil,
                    imageUrl: meta["image_url"],
                    imageSmallUrl: nil,
                    imageLargeUrl: meta["image_url"],
                    imageXlargeUrl: nil,
                    contextUri: meta["context_uri"],
                    hidden: nil
                )
            )
            await MainActor.run {
                if !self.nativeQueue.contains(where: { $0.uid == trackUID }) {
                    self.nativeQueue.append(optimistic)
                }
            }
            try? await refreshPlayerAndDeviceState()
        }
        return ok
    }

    /// Remove a queued track by uid via `set_queue`.
    func removeFromQueue(uid: String) async -> Bool {
        let sourceQueue = await MainActor.run { self.nativeQueue }
        let remaining = sourceQueue.filter { $0.uid != uid }
        guard remaining.count != sourceQueue.count else { return false }

        let next = connectQueueTrackPayloads(from: remaining)
        let prev = connectQueueTrackPayloads(from: playerState?.prevTracks ?? [])
        var extra: [String: Any] = [
            "next_tracks": next,
            "prev_tracks": prev
        ]
        if let revision = playerState?.queueRevision {
            extra["queue_revision"] = revision
        }

        // Optimistic UI update first so the row disappears immediately.
        await MainActor.run { self.nativeQueue = remaining }

        let ok = await sendConnectCommandReturning(endpoint: "set_queue", extra: extra)
        try? await refreshPlayerAndDeviceState()
        if !ok {
            // Roll back if the command failed.
            await MainActor.run { self.nativeQueue = sourceQueue }
        }
        return ok
    }

    private func connectQueueTrackPayloads(from tracks: [PlayerState.Track]) -> [[String: Any]] {
        tracks.map { track in
            var metadata: [String: String] = [:]
            if let title = track.metadata?.title { metadata["title"] = title }
            if let artist = track.metadata?.artistName { metadata["artist_name"] = artist }
            if let album = track.metadata?.albumTitle { metadata["album_title"] = album }
            if let image = track.metadata?.imageUrl ?? track.metadata?.imageLargeUrl {
                metadata["image_url"] = image
            }
            if let context = track.metadata?.contextUri ?? playerState?.contextUri {
                metadata["context_uri"] = context
            }
            return [
                "uri": track.uri,
                "uid": track.uid,
                "metadata": metadata,
                "provider": "queue"
            ] as [String: Any]
        }
    }

    @discardableResult
    func sendConnectCommandReturning(endpoint: String, extra: [String: Any] = [:]) async -> Bool {
        guard let from = controllerDeviceID,
              let to = activePlayerDeviceID ?? controllerDeviceID,
              let spclient = spclientClient else {
            print("[SpotifyConnect] connect command \(endpoint) skipped — missing device/spclient")
            return false
        }
        let path = "/connect-state/v1/player/command/from/\(from)/to/\(to)"
        var command: [String: Any] = [
            "endpoint": endpoint,
            "logging_params": [
                "command_id": generateRandomHexString(length: 32),
                "page_instance_ids": [] as [String],
                "interaction_ids": [] as [String]
            ]
        ]
        for (key, value) in extra { command[key] = value }
        let payload: [String: Any] = ["command": command]
        do {
            _ = try await spclient.post(path: path, jsonBody: payload)
            return true
        } catch {
            print("[SpotifyConnect] connect command \(endpoint) failed: \(error.localizedDescription)")
            return false
        }
    }

    private func applyQueueRevision(nextTracks: [[String: Any]]) async -> Bool {
        var extra: [String: Any] = [
            "next_tracks": nextTracks,
            "prev_tracks": connectQueueTrackPayloads(from: playerState?.prevTracks ?? [])
        ]
        if let revision = playerState?.queueRevision {
            extra["queue_revision"] = revision
        }
        let ok = await sendConnectCommandReturning(endpoint: "set_queue", extra: extra)
        try? await refreshPlayerAndDeviceState()
        return ok
    }

    func clearConnectControlSession() {
        Task { @MainActor in self.isConnectStreamingSession = false }
    }

    // MARK: Connect Commands (self-targeted)

    func sendConnectCommand(endpoint: String, extra: [String: Any] = [:]) async {
        _ = await sendConnectCommandReturning(endpoint: endpoint, extra: extra)
    }

    // MARK: Additional API Features

    func fetchColorLyrics(trackId: String, imageURL: String) async -> [LyricLine] {
        guard let client = wgSpclientClient else { return [] }
        let rawId = SpotifyIDConverter.rawID(from: trackId)
        let normalizedImage = Self.normalizedLyricsImageURL(imageURL)

        // encodeURIComponent-style: encode `/` so the image URL is a single path segment.
        // Web Player uses: /color-lyrics/v2/track/{id}/image/https%3A%2F%2Fi.scdn.co%2Fimage%2F…
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")

        let query = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "vocalRemoval", value: "false"),
            URLQueryItem(name: "market", value: "from_token")
        ]

        var candidates: [(path: String, query: [URLQueryItem])] = []
        if !normalizedImage.isEmpty,
           let encodedImage = normalizedImage.addingPercentEncoding(withAllowedCharacters: allowed) {
            candidates.append(("/color-lyrics/v2/track/\(rawId)/image/\(encodedImage)", query))
        }
        candidates.append(("/color-lyrics/v2/track/\(rawId)", query))

        let headers = [
            "Accept": "application/json",
            "app-platform": "WebPlayer",
            "spotify-app-version": clientVersion ?? "1.2.95.452.g5c9bdf32"
        ]

        for candidate in candidates {
            do {
                let response = try await client.get(
                    path: candidate.path,
                    queryItems: candidate.query,
                    additionalHeaders: headers
                )
                guard (200...299).contains(response.statusCode), !response.body.isEmpty else {
                    let snippet = String(data: response.body.prefix(120), encoding: .utf8) ?? ""
                    print("[SpotifyConnect] color-lyrics HTTP \(response.statusCode) for \(candidate.path.prefix(80)): \(snippet)")
                    continue
                }
                if let lines = decodeColorLyrics(response.body) {
                    return lines
                }
            } catch {
                print("[SpotifyConnect] color-lyrics \(candidate.path.prefix(80)) failed: \(error.localizedDescription)")
            }
        }
        return []
    }

    /// Web Player color-lyrics expects an https://i.scdn.co/image/… URL (not spotify:image:).
    private static func normalizedLyricsImageURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("spotify:image:") {
            let id = trimmed.replacingOccurrences(of: "spotify:image:", with: "")
            return "https://i.scdn.co/image/\(id)"
        }
        if trimmed.hasPrefix("//") { return "https:\(trimmed)" }
        return trimmed
    }

    private func decodeColorLyrics(_ data: Data) -> [LyricLine]? {
        do {
            let decoded = try JSONDecoder().decode(SpotifyColorLyrics.self, from: data)
            let lines = decoded.lyrics?.lines.compactMap { line -> LyricLine? in
                let ms: Int
                if let asInt = Int(line.startTimeMs) {
                    ms = asInt
                } else if let asDouble = Double(line.startTimeMs) {
                    ms = Int(asDouble)
                } else {
                    return nil
                }
                let text = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text != "♪" else {
                    return LyricLine(text: text.isEmpty ? "♪" : text, timestamp: TimeInterval(ms) / 1000.0, translatedText: nil)
                }
                return LyricLine(text: text, timestamp: TimeInterval(ms) / 1000.0, translatedText: nil)
            } ?? []
            return lines.isEmpty ? nil : lines
        } catch {
            let snippet = String(data: data.prefix(240), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
            print("[SpotifyConnect] color-lyrics decode failed: \(error.localizedDescription)\nSnippet: \(snippet)")
            return nil
        }
    }

    func fetchClipTranscript(episodeURI: String, startSeconds: Double = 0, endSeconds: Double = 60) async -> SpotifyClipTranscript? {
        guard let client = wgSpclientClient else { return nil }
        let encoded = SpotifyIDConverter.pathEncodedURI(episodeURI)
        let path = "/clip-transcript/v1/transcripts/\(encoded)"
        let query = [
            URLQueryItem(name: "offsets.start", value: String(format: "%.3fs", startSeconds)),
            URLQueryItem(name: "offsets.end", value: String(format: "%.3fs", endSeconds))
        ]
        do {
            let response = try await client.get(path: path, queryItems: query)
            return try JSONDecoder().decode(SpotifyClipTranscript.self, from: response.body)
        } catch {
            return nil
        }
    }

    func fetchJamSession() async -> Bool {
        guard let client = wgSpclientClient else { return false }
        do {
            let response = try await client.get(path: "/social-connect/v2/sessions/current")
            let decoded = try JSONDecoder().decode(SpotifyJamSession.self, from: response.body)
            let active = decoded.session?.isActive ?? false
            publishExtendedState(jamSessionActive: active)
            return active
        } catch {
            return false
        }
    }

    func fetchLibraryImportEligible() async -> Bool {
        guard let client = wgSpclientClient else { return false }
        do {
            let response = try await client.get(path: "/library-import/v1/eligible")
            if let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
               let eligible = json["eligible"] as? Bool {
                publishExtendedState(libraryImportEligible: eligible)
                return eligible
            }
        } catch { }
        return false
    }

    func fetchPopularReleases(artistId: String) async -> [SpotifyPopularRelease] {
        guard let client = wgSpclientClient else { return [] }
        let path = "/playlist/v2/list/popular-release-segments-main-roles/artist_\(artistId)"
        do {
            let response = try await client.get(path: path)
            guard let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }
            let releases = items.compactMap { item -> SpotifyPopularRelease? in
                guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
                let imageURL = (item["image"] as? [String: Any])?["url"] as? String
                return SpotifyPopularRelease(
                    id: uri,
                    name: name,
                    uri: uri,
                    imageURL: imageURL.flatMap { URL(string: $0) }
                )
            }
            publishExtendedState(popularReleases: releases)
            return releases
        } catch {
            return []
        }
    }

    func lookupChildEntities(uris: [String]) async -> [URL] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: LookupChildResponse = try await pathfinderQuery(
                operationName: "lookupChildEntities",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.lookupEntities.compactMap { entity in
                entity.visualIdentityTrait?.squareCoverImage?.image?.data?.sources?.first?.url.flatMap { URL(string: $0) }
            }
        } catch {
            return []
        }
    }

    func checkIsCurated(uris: [String]) async -> [Bool] {
        guard !uris.isEmpty else { return [] }
        do {
            let response: IsCuratedResponse = try await pathfinderQuery(
                operationName: "isCurated",
                variables: ["uris": uris],
                sendAsBody: true,
                useV2Endpoint: true
            )
            return response.data.lookup.map { $0.data?.isCurated ?? false }
        } catch {
            return []
        }
    }

    func fetchExtendedMetadata(trackURI: String) async -> [String: Any]? {
        guard let client = wgSpclientClient else { return nil }
        let payload: [String: Any] = [
            "entityRequest": [[
                "entityUri": trackURI,
                "query": [["extensionKind": 249, "etag": ""]]
            ]]
        ]
        do {
            let response = try await client.post(path: "/extended-metadata/v0/extended-metadata", jsonBody: payload)
            return try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        } catch {
            return nil
        }
    }

    func collectionContains(set: String, uris: [String]) async -> [Bool] {
        guard let client = wgSpclientClient, let username = userProfile?.profile.username else { return [] }
        let payload: [String: Any] = [
            "username": username,
            "set": set,
            "items": uris.map { ["uri": $0] }
        ]
        do {
            let response = try await client.post(path: "/collection/v2/contains?market=from_token", jsonBody: payload)
            let decoded = try JSONDecoder().decode(CollectionContainsResponse.self, from: response.body)
            return decoded.found
        } catch {
            return []
        }
    }
}

// MARK: - Response Wrappers

private struct LookupChildResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookupEntities: [EntityNode]
    }
    struct EntityNode: Decodable {
        let visualIdentityTrait: VisualTrait?
    }
    struct VisualTrait: Decodable {
        let squareCoverImage: CoverImage?
    }
    struct CoverImage: Decodable {
        let image: ImageData?
    }
    struct ImageData: Decodable {
        let data: ImageSources?
    }
    struct ImageSources: Decodable {
        let sources: [Source]?
    }
    struct Source: Decodable {
        let url: String?
    }
}

private struct IsCuratedResponse: Decodable {
    let data: DataNode
    struct DataNode: Decodable {
        let lookup: [LookupItem]
    }
    struct LookupItem: Decodable {
        let data: CuratedData?
    }
    struct CuratedData: Decodable {
        let isCurated: Bool?
    }
}

private struct CollectionContainsResponse: Decodable {
    let found: [Bool]
}

