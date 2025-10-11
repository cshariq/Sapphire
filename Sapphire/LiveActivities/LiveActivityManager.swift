//
//  LiveActivityManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04.
//
//
//

import Foundation
import SwiftUI
import Combine
import EventKit
import NearbyShare

// MARK: - Enums and Structs

enum ActivityType: Int, Equatable, Comparable, CaseIterable {
    case none = 0, persistentBattery = 1, weather = 5, music = 10, timer = 20, fileShelf = 25, desktopChange = 30, battery = 40, reminder = 49, calendar = 50, focusModeChange = 55, bluetooth = 58, audioSwitch = 60, fileProgress = 65, eyeBreak = 70, notification = 80, geminiLive = 85, nearbyShare = 90, updateAvailable = 95, systemHUD = 100, lockScreen = 110

    static func < (lhs: ActivityType, rhs: ActivityType) -> Bool { return lhs.rawValue < rhs.rawValue }

    init?(from settingsType: LiveActivityType) {
        switch settingsType {
        case .music: self = .music; case .weather: self = .weather; case .calendar: self = .calendar; case .reminders: self = .reminder; case .timers: self = .timer; case .battery: self = .battery; case .eyeBreak: self = .eyeBreak; case .desktop: self = .desktopChange; case .focus: self = .focusModeChange; case .fileShelf: self = .fileShelf; case .fileProgress: self = .fileProgress
        }
    }

    func toLiveActivityType() -> LiveActivityType? {
        switch self {
        case .music: return .music
        case .weather: return .weather
        case .calendar: return .calendar
        case .reminder: return .reminders
        case .timer: return .timers
        case .battery, .persistentBattery: return .battery
        case .eyeBreak: return .eyeBreak
        case .desktopChange: return .desktop
        case .focusModeChange: return .focus
        case .fileShelf: return .fileShelf
        case .fileProgress: return .fileProgress
        default: return nil
        }
    }
}

private struct SystemHUDIdentifier: Hashable {
    let type: HUDType
    let style: HUDStyle
}

// MARK: - LiveActivityManager

@MainActor
class LiveActivityManager: ObservableObject {

    // MARK: - Published Properties
    @Published private(set) var contentUpdateID = UUID()
    @Published private(set) var currentActivity: ActivityType = .none
    @Published private(set) var activityContent: LiveActivityContent = .none
    @Published private(set) var currentNearDropPayload: NearDropPayload?
    @Published private(set) var currentGeminiPayload: GeminiPayload?
    @Published private(set) var isScreenLocked: Bool = false
    @Published var isNotificationHovered: Bool = false

    // MARK: - Public Properties
    var showLyricsBinding: Binding<Bool>?
    var isFullViewActivity: Bool { if case .full = activityContent { true } else { false } }
    var fileShelfManager: FileShelfManager?

    // MARK: - Private Properties
    private var dismissalTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var activityCheckers: [ActivityType: () -> (ActivityType, LiveActivityContent, TimeInterval?)?] = [:]
    private var snoozedActivities: [ActivityType: Date] = [:]
    private let snoozableActivityTypes: Set<ActivityType> = [.persistentBattery, .weather, .timer, .calendar, .reminder, .fileShelf]
    private var dismissedNotifications: [AnyHashable: Date] = [:]
    private var lastIntervalWeatherShowTime: Date?
    private var periodicCheckTimer: Timer?
    private var lastKnownFocusStatus: FocusStatus?
    private var hasShownPluggedInAlert = false, hasShownLowBatteryAlert = false, hasShownCurrentEyeBreak = false
    private var lastShownDesktopNumber: Int?, lastShownFocusModeID: String?
    private var lastShownBluetoothEvent: BluetoothDeviceState?, lastShownAudioSwitchEventID: UUID?
    private var isDismissingPausedMusic = false
    private enum CalendarNotificationMilestone { case oneDay, thirtyMinutes }
    private var notifiedEventMilestones: [String: Set<CalendarNotificationMilestone>] = [:]
    private enum ReminderNotificationMilestone { case thirtyMinutes }
    private var notifiedReminderMilestones: [String: Set<ReminderNotificationMilestone>] = [:]

