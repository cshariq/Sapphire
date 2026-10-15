//
//  LiveActivityManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04
//

import Foundation
import AppKit
import SwiftUI
import Combine
import EventKit
import NearbyShare
import OSLog

// MARK: - Enums and Structs

private struct SystemHUDIdentifier: Hashable {
    let type: HUDType
    let style: HUDStyle
}

private struct WeatherLiveActivitySettings: Equatable {
    let isEnabled: Bool
    let isPersistent: Bool

    init(_ settings: Settings) {
        isEnabled = settings.weatherLiveActivityEnabled
        isPersistent = settings.showPersistentWeatherLiveActivity
    }
}

private struct LiveActivityEvaluationSettings: Equatable {
    let defaultFullScreenBehavior: FullScreenBehavior
    let perDisplayFullScreenBehavior: [String: FullScreenBehavior]
    let hideActivitiesInFullScreen: [String: Bool]
    let liveActivityOrder: [LiveActivityType]
    let showLiveActivitySatellites: Bool
    let liveActivitySatelliteLimit: Int
    let showUpdateAvailableLiveActivity: Bool
    let devActivityEnabled: Bool
    let devActivityHighPriority: Bool
    let statsLiveActivityEnabled: Bool
    let statsLiveActivityThresholdEnabled: Bool
    let showPersistentStatsLiveActivity: Bool
    let statThresholds: [StatType: StatThreshold]
    let batteryLiveActivityEnabled: Bool
    let showPersistentBatteryLiveActivity: Bool
    let lowBatteryNotificationPercentage: Int
    let lowBatteryNotificationSoundEnabled: Bool
    let batteryNotificationStyle: BatteryNotificationStyle
    let promptForLowPowerMode: Bool
    let weatherLiveActivityEnabled: Bool
    let showPersistentWeatherLiveActivity: Bool
    let weatherLiveActivityInterval: Int
    let capsLockLiveActivityEnabled: Bool
    let musicLiveActivityEnabled: Bool
    let continuityPhoneMediaLiveActivityEnabled: Bool
    let musicLiveActivityRightTextMode: MusicLiveActivityRightTextMode
    let musicLiveActivityWaveformMode: MusicLiveActivityWaveformMode
    let musicLiveActivityWaveformStyle: MusicLiveActivityWaveformStyle
    let enableQuickPeekOnHover: Bool
    let showLyricsInLiveActivity: Bool
    let spotifyShowNextSong: Bool
    let spotifyShowNextSongAlbumArt: Bool
    let calendarLiveActivityEnabled: Bool
    let remindersLiveActivityEnabled: Bool
    let timersLiveActivityEnabled: Bool
    let focusSessionLiveActivityEnabled: Bool
    let fileShelfLiveActivityEnabled: Bool
    let eyeBreakLiveActivityEnabled: Bool
    let desktopLiveActivityEnabled: Bool
    let focusLiveActivityEnabled: Bool
    let fileProgressLiveActivityEnabled: Bool
    let microphoneLiveActivityEnabled: Bool
    let otpLiveActivityEnabled: Bool
    let parcelLiveActivityEnabled: Bool
    let parcelTrackingEnabled: Bool
    let bluetoothLiveActivityEnabled: Bool
    let showBluetoothContinuityDevices: Bool
    let continuityEnabled: Bool
    let continuityStatusLiveActivityEnabled: Bool
    let continuityNotifications: Bool
    let continuityExternalLiveActivities: Bool
    let sportsLiveActivityEnabled: Bool
    let sportsCommentaryInLiveActivity: Bool
    let sportsLiveActivityWhenLiveOnly: Bool
    let sportsFavoriteTeams: [String]
    let financeLiveActivityEnabled: Bool
    let financeLiveActivityActiveHoursOnly: Bool
    let financeFavoriteSymbols: [String]
    let financeFavoriteSymbolIndex: Int
    let enableVolumeHUD: Bool
    let effectiveVolumeHUDStyle: HUDStyle
    let enableBrightnessHUD: Bool
    let effectiveBrightnessHUDStyle: HUDStyle

    init(_ settings: Settings) {
        defaultFullScreenBehavior = settings.defaultFullScreenBehavior
        perDisplayFullScreenBehavior = settings.perDisplayFullScreenBehavior
        hideActivitiesInFullScreen = settings.hideActivitiesInFullScreen
        liveActivityOrder = settings.liveActivityOrder
        showUpdateAvailableLiveActivity = settings.showUpdateAvailableLiveActivity
        devActivityEnabled = settings.devActivityEnabled
        devActivityHighPriority = settings.devActivityHighPriority
        statsLiveActivityEnabled = settings.statsLiveActivityEnabled
        statsLiveActivityThresholdEnabled = settings.statsLiveActivityThresholdEnabled
        showPersistentStatsLiveActivity = settings.showPersistentStatsLiveActivity
        statThresholds = settings.statThresholds
        batteryLiveActivityEnabled = settings.batteryLiveActivityEnabled
        showPersistentBatteryLiveActivity = settings.showPersistentBatteryLiveActivity
        lowBatteryNotificationPercentage = settings.lowBatteryNotificationPercentage
        lowBatteryNotificationSoundEnabled = settings.lowBatteryNotificationSoundEnabled
        batteryNotificationStyle = settings.batteryNotificationStyle
        promptForLowPowerMode = settings.promptForLowPowerMode
        weatherLiveActivityEnabled = settings.weatherLiveActivityEnabled
        showPersistentWeatherLiveActivity = settings.showPersistentWeatherLiveActivity
        weatherLiveActivityInterval = settings.weatherLiveActivityInterval
        capsLockLiveActivityEnabled = settings.capsLockLiveActivityEnabled
        musicLiveActivityEnabled = settings.musicLiveActivityEnabled
        continuityPhoneMediaLiveActivityEnabled = settings.continuityPhoneMediaLiveActivityEnabled
        musicLiveActivityRightTextMode = settings.musicLiveActivityRightTextMode
        musicLiveActivityWaveformMode = settings.musicLiveActivityWaveformMode
        musicLiveActivityWaveformStyle = settings.musicLiveActivityWaveformStyle
        enableQuickPeekOnHover = settings.enableQuickPeekOnHover
        showLyricsInLiveActivity = settings.showLyricsInLiveActivity
        spotifyShowNextSong = settings.spotifyShowNextSong
        spotifyShowNextSongAlbumArt = settings.spotifyShowNextSongAlbumArt
        calendarLiveActivityEnabled = settings.calendarLiveActivityEnabled
        remindersLiveActivityEnabled = settings.remindersLiveActivityEnabled
        timersLiveActivityEnabled = settings.timersLiveActivityEnabled
        focusSessionLiveActivityEnabled = settings.focusSessionLiveActivityEnabled
        fileShelfLiveActivityEnabled = settings.fileShelfLiveActivityEnabled
        eyeBreakLiveActivityEnabled = settings.eyeBreakLiveActivityEnabled
        desktopLiveActivityEnabled = settings.desktopLiveActivityEnabled
        focusLiveActivityEnabled = settings.focusLiveActivityEnabled
        fileProgressLiveActivityEnabled = settings.fileProgressLiveActivityEnabled
        microphoneLiveActivityEnabled = settings.microphoneLiveActivityEnabled
        otpLiveActivityEnabled = settings.otpLiveActivityEnabled
        parcelLiveActivityEnabled = settings.parcelLiveActivityEnabled
        parcelTrackingEnabled = settings.parcelTrackingEnabled
        bluetoothLiveActivityEnabled = settings.bluetoothLiveActivityEnabled
        showBluetoothContinuityDevices = settings.showBluetoothContinuityDevices
        continuityEnabled = settings.continuityEnabled
        continuityStatusLiveActivityEnabled = settings.continuityStatusLiveActivityEnabled
        continuityNotifications = settings.continuityNotifications
        continuityExternalLiveActivities = settings.continuityExternalLiveActivities
        sportsLiveActivityEnabled = settings.sportsLiveActivityEnabled
        sportsCommentaryInLiveActivity = settings.sportsCommentaryInLiveActivity
        sportsLiveActivityWhenLiveOnly = settings.sportsLiveActivityWhenLiveOnly
        sportsFavoriteTeams = settings.sportsFavoriteTeams
        financeLiveActivityEnabled = settings.financeLiveActivityEnabled
        financeLiveActivityActiveHoursOnly = settings.financeLiveActivityActiveHoursOnly
        financeFavoriteSymbols = settings.financeFavoriteSymbols
        financeFavoriteSymbolIndex = settings.financeFavoriteSymbolIndex
        enableVolumeHUD = settings.enableVolumeHUD
        effectiveVolumeHUDStyle = settings.effectiveVolumeHUDStyle
        enableBrightnessHUD = settings.enableBrightnessHUD
        effectiveBrightnessHUDStyle = settings.effectiveBrightnessHUDStyle
        showLiveActivitySatellites = settings.showLiveActivitySatellites
        liveActivitySatelliteLimit = settings.liveActivitySatelliteLimit
    }
}

struct NotchSatelliteActivity: Equatable {
    let type: ActivityType
    let content: LiveActivityContent

    static func == (lhs: NotchSatelliteActivity, rhs: NotchSatelliteActivity) -> Bool {
        guard lhs.type == rhs.type else { return false }
        return lhs.type == .fileProgress ? lhs.content == rhs.content : true
    }
}

enum LiveActivityHoverExpansionPolicy {
    static func shouldSuppress(activity: ActivityType) -> Bool {
        switch activity {
        case .none,
             .persistentBattery,
             .persistentStats,
             .persistentWeather,
             .music,
             .weather,
             .stats,
             .devActivity:
            return false
        default:
            return true
        }
    }
}

enum FullScreenActivityVisibilityPolicy {
    static let persistentActivities: Set<ActivityType> = [
        .music, .continuityMedia, .timer, .fileShelf, .continuity,
        .persistentBattery, .persistentStats, .persistentWeather,
        .devActivity, .focusSession, .intelligenceAgent, .sports, .finance, .appActivity
    ]

    private static let ungated: Set<ActivityType> = [.none, .lockScreen, .unlocked]

    static func hides(
        _ activity: ActivityType,
        behavior: FullScreenBehavior,
        selectedActivityTypes: [String: Bool],
        isAlerting: Bool = false
    ) -> Bool {
        guard !ungated.contains(activity) else { return false }
        switch behavior.activityVisibility {
        case .showAll:
            return false
        case .hideAll:
            return true
        case .hidePersistent:
            return !isAlerting && persistentActivities.contains(activity)
        case .hideSelected:
            guard let settingsType = activity.toLiveActivityType() else { return false }
            return selectedActivityTypes[settingsType.rawValue] == true
        }
    }
}

// MARK: - LiveActivityManager

@MainActor
@Observable
class LiveActivityManager {

    // MARK: - Published Properties
    private(set) var contentUpdateID = UUID()
    private(set) var currentActivity: ActivityType = .none
    private(set) var activityContent: LiveActivityContent = .none
    private(set) var satelliteActivities: [NotchSatelliteActivity] = []
    private(set) var currentNearbyTransferPayload: NearbyTransferPayload?
    private(set) var currentGeminiPayload: GeminiPayload?
    private(set) var isScreenLocked: Bool = false
    var isNotificationHovered: Bool = false

    // MARK: - Public Properties
    var isFullViewActivity: Bool {
        if case .full = activityContent { true } else { false }
    }

    func effectiveActivity(on screen: NSScreen?) -> ActivityType {
        effectiveActivity(onDisplayID: screen?.displayID)
    }

    func effectiveActivity(onDisplayID displayID: CGDirectDisplayID?) -> ActivityType {
        guard currentActivity != .none else { return .none }
        guard let displayID else { return currentActivity }

        if isHiddenInFullScreen(currentActivity, onDisplayID: displayID) {
            return .none
        }

        if Self.displayAnchoredActivityTypes.contains(currentActivity),
           let anchorDisplayID = activityAnchorDisplayID,
           anchorDisplayID != displayID {
            return .none
        }

        return currentActivity
    }

    var isCurrentActivityVisibleOnAnyDisplay: Bool {
        guard currentActivity != .none else { return false }
        return NSScreen.screens.contains { effectiveActivity(on: $0) != .none }
    }

    private(set) var fullScreenDisplayIDs: Set<CGDirectDisplayID> = []

    @ObservationIgnored private var lastFullScreenGateDescription: String?

    private func notchDisplaysAreFullScreen() -> Bool {
        let fullScreenDisplays = fullScreenDisplayIDs
        guard !fullScreenDisplays.isEmpty else { return false }
        let notchDisplays = notchDisplayIDs()
        guard !notchDisplays.isEmpty else { return false }
        return notchDisplays.isSubset(of: fullScreenDisplays)
    }

    private func lyricsOverlapFullScreenApp() -> Bool {
        guard !fullScreenDisplayIDs.isEmpty else { return false }
        return notchDisplayIDs().contains { fullScreenBehavior(onDisplayID: $0)?.hideLyrics == true }
    }

    private func notchDisplayIDs() -> Set<CGDirectDisplayID> {
        let windows = (NSApp.delegate as? AppDelegate)?.notchWindows ?? []
        return Set(windows.compactMap { ($0 as? DynamicFocusWindow)?.displayID }.filter { $0 != 0 })
    }

