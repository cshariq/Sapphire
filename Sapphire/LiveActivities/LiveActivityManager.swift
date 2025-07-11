//
//  LiveActivityManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04.
//

import Foundation
import SwiftUI
import Combine
import EventKit
import NearbyShare


enum ActivityType: Int, Equatable, Comparable, CaseIterable { case none = 0, weather = 5, music = 10, timer = 20, desktopChange = 30, battery = 40, calendar = 50, focusModeChange = 55, bluetooth = 58, audioSwitch = 60, eyeBreak = 70, notification = 80, geminiLive = 85, nearbyShare = 90, systemHUD = 100; static func < (lhs: ActivityType, rhs: ActivityType) -> Bool { return lhs.rawValue < rhs.rawValue }; init?(from settingsType: LiveActivityType) { switch settingsType { case .music: self = .music; case .weather: self = .weather; case .calendar: self = .calendar; case .timers: self = .timer; case .battery: self = .battery; case .eyeBreak: self = .eyeBreak; case .desktop: self = .desktopChange; case .focus: self = .focusModeChange } } }
private struct SystemHUDIdentifier: Hashable { let type: HUDType; let style: HUDStyle }

@MainActor
class LiveActivityManager: ObservableObject {
    @Published private(set) var contentUpdateID = UUID()
    @Published private(set) var currentActivity: ActivityType = .none
    @Published private(set) var activityContent: LiveActivityContent = .none
    @Published private(set) var currentNearDropPayload: NearDropPayload?
    @Published private(set) var currentGeminiPayload: GeminiPayload?
    var showLyricsBinding: Binding<Bool>?
    private var dismissalTimer: Timer?
    private var hasShownPluggedInAlert = false, hasShownLowBatteryAlert = false, hasShownCurrentEyeBreak = false
    private var lastShownCalendarEventID: String?, lastShownDesktopNumber: Int?, lastShownFocusModeID: String?
    private var lastShownBluetoothEvent: BluetoothDeviceState?, lastShownAudioSwitchEventID: UUID?
    @Published private var showNowPlayingText: Bool = false
    private var nowPlayingDismissalTimer: Timer?
    private var activityCheckers: [ActivityType: () -> (ActivityType, LiveActivityContent, TimeInterval?)?] = [:]
    var isFullViewActivity: Bool { if case .full = activityContent { true } else { false } }
    private let systemHUDManager: SystemHUDManager, notificationManager: NotificationManager, desktopManager: DesktopManager
    private let focusModeManager: FocusModeManager, musicWidget: MusicWidget, calendarService: CalendarService
    private let batteryMonitor: BatteryMonitor, bluetoothManager: BluetoothManager, audioDeviceManager: AudioDeviceManager
    private let eyeBreakManager: EyeBreakManager, timerManager: TimerManager, weatherActivityViewModel: WeatherActivityViewModel
    private let geminiLiveManager: GeminiLiveManager, settingsModel: SettingsModel
    private let activeAppMonitor: ActiveAppMonitor
    private var cancellables = Set<AnyCancellable>()

