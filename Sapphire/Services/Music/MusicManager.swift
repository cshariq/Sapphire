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

    @Published var title: String? { didSet { scheduleTrackIdentifierRefresh() } }
    @Published var artist: String? { didSet { scheduleTrackIdentifierRefresh() } }
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

    func setDetailPlayerOpen(_ isOpen: Bool) async {
        guard isDetailPlayerOpen != isOpen else { return }
        isDetailPlayerOpen = isOpen
        print("[MusicManager:Timing] Detail Player open state changed to: \(isOpen)")
        if isOpen {
            spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
        }
        refreshTimers()
        if isOpen {
            publishPlaybackTime(force: true, includeProgressUI: true)
            await ensureNextSongAvailableIfNeeded()
            await backfillSpotifyMetadataIfNeeded()
        }
        refreshLyricsLoadingState()
        refreshArtworkColorExtractionIfNeeded()
    }

    /// Re-sync Spotify extras / source tabs after navigating back from the Music Hub.
    func refreshPlayerUIAfterReturning() async {
        refreshSpotifyLiveSource()
        await ensureNextSongAvailableIfNeeded()
        publishPlaybackTime(force: true, includeProgressUI: true)
        if currentSourceKey == spotifyLiveSourceKey {
            applySpotifyLiveUIFromPlayerState(forceArtwork: false)
        }
        // Nudge SwiftUI in case nested private-API state changed while the player was off-screen.
        objectWillChange.send()
    }

    func setLyricsDetailOpen(_ isOpen: Bool) async {
        guard isLyricsDetailOpen != isOpen else { return }
        isLyricsDetailOpen = isOpen
        print("[MusicManager:Timing] Lyrics View open state changed to: \(isOpen)")
        refreshTimers()
        if isOpen {
            // Force an immediate precise calculation of the current elapsed time upon opening
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
        refreshLyricsLoadingState()
        if isOpen {
            await backfillSpotifyMetadataIfNeeded()
        }
    }

    func setDetachedLyricsOpen(_ isOpen: Bool) async {
        guard isDetachedLyricsOpen != isOpen else { return }
        isDetachedLyricsOpen = isOpen
        print("[MusicManager:Timing] Detached Lyrics Window state changed to: \(isOpen)")
        refreshTimers()
        if isOpen {
            // Force an immediate precise calculation of the current elapsed time upon opening
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
        refreshLyricsLoadingState()
        if isOpen {
            await backfillSpotifyMetadataIfNeeded()
        }
    }

    func setMusicLiveActivityActive(_ isActive: Bool) async {
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
    @Published private(set) var playCountValue: Int?
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
    /// When true, don't auto-jump to whichever source starts playing — honor the user's switcher choice.
    private var sourcePinnedByUser = false
    private let spotifyLiveSourceKey = "com.spotify.client:spotify-live"

    // Spotify Specific State (Queues)
    @Published var nativeQueue: [PlayerState.Track] = []
    @Published var nowPlayingTrack: PlayerState.Track?

    // Apple Music next-track (for the mini player pill)
    @Published private(set) var appleMusicNextTrack: AppleMusicManager.QueueTrack?

    @Published private(set) var currentLyric: LyricLine?
    @Published private(set) var isDetailPlayerOpen: Bool = false
    @Published private(set) var isLyricsDetailOpen: Bool = false
    @Published private(set) var isDetachedLyricsOpen: Bool = false
    @Published private(set) var isMusicLiveActivityActive: Bool = false
    private(set) var systemVolume: Float = 0.0

    // Published so SwiftUI progress/time labels refresh even if a Combine subscriber misses ticks.
    @Published private(set) var currentElapsedTime: TimeInterval = 0
    @Published private(set) var playbackProgress: Double = 0.0

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
    private var trackIdentifierRefreshTask: Task<Void, Never>?
    private var lastHandledTrackKey: String?
    private var lastNextSongFetchAttempt: Date = .distantPast
    /// Ignore brief "paused" frames from Connect/MediaRemote right after skip / track change.
    private var playStateHoldUntil: Date = .distantPast
    private var playStateHoldPreferPlaying = true
    /// While reconciling Connect vs MediaRemote, ignore stale Connect play flags.
    private var spotifyPlayStateReconcileUntil: Date = .distantPast
    private var spotifyPlayStateReconcileTarget: Bool?
    /// Bumped on every track advance so in-flight popularity/lyrics fetches can't overwrite the new song.
    private var trackMetadataGeneration: UInt64 = 0
    private var lastConnectTrackURI: String?
    private var spotifyConnectSyncTask: Task<Void, Never>?
    private var lastSpotifyConnectSyncAt: Date = .distantPast
    private var spotifyHydrationTask: Task<Void, Never>?
    private var spotifyHydrationInFlightURI: String?

    private var lyricsCache: [String: [LyricLine]] = [:]
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

    /// Pathfinder / stats.fm / lyrics — defer until the player actually needs them.
    private var needsSpotifyHeavyMetadata: Bool {
        isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen ||
        settingsModel.settings.showPopularityInMusicPlayer || needsLyricsUpdates
    }

    private init() {
        spotifyOfficialAPI.$hasApiKeys.assign(to: &$officialAPIHasKeys)
        spotifyOfficialAPI.$isAuthenticated.assign(to: &$isOfficialAPIAuthenticated)
        spotifyPrivateAPI.$isLoggedIn.assign(to: &$isPrivateAPIAuthenticated)
        spotifyOfficialAPI.$isPremiumUser.assign(to: &$isPremiumUser)

        spotifyPrivateAPI.$nativeQueue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                guard let self else { return }
                guard self.isSpotifySourceActive else {
                    if self.lastKnownBundleID == "com.apple.Music" {
                        self.nativeQueue = []
                    }
                    return
                }
                self.nativeQueue = queue
            }
            .store(in: &cancellables)

        spotifyPrivateAPI.$playerState
            .map { $0?.track }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self else { return }
                if self.isSpotifySourceActive {
                    self.nowPlayingTrack = track
                } else if self.lastKnownBundleID == "com.apple.Music" {
                    self.nowPlayingTrack = nil
                }
            }
            .store(in: &cancellables)

        spotifyPrivateAPI.$playerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self, let state = state else { return }

                let incomingURI = state.track?.uri
                let trackChanged = incomingURI != nil && incomingURI != self.lastConnectTrackURI
                let playChanged = state.isActivelyPlaying != self.isPlaying

                // Refresh Live tab only when identity/play state changes — not every position tick.
                if trackChanged || playChanged || self.activeMediaSources[self.spotifyLiveSourceKey] == nil {
                    self.refreshSpotifyLiveSource()
                }

                if self.isSpotifyDisplayedInUI,
                   self.spotifyPrivateAPI.isLoggedIn,
                   !self.prefersNativeSpotifyMediaRemote {
                    self.applyPlayingState(state.isActivelyPlaying, fromConnect: true)
                    self.applySpotifyPlayerTiming(state)
                }

                guard self.shouldSurfaceSpotifyConnectPlayback else { return }

                // Fast path: same track — only refresh wall-clock timing / play state.
                if !trackChanged {
                    if playChanged {
                        self.shuffleState = state.options?.shufflingContext ?? false
                        let rC = state.options?.repeatingContext ?? false
                        let rT = state.options?.repeatingTrack ?? false
                        if rT { self.repeatState = .track }
                        else if rC { self.repeatState = .context }
                        else { self.repeatState = .off }
                        if !(state.options?.shufflingContext ?? false) {
                            self.spotifyPrivateAPI.isSmartShuffleActive = false
                        }
                    }
                    self.applyPlayingState(state.isActivelyPlaying, fromConnect: true)
                    self.applySpotifyPlayerTiming(state)
                    if self.isDetailPlayerOpen {
                        Task { await self.ensureNextSongAvailableIfNeeded() }
                    }
                    return
                }

                self.shuffleState = state.options?.shufflingContext ?? false
                let rC = state.options?.repeatingContext ?? false
                let rT = state.options?.repeatingTrack ?? false
                if rT { self.repeatState = .track }
                else if rC { self.repeatState = .context }
                else { self.repeatState = .off }

                // Hold play glyph through skip transitions (Connect often blips paused).
                self.beginPlayStateHold(preferPlaying: state.isActivelyPlaying, duration: 0.55)
                self.applyPlayingState(state.isActivelyPlaying, fromConnect: true)

                if let incomingURI {
                    self.lastConnectTrackURI = incomingURI
                }

                if self.currentSourceKey == self.spotifyLiveSourceKey {
                    // Live tab owns the whole UI — force art reload on track changes.
                    self.applySpotifyLiveUIFromPlayerState(forceArtwork: true)
                } else if let track = state.track {
                    // Native Spotify selected — mirror Connect metadata + wall-clock timing
                    // (MediaRemote position updates are often frozen for Spotify).
                    self.syncConnectNowPlayingMetadata(from: track)
                    self.applyPlayingState(state.isActivelyPlaying, fromConnect: true)
                    self.applySpotifyPlayerTiming(state)
                    self.lockConnectMediaIdentity(from: track)
                    self.applyConnectArtworkIfNeeded(from: track, force: true)
                }
                if !(state.options?.shufflingContext ?? false) {
                    self.spotifyPrivateAPI.isSmartShuffleActive = false
                }

                self.lastNextSongFetchAttempt = .distantPast
                self.handleSpotifyTrackAdvanced(to: state.track)
                // Force scrubber / Now pane to re-bind immediately after skip.
                self.objectWillChange.send()

                // If the detail player is open and up-next vanished, refetch.
                if self.isDetailPlayerOpen {
                    Task { await self.ensureNextSongAvailableIfNeeded() }
                }
            }
            .store(in: &cancellables)

        setupHandlers()
        setupNotificationObservers()
        setupVolumeListener()
        setupDerivedStatePublisher()
        setupSettingsObserver()
        setupPrivateAPIUIForwarding()
        setupSpotifyBootstrapObserver()
        scheduleDeferredSpotifyBootstrap()
        mediaController.startListening()
    }

    private func scheduleDeferredSpotifyBootstrap() {
        spotifyPrivateAPI.bootstrapIfNeeded(policy: .automatic, delay: 3.0)
    }

    private func setupSpotifyBootstrapObserver() {
        // Bootstrap when the user switches default player to Spotify in settings
        settingsModel.$settings
            .map(\.defaultMusicPlayer)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] player in
                guard player == .spotify else { return }
                self?.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            }
            .store(in: &cancellables)

        // Bootstrap as soon as MediaRemote detects Spotify is playing —
        // this catches the case where Spotify is the active player but the
        // detail player hasn't been opened yet (so the onDemand trigger in
        // setDetailPlayerOpen never fires).
        $lastKnownBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                guard let self, bundleID == "com.spotify.client" else { return }
                self.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            }
            .store(in: &cancellables)
    }

    /// Forward only music-player-relevant Private API fields. Blanket `objectWillChange`
    /// forwarding made volume-key device refreshes remount the whole player.
    private func setupPrivateAPIUIForwarding() {
        let artist = spotifyPrivateAPI.$nowPlayingArtist.map { _ in () }.eraseToAnyPublisher()
        let related = spotifyPrivateAPI.$relatedTracks.map { _ in () }.eraseToAnyPublisher()
        let similar = spotifyPrivateAPI.$similarAlbums.map { _ in () }.eraseToAnyPublisher()
        let concerts = spotifyPrivateAPI.$artistConcerts.map { _ in () }.eraseToAnyPublisher()
        let canvas = spotifyPrivateAPI.$currentCanvas.map { _ in () }.eraseToAnyPublisher()
        let account = spotifyPrivateAPI.$accountInfo.map { _ in () }.eraseToAnyPublisher()
        let activeDevice = spotifyPrivateAPI.$activePlayerDeviceID.map { _ in () }.eraseToAnyPublisher()
        // Device *identity* only — ignore volume/capability churn from HUD volume keys.
        let deviceIDs = spotifyPrivateAPI.$devices
            .map { $0.map(\.deviceId) }
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()

        Publishers.MergeMany([artist, related, similar, concerts, canvas, account, activeDevice, deviceIDs])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func syncConnectNowPlayingMetadata(from track: PlayerState.Track) {
        if lastKnownBundleID != "com.spotify.client" {
            lastKnownBundleID = "com.spotify.client"
            fetchAppIcon(for: "com.spotify.client")
        }
        if let title = track.metadata?.title, !title.isEmpty, title != self.title { self.title = title }
        if let artist = track.metadata?.artistName, !artist.isEmpty, artist != self.artist { self.artist = artist }
        if let album = track.metadata?.albumTitle, album != self.album { self.album = album }
        if let imageURL = track.metadata?.imageURL, imageURL != self.artworkURL { self.artworkURL = imageURL }
        if track.uri != self.uri { self.uri = track.uri }
    }

    /// Align MediaRemote fingerprints with Connect so a lagging system update can't rewind UI.
    private func lockConnectMediaIdentity(from track: PlayerState.Track) {
        let fingerprint = [
            track.metadata?.title,
            track.metadata?.artistName,
            track.metadata?.albumTitle
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
            .lowercased()
        if !fingerprint.isEmpty {
            lastMediaFingerprint = fingerprint
        }
        lastTrackIdentity = track.uri
    }

    /// True when MediaRemote Spotify metadata disagrees with the authoritative Connect track.
    private func isStaleSpotifyMediaRemote(_ payload: TrackInfo.Payload) -> Bool {
        guard !prefersNativeSpotifyMediaRemote,
              spotifyPrivateAPI.isLoggedIn,
              shouldSurfaceSpotifyConnectPlayback,
              let connect = spotifyPrivateAPI.playerState?.track else { return false }
        let bundle = normalizeBundleID(payload.bundleIdentifier)
        guard bundle == "com.spotify.client" else { return false }

        let connectFP = [
            connect.metadata?.title,
            connect.metadata?.artistName,
            connect.metadata?.albumTitle
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
            .lowercased()
        let remoteFP = mediaFingerprint(for: payload)
        guard !connectFP.isEmpty, !remoteFP.isEmpty else { return false }
        return connectFP != remoteFP
    }

    /// Loads Connect cover art into `artwork` when the URL changes (metadata alone isn't enough for the player UI).
    private func applyConnectArtworkIfNeeded(from track: PlayerState.Track, force: Bool) {
        guard let imageURL = track.metadata?.imageURL else {
            // No art for this track — drop bitmap so the UI falls back to the app icon.
            if force {
                artwork = nil
                artworkURL = nil
                currentTrackArtworkToken = "missing-\(track.uri)"
            }
            return
        }
        let urlChanged = artworkURL != imageURL
        artworkURL = imageURL
        let needsLoad = force || urlChanged || artwork == nil || currentTrackArtworkToken.isEmpty
        guard needsLoad else { return }
        // Keep previous song art visible while the new image loads.
        let token = "connect-\(imageURL.absoluteString.hashValue)-\(UUID().uuidString.prefix(6))"
        currentTrackArtworkToken = token
        Task {
            await loadRemoteArtwork(from: imageURL, expectedToken: token)
        }
    }

    /// Apply play/pause while suppressing skip-transition flicker.
    private func applyPlayingState(_ playing: Bool, fromConnect: Bool = false) {
        if fromConnect,
           Date() < spotifyPlayStateReconcileUntil,
           let target = spotifyPlayStateReconcileTarget,
           playing != target {
            return
        }

        let holding = Date() < playStateHoldUntil
        if holding {
            if playing == playStateHoldPreferPlaying {
                // Authoritative match — drop the hold so real pauses/resumes apply immediately after.
                playStateHoldUntil = .distantPast
            } else {
                return
            }
        }
        if isPlaying != playing {
            isPlaying = playing
        }

        if fromConnect, playing == spotifyPlayStateReconcileTarget {
            spotifyPlayStateReconcileUntil = .distantPast
            spotifyPlayStateReconcileTarget = nil
        }
    }

    private func beginPlayStateHold(preferPlaying: Bool, duration: TimeInterval = 1.0) {
        playStateHoldPreferPlaying = preferPlaying
        playStateHoldUntil = Date().addingTimeInterval(duration)
    }

    private func heldOrReportedPlaying(_ reported: Bool) -> Bool {
        if Date() < playStateHoldUntil {
            return playStateHoldPreferPlaying
        }
        if Date() < spotifyPlayStateReconcileUntil, let target = spotifyPlayStateReconcileTarget {
            return target
        }
        return reported
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

    func play() async {
        beginPlayStateHold(preferPlaying: true, duration: 0.8)
        if shouldUseSpotifyPrivateControls() {
            applyPlayingState(true)
            await spotifyPrivateAPI.sendConnectCommand(endpoint: "resume")
            return
        }
        applyPlayingState(true)
        defaultControls.play()
    }

    func pause() async {
        beginPlayStateHold(preferPlaying: false, duration: 0.8)
        if shouldUseSpotifyPrivateControls() {
            applyPlayingState(false)
            await spotifyPrivateAPI.sendConnectCommand(endpoint: "pause")
            return
        }
        applyPlayingState(false)
        defaultControls.pause()
    }

    func nextTrack() async {
        beginPlayStateHold(preferPlaying: true, duration: 1.2)
        if shouldUseSpotifyPrivateControls() {
            await spotifyPrivateAPI.connectSkipNext()
            return
        }
        defaultControls.nextTrack()
    }

    func previousTrack() async {
        beginPlayStateHold(preferPlaying: true, duration: 1.2)
        if shouldUseSpotifyPrivateControls() {
            await spotifyPrivateAPI.connectSkipPrevious()
            return
        }
        defaultControls.previousTrack()
    }
    
    func seek(to seconds: Double) async {
        if shouldUseSpotifyPrivateControls() {
            await spotifyPrivateAPI.connectSeek(to: seconds)
            // Only mirror MediaRemote seeks when native Spotify (not the Live tab) owns the session.
            if !isSpotifyLiveSourceSelected, hasNativeSpotifyMediaSource() {
                defaultControls.seek(to: seconds)
            }
            applyOptimisticSeek(to: seconds)
            return
        }
        defaultControls.seek(to: seconds)
        applyOptimisticSeek(to: seconds)
    }

    func seek(by seconds: TimeInterval) async {
        let newTime = max(0.0, min(currentElapsedTime + seconds, max(totalDuration, currentElapsedTime + seconds)))
        await seek(to: newTime)
    }

    /// True when the injected Spotify Live source tab is selected (secondary audio).
    var isSpotifyLiveSourceSelected: Bool {
        currentSourceKey == spotifyLiveSourceKey
    }

    /// True when the UI is showing Spotify playback (mini widget, expanded player, or Live tab).
    private var isSpotifyDisplayedInUI: Bool {
        if lastKnownBundleID == "com.spotify.client" { return true }
        if currentSourceKey == spotifyLiveSourceKey { return true }
        if currentSourceKey?.hasPrefix("com.spotify.client") == true { return true }
        return false
    }

    /// True when Spotify (not Apple Music) owns the active player UI and queue.
    var isSpotifySourceActive: Bool {
        isSpotifyDisplayedInUI && lastKnownBundleID != "com.apple.Music"
    }

    private func clearSpotifyTransientUIState() {
        nativeQueue = []
        nowPlayingTrack = nil
        appleMusicNextTrack = nil
    }

    /// True when Connect (not native MediaRemote) should drive playback UI/state.
    private var shouldSurfaceSpotifyConnectPlayback: Bool {
        if isSpotifyLiveSourceSelected { return true }
        if spotifyPrivateAPI.isControllingConnectPlayback { return true }
        return false
    }

    /// Native Spotify desktop app is the active source — MediaRemote owns transport + now playing.
    private var prefersNativeSpotifyMediaRemote: Bool {
        if isSpotifyLiveSourceSelected { return false }
        if spotifyPrivateAPI.isControllingConnectPlayback { return false }
        if lastKnownBundleID == "com.spotify.client" { return true }
        if currentSourceKey?.hasPrefix("com.spotify.client") == true { return true }
        return false
    }

    /// MediaRemote often omits Spotify play/pause; pull Connect state when UI or transport disagrees.
    private func scheduleSpotifyConnectPlaybackSync(force: Bool = false, playStateOnly: Bool = false) {
        guard spotifyPrivateAPI.isLoggedIn,
              isSpotifyDisplayedInUI,
              !prefersNativeSpotifyMediaRemote else { return }
        if playStateOnly, spotifyPrivateAPI.webSocketManager?.hasActiveConnection == true { return }
        let minInterval: TimeInterval = playStateOnly ? 1.2 : 8.0
        if !force, Date().timeIntervalSince(lastSpotifyConnectSyncAt) < minInterval { return }

        spotifyConnectSyncTask?.cancel()
        spotifyConnectSyncTask = Task { @MainActor in
            let delayNs: UInt64 = playStateOnly ? 120_000_000 : 350_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            self.lastSpotifyConnectSyncAt = Date()
            do {
                try await self.spotifyPrivateAPI.refreshPlayerAndDeviceState()
            } catch {
                return
            }
            guard let state = self.spotifyPrivateAPI.playerState else { return }
            self.applyPlayingState(state.isActivelyPlaying, fromConnect: true)
            self.applySpotifyPlayerTiming(state)
        }
    }

    /// Reconcile Connect vs MediaRemote play state — never let stale Connect overwrite a fresh transport update.
    private func syncSpotifyPlayState(mediaRemoteHint: Bool? = nil, forceConnectRefresh: Bool = false) {
        if prefersNativeSpotifyMediaRemote {
            if let mediaRemoteHint { applyPlayingState(mediaRemoteHint) }
            return
        }

        guard spotifyPrivateAPI.isLoggedIn, isSpotifyDisplayedInUI else {
            if let mediaRemoteHint { applyPlayingState(mediaRemoteHint) }
            return
        }

        let connectPlaying = spotifyPrivateAPI.playerState?.isActivelyPlaying
        let mismatch = mediaRemoteHint != nil
            && connectPlaying != nil
            && mediaRemoteHint != connectPlaying

        if forceConnectRefresh || mismatch {
            if let mediaRemoteHint {
                spotifyPlayStateReconcileTarget = mediaRemoteHint
                spotifyPlayStateReconcileUntil = Date().addingTimeInterval(2.5)
                applyPlayingState(mediaRemoteHint)
            }
            scheduleSpotifyConnectPlaybackSync(force: true, playStateOnly: true)
            return
        }

        if let state = spotifyPrivateAPI.playerState {
            applyPlayingState(state.isActivelyPlaying, fromConnect: true)
            applySpotifyPlayerTiming(state)
        } else if let mediaRemoteHint {
            applyPlayingState(mediaRemoteHint)
            scheduleSpotifyConnectPlaybackSync(force: true, playStateOnly: true)
        } else {
            scheduleSpotifyConnectPlaybackSync(force: true, playStateOnly: true)
        }
    }

    private func applySpotifyConnectPlaybackIfAvailable() {
        syncSpotifyPlayState()
    }

    private func backfillSpotifyMetadataIfNeeded() async {
        guard spotifyPrivateAPI.isLoggedIn, needsSpotifyHeavyMetadata else { return }
        guard let uri = uri ?? spotifyPrivateAPI.playerState?.track?.uri,
              uri.contains("spotify:track:") else { return }
        await scheduleSpotifyAccessoryHydration(uri: uri, generation: trackMetadataGeneration)
    }

    private func scheduleSpotifyAccessoryHydration(uri: String, trackId: String? = nil, generation: UInt64) async {
        guard spotifyPrivateAPI.isLoggedIn else { return }
        if spotifyHydrationInFlightURI == uri {
            await spotifyHydrationTask?.value
            return
        }

        spotifyHydrationTask?.cancel()
        spotifyHydrationInFlightURI = uri
        spotifyHydrationTask = Task { @MainActor in
            defer {
                if self.spotifyHydrationInFlightURI == uri {
                    self.spotifyHydrationInFlightURI = nil
                }
            }
            await self.hydrateSpotifyTrackAccessories(uri: uri, trackId: trackId, generation: generation)
        }
        await spotifyHydrationTask?.value
    }

    /// Apply Connect track identity, artwork, and stats when the URI advances or metadata is missing.
    private func processConnectTrackUpdate(from state: PlayerState, forceArtwork: Bool) {
        guard let track = state.track, track.uri.contains("spotify:track:") else { return }

        let connectURI = track.uri
        let trackChanged = connectURI != lastConnectTrackURI

        if trackChanged {
            lastConnectTrackURI = connectURI
            syncConnectNowPlayingMetadata(from: track)
            applyConnectArtworkIfNeeded(from: track, force: true)

            if shouldSurfaceSpotifyConnectPlayback {
                lockConnectMediaIdentity(from: track)
                handleSpotifyTrackAdvanced(to: track)
            } else if prefersNativeSpotifyMediaRemote {
                Task { await scheduleSpotifyAccessoryHydration(uri: connectURI, generation: trackMetadataGeneration) }
            } else {
                Task { await scheduleSpotifyAccessoryHydration(uri: connectURI, generation: trackMetadataGeneration) }
            }
            return
        }

        if forceArtwork || artwork == nil {
            applyConnectArtworkIfNeeded(from: track, force: forceArtwork)
        }
    }

    /// Connect session Sapphire started on an external speaker, or the secondary Spotify Live tab.
    private func shouldUseSpotifyPrivateControls() -> Bool {
        guard spotifyPrivateAPI.isLoggedIn else { return false }
        if isSpotifyLiveSourceSelected { return true }
        return spotifyPrivateAPI.isControllingConnectPlayback
    }

    private func hasNativeSpotifyMediaSource(in clients: [String: TrackInfo] = [:]) -> Bool {
        let source = clients.isEmpty ? activeMediaSources : clients
        return source.keys.contains { key in
            !key.contains("spotify-live") && key.hasPrefix("com.spotify.client")
        }
    }

    private func shouldInjectSpotifySourceTab(into clients: [String: TrackInfo]) -> Bool {
        guard settingsModel.settings.showSpotifySourceTab else { return false }
        guard spotifyPrivateAPI.isLoggedIn else { return false }
        // Only show the extra Spotify tab when the main media source isn't already Spotify.
        guard !hasNativeSpotifyMediaSource(in: clients) else { return false }
        // Need at least one other media source so the tab is useful for switching.
        return !clients.isEmpty
    }

    private func mergedSourcesWithSpotifyLive(_ clients: [String: TrackInfo]) -> [String: TrackInfo] {
        var merged = clients
        if shouldInjectSpotifySourceTab(into: clients),
           let spotifyLive = buildSpotifyLiveTrackInfo() {
            merged[spotifyLiveSourceKey] = spotifyLive
        } else {
            merged.removeValue(forKey: spotifyLiveSourceKey)
        }
        return merged
    }

    func play(trackUri: String, contextUri: String?, trackUid: String? = nil, trackIndex: Int? = nil) async -> PlaybackResult {
        if spotifyPrivateAPI.isLoggedIn {
            let connectResult = await spotifyPrivateAPI.connectPlay(
                trackUri: trackUri,
                contextUri: contextUri,
                trackUid: trackUid,
                trackIndex: trackIndex
            )
            if case .success = connectResult {
                lastKnownBundleID = "com.spotify.client"
                return connectResult
            }
            print("[MusicManager] Connect play failed. Falling back to Spotify app.")
        }

        if spotifyOfficialAPI.isPremiumUser, !trackUri.isEmpty {
            let official = await spotifyOfficialAPI.playTrack(uri: trackUri)
            if case .success = official { return official }
        }

        // Last resort: drive the local Spotify desktop app via AppleScript.
        let uriForScript = trackUri.isEmpty ? (contextUri ?? "") : trackUri
        guard !uriForScript.isEmpty else {
            return .failure(reason: "Nothing to play.")
        }
        if !spotifyAppleScript.isAppRunning() {
            await spotifyAppleScript.launchAndPlay()
            // Give the app a moment to register as a Connect device, then retry Connect once.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if spotifyPrivateAPI.isLoggedIn {
                let retry = await playWithPrivateAPI(
                    trackUri: trackUri,
                    contextUri: contextUri,
                    trackUid: trackUid,
                    trackIndex: trackIndex
                )
                if case .success = retry {
                    lastKnownBundleID = "com.spotify.client"
                    return retry
                }
            }
        }
        let scriptResult = await spotifyAppleScript.play(uri: uriForScript)
        if case .success = scriptResult {
            lastKnownBundleID = "com.spotify.client"
        }
        return scriptResult
    }

    func play(contextUri: String) async -> PlaybackResult {
        return await play(trackUri: "", contextUri: contextUri, trackUid: nil, trackIndex: 0)
    }

    private func playWithPrivateAPI(trackUri: String, contextUri: String?, trackUid: String?, trackIndex: Int?) async -> PlaybackResult {
        await spotifyPrivateAPI.connectPlay(
            trackUri: trackUri,
            contextUri: contextUri,
            trackUid: trackUid,
            trackIndex: trackIndex
        )
    }

    private func findTargetDeviceID() async -> String? {
        try? await spotifyPrivateAPI.refreshPlayerAndDeviceState()
        guard let controller = spotifyPrivateAPI.controllerDeviceID else {
            return spotifyPrivateAPI.preferredExternalPlaybackDeviceID(excluding: "")
        }
        return spotifyPrivateAPI.preferredExternalPlaybackDeviceID(excluding: controller)
    }

    // MARK: - Rating & Mode Actions

    func toggleLike() async {
        let newLikedState = !self.isLiked
        self.isLiked = newLikedState
        var success = false
        if self.lastKnownBundleID == "com.apple.Music" {
            appleMusic.setLiked(isLiked: newLikedState)
            success = true
        } else if let trackId = self.trackID {
            if spotifyPrivateAPI.isLoggedIn {
                success = newLikedState
                    ? await spotifyPrivateAPI.likeTrack(trackURI: "spotify:track:\(trackId)")
                    : await spotifyPrivateAPI.unlikeTrack(trackURI: "spotify:track:\(trackId)")
            } else if spotifyOfficialAPI.isAuthenticated {
                success = newLikedState
                    ? await spotifyOfficialAPI.likeTrack(id: trackId)
                    : await spotifyOfficialAPI.unlikeTrack(id: trackId)
            }
        }
        if !success { self.isLiked = !newLikedState }
    }

    func toggleShuffle() async {
        // Rotation: Off → Shuffle → Smart Shuffle (when available) → Off
        await cycleShuffleMode()
    }

    private func cycleShuffleMode() async {
        let onPlaylistContext: Bool = {
            guard lastKnownBundleID == "com.spotify.client",
                  spotifyPrivateAPI.isLoggedIn,
                  let contextURI = spotifyPrivateAPI.currentContextURI else { return false }
            return contextURI.contains(":playlist:")
        }()

        if spotifyPrivateAPI.isSmartShuffleActive {
            // Smart → Off
            await MainActor.run {
                self.shuffleState = false
                self.spotifyPrivateAPI.isSmartShuffleActive = false
            }
            await applyPlainShuffle(enabled: false)
            return
        }

        if shuffleState {
            // Shuffle → Smart (if eligible) else Off
            if onPlaylistContext,
               let contextURI = spotifyPrivateAPI.currentContextURI {
                let available = await spotifyPrivateAPI.checkSmartShuffleAvailable(uri: contextURI)
                if available {
                    let result = await spotifyPrivateAPI.playSmartShuffle(playlistURI: contextURI)
                    await MainActor.run {
                        if case .success = result {
                            self.shuffleState = true
                            self.spotifyPrivateAPI.isSmartShuffleActive = true
                        } else {
                            // Couldn't enter smart — fall through to Off
                            self.shuffleState = false
                            self.spotifyPrivateAPI.isSmartShuffleActive = false
                        }
                    }
                    if case .success = result { return }
                    await applyPlainShuffle(enabled: false)
                    return
                }
            }
            await MainActor.run {
                self.shuffleState = false
                self.spotifyPrivateAPI.isSmartShuffleActive = false
            }
            await applyPlainShuffle(enabled: false)
            return
        }

        // Off → Shuffle
        await MainActor.run {
            self.shuffleState = true
            self.spotifyPrivateAPI.isSmartShuffleActive = false
        }
        await applyPlainShuffle(enabled: true)
    }

    private func applyPlainShuffle(enabled: Bool) async {
        if self.lastKnownBundleID == "com.apple.Music" {
            appleMusic.setShuffle(enabled: enabled)
        } else if spotifyPrivateAPI.isLoggedIn {
            _ = await spotifyPrivateAPI.setShuffle(state: enabled)
        } else if spotifyOfficialAPI.isAuthenticated && isPremiumUser {
            _ = await spotifyOfficialAPI.setShuffle(state: enabled)
        }
    }

    func cycleRepeatMode() async {
        let newRepeatState = self.repeatState.next()
        self.repeatState = newRepeatState
        if self.lastKnownBundleID == "com.apple.Music" {
            appleMusic.setRepeat(mode: newRepeatState)
        } else if spotifyPrivateAPI.isLoggedIn {
            _ = await spotifyPrivateAPI.setRepeatMode(mode: newRepeatState)
        } else if spotifyOfficialAPI.isAuthenticated && isPremiumUser {
            let modeString: String
            switch newRepeatState {
            case .off: modeString = "off"
            case .context: modeString = "context"
            case .track: modeString = "track"
            }
            _ = await spotifyOfficialAPI.setRepeatMode(mode: modeString)
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

    func selectSource(key: String, userInitiated: Bool = false) {
        if userInitiated {
            sourcePinnedByUser = true
        }
        let switching = key != currentSourceKey
        currentSourceKey = key

        if switching {
            // Force artwork/metadata refresh when switching medias — titles can match across apps.
            artwork = nil
            artworkURL = nil
            lastTrackIdentity = nil
            lastMediaFingerprint = nil
            lastHandledTrackKey = nil
            currentTrackArtworkToken = "source-switch-\(key)-\(UUID().uuidString)"
            if !key.hasPrefix("com.spotify.client"), key != spotifyLiveSourceKey {
                clearSpotifyTransientUIState()
            }
        }

        if key == spotifyLiveSourceKey || key.contains("spotify-live") {
            applySpotifyLiveUIFromPlayerState(forceArtwork: true)
            return
        }

        if key.hasPrefix("com.spotify.client"), spotifyPrivateAPI.isLoggedIn, !prefersNativeSpotifyMediaRemote {
            scheduleSpotifyConnectPlaybackSync(force: true)
        }

        if let track = activeMediaSources[key] {
            // Always re-apply selected source so play/pause, elapsed time, and art stay in sync.
            lastTrackIdentity = nil
            lastMediaFingerprint = nil
            applyTrackPayload(track.payload, sourceKey: key)
            if artwork == nil {
                let identity = trackIdentity(for: track.payload)
                if let embedded = track.payload.artwork {
                    applyArtwork(embedded, trackIdentity: identity)
                } else {
                    requestArtworkForTrack(payload: track.payload, trackIdentity: identity)
                }
            }
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
    }

    /// Push Connect / Live player state into the UI when the Spotify Live tab is selected.
    private func applySpotifyLiveUIFromPlayerState(forceArtwork: Bool) {
        if lastKnownBundleID != "com.spotify.client" {
            lastKnownBundleID = "com.spotify.client"
            fetchAppIcon(for: "com.spotify.client")
        } else {
            lastKnownBundleID = "com.spotify.client"
        }
        guard let state = spotifyPrivateAPI.playerState else {
            refreshSpotifyLiveSource()
            return
        }

        applyPlayingState(state.isActivelyPlaying, fromConnect: true)
        if let track = state.track {
            syncConnectNowPlayingMetadata(from: track)
            if let imageURL = track.metadata?.imageURL {
                let urlChanged = artworkURL != imageURL
                artworkURL = imageURL
                let needsLoad = forceArtwork || urlChanged || artwork == nil
                if needsLoad {
                    // Keep previous song art visible while the new image loads.
                    let token = "live-\(imageURL.absoluteString.hashValue)-\(UUID().uuidString.prefix(6))"
                    currentTrackArtworkToken = token
                    Task {
                        await loadRemoteArtwork(from: imageURL, expectedToken: token)
                    }
                } else {
                    refreshArtworkColorExtractionIfNeeded()
                }
            } else if forceArtwork {
                // No art for this track — fall back to app icon in the UI.
                artwork = nil
                artworkURL = nil
                currentTrackArtworkToken = "live-missing-\(track.uri)"
            }
        }
        applySpotifyPlayerTiming(state)
        refreshSpotifyLiveSource()
        publishPlaybackTime(force: true, includeProgressUI: true)
    }

    /// When the music player is open and up-next is missing/stale, re-fetch Connect queue.
    private func ensureNextSongAvailableIfNeeded(force: Bool = false) async {
        // Apple Music: fetch Up Next and expose the first track for the mini player pill
        if lastKnownBundleID == "com.apple.Music" {
            guard settingsModel.settings.spotifyShowNextSong else { return }
            if force || appleMusicNextTrack == nil {
                let queue = await appleMusic.fetchUpNextTracks()
                appleMusicNextTrack = queue.first
            }
            return
        }

        guard settingsModel.settings.spotifyShowNextSong else { return }
        guard spotifyPrivateAPI.isLoggedIn else { return }
        let isSpotifyContext = isSpotifyLiveSourceSelected
            || (lastKnownBundleID == "com.spotify.client")
            || (currentSourceKey?.hasPrefix("com.spotify.client") == true)
        guard isSpotifyContext else { return }

        let connectNextUIDs = spotifyPrivateAPI.playerState?.nextTracks?
            .filter { !($0.uri.contains("spotify:delimiter") || ($0.metadata?.hidden == "true")) }
            .map(\.uid) ?? []
        let localNextUIDs = nativeQueue.map(\.uid)

        let needsFetch: Bool = {
            if force {
                if !connectNextUIDs.isEmpty,
                   localNextUIDs == connectNextUIDs,
                   let next = nativeQueue.first,
                   !(next.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    return false
                }
                return true
            }
            guard let next = nativeQueue.first else { return true }
            let title = next.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty { return true }
            // Local queue drifted from Connect nextTracks — refresh so the pill catches up.
            if !connectNextUIDs.isEmpty, localNextUIDs != connectNextUIDs { return true }
            return false
        }()
        guard needsFetch else { return }
        // Avoid hammering Connect while the queue stays empty (unless forced after a skip).
        if !force {
            guard Date().timeIntervalSince(lastNextSongFetchAttempt) > 8 else { return }
        } else {
            guard Date().timeIntervalSince(lastNextSongFetchAttempt) > 1.2 else { return }
        }
        lastNextSongFetchAttempt = Date()
        await spotifyPrivateAPI.refreshQueueForUI()
    }

    private func loadRemoteArtwork(from url: URL, expectedToken: String) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                await MainActor.run {
                    guard self.currentTrackArtworkToken == expectedToken || self.artworkURL == url else { return }
                    self.artwork = image
                    self.currentTrackArtworkToken = "remote-\(url.absoluteString.hashValue)"
                    self.refreshArtworkColorExtractionIfNeeded()
                }
            }
        } catch {
            print("[MusicManager] Failed to load Spotify Live artwork: \(error.localizedDescription)")
        }
    }

    private func setupHandlers() {
        mediaController.onActiveClientsChanged = { [weak self] clients in
            Task { @MainActor in
                guard let self = self else { return }
                let mergedClients = self.mergedSourcesWithSpotifyLive(clients)
                self.activeMediaSources = mergedClients

                if self.currentSourceKey == nil || mergedClients[self.currentSourceKey!] == nil {
                    self.sourcePinnedByUser = false
                    if let playingKey = mergedClients.first(where: { $0.value.payload.isPlaying == true })?.key {
                        self.selectSource(key: playingKey)
                    } else if let firstKey = mergedClients.keys.first {
                        self.selectSource(key: firstKey)
                    } else {
                        self.clearPlayerState()
                    }
                } else if let key = self.currentSourceKey, let track = mergedClients[key] {
                    // Only refresh the *selected* source — never let another client's
                    // MediaRemote updates overwrite the active player UI.
                    if self.isStaleSpotifyMediaRemote(track.payload) {
                        self.applyPlaybackRefresh(track.payload)
                    } else if self.hasMediaChanged(track.payload) {
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

                // Keep the selected source's play/pause + timing fresh even when
                // the track fingerprint hasn't changed.
                if self.currentSourceKey == newKey {
                    // Critical: song changes arrive on the same client key. Refresh-only
                    // left title/artist/artwork frozen until the player was reopened.
                    if self.isStaleSpotifyMediaRemote(track.payload) {
                        // Connect already advanced — don't let lagging MediaRemote rewind UI.
                        self.applyPlaybackRefresh(track.payload)
                    } else if self.hasMediaChanged(track.payload) {
                        self.applyTrackPayload(track.payload, sourceKey: newKey)
                    } else {
                        self.applyPlaybackRefresh(track.payload)
                        if track.payload.artwork != nil && self.artwork == nil {
                            self.applyTrackPayload(track.payload, sourceKey: newKey)
                        }
                    }
                } else if self.isActivelyPlayingSpotifyPayload(track.payload) {
                    // Spotify is playing but isn't the selected source — surface its
                    // metadata anyway so the detail info stays live (not the primary media).
                    if self.isStaleSpotifyMediaRemote(track.payload) {
                        self.applyPlaybackRefresh(track.payload)
                    } else if self.hasMediaChanged(track.payload) {
                        self.applyTrackPayload(track.payload, sourceKey: newKey)
                    } else if track.payload.artwork != nil && self.artwork == nil {
                        self.applyTrackPayload(track.payload, sourceKey: newKey)
                    } else {
                        self.applyPlaybackRefresh(track.payload)
                    }
                }

                // Respect an explicit source choice from the music switcher.
                if track.payload.isPlaying == true,
                   self.currentSourceKey != newKey,
                   !self.sourcePinnedByUser {
                    self.selectSource(key: newKey)
                }
            }
        }

        mediaController.onListenerTerminated = { print("[MusicManager] Native media stream lost. Restarting.") }
        mediaController.onDecodingError = { error, _ in print("[MusicManager] Error decoding system media: \(error)") }
    }

    private func refreshSpotifyLiveSource() {
        let previousKey = currentSourceKey
        let merged = mergedSourcesWithSpotifyLive(activeMediaSources.filter { $0.key != spotifyLiveSourceKey })
        activeMediaSources = merged
        if let previousKey, merged[previousKey] == nil {
            sourcePinnedByUser = false
            if let playingKey = merged.first(where: { $0.value.payload.isPlaying == true })?.key {
                selectSource(key: playingKey)
            } else if let firstKey = merged.keys.first {
                selectSource(key: firstKey)
            } else {
                clearPlayerState()
            }
        }
    }

    private func buildSpotifyLiveTrackInfo() -> TrackInfo? {
        guard spotifyPrivateAPI.isLoggedIn else { return nil }

        if let state = spotifyPrivateAPI.playerState, let track = state.track {
            let title = track.metadata?.title
            let artist = track.metadata?.artistName
            let album = track.metadata?.albumTitle
            let elapsedSeconds: TimeInterval? = {
                guard let ms = state.realtimePositionMilliseconds() else { return nil }
                return TimeInterval(ms) / 1000.0
            }()

            let payload = TrackInfo.Payload(
                processIdentifier: nil,
                bundleIdentifier: "com.spotify.client",
                parentApplicationBundleIdentifier: nil,
                title: title,
                artist: artist,
                album: album,
                albumArtist: nil,
                composer: nil,
                genre: nil,
                chapterNumber: nil,
                totalChapterCount: nil,
                trackNumber: nil,
                discNumber: nil,
                totalTrackCount: nil,
                queueIndex: nil,
                totalQueueCount: nil,
                isPlaying: state.isActivelyPlaying,
                durationMicros: state.duration.map { Int64($0) * 1000 },
                currentElapsedTime: elapsedSeconds,
                elapsedTimeMicros: nil,
                playbackRate: state.isActivelyPlaying ? 1 : 0,
                startTime: nil,
                timestamp: nil,
                timestampEpochMicros: state.timestamp.map { $0 * 1000 },
                repeatMode: nil,
                shuffleMode: nil,
                isLiked: nil,
                isBanned: nil,
                isInWishList: nil,
                isAdvertisement: nil,
                isMusicApp: true,
                supportsIsLiked: true,
                supportsIsBanned: nil,
                supportsFastForward15Seconds: nil,
                supportsRewind15Seconds: nil,
                prohibitsSkip: nil,
                radioStationIdentifier: nil,
                radioStationHash: nil,
                contentItemIdentifier: track.uri,
                uniqueIdentifier: track.uid,
                mediaType: "music",
                artwork: nil,
                artworkMimeType: nil
            )
            return TrackInfo(payload: payload)
        }

        // Placeholder so the Spotify tab still appears when another app is playing
        // but Connect has no active track yet.
        let payload = TrackInfo.Payload(
            processIdentifier: nil,
            bundleIdentifier: "com.spotify.client",
            parentApplicationBundleIdentifier: nil,
            title: "Spotify",
            artist: "Not playing",
            album: nil,
            albumArtist: nil,
            composer: nil,
            genre: nil,
            chapterNumber: nil,
            totalChapterCount: nil,
            trackNumber: nil,
            discNumber: nil,
            totalTrackCount: nil,
            queueIndex: nil,
            totalQueueCount: nil,
            isPlaying: false,
            durationMicros: nil,
            currentElapsedTime: nil,
            elapsedTimeMicros: nil,
            playbackRate: 0,
            startTime: nil,
            timestamp: nil,
            timestampEpochMicros: nil,
            repeatMode: nil,
            shuffleMode: nil,
            isLiked: nil,
            isBanned: nil,
            isInWishList: nil,
            isAdvertisement: nil,
            isMusicApp: true,
            supportsIsLiked: true,
            supportsIsBanned: nil,
            supportsFastForward15Seconds: nil,
            supportsRewind15Seconds: nil,
            prohibitsSkip: nil,
            radioStationIdentifier: nil,
            radioStationHash: nil,
            contentItemIdentifier: "spotify-live-idle",
            uniqueIdentifier: "spotify-live-idle",
            mediaType: "music",
            artwork: nil,
            artworkMimeType: nil
        )
        return TrackInfo(payload: payload)
    }

    private func applySpotifyPlayerTiming(_ state: PlayerState) {
        let playing = heldOrReportedPlaying(state.isActivelyPlaying)
        if let timestamp = state.timestamp, let ms = state.positionAsOfTimestamp {
            let elapsedAtSample = TimeInterval(ms) / 1000.0
            let sampleEpoch = TimeInterval(timestamp) / 1000.0
            // Match Connect cluster math: paused → freeze at position_as_of_timestamp.
            let rate = playing ? 1.0 : 0.0
            playbackTimingAnchor = PlaybackTimingAnchor(
                elapsedAtSample: elapsedAtSample,
                sampleEpochTime: sampleEpoch,
                rate: rate
            )
        } else if let ms = state.positionAsOfTimestamp ?? state.realtimePositionMilliseconds() {
            // Fallback when dealer omits timestamp — still reset the scrubber.
            playbackTimingAnchor = PlaybackTimingAnchor(
                elapsedAtSample: TimeInterval(ms) / 1000.0,
                sampleEpochTime: Date().timeIntervalSince1970,
                rate: playing ? 1.0 : 0.0
            )
        }
        if let durationMs = state.duration, durationMs > 0 {
            currentTrackDuration = TimeInterval(durationMs) / 1000.0
            totalDuration = currentTrackDuration
        }
        // Ensure the 5 FPS scrubber is running even if isPlaying didn't flip.
        refreshTimers()
        publishPlaybackTime(force: true, includeProgressUI: true)
    }

    /// Immediate UI bookkeeping when Connect advances to a new track (artist + up-next).
    private func handleSpotifyTrackAdvanced(to track: PlayerState.Track?) {
        trackMetadataGeneration &+= 1
        let generation = trackMetadataGeneration

        // Drop previous song's ephemeral UI immediately.
        resetLyricsState()
        popularity = nil
        playCount = nil
        playCountValue = nil
        isLiked = false
        fetchedSpotifyPopularity = nil
        spotifyPrivateAPI.currentCanvas = nil
        spotifyPrivateAPI.relatedTracks = []
        spotifyPrivateAPI.similarAlbums = []
        spotifyPrivateAPI.trackArtistCredits = []
        spotifyPrivateAPI.popularReleases = []

        // Mark this Connect identity handled so title/artist didSets don't double-fetch.
        if let track,
           let title = track.metadata?.title,
           let artist = track.metadata?.artistName {
            lastHandledTrackKey = "com.spotify.client|\(track.uri)|\(title)|\(artist)".lowercased()
        } else {
            lastHandledTrackKey = nil
        }

        // Drop stale artist avatar until the new profile arrives.
        if settingsModel.settings.spotifyShowArtistProfile || settingsModel.settings.spotifyShowConcertTickets {
            spotifyPrivateAPI.nowPlayingArtist = nil
            spotifyPrivateAPI.artistConcerts = []
        }

        // Optimistically advance the up-next pill if the previous head became current.
        if let track, let head = nativeQueue.first, head.uri == track.uri || head.uid == track.uid {
            var advanced = nativeQueue
            advanced.removeFirst()
            nativeQueue = advanced
            // Keep PrivateAPI's published queue in sync for other views.
            spotifyPrivateAPI.nativeQueue = advanced
        }

        guard let track else {
            // Still try to refresh queue when playback stopped / unknown.
            lastNextSongFetchAttempt = .distantPast
            Task { await ensureNextSongAvailableIfNeeded(force: true) }
            return
        }

        triggerQuickPeek()
        trackDidChange.send()
        lastTrackChangeDate = Date()
        currentTrackArtworkToken = track.uri

        let artistURI = track.metadata?.artistUri
        let trackURI = track.uri
        Task {
            await refreshSpotifyExtendedTrackData(trackURI: trackURI, artistURI: artistURI, generation: generation)
            await scheduleSpotifyAccessoryHydration(uri: trackURI, generation: generation)
        }
        if nativeQueue.isEmpty || (nativeQueue.first?.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            lastNextSongFetchAttempt = .distantPast
            Task { await ensureNextSongAvailableIfNeeded(force: true) }
        }
    }

    private func applyTrackPayload(_ payload: TrackInfo.Payload, sourceKey: String) {
        // Ignore updates from non-selected sources so Spotify ↔ other media stay isolated,
        // EXCEPT when Spotify is actively playing — its detail info should stay live
        // regardless of which source is selected as primary.
        if let current = currentSourceKey, current != sourceKey, !isActivelyPlayingSpotifyPayload(payload) {
            return
        }
        self.latestTrackPayload = payload
        guard let title = payload.title, !title.isEmpty else {
            // Transitional MediaRemote frames often omit the title briefly — still apply
            // play/pause + timing so the player doesn't freeze mid-skip.
            applyPlaybackRefresh(payload)
            if self.title == nil {
                self.clearPlayerState()
            }
            return
        }

        let sourceBundleID = self.normalizeBundleID(payload.bundleIdentifier) ?? "N/A"
        if sourceBundleID == "com.apple.Music" {
            clearSpotifyTransientUIState()
        }

        if sourceBundleID == "com.spotify.client" {
            if let cid = payload.contentItemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               cid.contains("spotify:track:"),
               cid != self.uri {
                self.uri = cid
            }
        }

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
            // Spotify color-lyrics are fetched in handleTrackIdentifierChange when private API is up.
            if self.lastKnownBundleID != "com.spotify.client" || !spotifyPrivateAPI.isLoggedIn {
                Task { await self.fetchAndTranslateLyricsIfNeeded() }
            }
            self.trackDidChange.send()

            // Apply natively streamed artwork immediately with no disk or memory delay
            if let newArtwork = payload.artwork {
                self.applyArtwork(newArtwork, trackIdentity: trackIdentity)
            } else {
                self.requestArtworkForTrack(payload: payload, trackIdentity: trackIdentity)
            }

            // Local MediaRemote ad → background Spotify relaunch when Skip Ads is enabled.
            if sourceBundleID == "com.spotify.client",
               payload.isAdvertisement == true,
               settingsModel.settings.skipSpotifyAd {
                Task { await self.spotifyPrivateAPI.skipAdIfNeededFromMediaRemote(isAdvertisement: true) }
            }
        } else if let newArtwork = payload.artwork {
            self.applyArtwork(newArtwork, trackIdentity: trackIdentity)
        }

        if sourceBundleID == "com.spotify.client", spotifyPrivateAPI.isLoggedIn, !prefersNativeSpotifyMediaRemote {
            syncSpotifyPlayState(mediaRemoteHint: resolvedIsPlaying(from: payload))
        } else if let newIsPlaying = resolvedIsPlaying(from: payload) {
            applyPlayingState(newIsPlaying)
        }
        
        self.currentTrackDuration = TimeInterval(payload.durationMicros ?? 0) / 1_000_000
        self.totalDuration = self.currentTrackDuration

        // Spotify MediaRemote elapsed time is often frozen — prefer Connect wall-clock timing.
        if !applyConnectTimingIfPreferred() {
            syncPlaybackTiming(from: payload, trackChanged: hasTrackChanged)
        }

        if sourceBundleID != self.lastKnownBundleID {
            self.lastKnownBundleID = sourceBundleID
            if sourceBundleID == "com.spotify.client" {
                spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            }
            self.fetchAppIcon(for: sourceBundleID)
            self.updateDevicePolling()
        }
    }

    private func applyPlaybackRefresh(_ payload: TrackInfo.Payload) {
        latestTrackPayload = payload

        if normalizeBundleID(payload.bundleIdentifier) == "com.spotify.client", spotifyPrivateAPI.isLoggedIn, !prefersNativeSpotifyMediaRemote {
            syncSpotifyPlayState(mediaRemoteHint: resolvedIsPlaying(from: payload))
        } else if let newIsPlaying = resolvedIsPlaying(from: payload) {
            applyPlayingState(newIsPlaying)
        }

        let duration = TimeInterval(payload.durationMicros ?? 0) / 1_000_000
        if duration > 0, abs(duration - totalDuration) > 0.5 {
            currentTrackDuration = duration
            totalDuration = duration
        }

        if !applyConnectTimingIfPreferred() {
            syncPlaybackTiming(from: payload, trackChanged: false, publishImmediately: true)
        }
    }

    /// When Connect owns playback, its position is more reliable than MediaRemote.
    @discardableResult
    private func applyConnectTimingIfPreferred() -> Bool {
        guard spotifyPrivateAPI.isLoggedIn,
              !prefersNativeSpotifyMediaRemote,
              isSpotifyDisplayedInUI || shouldSurfaceSpotifyConnectPlayback,
              let state = spotifyPrivateAPI.playerState,
              state.timestamp != nil,
              state.positionAsOfTimestamp != nil else { return false }
        applySpotifyPlayerTiming(state)
        return true
    }

    private func resolvedIsPlaying(from payload: TrackInfo.Payload) -> Bool? {
        if let isPlaying = payload.isPlaying { return isPlaying }
        if let rate = payload.playbackRate { return rate != 0 }
        return nil
    }

    /// True when this payload is Spotify actively playing — used to surface Spotify's
    /// detail info even when it isn't the selected/primary media source.
    private func isActivelyPlayingSpotifyPayload(_ payload: TrackInfo.Payload) -> Bool {
        normalizeBundleID(payload.bundleIdentifier) == "com.spotify.client"
            && resolvedIsPlaying(from: payload) == true
    }

    // MARK: - Logic & Helpers

    /// Coalesce title+artist updates into one refresh (both didSets fire on track change).
    private func scheduleTrackIdentifierRefresh() {
        trackIdentifierRefreshTask?.cancel()
        trackIdentifierRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard !Task.isCancelled else { return }
            await self.handleTrackIdentifierChange()
        }
    }

    private func handleTrackIdentifierChange() async {
        if fetchedSpotifyPopularity != nil { fetchedSpotifyPopularity = nil }
        guard let currentTitle = self.title, let currentArtist = self.artist, !currentTitle.isEmpty, !currentArtist.isEmpty else { return }

        let trackKey = "\(lastKnownBundleID ?? "")|\(uri ?? "")|\(currentTitle)|\(currentArtist)".lowercased()
        guard trackKey != lastHandledTrackKey else { return }
        lastHandledTrackKey = trackKey

        trackMetadataGeneration &+= 1
        let generation = trackMetadataGeneration

        self.popularity = nil; self.playCount = nil; self.playCountValue = nil; self.isLiked = false

        if self.lastKnownBundleID == "com.apple.Music" {
            guard generation == self.trackMetadataGeneration else { return }
            self.isLiked = appleMusic.isTrackLiked()
            self.shuffleState = appleMusic.getShuffleState()
            self.repeatState = appleMusic.getRepeatState()
        } else if self.lastKnownBundleID == "com.spotify.client" {
            // Prefer Connect URI so we don't wait on (or race) a fuzzy title search.
            if let uri = self.uri, uri.contains("spotify:track:"), spotifyPrivateAPI.isLoggedIn {
                await scheduleSpotifyAccessoryHydration(uri: uri, generation: generation)
                let artistURI = self.nowPlayingTrack?.metadata?.artistUri
                    ?? self.spotifyPrivateAPI.playerState?.track?.metadata?.artistUri
                await refreshSpotifyExtendedTrackData(trackURI: uri, artistURI: artistURI, generation: generation)
                return
            }

            if let track = await searchForTrack(title: currentTitle, artist: currentArtist) {
                guard generation == self.trackMetadataGeneration else { return }
                self.uri = track.uri; self.trackID = track.id; self.popularity = track.popularity
                if spotifyPrivateAPI.isLoggedIn {
                    await scheduleSpotifyAccessoryHydration(uri: track.uri, trackId: track.id, generation: generation)
                    let artistURI = self.nowPlayingTrack?.metadata?.artistUri
                    await refreshSpotifyExtendedTrackData(trackURI: track.uri, artistURI: artistURI, generation: generation)
                } else if spotifyOfficialAPI.isAuthenticated, let liked = await spotifyOfficialAPI.checkIfTrackIsLiked(id: track.id) {
                    guard generation == self.trackMetadataGeneration else { return }
                    self.isLiked = liked
                }
                if self.playCount == nil, let count = await PlayCountFetcher.shared.getPlayCountValue(for: track.id) {
                    guard generation == self.trackMetadataGeneration else { return }
                    self.playCountValue = count
                    self.playCount = PlayCountFetcher.formatPlayCount(count)
                }
            } else {
                guard generation == self.trackMetadataGeneration else { return }
                await fetchAndTranslateLyricsIfNeeded()
            }
        }
    }

    /// Load artwork / liked / lyrics for a known track URI. Generation-gated against skip races.
    private func hydrateSpotifyTrackAccessories(uri: String, trackId: String? = nil, generation: UInt64) async {
        guard spotifyPrivateAPI.isLoggedIn else { return }
        guard generation == trackMetadataGeneration else { return }

        let id = trackId ?? uri.replacingOccurrences(of: "spotify:track:", with: "")
        guard !id.isEmpty, !id.contains(":") else { return }

        if self.uri != uri { self.uri = uri }
        if self.trackID != id { self.trackID = id }

        if let track = nowPlayingTrack, track.uri == uri {
            applyConnectArtworkIfNeeded(from: track, force: artwork == nil)
            guard generation == trackMetadataGeneration else { return }
        }

        guard needsSpotifyHeavyMetadata else { return }

        let details = await spotifyPrivateAPI.fetchTrackDetails(trackId: id)
        guard generation == trackMetadataGeneration else { return }
        if let details {
            if let count = details.playcountInt {
                playCountValue = count
                playCount = PlayCountFetcher.formatPlayCount(count)
            } else if let playcount = details.playcount, !playcount.isEmpty {
                playCount = playcount
            }

            if artwork == nil, let coverURL = details.albumOfTrack?.coverArt.bestImageURL {
                artworkURL = coverURL
                let token = "hydrate-\(coverURL.absoluteString.hashValue)-\(UUID().uuidString.prefix(6))"
                currentTrackArtworkToken = token
                await loadRemoteArtwork(from: coverURL, expectedToken: token)
                guard generation == trackMetadataGeneration else { return }
            }
        }

        let liked = await spotifyPrivateAPI.isTrackLiked(uri: uri)
        guard generation == trackMetadataGeneration else { return }
        self.isLiked = liked

        if playCountValue == nil, let count = await PlayCountFetcher.shared.getPlayCountValue(for: id) {
            guard generation == trackMetadataGeneration else { return }
            playCountValue = count
            playCount = PlayCountFetcher.formatPlayCount(count)
        }

        if popularity == nil, fetchedSpotifyPopularity == nil,
           let currentTitle = title, let currentArtist = artist,
           !currentTitle.isEmpty, !currentArtist.isEmpty,
           let track = await searchForTrack(title: currentTitle, artist: currentArtist) {
            guard generation == trackMetadataGeneration else { return }
            popularity = track.popularity
            fetchedSpotifyPopularity = track.popularity
        }

        guard needsLyricsUpdates else { return }

        let imageURL = details?.albumOfTrack?.coverArt.sources.first?.url
            ?? artworkURL?.absoluteString
            ?? nowPlayingTrack?.metadata?.imageURL?.absoluteString
            ?? ""
        let hasSpotifyLyrics = await spotifyPrivateAPI.trackHasLyrics(trackId: id)
        guard generation == trackMetadataGeneration else { return }
        if hasSpotifyLyrics != false {
            let spotifyLyrics = await spotifyPrivateAPI.fetchColorLyrics(
                trackId: id,
                imageURL: imageURL
            )
            guard generation == trackMetadataGeneration else { return }
            if !spotifyLyrics.isEmpty {
                replaceLyrics(spotifyLyrics)
            } else {
                await fetchAndTranslateLyricsIfNeeded()
            }
        } else {
            await fetchAndTranslateLyricsIfNeeded()
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
        
    func fetchActiveSpotifyDeviceState(forceRefresh: Bool = false) async -> ActiveSpotifyDeviceState? {
        if !forceRefresh, let cached = getActiveCachedSpotifyDeviceState() {
            return cached
        }
        if spotifyPrivateAPI.isLoggedIn {
            try? await spotifyPrivateAPI.refreshPlayerAndDeviceState()
            // Check if Spotify has an active device, regardless of playing state
            // (user might be paused but still wants to adjust volume with modifier keys)
            guard let playerState = spotifyPrivateAPI.playerState,
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
            // For official API, accept any active device (playing or paused)
            if let state = await spotifyOfficialAPI.fetchPlaybackState() {
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
    
    /// Faster version that uses cached device state without API call
    /// Returns nil if no device info is cached yet
    func getActiveCachedSpotifyDeviceState() -> ActiveSpotifyDeviceState? {
        if spotifyPrivateAPI.isLoggedIn {
            guard let activeDeviceID = spotifyPrivateAPI.activePlayerDeviceID else { return nil }
            
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
        case "tablet": return "ipad"
        case "automobile": return "car.fill"
        case "wearable": return "applewatch"
        default: return "hifispeaker.2.fill"
        }
    }

    /// SF Symbol for the currently active Connect / AirPlay output device.
    func currentOutputDeviceSystemImage() -> String {
        if settingsModel.settings.preferAirPlayOverSpotify,
           let device = AudioDeviceManager().getCurrentOutputDevice() {
            return IconMapper.icon(for: device)
        }
        if let activeID = spotifyPrivateAPI.activePlayerDeviceID,
           let device = spotifyPrivateAPI.devices.first(where: { $0.deviceId == activeID }) {
            return iconName(for: device.deviceType)
        }
        if let device = AudioDeviceManager().getCurrentOutputDevice() {
            return IconMapper.icon(for: device)
        }
        return MusicPlayerButtonType.devices.systemImage
    }

    /// App icon for a multi-source switcher key (Spotify Live → Spotify app icon).
    func sourceAppIcon(for key: String) -> NSImage {
        let bundleID: String?
        if key.contains("spotify-live") || key.lowercased().contains("spotify") {
            bundleID = "com.spotify.client"
        } else if let track = activeMediaSources[key] {
            bundleID = normalizeBundleID(track.payload.bundleIdentifier)
        } else {
            bundleID = nil
        }
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 16, height: 16))
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
        let reported = Double(latestTrackPayload?.playbackRate ?? 1.0)
        let rate = isPlaying ? (reported > 0 ? reported : 1.0) : 0
        playbackTimingAnchor = PlaybackTimingAnchor(
            elapsedAtSample: clamped,
            sampleEpochTime: Date().timeIntervalSince1970,
            rate: rate
        )
        refreshTimers()
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

        // Lyrics must track wall-clock elapsed even when we skip a progress UI publish.
        if needsLyricsUpdates {
            updateCurrentLyric(for: clampedElapsed)
        }

        let publishesProgress = includeProgressUI ?? (isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen)
        let elapsedThreshold = publishesProgress ? 0.025 : 0.45
        let elapsedDelta = abs(clampedElapsed - currentElapsedTime)
        
        if !force, elapsedDelta < elapsedThreshold {
            return
        }

        currentElapsedTime = clampedElapsed
        if publishesProgress {
            playbackProgress = progress
            playbackTimePublisher.send((elapsed: clampedElapsed, progress: progress))
        }
    }

    private func clearPlayerState() {
        self.latestTrackPayload = nil
        self.currentSourceKey = nil
        self.sourcePinnedByUser = false
        invalidateAllTimers()
        playbackTimingAnchor = nil
        lastPlaybackSyncWasPlaying = false
        lastTrackIdentity = nil
        lastMediaFingerprint = nil
        currentTrackArtworkToken = ""
        self.title = nil; self.artist = nil; self.album = nil; self.artwork = nil; self.artworkURL = nil
        self.uri = nil; self.trackID = nil; self.popularity = nil; self.playCount = nil; self.playCountValue = nil
        self.isPlaying = false; self.totalDuration = 0; self.currentElapsedTime = 0
        self.lastHandledTrackKey = nil
        self.resetLyricsState()
    }

    private func refreshTimers() {
        // Keep ticking while any lyrics/player surface is open so lines advance with wall-clock time.
        // Progress UI still gates on isPlaying via TimelineView; lyric lookup is cheap.
        let needsDetailTimer = (isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen)
            && (isPlaying || !lyrics.isEmpty)
        let needsActivityTimer = isPlaying && isMusicLiveActivityActive && settingsModel.settings.showLyricsInLiveActivity && settingsModel.settings.musicLiveActivityEnabled

        // OPTIMIZATION: Throttled scrubber loop down to 5 FPS (0.2s) to drastically reduce CPU rendering workloads [3]
        if needsDetailTimer {
            if detailPlayerTimer == nil {
                let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.publishPlaybackTime(includeProgressUI: true)
                    }
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
                    Task { @MainActor in
                        guard let self = self, self.isPlaying else { return }
                        self.publishPlaybackTime(includeProgressUI: false)
                    }
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

    /// Wall-clock elapsed time for TimelineView-driven progress UI.
    func elapsedTime(at date: Date = Date()) -> TimeInterval {
        let exact: TimeInterval
        if let anchor = playbackTimingAnchor {
            exact = anchor.elapsed(at: date)
        } else if let payload = latestTrackPayload {
            exact = payload.interpolatedElapsedTime(at: date)
        } else {
            return currentElapsedTime
        }
        return totalDuration > 0 ? max(0.0, min(totalDuration, exact)) : max(0.0, exact)
    }

    func progress(at date: Date = Date()) -> Double {
        guard totalDuration > 0 else { return 0 }
        return max(0.0, min(1.0, elapsedTime(at: date) / totalDuration))
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
            lyricsCache.removeAll()
            return
        }
        var filtered = lyricsCache
        filtered.removeValue(forKey: key)
        if filtered.count > 50 {
            filtered.removeAll()
        }
        lyricsCache = filtered
    }

    private func hasMediaChanged(_ payload: TrackInfo.Payload) -> Bool {
        // Identity (URI/UID) is authoritative when available — two songs can share
        // title/artist/album strings yet be different tracks (deluxe re-releases).
        // Only compare same-format identities to avoid cross-format false positives.
        let incomingIdentity = trackIdentity(for: payload)
        if incomingIdentity.hasPrefix("cid:"), lastTrackIdentity?.hasPrefix("cid:") == true {
            return incomingIdentity != lastTrackIdentity
        }
        if incomingIdentity.hasPrefix("uid:"), lastTrackIdentity?.hasPrefix("uid:") == true {
            return incomingIdentity != lastTrackIdentity
        }
        let fingerprint = mediaFingerprint(for: payload)
        if !fingerprint.isEmpty {
            return fingerprint != lastMediaFingerprint
        }
        return incomingIdentity != lastTrackIdentity
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
        // Artwork arrives via MediaRemote payload or requestArtworkForTrack.
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
        guard shouldExtractArtworkColors else { return }

        artworkColorExtractionTask = Task { @MainActor in
            guard !Task.isCancelled, self.shouldExtractArtworkColors else { return }

            if self.lastKnownBundleID == "com.spotify.client", self.spotifyPrivateAPI.isLoggedIn {
                if let imageURL = self.artworkURL?.absoluteString ?? self.nowPlayingTrack?.metadata?.imageURL?.absoluteString {
                    let colors = await self.spotifyPrivateAPI.fetchExtractedColors(for: [imageURL])
                    if let primary = colors.first {
                        let accent = primary.swiftUIColor.ensuringMinimumBrightness(0.52)
                        self.accentColor = accent
                        self.leftGradientColor = accent.opacity(0.85)
                        self.rightGradientColor = accent.opacity(0.65)
                        return
                    }
                }
            }

            guard let artwork = artwork else { return }
            if let edgeColors = artwork.getEdgeColors() {
                let accent = edgeColors.accent.ensuringMinimumBrightness(0.52)
                self.accentColor = accent
                self.leftGradientColor = edgeColors.left.ensuringMinimumBrightness(0.42)
                self.rightGradientColor = edgeColors.right.ensuringMinimumBrightness(0.42)
            } else {
                self.resetColorsToDefault()
            }
        }
    }

    private func refreshSpotifyExtendedTrackData(trackURI: String, artistURI: String?, generation: UInt64? = nil) async {
        guard spotifyPrivateAPI.isLoggedIn else { return }
        if let generation, generation != trackMetadataGeneration { return }
        let settings = settingsModel.settings

        let wantCanvas = settings.spotifyCanvasLiveVideo
        let wantSuggested = settings.spotifyShowSuggestedSongs
        let wantArtist = settings.spotifyShowArtistProfile
        let wantConcerts = settings.spotifyShowConcertTickets
        guard wantCanvas || wantSuggested || wantArtist || wantConcerts else { return }

        async let canvas: Void = {
            if wantCanvas { _ = await spotifyPrivateAPI.fetchCanvas(for: trackURI) }
        }()
        async let related: Void = {
            if wantSuggested { _ = await spotifyPrivateAPI.fetchRelatedTracks(for: trackURI) }
        }()
        async let similar: Void = {
            if wantSuggested { _ = await spotifyPrivateAPI.fetchSimilarAlbums(for: trackURI) }
        }()
        async let credits: Void = {
            if wantArtist { _ = await spotifyPrivateAPI.fetchTrackArtists(for: trackURI) }
        }()
        if let artistURI, wantConcerts || wantArtist {
            // NPV artist fetch also publishes nowPlayingArtist (avatar) — needed even when concerts are off.
            async let artistProfile: Void = {
                _ = await spotifyPrivateAPI.fetchArtistConcerts(artistURI: artistURI, trackURI: trackURI)
            }()
            async let popular: Void = {
                if wantArtist {
                    let artistId = artistURI.replacingOccurrences(of: "spotify:artist:", with: "")
                    _ = await spotifyPrivateAPI.fetchPopularReleases(artistId: artistId)
                }
            }()
            _ = await (artistProfile, popular)
        }
        _ = await (canvas, related, similar, credits)
        _ = generation // used for early-return above; publish paths guard on current track URI
    }

    private func refreshLyricsLoadingState() {
        if needsLyricsUpdates {
            if lyrics.isEmpty {
                print("[MusicManager:Lyrics] Dedicated view opened but lyrics list is empty. Triggering fetch.")
                Task { await fetchAndTranslateLyricsIfNeeded() }
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

    private func fetchAndTranslateLyricsIfNeeded() async {
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
        
        if let cachedLyrics = lyricsCache[cacheKey] {
            print("[MusicManager:Lyrics] Hit local memory cache! Loaded \(cachedLyrics.count) lines instantly.")
            self.replaceLyrics(cachedLyrics)
            self.retranslateLyricsIfNeeded()
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
                self.replaceLyrics(fL)
                self.lyricsCache[cacheKey] = fL
                self.retranslateLyricsIfNeeded()
            }
        }
        await lyricsFetchTask?.value
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
                self.replaceLyrics(lyricsToUpdate, preservePosition: true)
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
            self.replaceLyrics(lyricsToUpdate, preservePosition: true)
        }
    }

    /// Replace lyric lines and always re-bind `currentLyric` (index-only equality left stale text after song changes).
    private func replaceLyrics(_ newLyrics: [LyricLine], preservePosition: Bool = false) {
        lyrics = newLyrics
        lastLyricLookupSecond = -1
        if preservePosition, let idx = currentLyricIndex, newLyrics.indices.contains(idx) {
            let line = newLyrics[idx]
            if currentLyric?.id != line.id || currentLyric?.translatedText != line.translatedText {
                currentLyric = line
                currentLyricPublisher.send(line)
            }
        } else {
            currentLyricIndex = nil
            currentLyric = nil
            currentLyricPublisher.send(nil)
        }
        if needsLyricsUpdates {
            updateCurrentLyric(for: currentElapsedTime)
        }
    }

    private func updateCurrentLyric(for elapsedTime: TimeInterval) {
        guard needsLyricsUpdates, !lyrics.isEmpty else { return }

        let newIndex = binarySearchLyric(for: elapsedTime)
        let newLyric = newIndex.map { lyrics[$0] }

        // Only skip when the active line is unchanged — do not gate on whole-second buckets
        // (multiple lines often share the same second).
        guard newIndex != currentLyricIndex || currentLyric?.id != newLyric?.id else { return }

        currentLyricIndex = newIndex
        lastLyricLookupSecond = Int(elapsedTime)
        if currentLyric?.id != newLyric?.id {
            currentLyric = newLyric
            currentLyricPublisher.send(newLyric)
        }
    }

    /// Active lyric line for a wall-clock sample — used by TimelineView-driven lyric UIs.
    func lyricLine(at date: Date = Date()) -> LyricLine? {
        guard !lyrics.isEmpty else { return nil }
        let elapsed = elapsedTime(at: date)
        guard let index = binarySearchLyric(for: elapsed) else { return nil }
        return lyrics[index]
    }

    /// Index of the active lyric at `date`, if any.
    func lyricIndex(at date: Date = Date()) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        return binarySearchLyric(for: elapsedTime(at: date))
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

        settingsModel.$settings
            .map(\.showSpotifySourceTab)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSpotifyLiveSource()
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