    func fullScreenBehavior(onDisplayID displayID: CGDirectDisplayID) -> FullScreenBehavior? {
        guard fullScreenDisplayIDs.contains(displayID) else { return nil }
        let key = NSScreen.screens.first { $0.displayID == displayID }?.displayIdentifier
        return settingsModel.settings.resolvedFullScreenBehavior(forDisplayID: key)
    }

    private func isHiddenInFullScreen(_ activityType: ActivityType, onDisplayID displayID: CGDirectDisplayID) -> Bool {
        guard let behavior = fullScreenBehavior(onDisplayID: displayID) else { return false }
        return FullScreenActivityVisibilityPolicy.hides(
            activityType,
            behavior: behavior,
            selectedActivityTypes: settingsModel.current.hideActivitiesInFullScreen,
            isAlerting: activityType == .timer && timerManager.hasRingingTimer
        )
    }

    private func isHiddenInFullScreenOnEveryNotchDisplay(_ activityType: ActivityType) -> Bool {
        let displays = notchDisplayIDs()
        guard !displays.isEmpty else { return false }
        return displays.allSatisfy { isHiddenInFullScreen(activityType, onDisplayID: $0) }
    }

    private func notchDisplaysHideAllActivities() -> Bool {
        let displays = notchDisplayIDs()
        guard !displays.isEmpty else { return false }
        return displays.allSatisfy { fullScreenBehavior(onDisplayID: $0)?.activityVisibility == .hideAll }
    }

    private func logFullScreenGateIfChanged(isFullScreen: Bool) {
        let settings = settingsModel.settings
        let hiddenTypes = settings.hideActivitiesInFullScreen.filter(\.value).keys.sorted().joined(separator: ",")
        let fullScreen = fullScreenDisplayIDs.sorted().map(String.init).joined(separator: ",")
        let notch = notchDisplayIDs().sorted().map { id in
            "\(id):\(fullScreenBehavior(onDisplayID: id)?.activityVisibility.rawValue ?? "-")"
        }.joined(separator: ",")
        let description = "notchFullScreen=\(isFullScreen) default=\(settings.fullScreenActivityVisibility.rawValue) selectedTypes=[\(hiddenTypes)] fullScreenDisplays=[\(fullScreen)] notchDisplays=[\(notch)]"
        guard description != lastFullScreenGateDescription else { return }
        lastFullScreenGateDescription = description
        logger.info("full-screen gate: \(description, privacy: .public)")
    }

    private static let displayAnchoredActivityTypes: Set<ActivityType> = [.systemHUD]

    private(set) var activityAnchorDisplayID: CGDirectDisplayID?

