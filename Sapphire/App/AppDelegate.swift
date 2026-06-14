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
import OSLog

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
    private var interactiveContentFrame: CGRect = .zero
    private var diagnosticsTimer: Timer?
    private var isHandlingMouseInteraction = false
    private var lastPolledMousePoint: CGPoint?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotchDiagnostics")
    private var passthroughRefreshCount = 0
    private var sendEventCount = 0
    private var mouseMovedEventCount = 0
    private var outsideInteractivePollCount = 0
    private var ignoreStateFlipCount = 0
    private var hitTestRejectCount = 0
    private var droppedMoveEventCount = 0

    override var canBecomeKey: Bool { isFocusable }
    override var canBecomeMain: Bool { isFocusable }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        diagnosticsTimer?.invalidate()
    }

    func updateInteractiveContentFrame(_ frame: CGRect) {
        let normalizedFrame = frame.integral.insetBy(dx: -1, dy: -1)
        let previousFrame = interactiveContentFrame

        if !normalizedFrame.isNull, !normalizedFrame.isEmpty {
            interactiveContentFrame = normalizedFrame
        } else if let contentBounds = contentView?.bounds, !contentBounds.isEmpty {
            // Falling back to the content bounds avoids a "windowless" notch state
            // while SwiftUI is still settling size/position updates.
            interactiveContentFrame = contentBounds
        }

        guard interactiveContentFrame != previousFrame else { return }
        refreshMouseEventPassthrough(force: true)
    }

    func containsInteractivePoint(_ point: CGPoint) -> Bool {
        interactiveContentFrame.contains(point)
    }

    func recordHitTestRejection(at point: CGPoint) {
        guard contentView?.bounds.contains(point) == true else { return }
        hitTestRejectCount += 1
    }

    override func sendEvent(_ event: NSEvent) {
        sendEventCount += 1

        if shouldDropPassivePointerEvent(event) {
            droppedMoveEventCount += 1
            return
        }

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            isHandlingMouseInteraction = true
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            isHandlingMouseInteraction = false
        case .mouseMoved:
            mouseMovedEventCount += 1
        default:
            break
        }

        super.sendEvent(event)

        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                .mouseMoved, .mouseEntered, .mouseExited:
            refreshMouseEventPassthrough(force: true)
        default:
            break
        }
    }

    private func refreshMouseEventPassthrough(force: Bool = false) {
        guard contentView != nil else { return }
        guard force || isHandlingMouseInteraction || isVisible else {
            return
        }
        let mousePoint = mouseLocationOutsideOfEventStream
        if !force, !isHandlingMouseInteraction, lastPolledMousePoint == mousePoint {
            return
        }

        lastPolledMousePoint = mousePoint

        let shouldReceiveMouseEvents: Bool
        if isHandlingMouseInteraction {
            shouldReceiveMouseEvents = true
        } else {
            let effectiveInteractiveFrame = interactiveContentFrame.isEmpty ? (contentView?.bounds ?? .zero) : interactiveContentFrame
            shouldReceiveMouseEvents = effectiveInteractiveFrame.contains(mousePoint)
        }

        let shouldIgnoreMouseEvents = !shouldReceiveMouseEvents
        if ignoresMouseEvents != shouldIgnoreMouseEvents {
            ignoresMouseEvents = shouldIgnoreMouseEvents
        }

        let shouldAcceptMouseMovedEvents = shouldReceiveMouseEvents || isHandlingMouseInteraction
        if acceptsMouseMovedEvents != shouldAcceptMouseMovedEvents {
            acceptsMouseMovedEvents = shouldAcceptMouseMovedEvents
        }
    }

    private func shouldDropPassivePointerEvent(_ event: NSEvent) -> Bool {
        guard !isHandlingMouseInteraction else { return false }
        let effectiveInteractiveFrame = interactiveContentFrame.isEmpty ? (contentView?.bounds ?? .zero) : interactiveContentFrame

        switch event.type {
        case .mouseMoved, .mouseEntered, .mouseExited:
            return !effectiveInteractiveFrame.contains(event.locationInWindow)
        default:
            return false
        }
    }
}

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window = window as? DynamicFocusWindow else {
            return super.hitTest(point)
        }

        guard window.containsInteractivePoint(point) else {
            window.recordHitTestRejection(at: point)
            return nil
        }

        return super.hitTest(point)
    }
}

