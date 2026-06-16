//
//  MusicManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-05
//

import Foundation
import AppKit
import Combine
import SwiftUI
import AudioToolbox
import ImageIO

@MainActor
class MusicManager: ObservableObject {
    static let shared = MusicManager()

    // MARK: - Specialized Sub-Managers
    lazy var appleMusic = AppleMusicManager.shared
    lazy var spotifyAppleScript = SpotifyAppleScriptManager.shared
    lazy var spotifyOfficialAPI = SpotifyOfficialAPIManager.shared
    lazy var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared
    lazy var defaultControls = DefaultMusicManager.shared
    lazy var browserAppleScript = BrowserAppleScriptManager.shared

    // MARK: - Proxied Authentication States
    @Published var officialAPIHasKeys: Bool = false
    @Published var isOfficialAPIAuthenticated: Bool = false
    @Published var isPrivateAPIAuthenticated: Bool = false
    @Published var isPremiumUser: Bool = false

    // MARK: - Published UI State
    let playbackTimePublisher = PassthroughSubject<(elapsed: TimeInterval, progress: Double), Never>()
    let volumePublisher = PassthroughSubject<Float, Never>()
    let currentLyricPublisher = PassthroughSubject<LyricLine?, Never>()
    let trackDidChange = PassthroughSubject<Void, Never>()

    @Published var title: String? { didSet { handleTrackIdentifierChange() } }
    @Published var artist: String? { didSet { handleTrackIdentifierChange() } }
    @Published var album: String?
    @Published var artworkURL: URL?
    @Published var artwork: NSImage?
    @Published var uri: String?
    @Published var trackID: String?
    @Published var transientIcon: WaveformView.TransientIcon? = nil
    
    @Published var isPlaying: Bool = false {
        didSet(wasPlaying) {
            self.isWaveformAnimating = isPlaying
            if !isPlaying && wasPlaying {
                if title != nil { showTransientIcon(for: .paused) }
            } else if isPlaying && !wasPlaying {
                if transientIcon == .paused {
                    transientIconTimer?.invalidate()
                    transientIcon = nil
                }
            }
            refreshTimers()
        }
    }

