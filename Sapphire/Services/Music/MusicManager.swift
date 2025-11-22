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
import MediaRemoteAdapter

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
        }
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
    @Published var airplayDevices: [AirPlayDevice] = []

    @Published var nativeQueue: [PlayerState.Track] = []
    @Published var nowPlayingTrack: PlayerState.Track?

    @Published private(set) var currentLyric: LyricLine?
    private(set) var playbackProgress: Double = 0.0
    private(set) var currentElapsedTime: TimeInterval = 0
    private(set) var systemVolume: Float = 0.0

    // MARK: - Private Properties
    private let mediaController = MediaController()
    private let lyricsFetcher = LyricsFetcher()
    private let settingsModel = SettingsModel.shared

    private var lyricsFetchTask: Task<Void, Never>?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var currentTrackDuration: TimeInterval = 0
    private var lastFetchedTitle: String?
    private var cancellables = Set<AnyCancellable>()
    private var quickPeekTimer: Timer?
    private var airplayDeviceUpdateTimer: Timer?
    private var transientIconTimer: Timer?
    private var searchDebouncer = Debouncer(delay: 0.5)
    private var currentLyricIndex: Int? = nil

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

        setupHandlers()
        setupNotificationObservers()
        setupVolumeListener()
        setupDerivedStatePublisher()
        setupSettingsObserver()
        mediaController.startListening()
    }

    deinit {
        mediaController.stop()
        Task { @MainActor in self.removeVolumeListener() }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        quickPeekTimer?.invalidate()
        airplayDeviceUpdateTimer?.invalidate()
        transientIconTimer?.invalidate()
    }

    // MARK: - Unified Playback Actions

    func play() { defaultControls.play() }
    func pause() { defaultControls.pause() }
    func nextTrack() { defaultControls.nextTrack() }
    func previousTrack() { defaultControls.previousTrack() }
    func seek(to seconds: Double) { defaultControls.seek(to: seconds) }

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
        if spotifyPrivateAPI.isLoggedIn {
            return await playWithPrivateAPI(trackUri: "", contextUri: contextUri, trackUid: nil, trackIndex: 0)
        } else if spotifyOfficialAPI.isPremiumUser {
            return await spotifyOfficialAPI.playPlaylist(contextUri: contextUri)
        } else {
            return await spotifyAppleScript.play(uri: contextUri)
        }
    }

    private func playWithPrivateAPI(trackUri: String, contextUri: String?, trackUid: String?, trackIndex: Int?) async -> PlaybackResult {
        do {
            guard let targetDeviceID = await findTargetDeviceID() else {
                return .failure(reason: "No available Spotify players found.")
            }

            let finalContextUri = contextUri ?? trackUri

            try await spotifyPrivateAPI.pythonCompatiblePlay(
                trackUri: trackUri,
                contextUri: finalContextUri,
                trackUid: trackUid,
                trackIndex: trackIndex,
                targetDeviceID: targetDeviceID
            )
            return .success
        } catch {
            return .failure(reason: "Private API play command failed: \(error.localizedDescription)")
        }
    }

    private func findTargetDeviceID() async -> String? {
        try? await spotifyPrivateAPI.refreshPlayerAndDeviceState()

        if let activeDeviceID = spotifyPrivateAPI.activePlayerDeviceID, activeDeviceID != spotifyPrivateAPI.controllerDeviceID {
            return activeDeviceID
        }

        let availablePlayers = spotifyPrivateAPI.devices.filter { $0.deviceId != spotifyPrivateAPI.controllerDeviceID }
        if availablePlayers.isEmpty {
            return nil
        }

        return availablePlayers.first(where: { $0.deviceType.lowercased() == "computer" })?.deviceId ?? availablePlayers.first?.deviceId
    }

    // MARK: - Unified State Management Actions

    func toggleLike() {
        let newLikedState = !self.isLiked
        self.isLiked = newLikedState

        Task {
            var success = false
            if self.lastKnownBundleID == "com.apple.Music" {
                appleMusic.setLiked(isLiked: newLikedState)
                success = true
            } else if let trackId = self.trackID {
                if spotifyPrivateAPI.isLoggedIn {
                    success = newLikedState ? await spotifyPrivateAPI.likeTrack(trackURI: "spotify:track:\(trackId)") : await spotifyPrivateAPI.unlikeTrack(trackURI: "spotify:track:\(trackId)")
                } else if spotifyOfficialAPI.isAuthenticated {
                    success = newLikedState ? await spotifyOfficialAPI.likeTrack(id: trackId) : await spotifyOfficialAPI.unlikeTrack(id: trackId)
                }
            }

            if !success {
                self.isLiked = !newLikedState
            }
        }
    }

    func toggleShuffle() {
        let newShuffleState = !self.shuffleState
        self.shuffleState = newShuffleState

        Task {
            var success = false
            if self.lastKnownBundleID == "com.apple.Music" {
                appleMusic.setShuffle(enabled: newShuffleState)
                success = true
            } else {
                if spotifyPrivateAPI.isLoggedIn {
                    success = await spotifyPrivateAPI.setShuffle(state: newShuffleState)
                } else if spotifyOfficialAPI.isAuthenticated {
                    success = await spotifyOfficialAPI.setShuffle(state: newShuffleState)
                }
            }
            if !success {
                self.shuffleState = !newShuffleState
            }
        }
    }

    func cycleRepeatMode() {
        let newRepeatState = self.repeatState.next()
        self.repeatState = newRepeatState

        Task {
            var success = false
            if self.lastKnownBundleID == "com.apple.Music" {
                appleMusic.setRepeat(mode: newRepeatState)
                success = true
            } else {
                if spotifyPrivateAPI.isLoggedIn {
                    success = await spotifyPrivateAPI.setRepeatMode(mode: newRepeatState)
                } else if spotifyOfficialAPI.isAuthenticated {
                    success = await spotifyOfficialAPI.setRepeatMode(mode: newRepeatState.rawValue)
                }
            }
            if !success {
                self.repeatState = newRepeatState.next().next()
            }
        }
    }

    func setSpotifyVolume(percent: Int) async -> Bool {
        if spotifyPrivateAPI.isLoggedIn {
            return await spotifyPrivateAPI.setVolume(percent: percent)
        } else if isPremiumUser {
            let result = await spotifyOfficialAPI.setVolume(percent: percent)
            if case .success = result { return true }
            return false
        } else {
            let result = await spotifyAppleScript.setVolume(percent: percent)
            if case .success = result { return true }
            return false
        }
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

    // MARK: - Data Fetching & State Updates

    func fetchActiveSpotifyDeviceState() async -> ActiveSpotifyDeviceState? {
        if spotifyPrivateAPI.isLoggedIn {
            try? await spotifyPrivateAPI.refreshPlayerAndDeviceState()
            guard let playerState = spotifyPrivateAPI.playerState, playerState.isPlaying == true,
                  let activeDeviceID = spotifyPrivateAPI.activePlayerDeviceID else { return nil }

            if let activeDevice = spotifyPrivateAPI.devices.first(where: { $0.deviceId == activeDeviceID }) {
                let volumePercent = activeDevice.volume.map { Int((Double($0) / 65535.0) * 100.0) }
                let canControlVolume = (activeDevice.capabilities.volumeSteps ?? 0) > 0
                return ActiveSpotifyDeviceState(name: activeDevice.name, type: activeDevice.deviceType, volumePercent: volumePercent, iconName: iconName(for: activeDevice.deviceType), canControlVolume: canControlVolume)
            }
        } else if isOfficialAPIAuthenticated {
            if let state = await spotifyOfficialAPI.fetchPlaybackState(), state.isPlaying {
                let canControlVolume = state.device.volumePercent != nil
                return ActiveSpotifyDeviceState(name: state.device.name, type: state.device.type, volumePercent: state.device.volumePercent, iconName: iconName(for: state.device.type), canControlVolume: canControlVolume)
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

    private func handleTrackIdentifierChange() {
        if fetchedSpotifyPopularity != nil { fetchedSpotifyPopularity = nil }

        guard let currentTitle = self.title, let currentArtist = self.artist, !currentTitle.isEmpty, !currentArtist.isEmpty else {
            return
        }

        self.popularity = nil
        self.playCount = nil
        self.isLiked = false

        Task {
            if self.lastKnownBundleID == "com.apple.Music" {
                self.isLiked = appleMusic.isTrackLiked()
                self.shuffleState = appleMusic.getShuffleState()
                self.repeatState = appleMusic.getRepeatState()
                searchDebouncer.debounce {
                    Task { @MainActor in
                        if let spotifyTrack = await self.searchForTrack(title: currentTitle, artist: currentArtist) {
                            self.fetchedSpotifyPopularity = spotifyTrack.popularity
                        }
                    }
                }
            } else if self.lastKnownBundleID == "com.spotify.client" {
                await fetchSpotifyTrackDetails(title: currentTitle, artist: currentArtist)
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

    private func fetchSpotifyTrackDetails(title: String, artist: String) async {
        guard let track = await searchForTrack(title: title, artist: artist) else { return }

        self.uri = track.uri
        self.trackID = track.id
        self.popularity = track.popularity

        if let artworkUrlString = track.album.images.first?.url, let url = URL(string: artworkUrlString) {
             self.artworkURL = url
        }

        if spotifyPrivateAPI.isLoggedIn {
            if let details = await spotifyPrivateAPI.fetchTrackDetails(trackId: track.id) {
                self.playCount = details.playcount
            }
            if let likedResult: [Bool] = try? await spotifyPrivateAPI.pathfinderQuery(operationName: "getTracksLiked", variables: ["uris": [track.uri]], sendAsBody: false) {
                self.isLiked = likedResult.first ?? false
            }
            self.shuffleState = spotifyPrivateAPI.playerState?.options?.shufflingContext ?? false
            let repeatingContext = spotifyPrivateAPI.playerState?.options?.repeatingContext ?? false
            let repeatingTrack = spotifyPrivateAPI.playerState?.options?.repeatingTrack ?? false
            if repeatingTrack { self.repeatState = .track }
            else if repeatingContext { self.repeatState = .context }
            else { self.repeatState = .off }

        } else if spotifyOfficialAPI.isAuthenticated {
            if let liked = await spotifyOfficialAPI.checkIfTrackIsLiked(id: track.id) {
                self.isLiked = liked
            }
            if let playbackState = await spotifyOfficialAPI.fetchPlaybackState() {
                self.shuffleState = playbackState.shuffleState
                self.repeatState = RepeatMode(rawValue: playbackState.repeatState) ?? .off
            }
        }

        if self.playCount == nil, let count = await PlayCountFetcher.shared.getPlayCount(for: track.id) {
            self.playCount = count
        }
    }

    // MARK: - Helper methods from former MusicWidget

    func showTransientIcon(for icon: WaveformView.TransientIcon, duration: TimeInterval = 2.0) {
        transientIconTimer?.invalidate()
        transientIcon = icon
        transientIconTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            if self?.transientIcon == icon {
                self?.transientIcon = nil
            }
        }
    }

    private func setupDerivedStatePublisher() {
        $title.map { $0 != nil && !$0!.isEmpty }.removeDuplicates().assign(to: \.shouldShowLiveActivity, on: self).store(in: &cancellables)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleMediaKeyPlayPause), name: .mediaKeyPlayPausePressed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMediaKeyNext), name: .mediaKeyNextPressed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMediaKeyPrevious), name: .mediaKeyPreviousPressed, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppTermination(notification:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    private func setupSettingsObserver() {
        settingsModel.$settings.map { ($0.enableLyricTranslation, $0.lyricTranslationLanguage) }.removeDuplicates { $0 == $1 }.debounce(for: .seconds(0.5), scheduler: DispatchQueue.main).sink { [weak self] _ in self?.retranslateLyricsIfNeeded() }.store(in: &cancellables)
    }

    private func normalizeBundleID(_ bundleID: String?) -> String? {
        guard let bundleID = bundleID else { return nil }

        switch bundleID {
        case "com.apple.WebKit.GPU", "com.apple.WebKit.WebContent":
            return "com.apple.Safari"
        case let id where id.starts(with: "com.google.Chrome.helper"):
            return "com.google.Chrome"
        case let id where id.starts(with: "com.microsoft.edgemac.helper"):
            return "com.microsoft.edgemac"
        default:
            return bundleID
        }
    }

    private func setupHandlers() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor in
                guard let self = self else { return }
                guard let trackInfo = trackInfo else {
                    self.clearPlayerState()
                    return
                }
                let payload = trackInfo.payload

                guard let title = payload.title, !title.isEmpty else { self.clearPlayerState(); return }

                let rawSourceBundleID = payload.bundleIdentifier
                let sourceBundleID = self.normalizeBundleID(rawSourceBundleID) ?? "N/A"

                let preferredSource = self.settingsModel.settings.mediaSource
                let prioritize = self.settingsModel.settings.prioritizeMediaSource

                var shouldProcessUpdate = true
                if prioritize && preferredSource != .system {
                    let isFromPreferredSource = (preferredSource == .spotify && sourceBundleID == "com.spotify.client") || (preferredSource == .appleMusic && sourceBundleID == "com.apple.Music")
                    if !isFromPreferredSource {
                        if (self.title != nil && !self.title!.isEmpty) {
                            var isPreferredAppRunning = false
                            switch preferredSource {
                            case .spotify: isPreferredAppRunning = self.spotifyAppleScript.isAppRunning()
                            case .appleMusic: isPreferredAppRunning = self.appleMusic.isAppRunning()
                            default: break
                            }
                            if isPreferredAppRunning { shouldProcessUpdate = false }
                        }
                    }
                } else if !prioritize && preferredSource != .system {
                    let isFromSpotify = preferredSource == .spotify && sourceBundleID == "com.spotify.client"
                    let isFromAppleMusic = preferredSource == .appleMusic && sourceBundleID == "com.apple.Music"
                    if isFromSpotify { shouldProcessUpdate = self.spotifyAppleScript.isAppRunning() }
                    else if isFromAppleMusic { shouldProcessUpdate = self.appleMusic.isAppRunning() }
                    else { shouldProcessUpdate = false }
                }

                guard shouldProcessUpdate else { return }

                let hasTrackChanged = payload.title != self.lastFetchedTitle

                if hasTrackChanged {
                    self.resetLyricsState()
                    self.lastFetchedTitle = payload.title
                }

                self.title = payload.title; self.artist = payload.artist; self.album = payload.album

                if hasTrackChanged {
                    self.triggerQuickPeek()
                    self.lastTrackChangeDate = Date()
                    self.fetchAndTranslateLyricsIfNeeded()
                    self.trackDidChange.send()
                }

                if let newArtwork = payload.artwork {
                    if self.artwork?.tiffRepresentation != newArtwork.tiffRepresentation {
                        self.artwork = newArtwork
                        self.artworkURL = nil
                        if let edgeColors = newArtwork.getEdgeColors() { self.accentColor = edgeColors.accent; self.leftGradientColor = edgeColors.left; self.rightGradientColor = edgeColors.right }
                        else { self.resetColorsToDefault() }
                    }
                } else {
                    self.artwork = nil;
                    self.artworkURL = nil
                    self.resetColorsToDefault()
                }

                if let newIsPlaying = payload.isPlaying { self.isPlaying = newIsPlaying }
                self.currentTrackDuration = TimeInterval(payload.durationMicros ?? 0) / 1_000_000
                self.totalDuration = self.currentTrackDuration

                if sourceBundleID != self.lastKnownBundleID {
                    self.lastKnownBundleID = sourceBundleID
                    self.fetchAppIcon(for: sourceBundleID)
                    self.updateDevicePolling()
                }
            }
        }

        mediaController.onPlaybackTimeUpdate = { [weak self] elapsedTime in
            Task { @MainActor in
                guard let self = self, self.currentTrackDuration > 0 else { return }
                let progress = self.totalDuration > 0 ? max(0.0, min(1.0, elapsedTime / self.totalDuration)) : 0.0
                self.playbackProgress = progress; self.currentElapsedTime = elapsedTime
                self.playbackTimePublisher.send((elapsed: elapsedTime, progress: progress))
                self.updateCurrentLyric(for: elapsedTime)
            }
        }
        mediaController.onListenerTerminated = { print("[MusicManager] The media listener process was terminated.") }
        mediaController.onDecodingError = { error, data in print("[MusicManager] Decoding Error: \(error)") }
    }

    private func clearPlayerState() {
        self.title = nil; self.artist = nil; self.album = nil
        self.artwork = nil
        self.artworkURL = nil
        self.uri = nil; self.trackID = nil; self.popularity = nil; self.playCount = nil
        self.fetchedSpotifyPopularity = nil
        self.isPlaying = false; self.totalDuration = 0; self.currentElapsedTime = 0
        self.resetLyricsState()
    }

    private func triggerQuickPeek() {
        guard settingsModel.settings.showQuickPeekOnTrackChange else { return }
        quickPeekTimer?.invalidate()
        self.showQuickPeek = true
        quickPeekTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in self?.showQuickPeek = false }
    }

    private func updateDevicePolling() {
        airplayDeviceUpdateTimer?.invalidate()
        if lastKnownBundleID == "com.apple.Music" {
            airplayDeviceUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in Task { await self?.updateAirPlayDevices() } }
            airplayDeviceUpdateTimer?.fire()
        }
    }

    func updateAirPlayDevices() async { self.airplayDevices = await appleMusic.fetchAirPlayDevices() }

    func openInSourceApp() {
        let browserBundleIDs = ["com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.apple.Safari"]

        guard let bundleId = lastKnownBundleID else {
            return
        }

        if bundleId == "com.apple.Music" {
            appleMusic.revealCurrentTrack()
            return
        }

        if browserBundleIDs.contains(bundleId) {
            guard let trackTitle = self.title else {
                print("[MusicManager] No track title available for browser. Activating app as fallback.")
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    NSWorkspace.shared.open(appURL)
                }
                return
            }
            browserAppleScript.focusTab(for: bundleId, with: trackTitle)
            return
        }

        if let uriString = self.uri, let url = URL(string: uriString) {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open(appURL)
        }
    }

    private func setupVolumeListener() {
        self.systemVolume = SystemControl.getVolume()
        guard let deviceID = getDefaultOutputDeviceID() else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        self.volumeListener = { _, _ in DispatchQueue.main.async { let newVolume = SystemControl.getVolume(); self.systemVolume = newVolume; self.volumePublisher.send(newVolume) } }
        AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, self.volumeListener!)
    }

    private func removeVolumeListener() {
        guard let deviceID = getDefaultOutputDeviceID(), let listener = self.volumeListener else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, listener)
    }

    private func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = kAudioObjectUnknown, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr ? deviceID : nil
    }

    private func fetchAppIcon(for bundleIdentifier: String?) {
        guard let bundleId = bundleIdentifier, !bundleId.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { self.appIcon = nil; return }
        self.appIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    private func resetLyricsState() {
        lyricsFetchTask?.cancel()
        lyrics = []
        currentLyric = nil
        currentLyricIndex = nil
        currentLyricPublisher.send(nil)
    }

    private func fetchAndTranslateLyricsIfNeeded() {
        guard let title = self.title, let artist = self.artist, let album = self.album else { return }
        self.resetLyricsState()
        lyricsFetchTask = Task {
            guard let fetchedLyrics = await lyricsFetcher.fetchSyncedLyrics(for: title, artist: artist, album: album), !fetchedLyrics.isEmpty, !Task.isCancelled else { return }
            await MainActor.run {
                self.lyrics = fetchedLyrics
                self.retranslateLyricsIfNeeded()
            }
        }
    }

    private func retranslateLyricsIfNeeded() {
        Task {
            guard !self.lyrics.isEmpty else { return }
            var lyricsToUpdate = self.lyrics
            if !settingsModel.settings.enableLyricTranslation {
                for i in 0..<lyricsToUpdate.count { lyricsToUpdate[i].translatedText = nil }
                self.lyrics = lyricsToUpdate; return
            }
            let sampleText = lyricsToUpdate.prefix(5).map { $0.text }.joined(separator: " ")
            guard !sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let lang = await lyricsFetcher.detectLanguage(for: sampleText) else { return }
            let targetLanguage = settingsModel.settings.lyricTranslationLanguage
            if lang != targetLanguage { await lyricsFetcher.translate(lyrics: &lyricsToUpdate, from: lang, to: targetLanguage); self.lyrics = lyricsToUpdate }
        }
    }

    private func updateCurrentLyric(for elapsedTime: TimeInterval) {
        guard !lyrics.isEmpty else { return }
        let startIndex = currentLyricIndex ?? 0; var newLyricIndex: Int? = nil
        if elapsedTime >= (currentLyric?.timestamp ?? 0) {
            for i in startIndex..<lyrics.count { if lyrics[i].timestamp <= elapsedTime { newLyricIndex = i } else { break } }
        } else { newLyricIndex = lyrics.lastIndex { $0.timestamp <= elapsedTime } }
        if newLyricIndex != self.currentLyricIndex {
            self.currentLyricIndex = newLyricIndex; let newLyric = newLyricIndex != nil ? lyrics[newLyricIndex!] : nil
            if self.currentLyric?.id != newLyric?.id {
                self.currentLyric = newLyric; self.currentLyricPublisher.send(newLyric)
            }
        }
    }

    private func resetColorsToDefault() {
        let defaultAccent = Color(red: 0.53, green: 0.73, blue: 0.88)
        self.accentColor = defaultAccent; self.leftGradientColor = defaultAccent; self.rightGradientColor = defaultAccent.opacity(0.7)
    }

    @objc private func handleMediaKeyPlayPause() {
        if settingsModel.settings.defaultMusicPlayer == .spotify && !isPlaying {
            Task { @MainActor in
                if !spotifyAppleScript.isAppRunning() {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                        NSWorkspace.shared.open(url)
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                }

                let script = "tell application \"Spotify\" to play"
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: script) {
                    scriptObject.executeAndReturnError(&error)
                }
            }
        }
    }

    @objc private func handleMediaKeyNext() { showTransientIcon(for: .skippedForward) }
    @objc private func handleMediaKeyPrevious() { showTransientIcon(for: .skippedBackward) }

    @objc private func handleAppTermination(notification: NSNotification) {
        guard let terminatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let terminatedBundleID = terminatedApp.bundleIdentifier else { return }
        let preferredSource = settingsModel.settings.mediaSource; let shouldReact: Bool
        switch preferredSource {
        case .spotify: shouldReact = (terminatedBundleID == "com.spotify.client")
        case .appleMusic: shouldReact = (terminatedBundleID == "com.apple.Music")
        case .system: shouldReact = false
        }
        if shouldReact {
            Task { @MainActor in
                print("[MusicManager] Preferred media source '\(terminatedBundleID)' was terminated. Clearing state.")
                self.clearPlayerState(); self.mediaController.stop(); self.mediaController.startListening()
            }
        }
    }
}