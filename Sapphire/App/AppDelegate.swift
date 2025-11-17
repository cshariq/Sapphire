//
//  AppDelegate.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04
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
import FirebaseCrashlytics
import Network

@MainActor
final class LockScreenState: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var isCaffeineActive: Bool = false
    @Published var isFaceIDEnabled: Bool = false
    @Published var isBluetoothUnlockEnabled: Bool = false
}

final class DynamicFocusWindow: NSPanel {
    var isFocusable: Bool = false
    override var canBecomeKey: Bool { isFocusable }
    override var canBecomeMain: Bool { isFocusable }
}

@MainActor
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate, NSWindowDelegate {

    public var notchWindow: NSWindow?
    private var cgsSpace: CGSSpace?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private lazy var lockScreenManager = LockScreenManager.shared

    lazy var musicManager: MusicManager = .shared
    lazy var systemHUDManager: SystemHUDManager = .shared
    lazy var notificationManager: NotificationManager = NotificationManager()
    lazy var desktopManager: DesktopManager = DesktopManager()
    lazy var focusModeManager: FocusModeManager = FocusModeManager()
    lazy var calendarService: CalendarService = CalendarService()
    lazy var batteryMonitor: BatteryMonitor = .shared
    lazy var batteryManager = BatteryManager.shared
    lazy var batteryEstimator: BatteryEstimator = BatteryEstimator(batteryMonitor: batteryMonitor)
    lazy var bluetoothManager: BluetoothManager = BluetoothManager()
    lazy var audioDeviceManager: AudioDeviceManager = AudioDeviceManager()
    lazy var multiAudioManager: MultiAudioManager = .shared
    lazy var eyeBreakManager: EyeBreakManager = EyeBreakManager()
    lazy var timerManager: TimerManager = TimerManager()
    lazy var weatherActivityViewModel: WeatherActivityViewModel = WeatherActivityViewModel()
    lazy var contentPickerHelper: ContentPickerHelper = ContentPickerHelper()
    lazy var geminiLiveManager: GeminiLiveManager = GeminiLiveManager()
    lazy var settingsModel: SettingsModel = .shared
    lazy var activeAppMonitor: ActiveAppMonitor = .shared
    lazy var powerStateController: PowerStateController = PowerStateController()
    lazy var scheduleManager: ScheduleManager = .shared
    lazy var keyboardShortcutManager: KeyboardShortcutManager = .shared
    lazy var globalDragManager: GlobalDragManager = .shared
    lazy var batteryDataLogger: BatteryDataLogger = .shared
    lazy var fileShelfManager: FileShelfManager = .shared
    lazy var authManager: AuthenticationManager = .shared

    var statusBarController: StatusBarController?
    var interactionManager: MenuBarInteractionManager?

    private var appearanceManager: MenuBarAppearanceManager?

    private lazy var lockScreenState = LockScreenState()
    private lazy var caffeineManager = CaffeineManager.shared

    private var cancellables = Set<AnyCancellable>()

    var isScreenLocked = false
    private var isAuthenticating = false

    private var launchpadWindowController: LaunchpadWindowController?
    private lazy var launchpadGestureMonitor: LaunchpadGestureMonitor = .shared

    private var statusItem: NSStatusItem?
    private var networkMonitor: NWPathMonitor?
    private var previouslyFrontmostApp: NSRunningApplication?

    lazy var liveActivityManager: LiveActivityManager = LiveActivityManager(
        systemHUDManager: systemHUDManager,
        notificationManager: notificationManager,
        desktopManager: desktopManager,
        focusModeManager: focusModeManager,
        musicWidget: musicManager,
        calendarService: calendarService,
        batteryMonitor: batteryMonitor,
        bluetoothManager: bluetoothManager,
        audioDeviceManager: audioDeviceManager,
        eyeBreakManager: eyeBreakManager,
        timerManager: timerManager,
        weatherActivityViewModel: weatherActivityViewModel,
        geminiLiveManager: geminiLiveManager,
        settingsModel: settingsModel,
        activeAppMonitor: activeAppMonitor,
        batteryEstimator: batteryEstimator,
        batteryStatusManager: BatteryStatusManager.shared
    )

    // MARK: - Lifecycle

    func unregisterHelper() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("[AppDelegate] Unregistration failed (maybe not registered yet): \(error.localizedDescription)")
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        FirebaseApp.configure()
        NearbyConnectionManager.shared.deviceDisplayName = settingsModel.settings.neardropDeviceDisplayName
        observeSettings()
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            startMainApp()
        } else {
            showOnboardingWindow()
        }
    }

    private func observeSettings() {
        settingsModel.$settings
            .map(\.neardropDeviceDisplayName)
            .removeDuplicates()
            .sink { NearbyConnectionManager.shared.deviceDisplayName = $0 }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.launchAtLogin)
            .removeDuplicates()
            .sink { [weak self] in self?.toggleLaunchAtLogin(isOn: $0) }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.hideFromScreenSharing)
            .removeDuplicates()
            .sink { [weak self] in self?.updateWindowSharing(hide: $0) }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.launchpadEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.setupLaunchpad() } else { self?.teardownLaunchpad() }
                self?.setupStatusBarItem()
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.menuBarEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    if self.statusBarController == nil {
                        self.statusBarController = StatusBarController()
                        self.interactionManager = MenuBarInteractionManager.shared
                        self.interactionManager?.startMonitoring()
                        self.appearanceManager = MenuBarAppearanceManager()
                    }
                } else {
                    self.interactionManager?.stopMonitoring()
                    self.interactionManager = nil
                    self.statusBarController = nil
                    self.appearanceManager = nil
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Onboarding

    func showOnboardingWindow() {
        Analytics.logEvent("onboarding_started", parameters: nil)

        NSApp.setActivationPolicy(.accessory)

        if onboardingWindow == nil {
            let window = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900), styleMask: [.borderless, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.center()
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.title = "Sapphire Onboarding"
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly
            let hostingView = NSHostingView(rootView: OnboardingView(onComplete: { self.onboardingDidComplete() }).environmentObject(settingsModel).environmentObject(musicManager))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = hostingView
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func onboardingDidComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        Analytics.logEvent("onboarding_completed", parameters: nil)
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        startMainApp()
        DispatchQueue.main.async { self.openSettingsWindow() }
    }

    func startMainApp() {
        Analytics.logEvent("main_app_started", parameters: nil)

        HelperManager.shared.installIfNeeded()
        XPCClient.shared.start()

        createNotchWindow()
        setupStatusBarItem()
        transitionToAgentApp()
        initializeBackgroundServices()
        if settingsModel.settings.menuBarEnabled {
            if statusBarController == nil {
                statusBarController = StatusBarController()
                interactionManager = MenuBarInteractionManager.shared
                interactionManager?.startMonitoring()
                appearanceManager = MenuBarAppearanceManager()
            }
        }

        liveActivityManager.fileShelfManager = fileShelfManager
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

    private func initializeCoreManagers() {
        _ = StatsManager.shared
        _ = [musicManager, systemHUDManager, notificationManager, desktopManager, focusModeManager, calendarService, batteryMonitor, batteryManager, bluetoothManager, audioDeviceManager, multiAudioManager, eyeBreakManager, timerManager, weatherActivityViewModel, contentPickerHelper, geminiLiveManager, settingsModel, activeAppMonitor, powerStateController, scheduleManager, keyboardShortcutManager, globalDragManager, fileShelfManager, authManager, liveActivityManager].count
    }

    private func initializeBackgroundServices() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.initializeCoreManagers()
            _ = IOBluetoothDevice.pairedDevices()
            NearbyConnectionManager.shared.becomeVisible()
            Task { _ = await self.batteryManager.getBatteryTemperature() }
        }
    }

    // MARK: - Session Observers

    private func setupSessionObservers() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenIsLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenIsUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async {
                print("[AppDelegate] Network connection re-established.")
                self?.musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
            }
        }
        networkMonitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    @objc private func systemDidWake(notification: NSNotification) {
        musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
    }

    // MARK: - Lock Screen

    @objc private func screenIsLocked() {
        isScreenLocked = true
        lockScreenState.isUnlocked = false
        lockScreenState.isAuthenticating = false
        lockScreenState.isCaffeineActive = caffeineManager.isActive
        lockScreenState.isFaceIDEnabled = settingsModel.settings.faceIDUnlockEnabled &&
                                          settingsModel.settings.hasRegisteredFaceID
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

        weatherActivityViewModel.fetch()

        if settingsModel.settings.lockScreenShowNotch, let notchWindow {
            lockScreenManager.delegateWindow(notchWindow)
        }

        guard let mainScreen = NSScreen.main else { return }
        var widgetConfigs: [LockScreenManager.LockScreenWidgetConfig] = []

        if settingsModel.settings.lockScreenShowInfoWidget {
            let infoWidgetView = LockScreenInfoWidgetView()
                .environmentObject(settingsModel)
                .environmentObject(weatherActivityViewModel)
                .environmentObject(calendarService)
                .environmentObject(musicManager)
                .environmentObject(focusModeManager)
                .environmentObject(bluetoothManager)
                .environmentObject(batteryMonitor)

            widgetConfigs.append(.init(
                id: "infoWidget",
                view: AnyView(infoWidgetView),
                initialSize: .zero,
                positioner: lockScreenManager.calculateInfoWidgetFrame(size:screen:)
            ))
        }

        if settingsModel.settings.lockScreenShowMainWidget &&
           !settingsModel.settings.lockScreenMainWidgets.isEmpty {
            let mainWidgetContainer = LockScreenMainWidgetContainerView()
                .environmentObject(settingsModel)
                .environmentObject(musicManager)
                .environmentObject(calendarService)
            widgetConfigs.append(.init(
                id: "mainWidgetContainer",
                view: AnyView(mainWidgetContainer),
                initialSize: .zero,
                positioner: lockScreenManager.calculateMainWidgetFrame(size:screen:)
            ))
        }

        if settingsModel.settings.lockScreenShowMiniWidgets &&
           !settingsModel.settings.lockScreenMiniWidgets.isEmpty {
            let miniWidgetView = LockScreenMiniWidgetView()
                .environmentObject(settingsModel)
                .environmentObject(weatherActivityViewModel)
                .environmentObject(calendarService)
                .environmentObject(musicManager)
                .environmentObject(batteryMonitor)
                .environmentObject(bluetoothManager)
                .environmentObject(batteryEstimator)

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
        isScreenLocked = false
        isAuthenticating = false
        lockScreenState.isUnlocked = true
        lockScreenState.isAuthenticating = false

        authManager.stopAllAuthentication()

        lockScreenManager.hideAndDestroyWindows()
        liveActivityManager.finishLockScreenActivity()
        authManager.didCompleteUnlock()

        if let notchWindow, let cgsSpace {
            lockScreenManager.removeWindow(notchWindow)
            cgsSpace.windows.insert(notchWindow)
            notchWindow.orderFront(nil)
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

    // MARK: - Activation Policy

    private func transitionToAgentApp() {
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: - Termination

    func applicationWillTerminate(_ aNotification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        cgsSpace = nil
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        networkMonitor?.cancel()
        UpdateChecker.shared.stopPeriodicChecks()
        teardownLaunchpad()
        interactionManager?.stopMonitoring()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - URL Handling

    @objc func handleGetURL(event: NSAppleEventDescriptor!, withReplyEvent: NSAppleEventDescriptor!) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme == "sapphire"
        else { return }
        musicManager.spotifyOfficialAPI.handleRedirect(url: url)
    }

    // MARK: - Status Bar Item (Launchpad / Main Toggle)

    private func statusItemPreferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    private func seedStatusItemPreferredPositionIfNeeded(autosaveName: String, seed: Int) {
        let key = statusItemPreferredPositionKey(for: autosaveName)
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(seed, forKey: key)
        }
    }

    private func setupStatusBarItem() {
        if settingsModel.settings.launchpadEnabled {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                statusItem?.autosaveName = "SapphireMainStatusItem"
                seedStatusItemPreferredPositionIfNeeded(autosaveName: "SapphireMainStatusItem", seed: 3)

                statusItem?.button?.image = NSImage(
                    systemSymbolName: "square.grid.3x3.fill",
                    accessibilityDescription: "Sapphire Launchpad"
                )
                let menu = NSMenu()
                menu.addItem(NSMenuItem(title: "Show Launchpad", action: #selector(showLaunchpadAction), keyEquivalent: ""))
                menu.addItem(.separator())
                menu.addItem(.separator())
                menu.addItem(NSMenuItem(title: "Quit Sapphire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
                for item in menu.items { item.target = self }
                statusItem?.menu = menu
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
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

    // MARK: - Notch Window

    func createNotchWindow() {
        if let oldWindow = notchWindow {
            notchWindow = nil
            cgsSpace?.windows.remove(oldWindow)
            oldWindow.orderOut(nil)
            oldWindow.close()
        }

        let targetScreen: NSScreen? = {
            switch settingsModel.settings.notchDisplayTarget {
            case .macbookDisplay:
                return NSScreen.screens.first {
                    if let displayID = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                        return CGDisplayIsBuiltin(displayID) != 0
                    }
                    return false
                } ?? NSScreen.main
            case .mainDisplay, .allDisplays:
                return NSScreen.main
            }
        }()

        guard let mainScreen = targetScreen else { return }
        let screenFrame = mainScreen.frame
        let paddedWidth = screenFrame.width
        let paddedHeight: CGFloat = 400
        let rect = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - paddedHeight,
            width: paddedWidth,
            height: paddedHeight
        )

        let window = DynamicFocusWindow(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        notchWindow = window
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly

        if cgsSpace == nil { cgsSpace = CGSSpace() }
        cgsSpace?.windows.insert(window)

        let controllerView = NotchController(notchWindow: window)
        let container = VStack(spacing: 0) {
            controllerView
            Spacer()
        }
        .frame(width: paddedWidth, height: paddedHeight)

        let hosting = NSHostingView(
            rootView: container
                .environmentObject(lockScreenState)
                .environmentObject(systemHUDManager)
                .environmentObject(musicManager)
                .environmentObject(liveActivityManager)
                .environmentObject(audioDeviceManager)
                .environmentObject(bluetoothManager)
                .environmentObject(notificationManager)
                .environmentObject(desktopManager)
                .environmentObject(focusModeManager)
                .environmentObject(eyeBreakManager)
                .environmentObject(timerManager)
                .environmentObject(contentPickerHelper)
                .environmentObject(geminiLiveManager)
                .environmentObject(settingsModel)
                .environmentObject(activeAppMonitor)
                .environmentObject(batteryEstimator)
                .environmentObject(DragStateManager.shared)
                .environmentObject(calendarService)
        )
        hosting.frame = rect
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        window.orderFront(nil)
    }

    func makeNotchWindowFocusable() {
        guard let window = notchWindow as? DynamicFocusWindow else { return }
        if previouslyFrontmostApp == nil {
            let currentFrontmost = NSWorkspace.shared.frontmostApplication
            if currentFrontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previouslyFrontmostApp = currentFrontmost
            }
        }
        window.ignoresMouseEvents = false
        window.isFocusable = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func revertNotchWindowFocus() {
        guard let window = notchWindow as? DynamicFocusWindow else { return }
        if window.isKeyWindow { window.resignKey() }
        window.isFocusable = false
        window.ignoresMouseEvents = true
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        previouslyFrontmostApp?.activate(options: [.activateIgnoringOtherApps])
        previouslyFrontmostApp = nil
    }

    // MARK: - Settings Window

    func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 950, height: 650),
            styleMask: [.borderless, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = true

        let root = SettingsView()
            .environment(\.window, window)
            .environmentObject(powerStateController)

        let hosting = NSHostingView(rootView: root)
        window.contentView = hosting
        window.makeFirstResponder(hosting)
        window.delegate = self
        settingsWindow = window

        DispatchQueue.main.async {
            self.settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == settingsWindow {
            settingsWindow = nil
            transitionToAgentApp()
        }
    }

    // MARK: - Screen Parameters

    @objc func screenParametersChanged(notification: Notification) {
        createNotchWindow()
    }

    // MARK: - Launch at Login

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

    // MARK: - Window Sharing

    private func updateWindowSharing(hide: Bool) {
        let sharingType: NSWindow.SharingType = hide ? .none : .readOnly
        notchWindow?.sharingType = sharingType
        onboardingWindow?.sharingType = sharingType
        settingsWindow?.sharingType = sharingType
    }

    // MARK: - Display Power Control

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

    // MARK: - NearDrop Transfers

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, fileURLs: [URL]) {
        DispatchQueue.main.async {
            self.liveActivityManager.startNearDropActivity(transfer: transfer, device: device, fileURLs: fileURLs)
        }
    }

    func incomingTransfer(id: String, didUpdateProgress progress: Double) {
        DispatchQueue.main.async {
            self.liveActivityManager.updateNearDropProgress(id: id, progress: progress)
        }
    }

    func incomingTransfer(id: String, didFinishWith error: Error?) {
        DispatchQueue.main.async {
            self.liveActivityManager.finishNearDropTransfer(id: id, error: error)
        }
    }

    // MARK: - Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let transferID = response.notification.request.content.userInfo["transferID"] as? String {
            let accepted = response.actionIdentifier == "ACCEPT"
            NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accepted)
            if accepted {
                liveActivityManager.updateNearDropState(to: .inProgress)
            } else {
                liveActivityManager.clearNearDropActivity()
            }
        }
        completionHandler()
    }
}

// MARK: - KeyableWindow

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
