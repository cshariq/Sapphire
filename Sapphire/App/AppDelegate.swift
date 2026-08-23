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
    @Published var faceIDRequiresPassword: Bool = false
}

final class DynamicFocusWindow: NSPanel, NSWindowDelegate {
    var isFocusable: Bool = false
    var forceMouseEventPassthrough: Bool = false {
        didSet {
            guard forceMouseEventPassthrough != oldValue else { return }
            scheduleMouseEventPassthroughRefresh()
        }
    }
    private var interactiveContentFrame: CGRect = .zero
    private var diagnosticsTimer: Timer?
    private var isHandlingMouseInteraction = false
    private var lastPolledMousePoint: CGPoint?
    private var passthroughRefreshPending = false
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
        if #available(macOS 15.0, *) {
            delegate = self
        }
    }

    private var isProvidingFieldEditor = false

    func windowWillReturnFieldEditor(_ window: NSWindow, to client: Any?) -> Any? {
        guard !isProvidingFieldEditor else { return nil }
        isProvidingFieldEditor = true
        defer { isProvidingFieldEditor = false }
        guard let editor = window.fieldEditor(true, for: client) as? NSTextView else { return nil }
        if #available(macOS 15.0, *) {
            editor.writingToolsBehavior = .none
        }
        return editor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        diagnosticsTimer?.invalidate()
    }

    func updateInteractiveContentFrame(_ frame: CGRect) {
        let previousFrame = interactiveContentFrame

        if frame.isNull || frame.isEmpty {
            interactiveContentFrame = .zero
        } else {
            interactiveContentFrame = frame.integral.insetBy(dx: -1, dy: -1)
        }

        guard interactiveContentFrame != previousFrame else { return }
        scheduleMouseEventPassthroughRefresh()
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

        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                .mouseMoved, .mouseEntered, .mouseExited:
            scheduleMouseEventPassthroughRefresh()
        default:
            break
        }

        super.sendEvent(event)
    }

    func syncMouseEventPassthrough(forceEnable: Bool = false) {
        if NSEvent.pressedMouseButtons == 0 {
            isHandlingMouseInteraction = false
        }
        scheduleMouseEventPassthroughRefresh(forceEnable: forceEnable)
    }

    private func scheduleMouseEventPassthroughRefresh(forceEnable: Bool = false) {
        guard !passthroughRefreshPending else { return }
        passthroughRefreshPending = true
        let pendingForceEnable = forceEnable
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.passthroughRefreshPending = false
            self.refreshMouseEventPassthrough(force: true, forceEnable: pendingForceEnable)
        }
    }

    private func refreshMouseEventPassthrough(force: Bool = false, forceEnable: Bool = false) {
        guard contentView != nil else { return }

        if forceMouseEventPassthrough {
            if !ignoresMouseEvents {
                ignoresMouseEvents = true
                ignoreStateFlipCount += 1
            }
            return
        }

        guard force || isHandlingMouseInteraction || isVisible else {
            return
        }
        let mousePoint = mouseLocationOutsideOfEventStream
        if !force, !isHandlingMouseInteraction, lastPolledMousePoint == mousePoint {
            return
        }

        lastPolledMousePoint = mousePoint

        let effectiveInteractiveFrame = interactiveContentFrame.isEmpty ? (contentView?.bounds ?? .zero) : interactiveContentFrame
        let enableFrame = effectiveInteractiveFrame.insetBy(dx: -12, dy: -12)

        let shouldReceiveMouseEvents: Bool
        if isHandlingMouseInteraction || (forceEnable && enableFrame.contains(mousePoint)) {
            shouldReceiveMouseEvents = true
        } else {
            shouldReceiveMouseEvents = enableFrame.contains(mousePoint)
        }

        let shouldIgnoreMouseEvents = !shouldReceiveMouseEvents
        if ignoresMouseEvents != shouldIgnoreMouseEvents {
            ignoresMouseEvents = shouldIgnoreMouseEvents
            ignoreStateFlipCount += 1
        }

        let shouldAcceptMouseMovedEvents = shouldReceiveMouseEvents || isHandlingMouseInteraction || isFocusable
        if acceptsMouseMovedEvents != shouldAcceptMouseMovedEvents {
            acceptsMouseMovedEvents = shouldAcceptMouseMovedEvents
        }
    }

    private func shouldDropPassivePointerEvent(_ event: NSEvent) -> Bool {
        guard !isHandlingMouseInteraction else { return false }
        let effectiveInteractiveFrame = interactiveContentFrame.isEmpty ? (contentView?.bounds ?? .zero) : interactiveContentFrame
        let enableFrame = effectiveInteractiveFrame.insetBy(dx: -12, dy: -12)

        switch event.type {
        case .mouseMoved, .mouseEntered, .mouseExited:
            return !enableFrame.contains(event.locationInWindow)
        default:
            return false
        }
    }
}

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
    private var subscriptionValidationTimer: Timer?

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
    lazy var powerStateController: PowerStateController = .shared
    lazy var scheduleManager: ScheduleManager = .shared
    lazy var keyboardShortcutManager: KeyboardShortcutManager = .shared
    lazy var globalDragManager: GlobalDragManager = .shared
    lazy var batteryDataLogger: BatteryDataLogger = .shared
    lazy var fileShelfManager: FileShelfManager = .shared
    lazy var authManager: AuthenticationManager = .shared
    lazy var intelligenceViewModel: IntelligenceNotchViewModel = IntelligenceNotchViewModel()
    lazy var circleToSearchManager: CircleToSearchManager = .shared

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

    func applicationWillFinishLaunching(_ notification: Notification) {
        RemoteViewCrashGuardInstall()

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AccessibilityTrustMonitor.shared.start()

        SapphireStandardMenu.installIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHelperConnectionLost),
            name: .sapphireHelperConnectionLost,
            object: nil
        )
        SapphireAnalytics.bootstrap()

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

        Task {
            await SubscriptionManager.shared.bootstrap()
            await MainActor.run {
                self.routeAfterLaunch()
            }
        }
    }

    private func routeAfterLaunch() {
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
            .map(\.googleAnalyticsEnabled)
            .removeDuplicates()
            .sink { _ in SapphireAnalytics.applyCollectionPreference() }
            .store(in: &cancellables)

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

        settingsModel.$settings
            .map(\.notchDisplayTarget)
            .removeDuplicates()
            .sink { [weak self] _ in self?.createNotchWindow() }
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

        subscriptionValidationTimer?.invalidate()
        subscriptionValidationTimer = nil

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
            let visibleFrame = UtilityWindowMetrics.visibleFrame()
            let size = UtilityWindowMetrics.onboardingWindowSize()
            let frame = UtilityWindowMetrics.centeredFrame(size: size)
            let window = KeyableWindow(contentRect: frame, styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.setFrame(frame, display: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.title = "Sapphire Onboarding"
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.minSize = NSSize(
                width: NotchConfiguration.settingsWindowMinWidth,
                height: NotchConfiguration.settingsWindowMinHeight
            )
            window.maxSize = NSSize(
                width: visibleFrame.width,
                height: visibleFrame.height
            )
            window.setContentSize(size)
            window.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly
            let hostingView = FocusableHostingView(rootView: OnboardingView(onComplete: { self.onboardingDidComplete() }).environmentObject(settingsModel).environmentObject(musicManager))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = hostingView
            window.delegate = self
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

        Task {
            await SubscriptionManager.shared.bootstrap()
            await MainActor.run { self.routeAfterLaunch() }
        }
    }

    func startMainApp() {
        guard !isMainAppRunning else { return }
        isMainAppRunning = true

        Analytics.logEvent("main_app_started", parameters: nil)

        transitionToAgentApp()

        HelperManager.shared.installIfNeeded()

        createNotchWindow()
        _ = circleToSearchManager
        _ = keyboardShortcutManager
        _ = lidAngleAutomationManager
        setupStatusBarItem()
        initializeBackgroundServices()
        if settingsModel.settings.menuBarEnabled {
            if statusBarController == nil {
                statusBarController = StatusBarController()
                interactionManager = MenuBarInteractionManager.shared
                interactionManager?.startMonitoring()
                appearanceManager = MenuBarAppearanceManager()
            }
        }

        SystemControl.configureKeyboardBacklight()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        setupSessionObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionPaywallRequest(_:)), name: .subscriptionPaywallRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionSessionRevoked(_:)), name: .subscriptionSessionRevoked, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAccountPaneOpened), name: .sapphireOpenAccountPane, object: nil)
        UNUserNotificationCenter.current().delegate = self
        NearbyConnectionManager.shared.mainAppDelegate = self
        UpdateChecker.shared.startPeriodicChecks(interval: 5 * 60 * 60)
        if settingsModel.settings.launchpadEnabled {
            setupLaunchpad()
        }

        scheduleHelperHealthCheck()
        scheduleSubscriptionValidationTimer()
    }

    private func scheduleSubscriptionValidationTimer() {
        subscriptionValidationTimer?.invalidate()
        subscriptionValidationTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                print("[AppDelegate] Periodic subscription validation (5-hour interval).")
                await SubscriptionManager.shared.validateSubscriptionStatus()
            }
        }
        // Allow the timer to fire while scrolling, etc.
        RunLoop.current.add(subscriptionValidationTimer!, forMode: .common)
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
        _ = settingsModel
        _ = batteryMonitor
        _ = batteryManager
    }

    private func initializeBackgroundServices() {
        DispatchQueue.global(qos: .utility).async {
            self.initializeCoreManagers()
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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.screensDidWakeNotification,
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
        HelperManager.shared.checkIfRunning(force: true)

        let reconnectDelay: TimeInterval = AuthenticationManager.shared.isFaceIDSessionActive ? 4.0 : 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            self?.musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
        }
        Task {
            await SubscriptionManager.shared.validateSubscriptionStatus()
        }
        AuthenticationManager.shared.handleSystemDidWake()
    }

    @objc private func systemWillSleep(notification: NSNotification) {
        AuthenticationManager.shared.handleDisplayWillSleep()
    }

    @objc private func displayDidSleep(notification: NSNotification) {
        AuthenticationManager.shared.handleDisplayWillSleep()
    }

    @objc private func displayDidWake(notification: NSNotification) {
        AuthenticationManager.shared.handleDisplayDidWake()
        onDisplayWake()
    }

    @objc private func handleApplicationDidBecomeActive(_ notification: Notification) {
        HelperManager.shared.updateStatus()
        // Subscription validation is handled by the 5-hour timer,
        // wake-from-sleep, and network-reconnect triggers instead.
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
        lockScreenState.faceIDRequiresPassword = false
        lockScreenState.isCaffeineActive = caffeineManager.isActive
        lockScreenState.isFaceIDEnabled = settingsModel.settings.faceIDUnlockEnabled &&
                                          settingsModel.settings.hasRegisteredFaceID
        lockScreenState.isBluetoothUnlockEnabled = settingsModel.settings.bluetoothUnlockEnabled

        if settingsModel.settings.lockScreenLiveActivityEnabled {
            liveActivityManager.startLockScreenActivity()
        }

        if !isAuthenticating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard self.isScreenLocked else { return }
                self.startAuthentication()
            }
        }

        if !weatherActivityViewModel.hasValidWeather {
            weatherActivityViewModel.fetch()
        }

        if settingsModel.settings.lockScreenShowNotch, let notchWindow {
            lockScreenManager.delegateWindow(notchWindow)
        }

        guard let mainScreen = NSScreen.main else { return }
        var widgetConfigs: [LockScreenManager.LockScreenWidgetConfig] = []

        if settingsModel.settings.lockScreenShowInfoWidget {
            widgetConfigs.append(.init(
                id: "infoWidget",
                initialSize: .zero,
                positioner: lockScreenManager.calculateInfoWidgetFrame(size:screen:)
            ) { manager, initialFrame, screen in
                manager.displayView(
                    LockScreenInfoWidgetView()
                        .environmentObject(self.settingsModel)
                        .environmentObject(self.weatherActivityViewModel)
                        .environmentObject(self.calendarService)
                        .environmentObject(self.musicManager)
                        .environmentObject(self.focusModeManager)
                        .environmentObject(self.bluetoothManager)
                        .environmentObject(self.batteryMonitor)
                        .environmentObject(self.timerManager),
                    withId: "infoWidget",
                    initialFrame: initialFrame,
                    positioner: manager.calculateInfoWidgetFrame(size:screen:),
                    windowLevel: .mainMenu + 2,
                    on: screen
                )
            })
        }

        if settingsModel.settings.lockScreenShowMainWidget &&
           !settingsModel.settings.lockScreenMainWidgets.isEmpty {
            widgetConfigs.append(.init(
                id: "mainWidgetContainer",
                initialSize: .zero,
                positioner: lockScreenManager.calculateMainWidgetFrame(size:screen:)
            ) { manager, initialFrame, screen in
                manager.displayView(
                    LockScreenMainWidgetContainerView()
                        .environmentObject(self.settingsModel)
                        .environmentObject(self.musicManager)
                        .environmentObject(self.calendarService)
                        .environmentObject(BatteryStatusManager.shared)
                        .environmentObject(self.focusModeManager)
                        .environmentObject(self.timerManager)
                        .environmentObject(self.batteryMonitor)
                        .environmentObject(self.bluetoothManager),
                    withId: "mainWidgetContainer",
                    initialFrame: initialFrame,
                    positioner: manager.calculateMainWidgetFrame(size:screen:),
                    windowLevel: .mainMenu + 2,
                    on: screen
                )
            })
        }

        if settingsModel.settings.lockScreenShowMiniWidgets &&
           !settingsModel.settings.lockScreenMiniWidgets.isEmpty {
            widgetConfigs.append(.init(
                id: "miniWidgets",
                initialSize: .zero,
                positioner: lockScreenManager.calculateMiniWidgetFrame(size:screen:)
            ) { manager, initialFrame, screen in
                manager.displayView(
                    LockScreenMiniWidgetView()
                        .environmentObject(self.settingsModel)
                        .environmentObject(self.weatherActivityViewModel)
                        .environmentObject(self.calendarService)
                        .environmentObject(self.musicManager)
                        .environmentObject(self.batteryMonitor)
                        .environmentObject(self.bluetoothManager)
                        .environmentObject(self.batteryEstimator)
                        .environmentObject(self.focusModeManager)
                        .environmentObject(self.timerManager),
                    withId: "miniWidgets",
                    initialFrame: initialFrame,
                    positioner: manager.calculateMiniWidgetFrame(size:screen:),
                    windowLevel: .mainMenu + 2,
                    on: screen
                )
            })
        }

        widgetConfigs.append(.init(
            id: "fullScreenMusicPane",
            initialSize: .zero,
            positioner: lockScreenManager.calculateFullScreenMusicFrame(size:screen:),
            windowLevel: .mainMenu + 4
        ) { manager, initialFrame, screen in
            manager.displayView(
                LockScreenFullScreenMusicPane()
                    .environmentObject(self.settingsModel)
                    .environmentObject(self.musicManager),
                withId: "fullScreenMusicPane",
                initialFrame: initialFrame,
                positioner: manager.calculateFullScreenMusicFrame(size:screen:),
                windowLevel: .mainMenu + 4,
                on: screen
            )
        })

        lockScreenManager.setupAndShowWindows(configs: widgetConfigs, on: mainScreen)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func screenIsUnlocked() {
        lockScreenManager.hideAndDestroyWindows()

        LockScreenMusicPaneController.shared.reset()

        authManager.purgeFaceIDAfterUnlock()

        guard isScreenLocked else { return }
        isScreenLocked = false
        isAuthenticating = false
        lockScreenState.isUnlocked = true
        lockScreenState.isAuthenticating = false
        lockScreenState.faceIDRequiresPassword = false

        authManager.cancelPendingPasswordInjection(reason: "screen unlocked")

        lockScreenManager.hideAndDestroyWindows()
        liveActivityManager.finishLockScreenActivity()

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
        lockScreenState.faceIDRequiresPassword = false

        if settingsModel.settings.bluetoothUnlockEnabled {
            authManager.startBluetoothAuthentication()
        }
        if settingsModel.settings.faceIDUnlockEnabled && settingsModel.settings.hasRegisteredFaceID {
            authManager.startFaceIDAuthentication()
        }
    }

    func markFaceIDRequiresPassword() {
        lockScreenState.faceIDRequiresPassword = true
    }

    // MARK: - Activation Policy

    private func transitionToAgentApp() {
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Termination

    func applicationWillTerminate(_ aNotification: Notification) {
        settingsModel.flushPendingSave()
        BatteryManager.shared.stopSleepBatteryLogging()
        cleanupNotchWindow()

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

    private func cleanupNotchWindow() {
        screenParametersDebounceTimer?.invalidate()
        screenParametersDebounceTimer = nil

        if let window = notchWindow {
            cgsSpace?.windows.remove(window)
            window.orderOut(nil)
            window.close()
            notchWindow = nil
        }
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

    private var isCreatingNotchWindow = false
    private var liveActivityStartTask: Task<Void, Never>?

    func createNotchWindow() {
        guard !isCreatingNotchWindow else { return }
        isCreatingNotchWindow = true
        defer { isCreatingNotchWindow = false }

        guard let targetScreen = CursorPosition.targetNotchScreen() else { return }

        if let existingWindow = notchWindow, existingWindow.screen == targetScreen, existingWindow.isVisible {
            existingWindow.sharingType = settingsModel.settings.hideFromScreenSharing ? .none : .readOnly
            return
        }

        if let oldWindow = notchWindow {
            cgsSpace?.windows.remove(oldWindow)
            oldWindow.orderOut(nil)
            oldWindow.close()
            notchWindow = nil
        }
        let screenFrame = targetScreen.frame
        let initialConfig = ResolvedNotchConfiguration(from: settingsModel.settings, screen: targetScreen)
        let paddedWidth = ceil(screenFrame.width)
        let paddedHeight = ceil(max(initialConfig.initialSize.height + initialConfig.topBuffer + 24, screenFrame.height * 0.42))
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
        let container = ZStack(alignment: .top) {
            controllerView
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
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        window.orderFront(nil)

        scheduleLiveActivityStart()
    }

    private func scheduleLiveActivityStart() {
        guard liveActivityStartTask == nil else { return }
        liveActivityStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.liveActivityManager.start()
        }
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
        window.syncMouseEventPassthrough()
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        previouslyFrontmostApp?.activate(options: [.activateIgnoringOtherApps])
        previouslyFrontmostApp = nil
    }

    func refreshNotchMousePassthrough() {
        (notchWindow as? DynamicFocusWindow)?.syncMouseEventPassthrough()
    }

    func updateNotchHostWindowHeight(requiredContentHeight: CGFloat) {
        guard let window = notchWindow else { return }
        let targetScreen = window.screen ?? CursorPosition.targetNotchScreen()
        guard let targetScreen else { return }

        let config = ResolvedNotchConfiguration(from: settingsModel.settings, screen: targetScreen)
        let baselineHeight = max(
            config.initialSize.height + config.topBuffer + 24,
            targetScreen.frame.height * 0.42
        )
        let desiredHeight = max(baselineHeight, requiredContentHeight + config.topBuffer + 36)
        let paddedHeight = min(ceil(desiredHeight), targetScreen.visibleFrame.height)
        var frame = window.frame
        let newY = targetScreen.frame.maxY - paddedHeight
        guard abs(frame.height - paddedHeight) > 2 || abs(frame.origin.y - newY) > 2 else { return }
        frame.origin.y = newY
        frame.size.height = paddedHeight
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Settings Window

    func openSettingsWindow() {
        if let window = settingsWindow {
            UtilityWindowPresenter.presentSettingsWindow(window)
            return
        }

        let visibleFrame = UtilityWindowMetrics.visibleFrame()
        let size = UtilityWindowMetrics.settingsDefaultSize()
        let frame = UtilityWindowMetrics.centeredFrame(size: size)
        let window = KeyableWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.setFrame(frame, display: false)
        window.minSize = NSSize(
            width: NotchConfiguration.settingsWindowMinWidth,
            height: NotchConfiguration.settingsWindowMinHeight
        )
        window.maxSize = NSSize(
            width: visibleFrame.width,
            height: visibleFrame.height
        )
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
            .environmentObject(settingsModel)

        let hosting = FocusableHostingView(rootView: root)
        window.contentView = hosting
        window.delegate = self
        lyricsWindow = window

        UtilityWindowPresenter.presentSettingsWindow(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === onboardingWindow {
            NSApp.terminate(nil)
            return
        }

        let isSettings = window === settingsWindow
        let isLyrics = window === lyricsWindow
        guard isSettings || isLyrics else { return }

        if isSettings { settingsWindow = nil }
        if isLyrics { lyricsWindow = nil }

        DispatchQueue.main.async { [weak window] in
            window?.delegate = nil
        }

        DispatchQueue.main.async { [weak self] in
            self?.finishClosingUserWindow()
        }
    }

    private func finishClosingUserWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.restoreAgentActivationIfNeeded()
            MemoryTrimSupport.trimAfterUserWindowClose(musicManager: self.musicManager)
        }
    }

    private func restoreAgentActivationIfNeeded() {
        let hasUserWindow = [settingsWindow, lyricsWindow, onboardingWindow, betaBlockerWindow]
            .compactMap { $0 }
            .contains { $0.isVisible }
        guard !hasUserWindow else { return }
        transitionToAgentApp()
    }

    // MARK: - Screen Parameters

    private var screenParametersDebounceTimer: Timer?

    @objc func handleAccountPaneOpened() {
        print("[AppDelegate] Account pane opened — refreshing subscription status.")
        Task {
            await SubscriptionManager.shared.validateSubscriptionStatus()
        }
    }

    @objc func handleSubscriptionPaywallRequest(_ notification: Notification) {
        openSettingsWindow()
        NotificationCenter.default.post(name: .sapphireOpenAccountPane, object: nil)
    }

    @objc func screenParametersChanged(notification: Notification) {
        screenParametersDebounceTimer?.invalidate()
        screenParametersDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.createNotchWindow()
        }
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

}