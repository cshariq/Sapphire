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
    lazy var airPlay = AirPlayManager.shared
    lazy var spotifyAppleScript = SpotifyAppleScriptManager.shared
    lazy var spotifyOfficialAPI = SpotifyOfficialAPIManager.shared
    lazy var tidalAPI = TidalAPIManager.shared
    lazy var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared
    lazy var appleMusicPrivateAPI = AppleMusicPrivateAPIManager.shared
    lazy var browserAppleScript = BrowserAppleScriptManager.shared

    // MARK: - Proxied Authentication States
    @Published var officialAPIHasKeys: Bool = false
    @Published var isOfficialAPIAuthenticated: Bool = false
    @Published var isTidalAPIAuthenticated: Bool = false
    @Published var isPrivateAPIAuthenticated: Bool = false
    @Published var isAppleMusicPrivateAPIAuthenticated: Bool = false
    @Published var isPremiumUser: Bool = false

    // MARK: - Published UI State
    let playbackTimePublisher = PassthroughSubject<(elapsed: TimeInterval, progress: Double), Never>()
    let volumePublisher = PassthroughSubject<Float, Never>()
    let currentLyricPublisher = PassthroughSubject<LyricLine?, Never>()
    let trackDidChange = PassthroughSubject<Void, Never>()

    @Published var title: String? {
        didSet {
            if oldValue != title { scheduleTrackIdentifierRefresh() }
        }
    }
    @Published var artist: String? {
        didSet {
            if oldValue != artist { scheduleTrackIdentifierRefresh() }
        }
    }
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
            refreshWordTimingGenerationState()
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
            await ensureSpotifyPlayerExtrasLoaded(force: true)
            await backfillSpotifyMetadataIfNeeded()
        }
        refreshLyricsLoadingState()
        refreshArtworkColorExtractionIfNeeded()
    }

    func setMusicHubOpen(_ isOpen: Bool) async {
        guard isMusicHubOpen != isOpen else { return }
        isMusicHubOpen = isOpen
        if isOpen {
            spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            if spotifyPrivateAPI.isLoggedIn {
                Task(priority: .utility) {
                    try? await self.spotifyPrivateAPI.refreshPlayerAndDeviceState()
                }
            }
            await ensureSpotifyPlayerExtrasLoaded(force: true)
            await ensureNextSongAvailableIfNeeded()
        }
    }

    func refreshPlayerUIAfterReturning() async {
        if isSpotifyLiveSourceSelected {
            refreshSpotifyLiveSource()
            applySpotifyLiveUIFromPlayerState(forceArtwork: false)
        }
        await ensureNextSongAvailableIfNeeded()
        publishPlaybackTime(force: true, includeProgressUI: true)
        if isDetailPlayerOpen, isSpotifySourceSelected {
            await ensureSpotifyPlayerExtrasLoaded(force: false)
        }
        objectWillChange.send()
    }

    func currentSpotifyArtistNavigation() -> (uri: String, name: String)? {
        guard isSpotifySourceSelected else { return nil }
        if let artist = spotifyPrivateAPI.nowPlayingArtist,
           !artist.uri.isEmpty {
            return (artist.uri, artist.name)
        }
        if let credit = spotifyPrivateAPI.trackArtistCredits.first(where: { !$0.uri.isEmpty }) {
            return (credit.uri, credit.name)
        }
        let track = nowPlayingTrack ?? spotifyPrivateAPI.playerState?.track
        if let uri = track?.metadata?.artistUri, !uri.isEmpty {
            let name = track?.metadata?.artistName ?? artist ?? "Artist"
            return (uri, name)
        }
        return nil
    }

    func setLyricsDetailOpen(_ isOpen: Bool) async {
        await setLyricsSurfaceOpen(isOpen, at: \.isLyricsDetailOpen, named: "Lyrics View")
    }

    func setDetachedLyricsOpen(_ isOpen: Bool) async {
        await setLyricsSurfaceOpen(isOpen, at: \.isDetachedLyricsOpen, named: "Detached Lyrics Window")
    }

    private func setLyricsSurfaceOpen(
        _ isOpen: Bool,
        at keyPath: ReferenceWritableKeyPath<MusicManager, Bool>,
        named name: String
    ) async {
        guard self[keyPath: keyPath] != isOpen else { return }
        self[keyPath: keyPath] = isOpen
        print("[MusicManager:Timing] \(name) open state changed to: \(isOpen)")
        refreshTimers()
        if isOpen {
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
        LyricsLog.info("Music live activity \(isActive ? "active" : "inactive")")
        refreshTimers()
        refreshLyricsLoadingState()
        refreshArtworkColorExtractionIfNeeded()
        if isActive {
            await ensureLyricsForCurrentTrack()
        }
    }

    @Published var totalDuration: TimeInterval = 0
    @Published var lyrics: [LyricLine] = [] {
        didSet {
            let displayable = lyrics.contains(where: Self.isDisplayable)
            if hasDisplayableLyrics != displayable { hasDisplayableLyrics = displayable }
            if oldValue.isEmpty != lyrics.isEmpty {
                LyricsLog.info(lyrics.isEmpty
                    ? "Lyrics cleared"
                    : "Lyrics loaded: \(lyrics.count) lines (\(lyrics.filter(\.hasWordTiming).count) word-synced)")
                refreshTimers()
            }
        }
    }

    @Published private(set) var hasDisplayableLyrics: Bool = false
    @Published private(set) var hasCurrentDisplayableLyric: Bool = false

    private static func isDisplayable(_ line: LyricLine) -> Bool {
        !(line.translatedText ?? line.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    @Published var accentColor: Color = .white
    @Published var leftGradientColor: Color = .white
    @Published var rightGradientColor: Color = .white
    @Published var appIcon: NSImage?
    @Published var shouldShowLiveActivity: Bool = false
    @Published var popularity: Int?
    @Published var playCount: String?
    @Published private(set) var playCountValue: Int?
    @Published var fetchedSpotifyPopularity: Int?
    @Published var applePlayCount: Int?
    @Published var applePopularity: Int?
    @Published var appleSuggestedTracks: [AppleMusicSong] = []
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

    @Published var activeMediaSources: [String: TrackInfo] = [:]
    @Published var currentSourceKey: String?
    private var sourcePinnedByUser = false
    private let spotifyLiveSourceKey = "com.spotify.client:spotify-live"
    private var lastPublishedSourceSignature: Int = 0
    private var lastExtractedArtworkToken: String?

    @Published var nativeQueue: [PlayerState.Track] = []
    @Published var nowPlayingTrack: PlayerState.Track?

    @Published private(set) var appleMusicNextTrack: AppleMusicManager.QueueTrack?

    @Published private(set) var currentLyric: LyricLine? {
        didSet {
            let displayable = currentLyric.map(Self.isDisplayable) ?? false
            if hasCurrentDisplayableLyric != displayable { hasCurrentDisplayableLyric = displayable }
            if oldValue?.id != currentLyric?.id {
                LyricsLog.info(currentLyric.map {
                    "Current line → \($0.id.uuidString.prefix(8)) at \(String(format: "%.2f", $0.timestamp))s (\($0.words.count) words)"
                } ?? "Current line → none")
            }
        }
    }
    @Published private(set) var isDetailPlayerOpen: Bool = false
    @Published private(set) var isMusicHubOpen: Bool = false
    @Published private(set) var isLyricsDetailOpen: Bool = false
    @Published private(set) var isDetachedLyricsOpen: Bool = false
    @Published private(set) var isMusicLiveActivityActive: Bool = false
    private(set) var systemVolume: Float = 0.0

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
    private var cancellables = Set<AnyCancellable>()
    private var quickPeekTimer: Timer?
    private var airplayDeviceUpdateTimer: Timer?
    private var transientIconTimer: Timer?
    private var currentLyricIndex: Int? = nil

    private var liveActivityTimer: Timer?
    private var liveActivityTimerInterval: TimeInterval = 0
    private var liveActivityTimerRepeats = false
    private var latestTrackPayload: TrackInfo.Payload?
    private var playbackTimingAnchor: PlaybackTimingAnchor?
    private var lastTrackIdentity: String?
    private var lastMediaFingerprint: String?
    private var currentlyFetchingFingerprint: String?
    private var lastAttemptedLyricsFingerprint: String?
    private var artworkColorExtractionTask: Task<Void, Never>?
    private var trackIdentifierRefreshTask: Task<Void, Never>?
    private var lastHandledTrackKey: String?
    private var lastNextSongFetchAttempt: Date = .distantPast
    private var playStateHoldUntil: Date = .distantPast
    private var playStateHoldPreferPlaying = true
    private var spotifyPlayStateReconcileUntil: Date = .distantPast
    private var spotifyPlayStateReconcileTarget: Bool?
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
              settingsModel.settings.musicLiveActivityEnabled else { return false }
        return ActiveAppMonitor.shared.isLyricsAllowedForActiveApp
    }

    private var shouldExtractArtworkColors: Bool {
        isDetailPlayerOpen || isMusicLiveActivityActive
    }

    private var needsSpotifyHeavyMetadata: Bool {
        isDetailPlayerOpen || isMusicHubOpen || isLyricsDetailOpen || isDetachedLyricsOpen ||
        settingsModel.settings.showPopularityInMusicPlayer || needsLyricsUpdates
    }

    private var needsSpotifyPlayerEnrichment: Bool {
        isDetailPlayerOpen || isMusicHubOpen || isLyricsDetailOpen || isDetachedLyricsOpen
    }

    private init() {
        spotifyOfficialAPI.$hasApiKeys.assign(to: &$officialAPIHasKeys)
        spotifyOfficialAPI.$isAuthenticated.assign(to: &$isOfficialAPIAuthenticated)
        tidalAPI.$isAuthenticated.assign(to: &$isTidalAPIAuthenticated)
        spotifyPrivateAPI.$isLoggedIn.assign(to: &$isPrivateAPIAuthenticated)
        appleMusicPrivateAPI.$isLoggedIn.assign(to: &$isAppleMusicPrivateAPIAuthenticated)
        spotifyOfficialAPI.$isPremiumUser.assign(to: &$isPremiumUser)

        spotifyPrivateAPI.$isLoggedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loggedIn in
                guard let self else { return }
                self.refreshSpotifyLiveSource()
                if !loggedIn {
                    self.rebindToBestSystemMediaSource(forceReapply: true)
                }
            }
            .store(in: &cancellables)

        airPlay.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.airplayDevices = devices
            }
            .store(in: &cancellables)

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
                self?.handleSpotifyPlayerState(state)
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

    // MARK: - Spotify Connect State

    private func handleSpotifyPlayerState(_ state: PlayerState?) {
        guard let state else {
            refreshSpotifyLiveSource()
            return
        }
        guard isSpotifySourceSelected else { return }

        let incomingURI = state.track?.uri
        let trackChanged = incomingURI != nil && incomingURI != lastConnectTrackURI
        let playChanged: Bool = {
            if let previous = activeMediaSources[spotifyLiveSourceKey]?.payload.isPlaying {
                return previous != state.isActivelyPlaying
            }
            return state.isActivelyPlaying != isPlaying
        }()

        let isLoggedIn = spotifyPrivateAPI.isLoggedIn
        if trackChanged || playChanged || activeMediaSources[spotifyLiveSourceKey] == nil {
            refreshSpotifyLiveSource()
        }
        if isLoggedIn {
            applySpotifyConnectTransport(state)
        }

        guard shouldSurfaceSpotifyConnectPlayback else { return }

        guard trackChanged else {
            if playChanged { applySpotifyPlaybackOptions(state) }
            if !isLoggedIn { applySpotifyConnectTransport(state) }
            if isDetailPlayerOpen {
                Task { await self.ensureNextSongAvailableIfNeeded() }
            }
            return
        }

        applySpotifyPlaybackOptions(state)
        beginPlayStateHold(preferPlaying: state.isActivelyPlaying, duration: 0.55)
        applyPlayingState(state.isActivelyPlaying, fromConnect: true)

        if let incomingURI { lastConnectTrackURI = incomingURI }

        if isSpotifyLiveSourceSelected {
            applySpotifyLiveUIFromPlayerState(forceArtwork: true)
        } else if let track = state.track {
            publishSpotifyMediaIdentity(from: track, forceArtwork: true)
            applySpotifyConnectTransport(state)
        }

        lastNextSongFetchAttempt = .distantPast
        handleSpotifyTrackAdvanced(to: state.track)
        objectWillChange.send()

        if isDetailPlayerOpen || isMusicHubOpen {
            Task { await self.ensureNextSongAvailableIfNeeded() }
        }
    }

    private func applySpotifyConnectTransport(_ state: PlayerState) {
        applyPlayingState(state.isActivelyPlaying, fromConnect: true)
        applySpotifyPlayerTiming(state)
    }

    private func applySpotifyPlaybackOptions(_ state: PlayerState) {
        let shuffling = state.options?.shufflingContext ?? false
        shuffleState = shuffling
        if state.options?.repeatingTrack ?? false {
            repeatState = .track
        } else if state.options?.repeatingContext ?? false {
            repeatState = .context
        } else {
            repeatState = .off
        }
        if !shuffling { spotifyPrivateAPI.isSmartShuffleActive = false }
    }

    private func setupSpotifyBootstrapObserver() {
        settingsModel.$settings
            .map(\.defaultMusicPlayer)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] player in
                guard player == .spotify else { return }
                self?.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            }
            .store(in: &cancellables)

        $lastKnownBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                guard let self, bundleID == "com.spotify.client" else { return }
                self.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            }
            .store(in: &cancellables)

        $lastKnownBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                guard let self, bundleID == "com.apple.Music" else { return }
                guard !self.appleMusic.isMusicKitAuthorized, self.appleMusic.isMusicKitConfigured else { return }
                Task { await self.appleMusic.requestAuthorization() }
            }
            .store(in: &cancellables)
    }

    private func setupPrivateAPIUIForwarding() {
        let artist = spotifyPrivateAPI.$nowPlayingArtist.map { _ in () }.eraseToAnyPublisher()
        let related = spotifyPrivateAPI.$relatedTracks.map { _ in () }.eraseToAnyPublisher()
        let similar = spotifyPrivateAPI.$similarAlbums.map { _ in () }.eraseToAnyPublisher()
        let concerts = spotifyPrivateAPI.$artistConcerts.map { _ in () }.eraseToAnyPublisher()
        let credits = spotifyPrivateAPI.$trackArtistCredits.map { _ in () }.eraseToAnyPublisher()
        let canvas = spotifyPrivateAPI.$currentCanvas.map { _ in () }.eraseToAnyPublisher()
        let account = spotifyPrivateAPI.$accountInfo.map { _ in () }.eraseToAnyPublisher()
        let activeDevice = spotifyPrivateAPI.$activePlayerDeviceID.map { _ in () }.eraseToAnyPublisher()
        let deviceIDs = spotifyPrivateAPI.$devices
            .map { $0.map(\.deviceId) }
            .removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()

        Publishers.MergeMany([artist, related, similar, concerts, credits, canvas, account, activeDevice, deviceIDs])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func publishSpotifyMediaIdentity(from track: PlayerState.Track, forceArtwork: Bool) {
        guard isSpotifySourceSelected else { return }
        syncConnectNowPlayingMetadata(from: track)
        lockConnectMediaIdentity(from: track)
        applyConnectArtworkIfNeeded(from: track, force: forceArtwork)
    }

    private func syncConnectNowPlayingMetadata(from track: PlayerState.Track) {
        guard isSpotifySourceSelected else { return }
        if lastKnownBundleID != "com.spotify.client" {
            lastKnownBundleID = "com.spotify.client"
            fetchAppIcon(for: "com.spotify.client")
        }
        var identityChanged = false
        if let title = track.metadata?.title.trimmedOrNil, title != self.title {
            self.title = title
            identityChanged = true
        }
        if let artist = track.metadata?.artistName.trimmedOrNil, artist != self.artist {
            self.artist = artist
            identityChanged = true
        }
        if let album = track.metadata?.albumTitle.trimmedOrNil, album != self.album {
            self.album = album
            identityChanged = true
        }
        if let imageURL = track.metadata?.imageURL, imageURL != self.artworkURL {
            self.artworkURL = imageURL
        }
        if track.uri != self.uri {
            self.uri = track.uri
            identityChanged = true
        }
        if track.uri.contains("spotify:track:") {
            let id = track.uri.replacingOccurrences(of: "spotify:track:", with: "")
            if !id.isEmpty, trackID != id {
                trackID = id
            }
        }
        if identityChanged {
            trackDidChange.send()
        }
    }

    private func lockConnectMediaIdentity(from track: PlayerState.Track) {
        guard isSpotifySourceSelected else { return }
        let fingerprint = Self.mediaFingerprint(
            title: track.metadata?.title,
            artist: track.metadata?.artistName
        )
        if !fingerprint.isEmpty {
            lastMediaFingerprint = fingerprint
        }
        lastTrackIdentity = track.uri
    }

    private func isStaleSpotifyMediaRemote(_ payload: TrackInfo.Payload) -> Bool {
        guard isSpotifySourceSelected,
              shouldPreferSpotifyPrivateNowPlaying,
              let connect = spotifyPrivateAPI.playerState?.track else { return false }
        let bundle = MediaApplicationIdentity.canonicalBundleID(payload.bundleIdentifier)
        guard bundle == "com.spotify.client" else { return false }

        guard let connectTitle = connect.metadata?.title.trimmedOrNil?.lowercased(),
              let remoteTitle = payload.title.trimmedOrNil?.lowercased() else { return false }
        if connectTitle != remoteTitle { return true }

        fillSpotifyIdentityGapsFromMediaRemote(payload)
        return false
    }

    private func fillSpotifyIdentityGapsFromMediaRemote(_ payload: TrackInfo.Payload) {
        guard isSpotifySourceSelected else { return }
        if artist.isBlank, let remoteArtist = payload.artist.trimmedOrNil {
            artist = remoteArtist
        }
        if album.isBlank, let remoteAlbum = payload.album.trimmedOrNil {
            album = remoteAlbum
        }
        if artwork == nil, let art = payload.artwork {
            applyArtwork(art, trackIdentity: lastTrackIdentity ?? uri)
        }
    }

    private func applyConnectArtworkIfNeeded(from track: PlayerState.Track, force: Bool) {
        guard isSpotifySourceSelected else { return }
        guard let imageURL = track.metadata?.imageURL else { return }
        let urlChanged = artworkURL != imageURL
        artworkURL = imageURL
        let needsLoad = force || urlChanged || artwork == nil || currentTrackArtworkToken.isEmpty
        guard needsLoad else { return }
        let token = "connect-\(imageURL.absoluteString.hashValue)-\(UUID().uuidString.prefix(6))"
        currentTrackArtworkToken = token
        Task {
            await loadRemoteArtwork(from: imageURL, expectedToken: token)
        }
    }

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
                playStateHoldUntil = .distantPast
            } else {
                return
            }
        }
        if isPlaying != playing {
            isPlaying = playing
            freezeOrResumeTimingAnchor(playing: playing)
        } else {
            syncTimingAnchorRate(playing: playing)
        }

        if fromConnect, playing == spotifyPlayStateReconcileTarget {
            spotifyPlayStateReconcileUntil = .distantPast
            spotifyPlayStateReconcileTarget = nil
        }
    }

    private func freezeOrResumeTimingAnchor(playing: Bool) {
        let now = Date()
        let elapsed = playbackTimingAnchor?.elapsed(at: now) ?? currentElapsedTime
        playbackTimingAnchor = PlaybackTimingAnchor(
            elapsedAtSample: max(0, elapsed),
            sampleEpochTime: now.timeIntervalSince1970,
            rate: playing ? 1.0 : 0.0
        )
        refreshTimers()
        publishPlaybackTime(force: true, includeProgressUI: true)
    }

    private func syncTimingAnchorRate(playing: Bool) {
        guard let anchor = playbackTimingAnchor else {
            freezeOrResumeTimingAnchor(playing: playing)
            return
        }
        let desiredRate = playing ? 1.0 : 0.0
        guard abs(anchor.rate - desiredRate) > 0.01 else { return }
        freezeOrResumeTimingAnchor(playing: playing)
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
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        quickPeekTimer?.invalidate()
        airplayDeviceUpdateTimer?.invalidate()
        transientIconTimer?.invalidate()
        liveActivityTimer?.invalidate()
        if let volumeListener {
            Self.removeVolumeListener(volumeListener)
        }
    }

    // MARK: - Core Playback Actions (Context-Aware)

    func play() async {
        beginPlayStateHold(preferPlaying: true, duration: 1.2)
        applyPlayingState(true)

        guard isSpotifySourceSelected else {
            mediaController.play()
            return
        }
        beginSpotifyPlayStateReconcile(target: true)

        if spotifyPrivateAPI.isLoggedIn {
            if await spotifyPrivateAPI.connectResume() { return }
            if spotifyAppleScript.isAppRunning() {
                _ = await spotifyAppleScript.play(uri: "")
            } else if spotifyOfficialAPI.isAuthenticated, isPremiumUser {
                _ = await spotifyOfficialAPI.playTrack(uri: "")
            }
            return
        }

        if spotifyOfficialAPI.isAuthenticated, isPremiumUser {
            _ = await spotifyOfficialAPI.playTrack(uri: "")
        } else if spotifyAppleScript.isAppRunning() {
            _ = await spotifyAppleScript.play(uri: "")
        } else {
            mediaController.play()
        }
    }

    func pause() async {
        beginPlayStateHold(preferPlaying: false, duration: 1.2)
        applyPlayingState(false)

        guard isSpotifySourceSelected else {
            mediaController.pause()
            return
        }
        beginSpotifyPlayStateReconcile(target: false)

        if spotifyPrivateAPI.isLoggedIn {
            if await spotifyPrivateAPI.connectPause() { return }
            if spotifyAppleScript.isAppRunning() {
                _ = await spotifyAppleScript.pause()
            }
            return
        }

        if spotifyAppleScript.isAppRunning() {
            _ = await spotifyAppleScript.pause()
        } else {
            mediaController.pause()
        }
    }

    private func isCurrentTrack(_ generation: UInt64) -> Bool {
        generation == trackMetadataGeneration
    }

    private func isCurrentSpotifyTrack(_ generation: UInt64) -> Bool {
        isSpotifySourceSelected && generation == trackMetadataGeneration
    }

    private func beginSpotifyPlayStateReconcile(target: Bool, duration: TimeInterval = 3.0) {
        spotifyPlayStateReconcileTarget = target
        spotifyPlayStateReconcileUntil = Date().addingTimeInterval(duration)
    }

    func nextTrack() async {
        beginPlayStateHold(preferPlaying: true, duration: 1.2)
        if isSpotifySourceSelected {
            if await skipSpotifyViaConnectIfPossible(direction: .next) { return }
        }
        mediaController.nextTrack()
    }

    func previousTrack() async {
        beginPlayStateHold(preferPlaying: true, duration: 1.2)
        if isSpotifySourceSelected {
            if await skipSpotifyViaConnectIfPossible(direction: .previous) { return }
        }
        mediaController.previousTrack()
    }

    private enum SpotifySkipDirection { case next, previous }

    @discardableResult
    private func skipSpotifyViaConnectIfPossible(direction: SpotifySkipDirection) async -> Bool {
        guard spotifyPrivateAPI.isLoggedIn, isSpotifySourceSelected else { return false }

        let connectOK: Bool
        switch direction {
        case .next:
            connectOK = await spotifyPrivateAPI.connectSkipNext()
        case .previous:
            connectOK = await spotifyPrivateAPI.connectSkipPrevious()
        }
        if connectOK { return true }

        if spotifyAppleScript.isAppRunning() {
            switch direction {
            case .next:
                return await spotifyAppleScript.nextTrack()
            case .previous:
                return await spotifyAppleScript.previousTrack()
            }
        }
        return false
    }

    func seek(to seconds: Double) async {
        let clamped = max(0.0, totalDuration > 0 ? min(seconds, totalDuration) : seconds)

        if isSpotifySourceSelected {
            if spotifyPrivateAPI.isLoggedIn {
                let ok = await spotifyPrivateAPI.connectSeek(to: clamped)
                if !ok && spotifyAppleScript.isAppRunning() {
                    _ = await spotifyAppleScript.seek(to: clamped)
                }
                applyOptimisticSeek(to: clamped)
                return
            } else if spotifyAppleScript.isAppRunning() {
                _ = await spotifyAppleScript.seek(to: clamped)
                applyOptimisticSeek(to: clamped)
                return
            }
        }

        mediaController.setTime(seconds: clamped)
        applyOptimisticSeek(to: clamped)
    }

    func seek(by seconds: TimeInterval) async {
        let newTime = max(0.0, min(currentElapsedTime + seconds, max(totalDuration, currentElapsedTime + seconds)))
        await seek(to: newTime)
    }

    var isSpotifyLiveSourceSelected: Bool {
        currentSourceKey == spotifyLiveSourceKey
    }

    private var isSpotifyDisplayedInUI: Bool {
        if currentSourceKey == spotifyLiveSourceKey { return true }
        if currentSourceKey?.hasPrefix("com.spotify.client") == true { return true }
        if currentSourceKey == nil, lastKnownBundleID == "com.spotify.client" { return true }
        return false
    }

    var isSpotifySourceActive: Bool {
        isSpotifyDisplayedInUI && lastKnownBundleID != "com.apple.Music"
    }

    var isSpotifyPausedWithNoSystemMediaPlaying: Bool {
        guard isSpotifySourceActive || isSpotifyLiveSourceSelected else { return false }
        guard !isPlaying else { return false }
        return !activeMediaSources.values.contains {
            resolvedIsPlaying(from: $0.payload) == true
        }
    }

    private func clearSpotifyTransientUIState() {
        nativeQueue = []
        nowPlayingTrack = nil
        appleMusicNextTrack = nil
    }

    private var shouldSurfaceSpotifyConnectPlayback: Bool {
        guard isSpotifySourceSelected else { return false }
        if isSpotifyLiveSourceSelected { return true }
        if spotifyPrivateAPI.isControllingConnectPlayback { return true }
        return shouldPreferSpotifyPrivateNowPlaying
    }

    var isSpotifySourceSelected: Bool {
        guard let key = currentSourceKey else { return false }
        return isSpotifySourceKey(key)
    }

    private var shouldPreferSpotifyPrivateNowPlaying: Bool {
        guard spotifyPrivateAPI.isLoggedIn else { return false }
        guard isSpotifySourceSelected else { return false }
        return privateNowPlayingHasIdentity
    }

    private var privateNowPlayingHasIdentity: Bool {
        spotifyPrivateAPI.playerState?.track?.metadata?.title.isBlank == false
    }

    private var prefersNativeSpotifyMediaRemote: Bool {
        if isSpotifyLiveSourceSelected { return false }
        if spotifyPrivateAPI.isControllingConnectPlayback { return false }
        if shouldPreferSpotifyPrivateNowPlaying { return false }
        if lastKnownBundleID == "com.spotify.client" { return true }
        if currentSourceKey?.hasPrefix("com.spotify.client") == true { return true }
        return false
    }

    private func scheduleSpotifyConnectPlaybackSync(force: Bool = false, playStateOnly: Bool = false) {
        guard spotifyPrivateAPI.isLoggedIn, isSpotifySourceSelected else { return }
        if !force,
           playStateOnly,
           spotifyPrivateAPI.webSocketManager?.hasActiveConnection == true {
            return
        }
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

    private func syncSpotifyPlayState(mediaRemoteHint: Bool? = nil, forceConnectRefresh: Bool = false) {
        guard isSpotifySourceSelected else {
            if let mediaRemoteHint { applyPlayingState(mediaRemoteHint) }
            return
        }

        let preferConnectPlayback = spotifyPrivateAPI.isLoggedIn
            && spotifyPrivateAPI.playerState != nil

        if preferConnectPlayback, let state = spotifyPrivateAPI.playerState {
            let connectPlaying = state.isActivelyPlaying
            if let hint = mediaRemoteHint, hint == true, connectPlaying == false {
                applyPlayingState(true)
                scheduleSpotifyConnectPlaybackSync(force: true, playStateOnly: true)
                return
            }
            applyPlayingState(connectPlaying, fromConnect: true)
            applySpotifyPlayerTiming(state)
            let mismatch = mediaRemoteHint != nil && mediaRemoteHint != connectPlaying
            if forceConnectRefresh || mismatch {
                scheduleSpotifyConnectPlaybackSync(force: true, playStateOnly: true)
            }
            return
        }

        if prefersNativeSpotifyMediaRemote {
            if let mediaRemoteHint { applyPlayingState(mediaRemoteHint) }
            if spotifyPrivateAPI.isLoggedIn {
                scheduleSpotifyConnectPlaybackSync(force: forceConnectRefresh, playStateOnly: true)
            }
            return
        }

        guard spotifyPrivateAPI.isLoggedIn else {
            if let mediaRemoteHint { applyPlayingState(mediaRemoteHint) }
            return
        }

        if let mediaRemoteHint {
            applyPlayingState(mediaRemoteHint)
        }
        scheduleSpotifyConnectPlaybackSync(force: true, playStateOnly: true)
    }

    private func backfillSpotifyMetadataIfNeeded() async {
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn, needsSpotifyHeavyMetadata else { return }
        guard let uri = uri ?? spotifyPrivateAPI.playerState?.track?.uri,
              uri.contains("spotify:track:") else { return }
        await scheduleSpotifyAccessoryHydration(uri: uri, generation: trackMetadataGeneration)
    }

    private func scheduleSpotifyAccessoryHydration(uri: String, trackId: String? = nil, generation: UInt64) async {
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn else { return }
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

    private func fillMissingSpotifyIdentityIfNeeded(uri: String, generation: UInt64) async {
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn else { return }
        guard isCurrentTrack(generation) else { return }
        guard missingSpotifyIdentityFields else { return }
        let id = uri.replacingOccurrences(of: "spotify:track:", with: "")
        guard !id.isEmpty, !id.contains(":") else { return }

        let details = await spotifyPrivateAPI.fetchTrackDetails(trackId: id)
        guard isCurrentSpotifyTrack(generation) else { return }
        guard let details else { return }

        if artist.isBlank {
            let names = ((details.artists?.items ?? []) + (details.otherArtists?.items ?? []))
                .map(\.profile.name)
                .filter { !$0.isEmpty }
            if !names.isEmpty { artist = names.joined(separator: ", ") }
        }
        if album.isBlank, let albumName = details.albumOfTrack?.name, !albumName.isEmpty {
            album = albumName
        }
        if artwork == nil,
           let best = details.albumOfTrack?.coverArt.sources.max(by: { ($0.width ?? 0) < ($1.width ?? 0) }),
           let urlString = best.url,
           let url = URL(string: urlString) {
            artworkURL = url
            let token = "details-\(url.absoluteString.hashValue)"
            currentTrackArtworkToken = token
            await loadRemoteArtwork(from: url, expectedToken: token)
        }

        let liked = await spotifyPrivateAPI.isTrackLiked(uri: uri)
        guard isCurrentSpotifyTrack(generation) else { return }
        isLiked = liked
    }

    private var missingSpotifyIdentityFields: Bool {
        artist.isBlank || album.isBlank || artwork == nil
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
        guard !hasNativeSpotifyMediaSource(in: clients) else { return false }
        return true
    }

    private func bundleID(fromSourceKey key: String) -> String? {
        if key == spotifyLiveSourceKey || key.contains("spotify-live") {
            return "com.spotify.client"
        }
        if key.contains("."), !key.contains(":") {
            return key
        }
        return key.split(separator: ":").first.map(String.init)
    }

    private func isSourceVisible(_ key: String) -> Bool {
        settingsModel.settings.isMediaAppVisible(bundleID: bundleID(fromSourceKey: key))
    }

    private func isSystemSourceAlive(key: String, track: TrackInfo?) -> Bool {
        guard !isSpotifySourceKey(key) else { return false }
        guard isSourceVisible(key) else { return false }

        guard let bundle = bundleID(fromSourceKey: key), !bundle.isEmpty else { return false }

        if !RunningApps.shared.isRunning(bundle) {
            let matchesHelper = RunningApps.shared.containsBundleID { appBundle in
                MediaApplicationIdentity.canonicalBundleID(appBundle) == bundle
            }
            guard matchesHelper else { return false }
        }

        guard let payload = track?.payload else { return false }
        return !payload.title.isBlank
    }

    private func mergedSourcesWithSpotifyLive(_ clients: [String: TrackInfo]) -> [String: TrackInfo] {
        var merged: [String: TrackInfo] = [:]

        for (key, track) in clients {
            guard isSourceVisible(key) else { continue }
            if isSystemSourceAlive(key: key, track: track) || isSpotifySourceKey(key) {
                merged[key] = track
            }
        }

        if shouldInjectSpotifySourceTab(into: merged),
           settingsModel.settings.isMediaAppVisible(bundleID: "com.spotify.client"),
           let spotifyLive = buildSpotifyLiveTrackInfo() {
            merged[spotifyLiveSourceKey] = spotifyLive
        }

        return merged
    }

    private func sourceSignature(for sources: [String: TrackInfo]) -> Int {
        var combined = 0
        for (key, track) in sources {
            var hasher = Hasher()
            hasher.combine(key)
            hasher.combine(track.payload.title)
            hasher.combine(track.payload.artist)
            hasher.combine(track.payload.album)
            combined ^= hasher.finalize()
        }
        return combined
    }

    private func publishMergedSources(_ merged: [String: TrackInfo], reselect: Bool) {
        let signature = sourceSignature(for: merged)
        let keysChanged = merged.count != activeMediaSources.count
            || merged.keys.contains { activeMediaSources[$0] == nil }
        if signature != lastPublishedSourceSignature || keysChanged {
            lastPublishedSourceSignature = signature
            activeMediaSources = merged
            if reselect {
                evaluateAutoSourceSelection(in: merged)
            }
        } else {
            if merged != activeMediaSources {
                activeMediaSources = merged
            } else if let live = merged[spotifyLiveSourceKey],
                      activeMediaSources[spotifyLiveSourceKey]?.payload != live.payload {
                var next = activeMediaSources
                next[spotifyLiveSourceKey] = live
                activeMediaSources = next
            }
        }
    }

    private func preferredSourceKey(in sources: [String: TrackInfo]) -> String? {
        guard !sources.isEmpty else { return nil }

        if sourcePinnedByUser,
           let current = currentSourceKey,
           sources[current] != nil {
            return current
        }

        let playingKeys = sources.compactMap { resolvedIsPlaying(from: $0.value.payload) == true ? $0.key : nil }
        let pool = (playingKeys.isEmpty ? Array(sources.keys) : playingKeys).sorted()

        let preferredKey: String?
        switch settingsModel.settings.mediaSource {
        case .system:
            preferredKey = pool.first(where: { !isSpotifySourceKey($0) })
                ?? pool.first(where: isSpotifySourceKey)
        case .spotify:
            preferredKey = pool.first(where: isSpotifySourceKey)
                ?? pool.first(where: { !isSpotifySourceKey($0) })
        case .appleMusic:
            preferredKey = pool.first(where: isAppleMusicSourceKey)
                ?? pool.first(where: { !isSpotifySourceKey($0) })
                ?? pool.first(where: isSpotifySourceKey)
        }

        if let preferredKey { return preferredKey }
        if let current = currentSourceKey, sources[current] != nil { return current }
        return sources.keys.min()
    }

    private func evaluateAutoSourceSelection(in sources: [String: TrackInfo]) {
        if sourcePinnedByUser,
           let current = currentSourceKey,
           sources[current] != nil {
            return
        }

        if sourcePinnedByUser {
            sourcePinnedByUser = false
        }

        guard let preferred = preferredSourceKey(in: sources) else {
            if currentSourceKey != nil || title != nil {
                clearPlayerState()
            }
            return
        }

        if preferred != currentSourceKey {
            selectSource(key: preferred)
        }
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

        let uriForScript = trackUri.isEmpty ? (contextUri ?? "") : trackUri
        guard !uriForScript.isEmpty else {
            return .failure(reason: "Nothing to play.")
        }
        if !spotifyAppleScript.isAppRunning() {
            await spotifyAppleScript.launchAndPlay()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if spotifyPrivateAPI.isLoggedIn {
                let retry = await spotifyPrivateAPI.connectPlay(
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

    // MARK: - Rating & Mode Actions

    func toggleLike() async {
        let newLikedState = !self.isLiked
        self.isLiked = newLikedState
        var success = false
        if self.lastKnownBundleID == "com.apple.Music" {
            appleMusic.setLiked(isLiked: newLikedState)
            Task { [weak self] in
                guard let self else { return }
                if let songID = await appleMusicPrivateAPI.currentTrackSongID(),
                   appleMusicPrivateAPI.isLoggedIn {
                    _ = await appleMusicPrivateAPI.setFavorite(songID: songID, favorite: newLikedState)
                }
            }
            success = true
        } else if isSpotifySourceSelected {
            let trackURI: String? = {
                if let uri, uri.contains("spotify:track:") { return uri }
                if let trackID, !trackID.isEmpty { return "spotify:track:\(trackID)" }
                return nowPlayingTrack?.uri ?? spotifyPrivateAPI.playerState?.track?.uri
            }()

            if let trackURI, trackURI.contains("spotify:track:") {
                if spotifyPrivateAPI.isLoggedIn {
                    success = newLikedState
                        ? await spotifyPrivateAPI.likeTrack(trackURI: trackURI)
                        : await spotifyPrivateAPI.unlikeTrack(trackURI: trackURI)
                } else if spotifyOfficialAPI.isAuthenticated {
                    let id = trackURI.replacingOccurrences(of: "spotify:track:", with: "")
                    success = newLikedState
                        ? await spotifyOfficialAPI.likeTrack(id: id)
                        : await spotifyOfficialAPI.unlikeTrack(id: id)
                }
            }
        }
        if !success { self.isLiked = !newLikedState }
    }

    func toggleShuffle() async {
        if isSpotifySourceSelected {
            await cycleShuffleMode()
        } else {
            mediaController.toggleShuffle()
        }
    }

    private func cycleShuffleMode() async {
        let onPlaylistContext: Bool = {
            guard lastKnownBundleID == "com.spotify.client",
                  spotifyPrivateAPI.isLoggedIn,
                  let contextURI = spotifyPrivateAPI.currentContextURI else { return false }
            return contextURI.contains(":playlist:")
        }()

        if spotifyPrivateAPI.isSmartShuffleActive {
            await MainActor.run {
                self.shuffleState = false
                self.spotifyPrivateAPI.isSmartShuffleActive = false
            }
            await applyPlainShuffle(enabled: false)
            return
        }

        if shuffleState {
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
        if !isSpotifySourceSelected {
            mediaController.toggleRepeat()
            return
        }
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

    private var appURLCache: [String: URL?] = [:]
    private var appIconCache: [String: NSImage] = [:]

    private func appURL(for bundleID: String) -> URL? {
        if let cached = appURLCache[bundleID] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        appURLCache[bundleID] = url
        return url
    }

    private func cachedAppIcon(for bundleID: String) -> NSImage? {
        if let cached = appIconCache[bundleID] { return cached }
        guard let url = appURL(for: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIconCache[bundleID] = icon
        return icon
    }

    func appName(for bundleID: String?) -> String {
        guard let bundleID = bundleID else { return "Unknown" }
        if let url = appURL(for: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }

    private func isSpotifySourceKey(_ key: String) -> Bool {
        key == spotifyLiveSourceKey || key.hasPrefix("com.spotify.client")
    }

    private func isAppleMusicSourceKey(_ key: String) -> Bool {
        key.hasPrefix("com.apple.Music")
    }

    private func clearSpotifyTrackAccessories() {
        spotifyPrivateAPI.nowPlayingArtist = nil
        spotifyPrivateAPI.relatedTracks = []
        spotifyPrivateAPI.similarAlbums = []
        spotifyPrivateAPI.artistConcerts = []
        spotifyPrivateAPI.trackArtistCredits = []
        spotifyPrivateAPI.popularReleases = []
        spotifyPrivateAPI.currentCanvas = nil

        fetchedSpotifyPopularity = nil
        popularity = nil
        playCount = nil
        playCountValue = nil
    }

    private func clearPublishedSpotifyIdentityForSystemSource() {
        clearSpotifyTransientUIState()
        uri = nil
        trackID = nil
        lastConnectTrackURI = nil
        lastHandledTrackKey = nil
        trackMetadataGeneration &+= 1
        resetLyricsState()
        clearSpotifyTrackAccessories()
    }

    func selectSource(key: String, userInitiated: Bool = false, payload: TrackInfo.Payload? = nil) {
        if userInitiated {
            sourcePinnedByUser = true
        }
        let switching = key != currentSourceKey
        let wasSpotify = currentSourceKey.map(isSpotifySourceKey) ?? false
        let isNowSpotify = isSpotifySourceKey(key)
        currentSourceKey = key

        if switching {
            if !(wasSpotify && isNowSpotify) {
                lastTrackIdentity = nil
                lastMediaFingerprint = nil
                lastHandledTrackKey = nil
                currentTrackArtworkToken = "source-switch-\(key)-\(UUID().uuidString)"
                if !isNowSpotify {
                    clearPublishedSpotifyIdentityForSystemSource()
                    if let bundle = key.split(separator: ":").first.map(String.init) {
                        lastKnownBundleID = MediaApplicationIdentity.canonicalBundleID(bundle) ?? bundle
                        fetchAppIcon(for: lastKnownBundleID ?? bundle)
                    }
                }
            } else {
                currentTrackArtworkToken = "source-switch-spotify-\(UUID().uuidString)"
            }
        }

        if key == spotifyLiveSourceKey || key.contains("spotify-live") {
            applySpotifyLiveUIFromPlayerState(forceArtwork: true)
            return
        }

        if key.hasPrefix("com.spotify.client"), spotifyPrivateAPI.isLoggedIn, !prefersNativeSpotifyMediaRemote {
            scheduleSpotifyConnectPlaybackSync(force: true)
        }

        let resolvedPayload = payload ?? activeMediaSources[key]?.payload
        if let resolvedPayload {
            applyTrackPayload(resolvedPayload, sourceKey: key)
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
    }

    private func applySpotifyLiveUIFromPlayerState(forceArtwork: Bool) {
        lastKnownBundleID = "com.spotify.client"
        fetchAppIcon(for: "com.spotify.client")

        guard let state = spotifyPrivateAPI.playerState else {
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
                    let token = "live-\(imageURL.absoluteString.hashValue)-\(UUID().uuidString.prefix(6))"
                    currentTrackArtworkToken = token
                    Task {
                        await loadRemoteArtwork(from: imageURL, expectedToken: token)
                    }
                } else {
                    refreshArtworkColorExtractionIfNeeded()
                }
            } else if forceArtwork {
                artwork = nil
                artworkURL = nil
                currentTrackArtworkToken = "live-missing-\(track.uri)"
            }
        }
        applySpotifyPlayerTiming(state)
        publishPlaybackTime(force: true, includeProgressUI: true)
    }

    private func ensureNextSongAvailableIfNeeded(force: Bool = false) async {
        if lastKnownBundleID == "com.apple.Music" {
            guard settingsModel.settings.spotifyShowNextSong else { return }
            if force || appleMusicNextTrack == nil {
                let queue = await appleMusic.fetchUpNextTracks()
                appleMusicNextTrack = queue.first
            }
            return
        }

        guard settingsModel.settings.spotifyShowNextSong else { return }
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn else { return }

        let connectNextUIDs = spotifyPrivateAPI.playerState?.nextTracks?
            .filter { !($0.uri.contains("spotify:delimiter") || ($0.metadata?.hidden == "true")) }
            .map(\.uid) ?? []
        let localNextUIDs = nativeQueue.map(\.uid)

        let needsFetch: Bool = {
            if force {
                if !connectNextUIDs.isEmpty,
                   localNextUIDs == connectNextUIDs,
                   let next = nativeQueue.first,
                   next.metadata?.title.isBlank == false {
                    return false
                }
                return true
            }
            guard let next = nativeQueue.first else { return true }
            if next.metadata?.title.isBlank ?? true { return true }
            if !connectNextUIDs.isEmpty, localNextUIDs != connectNextUIDs { return true }
            return false
        }()
        guard needsFetch else { return }
        if !force {
            guard Date().timeIntervalSince(lastNextSongFetchAttempt) > 8 else { return }
        } else {
            guard Date().timeIntervalSince(lastNextSongFetchAttempt) > 1.2 else { return }
        }
        lastNextSongFetchAttempt = Date()
        await spotifyPrivateAPI.refreshQueueForUI()
    }

    private func loadRemoteArtwork(from url: URL, expectedToken: String) async {
        if artworkURL == url, artwork != nil, currentTrackArtworkToken == expectedToken {
            return
        }
        let image = await FileImageCache.shared.image(for: url)
        guard let image else { return }

        await MainActor.run {
            guard self.currentTrackArtworkToken == expectedToken || self.artworkURL == url else { return }
            if self.artwork !== image {
                self.artwork = image
                self.refreshArtworkColorExtractionIfNeeded()
            }
        }
    }

    private func setupHandlers() {
        mediaController.onActiveClientsChanged = { [weak self] clients in
            Task { @MainActor in
                guard let self = self else { return }
                let mergedClients = self.mergedSourcesWithSpotifyLive(clients)
                self.publishMergedSources(mergedClients, reselect: true)

                guard let key = self.currentSourceKey else { return }
                guard let track = mergedClients[key] else {
                    if key != self.spotifyLiveSourceKey {
                        self.evaluateAutoSourceSelection(in: mergedClients)
                    }
                    return
                }

                if key == self.spotifyLiveSourceKey { return }

                if self.isStaleSpotifyMediaRemote(track.payload) {
                    self.applyPlaybackRefresh(track.payload)
                } else if self.hasMediaChanged(track.payload) {
                    self.applyTrackPayload(track.payload, sourceKey: key)
                } else if let payloadArtwork = track.payload.artwork, payloadArtwork !== self.artwork {
                    self.applyTrackPayload(track.payload, sourceKey: key)
                } else {
                    self.applyPlaybackRefresh(track.payload)
                }
            }
        }

        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor in
                guard let self = self, let track = trackInfo else { return }
                let bundle = MediaApplicationIdentity.canonicalBundleID(track.payload.bundleIdentifier) ?? track.payload.bundleIdentifier ?? "unknown"
                guard self.settingsModel.settings.isMediaAppVisible(bundleID: bundle) else { return }
                let newKey = bundle

                guard self.currentSourceKey == newKey else { return }

                if self.isStaleSpotifyMediaRemote(track.payload) {
                    self.applyPlaybackRefresh(track.payload)
                } else if self.hasMediaChanged(track.payload) {
                    self.applyTrackPayload(track.payload, sourceKey: newKey)
                } else {
                    self.applyPlaybackRefresh(track.payload)
                    if let payloadArtwork = track.payload.artwork, payloadArtwork !== self.artwork {
                        self.applyTrackPayload(track.payload, sourceKey: newKey)
                    }
                }
            }
        }

        mediaController.onListenerTerminated = { [weak self] in
            print("[MusicManager] Native media stream lost. Restarting.")
            self?.mediaController.restartListeningIfNeeded()
        }
        mediaController.onDecodingError = { error, _ in print("[MusicManager] Error decoding system media: \(error)") }
    }

    private func refreshSpotifyLiveSource() {
        let systemClients = mediaController.activeClients
        let merged = mergedSourcesWithSpotifyLive(systemClients)
        publishMergedSources(merged, reselect: false)
    }

    private func rebindToBestSystemMediaSource(forceReapply: Bool) {
        sourcePinnedByUser = false
        let merged = activeMediaSources.isEmpty
            ? mergedSourcesWithSpotifyLive(mediaController.activeClients)
            : activeMediaSources
        if activeMediaSources.isEmpty {
            publishMergedSources(merged, reselect: false)
        }

        guard let preferred = preferredSourceKey(in: merged) else {
            clearPlayerState()
            return
        }
        selectSource(key: preferred)

        guard forceReapply,
              let key = currentSourceKey,
              key != spotifyLiveSourceKey,
              let track = merged[key] else { return }
        lastTrackIdentity = nil
        lastMediaFingerprint = nil
        applyTrackPayload(track.payload, sourceKey: key)
    }

    private func buildSpotifyLiveTrackInfo() -> TrackInfo? {
        guard spotifyPrivateAPI.isLoggedIn else { return nil }

        guard let state = spotifyPrivateAPI.playerState, let track = state.track else {
            return TrackInfo(payload: TrackInfo.Payload(
                bundleIdentifier: "com.spotify.client",
                title: "Spotify",
                artist: "Not playing",
                isPlaying: false,
                playbackRate: 0,
                isMusicApp: true,
                supportsIsLiked: true,
                contentItemIdentifier: "spotify-live-idle",
                uniqueIdentifier: "spotify-live-idle",
                mediaType: "music"
            ))
        }

        return TrackInfo(payload: TrackInfo.Payload(
            bundleIdentifier: "com.spotify.client",
            title: track.metadata?.title,
            artist: track.metadata?.artistName,
            album: track.metadata?.albumTitle,
            isPlaying: state.isActivelyPlaying,
            durationMicros: state.duration.map { Int64($0) * 1000 },
            currentElapsedTime: state.realtimePositionMilliseconds().map { TimeInterval($0) / 1000.0 },
            playbackRate: state.isActivelyPlaying ? 1 : 0,
            timestampEpochMicros: state.timestamp.map { $0 * 1000 },
            isMusicApp: true,
            supportsIsLiked: true,
            contentItemIdentifier: track.uri,
            uniqueIdentifier: track.uid,
            mediaType: "music"
        ))
    }

    private func applySpotifyPlayerTiming(_ state: PlayerState) {
        let playing = heldOrReportedPlaying(state.isActivelyPlaying)
        let rate = playing ? 1.0 : 0.0

        let newAnchor: PlaybackTimingAnchor?
        if let timestamp = state.timestamp, let ms = state.positionAsOfTimestamp {
            newAnchor = PlaybackTimingAnchor(
                elapsedAtSample: TimeInterval(ms) / 1000.0,
                sampleEpochTime: TimeInterval(timestamp) / 1000.0,
                rate: rate
            )
        } else if let ms = state.positionAsOfTimestamp ?? state.realtimePositionMilliseconds() {
            newAnchor = PlaybackTimingAnchor(
                elapsedAtSample: TimeInterval(ms) / 1000.0,
                sampleEpochTime: Date().timeIntervalSince1970,
                rate: rate
            )
        } else {
            newAnchor = nil
        }

        var changed = false
        if let newAnchor, newAnchor != playbackTimingAnchor {
            playbackTimingAnchor = newAnchor
            changed = true
        }
        if let durationMs = state.duration, durationMs > 0 {
            let duration = TimeInterval(durationMs) / 1000.0
            if duration != currentTrackDuration || duration != totalDuration {
                currentTrackDuration = duration
                totalDuration = duration
                changed = true
            }
        }

        guard changed else { return }
        refreshTimers()
        publishPlaybackTime(force: true, includeProgressUI: true)
    }

    private func handleSpotifyTrackAdvanced(to track: PlayerState.Track?) {
        guard isSpotifySourceSelected else { return }
        trackMetadataGeneration &+= 1
        let generation = trackMetadataGeneration

        resetLyricsState()
        clearSpotifyTrackAccessories()
        isLiked = false

        if let track,
           let title = track.metadata?.title,
           let artist = track.metadata?.artistName {
            lastHandledTrackKey = "com.spotify.client|\(track.uri)|\(title)|\(artist)".lowercased()
        } else {
            lastHandledTrackKey = nil
        }

        if let track, let head = nativeQueue.first, head.uri == track.uri || head.uid == track.uid {
            var advanced = nativeQueue
            advanced.removeFirst()
            nativeQueue = advanced
            spotifyPrivateAPI.nativeQueue = advanced
        }

        guard let track else {
            lastNextSongFetchAttempt = .distantPast
            Task { await ensureNextSongAvailableIfNeeded(force: true) }
            return
        }

        currentTrackArtworkToken = track.uri
        triggerQuickPeek()
        trackDidChange.send()
        lastTrackChangeDate = Date()

        let artistURI = track.metadata?.artistUri
        let trackURI = track.uri

        if needsSpotifyPlayerEnrichment {
            Task {
                await refreshSpotifyExtendedTrackData(
                    trackURI: trackURI,
                    artistURI: artistURI,
                    generation: generation,
                    force: true
                )
            }
        } else if needsLyricsUpdates || needsSpotifyHeavyMetadata {
            Task {
                await scheduleSpotifyAccessoryHydration(uri: trackURI, generation: generation)
            }
        }

        if nativeQueue.first?.metadata?.title.isBlank ?? true {
            lastNextSongFetchAttempt = .distantPast
            Task { await ensureNextSongAvailableIfNeeded(force: true) }
        }
    }

    func ensureSpotifyPlayerExtrasLoaded(force: Bool = false) async {
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn else { return }
        guard force || needsSpotifyPlayerEnrichment else { return }

        let trackURI = uri
            ?? nowPlayingTrack?.uri
            ?? spotifyPrivateAPI.playerState?.track?.uri
        guard let trackURI, trackURI.contains("spotify:track:") else { return }

        let artistURI = nowPlayingTrack?.metadata?.artistUri
            ?? spotifyPrivateAPI.playerState?.track?.metadata?.artistUri
            ?? spotifyPrivateAPI.nowPlayingArtist?.uri
            ?? spotifyPrivateAPI.trackArtistCredits.first?.uri

        await refreshSpotifyExtendedTrackData(
            trackURI: trackURI,
            artistURI: artistURI,
            generation: trackMetadataGeneration,
            force: force
        )
    }

    private func applyTrackPayload(_ payload: TrackInfo.Payload, sourceKey: String) {
        if let current = currentSourceKey, current != sourceKey { return }
        self.latestTrackPayload = payload

        guard let rawTitle = payload.title, !rawTitle.isEmpty else {
            applyPlaybackRefresh(payload)
            if self.title == nil { self.clearPlayerState() }
            return
        }

        let sourceBundleID = MediaApplicationIdentity.canonicalBundleID(payload.bundleIdentifier) ?? "N/A"
        let isSpotify = isSpotifySourceKey(sourceKey) || sourceBundleID == "com.spotify.client"
        let switchingAwayFromSpotify = lastKnownBundleID == "com.spotify.client" && !isSpotify

        if sourceBundleID != self.lastKnownBundleID {
            self.lastKnownBundleID = sourceBundleID
            self.fetchAppIcon(for: sourceBundleID)
            self.updateDevicePolling()
        }

        if switchingAwayFromSpotify {
            clearPublishedSpotifyIdentityForSystemSource()
        }

        let trackIdentity = self.trackIdentity(for: payload)
        let hasTrackChanged = hasMediaChanged(payload) || switchingAwayFromSpotify

        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String? = trimmedTitle.isEmpty ? rawTitle : trimmedTitle
        let resolvedArtist = payload.artist.trimmedOrNil
        let resolvedAlbum = payload.album.trimmedOrNil

        if self.title != resolvedTitle { self.title = resolvedTitle }
        if self.artist != resolvedArtist { self.artist = resolvedArtist }
        if self.album != resolvedAlbum { self.album = resolvedAlbum }

        if hasTrackChanged {
            self.lastTrackIdentity = trackIdentity
            let fingerprint = mediaFingerprint(for: payload)
            self.lastMediaFingerprint = fingerprint.isEmpty ? nil : fingerprint
            self.currentTrackArtworkToken = trackIdentity
            self.resetLyricsState()
            self.triggerQuickPeek()
            self.lastTrackChangeDate = Date()

            Task { await self.ensureLyricsForCurrentTrack() }
            self.trackDidChange.send()
        }

        if let newArtwork = payload.artwork {
            self.applyArtwork(newArtwork, trackIdentity: trackIdentity)
        } else if switchingAwayFromSpotify {
            self.artwork = nil
            self.artworkURL = nil
        }

        if let newIsPlaying = resolvedIsPlaying(from: payload) {
            applyPlayingState(newIsPlaying)
        }

        let newDuration = TimeInterval(payload.durationMicros ?? 0) / 1_000_000
        if abs(self.totalDuration - newDuration) > 0.5 {
            self.totalDuration = newDuration
        }
        self.currentTrackDuration = newDuration

        if !applyConnectTimingIfPreferred() {
            syncPlaybackTiming(from: payload, trackChanged: hasTrackChanged)
        }
    }

    private func applyPlaybackRefresh(_ payload: TrackInfo.Payload) {
        latestTrackPayload = payload

        if MediaApplicationIdentity.canonicalBundleID(payload.bundleIdentifier) == "com.spotify.client", spotifyPrivateAPI.isLoggedIn {
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

    @discardableResult
    private func applyConnectTimingIfPreferred() -> Bool {
        guard spotifyPrivateAPI.isLoggedIn,
              isSpotifySourceSelected,
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

    // MARK: - Logic & Helpers

    private func scheduleTrackIdentifierRefresh() {
        trackIdentifierRefreshTask?.cancel()
        trackIdentifierRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await self.handleTrackIdentifierChange()
        }
    }

    private func handleTrackIdentifierChange() async {
        if fetchedSpotifyPopularity != nil { fetchedSpotifyPopularity = nil }
        guard let currentTitle = self.title, !currentTitle.isEmpty else { return }

        let trackKey = "\(lastKnownBundleID ?? "")|\(uri ?? "")|\(currentTitle)|\(artist ?? "")".lowercased()
        guard trackKey != lastHandledTrackKey else { return }
        lastHandledTrackKey = trackKey

        trackMetadataGeneration &+= 1
        let generation = trackMetadataGeneration

        self.popularity = nil; self.playCount = nil; self.playCountValue = nil; self.isLiked = false
        self.applePlayCount = nil; self.applePopularity = nil; self.appleSuggestedTracks = []

        if self.lastKnownBundleID == "com.apple.Music" {
            guard isCurrentTrack(generation) else { return }
            self.isLiked = appleMusic.isTrackLiked()
            self.shuffleState = appleMusic.getShuffleState()
            self.repeatState = appleMusic.getRepeatState()
            await enrichAppleMusicTrackStats(generation: generation)
            guard isCurrentTrack(generation) else { return }
            if needsLyricsUpdates || isDetailPlayerOpen {
                await ensureLyricsForCurrentTrack()
            }
        } else if isSpotifySourceSelected && self.lastKnownBundleID == "com.spotify.client" {
            if shouldPreferSpotifyPrivateNowPlaying,
               let connectTrack = spotifyPrivateAPI.playerState?.track {
                publishSpotifyMediaIdentity(from: connectTrack, forceArtwork: artwork == nil)
            }

            if let uri = self.uri, uri.contains("spotify:track:"), spotifyPrivateAPI.isLoggedIn {
                if needsSpotifyPlayerEnrichment {
                    let artistURI = self.nowPlayingTrack?.metadata?.artistUri
                        ?? self.spotifyPrivateAPI.playerState?.track?.metadata?.artistUri
                    await refreshSpotifyExtendedTrackData(
                        trackURI: uri,
                        artistURI: artistURI,
                        generation: generation,
                        force: true
                    )
                } else if needsSpotifyHeavyMetadata || needsLyricsUpdates {
                    await scheduleSpotifyAccessoryHydration(uri: uri, generation: generation)
                } else {
                    await ensureLyricsForCurrentTrack()
                }
                return
            }

            if let currentArtist = self.artist, !currentArtist.isEmpty,
               let track = await searchForTrack(title: currentTitle, artist: currentArtist) {
                guard isCurrentSpotifyTrack(generation) else { return }
                self.uri = track.uri; self.trackID = track.id; self.popularity = track.popularity
                if spotifyPrivateAPI.isLoggedIn, needsSpotifyPlayerEnrichment {
                    let artistURI = self.nowPlayingTrack?.metadata?.artistUri
                    await refreshSpotifyExtendedTrackData(
                        trackURI: track.uri,
                        artistURI: artistURI,
                        generation: generation,
                        force: true
                    )
                } else if spotifyOfficialAPI.isAuthenticated, let liked = await spotifyOfficialAPI.checkIfTrackIsLiked(id: track.id) {
                    guard isCurrentSpotifyTrack(generation) else { return }
                    self.isLiked = liked
                }
                if self.playCount == nil, let count = await PlayCountFetcher.shared.getPlayCountValue(for: track.id) {
                    guard isCurrentSpotifyTrack(generation) else { return }
                    self.playCountValue = count
                    self.playCount = PlayCountFetcher.formatPlayCount(count)
                }
            } else {
                guard isCurrentTrack(generation) else { return }
                if needsLyricsUpdates || isDetailPlayerOpen {
                    await ensureLyricsForCurrentTrack()
                }
            }
        }
    }

    private func enrichAppleMusicTrackStats(generation: UInt64) async {
        guard lastKnownBundleID == "com.apple.Music" else { return }
        guard appleMusic.isMusicKitAuthorized else { return }
        guard isCurrentTrack(generation) else { return }
        guard let songID = trackID, !songID.isEmpty else { return }

        if let artistName = self.artist, !artistName.isEmpty {
            let suggested = await appleMusic.suggestedTracks(artistName: artistName)
            guard isCurrentTrack(generation) else { return }
            self.appleSuggestedTracks = suggested
        }
    }

    private func hydrateSpotifyTrackAccessories(uri: String, trackId: String? = nil, generation: UInt64) async {
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn else { return }
        guard isCurrentTrack(generation) else { return }

        let id = trackId ?? uri.replacingOccurrences(of: "spotify:track:", with: "")
        guard !id.isEmpty, !id.contains(":") else { return }

        if self.uri != uri { self.uri = uri }
        if self.trackID != id { self.trackID = id }

        if let track = nowPlayingTrack, track.uri == uri {
            applyConnectArtworkIfNeeded(from: track, force: artwork == nil)
            guard isCurrentTrack(generation) else { return }
        }

        if missingSpotifyIdentityFields {
            await fillMissingSpotifyIdentityIfNeeded(uri: uri, generation: generation)
            guard isCurrentTrack(generation) else { return }
        }

        guard needsSpotifyHeavyMetadata else {
            let liked = await spotifyPrivateAPI.isTrackLiked(uri: uri)
            guard isCurrentSpotifyTrack(generation) else { return }
            self.isLiked = liked
            return
        }

        let details = await spotifyPrivateAPI.fetchTrackDetails(trackId: id)
        guard isCurrentSpotifyTrack(generation) else { return }
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
                guard isCurrentSpotifyTrack(generation) else { return }
            }
        }

        let liked = await spotifyPrivateAPI.isTrackLiked(uri: uri)
        guard isCurrentSpotifyTrack(generation) else { return }
        self.isLiked = liked

        if playCountValue == nil, let count = await PlayCountFetcher.shared.getPlayCountValue(for: id) {
            guard isCurrentSpotifyTrack(generation) else { return }
            playCountValue = count
            playCount = PlayCountFetcher.formatPlayCount(count)
        }

        if popularity == nil, fetchedSpotifyPopularity == nil,
           let currentTitle = title, let currentArtist = artist,
           !currentTitle.isEmpty, !currentArtist.isEmpty,
           let track = await searchForTrack(title: currentTitle, artist: currentArtist) {
            guard isCurrentSpotifyTrack(generation) else { return }
            popularity = track.popularity
            fetchedSpotifyPopularity = track.popularity
        }

        guard needsLyricsUpdates else { return }

        await ensureLyricsForCurrentTrackViaSpotify(
            trackId: id,
            generation: generation
        )
    }

    private func ensureLyricsForCurrentTrackViaSpotify(trackId id: String, generation: UInt64) async {
        guard needsLyricsUpdates else { return }
        guard isCurrentSpotifyTrack(generation) else { return }
        await ensureLyricsForCurrentTrack(
            spotifyTrackID: id,
            spotifyGeneration: generation
        )
    }

    private func searchForTrack(title: String, artist: String) async -> SpotifyTrack? {
        if spotifyPrivateAPI.isLoggedIn {
            return await spotifyPrivateAPI.searchForTrack(title: title, artist: artist)
        } else if spotifyOfficialAPI.isAuthenticated {
            return await spotifyOfficialAPI.searchForTrack(title: title, artist: artist)
        } else if tidalAPI.isAuthenticated {
            return await tidalAPI.searchForTrack(title: title, artist: artist)
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

    private var lastForcedSpotifyDeviceStateRefreshAt: Date = .distantPast
    private let forcedSpotifyDeviceStateMinInterval: TimeInterval = 3.0

    func fetchActiveSpotifyDeviceState(forceRefresh: Bool = false) async -> ActiveSpotifyDeviceState? {
        var shouldForceRefresh = forceRefresh
        if shouldForceRefresh {
            let now = Date()
            if now.timeIntervalSince(lastForcedSpotifyDeviceStateRefreshAt) < forcedSpotifyDeviceStateMinInterval {
                shouldForceRefresh = false
            } else {
                lastForcedSpotifyDeviceStateRefreshAt = now
            }
        }
        if !shouldForceRefresh, let cached = getActiveCachedSpotifyDeviceState() {
            return cached
        }
        if spotifyPrivateAPI.isLoggedIn {
            try? await spotifyPrivateAPI.refreshPlayerAndDeviceState()
            return getActiveCachedSpotifyDeviceState()
        } else if isOfficialAPIAuthenticated {
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

    func getActiveCachedSpotifyDeviceState() -> ActiveSpotifyDeviceState? {
        guard spotifyPrivateAPI.isLoggedIn,
              let activeDeviceID = spotifyPrivateAPI.activePlayerDeviceID,
              let device = spotifyPrivateAPI.devices.first(where: { $0.deviceId == activeDeviceID })
        else { return nil }

        return ActiveSpotifyDeviceState(
            name: device.name,
            type: device.deviceType,
            volumePercent: device.volume.map { Int((Double($0) / 65535.0) * 100.0) },
            iconName: iconName(for: device.deviceType),
            canControlVolume: (device.capabilities.volumeSteps ?? 0) > 0
        )
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

    private var cachedOutputDevice: (device: AudioDevice?, sampledAt: Date)?

    private func currentOutputDevice() -> AudioDevice? {
        if let cached = cachedOutputDevice, Date().timeIntervalSince(cached.sampledAt) < 1.0 {
            return cached.device
        }
        let device = AudioDeviceManager.shared.getCurrentOutputDevice()
        cachedOutputDevice = (device, Date())
        return device
    }

    func currentOutputDeviceSystemImage() -> String {
        if settingsModel.settings.preferAirPlayOverSpotify,
           let device = currentOutputDevice() {
            return IconMapper.icon(for: device)
        }
        if let activeID = spotifyPrivateAPI.activePlayerDeviceID,
           let device = spotifyPrivateAPI.devices.first(where: { $0.deviceId == activeID }) {
            return iconName(for: device.deviceType)
        }
        if let device = currentOutputDevice() {
            return IconMapper.icon(for: device)
        }
        return MusicPlayerButtonType.devices.systemImage
    }

    func sourceAppIcon(for key: String) -> NSImage {
        let bundleID: String?
        if key.contains("spotify-live") || key.lowercased().contains("spotify") {
            bundleID = "com.spotify.client"
        } else if let track = activeMediaSources[key] {
            bundleID = MediaApplicationIdentity.canonicalBundleID(track.payload.bundleIdentifier)
        } else {
            bundleID = nil
        }
        if let bundleID, let icon = cachedAppIcon(for: bundleID) { return icon }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    private func syncPlaybackTiming(from payload: TrackInfo.Payload, trackChanged: Bool, publishImmediately: Bool = true) {
        let isPlayingNow = payload.isPlaying ?? isPlaying
        guard let incomingAnchor = payload.playbackTimingAnchor(isPlayingNow: isPlayingNow) else { return }

        playbackTimingAnchor = incomingAnchor

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

        if let anchor = playbackTimingAnchor {
            exactTime = anchor.elapsed(at: Date())
        } else if let payload = latestTrackPayload {
            exactTime = payload.interpolatedElapsedTime(at: Date())
        } else {
            return
        }

        let duration = totalDuration
        let clampedElapsed = duration > 0 ? max(0.0, min(duration, exactTime)) : max(0.0, exactTime)
        let progress = duration > 0 ? max(0.0, min(1.0, clampedElapsed / duration)) : 0.0

        let publishesProgress = includeProgressUI ?? (isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen || isMusicLiveActivityActive)

        if needsLyricsUpdates {
            updateCurrentLyric(for: clampedElapsed)
        }

        if !force && !publishesProgress && !needsLyricsUpdates {
            return
        }

        let elapsedThreshold = publishesProgress ? 0.05 : 1.0
        let elapsedDelta = abs(clampedElapsed - currentElapsedTime)

        if !force && elapsedDelta < elapsedThreshold {
            return
        }

        currentElapsedTime = clampedElapsed

        if publishesProgress {
            if abs(playbackProgress - progress) > 0.001 || force {
                playbackProgress = progress
            }
            playbackTimePublisher.send((elapsed: clampedElapsed, progress: progress))
        }
    }

    private func clearPlayerState() {
        self.latestTrackPayload = nil
        self.currentSourceKey = nil
        self.sourcePinnedByUser = false
        invalidateAllTimers()
        playbackTimingAnchor = nil
        lastTrackIdentity = nil
        lastMediaFingerprint = nil
        currentTrackArtworkToken = ""
        self.uri = nil; self.trackID = nil; self.popularity = nil; self.playCount = nil; self.playCountValue = nil
        self.applePlayCount = nil; self.applePopularity = nil; self.appleSuggestedTracks = []
        self.isPlaying = false; self.totalDuration = 0; self.currentElapsedTime = 0
        self.lastHandledTrackKey = nil
        self.resetLyricsState()
        if !settingsModel.settings.persistMusicWidgetWhenPaused {
            self.title = nil; self.artist = nil; self.album = nil; self.artwork = nil; self.artworkURL = nil
        }
    }

    private func refreshTimers() {
        let inputs = MusicPlaybackTickPolicy.Inputs(
            isPlaying: isPlaying,
            isDetailPlayerOpen: isDetailPlayerOpen,
            isLyricsDetailOpen: isLyricsDetailOpen,
            isDetachedLyricsOpen: isDetachedLyricsOpen,
            isMusicLiveActivityActive: isMusicLiveActivityActive,
            musicLiveActivityEnabled: settingsModel.settings.musicLiveActivityEnabled,
            showLyricsInLiveActivity: settingsModel.settings.showLyricsInLiveActivity,
            lyricsAllowedForActiveApp: ActiveAppMonitor.shared.isLyricsAllowedForActiveApp,
            hasLyrics: !lyrics.isEmpty,
            showNextSong: settingsModel.settings.spotifyShowNextSong,
            upNextSourceSupported: isSpotifySourceActive || isSpotifyLiveSourceSelected || lastKnownBundleID == "com.apple.Music"
        )
        let tickInterval = MusicPlaybackTickPolicy.interval(for: inputs)
        LyricsLog.infoOnChange(
            "playbackTick",
            "Playback tick \(tickInterval.map { "on (\($0)s)" } ?? "off"): playing=\(inputs.isPlaying) liveActivity=\(inputs.isMusicLiveActivityActive) liveActivityEnabled=\(inputs.musicLiveActivityEnabled) lyricsSetting=\(inputs.showLyricsInLiveActivity) appAllowed=\(inputs.lyricsAllowedForActiveApp) hasLyrics=\(inputs.hasLyrics) detailOpen=\(inputs.isDetailPlayerOpen || inputs.isLyricsDetailOpen || inputs.isDetachedLyricsOpen)"
        )

        guard let interval = tickInterval else {
            liveActivityTimer?.invalidate()
            liveActivityTimer = nil
            liveActivityTimerInterval = 0
            liveActivityTimerRepeats = false
            return
        }

        let needsProgressUI = inputs.isDetachedLyricsOpen
        let repeats = needsProgressUI
        let scheduledInterval: TimeInterval
        if repeats {
            scheduledInterval = interval
        } else {
            guard let nextDelay = MusicPlaybackTickPolicy.nextLiveActivityEventDelay(
                for: inputs,
                elapsed: elapsedTime(),
                lyricsElapsed: lyricsElapsedTime(),
                lyrics: lyrics,
                duration: totalDuration
            ) else {
                liveActivityTimer?.invalidate()
                liveActivityTimer = nil
                liveActivityTimerInterval = 0
                liveActivityTimerRepeats = false
                return
            }
            scheduledInterval = nextDelay
        }

        if let timer = liveActivityTimer {
            if repeats, liveActivityTimerRepeats, liveActivityTimerInterval == scheduledInterval {
                return
            }
            if !repeats, !liveActivityTimerRepeats,
               abs(timer.fireDate.timeIntervalSinceNow - scheduledInterval) < 0.1 {
                return
            }
        }

        liveActivityTimer?.invalidate()
        let timer = Timer(timeInterval: scheduledInterval, repeats: repeats) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                if !repeats {
                    self.liveActivityTimer = nil
                    self.liveActivityTimerInterval = 0
                    self.liveActivityTimerRepeats = false
                }
                self.publishPlaybackTime(includeProgressUI: true)
                if !repeats {
                    self.refreshTimers()
                }
            }
        }
        timer.tolerance = repeats ? 0.05 : 0.02
        liveActivityTimer = timer
        liveActivityTimerInterval = scheduledInterval
        liveActivityTimerRepeats = repeats
        RunLoop.main.add(timer, forMode: .common)
    }

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

    func lyricsElapsedTime(at date: Date = Date()) -> TimeInterval {
        adjustedLyricsElapsedTime(elapsedTime(at: date))
    }

    func progress(at date: Date = Date()) -> Double {
        guard totalDuration > 0 else { return 0 }
        return max(0.0, min(1.0, elapsedTime(at: date) / totalDuration))
    }

    private func invalidateAllTimers() {
        liveActivityTimer?.invalidate()
        liveActivityTimer = nil
        liveActivityTimerInterval = 0
        liveActivityTimerRepeats = false
    }

    func trimExpandedUIMemory() {
        trimLyricsCache()
        mediaController.trimArtworkCache(keeping: lastTrackIdentity)

        if !needsLyricsUpdates {
            resetLyricsState()
        }
        appIcon = nil
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
        let fingerprint = mediaFingerprint(for: payload)
        if !fingerprint.isEmpty {
            return fingerprint != (lastMediaFingerprint ?? "")
        }

        let incomingIdentity = trackIdentity(for: payload)
        if incomingIdentity == "unknown" { return false }
        return incomingIdentity != (lastTrackIdentity ?? "")
    }

    private func mediaFingerprint(for payload: TrackInfo.Payload) -> String {
        Self.mediaFingerprint(title: payload.title, artist: payload.artist)
    }

    private static func mediaFingerprint(title: String?, artist: String?) -> String {
        switch (title.trimmedOrNil, artist.trimmedOrNil) {
        case let (title?, artist?): return "\(title)|\(artist)".lowercased()
        case let (title?, nil): return title.lowercased()
        case let (nil, artist?): return artist.lowercased()
        case (nil, nil): return ""
        }
    }

    private func trackIdentity(for payload: TrackInfo.Payload) -> String {
        if let id = payload.contentItemIdentifier, !id.isEmpty { return "cid:\(id)" }
        if let id = payload.uniqueIdentifier, !id.isEmpty { return "uid:\(id)" }
        let fingerprint = mediaFingerprint(for: payload)
        return fingerprint.isEmpty ? "unknown" : "fp:\(fingerprint)"
    }

    private func applyArtwork(_ displayArtwork: NSImage, trackIdentity: String? = nil) {
        if let trackIdentity, let last = lastTrackIdentity, trackIdentity != last { return }

        if isSpotifySourceSelected && artworkURL != nil && self.artwork != nil {
            return
        }

        if self.artwork === displayArtwork { return }

        self.artwork = displayArtwork
        if !isSpotifySourceSelected {
            self.artworkURL = nil
        }
        refreshArtworkColorExtractionIfNeeded()
    }

    private func refreshArtworkColorExtractionIfNeeded() {
        artworkColorExtractionTask?.cancel()
        guard shouldExtractArtworkColors else { return }

        let currentToken = "\(currentTrackArtworkToken)-\(artwork?.hashValue ?? 0)"
        if lastExtractedArtworkToken == currentToken { return }
        lastExtractedArtworkToken = currentToken

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

    private func refreshSpotifyExtendedTrackData(
        trackURI: String,
        artistURI: String?,
        generation: UInt64? = nil,
        force: Bool = false
    ) async {
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn else { return }
        if let generation, !isCurrentTrack(generation) { return }
        let settings = settingsModel.settings

        let wantCanvas = settings.spotifyCanvasLiveVideo && (force || needsSpotifyPlayerEnrichment || isDetailPlayerOpen)
        let wantSuggested = force || settings.spotifyShowSuggestedSongs || isMusicHubOpen
        let wantArtist = force || settings.spotifyShowArtistProfile || isMusicHubOpen
        let wantConcerts = force || settings.spotifyShowConcertTickets || isMusicHubOpen
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

        var resolvedArtistURI = artistURI
        if wantArtist || wantConcerts {
            let credits = await spotifyPrivateAPI.fetchTrackArtists(for: trackURI)
            if resolvedArtistURI == nil || resolvedArtistURI?.isEmpty == true {
                resolvedArtistURI = credits.first?.uri
            }
        }

        if let resolvedArtistURI, wantConcerts || wantArtist {
            async let artistProfile: Void = {
                _ = await spotifyPrivateAPI.fetchArtistConcerts(artistURI: resolvedArtistURI, trackURI: trackURI)
            }()
            async let popular: Void = {
                if wantArtist {
                    let artistId = resolvedArtistURI.replacingOccurrences(of: "spotify:artist:", with: "")
                    _ = await spotifyPrivateAPI.fetchPopularReleases(artistId: artistId)
                }
            }()
            _ = await (artistProfile, popular)
        }
        _ = await (canvas, related, similar)
    }

    private func refreshLyricsLoadingState() {
        guard needsLyricsUpdates else {
            stopWordTimingGeneration()
            return
        }
        if lyrics.isEmpty {
            Task { await ensureLyricsForCurrentTrack() }
        } else {
            updateCurrentLyric(for: currentElapsedTime)
            refreshWordTimingGenerationState()
        }
    }

    private func ensureLyricsForCurrentTrack(
        spotifyTrackID requestedSpotifyTrackID: String? = nil,
        spotifyGeneration requestedSpotifyGeneration: UInt64? = nil
    ) async {
        guard needsLyricsUpdates else {
            LyricsLog.infoOnChange(
                "ensure",
                "Lyrics fetch skipped: not needed (detailOpen=\(isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen) lyricsSetting=\(settingsModel.settings.showLyricsInLiveActivity) liveActivityEnabled=\(settingsModel.settings.musicLiveActivityEnabled) appAllowed=\(ActiveAppMonitor.shared.isLyricsAllowedForActiveApp))"
            )
            return
        }
        guard let title = self.title.trimmedOrNil, let artist = self.artist.trimmedOrNil else {
            LyricsLog.infoOnChange("ensure", "Lyrics fetch skipped: track has no \(self.title.trimmedOrNil == nil ? "title" : "artist")")
            return
        }
        let album = self.album.trimmedOrNil ?? ""

        let cacheKey = lyricsCacheKey(title: title, artist: artist, album: album)
        if let cachedLyrics = lyricsCache[cacheKey] {
            LyricsLog.infoOnChange("ensure", "Lyrics cache hit for '\(title)' / '\(artist)': \(cachedLyrics.count) lines")
            guard !cachedLyrics.isEmpty else { return }
            replaceLyrics(cachedLyrics)
            retranslateLyricsIfNeeded()
            refreshWordTimingGenerationState()
            return
        }

        let spotifyTrackID: String? = {
            if let requestedSpotifyTrackID, !requestedSpotifyTrackID.isEmpty {
                return requestedSpotifyTrackID
            }
            guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn,
                  let trackURI = uri ?? spotifyPrivateAPI.playerState?.track?.uri,
                  trackURI.contains("spotify:track:") else {
                return nil
            }
            let id = trackURI.replacingOccurrences(of: "spotify:track:", with: "")
            return id.isEmpty ? nil : id
        }()

        let attemptKey = "\(cacheKey)|spotify:\(spotifyTrackID ?? "none")"
        if currentlyFetchingFingerprint == attemptKey || lastAttemptedLyricsFingerprint == attemptKey {
            LyricsLog.infoOnChange(
                "ensure",
                "Lyrics fetch skipped: already \(currentlyFetchingFingerprint == attemptKey ? "in flight" : "attempted") for '\(title)' / '\(artist)' (spotify fallback: \(spotifyTrackID != nil))"
            )
            return
        }

        lastAttemptedLyricsFingerprint = attemptKey
        lyricsFetchTask?.cancel()
        lyricsTranslationTask?.cancel()
        currentlyFetchingFingerprint = attemptKey
        LyricsLog.infoOnChange("ensure", "Lyrics fetch started for '\(title)' / '\(artist)' / '\(album)' (spotify fallback: \(spotifyTrackID != nil))")

        let fetchIdentity = lastTrackIdentity
        let spotifyGeneration = requestedSpotifyGeneration ?? trackMetadataGeneration
        let imageURL = artworkURL?.absoluteString
            ?? nowPlayingTrack?.metadata?.imageURL?.absoluteString
            ?? ""

        lyricsFetchTask = Task {
            defer {
                if self.currentlyFetchingFingerprint == attemptKey {
                    self.currentlyFetchingFingerprint = nil
                }
            }

            async let databaseLookup = LyricsDatabase.shared.lyrics(
                title: title,
                artist: artist,
                spotifyTrackID: spotifyTrackID
            )
            let fetchedLRCLIB = await lyricsFetcher.fetchSyncedLyrics(
                for: title,
                artist: artist,
                album: album
            )
            let databaseLyrics = await databaseLookup
            guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else {
                LyricsLog.info("Lyrics results for '\(title)' dropped: fetch cancelled or track changed")
                return
            }

            if let databaseLyrics {
                LyricsLog.info(
                    "Lyrics applied from Sapphire database for '\(title)': \(databaseLyrics.count) lines (\(databaseLyrics.filter(\.hasWordTiming).count) word-synced)"
                )
                self.replaceLyrics(databaseLyrics)
                self.lyricsCache[cacheKey] = databaseLyrics
                self.retranslateLyricsIfNeeded()
                return
            }

            let selectedLyrics: [LyricLine]
            let source: String
            if let fetchedLRCLIB {
                self.lyricsCache[cacheKey] = fetchedLRCLIB
                guard !fetchedLRCLIB.isEmpty else {
                    LyricsLog.info("LRCLIB has an empty (instrumental) document for '\(title)'; not falling back")
                    return
                }
                selectedLyrics = fetchedLRCLIB
                source = "LRCLIB"
            } else {
                let fetchedSpotify = await fetchSpotifyLyricsFallback(
                    trackID: spotifyTrackID,
                    imageURL: imageURL
                )
                guard !Task.isCancelled,
                      self.lastTrackIdentity == fetchIdentity,
                      spotifyTrackID != nil,
                      self.isSpotifySourceSelected,
                      self.trackMetadataGeneration == spotifyGeneration,
                      !fetchedSpotify.isEmpty else {
                    LyricsLog.info(
                        "No lyrics for '\(title)': LRCLIB had none, Spotify fallback \(spotifyTrackID == nil ? "unavailable (not a Spotify track)" : "returned \(fetchedSpotify.count) lines or went stale")"
                    )
                    return
                }
                selectedLyrics = fetchedSpotify
                source = "Spotify"
            }

            LyricsLog.info("Lyrics applied from \(source) for '\(title)': \(selectedLyrics.count) lines")
            self.replaceLyrics(selectedLyrics)
            self.lyricsCache[cacheKey] = selectedLyrics
            self.retranslateLyricsIfNeeded()
            self.refreshTimers()
            self.startWordTimingGenerationIfNeeded(
                lines: selectedLyrics,
                title: title,
                artist: artist,
                album: album,
                spotifyTrackID: spotifyTrackID,
                cacheKey: cacheKey
            )
        }
        await lyricsFetchTask?.value
    }

    private func startWordTimingGenerationIfNeeded(
        lines: [LyricLine],
        title: String,
        artist: String,
        album: String,
        spotifyTrackID: String?,
        cacheKey: String
    ) {
        guard settingsModel.settings.generateWordTimedLyrics else { return }
        guard needsLyricsUpdates else { return }
        guard !lines.contains(where: \.hasWordTiming) else { return }
        guard #available(macOS 26.0, *) else {
            LyricsLog.infoOnChange("generator", "Word timing generation needs macOS 26")
            return
        }
        guard isPlaying,
              let identity = lastTrackIdentity,
              let processID = latestTrackPayload?.processIdentifier, processID > 0 else {
            LyricsLog.info("Word timing for '\(title)' skipped: not playing, or the source app's process is unknown")
            return
        }

        let lineIDs = lines.map(\.id)
        LyricsWordTimingGenerator.shared.start(
            request: .init(
                trackIdentity: identity,
                title: title,
                artist: artist,
                album: album.isEmpty ? nil : album,
                spotifyTrackID: spotifyTrackID,
                durationMs: totalDuration > 0 ? Int(totalDuration * 1000) : nil,
                lines: lines,
                processID: pid_t(processID)
            ),
            currentSongTime: { [weak self] in self?.elapsedTime() },
            isCurrentTrack: { [weak self] in
                guard let self else { return false }
                return self.settingsModel.settings.generateWordTimedLyrics
                    && self.needsLyricsUpdates
                    && self.lastTrackIdentity == identity
                    && self.isPlaying
            },
            onGenerated: { [weak self] generated in
                guard let self, self.lastTrackIdentity == identity, self.lyrics.map(\.id) == lineIDs else { return }
                LyricsLog.info("Word timing applied for '\(title)': \(generated.filter(\.hasWordTiming).count) word-synced lines")
                self.replaceLyrics(generated, preservePosition: true)
                self.lyricsCache[cacheKey] = generated
            }
        )
    }

    private func refreshWordTimingGenerationState() {
        guard #available(macOS 26.0, *) else { return }
        guard settingsModel.settings.generateWordTimedLyrics,
              needsLyricsUpdates,
              isPlaying,
              !lyrics.isEmpty,
              !lyrics.contains(where: \.hasWordTiming),
              let title = title.trimmedOrNil,
              let artist = artist.trimmedOrNil else {
            LyricsWordTimingGenerator.shared.stop()
            return
        }

        let album = self.album.trimmedOrNil ?? ""
        startWordTimingGenerationIfNeeded(
            lines: lyrics,
            title: title,
            artist: artist,
            album: album,
            spotifyTrackID: lastKnownBundleID == "com.spotify.client" ? trackID : nil,
            cacheKey: lyricsCacheKey(title: title, artist: artist, album: album)
        )
    }

    private func stopWordTimingGeneration() {
        guard #available(macOS 26.0, *) else { return }
        LyricsWordTimingGenerator.shared.stop()
    }

    private func fetchSpotifyLyricsFallback(trackID: String?, imageURL: String) async -> [LyricLine] {
        guard let trackID, !trackID.isEmpty, spotifyPrivateAPI.isLoggedIn else { return [] }
        let hasSpotifyLyrics = await spotifyPrivateAPI.trackHasLyrics(trackId: trackID)
        guard !Task.isCancelled, hasSpotifyLyrics != false else { return [] }
        return await spotifyPrivateAPI.fetchColorLyrics(trackId: trackID, imageURL: imageURL)
    }

    private func lyricsCacheKey(title: String, artist: String?, album: String?) -> String {
        "\(title)|\(artist.trimmedOrNil ?? "")|\(album.trimmedOrNil ?? "")".lowercased()
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

    private func retranslateLyricsIfNeeded() {
        lyricsTranslationTask?.cancel()
        let fetchIdentity = lastTrackIdentity

        lyricsTranslationTask = Task {
            guard !self.lyrics.isEmpty else { return }
            var lyricsToUpdate = self.lyrics

            if !settingsModel.settings.enableLyricTranslation {
                for i in 0..<lyricsToUpdate.count { lyricsToUpdate[i].translatedText = nil }
                guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else { return }
                self.replaceLyrics(lyricsToUpdate, preservePosition: true)
                return
            }

            let sample = lyricsToUpdate.prefix(5).map { $0.text }.joined(separator: " ")
            guard !sample.isEmpty else { return }

            guard let lang = await lyricsFetcher.detectLanguage(for: sample) else {
                return
            }

            let target = settingsModel.settings.lyricTranslationLanguage
            guard lang != target else {
                return
            }

            if Task.isCancelled { return }
            await lyricsFetcher.translate(lyrics: &lyricsToUpdate, from: lang, to: target)

            guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else {
                return
            }

            self.replaceLyrics(lyricsToUpdate, preservePosition: true)
        }
    }

    private func replaceLyrics(_ newLyrics: [LyricLine], preservePosition: Bool = false) {
        lyrics = newLyrics
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

        let adjustedElapsed = adjustedLyricsElapsedTime(elapsedTime)
        let newIndex = LyricsTimeline.primaryIndex(
            in: lyrics,
            at: adjustedElapsed,
            trackDuration: totalDuration > 0 ? totalDuration : nil
        )
        let newLyric = newIndex.map { lyrics[$0] }

        guard newIndex != currentLyricIndex || currentLyric?.id != newLyric?.id else { return }

        currentLyricIndex = newIndex
        if currentLyric?.id != newLyric?.id {
            currentLyric = newLyric
            currentLyricPublisher.send(newLyric)
        }
    }

    func lyricLine(at date: Date = Date()) -> LyricLine? {
        guard !lyrics.isEmpty else { return nil }
        guard let index = lyricIndex(at: date) else { return nil }
        return lyrics[index]
    }

    func lyricIndex(at date: Date = Date()) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        return LyricsTimeline.primaryIndex(
            in: lyrics,
            at: lyricsElapsedTime(at: date),
            trackDuration: totalDuration > 0 ? totalDuration : nil
        )
    }

    func activeLyricIndices(at date: Date = Date()) -> [Int] {
        guard !lyrics.isEmpty else { return [] }
        return LyricsTimeline.activeIndices(
            in: lyrics,
            at: lyricsElapsedTime(at: date),
            trackDuration: totalDuration > 0 ? totalDuration : nil
        )
    }

    private func adjustedLyricsElapsedTime(_ elapsedTime: TimeInterval) -> TimeInterval {
        elapsedTime - settingsModel.settings.lyricOffset
    }

    private func setupDerivedStatePublisher() {
        $title
            .map { $0?.isEmpty == false }
            .removeDuplicates()
            .assign(to: &$shouldShowLiveActivity)
    }

    private func setupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppTermination(notification:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func handleAppTermination(notification: NSNotification) {
        guard let tApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let bID = tApp.bundleIdentifier else { return }
        Task { @MainActor in
            let normalized = MediaApplicationIdentity.canonicalBundleID(bID) ?? bID
            let prefixes = Set([bID, normalized])
            let keysToRemove = Set(
                self.activeMediaSources.keys.filter { key in
                    prefixes.contains(where: { key.hasPrefix($0) })
                }
            )
            guard !keysToRemove.isEmpty else { return }
            for key in keysToRemove {
                self.activeMediaSources.removeValue(forKey: key)
            }
            self.lastPublishedSourceSignature = 0
            if let current = self.currentSourceKey, keysToRemove.contains(current) {
                self.sourcePinnedByUser = false
                self.evaluateAutoSourceSelection(in: self.activeMediaSources)
            }
        }
    }

    nonisolated private static var volumeScalarAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func setupVolumeListener() {
        self.systemVolume = SystemControl.getVolume()
        guard let deviceID = Self.defaultOutputDeviceID() else { return }
        var address = Self.volumeScalarAddress
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            let volume = SystemControl.getVolume()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.systemVolume = volume
                self.volumePublisher.send(volume)
            }
        }
        self.volumeListener = listener
        AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, listener)
    }

    nonisolated private static func removeVolumeListener(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        var address = volumeScalarAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, listener)
    }

    nonisolated private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var dID: AudioDeviceID = kAudioObjectUnknown, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dID) == noErr ? dID : nil
    }

    private func fetchAppIcon(for bundleIdentifier: String?) {
        self.appIcon = bundleIdentifier.flatMap { cachedAppIcon(for: $0) }
    }

    private func resetColorsToDefault() {
        let def = Color(red: 0.53, green: 0.73, blue: 0.88)
        self.accentColor = def; self.leftGradientColor = def; self.rightGradientColor = def.opacity(0.7)
    }

    private func resetLyricsState() {
        if #available(macOS 26.0, *) {
            LyricsWordTimingGenerator.shared.stop()
        }
        lyricsFetchTask?.cancel()
        lyricsTranslationTask?.cancel()
        lyrics = []
        currentLyric = nil
        currentLyricIndex = nil
        currentlyFetchingFingerprint = nil
        lastAttemptedLyricsFingerprint = nil
        currentLyricPublisher.send(nil)
    }

    private func setupSettingsObserver() {
        settingsModel.$settings
            .map {
                (
                    $0.enableLyricTranslation,
                    $0.lyricTranslationLanguage
                )
            }
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
            .map { ($0.showLyricsInLiveActivity, $0.musicLiveActivityEnabled) }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshTimers()
                self.refreshLyricsLoadingState()
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.generateWordTimedLyrics)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWordTimingGenerationState()
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.lyricOffset)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateCurrentLyric(for: self.currentElapsedTime)
                self.objectWillChange.send()
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

        settingsModel.$settings
            .map { ($0.mediaAppVisibility, $0.mediaSource, $0.prioritizeMediaSource) }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSpotifyLiveSource()
            }
            .store(in: &cancellables)
    }

    func showTransientIcon(for icon: WaveformView.TransientIcon, duration: TimeInterval = 2.0) {
        transientIconTimer?.invalidate()
        transientIcon = icon
        transientIconTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.transientIcon == icon else { return }
                self.transientIcon = nil
            }
        }
    }

    private func triggerQuickPeek() {
        guard settingsModel.settings.showQuickPeekOnTrackChange else { return }
        quickPeekTimer?.invalidate()
        self.showQuickPeek = true
        quickPeekTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showQuickPeek = false }
        }
    }

    private func updateDevicePolling() {
        airPlay.startDiscovery()
        airplayDeviceUpdateTimer?.invalidate()
        if lastKnownBundleID == "com.apple.Music" {
            airplayDeviceUpdateTimer = Timer.scheduledCoalescing(withTimeInterval: 10.0, repeats: true) { [weak self] _ in Task { await self?.updateAirPlayDevices() } }
            airplayDeviceUpdateTimer?.fire()
        }
    }

    func updateAirPlayDevices() async {
        airPlay.startDiscovery()
        airPlay.refresh()
        let devices = airPlay.devices
        guard devices != airplayDevices else { return }
        self.airplayDevices = devices
    }

    @discardableResult
    func switchToAirPlayDevice(_ device: AirPlayDevice) async -> AirPlaySwitchResult {
        let result = await airPlay.switchTo(device)
        await updateAirPlayDevices()
        return result
    }

    func setAirPlayDeviceVolume(deviceName: String, volume: Int) async {
        airPlay.setVolume(volume, forDeviceNamed: deviceName)
    }
}

private extension Optional where Wrapped == String {
    var trimmedOrNil: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var isBlank: Bool { trimmedOrNil == nil }
}