    init(systemHUDManager: SystemHUDManager, notificationManager: NotificationManager, desktopManager: DesktopManager, focusModeManager: FocusModeManager, musicWidget: MusicWidget, calendarService: CalendarService, batteryMonitor: BatteryMonitor, bluetoothManager: BluetoothManager, audioDeviceManager: AudioDeviceManager, eyeBreakManager: EyeBreakManager, timerManager: TimerManager, weatherActivityViewModel: WeatherActivityViewModel, geminiLiveManager: GeminiLiveManager, settingsModel: SettingsModel, activeAppMonitor: ActiveAppMonitor) {
        self.systemHUDManager = systemHUDManager; self.notificationManager = notificationManager; self.desktopManager = desktopManager; self.focusModeManager = focusModeManager; self.musicWidget = musicWidget; self.calendarService = calendarService; self.batteryMonitor = batteryMonitor; self.bluetoothManager = bluetoothManager; self.audioDeviceManager = audioDeviceManager; self.eyeBreakManager = eyeBreakManager; self.timerManager = timerManager; self.weatherActivityViewModel = weatherActivityViewModel; self.geminiLiveManager = geminiLiveManager; self.settingsModel = settingsModel; self.activeAppMonitor = activeAppMonitor
        self.lastShownDesktopNumber = desktopManager.currentDesktopNumber
        self.activityCheckers = [ .systemHUD: self.checkForSystemHUD, .nearbyShare: self.checkForNearDrop, .geminiLive: self.checkForGeminiLive, .notification: self.checkForNotification, .eyeBreak: self.checkForEyeBreak, .audioSwitch: self.checkForAudioSwitch, .bluetooth: self.checkForBluetooth, .focusModeChange: self.checkForFocusMode, .calendar: self.checkForCalendar, .battery: self.checkForBattery, .desktopChange: self.checkForDesktopChange, .timer: self.checkForTimer, .music: self.checkForMusic, .weather: self.checkForWeather ]
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        geminiLiveManager.$isMicMuted.receive(on: DispatchQueue.main).sink { [weak self] newMuteState in guard let self, var payload = self.currentGeminiPayload, payload.isMicMuted != newMuteState else { return }; payload.isMicMuted = newMuteState; self.currentGeminiPayload = payload }.store(in: &cancellables)
        geminiLiveManager.sessionDidEndPublisher.receive(on: DispatchQueue.main).sink { [weak self] in self?.finishGeminiLive() }.store(in: &cancellables)
        let stateChangeTriggers: [AnyPublisher<Void, Never>] = [ systemHUDManager.$currentHUD.mapToVoid(), $currentNearDropPayload.mapToVoid(), $currentGeminiPayload.mapToVoid(), notificationManager.$latestNotification.mapToVoid(), desktopManager.$currentDesktopNumber.mapToVoid(), focusModeManager.$currentFocusMode.mapToVoid(), calendarService.$nextEvent.mapToVoid(), batteryMonitor.$currentState.mapToVoid(), audioDeviceManager.$lastSwitchEvent.mapToVoid(), bluetoothManager.$lastEvent.mapToVoid(), eyeBreakManager.$isBreakTime.mapToVoid(), timerManager.$isRunning.mapToVoid(), weatherActivityViewModel.$weatherData.mapToVoid(), musicWidget.$shouldShowLiveActivity.mapToVoid(), musicWidget.playerActionPublisher.mapToVoid(), $showNowPlayingText.mapToVoid(), settingsModel.objectWillChange.mapToVoid(), activeAppMonitor.$isLyricsAllowedForActiveApp.mapToVoid() ]
        Publishers.MergeMany(stateChangeTriggers).debounce(for: .milliseconds(50), scheduler: RunLoop.main).sink { [weak self] in self?.evaluateAndDisplayActivity() }.store(in: &cancellables)
    }
    
