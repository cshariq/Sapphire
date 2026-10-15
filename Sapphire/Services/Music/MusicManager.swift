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
@Observable
class MusicManager {
    static let shared = MusicManager()

    // MARK: - Specialized Sub-Managers
    @ObservationIgnored lazy var appleMusic = AppleMusicManager.shared
    @ObservationIgnored lazy var airPlay = AirPlayManager.shared
    @ObservationIgnored lazy var spotifyAppleScript = SpotifyAppleScriptManager.shared
    @ObservationIgnored lazy var spotifyOfficialAPI = SpotifyOfficialAPIManager.shared
    @ObservationIgnored lazy var tidalAPI = TidalAPIManager.shared
    @ObservationIgnored lazy var spotifyPrivateAPI = SpotifyPrivateAPIManager.shared
    @ObservationIgnored lazy var browserAppleScript = BrowserAppleScriptManager.shared

    // MARK: - Proxied Authentication States
    var officialAPIHasKeys: Bool { spotifyOfficialAPI.hasApiKeys }
    var isOfficialAPIAuthenticated: Bool { spotifyOfficialAPI.isAuthenticated }
    var isTidalAPIAuthenticated: Bool { tidalAPI.isAuthenticated }
    var isPrivateAPIAuthenticated: Bool { spotifyPrivateAPI.isLoggedIn }
    var isPremiumUser: Bool { spotifyOfficialAPI.isPremiumUser }

    // MARK: - Published UI State
    let playbackTimePublisher = PassthroughSubject<(elapsed: TimeInterval, progress: Double), Never>()
    let volumePublisher = PassthroughSubject<Float, Never>()
    let currentLyricPublisher = PassthroughSubject<LyricLine?, Never>()
    let trackDidChange = PassthroughSubject<Void, Never>()

    var title: String? {
        didSet {
            if oldValue != title { scheduleTrackIdentifierRefresh() }
        }
    }
    var artist: String? {
        didSet {
            if oldValue != artist { scheduleTrackIdentifierRefresh() }
        }
    }
    var album: String?
    var artworkURL: URL?
    var artwork: NSImage?
    var uri: String?
    var trackID: String?
    var transientIcon: WaveformView.TransientIcon? = nil

    var isPlaying: Bool = false {
        didSet(wasPlaying) {
            self.isWaveformAnimating = isPlaying
            if !isPlaying && wasPlaying {
                if title != nil { showTransientIcon(for: .paused) }
            } else if isPlaying && !wasPlaying {
                if transientIcon == .paused {
                    transientIconTimer?.invalidate()
                    transientIcon = nil
                }
                retryLyricsIfDue()
            }
            refreshTimers()
            refreshWordTimingGenerationState()
            refreshPlaybackTrajectory()
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
            if let prewarm = detailPrewarm, prewarm.key == detailPrewarmKey,
               Date().timeIntervalSince(prewarm.date) < 30 {
                await prewarm.task.value
            } else {
                await loadDetailPlayerExtras()
            }
            await backfillSpotifyMetadataIfNeeded()
        }
        refreshLyricsLoadingState()
        refreshArtworkColorExtractionIfNeeded()
    }

    @ObservationIgnored private var detailPrewarm: (key: String, date: Date, task: Task<Void, Never>)?

    private var detailPrewarmKey: String? {
        title.trimmedOrNil.map { uri ?? "\($0)|\(artist ?? "")" }
    }

    func prewarmDetailPlayer() {
        guard !isDetailPlayerOpen, let key = detailPrewarmKey else { return }
        if let prewarm = detailPrewarm, prewarm.key == key, Date().timeIntervalSince(prewarm.date) < 30 { return }
        spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
        detailPrewarm = (key, Date(), Task { @MainActor in await self.loadDetailPlayerExtras() })
    }

    private func loadDetailPlayerExtras() async {
        await ensureNextSongAvailableIfNeeded()
        if lastKnownBundleID == "com.apple.Music", settingsModel.current.spotifyShowSuggestedSongs,
           appleSuggestedTracks.isEmpty {
            await refreshAppleMusicNowPlaying()
        }
        await ensureSpotifyPlayerExtrasLoaded(force: true)
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
            applySpotifyLiveUIFromPlayerState()
        }
        await ensureNextSongAvailableIfNeeded()
        publishPlaybackTime(force: true, includeProgressUI: true)
        if isDetailPlayerOpen, isSpotifySourceSelected {
            await ensureSpotifyPlayerExtrasLoaded(force: false)
        }
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

    var totalDuration: TimeInterval = 0 {
        didSet { refreshPlaybackTrajectory() }
    }

    private(set) var playbackTrajectory = PlaybackTrajectory.stopped

    private func refreshPlaybackTrajectory() {
        let now = Date()
        let rate: Double
        if let anchor = playbackTimingAnchor {
            rate = anchor.rate
        } else if let payload = latestTrackPayload {
            rate = payload.playbackTimingAnchor(isPlayingNow: payload.isPlaying ?? false)?.rate ?? 0
        } else {
            rate = 0
        }
        let next = PlaybackTrajectory(elapsed: elapsedTime(at: now), date: now, rate: rate, duration: totalDuration)
        guard !next.isEquivalent(to: playbackTrajectory) else { return }
        playbackTrajectory = next
    }