    // MARK: - Private Properties
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "LiveActivityManager")
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var dismissalTimer: Timer?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    typealias ActivityCandidate = (ActivityType, LiveActivityContent, TimeInterval?)

    @ObservationIgnored private var activityCheckers: [ActivityType: () -> ActivityCandidate?] = [:]
    @ObservationIgnored private var snoozedActivities: [ActivityType: Date] = [:]
    private let snoozableActivityTypes: Set<ActivityType> = [
        .persistentBattery,
        .weather,
        .timer,
        .calendar,
        .reminder,
        .fileShelf,
        .updateAvailable,
        .persistentStats,
        .persistentWeather
    ]
    private let ephemeralActivityTypes: Set<ActivityType> = [
        .desktopChange,
        .bluetooth,
        .audioSwitch,
        .focusModeChange,
        .battery,
        .stats,
        .capsLock,
    ]
    @ObservationIgnored private var dismissedNotifications: [AnyHashable: Date] = [:]
    @ObservationIgnored private var lastIntervalWeatherShowTime: Date?
    @ObservationIgnored private var lastWeatherLiveActivityEnabled: Bool?
    @ObservationIgnored private var lastPersistentWeatherLiveActivityEnabled: Bool?
    @ObservationIgnored private var tickerRefreshTimer: Timer?
    @ObservationIgnored private var tickerFetchTick = 0
    @ObservationIgnored private var sportsFinanceWatchTimer: Timer?
    @ObservationIgnored private var lastKnownFocusStatus: FocusStatus?
    @ObservationIgnored private var hasShownPluggedInAlert = false
    @ObservationIgnored private var hasShownLowBatteryAlert = false
    @ObservationIgnored private var hasShownCurrentEyeBreak = false
    @ObservationIgnored private var lastShownDesktopNumber: Int?
    @ObservationIgnored private var lastShownFocusModeID: String?
    @ObservationIgnored private var lastShownBluetoothEvent: BluetoothDeviceState?
    @ObservationIgnored private var lastShownAudioSwitchEventID: UUID?
    @ObservationIgnored private var lastShownContinuityStatusKey: String?
    @ObservationIgnored private var continuityStatusKeySeen: String?
    @ObservationIgnored private var continuityStatusChangedAt: Date = .distantPast
    @ObservationIgnored private var isDismissingPausedMusic = false
    @ObservationIgnored private var musicPausedSince: Date?
    @ObservationIgnored private var pausedMusicExpiryWork: DispatchWorkItem?
    private static let pausedMusicGracePeriod: TimeInterval = 30
    @ObservationIgnored private var sportsActivityTeamIndex: Int = 0
    private enum CalendarNotificationMilestone { case oneDay, thirtyMinutes }
    @ObservationIgnored private var notifiedEventMilestones: [CalendarOccurrenceKey: Set<CalendarNotificationMilestone>] = [:]
    private enum ReminderNotificationMilestone { case thirtyMinutes }
    @ObservationIgnored private var notifiedReminderMilestones: [String: Set<ReminderNotificationMilestone>] = [:]

    @ObservationIgnored private var hasReceivedInitialFocusStatus = false
    @ObservationIgnored private var lastShownBatteryManagementState: ManagementState?
    @ObservationIgnored private var lastLyricContentID: AnyHashable?
    @ObservationIgnored private var lyricContentUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var lastMusicLiveActivityTick: CFAbsoluteTime = 0
    @ObservationIgnored private var capsLockTapToken: GlobalEventTap.Token?
    @ObservationIgnored private var lastCapsLockState = false
    @ObservationIgnored private var capsLockActivationID: UUID?
    @ObservationIgnored public var intelligenceVM: IntelligenceNotchViewModel?

    // MARK: - Dependencies
    private let systemHUDManager: SystemHUDManager, notificationManager: NotificationManager, desktopManager: DesktopManager, focusModeManager: FocusModeManager, musicWidget: MusicManager, calendarService: CalendarService, batteryMonitor: BatteryMonitor, bluetoothManager: BluetoothManager, audioDeviceManager: AudioDeviceManager, eyeBreakManager: EyeBreakManager, timerManager: TimerManager, weatherActivityViewModel: WeatherActivityViewModel, geminiLiveManager: GeminiLiveManager, settingsModel: SettingsModel, activeAppMonitor: ActiveAppMonitor, batteryEstimator: BatteryEstimator, batteryStatusManager: BatteryStatusManager

    private let devActivityMonitor = DevActivityMonitor.shared

    // MARK: - Initialization
    init(
        systemHUDManager: SystemHUDManager,
        notificationManager: NotificationManager,
        desktopManager: DesktopManager,
        focusModeManager: FocusModeManager,
        musicWidget: MusicManager,
        calendarService: CalendarService,
        batteryMonitor: BatteryMonitor,
        bluetoothManager: BluetoothManager,
        audioDeviceManager: AudioDeviceManager,
        eyeBreakManager: EyeBreakManager,
        timerManager: TimerManager,
        weatherActivityViewModel: WeatherActivityViewModel,
        geminiLiveManager: GeminiLiveManager,
        settingsModel: SettingsModel,
        activeAppMonitor: ActiveAppMonitor,
        batteryEstimator: BatteryEstimator,
        batteryStatusManager: BatteryStatusManager,
        intelligenceVM: IntelligenceNotchViewModel? = nil
    ) {
        self.systemHUDManager = systemHUDManager; self.notificationManager = notificationManager; self.desktopManager = desktopManager; self.focusModeManager = focusModeManager; self.musicWidget = musicWidget; self.calendarService = calendarService; self.batteryMonitor = batteryMonitor; self.bluetoothManager = bluetoothManager; self.audioDeviceManager = audioDeviceManager; self.eyeBreakManager = eyeBreakManager; self.timerManager = timerManager; self.weatherActivityViewModel = weatherActivityViewModel; self.geminiLiveManager = geminiLiveManager; self.settingsModel = settingsModel; self.activeAppMonitor = activeAppMonitor; self.batteryEstimator = batteryEstimator; self.batteryStatusManager = batteryStatusManager
        self.intelligenceVM = intelligenceVM
        self.lastShownDesktopNumber = desktopManager.currentDesktopNumber
        self.lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)
        self.activityCheckers = [
            .lockScreen: { self.checkForLockScreenActivity() },
            .capsLock: { self.checkForCapsLockActivity() },
            .updateAvailable: { self.checkForUpdateAvailable() },
            .nearbyShare: { self.checkForNearbyTransfer() },
            .geminiLive: { self.checkForGeminiLive() },
            .microphone: { self.checkForMicrophone() },
            .appActivity: { self.checkForAppActivity() },
            .otp: { self.checkForOTP() },
            .notification: { self.checkForNotification() },
            .continuityNotification: { self.checkForContinuityNotification() },
            .parcel: { self.checkForParcel() },
            .fileProgress: { self.checkForFileProgress() },
            .eyeBreak: { self.checkForEyeBreak() },
            .audioSwitch: { self.checkForAudioSwitch() },
            .bluetooth: { self.checkForBluetooth() },
            .focusModeChange: { self.checkForFocusMode() },
            .calendar: { self.checkForCalendar() },
            .reminder: { self.checkForReminder() },
            .battery: { self.checkForBatteryAlert() },
            .desktopChange: { self.checkForDesktopChange() },
            .timer: { self.checkForTimer() },
            .music: { self.checkForMusic() },
            .fileShelf: { self.checkForFileShelf() },
            .weather: { self.checkForWeather() },
            .stats: { self.checkForStatsThresholdActivity() },
            .intelligenceAgent: { self.checkForIntelligenceAgent() },
            .devActivity: { self.checkForDevActivity() },
            .sports: { self.checkForSports() },
            .finance: { self.checkForFinance() },
        ]
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        setupSubscriptions()
        syncCapsLockMonitoring()
        updateSportsFinanceWatchTimer()
        lastEvalTime = 0
        evaluateAndDisplayActivity()
        scheduleInitialUpdateActivityEvaluationIfNeeded()
        #if DEBUG
        installDebugActivityHook()
        #endif
    }

    #if DEBUG
    private var debugActivityObserver: NSObjectProtocol?

    private func installDebugActivityHook() {
        guard debugActivityObserver == nil else { return }
        debugActivityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.cshariq.sapphire.debug.activity"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let name = notification.object as? String
            MainActor.assumeIsolated { self?.showDebugActivity(name) }
        }
    }

    private func showDebugActivity(_ name: String?) {
        let candidate: (ActivityType, LiveActivityContent, TimeInterval?)?
        switch name {
        case "capsLock": candidate = (.capsLock, .standard(data: .capsLock, id: UUID().uuidString), nil)
        case "unlocked": candidate = (.unlocked, .standard(data: .unlocked, id: "unlock_activity"), nil)
        case "music": candidate = checkForMusic()
        case "weather": candidate = checkForPersistentWeather() ?? checkForWeather()
        case "battery": candidate = checkForPersistentBattery()
        default: candidate = (.none, .none, nil)
        }
        guard let (type, content, duration) = candidate else { return }
        setActivity(type: type, content: content, dismissAfter: duration)
    }
    #endif

    func stop() {
        guard hasStarted else { return }
        hasStarted = false

        cancellables.removeAll()
        dismissalTimer?.invalidate()
        dismissalTimer = nil
        dismissGraceTimer?.invalidate()
        dismissGraceTimer = nil
        tickerRefreshTimer?.invalidate()
        tickerRefreshTimer = nil
        sportsFinanceWatchTimer?.invalidate()
        sportsFinanceWatchTimer = nil
        if let capsLockTapToken {
            GlobalEventTap.shared.unregister(capsLockTapToken)
            self.capsLockTapToken = nil
        }
        capsLockActivationID = nil

        lyricContentUpdateTask?.cancel()
        lyricContentUpdateTask = nil
        pendingEvaluationTask?.cancel()
        pendingEvaluationTask = nil

        currentActivity = .none
        activityContent = .none
        activityAnchorDisplayID = nil
        currentNearbyTransferPayload = nil
        currentGeminiPayload = nil
        isNotificationHovered = false
        contentUpdateID = UUID()
    }

    private func scheduleInitialUpdateActivityEvaluationIfNeeded() {
        guard settingsModel.current.showUpdateAvailableLiveActivity,
              UpdateChecker.shared.status.isUpdateAvailable else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lastEvalTime = 0
            self?.evaluateAndDisplayActivity()
        }
    }

    // MARK: - Subscriptions
    private func setupSubscriptions() {
        systemHUDManager.$currentHUD
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hudType in
                self?.handleHUDUpdate(hudType)
            }
            .store(in: &cancellables)

        musicWidget.valuePublisher(\.currentLyric)
            .removeDuplicates { lhs, rhs in
                lhs?.id == rhs?.id && lhs?.text == rhs?.text && lhs?.translatedText == rhs?.translatedText
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleLyricUpdate()
            }
            .store(in: &cancellables)

        musicWidget.playbackTimePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.currentActivity == .music else { return }
                let now = CFAbsoluteTimeGetCurrent()
                guard now - self.lastMusicLiveActivityTick >= 0.4 else { return }
                self.lastMusicLiveActivityTick = now
                self.refreshMusicActivityContent()
            }
            .store(in: &cancellables)

        geminiLiveManager.valuePublisher(\.isMicMuted)
            .receive(on: DispatchQueue.main)
            .sink {
                [weak self] newMuteState in guard let self,
                                                  var payload = self.currentGeminiPayload,
                                                  payload.isMicMuted != newMuteState else {
                    return
                }; payload.isMicMuted = newMuteState; self.currentGeminiPayload = payload
            }
            .store(in: &cancellables)
        MicrophoneUsageManager.shared.$isMicInUse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.evaluateAndDisplayActivity()
            }
            .store(in: &cancellables)

        devActivityMonitor.$tasks
            .map { tasks -> String in
                guard let first = tasks.first else { return "" }
                return "\(first.id)|\(first.title)|\(first.detail)|\(tasks.count)"
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.settingsModel.current.devActivityEnabled else { return }
                self.evaluateAndDisplayActivity()
            }
            .store(in: &cancellables)

        AppActivityMonitor.shared.$activities
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.settingsModel.current.appActivitiesEnabled else { return }
                self.evaluateAndDisplayActivity()
            }
            .store(in: &cancellables)

        MicrophoneUsageManager.shared.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.currentActivity == .microphone {
                    self.evaluateAndDisplayActivity()
                }
            }
            .store(in: &cancellables)
        geminiLiveManager.sessionDidEndPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.finishGeminiLive() }
            .store(in: &cancellables)
        FileDropManager.shared.$tasks
            .removeDuplicates()
            .throttle(
                for: .milliseconds(100),
                scheduler: RunLoop.main,
                latest: true
            )
            .sink { [weak self] _ in
                self?.evaluateAndDisplayActivity()
            }
            .store(in: &cancellables)

        FileShelfManager.shared.$files
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.lastEvalTime = 0
                self.evaluateAndDisplayActivity(allowImmediateDismiss: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sapphireUpdateAvailable)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.lastEvalTime = 0
                self.evaluateAndDisplayActivity()
            }
            .store(in: &cancellables)

        settingsModel.changes(of: { $0.capsLockLiveActivityEnabled })
            .prepend(settingsModel.current.capsLockLiveActivityEnabled)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncCapsLockMonitoring()
                self?.lastEvalTime = 0
                self?.evaluateAndDisplayActivity(allowImmediateDismiss: true)
            }
            .store(in: &cancellables)

        subscribeToStateChangeTriggers()
        subscribeToSportsFinanceSettings()
        subscribeToWeatherLiveActivitySettings()
    }

    private func subscribeToWeatherLiveActivitySettings() {
        let initialSettings = WeatherLiveActivitySettings(settingsModel.settings)
        handleWeatherLiveActivitySettingsChanged(
            isEnabled: initialSettings.isEnabled,
            isPersistent: initialSettings.isPersistent
        )

        settingsModel.changes(of: WeatherLiveActivitySettings.init)
            .sink { [weak self] settings in
                self?.handleWeatherLiveActivitySettingsChanged(
                    isEnabled: settings.isEnabled,
                    isPersistent: settings.isPersistent
                )
            }
            .store(in: &cancellables)
    }

    private func handleWeatherLiveActivitySettingsChanged(isEnabled: Bool, isPersistent: Bool) {
        guard let wasEnabled = lastWeatherLiveActivityEnabled,
              let wasPersistent = lastPersistentWeatherLiveActivityEnabled else {
            lastWeatherLiveActivityEnabled = isEnabled
            lastPersistentWeatherLiveActivityEnabled = isPersistent
            return
        }

        guard wasEnabled != isEnabled || wasPersistent != isPersistent else { return }

        lastWeatherLiveActivityEnabled = isEnabled
        lastPersistentWeatherLiveActivityEnabled = isPersistent

        let becameDisabled = wasEnabled && !isEnabled
        let becameEnabled = !wasEnabled && isEnabled
        let persistentModeChanged = wasPersistent != isPersistent

        if becameDisabled {
            lastIntervalWeatherShowTime = nil
            if currentActivity == .weather || currentActivity == .persistentWeather {
                dismissalTimer?.invalidate()
                dismissalTimer = nil
                lastEvalTime = 0
                setActivity(type: .none, content: .none)
            }
            lastEvalTime = 0
            evaluateAndDisplayActivity(allowImmediateDismiss: true)
            return
        }

        if becameEnabled || (isEnabled && persistentModeChanged) {
            lastIntervalWeatherShowTime = nil
            snoozedActivities.removeValue(forKey: .weather)
            snoozedActivities.removeValue(forKey: .persistentWeather)
            lastEvalTime = 0
            evaluateAndDisplayActivity(allowImmediateDismiss: true)
        }
    }

    private func subscribeToStateChangeTriggers() {
        let intelligenceRunningPublisher: AnyPublisher<Void, Never> = {
            guard let intelligenceVM else { return Empty().eraseToAnyPublisher() }
            return intelligenceVM.$isRunning.mapToVoid().eraseToAnyPublisher()
        }()

        let intelligenceStatusPublisher: AnyPublisher<Void, Never> = {
            guard let intelligenceVM else { return Empty().eraseToAnyPublisher() }
            return intelligenceVM.$statusMessage
                .removeDuplicates()
                .mapToVoid()
                .eraseToAnyPublisher()
        }()

        let intelligenceProgressPublisher: AnyPublisher<Void, Never> = {
            guard let intelligenceVM else { return Empty().eraseToAnyPublisher() }
            return intelligenceVM.$subtaskProgress
                .map { "\($0.current)/\($0.total)" }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher()
        }()

        let intelligenceStepPublisher: AnyPublisher<Void, Never> = {
            guard let intelligenceVM else { return Empty().eraseToAnyPublisher() }
            return intelligenceVM.$currentActionLabel
                .removeDuplicates()
                .mapToVoid()
                .eraseToAnyPublisher()
        }()

        let stateChangeTriggers: [AnyPublisher<Void, Never>] = [
            valuePublisher(\.isScreenLocked).removeDuplicates().mapToVoid(),
            valuePublisher(\.currentNearbyTransferPayload).removeDuplicates().mapToVoid(),
            valuePublisher(\.currentGeminiPayload).removeDuplicates().mapToVoid(),
            notificationManager.$latestNotification
                .removeDuplicates()
                .mapToVoid(),
            ContinuityManager.shared.notificationBridge.$latest
                .removeDuplicates()
                .mapToVoid(),
            ContinuityManager.shared.liveActivityBridge.$featured
                .removeDuplicates()
                .mapToVoid(),
            ContinuityManager.shared.mediaBridge.$phoneMedia
                .removeDuplicates()
                .mapToVoid(),
            ContinuityManager.shared.mediaBridge.$phoneArtwork
                .map { $0 != nil }
                .removeDuplicates()
                .mapToVoid(),
            SmartInboxMonitor.shared.$latestOTP
                .removeDuplicates()
                .mapToVoid(),
            SmartInboxMonitor.shared.$activeParcels
                .mapToVoid(),
            desktopManager.$currentDesktopNumber.removeDuplicates().mapToVoid(),
            calendarService.$upcomingEvents
                .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
                .mapToVoid(),
            calendarService.$upcomingReminders
                .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
                .mapToVoid(),
            batteryMonitor.$currentState.removeDuplicates().mapToVoid(),
            audioDeviceManager.$lastSwitchEvent.removeDuplicates().mapToVoid(),
            bluetoothManager.$lastEvent.removeDuplicates().mapToVoid(),
            NotificationCenter.default.publisher(for: NSNotification.Name("IOBluetoothHostControllerPoweredOnNotification")).mapToVoid(),
            NotificationCenter.default.publisher(for: NSNotification.Name("IOBluetoothHostControllerPoweredOffNotification")).mapToVoid(),
            eyeBreakManager.$isBreakTime.removeDuplicates().mapToVoid(),
            eyeBreakManager.$isPausedForGameMode.removeDuplicates().mapToVoid(),
            timerManager.$isRunning.removeDuplicates().mapToVoid(),
            timerManager.$ringingTimers.removeDuplicates().mapToVoid(),
            FocusSessionManager.shared.$phase.removeDuplicates().mapToVoid(),
            WeatherViewModel.shared.weatherDataPublisher
                .mapToVoid(),
            musicWidget.valuePublisher(\.shouldShowLiveActivity).removeDuplicates().mapToVoid(),
            musicWidget.valuePublisher(\.isPlaying).removeDuplicates().mapToVoid(),
            musicWidget.valuePublisher(\.title).removeDuplicates().mapToVoid(),
            musicWidget.valuePublisher(\.artist).removeDuplicates().mapToVoid(),
            musicWidget.valuePublisher(\.album).removeDuplicates().mapToVoid(),
            musicWidget.trackDidChange.mapToVoid(),
            musicWidget.valuePublisher(\.showQuickPeek).removeDuplicates().mapToVoid(),
            musicWidget.valuePublisher(\.isHoveringAlbumArt).removeDuplicates().mapToVoid(),
            settingsModel.changes(of: LiveActivityEvaluationSettings.init).mapToVoid(),
            activeAppMonitor.$isLyricsAllowedForActiveApp
                .removeDuplicates()
                .mapToVoid(),
            activeAppMonitor.$fullScreenDisplayIDs.removeDuplicates().mapToVoid(),
            Publishers.CombineLatest(
                activeAppMonitor.$activeAppBundleID,
                settingsModel.changes(of: { $0.hideLiveActivityWhenSourceActive })
                    .prepend(settingsModel.current.hideLiveActivityWhenSourceActive)
            )
            .map { bundleID, hideWhenSourceActive in hideWhenSourceActive ? bundleID : nil }
            .removeDuplicates()
            .mapToVoid(),
            focusModeManager.$currentStatus.removeDuplicates().mapToVoid(),
            UpdateChecker.shared.$status.removeDuplicates().mapToVoid(),
            batteryStatusManager.$currentState.removeDuplicates().mapToVoid(),
            ContinuityManager.shared.valuePublisher(\.connectivity)
                .map { snapshot -> ContinuityConnectivitySnapshot in
                    var snapshot = snapshot
                    snapshot.rssi = nil
                    return snapshot
                }
                .removeDuplicates()
                .mapToVoid(),
            intelligenceRunningPublisher,
            intelligenceStatusPublisher
                .throttle(for: .milliseconds(750), scheduler: RunLoop.main, latest: true)
                .eraseToAnyPublisher(),
            intelligenceProgressPublisher
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .eraseToAnyPublisher(),
            intelligenceStepPublisher
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(stateChangeTriggers)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.evaluateAndDisplayActivity() }
            .store(in: &cancellables)

        StatsManager.shared.$currentStats
            .removeDuplicates()
            .compactMap { $0 }
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.handleStatsUpdate() }
            .store(in: &cancellables)

        activeAppMonitor.$fullScreenDisplayIDs
        .removeDuplicates()
        .sink { [weak self] displayIDs in
            guard let self else { return }
            self.fullScreenDisplayIDs = displayIDs
            let ids = displayIDs.sorted().map(String.init).joined(separator: ",")
            let notchDisplays = self.notchDisplayIDs()
            let notchDisplaysFullScreen = !displayIDs.isEmpty && !notchDisplays.isEmpty && notchDisplays.isSubset(of: displayIDs)
            self.logger.info("full-screen displays=[\(ids, privacy: .public)] notchDisplaysFullScreen=\(notchDisplaysFullScreen, privacy: .public)")
        }
        .store(in: &cancellables)
    }

    private func handleStatsUpdate() {
        let settings = settingsModel.current
        guard settings.statsLiveActivityEnabled else { return }
        if settings.statsLiveActivityThresholdEnabled {
            evaluateAndDisplayActivity()
            return
        }

        switch currentActivity {
        case .persistentStats:
            refreshActiveActivityContent()
        case .none:
            guard settings.showPersistentStatsLiveActivity else { return }
            evaluateAndDisplayActivity()
        default:
            break
        }
    }

    private func subscribeToSportsFinanceSettings() {
        let sportsEnabledPublisher = settingsModel.changes(of: { $0.sportsLiveActivityEnabled })

        let financeEnabledPublisher = settingsModel.changes(of: { $0.financeLiveActivityEnabled })

        sportsEnabledPublisher
            .merge(with: financeEnabledPublisher)
            .sink { [weak self] _ in
                self?.updateSportsFinanceWatchTimer()
            }
            .store(in: &cancellables)

        PremiumGate.accessChanges
            .sink { [weak self] in
                guard let self else { return }
                self.updateSportsFinanceWatchTimer()
                self.lastEvalTime = 0
                self.evaluateAndDisplayActivity()
            }
            .store(in: &cancellables)
    }

    // MARK: - Direct HUD Handler
    private func handleHUDUpdate(_ hudType: HUDType?) {
        if let hudType = hudType {
            let isEnabled: Bool
            switch hudType {
            case .volume, .externalDeviceVolume, .appVolume:
                isEnabled = settingsModel.current.enableVolumeHUD
            case .brightness, .keyboardBrightness, .multiDisplayBrightness:
                isEnabled = settingsModel.current.enableBrightnessHUD
            }
            guard isEnabled else {
                if currentActivity == .systemHUD {
                    setActivity(type: .none, content: .none)
                    evaluateAndDisplayActivity()
                }
                return
            }

            let hudStyle: HUDStyle
            switch hudType {
            case .volume, .externalDeviceVolume, .appVolume:
                hudStyle = settingsModel.current.effectiveVolumeHUDStyle
            case .brightness, .keyboardBrightness, .multiDisplayBrightness:
                hudStyle = settingsModel.current.effectiveBrightnessHUDStyle
            }

            if hudStyle == .pill {
                if currentActivity == .systemHUD {
                    setActivity(type: .none, content: .none)
                    evaluateAndDisplayActivity()
                }
                return
            }

            if hudStyle == .thin {
                let data = StandardActivityData.hud(type: hudType)
                let content = LiveActivityContent.standard(
                    data: data,
                    id: hudType
                )
                setActivity(
                    type: .systemHUD,
                    content: content,
                    dismissAfter: nil
                )
            } else {
                if currentActivity != .systemHUD {
                    let hudBottomCornerRadius: CGFloat = 25.0
                    let view = AnyView(
                        SystemHUDView()
                            .environmentObject(systemHUDManager)
                    )
                    let content = LiveActivityContent.full(
                        view: view,
                        id: "system_hud_activity",
                        bottomCornerRadius: hudBottomCornerRadius
                    )
                    setActivity(
                        type: .systemHUD,
                        content: content,
                        dismissAfter: nil
                    )
                }
            }
        } else {
            if currentActivity == .systemHUD {
                setActivity(type: .none, content: .none)
                evaluateAndDisplayActivity()
            }
        }
    }

    // MARK: - Special Update Handlers
    private func handleLyricUpdate() {
        refreshMusicActivityContent()
    }

    private func refreshActiveActivityContent() {
        let type = currentActivity
        guard type != .none else { return }
        guard isCurrentActivityVisibleOnAnyDisplay else { return }

        guard let (_, newContent, _) = currentActivityCandidate(for: type) else {
            lastEvalTime = 0
            evaluateAndDisplayActivity()
            return
        }

        guard newContent != activityContent else { return }
        activityContent = newContent
        contentUpdateID = UUID()
    }

    private func currentActivityCandidate(for type: ActivityType) -> ActivityCandidate? {
        switch type {
        case .persistentStats: return checkForPersistentStats()
        case .persistentBattery: return checkForPersistentBattery()
        case .persistentWeather: return checkForPersistentWeather()
        case .continuity: return checkForContinuity(issuesOnly: false) ?? checkForContinuity(issuesOnly: true)
        case .focusSession: return checkForFocusSession()
        case .devActivity: return checkForDevActivity()
        default: return activityCheckers[type]?()
        }
    }

    private func refreshMusicActivityContent() {
        guard self.currentActivity == .music else {
            LyricsLog.infoOnChange("liveActivity.refresh", "Music content refresh skipped: current activity is \(currentActivity)")
            return
        }
        guard isCurrentActivityVisibleOnAnyDisplay else {
            LyricsLog.infoOnChange("liveActivity.refresh", "Music content refresh skipped: music activity not visible on any display")
            return
        }
        guard let (_, newContent, _) = checkForMusic() else {
            LyricsLog.infoOnChange("liveActivity.refresh", "Music content refresh skipped: music live activity no longer eligible")
            return
        }
        LyricsLog.infoOnChange("liveActivity.refresh", "Music content refresh running")
        guard newContent != self.activityContent else { return }

        lastLyricContentID = newContent.id
        self.activityContent = newContent
        lyricContentUpdateTask?.cancel()
        lyricContentUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.contentUpdateID = UUID()
        }
    }

    // MARK: - Activity Management
    @ObservationIgnored private var lastSnoozeCleanup = Date()
    private let snoozeCleanupInterval: TimeInterval = 30.0
    @ObservationIgnored private var lastEvalTime: CFAbsoluteTime = 0
    private let minEvalInterval: CFAbsoluteTime = 0.2
    @ObservationIgnored private var dismissGraceTimer: Timer?
    @ObservationIgnored private var pendingEvaluationTask: Task<Void, Never>?

    private static let absoluteHighPriorityActivities: [ActivityType] = [
        .lockScreen,
        .capsLock,
        .otp,
        .notification,
        .continuityNotification,
        .parcel,
        .geminiLive,
        .nearbyShare,
        .audioSwitch,
        .bluetooth,
        .intelligenceAgent,
        .updateAvailable
    ]

    private var highPriorityActivities: [ActivityType] {
        guard settingsModel.current.devActivityHighPriority else {
            return Self.absoluteHighPriorityActivities
        }
        return Self.absoluteHighPriorityActivities + [.devActivity]
    }

    private func evaluateAndDisplayActivity(allowImmediateDismiss: Bool = false) {
        let evalTime = CFAbsoluteTimeGetCurrent()
        let minInterval: CFAbsoluteTime = NotchRuntimeState.shared.shouldReduceBackgroundWork ? 2.0 : minEvalInterval
        guard evalTime - lastEvalTime >= minInterval else {
            schedulePendingEvaluation(after: max(minInterval - (evalTime - lastEvalTime), 0.05))
            return
        }
        lastEvalTime = evalTime
        let now = Date()
        if now.timeIntervalSince(lastSnoozeCleanup) > snoozeCleanupInterval {
            snoozedActivities = snoozedActivities.filter { $0.value > now }
            dismissedNotifications = dismissedNotifications.filter { $0.value > now }
            lastSnoozeCleanup = now
        }

        if currentActivity == .lockScreen {
            if let (type, content, duration) = checkForLockScreenActivity() {
                setActivity(type: type, content: content, dismissAfter: duration)
            }
            return
        }

        if currentActivity == .systemHUD || currentActivity == .unlocked {
            return
        }

        if self.currentActivity == .battery, let state = batteryMonitor.currentState, !state.isPluggedIn, self.dismissalTimer != nil {
            return
        }

        let isFullScreen = notchDisplaysAreFullScreen()
        logFullScreenGateIfChanged(isFullScreen: isFullScreen)
        if isFullScreen && notchDisplaysHideAllActivities() {
            if !satelliteActivities.isEmpty { satelliteActivities = [] }
            consumeBlockedEphemeralActivities(winningType: nil)
            if currentActivity != .none {
                logger.info("full-screen: hiding \(self.currentActivity.rawValue, privacy: .public) (Hide All)")
                setActivity(type: .none, content: .none)
            }
            return
        }
        if !musicWidget.shouldShowLiveActivity, musicWidget.showQuickPeek {
            musicWidget.showQuickPeek = false
        }

        if timerManager.hasRingingTimer {
            snoozedActivities[.timer] = nil
        }
        let urgentActivities: [ActivityType] = (timerManager.hasRingingTimer ? [.timer] : [])
            + (isLowBatteryAlertDue ? [.battery] : [])
        let finalEvaluationOrder = chain(
            urgentActivities + highPriorityActivities,
            settingsModel.current.liveActivityOrder.lazy.compactMap(ActivityType.init(from:))
        )

        var winningCandidate: (ActivityType, LiveActivityContent, TimeInterval?)? = nil

        var evaluatedCandidates: [ActivityType: ActivityCandidate?] = [:]
        func candidate(for activityType: ActivityType) -> ActivityCandidate? {
            if let cached = evaluatedCandidates[activityType] { return cached }
            let result = activityCheckers[activityType]?()
            evaluatedCandidates[activityType] = result
            return result
        }

        for activityType in finalEvaluationOrder {
            guard snoozedActivities[activityType] == nil else { continue }
            guard activityCheckers[activityType] != nil else { continue }

            if isHiddenInFullScreenOnEveryNotchDisplay(activityType) {
                continue
            }

            if let candidate = candidate(for: activityType) {
                winningCandidate = candidate
                break
            }
        }

        if winningCandidate == nil,
           snoozedActivities[.continuityExternal] == nil,
           let candidate = checkForContinuityExternalActivity() {
            winningCandidate = candidate
        }

        if winningCandidate == nil,
           snoozedActivities[.continuity] == nil,
           let candidate = checkForContinuity(issuesOnly: true) {
            winningCandidate = candidate
        }

        if winningCandidate == nil,
           !settingsModel.current.devActivityHighPriority,
           !isHiddenInFullScreenOnEveryNotchDisplay(.devActivity),
           snoozedActivities[.devActivity] == nil,
           let candidate = checkForDevActivity() {
            winningCandidate = candidate
        }

        if winningCandidate == nil,
           !isHiddenInFullScreenOnEveryNotchDisplay(.persistentStats),
           snoozedActivities[.persistentStats] == nil,
           let candidate = checkForPersistentStats() {
            winningCandidate = candidate
        }

        if winningCandidate == nil,
           !isHiddenInFullScreenOnEveryNotchDisplay(.persistentBattery),
           snoozedActivities[.persistentBattery] == nil,
           let candidate = checkForPersistentBattery() {
            winningCandidate = candidate
        }

        if winningCandidate == nil,
           !isHiddenInFullScreenOnEveryNotchDisplay(.focusSession),
           snoozedActivities[.focusSession] == nil,
           let candidate = checkForFocusSession() {
            winningCandidate = candidate
        }

        if winningCandidate == nil,
           !isHiddenInFullScreenOnEveryNotchDisplay(.persistentWeather),
           snoozedActivities[.persistentWeather] == nil,
           let candidate = checkForPersistentWeather() {
            winningCandidate = candidate
        }

        if winningCandidate == nil,
           !isHiddenInFullScreenOnEveryNotchDisplay(.continuity),
           snoozedActivities[.continuity] == nil,
           let candidate = checkForContinuity(issuesOnly: false) {
            winningCandidate = candidate
        }

        let satellites = satelliteCandidates(
            winner: winningCandidate,
            order: chain(finalEvaluationOrder, [ActivityType.devActivity, .focusSession]),
            candidate: candidate
        )
        if satellites != satelliteActivities { satelliteActivities = satellites }

        consumeBlockedEphemeralActivities(
            winningType: winningCandidate?.0,
            keeping: liveTimedSatelliteTypes,
            candidate: candidate
        )

        if let (type, content, duration) = winningCandidate {
            setActivity(type: type, content: content, dismissAfter: duration)
            return
        }

        scheduleDismissToNoneUnlessRecovered(allowImmediate: allowImmediateDismiss)
    }

    static let nonSatelliteActivityTypes: Set<ActivityType> = [
        .none, .persistentBattery, .persistentStats, .persistentWeather,
        .systemHUD, .unlocked, .lockScreen, .notification, .continuityNotification, .otp,
    ]
    static let maximumSatellites = NotchSatelliteSlot.count

    @ObservationIgnored private var timedSatellites: [ActivityType: (content: LiveActivityContent, until: Date)] = [:]
    @ObservationIgnored private var timedSatelliteExpiryTask: Task<Void, Never>?

    private var liveTimedSatelliteTypes: Set<ActivityType> {
        let now = Date()
        return Set(timedSatellites.filter { $0.value.until > now }.keys)
    }

    private func satelliteCandidates(
        winner: ActivityCandidate?,
        order: some Sequence<ActivityType>,
        candidate: (ActivityType) -> ActivityCandidate?
    ) -> [NotchSatelliteActivity] {
        guard settingsModel.current.showLiveActivitySatellites,
              let winner, case .standard = winner.1,
              !Self.displayAnchoredActivityTypes.contains(winner.0) else { return [] }
        var found: [NotchSatelliteActivity] = []
        var seen: Set<ActivityType> = [winner.0]
        let now = Date()
        timedSatellites[winner.0] = nil
        let limit = min(Self.maximumSatellites, max(1, settingsModel.current.liveActivitySatelliteLimit))
        for type in order where found.count < limit {
            guard !Self.nonSatelliteActivityTypes.contains(type), seen.insert(type).inserted else { continue }
            guard snoozedActivities[type] == nil, activityCheckers[type] != nil,
                  !isHiddenInFullScreenOnEveryNotchDisplay(type) else { continue }
            let current = candidate(type)
            if case let (_, content, duration?)? = current, case .standard = content,
               timedSatellites[type]?.content != content {
                timedSatellites[type] = (content, now.addingTimeInterval(duration))
            }
            if let timed = timedSatellites[type] {
                if timed.until > now {
                    found.append(NotchSatelliteActivity(type: type, content: timed.content))
                } else if current?.1 != timed.content {
                    timedSatellites[type] = nil
                }
                continue
            }
            guard case let (_, content, nil)? = current, case .standard = content else { continue }
            found.append(NotchSatelliteActivity(type: type, content: content))
        }
        scheduleTimedSatelliteExpiry(after: now)
        #if DEBUG
        let real = found
        while !real.isEmpty, found.count < min(limit, debugSatelliteFill) {
            found.append(real[found.count % real.count])
        }
        #endif
        return found
    }

    private func scheduleTimedSatelliteExpiry(after now: Date) {
        timedSatelliteExpiryTask?.cancel()
        guard let next = timedSatellites.values.map(\.until).filter({ $0 > now }).min() else {
            timedSatelliteExpiryTask = nil
            return
        }
        timedSatelliteExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.lastEvalTime = 0
            self.evaluateAndDisplayActivity()
        }
    }

    #if DEBUG
    private var debugSatelliteFill = 0

    func debugFillSatellites(_ count: Int) {
        debugSatelliteFill = count
        evaluateAndDisplayActivity()
    }
    #endif

    private func consumeBlockedEphemeralActivities(
        winningType: ActivityType?,
        keeping bubbles: Set<ActivityType> = [],
        candidate: ((ActivityType) -> ActivityCandidate?)? = nil
    ) {
        let candidate = candidate ?? { [weak self] type in self?.activityCheckers[type]?() }
        let keepLowBatteryAlert = isLowBatteryAlertDue
        for activityType in ephemeralActivityTypes {
            guard activityType != winningType, !bubbles.contains(activityType) else { continue }
            if activityType == .battery, keepLowBatteryAlert { continue }
            guard snoozedActivities[activityType] == nil else { continue }
            guard activityCheckers[activityType] != nil else { continue }

            if isHiddenInFullScreenOnEveryNotchDisplay(activityType) {
                continue
            }

            guard candidate(activityType) != nil else { continue }
            consumeEphemeralActivity(activityType)
        }
    }

    private func consumeEphemeralActivity(_ type: ActivityType) {
        handleActivityDismissal(for: type)
        if type == .focusModeChange {
            lastKnownFocusStatus = focusModeManager.currentStatus
        }
    }

    private func schedulePendingEvaluation(after delay: TimeInterval) {
        pendingEvaluationTask?.cancel()
        pendingEvaluationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.lastEvalTime = 0
            self.evaluateAndDisplayActivity()
        }
    }

    private func scheduleDismissToNoneUnlessRecovered(allowImmediate: Bool) {
        dismissGraceTimer?.invalidate()
        dismissGraceTimer = nil

        if currentActivity == .none {
            return
        }

        if allowImmediate {
            setActivity(type: .none, content: .none)
            return
        }

        dismissGraceTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dismissGraceTimer = nil
                self.evaluateAndDisplayActivity(allowImmediateDismiss: true)
            }
        }
    }

    private func cancelPendingDismiss() {
        dismissGraceTimer?.invalidate()
        dismissGraceTimer = nil
    }

    private func setActivity(
        type: ActivityType,
        content: LiveActivityContent,
        dismissAfter duration: TimeInterval? = nil
    ) {
        if type != .none {
            cancelPendingDismiss()
        }

        if self.currentActivity == type && self.activityContent == content {
            return
        }
        if type == .battery, isLowBatteryAlertDue {
            markLowBatteryAlertShown()
        }
        if type != .notification && type != .continuityNotification { clearNotificationState() }

        let oldTimer = self.dismissalTimer
        self.dismissalTimer = nil
        oldTimer?.invalidate()

        let oldType = self.currentActivity
        let oldShape = notchShapeSignature

        if Self.displayAnchoredActivityTypes.contains(type) {
            let cursorLocation = NSEvent.mouseLocation
            activityAnchorDisplayID = NSScreen.screens.first { $0.frame.contains(cursorLocation) }?.displayID
        }

        self.currentActivity = type
        self.activityContent = content

        self.contentUpdateID = UUID()
        if oldType != type || oldShape != notchShapeSignature {
            lastEvalTime = 0
        }

        if (oldType == .music) != (type == .music) {
            Task { await musicWidget.setMusicLiveActivityActive(type == .music) }
        }
        updateTickerRefreshTimer()

        if let duration = duration {
            self.dismissalTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.currentActivity == type else { return }
                    self.dismissalTimer = nil
                    self.handleActivityDismissal(for: type)
                    self.currentActivity = .none
                    self.activityContent = .none
                    if type == .music { Task { await self.musicWidget.setMusicLiveActivityActive(false) } }

                    self.lastEvalTime = 0
                    self.evaluateAndDisplayActivity()
                }
            }
        }
    }

    private func handleActivityDismissal(for type: ActivityType) {
        switch type {
        case .desktopChange: self.lastShownDesktopNumber = self.desktopManager.currentDesktopNumber
        case .battery:
            if let state = self.batteryMonitor.currentState {
                if self.isBelowLowBatteryThreshold(state) { self.hasShownLowBatteryAlert = true }
                else if state.isPluggedIn { self.hasShownPluggedInAlert = true }
            }
        case .focusModeChange: self.lastShownFocusModeID = self.focusModeManager.currentStatus.identifier
        case .eyeBreak: self.hasShownCurrentEyeBreak = true
        case .bluetooth: self.lastShownBluetoothEvent = self.bluetoothManager.lastEvent
        case .continuity:
            let snapshot = ContinuityManager.shared.connectivity
            self.lastShownContinuityStatusKey = "\(snapshot.severity)_\(snapshot.linkState.rawValue)_\(snapshot.headline)"
        case .audioSwitch: self.lastShownAudioSwitchEventID = self.audioDeviceManager.lastSwitchEvent?.id
        case .capsLock: self.capsLockActivationID = nil
        case .music: self.isDismissingPausedMusic = true
        case .otp:
            SmartInboxMonitor.shared.dismissOTP()
            if let notification = notificationManager.latestNotification,
               let code = notification.verificationCode {
                SmartInboxMonitor.shared.consumeOTP(code)
            }
        case .notification:
            if let id = self.activityContent.id {
                dismissedNotifications[id] = Date().addingTimeInterval(300)
            }
            clearNotificationState()
        case .continuityNotification:
            ContinuityManager.shared.notificationBridge.clearLatest()
            clearNotificationState()
        default: break
        }
    }

    // MARK: - Activity Checkers

    private func checkForStatsThresholdActivity() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let settings = settingsModel.settings

        guard settings.statsLiveActivityEnabled,
              settings.statsLiveActivityThresholdEnabled else {
            return nil
        }
        guard let payload = StatsManager.shared.currentStats else { return nil }

        let thresholds = settings.statThresholds
        var shouldShow = false

        if let cpuThreshold = thresholds[.cpu], cpuThreshold.isEnabled, (payload.cpu?.totalUsage ?? 0) >= (Double(cpuThreshold.value) / 100.0) {
            shouldShow = true
        }
        if !shouldShow, let ramThreshold = thresholds[.ram], ramThreshold.isEnabled, (payload.ram?.usage ?? 0) >= (Double(ramThreshold.value) / 100.0) {
            shouldShow = true
        }
        if !shouldShow, let gpuThreshold = thresholds[.gpu], gpuThreshold.isEnabled, (payload.gpu?.utilization ?? 0) >= (Double(gpuThreshold.value) / 100.0) {
            shouldShow = true
        }

        guard shouldShow else { return nil }

        let id = "stats_threshold_activity"
        let data = StandardActivityData.stats(payload: payload)
        let content = LiveActivityContent.standard(data: data, id: id)

        return (.stats, content, 15.0)
    }

    private func checkForPersistentStats() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let settings = settingsModel.settings

        guard settings.statsLiveActivityEnabled,
              settings.showPersistentStatsLiveActivity,
              !settings.statsLiveActivityThresholdEnabled else {
            return nil
        }

        guard let payload = StatsManager.shared.currentStats else { return nil }

        let id = "persistent_stats_activity"
        let data = StandardActivityData.stats(payload: payload)
        let content = LiveActivityContent.standard(data: data, id: id)

        return (.persistentStats, content, nil)
    }

    private func checkForUpdateAvailable() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.showUpdateAvailableLiveActivity,
              case .available(let version, _) = UpdateChecker.shared.status else {
            return nil
        }
        let data = StandardActivityData.updateAvailable(version: version)
        return (
            .updateAvailable,
            .standard(data: data, id: "update_available_\(version)"),
            nil
        )
    }

    private func checkForIntelligenceAgent() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let vm = intelligenceVM, vm.isRunning else { return nil }

        let data = StandardActivityData.intelligenceAgent(
            status: vm.statusMessage,
            stepTitle: vm.currentStepTitle,
            current: vm.displayStepIndex,
            total: vm.displayStepTotal
        )
        return (.intelligenceAgent, .standard(data: data, id: "intelligence_agent_active"), nil)
    }

    private func checkForDevActivity() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.devActivityEnabled else { return nil }
        guard let task = devActivityMonitor.tasks.first else { return nil }

        let data = StandardActivityData.devActivity(
            task: task,
            additionalCount: devActivityMonitor.tasks.count - 1
        )
        return (
            .devActivity,
            .standard(data: data, id: "dev_activity_\(task.id)"),
            nil
        )
    }

    private func checkForLockScreenActivity() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard isScreenLocked else { return nil }
        return (
            .lockScreen,
            .standard(data: .lockScreen, id: "lock_screen_activity"),
            nil
        )
    }

    private func checkForCapsLockActivity() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.capsLockLiveActivityEnabled,
              let activationID = capsLockActivationID else { return nil }
        return (
            .capsLock,
            .standard(data: .capsLock, id: activationID),
            1.5
        )
    }

    private func syncCapsLockMonitoring() {
        guard hasStarted, settingsModel.current.capsLockLiveActivityEnabled else {
            if let capsLockTapToken {
                GlobalEventTap.shared.unregister(capsLockTapToken)
                self.capsLockTapToken = nil
            }
            return
        }

        guard capsLockTapToken == nil else { return }
        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)
        capsLockTapToken = GlobalEventTap.shared.register(
            name: "LiveActivity.capsLock",
            mask: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            priority: EventTapPriority.observer
        ) { [weak self] type, event in
            guard type == .flagsChanged else { return .pass }
            let capsOn = event.flags.contains(.maskAlphaShift)
            Task { @MainActor [weak self] in
                self?.handleCapsLockStateChange(capsOn)
            }
            return .pass
        }
    }

    #if DEBUG
    func debugSimulateDesktopChange(to number: Int) {
        desktopManager.debugSimulateDesktopChange(to: number)
    }

    func debugSimulateCapsLock(_ capsOn: Bool) {
        handleCapsLockStateChange(capsOn)
    }
    #endif

    private func handleCapsLockStateChange(_ capsOn: Bool) {
        guard capsOn != lastCapsLockState else { return }
        lastCapsLockState = capsOn
        guard capsOn, settingsModel.current.capsLockLiveActivityEnabled else { return }
        capsLockActivationID = UUID()
        lastEvalTime = 0
        evaluateAndDisplayActivity(allowImmediateDismiss: true)
    }

    private func isBelowLowBatteryThreshold(_ state: BatteryState) -> Bool {
        state.level >= 0
            && state.level <= settingsModel.current.lowBatteryNotificationPercentage
            && !state.isCharging
            && !state.isPluggedIn
    }

    private var isLowBatteryAlertDue: Bool {
        let settings = settingsModel.settings
        guard settings.batteryLiveActivityEnabled || settings.showPersistentBatteryLiveActivity,
              !hasShownLowBatteryAlert,
              let state = batteryMonitor.currentState else { return false }
        return isBelowLowBatteryThreshold(state)
    }

    private func markLowBatteryAlertShown() {
        hasShownLowBatteryAlert = true
        guard settingsModel.current.lowBatteryNotificationSoundEnabled else { return }
        let sound = Bundle.main.url(forResource: "head_gestures_double_shake", withExtension: "caf")
            .flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: "Tink")
        DispatchQueue.global(qos: .userInitiated).async { sound?.play() }
    }

    private func checkForBatteryAlert() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let settings = settingsModel.settings
        guard settings.batteryLiveActivityEnabled || settings.showPersistentBatteryLiveActivity else {
            return nil
        }
        guard let state = batteryMonitor.currentState else { return nil }

        let systemState = batteryStatusManager.currentState
        let newManagementState = systemState.managementState
        let timeRemaining = batteryEstimator.estimatedTimeRemaining

        if state.level > settings.lowBatteryNotificationPercentage { hasShownLowBatteryAlert = false }
        if !state.isPluggedIn { hasShownPluggedInAlert = false }

        let isLow = isBelowLowBatteryThreshold(state)

        if isLow && !hasShownLowBatteryAlert {
            let data = StandardActivityData.battery(
                state: state,
                style: settings.batteryNotificationStyle,
                timeRemaining: timeRemaining,
                systemState: systemState
            )
            let id = "low_battery_alert"

            if settings.promptForLowPowerMode {
                let view = BatteryLowPowerView(
                    state: state,
                    onToggle: {
                        let enabled = PowerModeManager.shared.toggleLowPowerMode()
                        self.logger.info("Low Power Mode toggled from low-battery prompt (now \(enabled ? "on" : "off", privacy: .public))")
                        self.hasShownLowBatteryAlert = true
                        self.dismissalTimer?.invalidate()
                        self.evaluateAndDisplayActivity()
                    },
                    onDismiss: {
                        self.dismissCurrentActivity()
                    }
                )
                return (.battery, .full(view: AnyView(view), id: "low_power_prompt"), 5.0)
            } else {
                return (.battery, .standard(data: data, id: id), 5.0)
            }
        }

        if state.isPluggedIn && !isLow && !hasShownPluggedInAlert {
            let data = StandardActivityData.battery(
                state: state,
                style: settings.batteryNotificationStyle,
                timeRemaining: timeRemaining,
                systemState: systemState
            )
            let id = "plugged_in_alert_\(state.isCharging)"
            return (.battery, .standard(data: data, id: id), 5.0)
        }

        if newManagementState != lastShownBatteryManagementState {
            let previousState = lastShownBatteryManagementState
            var eventState: ManagementState?

            switch (previousState, newManagementState) {
            case (_, .calibrating): eventState = .calibrationStarted
            case (.calibrating, .charging), (.calibrating, .inhibited): eventState = .calibrationDone
            case (_, .discharging):
                if previousState != .discharging { eventState = .dischargeStarted }
            case (.discharging, _):
                if newManagementState != .discharging { eventState = .dischargeStopped }
            case (_, .heatProtection): eventState = .heatProtectionOn
            case (.heatProtection, _): eventState = .heatProtectionOff
            case (_, .sailing), (_, .inhibited):
                if previousState != newManagementState { eventState = newManagementState }
            default: break
            }

            if newManagementState == .calibrationFailed {
                eventState = .calibrationFailed
            }

            if let eventState = eventState {
                self.lastShownBatteryManagementState = newManagementState

                let data = StandardActivityData.battery(
                    state: state,
                    style: .default,
                    timeRemaining: nil,
                    systemState: BatterySystemState(managementState: eventState)
                )
                let id = "management_event_\(eventState.rawValue)_\(Date().timeIntervalSince1970)"
                return (.battery, .standard(data: data, id: id), 7.0)
            }
        }

        return nil
    }

    private func checkForPersistentBattery() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.showPersistentBatteryLiveActivity else {
            return nil
        }
        guard let state = batteryMonitor.currentState else { return nil }

        let systemState = batteryStatusManager.currentState
        let timeRemaining = batteryEstimator.estimatedTimeRemaining
        let data = StandardActivityData.battery(
            state: state,
            style: .persistent,
            timeRemaining: timeRemaining,
            systemState: systemState
        )
        let dynamicId = "persistent_battery_\(state.level)_\(state.isCharging)_\(state.isPluggedIn)_\(timeRemaining ?? "nil")_\(systemState.managementState.rawValue)"

        return (.persistentBattery, .standard(data: data, id: dynamicId), nil)
    }

    private func checkForContinuity(issuesOnly: Bool) -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.continuityEnabled,
              settingsModel.current.continuityStatusLiveActivityEnabled else {
            return nil
        }
        let snapshot = ContinuityManager.shared.connectivity
        guard snapshot.hasDevice else { return nil }
        if issuesOnly != snapshot.isIssue { return nil }

        let statusKey = "\(snapshot.severity)_\(snapshot.linkState.rawValue)_\(snapshot.headline)"
        if statusKey != continuityStatusKeySeen {
            let isLaunchIssue = continuityStatusKeySeen == nil && snapshot.isIssue
            continuityStatusKeySeen = statusKey
            continuityStatusChangedAt = isLaunchIssue ? .distantPast : Date()
        }

        if snapshot.severity == .degraded { return nil }
        guard statusKey != lastShownContinuityStatusKey,
              Date().timeIntervalSince(continuityStatusChangedAt) < 10 else { return nil }

        let id = "continuity_\(snapshot.severity)_\(snapshot.linkState.rawValue)_\(snapshot.headline)_\(snapshot.phoneBatteryPercent ?? -1)_\(snapshot.phoneCharging)_\(snapshot.phoneSignalLevel)"
        let content = LiveActivityContent.standard(data: .continuity(snapshot: snapshot), id: id)
        return (.continuity, content, 5.0)
    }

    private func checkForContinuityNotification() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.continuityEnabled,
              settingsModel.current.continuityNotifications else { return nil }
        let bridge = ContinuityManager.shared.notificationBridge
        guard let entry = bridge.latest else { return nil }

        let hoverBinding = Binding(
            get: { self.isNotificationHovered },
            set: { self.isNotificationHovered = $0 })
        let view = ContinuityNotificationActivityView(
            entry: entry, bridge: bridge, isHovered: hoverBinding)
        let dismissAfter: TimeInterval = isNotificationHovered ? 30 : 8
        return (.continuityNotification,
                .full(view: AnyView(view), id: "continuity-notif-\(entry.id)"),
                dismissAfter)
    }

    private func checkForContinuityExternalActivity() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.continuityEnabled,
              settingsModel.current.continuityExternalLiveActivities else { return nil }
        guard let entry = ContinuityManager.shared.liveActivityBridge.featured else { return nil }

        let a = entry.activity
        let id = "continuity-ext-\(a.key)-\(a.title)-\(a.text ?? "")-\(a.progress?.current ?? -1)-\(a.left.text ?? "")-\(a.right.text ?? "")-\(a.shortText ?? "")"
        return (.continuityExternal, .standard(data: .continuityExternal(activity: entry), id: id), nil)
    }

    private func checkForPersistentWeather() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let settings = settingsModel.settings
        guard settings.weatherLiveActivityEnabled,
              settings.showPersistentWeatherLiveActivity else {
            return nil
        }
        guard let weatherData = weatherActivityViewModel.weatherData,
              weatherData.isValid else {
            return nil
        }

        let content = LiveActivityContent.standard(
            data: .weather(data: weatherData),
            id: "persistent_weather_activity"
        )

        return (.persistentWeather, content, nil)
    }

    private func checkForWeather() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard !settingsModel.current.showPersistentWeatherLiveActivity else {
            return nil
        }

        guard settingsModel.current.weatherLiveActivityEnabled else {
            return nil
        }
        guard let weatherData = weatherActivityViewModel.weatherData,
              weatherData.isValid else {
            return nil
        }

        let content = LiveActivityContent.standard(
            data: .weather(data: weatherData),
            id: "weather_activity"
        )

        let interval = TimeInterval(
            settingsModel.current.weatherLiveActivityInterval * 60
        )
        let now = Date()

        if lastIntervalWeatherShowTime == nil || now
            .timeIntervalSince(lastIntervalWeatherShowTime!) >= interval {
            lastIntervalWeatherShowTime = now
            return (.weather, content, 90.0)
        }

        return nil
    }

    private func checkForMusic() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard musicWidget.shouldShowLiveActivity, settingsModel.current.musicLiveActivityEnabled else {
            self.isDismissingPausedMusic = false
            return nil
        }
        guard !musicWidget.isPhoneMediaSourceSelected
                || settingsModel.current.continuityPhoneMediaLiveActivityEnabled else {
            self.isDismissingPausedMusic = false
            return nil
        }
        if settingsModel.current.hideLiveActivityWhenSourceActive, let activeID = activeAppMonitor.activeAppBundleID, activeID == musicWidget.lastKnownBundleID {
            return nil
        }

        let isPlaying = musicWidget.isPlaying
        if isDismissingPausedMusic && !isPlaying { return nil }
        if isPlaying {
            isDismissingPausedMusic = false
            musicPausedSince = nil
            pausedMusicExpiryWork?.cancel()
            pausedMusicExpiryWork = nil
        } else {
            let pausedSince = musicPausedSince ?? Date()
            musicPausedSince = pausedSince
            let remaining = Self.pausedMusicGracePeriod - Date().timeIntervalSince(pausedSince)
            if remaining <= 0 { return nil }
            if pausedMusicExpiryWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.pausedMusicExpiryWork = nil
                    self?.evaluateAndDisplayActivity()
                }
                pausedMusicExpiryWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 0.05, execute: work)
            }
        }

        var bottomContentType: MusicBottomContentType = .none
        var bottomContentIdentifier = "none"
        let showHoverPeek = settingsModel.current.enableQuickPeekOnHover && musicWidget.isHoveringAlbumArt

        let bottomLog: String
        if musicWidget.showQuickPeek || showHoverPeek {
            bottomContentType =
                .peek(
                    title: " " + (musicWidget.title ?? "Now Playing"),
                    artist: musicWidget.artist ?? ""
                )
            bottomContentIdentifier = "peek"
            bottomLog = "quick peek (lyrics suppressed)"
        } else if isPlaying, isUpNextWindow, let upNext = musicLiveActivityUpNext {
            bottomContentType = .upNext(
                title: upNext.title,
                artist: upNext.artist,
                artworkURL: upNext.artworkURL
            )
            bottomContentIdentifier = "upNext-\(upNext.title)"
            bottomLog = "up next (lyrics suppressed)"
        } else {
            let allowLyrics = settingsModel.current.showLyricsInLiveActivity
                && (!musicWidget.isPhoneMediaSourceSelected
                    || settingsModel.current.continuityPhoneMediaLyricsInLiveActivity)
            switch LiveActivityLyricsPolicy.decide(
                isPlaying: isPlaying,
                showLyricsInLiveActivity: allowLyrics,
                lyricsAllowedForActiveApp: activeAppMonitor.isLyricsAllowedForActiveApp,
                isHiddenByFullScreenApp: lyricsOverlapFullScreenApp(),
                currentLyric: musicWidget.currentLyric ?? LiveActivityLyricsPolicy.lineBridgingGap(
                    in: musicWidget.lyrics,
                    at: musicWidget.lyricsElapsedTime()
                )
            ) {
            case .show(let line):
                bottomContentType = .lyrics(line: line)
                bottomContentIdentifier = line.id.uuidString
                bottomLog = "showing line \(line.id.uuidString.prefix(8)) (\(line.words.count) words)"
            case .hide(let reason):
                bottomLog = "lyrics hidden: \(reason.rawValue)"
            }
        }
        LyricsLog.infoOnChange("liveActivity.bottom", "Live activity bottom: \(bottomLog)")

        let chrome = "\(settingsModel.current.musicLiveActivityRightTextMode.rawValue)-\(settingsModel.current.musicLiveActivityWaveformMode.rawValue)-\(settingsModel.current.musicLiveActivityWaveformStyle.rawValue)-\(musicWidget.isPhoneMediaSourceSelected)"
        let id = "\((musicWidget.title ?? "") + (musicWidget.artist ?? "") + (musicWidget.album ?? ""))-\(bottomContentIdentifier)-\(isPlaying)-\(chrome)"
        let duration: TimeInterval? = isPlaying ? nil : 5.0
        return (
            .music,
            .standard(data: .music(bottom: bottomContentType), id: id),
            duration
        )
    }

    private var isUpNextWindow: Bool {
        guard settingsModel.current.spotifyShowNextSong else { return false }
        guard musicWidget.totalDuration > 0 else { return false }
        let remaining = musicWidget.totalDuration - musicWidget.elapsedTime()
        return remaining >= 0 && remaining <= 10.0
    }

    private var musicLiveActivityUpNext: (title: String, artist: String?, artworkURL: URL?)? {
        guard settingsModel.current.spotifyShowNextSong else { return nil }

        if musicWidget.isSpotifyLiveSourceSelected || musicWidget.isSpotifySourceActive {
            guard let next = musicWidget.nativeQueue.first else { return nil }
            let title = (next.metadata?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return (
                title,
                next.metadata?.artistName,
                settingsModel.current.spotifyShowNextSongAlbumArt ? next.metadata?.imageURL : nil
            )
        }

        if musicWidget.lastKnownBundleID == "com.apple.Music",
           let next = musicWidget.appleMusicNextTrack {
            return (
                next.title,
                next.artist,
                settingsModel.current.spotifyShowNextSongAlbumArt ? next.artworkURL : nil
            )
        }

        return nil
    }

    private static func calendarOccurrenceID(_ event: EKEvent) -> String {
        let identifier = event.eventIdentifier ?? UUID().uuidString
        guard let start = event.startDate else { return identifier }
        return "\(identifier)@\(Int(start.timeIntervalSince1970))"
    }

    private func checkForCalendar() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.calendarLiveActivityEnabled else {
            return nil
        }
        let now = Date()
        notifiedEventMilestones = CalendarSchedule.prune(notifiedEventMilestones, now: now)

        let thirtyMinBefore = now.addingTimeInterval(30 * 60)
        let eventsIn30Min = calendarService.upcomingEvents.filter { event in
            guard let key = CalendarOccurrenceKey(event: event) else { return false }
            return event.startDate > now &&
            event.startDate <= thirtyMinBefore &&
            notifiedEventMilestones[key]?.contains(.thirtyMinutes) != true
        }

        if !eventsIn30Min.isEmpty {
            eventsIn30Min.forEach { event in
                if let key = CalendarOccurrenceKey(event: event) {
                    notifiedEventMilestones[key, default: []].formUnion([.thirtyMinutes, .oneDay])
                }
            }

            if eventsIn30Min.count == 1, let event = eventsIn30Min.first {
                let id = "\(Self.calendarOccurrenceID(event))_30min"
                let view = AnyView(
                    CalendarNotificationView(
                        event: event,
                        timeUntil: "in about 30 minutes"
                    )
                )
                return (.calendar, .full(view: view, id: id), 60.0)
            } else {
                let id = "multiple_\(eventsIn30Min.count)_30min_\(eventsIn30Min.first?.eventIdentifier ?? "")"
                let view = AnyView(
                    MultipleCalendarNotificationView(
                        events: eventsIn30Min,
                        timeUntil: "in the next 30 mins"
                    )
                )
                return (.calendar, .full(view: view, id: id), 60.0)
            }
        }

        let oneDayBefore = now.addingTimeInterval(24 * 60 * 60)
        let eventsIn24Hours = calendarService.upcomingEvents.filter { event in
            guard let key = CalendarOccurrenceKey(event: event) else { return false }
            return event.startDate > now &&
            event.startDate <= oneDayBefore &&
            notifiedEventMilestones[key]?.contains(.oneDay) != true
        }

        if !eventsIn24Hours.isEmpty {
            eventsIn24Hours.forEach { event in
                if let key = CalendarOccurrenceKey(event: event) {
                    notifiedEventMilestones[key, default: []].insert(.oneDay)
                }
            }

            if eventsIn24Hours.count == 1, let event = eventsIn24Hours.first {
                let id = "\(Self.calendarOccurrenceID(event))_1day"
                let view = AnyView(
                    CalendarNotificationView(
                        event: event,
                        timeUntil: "tomorrow"
                    )
                )
                return (.calendar, .full(view: view, id: id), 60.0)
            } else {
                let id = "multiple_\(eventsIn24Hours.count)_1day_\(eventsIn24Hours.first?.eventIdentifier ?? "")"
                let view = AnyView(
                    MultipleCalendarNotificationView(
                        events: eventsIn24Hours,
                        timeUntil: "tomorrow"
                    )
                )
                return (.calendar, .full(view: view, id: id), 60.0)
            }
        }

        if let nextEvent = calendarService.upcomingEvents.first(where: { $0.startDate > Date() }), let eventId = nextEvent.eventIdentifier, !eventId.isEmpty {
            let timeUntilEvent = nextEvent.startDate.timeIntervalSinceNow
            if timeUntilEvent > 0 && timeUntilEvent <= 10 * 60 {
                return (
                    .calendar,
                    .standard(data: .calendar(event: nextEvent), id: Self.calendarOccurrenceID(nextEvent)),
                    nil
                )
            }
        }

        return nil
    }

    private func checkForReminder() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.remindersLiveActivityEnabled else {
            return nil
        }
        for reminder in calendarService.upcomingReminders {
            let reminderId = reminder.calendarItemIdentifier
            guard !reminderId.isEmpty, let dueDate = reminder.dueDateComponents?.date else {
                continue
            }
            if notifiedReminderMilestones[reminderId] == nil {
                notifiedReminderMilestones[reminderId] = []
            }
            let now = Date()
            let thirtyMinBefore = dueDate.addingTimeInterval(-30 * 60)
            if now >= thirtyMinBefore && !notifiedReminderMilestones[reminderId]!
                .contains(.thirtyMinutes) {
                notifiedReminderMilestones[reminderId]!.insert(.thirtyMinutes)
                return (
                    .reminder,
                    .full(
                        view: AnyView(
                            ReminderNotificationView(
                                reminder: reminder,
                                timeUntil: "in about 30 minutes"
                            )
                        ),
                        id: "\(reminderId)_30min"
                    ),
                    60.0
                )
            }
        }
        if let nextReminder = calendarService.upcomingReminders.first, let dueDate = nextReminder.dueDateComponents?.date {
            let reminderId = nextReminder.calendarItemIdentifier
            guard !reminderId.isEmpty else { return nil }
            let timeUntilReminder = dueDate.timeIntervalSinceNow
            if timeUntilReminder > 0 && timeUntilReminder <= 10 * 60 {
                return (
                    .reminder,
                    .standard(
                        data: .reminder(reminder: nextReminder),
                        id: reminderId
                    ),
                    nil
                )
            }
        }
        return nil
    }

    private func checkForTimer() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.timersLiveActivityEnabled else {
            return nil
        }

        if let ringingTimer = timerManager.ringingTimer {
            let view = TimerFinishedActivityView(
                timerManager: timerManager,
                timerID: ringingTimer.id
            )
            return (
                .timer,
                .full(
                    view: AnyView(view),
                    id: "ringing_timer_\(ringingTimer.id)",
                    bottomCornerRadius: 24
                ),
                nil
            )
        }

        guard timerManager.isRunning else { return nil }
        return (.timer, .standard(data: .timer, id: "active_timer"), nil)
    }

    private func checkForFocusSession() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.focusSessionLiveActivityEnabled,
              FocusSessionManager.shared.isSessionActive else {
            return nil
        }
        return (.focusSession, .standard(data: .focusSession, id: "focus_session_active"), nil)
    }

    private func checkForFileShelf() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let files = FileShelfManager.shared.files
        guard settingsModel.current.fileShelfLiveActivityEnabled, !files.isEmpty else {
            return nil
        }
        let count = files.count
        return (
            .fileShelf,
            .standard(
                data: .fileShelf(count: count),
                id: "file_shelf_\(count)"
            ),
            nil
        )
    }

    private func checkForEyeBreak() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        if !eyeBreakManager.isBreakTime || eyeBreakManager.isPausedForGameMode {
            hasShownCurrentEyeBreak = false
        }
        guard settingsModel.current.eyeBreakLiveActivityEnabled,
              eyeBreakManager.isBreakTime,
              !eyeBreakManager.isPausedForGameMode,
              !hasShownCurrentEyeBreak else {
            return nil
        }
        return (
            .eyeBreak,
            .full(
                view: AnyView(EyeBreakFullActivityView()),
                id: "eye_break_active_full",
                bottomCornerRadius: 30
            ),
            nil
        )
    }

    private func checkForDesktopChange() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.desktopLiveActivityEnabled, let desktopNum = desktopManager.currentDesktopNumber, desktopNum != lastShownDesktopNumber else {
            return nil
        }
        return (
            .desktopChange,
            .standard(data: .desktop(number: desktopNum), id: desktopNum),
            2.0
        )
    }

    private func checkForFocusMode() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.focusLiveActivityEnabled else {
            return nil
        }

        let newStatus = focusModeManager.currentStatus

        if !hasReceivedInitialFocusStatus {
            hasReceivedInitialFocusStatus = true
            self.lastKnownFocusStatus = newStatus
            return nil
        }

        let oldStatus = lastKnownFocusStatus
        self.lastKnownFocusStatus = newStatus

        if newStatus.isActive && !(oldStatus?.isActive ?? false) {
            let modeInfo = newStatus.toFocusModeInfo(isActive: true)
            return (
                .focusModeChange,
                .standard(
                    data: .focus(mode: modeInfo),
                    id: newStatus.identifier
                ),
                4.0
            )
        }

        if !newStatus.isActive && (oldStatus?.isActive ?? false) {
            let offModeInfo = FocusModeInfo(
                name: "Off",
                identifier: "focus.off.activity",
                symbolName: oldStatus?.symbolName ?? "moon.zzz.fill",
                tintColorName: "systemGrayColor",
                tintColorNames: nil,
                isActive: false
            )
            return (
                .focusModeChange,
                .standard(
                    data: .focus(mode: offModeInfo),
                    id: offModeInfo.identifier
                ),
                2.0
            )
        }

        if newStatus.isActive && (oldStatus?.isActive ?? false) && newStatus.identifier != oldStatus?.identifier {
            let modeInfo = newStatus.toFocusModeInfo(isActive: true)
            return (
                .focusModeChange,
                .standard(
                    data: .focus(mode: modeInfo),
                    id: newStatus.identifier
                ),
                4.0
            )
        }

        return nil
    }

    private func checkForNearbyTransfer() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let payload = currentNearbyTransferPayload else { return nil }
        let content: LiveActivityContent = (payload.state == .waitingForConsent) ? .full(view: AnyView(NearbyTransferLiveActivityView(payload: payload)), id: payload) : .standard(
            data: .nearbyTransfer(payload: payload),
            id: payload
        )
        return (
            .nearbyShare,
            content,
            (payload.state == .waitingForConsent) ? 60.0 : nil
        )
    }

    private func checkForFileProgress() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let continuityTask = FileDropManager.shared.tasks.first { task in
            if case .universalTransfer(let t) = task {
                return t.sourceType == .continuity && !t.isComplete
            }
            return false
        }
        if SettingsModel.shared.current.continuityEnabled,
           SettingsModel.shared.current.continuityFiles,
           let continuityTask {
            return (
                .fileProgress,
                .standard(data: .fileProgress(task: continuityTask), id: continuityTask.id),
                nil
            )
        }
        guard settingsModel.current.fileProgressLiveActivityEnabled else { return nil }
        let task = FileDropManager.shared.tasks
            .compactMap { item -> FileTask? in
                switch item {
                case .universalTransfer(let task) where !task.isComplete:
                    return .universalTransfer(task)
                case .airDrop(let task) where !task.isComplete:
                    return .airDrop(task)
                default:
                    return nil
                }
            }
            .sorted { lhs, rhs in
                let lhsDate: Date = {
                    if case .universalTransfer(let task) = lhs { return task.lastChangeDate }
                    return Date()
                }()
                let rhsDate: Date = {
                    if case .universalTransfer(let task) = rhs { return task.lastChangeDate }
                    return Date()
                }()
                return lhsDate > rhsDate
            }
            .first
        guard let task else { return nil }
        return (
            .fileProgress,
            .standard(data: .fileProgress(task: task), id: task.id),
            nil
        )
    }

    private func checkForGeminiLive() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let payload = currentGeminiPayload else { return nil }
        return (
            .geminiLive,
            .standard(data: .geminiLive(payload: payload), id: payload),
            nil
        )
    }

    private func checkForMicrophone() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let settings = settingsModel.settings
        guard settings.microphoneLiveActivityEnabled else { return nil }

        let mic = MicrophoneUsageManager.shared
        guard mic.isMicInUse else { return nil }
        if settings.appActivitiesEnabled, !AppActivityMonitor.shared.activities.isEmpty { return nil }

        let payload = MicrophonePayload(isMuted: mic.isMuted, audioLevel: mic.audioLevel)
        let data = StandardActivityData.microphone(payload: payload)
        let content = LiveActivityContent.standard(data: data, id: "microphone_activity")
        return (.microphone, content, nil)
    }

    private func checkForAppActivity() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.appActivitiesEnabled else { return nil }
        let monitor = AppActivityMonitor.shared
        guard let activity = monitor.primary else { return nil }
        let data = StandardActivityData.appActivity(activity: activity, additionalCount: monitor.activities.count - 1)
        return (.appActivity, .standard(data: data, id: "app-activity-\(activity.id)"), nil)
    }

    private func checkForNotification() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        notificationManager.start()
        guard let notification = notificationManager.latestNotification else {
            return nil
        }
        if notification.verificationCode != nil, settingsModel.current.otpLiveActivityEnabled {
            return nil
        }
        if let until = dismissedNotifications[notification.id], until > Date() {
            return nil
        }
        let hoverBinding = Binding<Bool>(
            get: { self.isNotificationHovered
            },
            set: { self.isNotificationHovered = $0 })
        let fullView = NotificationLiveActivityView(
            payload: notification,
            isHovered: hoverBinding
        )
        return (
            .notification,
            .full(view: AnyView(fullView), id: notification.id),
            15.0
        )
    }

    private func checkForOTP() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.otpLiveActivityEnabled else { return nil }

        if let event = SmartInboxMonitor.shared.latestOTP {
            if SmartInboxMonitor.shared.hasConsumedOTP(event.code), currentActivity != .otp {
                SmartInboxMonitor.shared.dismissOTP()
                return nil
            }
            SmartInboxMonitor.shared.consumeOTP(event.code)
            let view = OTPLiveActivityView(event: event)
            return (.otp, .full(view: AnyView(view), id: event.id), 20.0)
        }

        notificationManager.start()
        if let notification = notificationManager.latestNotification,
           let code = notification.verificationCode {
            if SmartInboxMonitor.shared.hasConsumedOTP(code) {
                return nil
            }
            SmartInboxMonitor.shared.consumeOTP(code)
            let eventID = "notif-\(notification.id)"
            let event = OTPEvent(
                id: eventID,
                code: code,
                source: notification.appName,
                title: notification.title.isEmpty ? "Verification code" : notification.title,
                body: notification.body,
                date: notification.date
            )
            let view = OTPLiveActivityView(event: event, fromNotification: true)
            return (.otp, .full(view: AnyView(view), id: event.id), 20.0)
        }
        return nil
    }

    private func checkForParcel() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.parcelLiveActivityEnabled,
              settingsModel.current.parcelTrackingEnabled else { return nil }
        let parcels = SmartInboxMonitor.shared.activeParcels.filter { !$0.isDelivered }
        guard let parcel = parcels.first else { return nil }
        let view = ParcelLiveActivityView(parcel: parcel)
        let id = [parcel.id, parcel.status, parcel.detail, String(parcel.lastUpdated.timeIntervalSince1970)].joined(separator: "|")
        return (.parcel, .full(view: AnyView(view), id: id), 18.0)
    }

    private func checkForAudioSwitch() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let event = audioDeviceManager.lastSwitchEvent, event.id != lastShownAudioSwitchEventID else {
            return nil
        }
        return (
            .audioSwitch,
            .standard(data: .audioSwitch(event: event), id: event.id),
            5.0
        )
    }

    private func checkForBluetooth() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let event = bluetoothManager.lastEvent, event != lastShownBluetoothEvent else {
            return nil
        }

        let settings = settingsModel.settings
        let isBlocked = !bluetoothManager.isBluetoothPoweredOn
            || !settings.bluetoothLiveActivityEnabled
            || (event.isContinuityDevice && !settings.showBluetoothContinuityDevices)

        if isBlocked {
            lastShownBluetoothEvent = event
            return nil
        }

        let duration: TimeInterval = switch event.eventType {
        case .connected: 6.0; case .disconnected: 5.0; case .batteryLow: 12.0
        }
        return (
            .bluetooth,
            .standard(data: .bluetooth(device: event), id: event),
            duration
        )
    }

    private func checkForSports() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.sportsLiveActivityEnabled,
              SubscriptionManager.shared.hasAccess(to: .liveSports) else {
            return nil
        }

        let teams = settingsModel.current.sportsFavoriteTeams
        guard !teams.isEmpty else { return nil }

        let whenLiveOnly = settingsModel.current.sportsLiveActivityWhenLiveOnly
        let liveTeamIndex = teams.firstIndex(where: { team in
            SportsAPIService.shared.cachedLiveEvent(for: team)?.isLive == true
        })

        if whenLiveOnly, liveTeamIndex == nil {
            return nil
        }

        if let liveIndex = liveTeamIndex {
            sportsActivityTeamIndex = liveIndex
        } else {
            sportsActivityTeamIndex = max(0, min(sportsActivityTeamIndex, teams.count - 1))
        }

        let teamOrLeague = teams[sportsActivityTeamIndex]

        let liveEvent = SportsAPIService.shared.cachedLiveEvent(for: teamOrLeague)
        if whenLiveOnly, liveEvent?.isLive != true {
            return nil
        }

        let payload: SportsPayload
        if let live = liveEvent {
            payload = SportsFinanceContentProvider.makeSportsPayload(from: live)
        } else {
            payload = SportsFinanceContentProvider.makeSportsPayload(for: teamOrLeague, index: sportsActivityTeamIndex)
        }

        var bottomContent: SportsBottomContentType = .none
        if settingsModel.current.sportsCommentaryInLiveActivity,
           payload.status == "Live",
           let liveEvent,
           let latestComment = SportsAPIService.shared.peekLatestCommentary(for: liveEvent) {
            let trimmed = latestComment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                bottomContent = .commentary(text: trimmed, id: latestComment.id)
            }
        }

        let commentarySuffix: String
        switch bottomContent {
        case .none:
            commentarySuffix = ""
        case .commentary(_, let id):
            commentarySuffix = "_\(id)"
        }

        let id = payload.status == "Live"
            ? "sports_\(payload.homeTeam)_\(payload.awayTeam)_\(payload.homeScore)_\(payload.awayScore)_live\(commentarySuffix)"
            : "sports_\(payload.homeTeam)_\(payload.awayTeam)_\(payload.homeScore)_\(payload.awayScore)\(commentarySuffix)"
        let data = StandardActivityData.sports(payload: payload, bottom: bottomContent)
        let content = LiveActivityContent.standard(data: data, id: id)

        return (.sports, content, nil)
    }

    @discardableResult
    func cycleSportsActivity() -> Bool {
        let teams = settingsModel.current.sportsFavoriteTeams
        guard currentActivity == .sports, teams.count > 1 else { return false }
        sportsActivityTeamIndex = (sportsActivityTeamIndex + 1) % teams.count
        evaluateAndDisplayActivity()
        return true
    }

    private func checkForFinance() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.current.financeLiveActivityEnabled,
              SubscriptionManager.shared.hasAccess(to: .financeLiveActivity) else {
            return nil
        }

        guard let symbol = settingsModel.settings.currentFinanceFavoriteSymbol() else {
            return nil
        }

        let index = settingsModel.current.financeFavoriteSymbolIndex
        let quote = FinanceAPIService.shared.cachedQuote(symbol: symbol)
        let payload = FinanceAPIService.shared.makePayload(symbol: symbol, index: index, quote: quote)

        if settingsModel.current.financeLiveActivityActiveHoursOnly, payload.isAfterHours {
            return nil
        }

        let id = payload.isAfterHours
            ? "finance_\(payload.symbol)_\(payload.price)"
            : "finance_\(payload.symbol)_\(payload.price)_live"
        let data = StandardActivityData.finance(payload: payload)
        let content = LiveActivityContent.standard(data: data, id: id)

        return (.finance, content, nil)
    }

    // MARK: - Public Control Functions
    func dismissCurrentActivity() {
        guard currentActivity != .none else { return }
        if settingsModel.current.hapticFeedbackEnabled { haptic() }

        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.revertNotchWindowFocus()
        }

        if currentActivity == .timer, timerManager.hasRingingTimer {
            timerManager.dismissAllRingingTimers()
            setActivity(type: .none, content: .none)
            evaluateAndDisplayActivity()
            return
        }

        if snoozableActivityTypes.contains(currentActivity) {
            snoozedActivities[currentActivity] = Date().addingTimeInterval(300)
        } else {
            handleActivityDismissal(for: currentActivity)
        }

        setActivity(type: .none, content: .none)
        evaluateAndDisplayActivity()
    }

    func dismissCalendarNotification() {
        guard currentActivity == .calendar || currentActivity == .reminder else { return }
        if settingsModel.current.hapticFeedbackEnabled { haptic() }

        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.revertNotchWindowFocus()
        }

        handleActivityDismissal(for: currentActivity)
        setActivity(type: .none, content: .none)
        lastEvalTime = 0
        evaluateAndDisplayActivity()
    }

    func snoozeCalendarNotification(
        eventIDs: [String] = [],
        reminderIDs: [String] = [],
        for duration: TimeInterval = 5 * 60
    ) {
        guard currentActivity == .calendar || currentActivity == .reminder else { return }
        if settingsModel.current.hapticFeedbackEnabled { haptic() }

        let snoozedEventIDs = Set(eventIDs.filter { !$0.isEmpty })
        if !snoozedEventIDs.isEmpty {
            notifiedEventMilestones = notifiedEventMilestones.filter { !snoozedEventIDs.contains($0.key.eventIdentifier) }
        }
        reminderIDs.filter { !$0.isEmpty }.forEach {
            notifiedReminderMilestones[$0] = nil
        }

        let activity = currentActivity
        snoozedActivities[activity] = Date().addingTimeInterval(duration)

        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.revertNotchWindowFocus()
        }

        setActivity(type: .none, content: .none)
        lastEvalTime = 0
        evaluateAndDisplayActivity()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            self.lastEvalTime = 0
            self.evaluateAndDisplayActivity()
        }
    }

    private func clearNotificationState() {
        if isNotificationHovered {
            isNotificationHovered = false
        }
    }

    func startLockScreenActivity() {
        guard !isScreenLocked else { return }
        self.isScreenLocked = true
        lastEvalTime = 0
        evaluateAndDisplayActivity()
    }

    func finishLockScreenActivity() {
        guard isScreenLocked else { return }
        self.isScreenLocked = false

        let content = LiveActivityContent.standard(
            data: .unlocked,
            id: "unlock_activity"
        )
        setActivity(type: .unlocked, content: content, dismissAfter: 1.5)
    }

    func startGeminiLive() {
        guard currentGeminiPayload == nil else { return }; self.currentGeminiPayload = GeminiPayload(isMicMuted: geminiLiveManager.isMicMuted); evaluateAndDisplayActivity()
    }
    func finishGeminiLive() {
        self.currentGeminiPayload = nil; evaluateAndDisplayActivity()
    }
    func startNearbyTransferActivity(
        transfer: TransferMetadata,
        device: RemoteDeviceInfo,
        fileURLs: [URL]
    ) {
        self.currentNearbyTransferPayload = NearbyTransferPayload(id: transfer.id, device: device, transfer: transfer, destinationURLs: fileURLs); evaluateAndDisplayActivity()
    }
    func updateNearbyTransferState(to newState: NearbyTransferState) {
        guard var payload = self.currentNearbyTransferPayload else { return }; payload.state = newState; if newState == .inProgress { payload.progress = 0.0 }; self.currentNearbyTransferPayload = payload; evaluateAndDisplayActivity()
    }
    func declineNearbyTransfer(id: String) {
        NearbyConnectionManager.shared
            .submitUserConsent(transferID: id, accept: false); clearNearbyTransferActivity(
                id: id
            )
    }
    func updateNearbyTransferProgress(id: String, progress: Double) {
        guard var payload = self.currentNearbyTransferPayload,
              payload.id == id else {
            return
        }
        let clampedProgress = min(max(progress, 0), 1)
        guard payload.progress != clampedProgress else { return }
        payload.progress = clampedProgress
        self.currentNearbyTransferPayload = payload
        evaluateAndDisplayActivity()
    }
    func finishNearbyTransfer(id: String, error: Error?) {
        guard var payload = self.currentNearbyTransferPayload, payload.id == id, (payload.state == .waitingForConsent || payload.state == .inProgress) else {
            return
        }
        if let error {
            let errorString: String
            if let nearbyError = error as? NearbyError, case .canceled(let reason) = nearbyError {
                errorString = switch reason {
                case .userRejected: "Declined"; case .userCanceled: "Canceled"; case .notEnoughSpace: "Not enough space"; case .unsupportedType: "Unsupported type"; case .timedOut: "Timed out"
                }
            } else { errorString = error.localizedDescription }
            payload.state =
                .failed(errorString.isEmpty ? "Unknown Error" : errorString)
        } else { payload.state = .finished }
        payload.progress = nil
        self.currentNearbyTransferPayload = payload
        Task {
            try? await Task
                .sleep(for: .seconds(4)); await MainActor
                .run { self.clearNearbyTransferActivity(id: id) }
        }
    }
    func clearNearbyTransferActivity(id: String? = nil) {
        if id == nil || self.currentNearbyTransferPayload?.id == id {
            self.currentNearbyTransferPayload = nil; evaluateAndDisplayActivity()
        }
    }

    private static let tickerNetworkRefreshTicks = 10

    private func updateTickerRefreshTimer() {
        let needsFastRefresh = currentActivity == .finance || currentActivity == .sports
        if needsFastRefresh {
            guard tickerRefreshTimer == nil else { return }
            tickerFetchTick = 0
            tickerRefreshTimer = Timer.scheduledCoalescing(
                withTimeInterval: 1.0,
                repeats: true,
                toleranceFraction: 0.1
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.currentActivity == .finance || self.currentActivity == .sports else {
                        self.updateTickerRefreshTimer()
                        return
                    }
                    self.tickerFetchTick += 1
                    if self.tickerFetchTick % Self.tickerNetworkRefreshTicks == 0 {
                        Task { await self.refreshSportsFinanceData(forceRefresh: true) }
                    }
                    self.refreshActiveActivityContent()
                }
            }
        } else {
            tickerRefreshTimer?.invalidate()
            tickerRefreshTimer = nil
        }
        updateSportsFinanceWatchTimer()
    }

    private func updateSportsFinanceWatchTimer() {
        let needsWatch = PremiumGate.isActive(.liveSports, enabled: settingsModel.current.sportsLiveActivityEnabled)
            || PremiumGate.isActive(.financeLiveActivity, enabled: settingsModel.current.financeLiveActivityEnabled)
        if needsWatch {
            let onScreen = currentActivity == .finance || currentActivity == .sports
            let interval: TimeInterval = onScreen ? 60.0 : 30.0
            if let sportsFinanceWatchTimer, sportsFinanceWatchTimer.isValid,
               abs(sportsFinanceWatchTimer.timeInterval - interval) < 0.01 {
                return
            }
            sportsFinanceWatchTimer?.invalidate()
            SportsAPIService.shared.bootstrapIfNeeded()
            sportsFinanceWatchTimer = Timer.scheduledCoalescing(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.currentActivity != .finance, self.currentActivity != .sports else { return }
                    await self.refreshSportsFinanceData(forceRefresh: true)
                    self.lastEvalTime = 0
                    self.evaluateAndDisplayActivity()
                }
            }
            Task { await refreshSportsFinanceData(forceRefresh: true) }
        } else {
            sportsFinanceWatchTimer?.invalidate()
            sportsFinanceWatchTimer = nil
        }
    }

    private func refreshSportsFinanceData(forceRefresh: Bool = false) async {
        if settingsModel.current.sportsLiveActivityEnabled, SubscriptionManager.shared.hasAccess(to: .liveSports) {
            let teams = settingsModel.current.sportsFavoriteTeams
            await SportsAPIService.shared.prefetchLiveScoreboards(for: teams)
            for team in teams.prefix(6) {
                _ = await SportsAPIService.shared.fetchLiveEvent(for: team, forceRefresh: forceRefresh)
            }
        }
        if settingsModel.current.financeLiveActivityEnabled, SubscriptionManager.shared.hasAccess(to: .financeLiveActivity) {
            for symbol in settingsModel.current.financeFavoriteSymbols.prefix(6) {
                _ = await FinanceAPIService.shared.fetchQuote(symbol: symbol)
            }
        }
    }
}

extension LiveActivityContent {
    var id: AnyHashable? {
        switch self {
        case .none: return nil
        case .full(_, let id, _): return id
        case .standard(_, let id): return id
        }
    }
}

extension Publisher where Failure == Never {
    func mapToVoid() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
func chain<A: Sequence, B: Sequence>(_ first: A, _ second: B) -> AnySequence<A.Element>
where A.Element == B.Element {
    AnySequence { () -> AnyIterator<A.Element> in
        var firstIterator = first.makeIterator()
        var secondIterator = second.makeIterator()
        return AnyIterator { firstIterator.next() ?? secondIterator.next() }
    }
}