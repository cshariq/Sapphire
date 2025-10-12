//
//  AppDelegate.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04.
//
//
//
//
//

import Cocoa
import SwiftUI
import Combine
import UserNotifications
import NearbyShare
import ApplicationServices
import IOBluetooth
import ServiceManagement
import Firebase
import FirebaseAnalytics
import Network

@MainActor
final class LockScreenState: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var isCaffeineActive: Bool = false
    @Published var isFaceIDEnabled: Bool = false
    @Published var isBluetoothUnlockEnabled: Bool = false
}

final class DynamicFocusWindow: NSWindow {
    var isFocusable: Bool = false

    override var canBecomeKey: Bool {
        return isFocusable
    }
    override var canBecomeMain: Bool {
        return isFocusable
    }
}

@MainActor
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate {

    public var notchWindow: NSWindow?
    private var cgsSpace: CGSSpace?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var settingsDelegate: SettingsWindowDelegate?

    private lazy var lockScreenManager = LockScreenManager.shared

    lazy var musicManager: MusicManager = MusicManager.shared
    lazy var systemHUDManager: SystemHUDManager = .shared
    lazy var notificationManager: NotificationManager = NotificationManager()
    lazy var desktopManager: DesktopManager = DesktopManager()
    lazy var focusModeManager: FocusModeManager = FocusModeManager()
    lazy var calendarService: CalendarService = CalendarService()
    lazy var batteryMonitor: BatteryMonitor = BatteryMonitor.shared
    lazy var batteryManager = BatteryManager.shared
    lazy var batteryEstimator: BatteryEstimator = BatteryEstimator(batteryMonitor: self.batteryMonitor)
    lazy var bluetoothManager: BluetoothManager = BluetoothManager()
    lazy var audioDeviceManager: AudioDeviceManager = AudioDeviceManager()
    lazy var multiAudioManager: MultiAudioManager = .shared
    lazy var eyeBreakManager: EyeBreakManager = EyeBreakManager()
    lazy var timerManager: TimerManager = TimerManager()
    lazy var weatherActivityViewModel: WeatherActivityViewModel = WeatherActivityViewModel()
    lazy var contentPickerHelper: ContentPickerHelper = ContentPickerHelper()
    lazy var geminiLiveManager: GeminiLiveManager = GeminiLiveManager()
    lazy var settingsModel: SettingsModel = SettingsModel.shared
    lazy var activeAppMonitor: ActiveAppMonitor = .shared
    lazy var powerStateController: PowerStateController = PowerStateController()
    lazy var scheduleManager: ScheduleManager = .shared
    lazy var keyboardShortcutManager: KeyboardShortcutManager = .shared
    lazy var globalDragManager: GlobalDragManager = .shared
    lazy var fileShelfManager: FileShelfManager = .shared
    lazy var authManager: AuthenticationManager = AuthenticationManager.shared
    private lazy var lockScreenState = LockScreenState()
    private lazy var caffeineManager = CaffeineManager.shared
    private var activeUnlockID: UUID?

    private var cancellables = Set<AnyCancellable>()

    var isScreenLocked = false
    private var isAuthenticating = false

    private var launchpadWindowController: LaunchpadWindowController?
    private lazy var launchpadGestureMonitor: LaunchpadGestureMonitor = .shared

    private var statusItem: NSStatusItem?

    private var networkMonitor: NWPathMonitor? // <-- ADD NETWORK MONITOR PROPERTY

    lazy var liveActivityManager: LiveActivityManager = LiveActivityManager(
        systemHUDManager: self.systemHUDManager, notificationManager: self.notificationManager, desktopManager: self.desktopManager,
        focusModeManager: self.focusModeManager, musicWidget: self.musicManager, calendarService: self.calendarService,
        batteryMonitor: self.batteryMonitor, bluetoothManager: self.bluetoothManager, audioDeviceManager: self.audioDeviceManager,
        eyeBreakManager: self.eyeBreakManager, timerManager: self.timerManager, weatherActivityViewModel: self.weatherActivityViewModel,
        geminiLiveManager: self.geminiLiveManager, settingsModel: self.settingsModel, activeAppMonitor: self.activeAppMonitor,
        batteryEstimator: self.batteryEstimator
    )

    func unregisterHelper() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("[AppDelegate] Unregistration failed (this is expected if it wasn't registered): \(error.localizedDescription)")
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        FirebaseApp.configure()

        NearbyConnectionManager.shared.deviceDisplayName = settingsModel.settings.neardropDeviceDisplayName

        settingsModel.$settings
            .map(\.neardropDeviceDisplayName)
            .removeDuplicates()
            .sink { newName in
                NearbyConnectionManager.shared.deviceDisplayName = newName
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.launchAtLogin)
            .removeDuplicates()
            .sink { shouldLaunch in
                self.toggleLaunchAtLogin(isOn: shouldLaunch)
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.hideFromScreenSharing)
            .removeDuplicates()
            .sink { [weak self] hide in
                self?.updateWindowSharing(hide: hide)
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.launchpadEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled {
                    self?.setupLaunchpad()
                } else {
                    self?.teardownLaunchpad()
                }
                self?.setupStatusBarItem() // <-- MODIFICATION: Re-evaluate status bar when launchpad setting changes.
            }
            .store(in: &cancellables)

        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            startMainApp()
        } else {
            showOnboardingWindow()
        }
    }

    private func initializeCoreManagers() {
        let managers: [Any] = [
            musicManager, systemHUDManager, notificationManager, desktopManager, focusModeManager,
            calendarService, batteryMonitor, batteryManager, bluetoothManager, audioDeviceManager,
            multiAudioManager, eyeBreakManager, timerManager, weatherActivityViewModel,
            contentPickerHelper, geminiLiveManager, settingsModel, activeAppMonitor,
            powerStateController, scheduleManager, keyboardShortcutManager, globalDragManager,
            fileShelfManager, authManager, liveActivityManager // This initializes the entire dependency graph
        ]
        _ = managers.count
    }

    private func initializeBackgroundServices() {
        DispatchQueue.global(qos: .userInitiated).async {

            self.initializeCoreManagers()
            _ = IOBluetoothDevice.pairedDevices()
            NearbyConnectionManager.shared.becomeVisible()
            Task {
                _ = await self.batteryManager.getBatteryTemperature()
            }
        }
    }

    func showOnboardingWindow() {
        Analytics.logEvent("onboarding_started", parameters: nil)

        if onboardingWindow == nil {
            let window = KeyableWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                styleMask: [.titled, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )

            window.center()

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            if let close = window.standardWindowButton(.closeButton) { close.isHidden = true }
            if let mini = window.standardWindowButton(.miniaturizeButton) { mini.isHidden = true }
            if let zoom = window.standardWindowButton(.zoomButton) { zoom.isHidden = true }

            window.title = "Welcome to Sapphire"
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly

            let hostingView = NSHostingView(rootView: OnboardingView(onComplete: { self.onboardingDidComplete() })
                .environmentObject(settingsModel)
                .environmentObject(musicManager)
            )
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor

            window.contentView = hostingView
            onboardingWindow = window
        }

        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.level = .normal
        NSApp.activate(ignoringOtherApps: true)
    }

    func onboardingDidComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        Analytics.logEvent("onboarding_completed", parameters: nil) // Log completion
        self.onboardingWindow?.orderOut(nil)
        self.onboardingWindow = nil
        startMainApp()
    }

    func startMainApp() {
        Analytics.logEvent("main_app_started", parameters: nil)

        createNotchWindow()
        setupStatusBarItem()
        transitionToAgentApp()

        initializeBackgroundServices()

        liveActivityManager.fileShelfManager = self.fileShelfManager

        OSDManager.disableSystemHUD()
        SystemControl.configureKeyboardBacklight()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        setupSessionObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        UNUserNotificationCenter.current().delegate = self
        NearbyConnectionManager.shared.mainAppDelegate = self

        UpdateChecker.shared.startPeriodicChecks(interval: 5 * 60 * 60)

        if settingsModel.settings.launchpadEnabled {
            setupLaunchpad()
        }
    }

    private func setupSessionObservers() {
        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(self, selector: #selector(screenIsLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenIsUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)

        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                DispatchQueue.main.async {
                    print("[AppDelegate] Network connection re-established.")
                    self?.musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    @objc private func systemDidWake(notification: NSNotification) {
        print("[AppDelegate] System did wake from sleep.")
        musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
    }

    @objc private func screenIsLocked() {

        self.activeUnlockID = nil
        isScreenLocked = true

        lockScreenState.isUnlocked = false
        lockScreenState.isAuthenticating = false
        lockScreenState.isCaffeineActive = caffeineManager.isActive
        lockScreenState.isFaceIDEnabled = settingsModel.settings.faceIDUnlockEnabled && settingsModel.settings.hasRegisteredFaceID
        lockScreenState.isBluetoothUnlockEnabled = settingsModel.settings.bluetoothUnlockEnabled

        if settingsModel.settings.lockScreenLiveActivityEnabled {
            liveActivityManager.startLockScreenActivity()
        }

        if !isAuthenticating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard self.isScreenLocked else { return }
                self.startAuthentication()
            }
        }

        self.bluetoothManager.forceBatteryUpdateScan()

        weatherActivityViewModel.fetch()

        if settingsModel.settings.lockScreenShowNotch, let notchWindow = notchWindow {
            lockScreenManager.delegateWindow(notchWindow)
        }

        guard let mainScreen = NSScreen.main else { return }
        var widgetConfigs: [LockScreenManager.LockScreenWidgetConfig] = []

        if settingsModel.settings.lockScreenShowInfoWidget {
            let infoWidgetView = LockScreenInfoWidgetView()
                .environmentObject(self.settingsModel)
                .environmentObject(self.weatherActivityViewModel)
                .environmentObject(self.calendarService)
                .environmentObject(self.musicManager)
                .environmentObject(self.focusModeManager)
                .environmentObject(self.bluetoothManager)
                .environmentObject(self.batteryMonitor)

            widgetConfigs.append(.init(
                id: "infoWidget",
                view: AnyView(infoWidgetView),
                initialSize: .zero,
                positioner: lockScreenManager.calculateInfoWidgetFrame(size:screen:)
            ))
        }

        if settingsModel.settings.lockScreenShowMainWidget && !settingsModel.settings.lockScreenMainWidgets.isEmpty {
            let mainWidgetContainer = LockScreenMainWidgetContainerView()
                .environmentObject(self.settingsModel)
                .environmentObject(self.musicManager)
                .environmentObject(self.calendarService)

            widgetConfigs.append(.init(
                id: "mainWidgetContainer",
                view: AnyView(mainWidgetContainer),
                initialSize: .zero, // Size will be determined by the view's content
                positioner: lockScreenManager.calculateMainWidgetFrame(size:screen:)
            ))
        }

        if settingsModel.settings.lockScreenShowMiniWidgets && !settingsModel.settings.lockScreenMiniWidgets.isEmpty {
            let miniWidgetView = LockScreenMiniWidgetView()
                .environmentObject(self.settingsModel)
                .environmentObject(self.weatherActivityViewModel)
                .environmentObject(self.calendarService)
                .environmentObject(self.musicManager)
                .environmentObject(self.batteryMonitor)
                .environmentObject(self.bluetoothManager)
                .environmentObject(self.batteryEstimator)

            widgetConfigs.append(.init(
                id: "miniWidgets",
                view: AnyView(miniWidgetView),
                initialSize: .zero,
                positioner: lockScreenManager.calculateMiniWidgetFrame(size:screen:)
            ))
        }

        lockScreenManager.setupAndShowWindows(configs: widgetConfigs, on: mainScreen)

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func screenIsUnlocked() {
        guard isScreenLocked else { return }
        lockScreenManager.hideAndDestroyWindows()
        if let notchWindow = notchWindow, let cgsSpace = cgsSpace {
            lockScreenManager.removeWindow(notchWindow)
            cgsSpace.windows.insert(notchWindow)
            notchWindow.orderFront(nil)
        }

        lockScreenState.isUnlocked = true
        lockScreenState.isAuthenticating = false

        let currentUnlockID = UUID()
        self.activeUnlockID = currentUnlockID

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.activeUnlockID == currentUnlockID else {
                return
            }

            self.isScreenLocked = false
            self.stopAuthentication()
            self.liveActivityManager.finishLockScreenActivity()
            self.lockScreenManager.hideAndDestroyWindows()
        }
    }

    private func startAuthentication() {
        guard isScreenLocked, !isAuthenticating else { return }

        isAuthenticating = true
        lockScreenState.isAuthenticating = true

        if settingsModel.settings.bluetoothUnlockEnabled {
            authManager.startBluetoothAuthentication()
        }

        if settingsModel.settings.faceIDUnlockEnabled && settingsModel.settings.hasRegisteredFaceID {
            authManager.startFaceIDAuthentication()
        }
    }

    private func stopAuthentication() {
        guard isAuthenticating else { return }

        isAuthenticating = false
        lockScreenState.isAuthenticating = false

        authManager.stopAllAuthentication()
    }

    private func transitionToAgentApp() {
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        OSDManager.enableSystemHUD()
        NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        cgsSpace = nil
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)

        networkMonitor?.cancel() // <-- CLEAN UP NETWORK MONITOR

        UpdateChecker.shared.stopPeriodicChecks()

        teardownLaunchpad()

        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc func handleGetURL(event: NSAppleEventDescriptor!, withReplyEvent: NSAppleEventDescriptor!) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = URL(string: urlString) else { return }
        if url.scheme == "sapphire" {
            musicManager.spotifyOfficialAPI.handleRedirect(url: url)
        }
    }

    private func setupStatusBarItem() {
        if settingsModel.settings.launchpadEnabled {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                if let button = statusItem?.button {
                    button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Sapphire Launchpad")
                }

                let menu = NSMenu()
                menu.addItem(NSMenuItem(title: "Show Launchpad", action: #selector(showLaunchpadAction), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
                menu.addItem(NSMenuItem(title: "Quit Sapphire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
                statusItem?.menu = menu
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    @objc private func showLaunchpadAction() {
        if launchpadWindowController == nil && settingsModel.settings.launchpadEnabled {
            setupLaunchpad()
        }
        launchpadWindowController?.showLaunchpad()
    }

    private func setupLaunchpad() {
        guard launchpadWindowController == nil else { return }

        setupStatusBarItem()

        DispatchQueue.main.async {
            self.launchpadWindowController = LaunchpadWindowController()
            self.launchpadGestureMonitor.onShowLaunchpad = { [weak self] in
                self?.launchpadWindowController?.showLaunchpad()
            }
            self.launchpadGestureMonitor.onHideLaunchpad = { [weak self] in
                self?.launchpadWindowController?.hideLaunchpad()
            }
            self.launchpadGestureMonitor.startMonitoring()
        }
    }

    private func teardownLaunchpad() {
        launchpadWindowController?.hideLaunchpad()
        launchpadGestureMonitor.stopMonitoring()
        launchpadGestureMonitor.onShowLaunchpad = nil
        launchpadGestureMonitor.onHideLaunchpad = nil
        launchpadWindowController?.close()
        launchpadWindowController = nil

        setupStatusBarItem()
    }

    func createNotchWindow() {
        notchWindow?.orderOut(nil); notchWindow?.close()

        let targetScreen: NSScreen?
        switch settingsModel.settings.notchDisplayTarget {
        case .macbookDisplay:
            targetScreen = NSScreen.screens.first { screen in
                guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                    return false
                }
                return CGDisplayIsBuiltin(displayID) != 0
            } ?? NSScreen.main
        case .mainDisplay:
            targetScreen = NSScreen.main
        case .allDisplays:
            targetScreen = NSScreen.main
        }

        guard let mainScreen = targetScreen else { return }

        let screenFrame = mainScreen.frame
        let paddedWindowWidth: CGFloat = screenFrame.width, paddedWindowHeight: CGFloat = 400
        let windowOriginX = screenFrame.minX, windowOriginY = screenFrame.maxY - paddedWindowHeight
        let windowRect = NSRect(x: windowOriginX, y: windowOriginY, width: paddedWindowWidth, height: paddedWindowHeight)

        let newWindow = DynamicFocusWindow(contentRect: windowRect, styleMask: .borderless, backing: .buffered, defer: false)

        self.notchWindow = newWindow
        guard let window = self.notchWindow else { return }
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly

        if self.cgsSpace == nil { self.cgsSpace = CGSSpace() }; self.cgsSpace?.windows.removeAll(); self.cgsSpace?.windows.insert(window)

        let notchControllerView = NotchController(notchWindow: window)
        let rootViewContainer = VStack(spacing: 0) { notchControllerView; Spacer() }.frame(width: paddedWindowWidth, height: paddedWindowHeight)

        let hostingView = NSHostingView(
            rootView: rootViewContainer
                .environmentObject(lockScreenState)
                .environmentObject(systemHUDManager).environmentObject(musicManager)
                .environmentObject(liveActivityManager).environmentObject(audioDeviceManager).environmentObject(bluetoothManager)
                .environmentObject(notificationManager).environmentObject(desktopManager).environmentObject(focusModeManager)
                .environmentObject(eyeBreakManager).environmentObject(timerManager).environmentObject(contentPickerHelper)
                .environmentObject(geminiLiveManager).environmentObject(settingsModel).environmentObject(activeAppMonitor)
                .environmentObject(batteryEstimator)
                .environmentObject(DragStateManager.shared)
                .environmentObject(calendarService)
        )
        hostingView.frame = NSRect(origin: .zero, size: windowRect.size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true; hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hostingView; window.orderFront(nil)
    }

    func makeNotchWindowFocusable() {
        guard let window = notchWindow as? DynamicFocusWindow else { return }

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        window.ignoresMouseEvents = false
        window.isFocusable = true

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func revertNotchWindowFocus() {
        guard let window = notchWindow as? DynamicFocusWindow else { return }

        if window.isKeyWindow {
            window.resignKey()
        }

        window.isFocusable = false
        window.ignoresMouseEvents = true

        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func openSettingsWindow() {
        if let window = settingsWindow {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let newWindow = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 950, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        newWindow.center(); newWindow.isMovableByWindowBackground = true
        newWindow.title = "Sapphire Settings"
        newWindow.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView
            .environment(\.window, newWindow)
            .environmentObject(settingsModel)
            .environmentObject(musicManager)
        )
        newWindow.contentView = hostingView

        self.settingsDelegate = SettingsWindowDelegate {
            self.transitionToAgentApp()
            self.settingsWindow = nil
        }
        newWindow.delegate = self.settingsDelegate

        self.settingsWindow = newWindow
        NSApp.setActivationPolicy(.regular)
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func screenParametersChanged(notification: Notification) {
        createNotchWindow()
    }

    private func toggleLaunchAtLogin(isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[AppDelegate] Failed to update launch at login status: \(error)")
        }
    }

    private func updateWindowSharing(hide: Bool) {
        let sharingType: NSWindow.SharingType = hide ? .none : .readOnly
        notchWindow?.sharingType = sharingType
        onboardingWindow?.sharingType = sharingType
        settingsWindow?.sharingType = sharingType
    }

    @objc private func onDisplayWake() {
        if isScreenLocked && !isAuthenticating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard self.isScreenLocked && !self.isAuthenticating else { return }
                self.startAuthentication()
            }
        }
    }

    func wakeDisplay() {
        let task = Process()
        task.launchPath = "/usr/bin/caffeinate"
        task.arguments = ["-u", "-t", "1"]
        try? task.run()
    }

    func sleepDisplay() {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, fileURLs: [URL]) {
        DispatchQueue.main.async { self.liveActivityManager.startNearDropActivity(transfer: transfer, device: device, fileURLs: fileURLs) }
    }

    func incomingTransfer(id: String, didUpdateProgress progress: Double) {
        DispatchQueue.main.async { self.liveActivityManager.updateNearDropProgress(id: id, progress: progress) }
    }

    func incomingTransfer(id: String, didFinishWith error: Error?) {
        DispatchQueue.main.async { self.liveActivityManager.finishNearDropTransfer(id: id, error: error) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let transferID = response.notification.request.content.userInfo["transferID"] as? String {
            let accepted = response.actionIdentifier == "ACCEPT"
            NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accepted)
            if accepted { liveActivityManager.updateNearDropState(to: .inProgress) } else { liveActivityManager.clearNearDropActivity() }
        }
        completionHandler()
    }
}

fileprivate class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}