    func setDetailPlayerOpen(_ isOpen: Bool) {
        guard isDetailPlayerOpen != isOpen else { return }
        isDetailPlayerOpen = isOpen
        print("[MusicManager:Timing] Detail Player open state changed to: \(isOpen)")
        refreshTimers()
        if isOpen {
            // Force an immediate precise calculation of the current elapsed time upon opening
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
        refreshLyricsLoadingState()
        refreshArtworkColorExtractionIfNeeded()
    }

    func setLyricsDetailOpen(_ isOpen: Bool) {
        guard isLyricsDetailOpen != isOpen else { return }
        isLyricsDetailOpen = isOpen
        print("[MusicManager:Timing] Lyrics View open state changed to: \(isOpen)")
        refreshTimers()
        if isOpen {
            // Force an immediate precise calculation of the current elapsed time upon opening
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
        refreshLyricsLoadingState()
    }

    func setDetachedLyricsOpen(_ isOpen: Bool) {
        guard isDetachedLyricsOpen != isOpen else { return }
        isDetachedLyricsOpen = isOpen
        print("[MusicManager:Timing] Detached Lyrics Window state changed to: \(isOpen)")
        refreshTimers()
        if isOpen {
            // Force an immediate precise calculation of the current elapsed time upon opening
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
        refreshLyricsLoadingState()
    }

    func setMusicLiveActivityActive(_ isActive: Bool) {
        guard isMusicLiveActivityActive != isActive else { return }
        isMusicLiveActivityActive = isActive
        refreshTimers()
        refreshLyricsLoadingState()
        refreshArtworkColorExtractionIfNeeded()
    }

    @Published var totalDuration: TimeInterval = 0
    @Published var lyrics: [LyricLine] = []
    @Published var accentColor: Color = .white
    @Published var leftGradientColor: Color = .white
    @Published var rightGradientColor: Color = .white
    @Published var appIcon: NSImage?
    @Published var shouldShowLiveActivity: Bool = false
    @Published var popularity: Int?
    @Published var playCount: String?
    @Published var fetchedSpotifyPopularity: Int?
    @Published var isLiked: Bool = false
    @Published var shuffleState: Bool = false
    @Published var repeatState: RepeatMode = .off
    @Published var lastTrackChangeDate: Date?
    @Published var isHoveringAlbumArt: Bool = false
    @Published var showQuickPeek: Bool = false
    @Published var lyricsTapped: Bool = false
    @Published var isWaveformAnimating: Bool = false
    @Published private(set) var lastKnownBundleID: String?
    @Published private(set) var currentTrackArtworkToken: String = ""
    @Published var airplayDevices: [AirPlayDevice] = []
    
    // Multi-source support
    @Published var activeMediaSources: [String: TrackInfo] = [:]
    @Published var currentSourceKey: String?

    // Spotify Specific State (Queues)
    @Published var nativeQueue: [PlayerState.Track] = []
    @Published var nowPlayingTrack: PlayerState.Track?

    @Published private(set) var currentLyric: LyricLine?
    @Published private(set) var isDetailPlayerOpen: Bool = false
    @Published private(set) var isLyricsDetailOpen: Bool = false
    @Published private(set) var isDetachedLyricsOpen: Bool = false
    @Published private(set) var isMusicLiveActivityActive: Bool = false
    private(set) var systemVolume: Float = 0.0

    // Non-published layout properties to prevent high-frequency global body redraw cascades
    private(set) var currentElapsedTime: TimeInterval = 0
    private(set) var playbackProgress: Double = 0.0

    // MARK: - Private Properties
    private let mediaController = NativeMediaController()
    private let lyricsFetcher = LyricsFetcher()
    private let settingsModel = SettingsModel.shared

    private var lyricsFetchTask: Task<Void, Never>?
    private var lyricsTranslationTask: Task<Void, Never>?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var currentTrackDuration: TimeInterval = 0
    private var lastFetchedTitle: String?
    private var cancellables = Set<AnyCancellable>()
    private var quickPeekTimer: Timer?
    private var airplayDeviceUpdateTimer: Timer?
    private var transientIconTimer: Timer?
    private var searchDebouncer = Debouncer(delay: 0.5)
    private var lastLyricLookupSecond: Int = -1
    private var currentLyricIndex: Int? = nil

    // OPTIMIZATION: Throttled scrubber loop down to 5 FPS (0.2s) to drastically reduce CPU rendering workloads [3]
    private var detailPlayerTimer: Timer?
    private var liveActivityTimer: Timer?
    private var latestTrackPayload: TrackInfo.Payload?
    private var playbackTimingAnchor: PlaybackTimingAnchor?
    private var lastPlaybackSyncWasPlaying = false
    private var lastTrackIdentity: String?
    private var lastMediaFingerprint: String?
    private var currentlyFetchingFingerprint: String?
    private var artworkFetchGeneration = 0
    private var artworkColorExtractionTask: Task<Void, Never>?

    private var lyricsCache: [String: [LyricLine]] = [:]
    private let lyricsCacheQueue = DispatchQueue(label: "com.sapphire.lyricsCache", attributes: .concurrent)

    private var needsLyricsUpdates: Bool {
        if isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen { return true }
        guard settingsModel.settings.showLyricsInLiveActivity,
              settingsModel.settings.musicLiveActivityEnabled,
              isMusicLiveActivityActive else { return false }
        return ActiveAppMonitor.shared.isLyricsAllowedForActiveApp
    }

    private var shouldExtractArtworkColors: Bool {
        isDetailPlayerOpen || isMusicLiveActivityActive
    }

    private init() {
        spotifyOfficialAPI.$hasApiKeys.assign(to: &$officialAPIHasKeys)
        spotifyOfficialAPI.$isAuthenticated.assign(to: &$isOfficialAPIAuthenticated)
        spotifyPrivateAPI.$isLoggedIn.assign(to: &$isPrivateAPIAuthenticated)
        spotifyOfficialAPI.$isPremiumUser.assign(to: &$isPremiumUser)

        spotifyPrivateAPI.$nativeQueue
            .receive(on: DispatchQueue.main)
            .assign(to: &$nativeQueue)

        spotifyPrivateAPI.$playerState
            .map { $0?.track }
            .receive(on: DispatchQueue.main)
            .assign(to: &$nowPlayingTrack)

        spotifyPrivateAPI.$playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self, let state = state else { return }
                self.shuffleState = state.options?.shufflingContext ?? false
                let rC = state.options?.repeatingContext ?? false
                let rT = state.options?.repeatingTrack ?? false
                if rT { self.repeatState = .track }
                else if rC { self.repeatState = .context }
                else { self.repeatState = .off }
            }
            .store(in: &cancellables)

        setupHandlers()
        setupNotificationObservers()
        setupVolumeListener()
        setupDerivedStatePublisher()
        setupSettingsObserver()
        mediaController.startListening()
    }

    deinit {
        Task { @MainActor in self.removeVolumeListener() }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        quickPeekTimer?.invalidate()
        airplayDeviceUpdateTimer?.invalidate()
        transientIconTimer?.invalidate()
        Task { @MainActor in self.invalidateAllTimers() }
    }

    // MARK: - Core Playback Actions

    func play() { defaultControls.play() }
    func pause() { defaultControls.pause() }
    func nextTrack() { defaultControls.nextTrack() }
    func previousTrack() { defaultControls.previousTrack() }
    
    func seek(to seconds: Double) {
        defaultControls.seek(to: seconds)
        applyOptimisticSeek(to: seconds)
    }

    func seek(by seconds: TimeInterval) {
        let potentialNewTime = self.currentElapsedTime + seconds
        let newTime = max(0.0, min(potentialNewTime, self.totalDuration))
        defaultControls.seek(to: newTime)
    }

    func play(trackUri: String, contextUri: String?, trackUid: String? = nil, trackIndex: Int? = nil) async -> PlaybackResult {
        if spotifyPrivateAPI.isLoggedIn {
            return await playWithPrivateAPI(trackUri: trackUri, contextUri: contextUri, trackUid: trackUid, trackIndex: trackIndex)
        } else if spotifyOfficialAPI.isPremiumUser {
            return await spotifyOfficialAPI.playTrack(uri: trackUri)
        } else {
            return await spotifyAppleScript.play(uri: trackUri)
        }
    }

    func play(contextUri: String) async -> PlaybackResult {
        return await play(trackUri: "", contextUri: contextUri, trackUid: nil, trackIndex: 0)
    }

    private func playWithPrivateAPI(trackUri: String, contextUri: String?, trackUid: String?, trackIndex: Int?) async -> PlaybackResult {
        do {
            guard let targetDeviceID = await findTargetDeviceID() else {
                return .failure(reason: "No available Spotify players found.")
            }
            let finalContextUri = contextUri ?? trackUri
            try await spotifyPrivateAPI.pythonCompatiblePlay(
                trackUri: trackUri, contextUri: finalContextUri,
                trackUid: trackUid, trackIndex: trackIndex, targetDeviceID: targetDeviceID
            )
            return .success
        } catch {
            return .failure(reason: "Private API play command failed: \(error.localizedDescription)")
        }
    }

    private func findTargetDeviceID() async -> String? {
        try? await spotifyPrivateAPI.refreshPlayerAndDeviceState()
        if let activeDeviceID = spotifyPrivateAPI.activePlayerDeviceID, activeDeviceID != spotifyPrivateAPI.controllerDeviceID { return activeDeviceID }
        let availablePlayers = spotifyPrivateAPI.devices.filter { $0.deviceId != spotifyPrivateAPI.controllerDeviceID }
        return availablePlayers.first(where: { $0.deviceType.lowercased() == "computer" })?.deviceId ?? availablePlayers.first?.deviceId
    }

    // MARK: - Rating & Mode Actions

    func toggleLike() {
        let newLikedState = !self.isLiked
        self.isLiked = newLikedState
        Task {
            var success = false
            if self.lastKnownBundleID == "com.apple.Music" {
                appleMusic.setLiked(isLiked: newLikedState); success = true
            } else if let trackId = self.trackID {
                if spotifyPrivateAPI.isLoggedIn {
                    success = newLikedState ? await spotifyPrivateAPI.likeTrack(trackURI: "spotify:track:\(trackId)") : await spotifyPrivateAPI.unlikeTrack(trackURI: "spotify:track:\(trackId)")
                } else if spotifyOfficialAPI.isAuthenticated {
                    success = newLikedState ? await spotifyOfficialAPI.likeTrack(id: trackId) : await spotifyOfficialAPI.unlikeTrack(id: trackId)
                }
            }
            if !success { self.isLiked = !newLikedState }
        }
    }

    func toggleShuffle() {
        let newShuffleState = !self.shuffleState
        self.shuffleState = newShuffleState
        Task {
            if self.lastKnownBundleID == "com.apple.Music" {
                appleMusic.setShuffle(enabled: newShuffleState)
            } else if spotifyPrivateAPI.isLoggedIn {
                _ = await spotifyPrivateAPI.setShuffle(state: newShuffleState)
            }
        }
    }

    func cycleRepeatMode() {
        let newRepeatState = self.repeatState.next()
        self.repeatState = newRepeatState
        Task {
            if self.lastKnownBundleID == "com.apple.Music" {
                appleMusic.setRepeat(mode: newRepeatState)
            } else if spotifyPrivateAPI.isLoggedIn {
                _ = await spotifyPrivateAPI.setRepeatMode(mode: newRepeatState)
            }
        }
    }

    func setSpotifyVolume(percent: Int) async -> Bool {
        let asResult = await spotifyAppleScript.setVolume(percent: percent)
        if case .success = asResult { return true }
        if isPremiumUser {
            let result = await spotifyOfficialAPI.setVolume(percent: percent)
            if case .success = result { return true }
        }
        if spotifyPrivateAPI.isLoggedIn { return await spotifyPrivateAPI.setVolume(percent: percent) }
        return false
    }

    // MARK: - Multi-Source State Management

    func appName(for bundleID: String?) -> String {
        guard let bundleID = bundleID else { return "Unknown" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }

    func selectSource(key: String) {
        currentSourceKey = key
        if let track = activeMediaSources[key] {
            applyTrackPayload(track.payload, sourceKey: key)
        }
    }

    private func setupHandlers() {
        mediaController.onActiveClientsChanged = { [weak self] clients in
            Task { @MainActor in
                guard let self = self else { return }
                self.activeMediaSources = clients

                if self.currentSourceKey == nil || clients[self.currentSourceKey!] == nil {
                    if let playingKey = clients.first(where: { $0.value.payload.isPlaying == true })?.key {
                        self.selectSource(key: playingKey)
                    } else if let firstKey = clients.keys.first {
                        self.selectSource(key: firstKey)
                    } else {
                        self.clearPlayerState()
                    }
                } else if let key = self.currentSourceKey, let track = clients[key] {
                    if self.hasMediaChanged(track.payload) {
                        self.applyTrackPayload(track.payload, sourceKey: key)
                    } else if track.payload.artwork != nil && self.artwork == nil {
                        self.applyTrackPayload(track.payload, sourceKey: key)
                    } else {
                        self.applyPlaybackRefresh(track.payload)
                    }
                }
            }
        }

        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor in
                guard let self = self, let track = trackInfo else { return }
                let bundle = track.payload.bundleIdentifier ?? "unknown"
                let pid = track.payload.processIdentifier.map(String.init) ?? "0"
                let newKey = "\(bundle):\(pid)"

                if let playing = self.resolvedIsPlaying(from: track.payload) {
                    if self.currentSourceKey == newKey {
                        self.isPlaying = playing
                    }
                }

                if track.payload.isPlaying == true && self.currentSourceKey != newKey {
                    self.selectSource(key: newKey)
                }
            }
        }

        mediaController.onListenerTerminated = { print("[MusicManager] Native media stream lost. Restarting.") }
        mediaController.onDecodingError = { error, _ in print("[MusicManager] Error decoding system media: \(error)") }
    }

    private func applyTrackPayload(_ payload: TrackInfo.Payload, sourceKey: String) {
        self.latestTrackPayload = payload
        guard let title = payload.title, !title.isEmpty else {
            if self.title != nil { return }
            self.clearPlayerState()
            return
        }

        let sourceBundleID = self.normalizeBundleID(payload.bundleIdentifier) ?? "N/A"
        let trackIdentity = self.trackIdentity(for: payload)
        let hasTrackChanged = hasMediaChanged(payload)

        if payload.title != self.title { self.title = payload.title }
        if payload.artist != self.artist { self.artist = payload.artist }
        if payload.album != self.album { self.album = payload.album }

        if hasTrackChanged {
            self.lastTrackIdentity = trackIdentity
            let fingerprint = mediaFingerprint(for: payload)
            self.lastMediaFingerprint = fingerprint.isEmpty ? nil : fingerprint
            self.lastFetchedTitle = payload.title
            self.currentTrackArtworkToken = trackIdentity
            self.resetLyricsState()
            self.triggerQuickPeek()
            self.lastTrackChangeDate = Date()
            self.fetchAndTranslateLyricsIfNeeded()
            self.trackDidChange.send()

            // Apply natively streamed artwork immediately with no disk or memory delay
            if let newArtwork = payload.artwork {
                self.applyArtwork(newArtwork, trackIdentity: trackIdentity)
            } else {
                self.requestArtworkForTrack(payload: payload, trackIdentity: trackIdentity)
            }
        } else if let newArtwork = payload.artwork {
            self.applyArtwork(newArtwork, trackIdentity: trackIdentity)
        }

        if let newIsPlaying = resolvedIsPlaying(from: payload) { self.isPlaying = newIsPlaying }
        
        self.currentTrackDuration = TimeInterval(payload.durationMicros ?? 0) / 1_000_000
        self.totalDuration = self.currentTrackDuration

        syncPlaybackTiming(from: payload, trackChanged: hasTrackChanged)

        if sourceBundleID != self.lastKnownBundleID {
            self.lastKnownBundleID = sourceBundleID
            self.fetchAppIcon(for: sourceBundleID)
            self.updateDevicePolling()
        }
    }

    private func applyPlaybackRefresh(_ payload: TrackInfo.Payload) {
        latestTrackPayload = payload

        let playStateChanged: Bool
        if let newIsPlaying = resolvedIsPlaying(from: payload) {
            playStateChanged = newIsPlaying != isPlaying
            isPlaying = newIsPlaying
        } else {
            playStateChanged = false
        }

        let duration = TimeInterval(payload.durationMicros ?? 0) / 1_000_000
        if duration > 0, abs(duration - totalDuration) > 0.5 {
            currentTrackDuration = duration
            totalDuration = duration
        }

        syncPlaybackTiming(from: payload, trackChanged: false, publishImmediately: true)
    }

    private func resolvedIsPlaying(from payload: TrackInfo.Payload) -> Bool? {
        if let isPlaying = payload.isPlaying { return isPlaying }
        if let rate = payload.playbackRate { return rate != 0 }
        return nil
    }

    // MARK: - Logic & Helpers

    private func handleTrackIdentifierChange() {
        if fetchedSpotifyPopularity != nil { fetchedSpotifyPopularity = nil }
        guard let currentTitle = self.title, let currentArtist = self.artist, !currentTitle.isEmpty, !currentArtist.isEmpty else { return }
        self.popularity = nil; self.playCount = nil; self.isLiked = false

        Task {
            if self.lastKnownBundleID == "com.apple.Music" {
                self.isLiked = appleMusic.isTrackLiked()
                self.shuffleState = appleMusic.getShuffleState()
                self.repeatState = appleMusic.getRepeatState()
            } else if self.lastKnownBundleID == "com.spotify.client" {
                if let track = await searchForTrack(title: currentTitle, artist: currentArtist) {
                    self.uri = track.uri; self.trackID = track.id; self.popularity = track.popularity
                    if spotifyPrivateAPI.isLoggedIn {
                        if let details = await spotifyPrivateAPI.fetchTrackDetails(trackId: track.id) { self.playCount = details.playcount }
                    }
                    if self.playCount == nil, let count = await PlayCountFetcher.shared.getPlayCount(for: track.id) { self.playCount = count }
                }
            }
        }
    }
    
    private func searchForTrack(title: String, artist: String) async -> SpotifyTrack? {
        if spotifyPrivateAPI.isLoggedIn {
            return await spotifyPrivateAPI.searchForTrack(title: title, artist: artist)
        } else if spotifyOfficialAPI.isAuthenticated {
            return await spotifyOfficialAPI.searchForTrack(title: title, artist: artist)
        }
        return nil
    }
    
    func transferSpotifyPlayback(to deviceId: String) async -> PlaybackResult {
        if spotifyPrivateAPI.isLoggedIn {
            let success = await spotifyPrivateAPI.transferPlayback(to: deviceId)
            return success ? .success : .failure(reason: "Private API transfer failed.")
        } else if isPremiumUser {
            return await spotifyOfficialAPI.transferPlayback(to: deviceId)
        }
        return .requiresPremium
    }
        
    func fetchActiveSpotifyDeviceState() async -> ActiveSpotifyDeviceState? {
        if spotifyPrivateAPI.isLoggedIn {
            try? await spotifyPrivateAPI.refreshPlayerAndDeviceState()
            guard let playerState = spotifyPrivateAPI.playerState, playerState.isPlaying == true,
                  let activeDeviceID = spotifyPrivateAPI.activePlayerDeviceID else { return nil }

            if let activeDevice = spotifyPrivateAPI.devices.first(where: { $0.deviceId == activeDeviceID }) {
                let volumePercent = activeDevice.volume.map { Int((Double($0) / 65535.0) * 100.0) }
                let canControlVolume = (activeDevice.capabilities.volumeSteps ?? 0) > 0
                return ActiveSpotifyDeviceState(
                    name: activeDevice.name,
                    type: activeDevice.deviceType,
                    volumePercent: volumePercent,
                    iconName: iconName(for: activeDevice.deviceType),
                    canControlVolume: canControlVolume
                )
            }
        } else if isOfficialAPIAuthenticated {
            if let state = await spotifyOfficialAPI.fetchPlaybackState(), state.isPlaying {
                let canControlVolume = state.device.volumePercent != nil
                return ActiveSpotifyDeviceState(
                    name: state.device.name,
                    type: state.device.type,
                    volumePercent: state.device.volumePercent,
                    iconName: iconName(for: state.device.type),
                    canControlVolume: canControlVolume
                )
            }
        }
        return nil
    }
    
    private func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "macbook.gen2"
        case "speaker": return "hifispeaker.2.fill"
        case "smartphone": return "iphone"
        case "avr", "stb": return "tv.inset.filled"
        case "tv", "castvideo": return "appletv"
        case "castaudio": return "hifispeaker.2.fill"
        default: return "hifispeaker.2.fill"
        }
    }
    
    private func normalizeBundleID(_ bundleID: String?) -> String? {
        guard let bundleID = bundleID else { return nil }
        switch bundleID {
        case "com.apple.WebKit.GPU", "com.apple.WebKit.WebContent": return "com.apple.Safari"
        case let id where id.starts(with: "com.google.Chrome.helper"): return "com.google.Chrome"
        case let id where id.starts(with: "com.microsoft.edgemac.helper"): return "com.microsoft.edgemac"
        case "company.thebrowser.Browser.helper": return "company.thebrowser.Browser"
        default: return bundleID
        }
    }

    private func syncPlaybackTiming(from payload: TrackInfo.Payload, trackChanged: Bool, publishImmediately: Bool = true) {
        let isPlayingNow = payload.isPlaying ?? isPlaying
        guard let incomingAnchor = payload.playbackTimingAnchor(isPlayingNow: isPlayingNow) else { return }

        playbackTimingAnchor = incomingAnchor
        lastPlaybackSyncWasPlaying = isPlayingNow

        publishPlaybackTime(
            force: trackChanged || publishImmediately,
            includeProgressUI: (isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen)
        )
    }

    private func applyOptimisticSeek(to seconds: TimeInterval) {
        let clamped = totalDuration > 0 ? max(0, min(totalDuration, seconds)) : max(0, seconds)
        let rate = isPlaying ? Double(latestTrackPayload?.playbackRate ?? 1.0) : 0
        playbackTimingAnchor = PlaybackTimingAnchor(
            elapsedAtSample: clamped,
            sampleEpochTime: Date().timeIntervalSince1970,
            rate: rate
        )
        publishPlaybackTime(force: true)
    }

    private func publishPlaybackTime(force: Bool = false, includeProgressUI: Bool? = nil) {
        let exactTime: TimeInterval
        let source: String
        
        if let anchor = playbackTimingAnchor {
            exactTime = anchor.elapsed(at: Date())
            source = "Anchor (Sample: \(anchor.elapsedAtSample)s, Rate: \(anchor.rate), Age: \(Date().timeIntervalSince1970 - anchor.sampleEpochTime)s)"
        } else if let payload = latestTrackPayload {
            exactTime = payload.interpolatedElapsedTime(at: Date())
            source = "Payload Interpolation (Sample: \(payload.currentElapsedTime ?? 0)s)"
        } else {
            print("[MusicManager:Timing] WARNING: Cannot publish playback time. No timing anchor or payload available.")
            return
        }

        let duration = totalDuration
        let clampedElapsed = duration > 0 ? max(0.0, min(duration, exactTime)) : max(0.0, exactTime)
        let progress = duration > 0 ? max(0.0, min(1.0, clampedElapsed / duration)) : 0.0

        let publishesProgress = includeProgressUI ?? (isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen)
        let elapsedThreshold = publishesProgress ? 0.025 : 0.45
        let elapsedDelta = abs(clampedElapsed - currentElapsedTime)
        
        if force {
            print("[MusicManager:Timing] Forcing update. Calculated elapsed: \(clampedElapsed)s / \(duration)s (\(progress * 100)%) via \(source)")
        }

        if !force, elapsedDelta < elapsedThreshold {
            return
        }

        currentElapsedTime = clampedElapsed
        if publishesProgress {
            playbackProgress = progress
            playbackTimePublisher.send((elapsed: clampedElapsed, progress: progress))
        }
        if needsLyricsUpdates {
            updateCurrentLyric(for: clampedElapsed)
        }
    }

    private func clearPlayerState() {
        self.latestTrackPayload = nil; self.currentSourceKey = nil
        invalidateAllTimers()
        playbackTimingAnchor = nil
        lastPlaybackSyncWasPlaying = false
        lastTrackIdentity = nil
        lastMediaFingerprint = nil
        currentTrackArtworkToken = ""
        self.title = nil; self.artist = nil; self.album = nil; self.artwork = nil; self.artworkURL = nil
        self.uri = nil; self.trackID = nil; self.popularity = nil; self.playCount = nil
        self.isPlaying = false; self.totalDuration = 0; self.currentElapsedTime = 0
        self.resetLyricsState()
    }

    private func refreshTimers() {
        let needsDetailTimer = isPlaying && (isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen)
        let needsActivityTimer = isPlaying && isMusicLiveActivityActive && settingsModel.settings.showLyricsInLiveActivity && settingsModel.settings.musicLiveActivityEnabled

        // OPTIMIZATION: Throttled scrubber loop down to 5 FPS (0.2s) to drastically reduce CPU rendering workloads [3]
        if needsDetailTimer {
            if detailPlayerTimer == nil {
                print("[MusicManager:Timing] Starting 5 FPS low-overhead playback timer.")
                let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                    guard let self = self, self.isPlaying else { return }
                    self.publishPlaybackTime(includeProgressUI: true)
                }
                detailPlayerTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            if detailPlayerTimer != nil {
                print("[MusicManager:Timing] Stopping 5 FPS playback timer.")
                detailPlayerTimer?.invalidate()
                detailPlayerTimer = nil
            }
        }

        if needsActivityTimer && !needsDetailTimer {
            if liveActivityTimer == nil {
                print("[MusicManager:Timing] Starting 1 Hz Live Activity fallback timer.")
                let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self, self.isPlaying else { return }
                    self.publishPlaybackTime(includeProgressUI: false)
                }
                liveActivityTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            if liveActivityTimer != nil {
                print("[MusicManager:Timing] Stopping 1 Hz Live Activity fallback timer.")
                liveActivityTimer?.invalidate()
                liveActivityTimer = nil
            }
        }
    }

    private func invalidateAllTimers() {
        detailPlayerTimer?.invalidate()
        detailPlayerTimer = nil
        liveActivityTimer?.invalidate()
        liveActivityTimer = nil
    }

    func trimExpandedUIMemory() {
        trimArtworkCache()
        trimLyricsCache()
        mediaController.trimArtworkCache(keeping: lastTrackIdentity)

        if !needsLyricsUpdates {
            resetLyricsState()
        }
        appIcon = nil
    }

    func trimArtworkCache() {
        // Stateless: Memory and disk maps are freed automatically on track update.
    }

    func trimLyricsCache() {
        guard let key = lastMediaFingerprint else {
            lyricsCacheQueue.async(flags: .barrier) {
                self.lyricsCache.removeAll()
            }
            return
        }
        lyricsCacheQueue.async(flags: .barrier) {
            var filtered = self.lyricsCache
            filtered.removeValue(forKey: key)
            if filtered.count > 50 {
                filtered.removeAll()
            }
            self.lyricsCache = filtered
        }
    }

    private func hasMediaChanged(_ payload: TrackInfo.Payload) -> Bool {
        let fingerprint = mediaFingerprint(for: payload)
        if !fingerprint.isEmpty {
            return fingerprint != lastMediaFingerprint
        }
        return trackIdentity(for: payload) != lastTrackIdentity
    }

    private func mediaFingerprint(for payload: TrackInfo.Payload) -> String {
        [payload.title, payload.artist, payload.album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
            .lowercased()
    }

    private func trackIdentity(for payload: TrackInfo.Payload) -> String {
        if let id = payload.contentItemIdentifier, !id.isEmpty { return "cid:\(id)" }
        if let id = payload.uniqueIdentifier, !id.isEmpty { return "uid:\(id)" }
        let fingerprint = mediaFingerprint(for: payload)
        return fingerprint.isEmpty ? "unknown" : "fp:\(fingerprint)"
    }

    private func prefetchArtworkIfNeeded(payload: TrackInfo.Payload, trackIdentity: String) {
        // Stateless: Stream loads direct base64 automatically.
    }

    private func requestArtworkForTrack(payload: TrackInfo.Payload, trackIdentity: String) {
        let generation = artworkFetchGeneration
        let title = payload.title
        let artist = payload.artist
        let album = payload.album

        if let artwork = payload.artwork {
            self.applyArtwork(artwork, trackIdentity: trackIdentity)
            return
        }

        Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let (artwork, _) = await self.mediaController.fetchArtworkForTrack(
                expectedIdentity: trackIdentity,
                title: title,
                artist: artist,
                album: album
            )

            guard self.artworkFetchGeneration == generation,
                  self.lastTrackIdentity == trackIdentity,
                  let artwork = artwork else { return }
                  
            self.applyArtwork(artwork, trackIdentity: trackIdentity)
        }
    }

    private func applyArtwork(_ displayArtwork: NSImage, trackIdentity: String? = nil) {
        if let trackIdentity, trackIdentity != lastTrackIdentity { return }
        self.artwork = displayArtwork
        self.artworkURL = nil
        refreshArtworkColorExtractionIfNeeded()
    }

    private func refreshArtworkColorExtractionIfNeeded() {
        artworkColorExtractionTask?.cancel()
        guard shouldExtractArtworkColors, let artwork = artwork else { return }

        artworkColorExtractionTask = Task { @MainActor in
            guard !Task.isCancelled, self.shouldExtractArtworkColors else { return }
            if let edgeColors = artwork.getEdgeColors() {
                self.accentColor = edgeColors.accent
                self.leftGradientColor = edgeColors.left
                self.rightGradientColor = edgeColors.right
            } else {
                self.resetColorsToDefault()
            }
        }
    }

    private func refreshLyricsLoadingState() {
        if needsLyricsUpdates {
            if lyrics.isEmpty {
                print("[MusicManager:Lyrics] Dedicated view opened but lyrics list is empty. Triggering fetch.")
                fetchAndTranslateLyricsIfNeeded()
            } else {
                print("[MusicManager:Lyrics] Dedicated view opened. Syncing current active lyric line.")
                updateCurrentLyric(for: currentElapsedTime)
            }
        }
    }

    func openInSourceApp() {
        guard let bundleId = lastKnownBundleID else { return }
        if bundleId == "com.apple.Music" { appleMusic.revealCurrentTrack(); return }
        if ["com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.apple.Safari"].contains(bundleId) {
            guard let trackTitle = self.title else {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) { NSWorkspace.shared.open(appURL) }
                return
            }
            browserAppleScript.focusTab(for: bundleId, with: trackTitle); return
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) { NSWorkspace.shared.open(appURL) }
    }

    // MARK: - Lyrics & UI Helpers

    private func fetchAndTranslateLyricsIfNeeded() {
        guard let title = self.title, let artist = self.artist, let album = self.album else {
            print("[MusicManager:Lyrics] Cancelled fetch: Title/Artist/Album values are missing.")
            return
        }
        
        let cacheKey = "\(title)|\(artist)|\(album)".lowercased()
        
        // OPTIMIZATION: Prevent fetch thrashing (cancellation loop) if exact track request is already active
        if currentlyFetchingFingerprint == cacheKey {
            print("[MusicManager:Lyrics] Fetch for '\(title)' by '\(artist)' is already in progress. Ignoring redundant fetch.")
            return
        }
        
        print("[MusicManager:Lyrics] Requesting lyrics for track: '\(title)' by '\(artist)' [Album: '\(album)']")
        
        if let cachedLyrics = lyricsCacheQueue.sync(execute: { lyricsCache[cacheKey] }) {
            print("[MusicManager:Lyrics] Hit local memory cache! Loaded \(cachedLyrics.count) lines instantly.")
            self.lyrics = cachedLyrics
            self.retranslateLyricsIfNeeded()
            if self.needsLyricsUpdates {
                self.updateCurrentLyric(for: self.currentElapsedTime)
            }
            return
        }
        
        lyricsFetchTask?.cancel()
        lyricsTranslationTask?.cancel()
        currentlyFetchingFingerprint = cacheKey
        
        let fetchIdentity = lastTrackIdentity
        print("[MusicManager:Lyrics] Initiating network fetch from API...")
        lyricsFetchTask = Task {
            defer {
                Task { @MainActor in
                    if self.currentlyFetchingFingerprint == cacheKey {
                        self.currentlyFetchingFingerprint = nil
                    }
                }
            }
            guard let fL = await lyricsFetcher.fetchSyncedLyrics(for: title, artist: artist, album: album),
                  !fL.isEmpty, !Task.isCancelled else {
                print("[MusicManager:Lyrics] Synced lyrics API returned empty or call was cancelled.")
                return
            }
            
            await MainActor.run {
                guard self.lastTrackIdentity == fetchIdentity else {
                    print("[MusicManager:Lyrics] Network fetch completed, but active track already changed. Ignoring.")
                    return
                }
                print("[MusicManager:Lyrics] Synced lyrics loaded successfully! Count: \(fL.count) lines. Updating UI instantly.")
                self.lyrics = fL
                self.lyricsCacheQueue.async(flags: .barrier) {
                    self.lyricsCache[cacheKey] = fL
                }
                self.retranslateLyricsIfNeeded()
                if self.needsLyricsUpdates {
                    self.updateCurrentLyric(for: self.currentElapsedTime)
                }
            }
        }
    }

    private func retranslateLyricsIfNeeded() {
        lyricsTranslationTask?.cancel()
        let fetchIdentity = lastTrackIdentity
        
        lyricsTranslationTask = Task {
            guard !self.lyrics.isEmpty else { return }
            var lyricsToUpdate = self.lyrics
            
            // If translation is disabled, clear any translations and update immediately
            if !settingsModel.settings.enableLyricTranslation {
                print("[MusicManager:Lyrics] Translations disabled in user settings. Skipping.")
                for i in 0..<lyricsToUpdate.count { lyricsToUpdate[i].translatedText = nil }
                guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else { return }
                self.lyrics = lyricsToUpdate
                return
            }
            
            let sample = lyricsToUpdate.prefix(5).map { $0.text }.joined(separator: " ")
            guard !sample.isEmpty else { return }
            
            print("[MusicManager:Lyrics] Detecting language for lyrics sample...")
            guard let lang = await lyricsFetcher.detectLanguage(for: sample) else {
                print("[MusicManager:Lyrics] Language detection failed.")
                return
            }
            print("[MusicManager:Lyrics] Detected source language: '\(lang)'")
            
            let target = settingsModel.settings.lyricTranslationLanguage
            guard lang != target else {
                print("[MusicManager:Lyrics] Track language matches target language '\(target)'. Skipping translation.")
                return
            }
            
            if Task.isCancelled { return }
            print("[MusicManager:Lyrics] Translating lyrics from '\(lang)' to '\(target)'...")
            await lyricsFetcher.translate(lyrics: &lyricsToUpdate, from: lang, to: target)
            
            guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else {
                print("[MusicManager:Lyrics] Translation finished but active track already changed. Discarding output.")
                return
            }
            
            print("[MusicManager:Lyrics] Translation successfully completed. Updating UI.")
            self.lyrics = lyricsToUpdate
            self.updateCurrentLyric(for: self.currentElapsedTime)
        }
    }

    private func updateCurrentLyric(for elapsedTime: TimeInterval) {
        guard needsLyricsUpdates, !lyrics.isEmpty else { return }

        let second = Int(elapsedTime)
        if second == lastLyricLookupSecond, currentLyricIndex != nil { return }
        lastLyricLookupSecond = second

        let newIndex = binarySearchLyric(for: elapsedTime)
        guard newIndex != self.currentLyricIndex else { return }
        self.currentLyricIndex = newIndex
        let newLyric = newIndex.map { lyrics[$0] }
        if self.currentLyric?.id != newLyric?.id {
            self.currentLyric = newLyric
            self.currentLyricPublisher.send(newLyric)
            print("[MusicManager:Lyrics] Active lyric line updated to index \(newIndex ?? -1): '\(newLyric?.text ?? "")'")
        }
    }

    private func binarySearchLyric(for elapsedTime: TimeInterval) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        var low = 0, high = lyrics.count - 1, result: Int? = nil
        while low <= high {
            let mid = (low + high) / 2
            if lyrics[mid].timestamp <= elapsedTime {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    private func setupDerivedStatePublisher() {
        $title.map { $0 != nil && !$0!.isEmpty }.removeDuplicates().assign(to: \.shouldShowLiveActivity, on: self).store(in: &cancellables)
    }

    private func setupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppTermination(notification:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func handleAppTermination(notification: NSNotification) {
        guard let tApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let bID = tApp.bundleIdentifier else { return }
        Task { @MainActor in
            let keysToRemove = self.activeMediaSources.keys.filter { $0.hasPrefix(bID) }
            for key in keysToRemove { self.activeMediaSources.removeValue(forKey: key) }
            if let current = self.currentSourceKey, keysToRemove.contains(current) {
                if let first = self.activeMediaSources.keys.first { self.selectSource(key: first) }
                else { self.clearPlayerState() }
            }
        }
    }

    private func setupVolumeListener() {
        self.systemVolume = SystemControl.getVolume()
        guard let deviceID = getDefaultOutputDeviceID() else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        self.volumeListener = { _, _ in DispatchQueue.main.async { let nV = SystemControl.getVolume(); self.systemVolume = nV; self.volumePublisher.send(nV) } }
        AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, self.volumeListener!)
    }

    private func removeVolumeListener() {
        guard let deviceID = getDefaultOutputDeviceID(), let listener = self.volumeListener else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, listener)
    }

    private func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var dID: AudioDeviceID = kAudioObjectUnknown, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dID) == noErr ? dID : nil
    }

    private func fetchAppIcon(for bundleIdentifier: String?) {
        guard let bId = bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bId) else { self.appIcon = nil; return }
        self.appIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    // High-performance background-safe scaling via ImageIO
    nonisolated private static func downsampleImage(_ image: NSImage, maxDimension: CGFloat = 200) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiffData as CFData, nil) else {
            return image
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return image
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func resetColorsToDefault() {
        let def = Color(red: 0.53, green: 0.73, blue: 0.88)
        self.accentColor = def; self.leftGradientColor = def; self.rightGradientColor = def.opacity(0.7)
    }

    private func resetColorsToDefault_() {
        let def = Color(red: 0.53, green: 0.73, blue: 0.88)
        self.accentColor = def; self.leftGradientColor = def; self.rightGradientColor = def.opacity(0.7)
    }

    private func resetLyricsState() {
        lyricsFetchTask?.cancel()
        lyricsTranslationTask?.cancel()
        lyrics = []
        currentLyric = nil
        currentLyricIndex = nil
        lastLyricLookupSecond = -1
        currentLyricPublisher.send(nil)
    }

    private func setupSettingsObserver() {
        settingsModel.$settings
            .map { ($0.enableLyricTranslation, $0.lyricTranslationLanguage, $0.showLyricsInLiveActivity, $0.musicLiveActivityEnabled) }
            .removeDuplicates { $0 == $1 }
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.refreshLyricsLoadingState()
                if self.needsLyricsUpdates {
                    self.retranslateLyricsIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    func showTransientIcon(for icon: WaveformView.TransientIcon, duration: TimeInterval = 2.0) {
        transientIconTimer?.invalidate()
        transientIcon = icon
        transientIconTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in if self?.transientIcon == icon { self?.transientIcon = nil } }
    }

    private func triggerQuickPeek() {
        guard settingsModel.settings.showQuickPeekOnTrackChange else { return }
        quickPeekTimer?.invalidate(); self.showQuickPeek = true
        quickPeekTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in self?.showQuickPeek = false }
    }

    private func updateDevicePolling() {
        airplayDeviceUpdateTimer?.invalidate()
        if lastKnownBundleID == "com.apple.Music" {
            airplayDeviceUpdateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in Task { await self?.updateAirPlayDevices() } }
            airplayDeviceUpdateTimer?.fire()
        }
    }

    func updateAirPlayDevices() async { self.airplayDevices = await appleMusic.fetchAirPlayDevices() }
}