    // MARK: - Dependencies
    private let systemHUDManager: SystemHUDManager, notificationManager: NotificationManager, desktopManager: DesktopManager, focusModeManager: FocusModeManager, musicWidget: MusicManager, calendarService: CalendarService, batteryMonitor: BatteryMonitor, bluetoothManager: BluetoothManager, audioDeviceManager: AudioDeviceManager, eyeBreakManager: EyeBreakManager, timerManager: TimerManager, weatherActivityViewModel: WeatherActivityViewModel, geminiLiveManager: GeminiLiveManager, settingsModel: SettingsModel, activeAppMonitor: ActiveAppMonitor, batteryEstimator: BatteryEstimator

    // MARK: - Initialization
    init(systemHUDManager: SystemHUDManager, notificationManager: NotificationManager, desktopManager: DesktopManager, focusModeManager: FocusModeManager, musicWidget: MusicManager, calendarService: CalendarService, batteryMonitor: BatteryMonitor, bluetoothManager: BluetoothManager, audioDeviceManager: AudioDeviceManager, eyeBreakManager: EyeBreakManager, timerManager: TimerManager, weatherActivityViewModel: WeatherActivityViewModel, geminiLiveManager: GeminiLiveManager, settingsModel: SettingsModel, activeAppMonitor: ActiveAppMonitor, batteryEstimator: BatteryEstimator) {
        self.systemHUDManager = systemHUDManager; self.notificationManager = notificationManager; self.desktopManager = desktopManager; self.focusModeManager = focusModeManager; self.musicWidget = musicWidget; self.calendarService = calendarService; self.batteryMonitor = batteryMonitor; self.bluetoothManager = bluetoothManager; self.audioDeviceManager = audioDeviceManager; self.eyeBreakManager = eyeBreakManager; self.timerManager = timerManager; self.weatherActivityViewModel = weatherActivityViewModel; self.geminiLiveManager = geminiLiveManager; self.settingsModel = settingsModel; self.activeAppMonitor = activeAppMonitor; self.batteryEstimator = batteryEstimator
        self.lastShownDesktopNumber = desktopManager.currentDesktopNumber
        self.activityCheckers = [
            .lockScreen: { self.checkForLockScreenActivity() },
            .updateAvailable: { self.checkForUpdateAvailable() },
            .nearbyShare: { self.checkForNearDrop() },
            .geminiLive: { self.checkForGeminiLive() },
            .notification: { self.checkForNotification() },
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
        ]
        setupSubscriptions()
        setupPeriodicTimer()
    }

    // MARK: - Subscriptions
    private func setupSubscriptions() {
        systemHUDManager.$currentHUD
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hudType in
                self?.handleHUDUpdate(hudType)
            }
            .store(in: &cancellables)