    private func triggerNowPlayingText() { nowPlayingDismissalTimer?.invalidate(); showNowPlayingText = true; nowPlayingDismissalTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in self?.showNowPlayingText = false } }
    private func evaluateAndDisplayActivity(ignoring: ActivityType? = nil) { let highPriorityActivities: [ActivityType] = [.systemHUD, .nearbyShare, .geminiLive, .notification, .audioSwitch, .bluetooth]; let userOrderedActivities = settingsModel.settings.liveActivityOrder.compactMap { ActivityType(from: $0) }; let finalEvaluationOrder = highPriorityActivities + userOrderedActivities; for activityType in finalEvaluationOrder { guard activityType != ignoring, let checker = activityCheckers[activityType] else { continue }; if let (type, content, duration) = checker() { setActivity(type: type, content: content, dismissAfter: duration); return } }; setActivity(type: .none, content: .none) }
    private func setActivity(type: ActivityType, content: LiveActivityContent, dismissAfter duration: TimeInterval? = nil) { if self.currentActivity == type && self.activityContent == content { return }; dismissalTimer?.invalidate(); self.currentActivity = type; self.activityContent = content; self.contentUpdateID = UUID(); if let duration { dismissalTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in guard let self, self.currentActivity == type else { return }; switch type { case .desktopChange: self.lastShownDesktopNumber = self.desktopManager.currentDesktopNumber; case .battery: if let state = self.batteryMonitor.currentState { if state.isLow { self.hasShownLowBatteryAlert = true } else if state.isPluggedIn { self.hasShownPluggedInAlert = true } }; case .focusModeChange: self.lastShownFocusModeID = self.focusModeManager.currentFocusMode?.identifier; case .calendar: self.lastShownCalendarEventID = self.calendarService.nextEvent?.eventIdentifier; case .eyeBreak: self.hasShownCurrentEyeBreak = true; case .bluetooth: self.lastShownBluetoothEvent = self.bluetoothManager.lastEvent; case .audioSwitch: self.lastShownAudioSwitchEventID = self.audioDeviceManager.lastSwitchEvent?.id; default: break }; self.evaluateAndDisplayActivity(ignoring: type) } } }
    
    private func checkForMusic() -> (ActivityType, LiveActivityContent, TimeInterval?)? {
        guard settingsModel.settings.musicLiveActivityEnabled, musicWidget.shouldShowLiveActivity else { return nil }
        let lyricsAllowed = activeAppMonitor.isLyricsAllowedForActiveApp
        
        let bottomViewBuilder: () -> AnyView = {
            let binding = self.showLyricsBinding ?? .constant(false)
            if self.showNowPlayingText {
                return AnyView(NowPlayingTextView(title: self.musicWidget.title ?? "Now Playing"))
            } else if self.musicWidget.isPlaying && lyricsAllowed {
                return AnyView(MusicLyricsView(binding))
            }
            return AnyView(EmptyView())
        }
        
        let view = StandardActivityView(left: { AlbumArtView(image: musicWidget.artwork) }, right: { MusicWaveformView().environmentObject(musicWidget).environmentObject(settingsModel) }, bottom: { bottomViewBuilder() })
        
        
        let identifier = (musicWidget.title ?? "") + (musicWidget.artist ?? "") + "\(musicWidget.isDisplayingTransientIcon)\(musicWidget.isPlaying)\(showNowPlayingText)\(lyricsAllowed)"
        
        return (.music, .standard(view: AnyView(view), id: identifier), nil)
    }

    
    private func checkForWeather() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard settingsModel.settings.weatherLiveActivityEnabled, let data = weatherActivityViewModel.weatherData else { return nil }; return (.weather, .standard(view: AnyView(StandardActivityView(left: { WeatherActivityView.left(for: data) }, right: { WeatherActivityView.right(for: data) })), id: data), nil) }
    private func checkForCalendar() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard settingsModel.settings.calendarLiveActivityEnabled, let event = calendarService.nextEvent, event.startDate.timeIntervalSinceNow < 15 * 60, event.eventIdentifier != lastShownCalendarEventID else { return nil }; return (.calendar, .standard(view: AnyView(StandardActivityView(left: { CalendarActivityView.left(for: event) }, right: { CalendarActivityView.right(for: event) })), id: event.eventIdentifier), 15.0) }
    private func checkForTimer() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard settingsModel.settings.timersLiveActivityEnabled, timerManager.isRunning else { return nil }; return (.timer, .standard(view: AnyView(StandardActivityView(left: { TimerActivityView().environmentObject(timerManager) })), id: "active_timer"), nil) }
    private func checkForBattery() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard settingsModel.settings.batteryLiveActivityEnabled, let state = batteryMonitor.currentState else { return nil }; if !state.isLow { hasShownLowBatteryAlert = false }; if !state.isPluggedIn { hasShownPluggedInAlert = false }; let view = StandardActivityView(left: { BatteryActivityView.left(for: state) }, right: { BatteryActivityView.right(for: state) }); if state.isLow, !hasShownLowBatteryAlert { return (.battery, .standard(view: AnyView(view), id: "low_battery_alert"), 10.0) }; if state.isPluggedIn, !state.isLow, !hasShownPluggedInAlert { return (.battery, .standard(view: AnyView(view), id: state), 5.0) }; return nil }
    private func checkForEyeBreak() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard settingsModel.settings.eyeBreakLiveActivityEnabled, eyeBreakManager.isBreakTime, !hasShownCurrentEyeBreak else { if !eyeBreakManager.isBreakTime { hasShownCurrentEyeBreak = false }; return nil }; return (.eyeBreak, .standard(view: AnyView(StandardActivityView(left: { EyeBreakActivityView.left }, right: { EyeBreakActivityView.right }, bottom: { EyeBreakActivityView.bottom() })), id: "eye_break_active"), 60.0) }
    private func checkForDesktopChange() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard settingsModel.settings.desktopLiveActivityEnabled, let desktopNum = desktopManager.currentDesktopNumber, desktopNum != lastShownDesktopNumber else { return nil }; return (.desktopChange, .standard(view: AnyView(StandardActivityView(left: { DesktopActivityView.left(for: desktopNum) }, right: { DesktopActivityView.right(for: desktopNum) })), id: desktopNum), 2.0) }
    private func checkForFocusMode() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard settingsModel.settings.focusLiveActivityEnabled, let mode = focusModeManager.currentFocusMode, mode.identifier != lastShownFocusModeID else { return nil }; return (.focusModeChange, .standard(view: AnyView(StandardActivityView(left: { FocusModeActivityView.left(for: mode) }, right: { FocusModeActivityView.right(for: mode) })), id: mode.identifier), 4.0) }
    private func checkForSystemHUD() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard let hudType = systemHUDManager.currentHUD else { return nil }; let style: HUDStyle; switch hudType { case .volume: guard settingsModel.settings.enableVolumeHUD else { return nil }; style = settingsModel.settings.volumeHUDStyle; case .brightness: guard settingsModel.settings.enableBrightnessHUD else { return nil }; style = settingsModel.settings.brightnessHUDStyle }; let id = SystemHUDIdentifier(type: hudType, style: style); let content: LiveActivityContent = (style == .default) ? .full(view: AnyView(SystemHUDView(type: hudType)), id: id) : .standard(view: AnyView(StandardActivityView(left: { SystemHUDSlimActivityView.left(type: hudType) }, right: { SystemHUDSlimActivityView.right(type: hudType) })), id: id); return (.systemHUD, content, nil) }
    private func checkForNearDrop() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard let payload = currentNearDropPayload else { return nil }; let content: LiveActivityContent = (payload.state == .waitingForConsent) ? .full(view: AnyView(NearDropLiveActivityView(payload: payload)), id: payload) : .standard(view: AnyView(StandardActivityView(left: { NearDropCompactActivityView.left() }, right: { NearDropCompactActivityView.right(payload: payload) })), id: payload); return (.nearbyShare, content, (payload.state == .waitingForConsent) ? 60.0 : nil) }
    private func checkForGeminiLive() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard let payload = currentGeminiPayload else { return nil }; let rightView = GeminiActiveActivityView.right(isMuted: payload.isMicMuted) { self.geminiLiveManager.isMicMuted.toggle(); if self.geminiLiveManager.isMicMuted { self.geminiLiveManager.signalEndOfUserTurn() } }; return (.geminiLive, .standard(view: AnyView(StandardActivityView(left: { GeminiActiveActivityView.left() }, right: { rightView })), id: payload), nil) }
    private func checkForNotification() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard let notification = notificationManager.latestNotification else { return nil }; let view = StandardActivityView(left: { NotificationActivityView.left(for: notification) }, right: { NotificationActivityView.right(for: notification) }, bottom: { NotificationBottomView(payload: notification) }); return (.notification, .standard(view: AnyView(view), id: notification.id), 15.0) }
    private func checkForAudioSwitch() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard let event = audioDeviceManager.lastSwitchEvent, event.id != lastShownAudioSwitchEventID else { return nil }; return (.audioSwitch, .standard(view: AnyView(StandardActivityView(left: { AudioSwitchActivityView.left(for: event) }, right: { AudioSwitchActivityView.right(for: event) })), id: event.id), 5.0) }
    private func checkForBluetooth() -> (ActivityType, LiveActivityContent, TimeInterval?)? { guard let event = bluetoothManager.lastEvent, event != lastShownBluetoothEvent else { return nil }; let view: AnyView, duration: TimeInterval; switch event.eventType { case .connected: view = AnyView(StandardActivityView(left: { BluetoothActivityView.left(for: event) }, right: { BluetoothActivityView.right(for: event) })); duration = 6.0; case .disconnected: view = AnyView(StandardActivityView(left: { BluetoothDisconnectedActivityView.left(for: event) }, right: { BluetoothDisconnectedActivityView.right(for: event) })); duration = 5.0; case .batteryLow: view = AnyView(StandardActivityView(left: { BluetoothBatteryActivityView.left(for: event) }, right: { BluetoothBatteryActivityView.right(for: event) })); duration = 12.0 }; return (.bluetooth, .standard(view: view, id: event), duration) }
    func startGeminiLive() { guard currentGeminiPayload == nil else { return }; self.currentGeminiPayload = GeminiPayload(isMicMuted: geminiLiveManager.isMicMuted); evaluateAndDisplayActivity() }
    func finishGeminiLive() { self.currentGeminiPayload = nil; evaluateAndDisplayActivity() }
    func startNearDropActivity(transfer: TransferMetadata, device: RemoteDeviceInfo, fileURLs: [URL]) { self.currentNearDropPayload = NearDropPayload(id: transfer.id, device: device, transfer: transfer, destinationURLs: fileURLs); evaluateAndDisplayActivity() }
    func updateNearDropState(to newState: NearDropTransferState) { guard var payload = self.currentNearDropPayload else { return }; payload.state = newState; if newState == .inProgress { payload.progress = 0.0 }; self.currentNearDropPayload = payload; evaluateAndDisplayActivity() }
    func declineNearDropTransfer(id: String) { NearbyConnectionManager.shared.submitUserConsent(transferID: id, accept: false); clearNearDropActivity(id: id) }
    func updateNearDropProgress(id: String, progress: Double) { guard var payload = self.currentNearDropPayload, payload.id == id else { return }; payload.progress = progress; self.currentNearDropPayload = payload }
    func finishNearDropTransfer(id: String, error: Error?) { guard var payload = self.currentNearDropPayload, payload.id == id, (payload.state == .waitingForConsent || payload.state == .inProgress) else { return }; if let error { let errorString: String; if let nearbyError = error as? NearbyError, case .canceled(let reason) = nearbyError { switch reason { case .userRejected: errorString = "Declined"; case .userCanceled: errorString = "Canceled"; case .notEnoughSpace: errorString = "Not enough space"; case .unsupportedType: errorString = "Unsupported type"; case .timedOut: errorString = "Timed out"; default: errorString = "Canceled" } } else { errorString = error.localizedDescription }; payload.state = .failed(errorString.isEmpty ? "Unknown Error" : errorString) } else { payload.state = .finished }; payload.progress = nil; self.currentNearDropPayload = payload; DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { self.clearNearDropActivity(id: id) } }
    func clearNearDropActivity(id: String? = nil) { if id == nil || self.currentNearDropPayload?.id == id { self.currentNearDropPayload = nil; evaluateAndDisplayActivity() } }
}


extension Publisher {
    func mapToVoid() -> AnyPublisher<Void, Never> {
        self
            .map { _ in () }
            .catch { _ in Empty<Void, Never>() }
            .eraseToAnyPublisher()
    }
}