    var lyrics: [LyricLine] = [] {
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

    private(set) var hasDisplayableLyrics: Bool = false
    private(set) var hasCurrentDisplayableLyric: Bool = false

    private static func isDisplayable(_ line: LyricLine) -> Bool {
        !(line.translatedText ?? line.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var accentColor: Color = .white
    var leftGradientColor: Color = .white
    var rightGradientColor: Color = .white
    var appIcon: NSImage?
    var shouldShowLiveActivity: Bool { title?.isEmpty == false }
    var popularity: Int?
    var playCount: String?
    private(set) var playCountValue: Int?
    var fetchedSpotifyPopularity: Int?
    var applePlayCount: Int?
    var applePopularity: Int?
    var appleSuggestedTracks: [AppleMusicSong] = []
    private(set) var appleSuggestionsResolved = false
    private(set) var appleNowPlaying = AppleMusicNowPlayingDetails()
    var isLiked: Bool = false
    var shuffleState: Bool = false
    var repeatState: RepeatMode = .off
    var lastTrackChangeDate: Date?
    var isHoveringAlbumArt: Bool = false
    @ObservationIgnored private var albumArtHoverExit: DispatchWorkItem?
    var showQuickPeek: Bool = false
    var lyricsTapped: Bool = false
    var isWaveformAnimating: Bool = false
    private(set) var lastKnownBundleID: String?
    private(set) var currentTrackArtworkToken: String = ""
    var airplayDevices: [AirPlayDevice] = []

    var activeMediaSources: [String: TrackInfo] = [:]
    var currentSourceKey: String?
    @ObservationIgnored private var sourcePinnedByUser = false
    private let spotifyLiveSourceKey = "com.spotify.client:spotify-live"
    private let phoneMediaSourceKey = "com.shariq.sapphire.phone-media"
    @ObservationIgnored private var phoneMediaSource: TrackInfo?
    private(set) var phoneMediaDeviceName: String?
    private(set) var phoneMediaAppName: String?
    @ObservationIgnored private var lastPublishedSourceSignature: Int = 0
    @ObservationIgnored private var lastExtractedArtworkToken: String?

    var nativeQueue: [PlayerState.Track] = []
    var nowPlayingTrack: PlayerState.Track?

    private(set) var appleMusicNextTrack: AppleMusicManager.QueueTrack?

    private(set) var currentLyric: LyricLine? {
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
    private(set) var isDetailPlayerOpen: Bool = false
    private(set) var isMusicHubOpen: Bool = false
    private(set) var isLyricsDetailOpen: Bool = false
    private(set) var isDetachedLyricsOpen: Bool = false
    private(set) var isMusicLiveActivityActive: Bool = false
    @ObservationIgnored private(set) var systemVolume: Float = 0.0

    @ObservationIgnored private(set) var currentElapsedTime: TimeInterval = 0
    @ObservationIgnored private(set) var playbackProgress: Double = 0.0

    // MARK: - Private Properties
    private let mediaController = NativeMediaController()
    private let lyricsFetcher = LyricsFetcher()
    private let settingsModel = SettingsModel.shared

    @ObservationIgnored private var lyricsFetchTask: Task<Void, Never>?
    @ObservationIgnored private var wordTimingRefreshWork: DispatchWorkItem?
    @ObservationIgnored private var lyricsTranslationTask: Task<Void, Never>?
    @ObservationIgnored private var volumeListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var currentTrackDuration: TimeInterval = 0
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var quickPeekTimer: Timer?
    @ObservationIgnored private var transientIconTimer: Timer?
    @ObservationIgnored private var currentLyricIndex: Int? = nil

    @ObservationIgnored private var liveActivityTimer: Timer?
    @ObservationIgnored private var liveActivityTimerInterval: TimeInterval = 0
    @ObservationIgnored private var liveActivityTimerRepeats = false
    @ObservationIgnored private var latestTrackPayload: TrackInfo.Payload? {
        didSet { refreshPlaybackTrajectory() }
    }
    @ObservationIgnored private var playbackTimingAnchor: PlaybackTimingAnchor? {
        didSet { refreshPlaybackTrajectory() }
    }
    @ObservationIgnored private var lastTrackIdentity: String?
    @ObservationIgnored private var lastMediaFingerprint: String?
    @ObservationIgnored private var currentlyFetchingFingerprint: String?
    @ObservationIgnored private var lastAttemptedLyricsFingerprint: String?
    @ObservationIgnored private var artworkColorExtractionTask: Task<Void, Never>?
    @ObservationIgnored private var displayedRemoteArtwork: (url: URL, image: NSImage)?
    @ObservationIgnored private var loadingArtworkURL: URL?
    @ObservationIgnored private var artworkTrackToken: String?
    @ObservationIgnored private var trackIdentifierRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastHandledTrackKey: String?
    @ObservationIgnored private var lastNextSongFetchAttempt: Date = .distantPast
    @ObservationIgnored private var playStateHoldUntil: Date = .distantPast
    @ObservationIgnored private var playStateHoldPreferPlaying = true
    @ObservationIgnored private var spotifyPlayStateReconcileUntil: Date = .distantPast
    @ObservationIgnored private var spotifyPlayStateReconcileTarget: Bool?
    @ObservationIgnored private var trackMetadataGeneration: UInt64 = 0
    @ObservationIgnored private var lastConnectTrackURI: String?
    @ObservationIgnored private var spotifyConnectSyncTask: Task<Void, Never>?
    @ObservationIgnored private var lastSpotifyConnectSyncAt: Date = .distantPast
    @ObservationIgnored private var spotifyHydrationTask: Task<Void, Never>?
    @ObservationIgnored private var spotifyHydrationInFlightURI: String?

    @ObservationIgnored private var lyricsCache = BoundedLRUCache<String, [LyricLine]>(capacity: 40)
    @ObservationIgnored private var wordTimingBase: WordTimingBase?
    @ObservationIgnored private var wordTimingBases = BoundedLRUCache<String, WordTimingBase>(capacity: 40)
    @ObservationIgnored private var lyricsTranslationCache = BoundedLRUCache<String, LyricsTranslation>(capacity: 24)
    @ObservationIgnored private var lyricsRetry = LyricsRetryPolicy()
    @ObservationIgnored private var lyricsRetryTask: Task<Void, Never>?
    private var needsLyricsForTiming: Bool {
        needsLyricsUpdates || settingsModel.current.generateWordTimedLyrics
    }

    private var needsLyricsUpdates: Bool {
        if isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen { return true }
        guard settingsModel.current.showLyricsInLiveActivity,
              settingsModel.current.musicLiveActivityEnabled else { return false }
        if isPhoneMediaSourceSelected,
           !settingsModel.current.continuityPhoneMediaLyricsInLiveActivity {
            return false
        }
        return ActiveAppMonitor.shared.isLyricsAllowedForActiveApp
    }

    private var shouldExtractArtworkColors: Bool {
        isDetailPlayerOpen || isMusicLiveActivityActive
    }

    private var needsSpotifyHeavyMetadata: Bool {
        isDetailPlayerOpen || isMusicHubOpen || isLyricsDetailOpen || isDetachedLyricsOpen ||
        settingsModel.current.showPopularityInMusicPlayer || needsLyricsUpdates
    }

    private var needsSpotifyPlayerEnrichment: Bool {
        isDetailPlayerOpen || isMusicHubOpen || isLyricsDetailOpen || isDetachedLyricsOpen
    }

    private init() {
        #if DEBUG
        if #available(macOS 26.0, *) { LyricsEvaluationHarness.shared.install() }
        #endif
        appleMusic.attach(mediaController: mediaController)

        spotifyPrivateAPI.valuePublisher(\.isLoggedIn)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loggedIn in
                guard let self else { return }
                self.refreshSpotifyLiveSource()
                if !loggedIn {
                    self.rebindToBestSystemMediaSource(forceReapply: true)
                }
            }
            .store(in: &cancellables)

        airPlay.valuePublisher(\.devices)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.airplayDevices = devices
            }
            .store(in: &cancellables)

        spotifyPrivateAPI.valuePublisher(\.nativeQueue)
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

        spotifyPrivateAPI.valuePublisher(\.playerState)
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

        spotifyPrivateAPI.valuePublisher(\.playerState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleSpotifyPlayerState(state)
            }
            .store(in: &cancellables)

        setupHandlers()
        setupNotificationObservers()
        setupVolumeListener()
        setupSettingsObserver()
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

        let keepsDisplayedSong = state.track.map(isDisplayedSpotifySong) ?? false
        if let incomingURI { lastConnectTrackURI = incomingURI }

        if isSpotifyLiveSourceSelected {
            applySpotifyLiveUIFromPlayerState()
        } else if let track = state.track {
            publishSpotifyMediaIdentity(from: track, keepingDisplayedSong: keepsDisplayedSong)
            applySpotifyConnectTransport(state)
        }

        lastNextSongFetchAttempt = .distantPast
        handleSpotifyTrackAdvanced(to: state.track, keepingDisplayedSong: keepsDisplayedSong)

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

        valuePublisher(\.lastKnownBundleID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                guard let self, bundleID == "com.spotify.client" else { return }
                self.spotifyPrivateAPI.bootstrapIfNeeded(policy: .onDemand)
            }
            .store(in: &cancellables)

        valuePublisher(\.lastKnownBundleID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                guard let self, bundleID == "com.apple.Music" else { return }
                guard !self.appleMusic.isMusicKitAuthorized, self.appleMusic.isMusicKitConfigured else { return }
                Task { await self.appleMusic.requestAuthorization() }
            }
            .store(in: &cancellables)
    }

    private func publishSpotifyMediaIdentity(from track: PlayerState.Track, keepingDisplayedSong: Bool = false) {
        guard isSpotifySourceSelected else { return }
        syncConnectNowPlayingMetadata(from: track)
        lockConnectMediaIdentity(from: track, keepingFingerprint: keepingDisplayedSong)
    }

    private func syncConnectNowPlayingMetadata(from track: PlayerState.Track) {
        guard isSpotifySourceSelected else { return }
        if lastKnownBundleID != "com.spotify.client" {
            lastKnownBundleID = "com.spotify.client"
            fetchAppIcon(for: "com.spotify.client")
        }
        var identityChanged = false
        let keepsDisplayedSong = isDisplayedSpotifySong(track)
        if track.uri != self.uri, !track.uri.isEmpty, !keepsDisplayedSong {
            if track.metadata?.artistName.trimmedOrNil == nil { self.artist = nil }
            if track.metadata?.albumTitle.trimmedOrNil == nil { self.album = nil }
            if track.metadata?.imageURL == nil {
                clearArtwork()
                currentTrackArtworkToken = "connect-missing-\(track.uri)"
            }
            if !track.uri.hasPrefix("spotify:track:") { trackID = nil }
        }
        if let imageURL = track.metadata?.imageURL {
            showRemoteArtwork(imageURL)
        }
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

    private func lockConnectMediaIdentity(from track: PlayerState.Track, keepingFingerprint: Bool = false) {
        guard isSpotifySourceSelected else { return }
        let fingerprint = Self.mediaFingerprint(
            title: track.metadata?.title,
            artist: track.metadata?.artistName
        )
        if !fingerprint.isEmpty, !(keepingFingerprint && lastMediaFingerprint != nil) {
            lastMediaFingerprint = fingerprint
        }
        lastTrackIdentity = track.uri
    }

    private func isDisplayedSong(title incomingTitle: String?, artist incomingArtist: String?) -> Bool {
        guard let incoming = incomingTitle.trimmedOrNil?.lowercased(),
              let shown = title.trimmedOrNil?.lowercased(),
              incoming == shown else { return false }
        guard let incomingArtist = incomingArtist.trimmedOrNil?.lowercased(),
              let shownArtist = artist.trimmedOrNil?.lowercased() else { return true }
        return incomingArtist.contains(shownArtist) || shownArtist.contains(incomingArtist)
    }

    private func isDisplayedSpotifySong(_ track: PlayerState.Track) -> Bool {
        if let uri, uri.hasPrefix("spotify:track:") { return uri == track.uri }
        return isDisplayedSong(title: track.metadata?.title, artist: track.metadata?.artistName)
    }

    private func isStaleSpotifyMediaRemote(_ payload: TrackInfo.Payload) -> Bool {
        guard let matches = connectTrackMatches(payload) else { return false }
        if !matches { return true }
        fillSpotifyIdentityGapsFromMediaRemote(payload)
        return false
    }

    private func connectTrackMatches(_ payload: TrackInfo.Payload) -> Bool? {
        guard isSpotifySourceSelected,
              shouldPreferSpotifyPrivateNowPlaying,
              let connect = spotifyPrivateAPI.playerState?.track else { return nil }
        let bundle = MediaApplicationIdentity.canonicalBundleID(payload.bundleIdentifier)
        guard bundle == "com.spotify.client" else { return nil }

        guard let connectTitle = connect.metadata?.title.trimmedOrNil?.lowercased(),
              let remoteTitle = payload.title.trimmedOrNil?.lowercased() else { return nil }
        return connectTitle == remoteTitle
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
        transientIconTimer?.invalidate()
        liveActivityTimer?.invalidate()
        if let volumeListener {
            Self.removeVolumeListener(volumeListener)
        }
    }

    // MARK: - Core Playback Actions (Context-Aware)

    func play() async {
        if currentSourceKey == nil, !isPhoneMediaSourceSelected {
            let defaultPlayer = settingsModel.current.defaultMusicPlayer
            if defaultPlayer != .appleMusic {
                defaultPlayer.open()
                return
            }
        }
        beginPlayStateHold(preferPlaying: true, duration: 1.2)
        applyPlayingState(true)

        if isPhoneMediaSourceSelected {
            ContinuityManager.shared.sendMediaCommand(.play)
            return
        }

        guard isSpotifySourceSelected else {
            if isAppleMusicInAppSource { appleMusic.play() } else { mediaController.play() }
            return
        }
        beginSpotifyPlayStateReconcile(target: true)

        if spotifyPrivateAPI.isLoggedIn {
            if await spotifyPrivateAPI.connectResume() { return }
            if spotifyAppleScript.isAppRunning() {
                _ = await spotifyAppleScript.play()
            } else if spotifyOfficialAPI.isAuthenticated, isPremiumUser {
                _ = await spotifyOfficialAPI.resume()
            }
            return
        }

        if spotifyOfficialAPI.isAuthenticated, isPremiumUser {
            _ = await spotifyOfficialAPI.resume()
        } else if spotifyAppleScript.isAppRunning() {
            _ = await spotifyAppleScript.play()
        } else {
            mediaController.play()
        }
    }

    func pause() async {
        beginPlayStateHold(preferPlaying: false, duration: 1.2)
        applyPlayingState(false)

        if isPhoneMediaSourceSelected {
            ContinuityManager.shared.sendMediaCommand(.pause)
            return
        }

        guard isSpotifySourceSelected else {
            if isAppleMusicInAppSource { appleMusic.pause() } else { mediaController.pause() }
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
        if isPhoneMediaSourceSelected {
            ContinuityManager.shared.sendMediaCommand(.next)
            return
        }
        if isSpotifySourceSelected {
            if await skipSpotifyViaConnectIfPossible(direction: .next) { return }
        }
        if isAppleMusicInAppSource { appleMusic.nextTrack(); return }
        mediaController.nextTrack()
    }

    func previousTrack() async {
        beginPlayStateHold(preferPlaying: true, duration: 1.2)
        if isPhoneMediaSourceSelected {
            ContinuityManager.shared.sendMediaCommand(.previous)
            return
        }
        if isSpotifySourceSelected {
            if await skipSpotifyViaConnectIfPossible(direction: .previous) { return }
        }
        if isAppleMusicInAppSource { appleMusic.previousTrack(); return }
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

        if isPhoneMediaSourceSelected {
            ContinuityManager.shared.sendMediaCommand(.seek, seekMs: Int(clamped * 1000))
            applyOptimisticSeek(to: clamped)
            return
        }

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

        if isAppleMusicInAppSource {
            appleMusic.seek(to: clamped)
        } else {
            mediaController.setTime(seconds: clamped)
        }
        applyOptimisticSeek(to: clamped)
    }

    var isAppleMusicContext: Bool {
        if lastKnownBundleID == "com.apple.Music" { return true }
        if isSpotifySourceActive || isSpotifyLiveSourceSelected { return false }
        if title != nil, lastKnownBundleID == DefaultMusicPlayer.tidal.bundleIdentifier { return false }
        return settingsModel.current.defaultMusicPlayer == .appleMusic
    }

    private var isAppleMusicInAppSource: Bool {
        guard lastKnownBundleID == "com.apple.Music", appleMusic.isInAppPlaybackActive else { return false }
        guard let rawBundle = latestTrackPayload?.bundleIdentifier else { return true }
        return rawBundle == AppleMusicPlaybackIdentity.hostBundleID
    }

    func seek(by seconds: TimeInterval) async {
        let newTime = max(0.0, min(currentElapsedTime + seconds, max(totalDuration, currentElapsedTime + seconds)))
        await seek(to: newTime)
    }

    var isSpotifyLiveSourceSelected: Bool {
        currentSourceKey == spotifyLiveSourceKey
    }

    var isPhoneMediaSourceSelected: Bool {
        currentSourceKey == phoneMediaSourceKey
    }

    func isPhoneMediaSource(_ key: String) -> Bool {
        key == phoneMediaSourceKey
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
            showRemoteArtwork(url)
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
        guard settingsModel.current.showSpotifySourceTab else { return false }
        guard spotifyPrivateAPI.isLoggedIn else { return false }
        guard !hasNativeSpotifyMediaSource(in: clients) else { return false }
        return true
    }

    private var shouldInjectPhoneMediaSource: Bool {
        settingsModel.current.continuityEnabled
            && settingsModel.current.continuityMediaControls
            && settingsModel.current.continuityPhoneMediaInMusicPlayer
            && phoneMediaSource != nil
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
        guard key != phoneMediaSourceKey else { return false }
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
            if isSystemSourceAlive(key: key, track: track) {
                merged[key] = track
            } else if isSpotifySourceKey(key), RunningApps.shared.isRunning("com.spotify.client") {
                merged[key] = track
            }
        }

        if shouldInjectSpotifySourceTab(into: merged),
           settingsModel.settings.isMediaAppVisible(bundleID: "com.spotify.client"),
           let spotifyLive = buildSpotifyLiveTrackInfo() {
            merged[spotifyLiveSourceKey] = spotifyLive
        }

        if shouldInjectPhoneMediaSource, let phoneMediaSource {
            merged[phoneMediaSourceKey] = phoneMediaSource
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
            hasher.combine(resolvedIsPlaying(from: track.payload))
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

        let localPlayingKeys = sources.compactMap { key, track -> String? in
            guard key != phoneMediaSourceKey,
                  key != spotifyLiveSourceKey,
                  isSystemSourceAlive(key: key, track: track),
                  resolvedIsPlaying(from: track.payload) == true else { return nil }
            return key
        }
        if !localPlayingKeys.isEmpty,
           !sourcePinnedByUser || currentSourceKey == phoneMediaSourceKey {
            return preferredSourceKey(restrictedTo: localPlayingKeys)
        }

        if sourcePinnedByUser,
           let current = currentSourceKey,
           sources[current] != nil {
            return current
        }

        let playingKeys = sources.compactMap { resolvedIsPlaying(from: $0.value.payload) == true ? $0.key : nil }
        guard !playingKeys.isEmpty else { return idleSourceKey(in: sources) }
        let pool = playingKeys.sorted()

        return preferredSourceKey(restrictedTo: pool)
            ?? currentSourceKey.flatMap { sources[$0] == nil ? nil : $0 }
            ?? sources.keys.min()
    }

    private func idleSourceKey(in sources: [String: TrackInfo]) -> String? {
        let defaultPlayer = settingsModel.current.defaultMusicPlayer
        if let bundle = defaultPlayer.bundleIdentifier {
            let own = sources.keys.filter { bundleID(fromSourceKey: $0) == bundle }.sorted()
            if let key = own.first(where: { $0 != spotifyLiveSourceKey }) ?? own.first {
                return key
            }
        }
        let pool = sources.keys.filter { $0 != spotifyLiveSourceKey }.sorted()
        guard !pool.isEmpty else { return nil }
        return preferredSourceKey(restrictedTo: pool)
            ?? currentSourceKey.flatMap { pool.contains($0) ? $0 : nil }
            ?? pool.first
    }

    private func preferredSourceKey(restrictedTo candidates: [String]) -> String? {
        let pool = candidates.filter { $0 != phoneMediaSourceKey }
        guard !pool.isEmpty else { return candidates.first }
        let preferredKey: String?
        switch settingsModel.current.mediaSource {
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
        return preferredKey
    }

    private func evaluateAutoSourceSelection(in sources: [String: TrackInfo]) {
        if sourcePinnedByUser,
           let current = currentSourceKey,
           sources[current] != nil {
            if current != phoneMediaSourceKey { return }
            let hasPlayingLocalSource = sources.contains { key, track in
                key != phoneMediaSourceKey
                    && key != spotifyLiveSourceKey
                    && isSystemSourceAlive(key: key, track: track)
                    && resolvedIsPlaying(from: track.payload) == true
            }
            if !hasPlayingLocalSource { return }
            sourcePinnedByUser = false
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
            success = await appleMusic.setFavorite(newLikedState, title: title, artist: artist)
            if success { appleNowPlaying.isFavorited = newLikedState }
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
        } else if lastKnownBundleID == "com.apple.Music" {
            shuffleState.toggle()
            appleMusic.setShuffle(enabled: shuffleState)
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
        if lastKnownBundleID == "com.apple.Music" {
            repeatState = repeatState.next()
            appleMusic.setRepeat(mode: repeatState)
            return
        }
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

    @ObservationIgnored private var appURLCache: [String: URL?] = [:]
    @ObservationIgnored private var appIconCache: [String: NSImage] = [:]

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
        spotifyPrivateAPI.relatedTracksURI = nil
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
        let wasPhone = currentSourceKey == phoneMediaSourceKey
        let isNowSpotify = isSpotifySourceKey(key)
        let resolvedPayload = payload ?? activeMediaSources[key]?.payload
        let keepsDisplayedSong = switching && currentSourceKey != nil && !(wasSpotify && !isNowSpotify)
            && resolvedPayload.map { isDisplayedSong(title: $0.title, artist: $0.artist) } == true
        currentSourceKey = key

        if switching {
            if wasPhone || key == phoneMediaSourceKey, !keepsDisplayedSong {
                clearArtwork()
            }
            if keepsDisplayedSong, let resolvedPayload {
                let fingerprint = mediaFingerprint(for: resolvedPayload)
                if !fingerprint.isEmpty { lastMediaFingerprint = fingerprint }
            }
            if !(wasSpotify && isNowSpotify) {
                if keepsDisplayedSong, let resolvedPayload {
                    lastTrackIdentity = trackIdentity(for: resolvedPayload)
                } else {
                    lastTrackIdentity = nil
                    lastMediaFingerprint = nil
                    currentTrackArtworkToken = "source-switch-\(key)-\(UUID().uuidString)"
                }
                lastHandledTrackKey = nil
                if !isNowSpotify {
                    clearPublishedSpotifyIdentityForSystemSource()
                    if let bundle = key.split(separator: ":").first.map(String.init) {
                        lastKnownBundleID = MediaApplicationIdentity.canonicalBundleID(bundle) ?? bundle
                        fetchAppIcon(for: lastKnownBundleID ?? bundle)
                    }
                }
            } else if !keepsDisplayedSong {
                currentTrackArtworkToken = "source-switch-spotify-\(UUID().uuidString)"
            }
        }

        if key == spotifyLiveSourceKey || key.contains("spotify-live") {
            applySpotifyLiveUIFromPlayerState()
            return
        }

        if key.hasPrefix("com.spotify.client"), spotifyPrivateAPI.isLoggedIn, !prefersNativeSpotifyMediaRemote {
            scheduleSpotifyConnectPlaybackSync(force: true)
        }

        if let resolvedPayload {
            applyTrackPayload(resolvedPayload, sourceKey: key)
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
    }

    private func applySpotifyLiveUIFromPlayerState() {
        lastKnownBundleID = "com.spotify.client"
        fetchAppIcon(for: "com.spotify.client")

        guard let state = spotifyPrivateAPI.playerState else {
            return
        }

        applyPlayingState(state.isActivelyPlaying, fromConnect: true)
        if let track = state.track {
            syncConnectNowPlayingMetadata(from: track)
        }
        applySpotifyPlayerTiming(state)
        publishPlaybackTime(force: true, includeProgressUI: true)
    }

    private func ensureNextSongAvailableIfNeeded(force: Bool = false) async {
        if lastKnownBundleID == "com.apple.Music" {
            guard settingsModel.current.spotifyShowNextSong else { return }
            if force || appleMusicNextTrack == nil {
                let queue = await appleMusic.fetchUpNextTracks()
                appleMusicNextTrack = queue.first
            }
            return
        }

        guard settingsModel.current.spotifyShowNextSong else { return }
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

    // MARK: - Artwork

    private func showRemoteArtwork(_ url: URL) {
        artworkURL = url
        if isShowingRemoteArtwork {
            refreshArtworkColorExtractionIfNeeded()
            return
        }
        guard loadingArtworkURL != url else { return }
        loadingArtworkURL = url
        Task { await loadRemoteArtwork(from: url) }
    }

    private static let remoteArtworkAttempts = 3

    private func clearArtwork() {
        artwork = nil
        artworkURL = nil
        loadingArtworkURL = nil
        artworkTrackToken = nil
        displayedRemoteArtwork = nil
    }

    private func clearSystemArtworkForCoverlessTrack() {
        guard artwork != nil, artworkURL == nil, !isShowingRemoteArtwork,
              !isSpotifySourceSelected, !isPhoneMediaSourceSelected else { return }
        artwork = nil
    }

    private var isShowingRemoteArtwork: Bool {
        guard let shown = displayedRemoteArtwork, let artwork else { return false }
        return shown.image === artwork && shown.url == artworkURL
    }

    private func acceptsSystemArtwork(_ image: NSImage) -> Bool {
        image !== artwork && !(isSpotifySourceSelected && isShowingRemoteArtwork)
    }

    private func loadRemoteArtwork(from url: URL) async {
        var image = await FileImageCache.shared.image(for: url)
        var attempt = 1
        while image == nil, attempt < Self.remoteArtworkAttempts, artworkURL == url {
            try? await Task.sleep(for: .seconds(1.5 * Double(attempt)))
            guard artworkURL == url else { break }
            image = await FileImageCache.shared.image(for: url)
            attempt += 1
        }
        if loadingArtworkURL == url { loadingArtworkURL = nil }
        guard let image, artworkURL == url else { return }
        displayedRemoteArtwork = (url, image)
        if artwork == nil || artworkTrackToken != currentTrackArtworkToken {
            currentTrackArtworkToken = "url:\(url.absoluteString)"
        }
        artworkTrackToken = currentTrackArtworkToken
        guard artwork !== image else { return }
        artwork = image
        refreshArtworkColorExtractionIfNeeded()
    }

    private func routeSystemPayload(_ payload: TrackInfo.Payload, sourceKey: String) {
        if isStaleSpotifyMediaRemote(payload) {
            applyPlaybackRefresh(payload)
        } else if hasMediaChanged(payload) {
            applyTrackPayload(payload, sourceKey: sourceKey)
        } else if let payloadArtwork = payload.artwork, acceptsSystemArtwork(payloadArtwork) {
            applyTrackPayload(payload, sourceKey: sourceKey)
        } else {
            if payload.artworkKnownAbsent { clearSystemArtworkForCoverlessTrack() }
            applyPlaybackRefresh(payload)
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
                self.routeSystemPayload(track.payload, sourceKey: key)
            }
        }

        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor in
                guard let self = self, let track = trackInfo else { return }
                let bundle = MediaApplicationIdentity.canonicalBundleID(track.payload.bundleIdentifier) ?? track.payload.bundleIdentifier ?? "unknown"
                guard self.settingsModel.settings.isMediaAppVisible(bundleID: bundle) else { return }
                let newKey = bundle

                guard self.currentSourceKey == newKey else { return }
                self.routeSystemPayload(track.payload, sourceKey: newKey)
            }
        }

        mediaController.onListenerTerminated = {
            print("[MusicManager] Native media stream lost; the controller will restart it.")
        }
        mediaController.onDecodingError = { error, _ in print("[MusicManager] Error decoding system media: \(error)") }
    }

    private func refreshSpotifyLiveSource() {
        let systemClients = mediaController.activeClients
        let merged = mergedSourcesWithSpotifyLive(systemClients)
        publishMergedSources(merged, reselect: false)
    }

    func updatePhoneMediaSource(
        _ state: ContinuityMediaState,
        artwork: NSImage?,
        deviceName: String?,
        sampledAt: Date
    ) {
        guard state.sessionId != "mac" else {
            clearPhoneMediaSource()
            return
        }
        let trimmedTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if !trimmedTitle.isEmpty {
            title = trimmedTitle
        } else if state.isPlaying {
            let app = state.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            title = app.isEmpty ? "Now Playing" : app
        } else {
            clearPhoneMediaSource()
            return
        }

        phoneMediaDeviceName = deviceName
        phoneMediaAppName = state.appName
        let position = max(0, TimeInterval(state.positionMs) / 1000)
        let durationMicros = state.durationMs > 0 ? Int64(state.durationMs) * 1_000 : nil
        let timestampMicros = Int64(sampledAt.timeIntervalSince1970 * 1_000_000)
        let trackID = [state.sessionId, state.appId, title, state.artist ?? ""]
            .joined(separator: "|")
        let phoneTrackChanged = phoneMediaSource?.payload.contentItemIdentifier != trackID

        let payload = TrackInfo.Payload(
            bundleIdentifier: phoneMediaSourceKey,
            title: title,
            artist: state.artist,
            album: state.album,
            isPlaying: state.isPlaying,
            durationMicros: durationMicros,
            currentElapsedTime: position,
            elapsedTimeMicros: Int64(position * 1_000_000),
            playbackRate: state.isPlaying ? 1 : 0,
            timestampEpochMicros: timestampMicros,
            isMusicApp: true,
            contentItemIdentifier: trackID,
            uniqueIdentifier: trackID,
            mediaType: "music",
            artwork: artwork
        )
        let track = TrackInfo(payload: payload)
        phoneMediaSource = track
        if phoneTrackChanged, artwork == nil, currentSourceKey == phoneMediaSourceKey {
            clearArtwork()
        }

        let merged = mergedSourcesWithSpotifyLive(mediaController.activeClients)
        publishMergedSources(merged, reselect: true)
        if currentSourceKey == phoneMediaSourceKey {
            applyTrackPayload(payload, sourceKey: phoneMediaSourceKey)
            publishPlaybackTime(force: true, includeProgressUI: true)
        }
    }

    func clearPhoneMediaSource() {
        guard phoneMediaSource != nil || activeMediaSources[phoneMediaSourceKey] != nil else { return }
        phoneMediaSource = nil
        phoneMediaDeviceName = nil
        phoneMediaAppName = nil
        publishMergedSources(mergedSourcesWithSpotifyLive(mediaController.activeClients), reselect: true)
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

    private func handleSpotifyTrackAdvanced(to track: PlayerState.Track?, keepingDisplayedSong: Bool = false) {
        guard isSpotifySourceSelected else { return }
        trackMetadataGeneration &+= 1
        let generation = trackMetadataGeneration

        if !keepingDisplayedSong {
            resetLyricsState()
            clearSpotifyTrackAccessories()
            isLiked = false
        }

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

        if !keepingDisplayedSong {
            currentTrackArtworkToken = track.uri
            triggerQuickPeek()
            trackDidChange.send()
            lastTrackChangeDate = Date()
        }

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
        }
        if !needsSpotifyPlayerEnrichment || keepingDisplayedSong,
           needsLyricsUpdates || needsSpotifyHeavyMetadata {
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
        if payload.bundleIdentifier == "com.apple.Music", payload.isPlaying == true,
           appleMusic.isInAppPlaybackActive {
            appleMusic.musicKit.relinquishInAppPlayback()
        }

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
            self.updateDeviceDiscovery()
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
            if artworkURL != nil, connectTrackMatches(payload) != true {
                artworkURL = nil
                loadingArtworkURL = nil
            }
            self.resetLyricsState()
            self.triggerQuickPeek()
            self.lastTrackChangeDate = Date()

            Task { await self.ensureLyricsForCurrentTrack() }
            self.trackDidChange.send()
        }

        if let newArtwork = payload.artwork {
            self.applyArtwork(newArtwork, trackIdentity: trackIdentity)
        } else if switchingAwayFromSpotify {
            clearArtwork()
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
        self.applePlayCount = nil; self.applePopularity = nil; self.appleSuggestedTracks = []; self.appleNowPlaying = AppleMusicNowPlayingDetails()
        self.appleSuggestionsResolved = false

        if self.lastKnownBundleID == "com.apple.Music" {
            guard isCurrentTrack(generation) else { return }
            let modes = await appleMusic.playerModes()
            guard isCurrentTrack(generation) else { return }
            self.shuffleState = modes.shuffle
            self.repeatState = modes.repeat
            appleMusicNextTrack = nil
            Task { await self.ensureNextSongAvailableIfNeeded(force: true) }
            await enrichAppleMusicTrackStats(generation: generation)
            Task { await self.fillAppleMusicPopularity(generation: generation) }
            guard isCurrentTrack(generation) else { return }
            if needsLyricsForTiming || isDetailPlayerOpen {
                await ensureLyricsForCurrentTrack()
            }
        } else if isSpotifySourceSelected && self.lastKnownBundleID == "com.spotify.client" {
            if shouldPreferSpotifyPrivateNowPlaying,
               let connectTrack = spotifyPrivateAPI.playerState?.track {
                publishSpotifyMediaIdentity(from: connectTrack)
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
                if needsLyricsForTiming || isDetailPlayerOpen {
                    await ensureLyricsForCurrentTrack()
                }
            }
        }
    }

    private func enrichAppleMusicTrackStats(generation: UInt64) async {
        guard lastKnownBundleID == "com.apple.Music" else { return }
        guard appleMusic.isMusicKitAuthorized else { return }
        guard isCurrentTrack(generation) else { return }
        guard let title, !title.isEmpty, let artist, !artist.isEmpty else { return }

        let includeRelated = isDetailPlayerOpen || isMusicHubOpen
        let details = await appleMusic.nowPlayingDetails(
            title: title,
            artist: artist,
            album: album,
            includeRelated: includeRelated
        )
        guard isCurrentTrack(generation) else { return }
        applyAppleNowPlaying(details, includesRelated: includeRelated)
    }

    private func fillAppleMusicPopularity(generation: UInt64) async {
        guard lastKnownBundleID == "com.apple.Music",
              settingsModel.current.showPopularityInMusicPlayer,
              let title, !title.isEmpty, let artist, !artist.isEmpty else { return }
        var score = await StatsFMPopularity.popularity(
            title: title,
            artist: artist,
            appleMusicID: appleNowPlaying.song?.id
        )
        if score == nil, let track = await searchForTrack(title: title, artist: artist) {
            score = track.popularity
        }
        guard isCurrentTrack(generation), let score else { return }
        applePopularity = score
        popularity = score
    }

    private func applyAppleNowPlaying(_ details: AppleMusicNowPlayingDetails, includesRelated: Bool) {
        appleNowPlaying = details
        applePlayCount = details.playCount
        appleSuggestedTracks = details.moreByArtist
        if includesRelated { appleSuggestionsResolved = true }
        if let favorited = details.isFavorited { isLiked = favorited }
    }

    func refreshAppleMusicNowPlaying() async {
        guard lastKnownBundleID == "com.apple.Music",
              let title, !title.isEmpty, let artist, !artist.isEmpty else { return }
        let generation = trackMetadataGeneration
        let details = await appleMusic.nowPlayingDetails(title: title, artist: artist, album: album, includeRelated: true)
        guard isCurrentTrack(generation) else { return }
        applyAppleNowPlaying(details, includesRelated: true)
    }

    private func hydrateSpotifyTrackAccessories(uri: String, trackId: String? = nil, generation: UInt64) async {
        guard isSpotifySourceSelected, spotifyPrivateAPI.isLoggedIn else { return }
        guard isCurrentTrack(generation) else { return }

        let id = trackId ?? uri.replacingOccurrences(of: "spotify:track:", with: "")
        guard !id.isEmpty, !id.contains(":") else { return }

        if self.uri != uri { self.uri = uri }
        if self.trackID != id { self.trackID = id }

        if let track = nowPlayingTrack, track.uri == uri {
            if let imageURL = track.metadata?.imageURL { showRemoteArtwork(imageURL) }
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
                showRemoteArtwork(coverURL)
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

    @ObservationIgnored private var lastForcedSpotifyDeviceStateRefreshAt: Date = .distantPast
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

    @ObservationIgnored private var cachedOutputDevice: (device: AudioDevice?, sampledAt: Date)?

    private func currentOutputDevice() -> AudioDevice? {
        if let cached = cachedOutputDevice, Date().timeIntervalSince(cached.sampledAt) < 1.0 {
            return cached.device
        }
        let device = AudioDeviceManager.shared.getCurrentOutputDevice()
        cachedOutputDevice = (device, Date())
        return device
    }

    func currentOutputDeviceSystemImage() -> String {
        if settingsModel.current.preferAirPlayOverSpotify,
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
        if key == phoneMediaSourceKey {
            return NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: "Phone")
                ?? NSImage(size: NSSize(width: 16, height: 16))
        }
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
        self.applePlayCount = nil; self.applePopularity = nil; self.appleSuggestedTracks = []; self.appleNowPlaying = AppleMusicNowPlayingDetails()
        self.appleSuggestionsResolved = false
        self.isPlaying = false; self.totalDuration = 0; self.currentElapsedTime = 0
        self.lastHandledTrackKey = nil
        self.resetLyricsState()
        if !settingsModel.current.persistMusicWidgetWhenPaused {
            self.title = nil; self.artist = nil; self.album = nil; clearArtwork()
        }
    }

    private func refreshTimers() {
        let inputs = MusicPlaybackTickPolicy.Inputs(
            isPlaying: isPlaying,
            isDetailPlayerOpen: isDetailPlayerOpen,
            isLyricsDetailOpen: isLyricsDetailOpen,
            isDetachedLyricsOpen: isDetachedLyricsOpen,
            isMusicLiveActivityActive: isMusicLiveActivityActive,
            musicLiveActivityEnabled: settingsModel.current.musicLiveActivityEnabled,
            showLyricsInLiveActivity: settingsModel.current.showLyricsInLiveActivity,
            lyricsAllowedForActiveApp: ActiveAppMonitor.shared.isLyricsAllowedForActiveApp,
            hasLyrics: !lyrics.isEmpty,
            showNextSong: settingsModel.current.spotifyShowNextSong,
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

        if !needsLyricsUpdates {
            resetLyricsState()
        }
        appIcon = nil
    }

    func trimLyricsCache() {
        let currentKey = currentLyricsCacheKey
        lyricsCache.trim(to: 4, keeping: currentKey)
        let target = settingsModel.current.lyricTranslationLanguage
        lyricsTranslationCache.trim(
            to: 2,
            keeping: currentKey.map { LyricsTranslation.cacheKey(trackKey: $0, targetLanguage: target) }
        )
    }

    private var currentLyricsCacheKey: String? {
        guard let title = title.trimmedOrNil, let artist = artist.trimmedOrNil else { return nil }
        return lyricsCacheKey(title: title, artist: artist, album: album.trimmedOrNil ?? "")
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
        guard acceptsSystemArtwork(displayArtwork) else { return }

        self.artwork = displayArtwork
        artworkTrackToken = currentTrackArtworkToken
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
            let extracted = await Task.detached(priority: .utility) { artwork.getEdgeColors() }.value
            guard !Task.isCancelled else { return }
            if let edgeColors = extracted {
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
        guard needsLyricsForTiming else {
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
        guard needsLyricsForTiming else {
            LyricsLog.infoOnChange(
                "ensure",
                "Lyrics fetch skipped: not needed (detailOpen=\(isDetailPlayerOpen || isLyricsDetailOpen || isDetachedLyricsOpen) lyricsSetting=\(settingsModel.current.showLyricsInLiveActivity) liveActivityEnabled=\(settingsModel.current.musicLiveActivityEnabled) appAllowed=\(ActiveAppMonitor.shared.isLyricsAllowedForActiveApp))"
            )
            return
        }
        guard let title = self.title.trimmedOrNil, let artist = self.artist.trimmedOrNil else {
            LyricsLog.infoOnChange("ensure", "Lyrics fetch skipped: track has no \(self.title.trimmedOrNil == nil ? "title" : "artist")")
            return
        }
        let album = self.album.trimmedOrNil ?? ""

        let cacheKey = lyricsCacheKey(title: title, artist: artist, album: album)
        if let cachedLyrics = lyricsCache.value(for: cacheKey) {
            LyricsLog.infoOnChange("ensure", "Lyrics cache hit for '\(title)' / '\(artist)': \(cachedLyrics.count) lines")
            guard !cachedLyrics.isEmpty else { return }
            if let base = wordTimingBases.value(for: cacheKey) {
                wordTimingBase = WordTimingBase(identity: lastTrackIdentity, baseLines: base.baseLines, stored: base.stored)
            }
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
        let databaseSpotifyID: String? = spotifyTrackID ?? {
            guard lastKnownBundleID == "com.spotify.client" || isSpotifySourceSelected,
                  let trackURI = uri, trackURI.hasPrefix("spotify:track:") else { return nil }
            let id = String(trackURI.dropFirst("spotify:track:".count))
            return id.isEmpty ? nil : id
        }()

        let attemptKey = "\(cacheKey)|spotify:\(spotifyTrackID ?? "none")"
        if currentlyFetchingFingerprint == attemptKey
            || (lastAttemptedLyricsFingerprint == attemptKey && !lyricsRetry.isDue(attemptKey, now: Date())) {
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
        let trackDuration: TimeInterval? = totalDuration > 0 ? totalDuration : nil
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

            async let appleLookup = AppleMusicLyricsProvider.shared.lyrics(
                title: title,
                artist: artist,
                duration: trackDuration
            )
            async let databaseLookup = LyricsDatabase.shared.lookup(
                title: title,
                artist: artist,
                spotifyTrackID: databaseSpotifyID,
                duration: trackDuration
            )
            let fetchedLRCLIB = await lyricsFetcher.fetchSyncedLyrics(
                for: title,
                artist: artist,
                album: album,
                duration: trackDuration
            )
            let databaseResult = await databaseLookup
            let appleLines = await appleLookup
            #if DEBUG
            if #available(macOS 26.0, *), LyricsEvaluationHarness.shared.isStudying {
                let wordTimedApple = appleLines?.contains(where: \.hasWordTiming) == true ? appleLines : nil
                var curated: [LyricLine]?
                if case .lyrics(let lines) = databaseResult { curated = lines }
                var lrclib: [LyricLine]?
                if case .found(let lines) = fetchedLRCLIB, !lines.isEmpty { lrclib = lines }
                LyricsEvaluationHarness.shared.study(
                    title: title,
                    artist: artist,
                    duration: trackDuration,
                    reference: wordTimedApple ?? curated,
                    referenceSource: wordTimedApple != nil ? "Apple Music" : "hand-timed",
                    lines: lrclib,
                    processID: pid_t(self.latestTrackPayload?.processIdentifier ?? 0)
                )
            }
            #endif
            guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else {
                LyricsLog.info("Lyrics results for '\(title)' dropped: fetch cancelled or track changed")
                return
            }

            if let appleLines, appleLines.contains(where: \.hasWordTiming) {
                LyricsLog.info(
                    "Lyrics applied from Apple Music for '\(title)': \(appleLines.count) lines (\(appleLines.filter(\.hasWordTiming).count) word-synced, \(appleLines.filter { !$0.background.isEmpty }.count) with background vocals)"
                )
                self.lyricsRetry.recordSuccess(attemptKey)
                self.wordTimingBase = nil
                self.replaceLyrics(appleLines)
                self.lyricsCache.set(appleLines, for: cacheKey)
                self.retranslateLyricsIfNeeded()
                return
            }

            if case .lyrics(let databaseLines) = databaseResult {
                LyricsLog.info(
                    "Lyrics applied from Sapphire database for '\(title)': \(databaseLines.count) lines (\(databaseLines.filter(\.hasWordTiming).count) word-synced)"
                )
                self.lyricsRetry.recordSuccess(attemptKey)
                self.replaceLyrics(databaseLines)
                self.lyricsCache.set(databaseLines, for: cacheKey)
                self.retranslateLyricsIfNeeded()
                return
            }

            let selectedLyrics: [LyricLine]
            let source: String
            if case .found(let lrclibLines) = fetchedLRCLIB {
                self.lyricsRetry.recordSuccess(attemptKey)
                self.lyricsCache.set(lrclibLines, for: cacheKey)
                guard !lrclibLines.isEmpty else {
                    LyricsLog.info("LRCLIB has an empty (instrumental) document for '\(title)'; not falling back")
                    return
                }
                selectedLyrics = lrclibLines
                source = "LRCLIB"
            } else {
                let fetchedSpotify = await fetchSpotifyLyricsFallback(
                    trackID: spotifyTrackID,
                    imageURL: imageURL
                )
                guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else { return }
                let spotifyStillCurrent = spotifyTrackID != nil
                    && self.isSpotifySourceSelected
                    && self.trackMetadataGeneration == spotifyGeneration
                guard spotifyStillCurrent, !fetchedSpotify.isEmpty else {
                    let anySourceFailed = fetchedLRCLIB == .failed
                        || databaseResult == .failed
                        || spotifyTrackID != nil
                    if anySourceFailed {
                        let retryAt = self.lyricsRetry.recordFailure(attemptKey, now: Date())
                        LyricsLog.info(
                            "No lyrics for '\(title)' yet (a source failed); retrying after \(Int(retryAt.timeIntervalSinceNow))s"
                        )
                        self.scheduleLyricsRetry(at: retryAt)
                    } else {
                        LyricsLog.info("No lyrics for '\(title)': LRCLIB and the database have none")
                        self.lyricsRetry.recordSuccess(attemptKey)
                        self.lyricsCache.set([], for: cacheKey)
                    }
                    return
                }
                self.lyricsRetry.recordSuccess(attemptKey)
                selectedLyrics = fetchedSpotify
                source = "Spotify"
            }

            let providerLyrics = LyricsVocalParts.split(selectedLyrics)
            var displayedLyrics = providerLyrics
            var base: WordTimingBase?
            if !providerLyrics.contains(where: \.hasWordTiming), Self.isLineSynced(providerLyrics) {
                var stored: WordTimingBase.Stored?
                if case .timing(let overlay, let samples, let confidence) = databaseResult {
                    let fit = overlay.fit(to: providerLyrics)
                    if fit.found >= 0.8, let timed = overlay.apply(to: providerLyrics, minimumCoverage: 0) {
                        displayedLyrics = timed
                        stored = .init(overlay: overlay, samples: samples, confidence: confidence)
                        LyricsLog.info("Lyrics timing from Sapphire database applied to \(Int(fit.coverage * 100))% of '\(title)' (\(samples) listen(s))")
                    } else {
                        LyricsLog.info("Lyrics timing from Sapphire database doesn't fit the \(source) text for '\(title)'")
                    }
                }
                let measuredLines = displayedLyrics.filter(\.hasWordTiming).count
                displayedLyrics = LyricsTimingRefiner.estimatedWords(for: displayedLyrics)
                LyricsLog.info("Word timing for '\(title)': \(measuredLines) lines measured, the rest estimated from \(source) line timing")
                base = WordTimingBase(identity: fetchIdentity, baseLines: providerLyrics, stored: stored)
                self.wordTimingBases.set(base!, for: cacheKey)
            }
            self.wordTimingBase = base

            displayedLyrics = LyricsVocalParts.timedBackground(displayedLyrics)
            LyricsLog.info("Lyrics applied from \(source) for '\(title)': \(providerLyrics.count) lines")
            self.replaceLyrics(displayedLyrics)
            self.lyricsCache.set(displayedLyrics, for: cacheKey)
            self.retranslateLyricsIfNeeded()
            self.refreshTimers()
            self.startWordTimingGenerationIfNeeded(
                lines: base?.baseLines ?? providerLyrics,
                title: title,
                artist: artist,
                album: album,
                cacheKey: cacheKey,
                base: base
            )
        }
        await lyricsFetchTask?.value
    }

    struct WordTimingBase {
        struct Stored {
            let overlay: LyricsTimingOverlay
            let samples: Int
            let confidence: Double
        }

        let identity: String?
        let baseLines: [LyricLine]
        let stored: Stored?
    }

    static func isLineSynced(_ lines: [LyricLine]) -> Bool {
        let timed = lines.filter { $0.timestamp > 0 }.count
        return timed >= max(lines.count / 2, 1)
    }

    private func startWordTimingGenerationIfNeeded(
        lines: [LyricLine],
        title: String,
        artist: String,
        album: String,
        cacheKey: String,
        base: WordTimingBase? = nil
    ) {
        guard settingsModel.current.generateWordTimedLyrics else { return }
        guard !lines.contains(where: \.hasWordTiming) else { return }
        if let stored = base?.stored,
           stored.samples >= LyricsTimingOverlay.maximumSamples
            || (stored.samples >= LyricsTimingOverlay.consensusTarget && stored.overlay.apply(to: lines) != nil) {
            return
        }
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
                consensus: base?.stored.map { ($0.overlay, $0.samples, $0.confidence) },
                durationMs: totalDuration > 0 ? Int(totalDuration * 1000) : nil,
                lines: lines,
                processID: pid_t(processID)
            ),
            currentSongTime: { [weak self] in self?.elapsedTime() },
            isCurrentTrack: { [weak self] in
                guard let self else { return false }
                return self.settingsModel.current.generateWordTimedLyrics
                    && self.lastTrackIdentity == identity
                    && self.isPlaying
            },
            onGenerated: { [weak self] generated in
                guard let self, self.lastTrackIdentity == identity, self.lyrics.map(\.id) == lineIDs else { return }
                let timed = LyricsVocalParts.timedBackground(LyricsTimingRefiner.estimatedWords(for: generated))
                LyricsLog.info("Word timing applied for '\(title)': \(timed.filter(\.hasWordTiming).count) word-synced lines")
                self.replaceLyrics(timed, preservePosition: true)
                self.lyricsCache.set(timed, for: cacheKey)
            }
        )
    }

    private func refreshWordTimingGenerationState() {
        wordTimingRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applyWordTimingGenerationState() }
        }
        wordTimingRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wordTimingRefreshDelay, execute: work)
    }

    private static let wordTimingRefreshDelay: TimeInterval = 0.4

    private func applyWordTimingGenerationState() {
        wordTimingRefreshWork = nil
        guard #available(macOS 26.0, *) else { return }
        let base = wordTimingBase.flatMap { $0.identity == lastTrackIdentity ? $0 : nil }
        guard settingsModel.current.generateWordTimedLyrics,
              isPlaying,
              !lyrics.isEmpty,
              base != nil || !lyrics.contains(where: \.hasWordTiming),
              let title = title.trimmedOrNil,
              let artist = artist.trimmedOrNil else {
            LyricsWordTimingGenerator.shared.stop()
            return
        }

        let album = self.album.trimmedOrNil ?? ""
        startWordTimingGenerationIfNeeded(
            lines: base?.baseLines ?? lyrics,
            title: title,
            artist: artist,
            album: album,
            cacheKey: lyricsCacheKey(title: title, artist: artist, album: album),
            base: base
        )
    }

    private func stopWordTimingGeneration() {
        guard #available(macOS 26.0, *) else { return }
        LyricsWordTimingGenerator.shared.stop()
    }

    private func scheduleLyricsRetry(at date: Date) {
        lyricsRetryTask?.cancel()
        let identity = lastTrackIdentity
        lyricsRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.lyricsRetryTask = nil
            guard self.lastTrackIdentity == identity, self.lyrics.isEmpty else { return }
            await self.ensureLyricsForCurrentTrack()
        }
    }

    private func retryLyricsIfDue(forceDue: Bool = false) {
        if forceDue { lyricsRetry.makeAllDue(now: Date()) }
        guard needsLyricsUpdates, lyrics.isEmpty, currentlyFetchingFingerprint == nil,
              title.trimmedOrNil != nil else { return }
        Task { await ensureLyricsForCurrentTrack() }
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
        if isPhoneMediaSourceSelected { return }
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
        let trackKey = currentLyricsCacheKey

        lyricsTranslationTask = Task {
            guard !self.lyrics.isEmpty else { return }
            var lyricsToUpdate = self.lyrics

            if !settingsModel.current.enableLyricTranslation {
                for i in 0..<lyricsToUpdate.count { lyricsToUpdate[i].translatedText = nil }
                guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else { return }
                self.replaceLyrics(lyricsToUpdate, preservePosition: true)
                return
            }

            let target = settingsModel.current.lyricTranslationLanguage
            let translationKey = trackKey.map { LyricsTranslation.cacheKey(trackKey: $0, targetLanguage: target) }
            if let translationKey, let cached = self.lyricsTranslationCache.value(for: translationKey) {
                if cached.sourceLanguage == target { return }
                if let applied = cached.applied(to: lyricsToUpdate), self.lastTrackIdentity == fetchIdentity {
                    self.replaceLyrics(applied, preservePosition: true)
                    return
                }
            }

            let sample = lyricsToUpdate.prefix(5).map { $0.text }.joined(separator: " ")
            guard !sample.isEmpty else { return }

            guard let lang = await lyricsFetcher.detectLanguage(for: sample) else {
                return
            }

            guard lang != target else {
                if let translationKey {
                    self.lyricsTranslationCache.set(
                        LyricsTranslation(sourceLanguage: lang, byOriginal: [:]),
                        for: translationKey
                    )
                }
                return
            }

            if Task.isCancelled { return }
            let complete = await lyricsFetcher.translate(lyrics: &lyricsToUpdate, from: lang, to: target)

            guard !Task.isCancelled, self.lastTrackIdentity == fetchIdentity else {
                return
            }

            if complete, let translationKey {
                self.lyricsTranslationCache.set(
                    LyricsTranslation(sourceLanguage: lang, translatedLines: lyricsToUpdate),
                    for: translationKey
                )
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
        elapsedTime - settingsModel.current.lyricOffset
    }

    private func setupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppTermination(notification:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSystemWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleSystemWake() {
        retryLyricsIfDue(forceDue: true)
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

    nonisolated private static var volumeScalarAddresses: [AudioObjectPropertyAddress] {
        [kAudioObjectPropertyElementMain, 1, 2].map {
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: $0
            )
        }
    }

    private func setupVolumeListener() {
        self.systemVolume = SystemControl.getVolume()
        guard let deviceID = Self.defaultOutputDeviceID() else { return }
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            let volume = SystemControl.getVolume()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.systemVolume = volume
                self.volumePublisher.send(volume)
            }
        }
        self.volumeListener = listener
        for var address in Self.volumeScalarAddresses {
            AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, listener)
        }
    }

    nonisolated private static func removeVolumeListener(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        for var address in volumeScalarAddresses {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, listener)
        }
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
        lyricsRetryTask?.cancel()
        lyricsRetryTask = nil
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
                self.publishPlaybackTime(force: true, includeProgressUI: true)
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
            .map {
                ($0.continuityEnabled, $0.continuityMediaControls, $0.continuityPhoneMediaInMusicPlayer)
            }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.publishMergedSources(
                    self.mergedSourcesWithSpotifyLive(self.mediaController.activeClients),
                    reselect: true
                )
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
        guard settingsModel.current.showQuickPeekOnTrackChange else { return }
        quickPeekTimer?.invalidate()
        self.showQuickPeek = true
        quickPeekTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showQuickPeek = false }
        }
    }

    private func updateDeviceDiscovery() {
        airPlay.startDiscovery()
        if lastKnownBundleID == "com.apple.Music" {
            Task { await updateAirPlayDevices() }
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
extension MusicManager {
    func setAlbumArtHovered(_ hovering: Bool) {
        albumArtHoverExit?.cancel()
        albumArtHoverExit = nil
        if hovering {
            if !isHoveringAlbumArt { isHoveringAlbumArt = true }
            return
        }
        guard isHoveringAlbumArt else { return }
        let exit = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.isHoveringAlbumArt = false }
        }
        albumArtHoverExit = exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: exit)
    }
}