        geminiLiveManager.$isMicMuted.receive(on: DispatchQueue.main).sink { [weak self] newMuteState in guard let self, var payload = self.currentGeminiPayload, payload.isMicMuted != newMuteState else { return }; payload.isMicMuted = newMuteState; self.currentGeminiPayload = payload }.store(in: &cancellables)
        geminiLiveManager.sessionDidEndPublisher.receive(on: DispatchQueue.main).sink { [weak self] in self?.finishGeminiLive() }.store(in: &cancellables)
        FileDropManager.shared.$tasks.throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in if self?.currentActivity == .fileProgress || self?.currentActivity == .none { self?.evaluateAndDisplayActivity() } }.store(in: &cancellables)
        $isNotificationHovered.removeDuplicates().debounce(for: .milliseconds(50), scheduler: DispatchQueue.main).sink { [weak self] isHovered in }.store(in: &cancellables)

        let stateChangeTriggers: [AnyPublisher<Void, Never>] = [
            $isScreenLocked.removeDuplicates().mapToVoid(),
            $currentNearDropPayload.removeDuplicates().mapToVoid(),
            $currentGeminiPayload.removeDuplicates().mapToVoid(),
            notificationManager.$latestNotification.removeDuplicates().mapToVoid(),
            desktopManager.$currentDesktopNumber.removeDuplicates().mapToVoid(),
            calendarService.$upcomingEvents.mapToVoid(),
            calendarService.$upcomingReminders.mapToVoid(),
            batteryMonitor.$currentState.removeDuplicates().mapToVoid(),
            audioDeviceManager.$lastSwitchEvent.removeDuplicates().mapToVoid(),
            bluetoothManager.$lastEvent.removeDuplicates().mapToVoid(),
            eyeBreakManager.$isBreakTime.removeDuplicates().mapToVoid(),
            timerManager.$isRunning.removeDuplicates().mapToVoid(),
            weatherActivityViewModel.$weatherData.removeDuplicates().mapToVoid(),
            musicWidget.$shouldShowLiveActivity.removeDuplicates().mapToVoid(),
            musicWidget.$isPlaying.removeDuplicates().mapToVoid(),
            musicWidget.currentLyricPublisher.mapToVoid(),
            musicWidget.trackDidChange.mapToVoid(),
            musicWidget.$showQuickPeek.removeDuplicates().mapToVoid(),
            musicWidget.$isHoveringAlbumArt.removeDuplicates().mapToVoid(),
            fileShelfManager?.$files.mapToVoid() ?? Empty().eraseToAnyPublisher(),
            settingsModel.$settings.mapToVoid(),
            activeAppMonitor.$isLyricsAllowedForActiveApp.removeDuplicates().mapToVoid(),
            activeAppMonitor.$isFullScreen.removeDuplicates().mapToVoid(),
            activeAppMonitor.$activeAppBundleID.removeDuplicates().mapToVoid(),
            focusModeManager.$currentStatus.removeDuplicates().mapToVoid(),
            UpdateChecker.shared.$status.mapToVoid() // Listen for update status changes
        ]

        Publishers.MergeMany(stateChangeTriggers)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.evaluateAndDisplayActivity() }
            .store(in: &cancellables)
    }

    // MARK: - Direct HUD Handler
    private func handleHUDUpdate(_ hudType: HUDType?) {
        if let hudType = hudType {
            let hudStyle: HUDStyle
            switch hudType {
            case .volume, .externalDeviceVolume:
                hudStyle = settingsModel.settings.volumeHUDStyle
            case .brightness, .keyboardBrightness:
                hudStyle = settingsModel.settings.brightnessHUDStyle
            }

            if hudStyle == .thin {
                let data = StandardActivityData.hud(type: hudType)
                let content = LiveActivityContent.standard(data: data, id: hudType)
                setActivity(type: .systemHUD, content: content, dismissAfter: nil)
            } else { // .default style
                if currentActivity != .systemHUD {
                    let hudBottomCornerRadius: CGFloat = 25.0
                    let view = AnyView(
                        SystemHUDView()
                            .environmentObject(systemHUDManager)
                            .environmentObject(settingsModel)
                    )
                    let content = LiveActivityContent.full(
                        view: view,
                        id: "system_hud_activity",
                        bottomCornerRadius: hudBottomCornerRadius
                    )
                    setActivity(type: .systemHUD, content: content, dismissAfter: nil)
                }
            }
        } else {
            if currentActivity == .systemHUD {
                setActivity(type: .none, content: .none)
                evaluateAndDisplayActivity()
            }
        }
    }

    // MARK: - Activity Management
    private func evaluateAndDisplayActivity() {
        let now = Date()
        snoozedActivities = snoozedActivities.filter { $0.value > now }
        dismissedNotifications = dismissedNotifications.filter { $0.value > now }

        if currentActivity == .systemHUD {
            return
        }

        if let (type, content, duration) = checkForLockScreenActivity() {
            setActivity(type: type, content: content, dismissAfter: duration)
            return
        }

        if self.currentActivity == .battery, let state = batteryMonitor.currentState, !state.isPluggedIn, self.dismissalTimer != nil { return }
        if activeAppMonitor.isFullScreen && settingsModel.settings.hideLiveActivityInFullScreen { if currentActivity != .none { setActivity(type: .none, content: .none) }; return }
        if !musicWidget.shouldShowLiveActivity { musicWidget.showQuickPeek = false }

        let highPriorityActivities: [ActivityType] = [.updateAvailable, .nearbyShare, .geminiLive, .notification, .fileProgress, .audioSwitch, .bluetooth, .calendar, .reminder, .battery]
        let userOrderedActivities = settingsModel.settings.liveActivityOrder.compactMap { ActivityType(from: $0) }
        let finalEvaluationOrder = highPriorityActivities + userOrderedActivities

        for activityType in finalEvaluationOrder.sorted(by: >) {
            guard snoozedActivities[activityType] == nil else { continue }
            guard let checker = activityCheckers[activityType], activityType != .lockScreen else { continue }

            if activeAppMonitor.isFullScreen {
                if let liveActivitySettingsType = activityType.toLiveActivityType(),
                   settingsModel.settings.hideActivitiesInFullScreen[liveActivitySettingsType.rawValue] == true {
                    continue
                }
            }

            if let (type, content, duration) = checker() {
                setActivity(type: type, content: content, dismissAfter: duration)
                return
            }
        }

        if let batterySettingsType = ActivityType.persistentBattery.toLiveActivityType() {
            let shouldHide = activeAppMonitor.isFullScreen && settingsModel.settings.hideActivitiesInFullScreen[batterySettingsType.rawValue] == true
            if !shouldHide {
                if snoozedActivities[.persistentBattery] == nil, let (type, content, duration) = checkForPersistentBattery() {
                    setActivity(type: type, content: content, dismissAfter: duration)
                    return
                }
            }
        }

        setActivity(type: .none, content: .none)
    }

    private func setActivity(type: ActivityType, content: LiveActivityContent, dismissAfter duration: TimeInterval? = nil) {
        if self.currentActivity == type && self.activityContent == content { return }
        if type != .notification { clearNotificationState() }

        let oldTimer = self.dismissalTimer
        self.dismissalTimer = nil
        oldTimer?.invalidate()

        self.currentActivity = type
        self.activityContent = content
        self.contentUpdateID = UUID()

        if let duration = duration {
            self.dismissalTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                guard let self = self, self.currentActivity == type else { return }
                self.dismissalTimer = nil
                self.handleActivityDismissal(for: type)
                self.evaluateAndDisplayActivity()
            }
        }
    }

    private func handleActivityDismissal(for type: ActivityType) {
        switch type {
        case .desktopChange: self.lastShownDesktopNumber = self.desktopManager.currentDesktopNumber
        case .battery:
            if let state = self.batteryMonitor.currentState {
                if state.isLow { self.hasShownLowBatteryAlert = true }
                else if state.isPluggedIn { self.hasShownPluggedInAlert = true }
            }
        case .focusModeChange: self.lastShownFocusModeID = self.focusModeManager.currentStatus.identifier
        case .eyeBreak: self.hasShownCurrentEyeBreak = true
        case .bluetooth: self.lastShownBluetoothEvent = self.bluetoothManager.lastEvent
        case .audioSwitch: self.lastShownAudioSwitchEventID = self.audioDeviceManager.lastSwitchEvent?.id
        case .music: self.isDismissingPausedMusic = true
        case .notification:
            if let id = self.activityContent.id {
                dismissedNotifications[id] = Date().addingTimeInterval(300)
            }
            clearNotificationState()
        default: break
        }
    }

    // MARK: - Activity Checkers
    private func checkForUpdateAvailable() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard case .available(let version, _) = UpdateChecker.shared.status else { return nil }
        let data = StandardActivityData.updateAvailable(version: version)
        return (.updateAvailable, .standard(data: data, id: "update_available_\(version)"), nil)
    }

    private func checkForLockScreenActivity() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard isScreenLocked else { return nil }
        return (.lockScreen, .standard(data: .lockScreen, id: "lock_screen_activity"), nil)
    }

    private func checkForBatteryAlert() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        let settings = settingsModel.settings
        guard settings.batteryLiveActivityEnabled || settings.showPersistentBatteryLiveActivity else { return nil }
        guard let state = batteryMonitor.currentState else { return nil }

        if state.level > settings.lowBatteryNotificationPercentage { hasShownLowBatteryAlert = false }
        if !state.isPluggedIn { hasShownPluggedInAlert = false }

        let timeRemaining = batteryEstimator.estimatedTimeRemaining
        let isLow = state.level <= settings.lowBatteryNotificationPercentage && !state.isCharging

        if isLow && !hasShownLowBatteryAlert {
            if settings.lowBatteryNotificationSoundEnabled {
                if let soundURL = Bundle.main.url(forResource: "head_gestures_double_shake", withExtension: "caf") {
                    NSSound(contentsOf: soundURL, byReference: true)?.play()
                } else {
                    NSSound(named: "Tink")?.play()
                }
            }
            self.hasShownLowBatteryAlert = true

            let data = StandardActivityData.battery(state: state, style: settings.batteryNotificationStyle, timeRemaining: timeRemaining)
            let id = "low_battery_alert"

            if settings.promptForLowPowerMode && !PowerModeManager.shared.isLowPowerModeEnabled() {
                 let view = BatteryLowPowerView(
                    state: state,
                    onEnable: {
                        PowerModeManager.shared.enableLowPowerMode()
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
            let data = StandardActivityData.battery(state: state, style: settings.batteryNotificationStyle, timeRemaining: timeRemaining)
            let id = "plugged_in_alert_\(state.isCharging)"
            return (.battery, .standard(data: data, id: id), 5.0)
        }

        return nil
    }

    private func checkForPersistentBattery() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.showPersistentBatteryLiveActivity else { return nil }
        guard let state = batteryMonitor.currentState else { return nil }

        let timeRemaining = batteryEstimator.estimatedTimeRemaining
        let data = StandardActivityData.battery(state: state, style: .persistent, timeRemaining: timeRemaining)
        let dynamicId = "persistent_battery_\(state.level)_\(state.isCharging)_\(state.isPluggedIn)_\(timeRemaining ?? "nil")"

        return (.persistentBattery, .standard(data: data, id: dynamicId), nil)
    }

    private func checkForWeather() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.weatherLiveActivityEnabled else { return nil }
        guard let weatherData = weatherActivityViewModel.weatherData else { return nil }

        let content = LiveActivityContent.standard(data: .weather(data: weatherData), id: "weather_activity")

        if settingsModel.settings.showPersistentWeatherLiveActivity {
            return (.weather, content, nil)
        }

        let interval = TimeInterval(settingsModel.settings.weatherLiveActivityInterval * 60)
        let now = Date()

        if lastIntervalWeatherShowTime == nil || now.timeIntervalSince(lastIntervalWeatherShowTime!) >= interval {
            lastIntervalWeatherShowTime = now
            return (.weather, content, 90.0)
        }

        return nil
    }

    private func checkForMusic() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard musicWidget.shouldShowLiveActivity, settingsModel.settings.musicLiveActivityEnabled else {
            self.isDismissingPausedMusic = false
            return nil
        }
        if settingsModel.settings.hideLiveActivityWhenSourceActive, let activeID = activeAppMonitor.activeAppBundleID, activeID == musicWidget.lastKnownBundleID {
            return nil
        }

        if isDismissingPausedMusic && !musicWidget.isPlaying { return nil }
        if musicWidget.isPlaying { isDismissingPausedMusic = false }

        var bottomContentType: MusicBottomContentType = .none
        let showHoverPeek = settingsModel.settings.enableQuickPeekOnHover && musicWidget.isHoveringAlbumArt

        if musicWidget.showQuickPeek || showHoverPeek {
            bottomContentType = .peek(title: " " + (musicWidget.title ?? "Now Playing"), artist: musicWidget.artist ?? "")
        } else if musicWidget.isPlaying {
            let lyricsAllowed = activeAppMonitor.isLyricsAllowedForActiveApp && settingsModel.settings.showLyricsInLiveActivity
            if lyricsAllowed, let currentLyric = musicWidget.currentLyric {
                let lyricText = currentLyric.translatedText ?? currentLyric.text
                if !lyricText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bottomContentType = .lyrics(text: lyricText, id: currentLyric.id)
                }
            }
        }

        let id = "\((musicWidget.title ?? "") + (musicWidget.artist ?? ""))-\(bottomContentType)"
        let duration: TimeInterval? = musicWidget.isPlaying ? nil : 7.0
        return (.music, .standard(data: .music(bottom: bottomContentType), id: id), duration)
    }

    private func checkForCalendar() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.calendarLiveActivityEnabled else { return nil }
        let now = Date()

        let thirtyMinBefore = now.addingTimeInterval(30 * 60)
        let eventsIn30Min = calendarService.upcomingEvents.filter { event in
            guard let eventId = event.eventIdentifier, !eventId.isEmpty else { return false }
            if notifiedEventMilestones[eventId] == nil { notifiedEventMilestones[eventId] = [] }

            return event.startDate > now &&
                   event.startDate <= thirtyMinBefore &&
                   !notifiedEventMilestones[eventId]!.contains(.thirtyMinutes)
        }

        if !eventsIn30Min.isEmpty {
            eventsIn30Min.forEach { event in
                if let eventId = event.eventIdentifier {
                    notifiedEventMilestones[eventId, default: []].insert(.thirtyMinutes)
                    notifiedEventMilestones[eventId, default: []].insert(.oneDay)
                }
            }

            if eventsIn30Min.count == 1, let event = eventsIn30Min.first {
                let id = "\(event.eventIdentifier ?? UUID().uuidString)_30min"
                let view = AnyView(CalendarNotificationView(event: event, timeUntil: "in about 30 minutes"))
                return (.calendar, .full(view: view, id: id), 60.0)
            } else {
                let id = "multiple_\(eventsIn30Min.count)_30min_\(eventsIn30Min.first?.eventIdentifier ?? "")"
                let view = AnyView(MultipleCalendarNotificationView(events: eventsIn30Min, timeUntil: "in the next 30 mins"))
                return (.calendar, .full(view: view, id: id), 60.0)
            }
        }

        let oneDayBefore = now.addingTimeInterval(24 * 60 * 60)
        let eventsIn24Hours = calendarService.upcomingEvents.filter { event in
            guard let eventId = event.eventIdentifier, !eventId.isEmpty else { return false }
            if notifiedEventMilestones[eventId] == nil { notifiedEventMilestones[eventId] = [] }

            return event.startDate > now &&
                   event.startDate <= oneDayBefore &&
                   !notifiedEventMilestones[eventId]!.contains(.oneDay)
        }

        if !eventsIn24Hours.isEmpty {
            eventsIn24Hours.forEach { event in
                if let eventId = event.eventIdentifier {
                    notifiedEventMilestones[eventId, default: []].insert(.oneDay)
                }
            }

            if eventsIn24Hours.count == 1, let event = eventsIn24Hours.first {
                let id = "\(event.eventIdentifier ?? UUID().uuidString)_1day"
                let view = AnyView(CalendarNotificationView(event: event, timeUntil: "tomorrow"))
                return (.calendar, .full(view: view, id: id), 60.0)
            } else {
                let id = "multiple_\(eventsIn24Hours.count)_1day_\(eventsIn24Hours.first?.eventIdentifier ?? "")"
                let view = AnyView(MultipleCalendarNotificationView(events: eventsIn24Hours, timeUntil: "tomorrow"))
                return (.calendar, .full(view: view, id: id), 60.0)
            }
        }

        if let nextEvent = calendarService.upcomingEvents.first(where: { $0.startDate > Date() }), let eventId = nextEvent.eventIdentifier, !eventId.isEmpty {
            let timeUntilEvent = nextEvent.startDate.timeIntervalSinceNow
            if timeUntilEvent > 0 && timeUntilEvent <= 10 * 60 {
                return (.calendar, .standard(data: .calendar(event: nextEvent), id: eventId), nil)
            }
        }

        return nil
    }

    private func checkForReminder() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.remindersLiveActivityEnabled else { return nil }
        for reminder in calendarService.upcomingReminders {
            let reminderId = reminder.calendarItemIdentifier
            guard !reminderId.isEmpty, let dueDate = reminder.dueDateComponents?.date else { continue }
            if notifiedReminderMilestones[reminderId] == nil { notifiedReminderMilestones[reminderId] = [] }
            let now = Date()
            let thirtyMinBefore = dueDate.addingTimeInterval(-30 * 60)
            if now >= thirtyMinBefore && !notifiedReminderMilestones[reminderId]!.contains(.thirtyMinutes) {
                notifiedReminderMilestones[reminderId]!.insert(.thirtyMinutes)
                return (.reminder, .full(view: AnyView(ReminderNotificationView(reminder: reminder, timeUntil: "in about 30 minutes")), id: "\(reminderId)_30min"), 60.0)
            }
        }
        if let nextReminder = calendarService.upcomingReminders.first, let dueDate = nextReminder.dueDateComponents?.date {
            let reminderId = nextReminder.calendarItemIdentifier
            guard !reminderId.isEmpty else { return nil }
            let timeUntilReminder = dueDate.timeIntervalSinceNow
            if timeUntilReminder > 0 && timeUntilReminder <= 10 * 60 { return (.reminder, .standard(data: .reminder(reminder: nextReminder), id: reminderId), nil) }
        }
        return nil
    }

    private func checkForTimer() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.timersLiveActivityEnabled, timerManager.isRunning else { return nil }
        return (.timer, .standard(data: .timer, id: "active_timer"), nil)
    }

    private func checkForFileShelf() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let fileShelfManager = fileShelfManager, settingsModel.settings.fileShelfLiveActivityEnabled, !fileShelfManager.files.isEmpty else { return nil }
        let count = fileShelfManager.files.count
        return (.fileShelf, .standard(data: .fileShelf(count: count), id: "file_shelf_\(count)"), nil)
    }

    private func checkForEyeBreak() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        if !eyeBreakManager.isBreakTime { hasShownCurrentEyeBreak = false }
        guard settingsModel.settings.eyeBreakLiveActivityEnabled, eyeBreakManager.isBreakTime, !hasShownCurrentEyeBreak else { return nil }
        return (.eyeBreak, .full(view: AnyView(EyeBreakFullActivityView()), id: "eye_break_active_full"), nil)
    }

    private func checkForDesktopChange() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.desktopLiveActivityEnabled, let desktopNum = desktopManager.currentDesktopNumber, desktopNum != lastShownDesktopNumber else { return nil }
        return (.desktopChange, .standard(data: .desktop(number: desktopNum), id: desktopNum), 2.0)
    }

    private func checkForFocusMode() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.focusLiveActivityEnabled else { return nil }

        let newStatus = focusModeManager.currentStatus
        let oldStatus = lastKnownFocusStatus
        self.lastKnownFocusStatus = newStatus

        if newStatus.isActive && !(oldStatus?.isActive ?? false) {
            let modeInfo = newStatus.toFocusModeInfo(isActive: true)
            return (.focusModeChange, .standard(data: .focus(mode: modeInfo), id: newStatus.identifier), 4.0)
        }

        if !newStatus.isActive && (oldStatus?.isActive ?? false) {
            let offModeInfo = FocusModeInfo(name: "Off", identifier: "focus.off.activity", symbolName: oldStatus?.symbolName ?? "moon.zzz.fill", tintColorName: "systemGrayColor", tintColorNames: nil, isActive: false)
            return (.focusModeChange, .standard(data: .focus(mode: offModeInfo), id: offModeInfo.identifier), 2.0)
        }

        if newStatus.isActive && (oldStatus?.isActive ?? false) && newStatus.identifier != oldStatus?.identifier {
            let modeInfo = newStatus.toFocusModeInfo(isActive: true)
            return (.focusModeChange, .standard(data: .focus(mode: modeInfo), id: newStatus.identifier), 4.0)
        }

        return nil
    }

    private func checkForNearDrop() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let payload = currentNearDropPayload else { return nil }
        let content: LiveActivityContent = (payload.state == .waitingForConsent) ? .full(view: AnyView(NearDropLiveActivityView(payload: payload)), id: payload) : .standard(data: .nearDrop(payload: payload), id: payload)
        return (.nearbyShare, content, (payload.state == .waitingForConsent) ? 60.0 : nil)
    }

    private func checkForFileProgress() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.fileProgressLiveActivityEnabled, let task = FileDropManager.shared.tasks.first(where: {
            if case .universalTransfer = $0 { return true }; if case .airDrop = $0 { return true }; return false
        }) else { return nil }
        return (.fileProgress, .standard(data: .fileProgress(task: task), id: task.id), nil)
    }

    private func checkForGeminiLive() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let payload = currentGeminiPayload else { return nil }
        return (.geminiLive, .standard(data: .geminiLive(payload: payload), id: payload), nil)
    }

    private func checkForNotification() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let notification = notificationManager.latestNotification else { return nil }
        if let until = dismissedNotifications[notification.id], until > Date() { return nil }
        let hoverBinding = Binding<Bool>(get: { self.isNotificationHovered }, set: { self.isNotificationHovered = $0 })
        let fullView = NotificationLiveActivityView(payload: notification, isHovered: hoverBinding)
        return (.notification, .full(view: AnyView(fullView), id: notification.id), 15.0)
    }

    private func checkForAudioSwitch() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let event = audioDeviceManager.lastSwitchEvent, event.id != lastShownAudioSwitchEventID else { return nil }
        return (.audioSwitch, .standard(data: .audioSwitch(event: event), id: event.id), 5.0)
    }

    private func checkForBluetooth() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard let event = bluetoothManager.lastEvent, event != lastShownBluetoothEvent else { return nil }
        let duration: TimeInterval = switch event.eventType { case .connected: 6.0; case .disconnected: 5.0; case .batteryLow: 12.0 }
        return (.bluetooth, .standard(data: .bluetooth(device: event), id: event), duration)
    }

    // MARK: - Public Control Functions
    func dismissCurrentActivity() {
        guard currentActivity != .none else { return }
        if settingsModel.settings.hapticFeedbackEnabled { HapticManager.perform(.alignment) }

        if snoozableActivityTypes.contains(currentActivity) {
            snoozedActivities[currentActivity] = Date().addingTimeInterval(300)
        } else {
            handleActivityDismissal(for: currentActivity)
        }

        setActivity(type: .none, content: .none)
        evaluateAndDisplayActivity()
    }

    private func clearNotificationState() {
        if isNotificationHovered {
            isNotificationHovered = false
        }
    }

    func startLockScreenActivity() {
        guard !isScreenLocked else { return }
        self.isScreenLocked = true
        evaluateAndDisplayActivity()
    }

    func finishLockScreenActivity() {
        guard isScreenLocked else { return }
        self.isScreenLocked = false
        evaluateAndDisplayActivity()
    }

    func startGeminiLive() { guard currentGeminiPayload == nil else { return }; self.currentGeminiPayload = GeminiPayload(isMicMuted: geminiLiveManager.isMicMuted); evaluateAndDisplayActivity() }
    func finishGeminiLive() { self.currentGeminiPayload = nil; evaluateAndDisplayActivity() }
    func startNearDropActivity(transfer: TransferMetadata, device: RemoteDeviceInfo, fileURLs: [URL]) { self.currentNearDropPayload = NearDropPayload(id: transfer.id, device: device, transfer: transfer, destinationURLs: fileURLs); evaluateAndDisplayActivity() }
    func updateNearDropState(to newState: NearDropTransferState) { guard var payload = self.currentNearDropPayload else { return }; payload.state = newState; if newState == .inProgress { payload.progress = 0.0 }; self.currentNearDropPayload = payload; evaluateAndDisplayActivity() }
    func declineNearDropTransfer(id: String) { NearbyConnectionManager.shared.submitUserConsent(transferID: id, accept: false); clearNearDropActivity(id: id) }
    func updateNearDropProgress(id: String, progress: Double) { guard var payload = self.currentNearDropPayload, payload.id == id else { return }; payload.progress = progress; self.currentNearDropPayload = payload }
    func finishNearDropTransfer(id: String, error: Error?) {
        guard var payload = self.currentNearDropPayload, payload.id == id, (payload.state == .waitingForConsent || payload.state == .inProgress) else { return }
        if let error {
            let errorString: String
            if let nearbyError = error as? NearbyError, case .canceled(let reason) = nearbyError {
                errorString = switch reason { case .userRejected: "Declined"; case .userCanceled: "Canceled"; case .notEnoughSpace: "Not enough space"; case .unsupportedType: "Unsupported type"; case .timedOut: "Timed out"; default: "Canceled" }
            } else { errorString = error.localizedDescription }
            payload.state = .failed(errorString.isEmpty ? "Unknown Error" : errorString)
        } else { payload.state = .finished }
        payload.progress = nil
        self.currentNearDropPayload = payload
        Task { try? await Task.sleep(for: .seconds(4)); await MainActor.run { self.clearNearDropActivity(id: id) } }
    }
    func clearNearDropActivity(id: String? = nil) { if id == nil || self.currentNearDropPayload?.id == id { self.currentNearDropPayload = nil; evaluateAndDisplayActivity() } }

    private func setupPeriodicTimer() {
        periodicCheckTimer?.invalidate()
        periodicCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            if self?.currentActivity == .none {
                self?.evaluateAndDisplayActivity()
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
    func mapToVoid() -> AnyPublisher<Void, Never> { map { _ in () }.eraseToAnyPublisher() }
}