@MainActor
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate, NSWindowDelegate {

    public var notchWindow: NSWindow?
    private var cgsSpace: CGSSpace?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var lyricsWindow: NSWindow?
    private var betaBlockerWindow: NSWindow?
    private var isMainAppRunning = false
    private var subscriptionObservation: AnyCancellable?

    private lazy var lockScreenManager = LockScreenManager.shared
    private lazy var lidAngleAutomationManager = LidAngleAutomationManager.shared

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
    lazy var intelligenceViewModel: IntelligenceNotchViewModel = IntelligenceNotchViewModel()

    var statusBarController: StatusBarController?
    var interactionManager: MenuBarInteractionManager?

    func addWindowToNotchSpace(_ window: NSWindow) {
        if cgsSpace == nil { cgsSpace = CGSSpace() }
        cgsSpace?.windows.insert(window)
    }

    func removeWindowFromNotchSpace(_ window: NSWindow) {
        cgsSpace?.windows.remove(window)
    }

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
        batteryStatusManager: BatteryStatusManager.shared,
        intelligenceVM: intelligenceViewModel
    )

    // MARK: - Lifecycle

    private func setupMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            print("[Memory] Pressure event: \(event == .critical ? "CRITICAL" : "WARNING")")
            Task { @MainActor in
                MemoryTrimSupport.trimUnderMemoryPressure(musicManager: self.musicManager)
            }
        }
        source.resume()
    }

    func unregisterHelper() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("[AppDelegate] Unregistration failed (maybe not registered yet): \(error.localizedDescription)")
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        SapphireStandardMenu.installIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHelperConnectionLost),
            name: .sapphireHelperConnectionLost,
            object: nil
        )
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
        FirebaseApp.configure()

        if settingsModel.settings.sportsWidgetEnabled {
            SportsAPIService.shared.bootstrapIfNeeded()
        }
        NearbyConnectionManager.shared.deviceDisplayName = settingsModel.settings.neardropDeviceDisplayName
        observeSettings()

        if ProcessInfo.processInfo.environment["PERFMON"] == "1" || UserDefaults.standard.bool(forKey: "enablePerfMonitor") {
            ProcessCPUMonitor.shared.startPeriodicReporting(interval: 60)
            print("[PerfMon] CPU performance monitor enabled. Report logs every 60s.")
        }

        setupMemoryPressureHandler()

        // Bootstrap subscription FIRST, then route to the appropriate UI.
        // This ensures entitlements are always known before any content is shown.
        Task {
            await SubscriptionManager.shared.bootstrap()
            await MainActor.run {
                self.routeAfterLaunch()
            }
        }
    }

    private func routeAfterLaunch() {
        // Beta builds require a valid subscription with beta access.
        // This check must happen before showing any app UI.
        if BetaEntitlementRuntime.isBetaBuild {
            let validator = BetaEntitlementRuntime.makeValidator()
            if !validator.validateBetaEntitlement() {
                showBetaBlocker()
                return
            }
        }

        if OnboardingLaunchPolicy.shouldShowOnboarding {
            showOnboardingWindow()
        } else {
            startMainApp()
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

        observeSubscriptionForBetaGate()
    }

    private func observeSubscriptionForBetaGate() {
        subscriptionObservation = SubscriptionManager.shared.$entitlements
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handlePossibleBetaAccessLoss()
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSubscriptionEntitlementsDidChange(_:)),
            name: .subscriptionEntitlementsDidChange,
            object: nil
        )
    }

    @objc private func handleSubscriptionEntitlementsDidChange(_ notification: Notification) {
        guard BetaEntitlementRuntime.isBetaBuild, isMainAppRunning else { return }

        let previousTier = notification.userInfo?["previousTier"] as? String
        let newTier = notification.userInfo?["newTier"] as? String
        let lostBetaAccess = notification.userInfo?["lostBetaAccess"] as? Bool ?? false

        guard previousTier != newTier || lostBetaAccess else { return }
        presentBetaBlockerStoppingMainApp()
    }

    private func handlePossibleBetaAccessLoss() {
        guard BetaEntitlementRuntime.isBetaBuild, isMainAppRunning else { return }
        guard !SubscriptionManager.shared.hasBetaSoftwareAccess else { return }
        presentBetaBlockerStoppingMainApp()
    }

    private func presentBetaBlockerStoppingMainApp() {
        stopMainApp()
        showBetaBlocker()
    }

    private func stopMainApp() {
        guard isMainAppRunning else { return }

        AppSystemTeardown.restoreManagedSystemState(reason: "beta-access-revoked")

        isMainAppRunning = false

        UpdateChecker.shared.stopPeriodicChecks()

        if let window = notchWindow {
            cgsSpace?.windows.remove(window)
            window.orderOut(nil)
            window.close()
            notchWindow = nil
        }
        cgsSpace = nil

        settingsWindow?.orderOut(nil)
        settingsWindow?.close()
        settingsWindow = nil

        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil

        lyricsWindow?.orderOut(nil)
        lyricsWindow = nil

        teardownLaunchpad()

        interactionManager?.stopMonitoring()
        interactionManager = nil
        statusBarController = nil
        appearanceManager = nil

        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .subscriptionPaywallRequested,
            object: nil
        )

        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Onboarding

    func showOnboardingWindow() {
        Analytics.logEvent("onboarding_started", parameters: nil)

        if onboardingWindow == nil {
            let window = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900), styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
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
            window.minSize = NSSize(width: 1200, height: 900)
            window.maxSize = NSSize(width: 1200, height: 900)
            window.setContentSize(NSSize(width: 1200, height: 900))
            window.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly
            let hostingView = FocusableHostingView(rootView: OnboardingView(onComplete: { self.onboardingDidComplete() }).environmentObject(settingsModel).environmentObject(musicManager))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = hostingView
            onboardingWindow = window
        }
        if let onboardingWindow {
            UtilityWindowPresenter.present(onboardingWindow)
        }
    }

    func onboardingDidComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        Analytics.logEvent("onboarding_completed", parameters: nil)
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        startMainApp()
        DispatchQueue.main.async { self.openSettingsWindow() }
    }

    private func showBetaBlocker() {
        betaBlockerWindow?.orderOut(nil)
        betaBlockerWindow = nil

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.center()
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let hostingView = FocusableHostingView(
            rootView: BetaBlockerView(onValidationComplete: { [weak self] in
                Task { @MainActor in
                    self?.dismissBetaBlockerAndContinue()
                }
            })
                .environmentObject(settingsModel)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 28
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        betaBlockerWindow = window
        UtilityWindowPresenter.present(window)
    }

    private func dismissBetaBlockerAndContinue() {
        betaBlockerWindow?.orderOut(nil)
        betaBlockerWindow = nil

        // Re-bootstrap so we pick up any changes made during the beta blocker session
        // (e.g., user just entered a valid license key), then re-route.
        Task {
            await SubscriptionManager.shared.bootstrap()
            await MainActor.run { self.routeAfterLaunch() }
        }
    }

    func startMainApp() {
        guard !isMainAppRunning else { return }
        isMainAppRunning = true

        Analytics.logEvent("main_app_started", parameters: nil)

        HelperManager.shared.installIfNeeded()
        XPCClient.shared.start()

        createNotchWindow()
        _ = lidAngleAutomationManager
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionPaywallRequest(_:)), name: .subscriptionPaywallRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionSessionRevoked(_:)), name: .subscriptionSessionRevoked, object: nil)
        UNUserNotificationCenter.current().delegate = self
        NearbyConnectionManager.shared.mainAppDelegate = self
        UpdateChecker.shared.startPeriodicChecks(interval: 5 * 60 * 60)
        if settingsModel.settings.launchpadEnabled {
            setupLaunchpad()
        }

        scheduleHelperHealthCheck()
    }

    private func scheduleHelperHealthCheck() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard isMainAppRunning else { return }
            if await batteryManager.verifyHelperResponds() {
                helperHasConnectedThisSession = true
            }
        }
    }

    private func initializeCoreManagers() {
        // Only initialize absolutely essential managers — everything else lazy
        _ = settingsModel
        _ = batteryMonitor
        _ = batteryManager
    }

    private func initializeBackgroundServices() {
        // Changed from .userInitiated to .utility to reduce CPU priority
        DispatchQueue.global(qos: .utility).async {
            self.initializeCoreManagers()
            // Defer non-critical initializations
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
                _ = IOBluetoothDevice.pairedDevices()
                if self.settingsModel.settings.neardropEnabled {
                    NearbyConnectionManager.shared.becomeVisible()
                }
                Task { _ = await self.batteryManager.getBatteryTemperature() }
            }
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async {
                print("[AppDelegate] Network connection re-established.")
                self?.musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
                Task {
                    await SubscriptionManager.shared.validateSubscriptionStatus()
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    private var hasPresentedHelperConnectionAlertThisSession = false
    private var helperHasConnectedThisSession = false

    @objc private func systemDidWake(notification: NSNotification) {
        batteryManager.reconnectHelper()
        musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
        Task {
            await SubscriptionManager.shared.validateSubscriptionStatus()
        }
    }

    @objc private func handleApplicationDidBecomeActive(_ notification: Notification) {
        Task {
            await evaluateHelperConnection(showAlertOnFailure: true)
            await SubscriptionManager.shared.validateSubscriptionStatus()
        }
    }

    @objc private func handleHelperConnectionLost() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard isMainAppRunning else { return }
            await evaluateHelperConnection(showAlertOnFailure: true)
        }
    }

    private func evaluateHelperConnection(showAlertOnFailure: Bool) async {
        if await batteryManager.verifyHelperResponds() {
            helperHasConnectedThisSession = true
            return
        }

        guard helperHasConnectedThisSession else { return }

        batteryManager.reconnectHelper()
        try? await Task.sleep(for: .seconds(1.5))

        if await batteryManager.verifyHelperResponds() {
            helperHasConnectedThisSession = true
            return
        }

        if showAlertOnFailure {
            presentHelperConnectionAlertIfNeeded()
        }
    }

    private func presentHelperConnectionAlertIfNeeded() {
        guard !hasPresentedHelperConnectionAlertThisSession else { return }
        guard helperHasConnectedThisSession else { return }
        hasPresentedHelperConnectionAlertThisSession = true

        DispatchQueue.main.async {
            HelperAlertPresenter.showHelperConnectionLost()
        }
    }

    @objc private func handleSubscriptionSessionRevoked(_ notification: Notification) {
        let reasonRaw = notification.userInfo?["reason"] as? String ?? SubscriptionRevocationReason.sessionExpired.rawValue
        let reason = SubscriptionRevocationReason(rawValue: reasonRaw) ?? .sessionExpired

        if BetaEntitlementRuntime.isBetaBuild {
            presentBetaBlockerStoppingMainApp()
            return
        }

        DispatchQueue.main.async {
            HelperAlertPresenter.presentModal(
                messageText: "Signed Out of Sapphire",
                informativeText: reason.alertMessage,
                alertStyle: .warning,
                buttonTitles: ["Open Account Settings", "OK"]
            ) { buttonIndex in
                if buttonIndex == 0 {
                    NotificationCenter.default.post(name: .sapphireOpenAccountPane, object: nil)
                }
            }
        }
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
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Termination

    func applicationWillTerminate(_ aNotification: Notification) {
        if Thread.isMainThread {
            AppSystemTeardown.restoreManagedSystemState(reason: "app-quit")
        } else {
            DispatchQueue.main.sync {
                AppSystemTeardown.restoreManagedSystemState(reason: "app-quit")
            }
        }

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
        let initialConfig = ResolvedNotchConfiguration(from: settingsModel.settings)
        let paddedWidth = ceil(max(initialConfig.initialSize.width + 8, screenFrame.width * 0.72))
        let paddedHeight = ceil(max(initialConfig.initialSize.height + initialConfig.topBuffer + 24, screenFrame.height * 0.42))
        let rect = NSRect(
            x: screenFrame.midX - (paddedWidth / 2),
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        let hosting = PassthroughHostingView(
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
                .environmentObject(intelligenceViewModel)
        )
        hosting.frame = NSRect(origin: .zero, size: rect.size)
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
            UtilityWindowPresenter.presentSettingsWindow(window)
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

        let hosting = FocusableHostingView(rootView: root)
        window.contentView = hosting
        window.delegate = self
        settingsWindow = window

        UtilityWindowPresenter.presentSettingsWindow(window)
    }

    func openLyricsWindow() {
        if let window = lyricsWindow {
            UtilityWindowPresenter.presentSettingsWindow(window)
            return
        }

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 620),
            styleMask: [.titled, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lyrics"
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = true
        window.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly

        let root = LyricsDetachedWindowView()
            .environmentObject(musicManager)

        let hosting = FocusableHostingView(rootView: root)
        window.contentView = hosting
        window.delegate = self
        lyricsWindow = window

        UtilityWindowPresenter.presentSettingsWindow(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        let isSettings = window === settingsWindow
        let isLyrics = window === lyricsWindow
        guard isSettings || isLyrics else { return }

        if isSettings { settingsWindow = nil }
        if isLyrics { lyricsWindow = nil }

        // Let AppKit release the window/content view (isReleasedWhenClosed).
        // Only drop our delegate reference after this callback returns.
        DispatchQueue.main.async { [weak window] in
            window?.delegate = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.finishClosingUserWindow()
        }
    }

    private func finishClosingUserWindow() {
        restoreAgentActivationIfNeeded()
        MemoryTrimSupport.trimAfterUserWindowClose(musicManager: musicManager)
    }

    private func restoreAgentActivationIfNeeded() {
        let hasUserWindow = [settingsWindow, lyricsWindow, onboardingWindow, betaBlockerWindow]
            .compactMap { $0 }
            .contains { $0.isVisible }
        guard !hasUserWindow else { return }
        transitionToAgentApp()
    }

    // MARK: - Screen Parameters

    @objc func handleSubscriptionPaywallRequest(_ notification: Notification) {
        openSettingsWindow()
    }

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
        lyricsWindow?.sharingType = sharingType
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

    override func becomeKey() {
        super.becomeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}
