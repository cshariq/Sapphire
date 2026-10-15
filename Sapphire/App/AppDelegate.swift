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
import Network
import os.log

private let appDelegateLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Sapphire",
    category: "AppDelegate"
)

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
    var displayID: CGDirectDisplayID = 0
    var isFocusable: Bool = false

    override var canBecomeKey: Bool { isFocusable }
    override var canBecomeMain: Bool { isFocusable }

    override var isKeyWindow: Bool { isFocusable ? super.isKeyWindow : true }
    override var isMainWindow: Bool { isFocusable ? super.isMainWindow : true }
    @objc func hasKeyAppearance() -> Bool { true }
    @objc func hasMainAppearance() -> Bool { true }
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

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

    func setMouseEventHandlingEnabled(_ isEnabled: Bool = false) {
        ignoresMouseEvents = !isEnabled
    }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }

    private(set) var isNotchHidden = false

    var monitorsTornDown = false

    func setNotchHidden(_ hidden: Bool) {
        guard hidden != isNotchHidden else { return }
        isNotchHidden = hidden
        if hidden {
            orderOut(nil)
        } else {
            showIfAllowed()
        }
    }

    private(set) var isDisplayDetached = false

    func setDisplayDetached(_ detached: Bool) {
        guard detached != isDisplayDetached else { return }
        isDisplayDetached = detached
        if detached {
            orderOut(nil)
        } else {
            showIfAllowed()
        }
    }

    private func showIfAllowed() {
        guard !isNotchHidden, !isDisplayDetached else { return }
        (NSApp.delegate as? AppDelegate)?.reassertNotchSpaceMembership(self)
        alphaValue = 1
        orderFrontRegardless()
    }

    var onDisplayConfigurationChange: (() -> Void)?

    var onTeardown: (() -> Void)?

    private(set) lazy var hostSizer = NotchHostWindowSizer(window: self)

    private let pointerTrackingClients = NSHashTable<NSView>.weakObjects()

    func registerPointerTrackingClient(_ view: some PointerTrackingGated) {
        pointerTrackingClients.add(view)
        view.setPointerTrackingEnabled(!ignoresMouseEvents)
    }

    func unregisterPointerTrackingClient(_ view: some PointerTrackingGated) {
        pointerTrackingClients.remove(view)
    }

    override var ignoresMouseEvents: Bool {
        didSet {
            if ignoresMouseEvents != oldValue {
                for case let client as PointerTrackingGated in pointerTrackingClients.allObjects {
                    client.setPointerTrackingEnabled(!ignoresMouseEvents)
                }
                if ignoresMouseEvents { dropMouseMovedListener() }
            }
            updateCursorRectGate()
        }
    }

    private func dropMouseMovedListener() {
        guard let ivar = class_getInstanceVariable(NSWindow.self, "_trackingAreaManager"),
              let manager = object_getIvar(self, ivar) as? NSObject else { return }
        let selector = NSSelectorFromString("_removeMouseMovedListener:")
        guard let method = class_getInstanceMethod(NSWindow.self, selector),
              method_getTypeEncoding(method).map({ String(cString: $0) }) == "v24@0:8@16" else { return }
        typealias Remove = @convention(c) (NSWindow, Selector, AnyObject) -> Void
        unsafeBitCast(method_getImplementation(method), to: Remove.self)(self, selector, manager)
    }

    private func updateCursorRectGate() {
        guard areCursorRectsEnabled == ignoresMouseEvents else { return }
        if ignoresMouseEvents { disableCursorRects() } else { enableCursorRects() }
    }

    var onMouseUp: (() -> Void)?

    private static let eventsDroppedWhileIgnoringMouse: Set<NSEvent.EventType> = [
        .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
    ]

    private static let edgeClampedMouseEvents: Set<NSEvent.EventType> = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    private func clampedToTopEdge(_ event: NSEvent) -> NSEvent {
        guard Self.edgeClampedMouseEvents.contains(event.type), let height = contentView?.bounds.height else {
            return event
        }
        let inside = height - 0.5
        let location = event.locationInWindow
        guard location.y > inside else { return event }
        return NSEvent.mouseEvent(
            with: event.type,
            location: NSPoint(x: location.x, y: inside),
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        ) ?? event
    }

    override func sendEvent(_ event: NSEvent) {
        if ignoresMouseEvents, Self.eventsDroppedWhileIgnoringMouse.contains(event.type) { return }
        let event = clampedToTopEdge(event)
        #if DEBUG
        if event.type == .leftMouseDown || event.type == .leftMouseUp, let root = contentView?.superview {
            var chain: [String] = []
            var view = root.hitTest(event.locationInWindow)
            while let v = view { chain.append(String(describing: type(of: v)).prefix(40).description); view = v.superview }
            os_log(.error, "CLICK-TRACE window %{public}@ loc=%{public}@ frame=%{public}@ hit=%{public}@",
                   event.type == .leftMouseDown ? "down" : "up", NSStringFromPoint(event.locationInWindow), NSStringFromRect(frame), chain.joined(separator: " < "))
        }
        #endif
        super.sendEvent(event)
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onMouseUp?()
        default:
            break
        }
    }
}

final class PassthroughHostingView<Content: View>: NSHostingView<Content>, PointerTrackingGated {
    private lazy var trackingGate = PointerTrackingGate(view: self)

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        (window as? DynamicFocusWindow)?.unregisterPointerTrackingClient(self)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window as? DynamicFocusWindow {
            window.registerPointerTrackingClient(self)
        } else {
            setPointerTrackingEnabled(true)
        }
    }

    override func addTrackingArea(_ trackingArea: NSTrackingArea) {
        guard trackingGate.shouldInstall(trackingArea) else { return }
        super.addTrackingArea(trackingArea)
    }

    override func removeTrackingArea(_ trackingArea: NSTrackingArea) {
        trackingGate.didRemove(trackingArea)
        super.removeTrackingArea(trackingArea)
    }

    func setPointerTrackingEnabled(_ enabled: Bool) {
        trackingGate.setOpen(enabled) { super.addTrackingArea($0) }
    }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var safeAreaRect: NSRect { bounds }
}

@MainActor
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate, NSWindowDelegate {
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    public var notchWindows: [NSWindow] = []
    private var cgsSpace: CGSSpace?
    private static let notchSpaceLevel = Int(CGWindowLevelForKey(.statusWindow))
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var lyricsWindow: NSWindow?
    private var betaBlockerWindow: NSWindow?
    private var isMainAppRunning = false
    private var subscriptionValidationTimer: Timer?
    private var backgroundInitializationTask: Task<Void, Never>?
    private var sessionObserversInstalled = false
    private var networkPathSatisfied: Bool?
    private var pendingAllocatorRelief: DispatchWorkItem?
    private var isPresentingSapphireVMLaunchFailure = false
    private let performanceLaunchStart = (
        date: Date(),
        uptime: ProcessInfo.processInfo.systemUptime
    )

    private lazy var lockScreenManager = LockScreenManager.shared
    private lazy var lidAngleAutomationManager = LidAngleAutomationManager.shared

    lazy var musicManager: MusicManager = .shared
    lazy var systemHUDManager: SystemHUDManager = .shared
    lazy var pillHUDController: PillHUDController = .shared
    lazy var notificationManager: NotificationManager = .shared
    lazy var desktopManager: DesktopManager = DesktopManager()
    lazy var focusModeManager: FocusModeManager = .shared
    lazy var calendarService: CalendarService = CalendarService()
    lazy var batteryMonitor: BatteryMonitor = .shared
    lazy var batteryManager = BatteryManager.shared
    lazy var batteryEstimator: BatteryEstimator = BatteryEstimator(batteryMonitor: batteryMonitor)
    lazy var bluetoothManager: BluetoothManager = BluetoothManager()
    lazy var continuityManager: ContinuityManager = .shared
    lazy var audioDeviceManager: AudioDeviceManager = AudioDeviceManager()
    lazy var multiAudioManager: MultiAudioManager = .shared
    lazy var eyeBreakManager: EyeBreakManager = .shared
    lazy var timerManager: TimerManager = TimerManager()
    lazy var focusSessionManager: FocusSessionManager = .shared
    lazy var focusSessionShortcutMonitor: FocusSessionShortcutMonitor = .shared
    lazy var ocrScreenshotMonitor: OCRScreenshotMonitor = .shared
    lazy var focusScheduleManager: FocusScheduleManager = .shared
    lazy var appLockManager: AppLockManager = .shared
    lazy var weatherActivityViewModel: WeatherActivityViewModel = WeatherActivityViewModel()
    lazy var contentPickerHelper: ContentPickerHelper = ContentPickerHelper()
    lazy var geminiLiveManager: GeminiLiveManager = GeminiLiveManager()
    lazy var settingsModel: SettingsModel = .shared
    lazy var activeAppMonitor: ActiveAppMonitor = .shared
    lazy var powerStateController: PowerStateController = .shared
    lazy var scheduleManager: ScheduleManager = .shared
    lazy var keyboardShortcutManager: KeyboardShortcutManager = .shared
    lazy var plainTextPasteManager: PlainTextPasteManager = .shared
    lazy var globalDragManager: GlobalDragManager = .shared
    lazy var batteryDataLogger: BatteryDataLogger = .shared
    lazy var fileShelfManager: FileShelfManager = .shared
    lazy var authManager: AuthenticationManager = .shared
    lazy var intelligenceViewModel: IntelligenceNotchViewModel = IntelligenceNotchViewModel()
    lazy var circleToSearchManager: CircleToSearchManager = .shared
    lazy var systemEnhanceWindowRegistry = SystemEnhanceWindowRegistry.shared
    lazy var systemEnhanceDockPreviewController = SystemEnhanceDockPreviewController.shared
    lazy var systemEnhanceWindowSwitcher = SystemEnhanceWindowSwitcher.shared
    lazy var systemEnhanceDockClicks = SystemEnhanceDockClicks.shared
    lazy var systemEnhanceAutoQuit = SystemEnhanceAutoQuit.shared
    lazy var systemEnhanceQuitProtection = SystemEnhanceQuitProtection.shared
    lazy var systemEnhanceGreenMaximize = SystemEnhanceGreenMaximize.shared
    lazy var systemEnhanceContextMenu = SystemEnhanceContextMenu.shared
    lazy var systemEnhanceHingeAnimation = SystemEnhanceHingeAnimationManager.shared
    lazy var dmgInstallerManager: DMGInstallerManager = .shared
    lazy var emojiShortcutManager: EmojiShortcutManager = .shared
    lazy var clipboardPickerManager: ClipboardPickerManager = .shared
    lazy var clipboardAutoClearManager = ClipboardAutoClearManager.shared
    lazy var cleanURLManager = CleanURLManager.shared
    lazy var finderCutPasteManager = FinderCutPasteManager.shared
    lazy var snippetManager = SnippetManager.shared
    lazy var mouseControlManager: MouseControlManager = .shared
    lazy var focusFollowsMouseManager = FocusFollowsMouseManager.shared
    lazy var extraClickFilterManager = ExtraClickFilterManager.shared
    lazy var keyboardDebounceManager = KeyboardDebounceManager.shared
    lazy var superKeyManager = SuperKeyManager.shared
    lazy var menuBarReadoutsManager = MenuBarReadoutsManager.shared
    lazy var systemAlertsManager = SystemAlertsManager.shared
    lazy var archiveExtractor: ArchiveExtractor = .shared

    var statusBarController: StatusBarController?
    var interactionManager: MenuBarInteractionManager?

    func addWindowToNotchSpace(_ window: NSWindow) {
        if cgsSpace == nil { cgsSpace = CGSSpace(level: Self.notchSpaceLevel) }
        cgsSpace?.windows.insert(window)
    }

    func removeWindowFromNotchSpace(_ window: NSWindow) {
        cgsSpace?.windows.remove(window)
    }

    private lazy var lockScreenState = LockScreenState()
    private lazy var caffeineManager = CaffeineManager.shared

    private var cancellables = Set<AnyCancellable>()

    var isScreenLocked = false
    private var isAuthenticating = false

    private var launchpadWindowController: LaunchpadWindowController?
    private var isLaunchpadSetupPending = false
    private lazy var launchpadGestureMonitor: LaunchpadGestureMonitor = .shared

    private var statusItem: NSStatusItem?
    private var networkMonitor: NWPathMonitor?
    private var previouslyFrontmostApp: NSRunningApplication?
    private var didActivateForNotchFocus = false
    private weak var focusedNotchWindow: DynamicFocusWindow?

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

    func unregisterHelper() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("[AppDelegate] Unregistration failed (maybe not registered yet): \(error.localizedDescription)")
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        RemoteViewCrashGuardInstall()

        AX.installGlobalMessagingTimeout()

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard !Self.isRunningUnitTests else { return }
        let launchMode = StartupHealthMarker.shared.beginLaunch()
        GlobalEventTap.shared.installTrustAwareness()
        AccessibilityTrustMonitor.shared.start()
        SystemMutationRecovery.restoreAfterUnexpectedExit()

        SapphireStandardMenu.installIfNeeded()
        ContinuityServicesProvider.shared.install()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHelperConnectionLost),
            name: .sapphireHelperConnectionLost,
            object: nil
        )
        SapphireAnalytics.scheduleBootstrap(after: 8)
        if launchMode == .normal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                FaceIDModelManager.shared.applyResidencyPolicy()
            }
        }
        let launchStartDate = performanceLaunchStart.date
        let launchDuration = ProcessInfo.processInfo.systemUptime - performanceLaunchStart.uptime
        SapphireAnalytics.whenReady {
            SapphirePerformance.recordTrace(
                name: "macos_app_start",
                startTime: launchStartDate,
                duration: launchDuration,
                attributes: [
                    "platform": "macos",
                    "lifecycle": "did_finish_launching"
                ]
            )
        }
        if launchMode == .normal {
            SapphireBrowserIntegration.shared.start()
        }
        SandboxIntegration.shared.start()
        _ = FocusProfileStore.shared
        FocusTriggerEngine.shared.start()
        CaffeineManager.shared.bootstrap()

        NearbyConnectionManager.shared.deviceDisplayName = settingsModel.current.nearbyShareDeviceDisplayName
        observeSettings()

        if launchMode == .normal,
           ProcessInfo.processInfo.environment["PERFMON"] == "1" || UserDefaults.standard.bool(forKey: "enablePerfMonitor") {
            ProcessCPUMonitor.shared.startPeriodicReporting(interval: 60)
            print("[PerfMon] CPU performance monitor enabled. Report logs every 60s.")
        }

        Task {
            var didRoute = false
            await SubscriptionManager.shared.bootstrap(onCachedAccessReady: { [weak self] in
                guard let self else { return }
                if BetaEntitlementRuntime.isBetaBuild, !self.hasConfirmedBetaAccess { return }
                didRoute = true
                self.routeAfterLaunch()
            })
            if !didRoute { self.routeAfterLaunch() }
        }
        StartupHealthMarker.shared.scheduleHealthyCheckpoint()
    }

    @discardableResult
    private func routeAfterLaunch() -> Bool {
        SapphireAnalytics.scheduleBootstrap(after: 1)
        if OnboardingLaunchPolicy.shouldShowOnboarding {
            showOnboardingWindow()
            return false
        }

        if BetaEntitlementRuntime.isBetaBuild, !hasConfirmedBetaAccess {
            showBetaBlocker()
            return false
        }

        startMainApp()
        return true
    }

    private var hasConfirmedBetaAccess: Bool {
        guard BetaEntitlementRuntime.isBetaBuild else { return true }
        let validator = BetaEntitlementRuntime.makeValidator()
        return validator.validateBetaEntitlement() && SubscriptionManager.shared.hasBetaSoftwareAccess
    }

    private func observeSettings() {
        settingsModel.$settings
            .map { [$0.faceIDKeepModelsInMemory, $0.faceIDUnlockEnabled, $0.hasRegisteredFaceID] }
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in FaceIDModelManager.shared.applyResidencyPolicy() }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.googleAnalyticsEnabled)
            .dropFirst()
            .removeDuplicates()
            .sink { _ in SapphireAnalytics.applyCollectionPreference() }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.nearbyShareDeviceDisplayName)
            .dropFirst()
            .removeDuplicates()
            .sink { NearbyConnectionManager.shared.deviceDisplayName = $0 }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.nearbyShareEnabled)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.startNearbyShareIfNeeded()
                } else {
                    NearbyConnectionManager.shared.becomeInvisible()
                }
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.launchAtLogin)
            .removeDuplicates()
            .sink { isOn in
                DispatchQueue.global(qos: .utility).async { Self.toggleLaunchAtLogin(isOn: isOn) }
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.hideFromScreenSharing)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.updateWindowSharing(hide: $0) }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.launchpadEnabled)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, self.isMainAppRunning else { return }
                if enabled { self.setupLaunchpad() } else { self.teardownLaunchpad() }
                self.setupStatusBarItem()
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.menuBarEnabled)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, self.isMainAppRunning else { return }
                if enabled {
                    if self.statusBarController == nil {
                        self.statusBarController = StatusBarController()
                        self.interactionManager = MenuBarInteractionManager.shared
                        self.interactionManager?.startMonitoring()
                        MenuBarHotkeyMonitor.shared.start()
                    }
                } else {
                    self.interactionManager?.stopMonitoring()
                    self.interactionManager = nil
                    StatusBarController.teardown(self.statusBarController)
                    self.statusBarController = nil
                }
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map { NotchScreenSelection(target: $0.notchDisplayTarget, perDisplay: $0.perDisplayShowNotch) }
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isMainAppRunning else { return }
                self.createNotchWindow()
            }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.systemEnhanceDockPreviewsEnabled)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self, self.isMainAppRunning else { return }
                if enabled {
                    self.systemEnhanceDockPreviewController.start()
                } else {
                    self.systemEnhanceDockPreviewController.dismiss()
                }
            }
            .store(in: &cancellables)

        observeSubscriptionForBetaGate()
    }

    private func observeSubscriptionForBetaGate() {
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

        guard previousTier != newTier || lostBetaAccess || !SubscriptionManager.shared.hasBetaSoftwareAccess else { return }
        presentBetaBlockerStoppingMainApp()
    }

    private func presentBetaBlockerStoppingMainApp() {
        stopMainApp()
        showBetaBlocker()
    }

    private func stopMainApp() {
        guard isMainAppRunning else { return }

        AppSystemTeardown.restoreManagedSystemState(reason: "beta-access-revoked")
        NearbyConnectionManager.shared.becomeInvisible()

        isMainAppRunning = false

        UpdateChecker.shared.stopPeriodicChecks()

        cancelNotchDisplayRefresh()
        for window in notchWindows {
            destroyNotchWindow(window)
        }
        notchWindows.removeAll()
        cgsSpace?.removeAllWindows()
        cgsSpace = nil

        settingsWindow?.orderOut(nil)
        settingsWindow?.contentView = nil
        settingsWindow?.close()
        settingsWindow = nil

        onboardingWindow?.orderOut(nil)
        onboardingWindow?.contentView = nil
        onboardingWindow = nil

        lyricsWindow?.orderOut(nil)
        lyricsWindow?.contentView = nil
        lyricsWindow = nil

        teardownLaunchpad()

        interactionManager?.stopMonitoring()
        interactionManager = nil
        StatusBarController.teardown(statusBarController)
        statusBarController = nil

        systemEnhanceDockPreviewController.dismiss()
        systemEnhanceWindowSwitcher.dismiss()
        systemEnhanceDockClicks.stopMonitoring()
        systemEnhanceAutoQuit.stopObserving()
        systemEnhanceQuitProtection.removeTap()
        systemEnhanceGreenMaximize.stopMonitoring()
        systemEnhanceHingeAnimation.stop()
        emojiShortcutManager.stopMonitoring()
        clipboardPickerManager.stopMonitoring()
        clipboardAutoClearManager.stop()
        cleanURLManager.stopMonitoring()
        finderCutPasteManager.removeTap()
        snippetManager.removeHandler()
        mouseControlManager.shutdown()
        focusFollowsMouseManager.removeMonitors()
        extraClickFilterManager.shutdown()
        keyboardDebounceManager.stopMonitoring()
        superKeyManager.stopMonitoring()
        menuBarReadoutsManager.removeStatusItem()
        systemAlertsManager.stopMonitoring()

        subscriptionValidationTimer?.invalidate()
        subscriptionValidationTimer = nil
        backgroundInitializationTask?.cancel()
        backgroundInitializationTask = nil
        liveActivityStartTask?.cancel()
        liveActivityStartTask = nil
        liveActivityManager.stop()
        DevActivityMonitor.shared.stop()
        LiveWallpaperManager.shared.shutdown()

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
        NotificationCenter.default.removeObserver(
            self,
            name: .subscriptionSessionRevoked,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .sapphireOpenAccountPane,
            object: nil
        )

        NSApp.setActivationPolicy(.accessory)
        scheduleAllocatorRelief()
    }

    // MARK: - Onboarding

    func showOnboardingWindow() {
        SapphireAnalytics.logEvent("onboarding_started")

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
            window.sharingType = settingsModel.current.hideFromScreenSharing ? .none : .readOnly
            let hostingView = FocusableHostingView(rootView: OnboardingView(onComplete: { self.onboardingDidComplete() }))
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
        LaunchAtLoginReconciler.reconcile(wanted: settingsModel.current.launchAtLogin, isUserChange: true) { isOn in
            Self.adoptLaunchAtLogin(isOn)
        }
        SapphireAnalytics.logEvent("onboarding_completed")
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        if routeAfterLaunch() {
            DispatchQueue.main.async { self.openSettingsWindow() }
        }
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
            _ = await MainActor.run { self.routeAfterLaunch() }
        }
    }

    func startMainApp() {
        guard !isMainAppRunning else { return }

        if BetaEntitlementRuntime.isBetaBuild, !hasConfirmedBetaAccess {
            showBetaBlocker()
            return
        }

        isMainAppRunning = true

        SapphireAnalytics.logEvent("main_app_started")

        transitionToAgentApp()

        FanManager.resumeAfterSuspension()
        HelperManager.shared.installIfNeeded()

        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        createNotchWindow()
        archiveExtractor.reconcileDefaultHandlerIfNeeded()
        dmgInstallerManager.reconcileDefaultHandlerIfNeeded()
        _ = circleToSearchManager
        _ = systemEnhanceWindowRegistry
        systemEnhanceDockPreviewController.start()
        systemEnhanceWindowSwitcher.start()
        systemEnhanceDockClicks.start()
        systemEnhanceAutoQuit.start()
        systemEnhanceQuitProtection.start()
        systemEnhanceGreenMaximize.start()
        systemEnhanceContextMenu.installIfNeeded()
        systemEnhanceHingeAnimation.start()
        DockLayoutsManager.shared.start()
        DockLayoutsManager.shared.startDockBehaviorSync()
        if settingsModel.isPremiumActive(.sportsWidget, \.sportsWidgetEnabled) {
            SportsAPIService.shared.bootstrapIfNeeded()
        }
        settingsModel.premiumChanges(.sportsWidget, \.sportsWidgetEnabled)
            .filter { $0 }
            .sink { _ in SportsAPIService.shared.bootstrapIfNeeded() }
            .store(in: &cancellables)
        MediaOptimizerManager.shared.start()
        FileOperationProgressRouter.shared.start()
        _ = ocrScreenshotMonitor
        requestScreenRecordingForSystemEnhanceIfNeeded()
        _ = emojiShortcutManager
        _ = clipboardPickerManager
        ClipboardManager.shared.startMonitoring()
        clipboardAutoClearManager.start()
        cleanURLManager.start()
        finderCutPasteManager.start()
        snippetManager.start()
        _ = mouseControlManager
        focusFollowsMouseManager.start()
        extraClickFilterManager.start()
        keyboardDebounceManager.start()
        superKeyManager.start()
        menuBarReadoutsManager.start()
        systemAlertsManager.start()
        if StartupHealthMarker.shared.isRecoveryLaunch {
            print("[AppDelegate] Recovery launch: Live Wallpaper and agent activity detection stay off until the next launch.")
        } else {
            DevActivityMonitor.shared.start()
        }
        AppActivityMonitor.shared.bootstrap()
        if !StartupHealthMarker.shared.isRecoveryLaunch {
            LiveWallpaperManager.shared.start()
        }
        _ = archiveExtractor
        _ = keyboardShortcutManager
        _ = plainTextPasteManager
        _ = focusSessionShortcutMonitor
        _ = focusScheduleManager
        _ = appLockManager
        _ = lidAngleAutomationManager
        setupStatusBarItem()
        initializeBackgroundServices()
        EarbudControlManager.shared.activate()
        if settingsModel.current.menuBarEnabled {
            if statusBarController == nil {
                statusBarController = StatusBarController()
                interactionManager = MenuBarInteractionManager.shared
                interactionManager?.startMonitoring()
                MenuBarHotkeyMonitor.shared.start()
            }
        }

        SystemControl.configureKeyboardBacklight()
        setupSessionObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionPaywallRequest(_:)), name: .subscriptionPaywallRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionSessionRevoked(_:)), name: .subscriptionSessionRevoked, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAccountPaneOpened), name: .sapphireOpenAccountPane, object: nil)
        UNUserNotificationCenter.current().delegate = self
        NearbyConnectionManager.shared.mainAppDelegate = self
        startNearbyShareIfNeeded()
        continuityManager.startIfEnabled()
        UpdateChecker.shared.startPeriodicChecks(interval: 5 * 60 * 60)
        InstalledAppUpdatesChecker.shared.applySettings(
            installedAppUpdatesEnabled: settingsModel.current.installedAppUpdatesEnabled,
            notificationsEnabled: settingsModel.current.installedAppUpdateNotificationsEnabled
        )
        if settingsModel.current.launchpadEnabled {
            setupLaunchpad()
        }

        scheduleHelperHealthCheck()
        scheduleSubscriptionValidationTimer()
    }

    private func requestScreenRecordingForSystemEnhanceIfNeeded() {
        let settings = settingsModel.settings
        let needsWindowCapture = settings.systemEnhanceDockPreviewsEnabled || settings.systemEnhanceWindowSwitcherEnabled
        let needsHingeCapture = settings.systemEnhanceHingeAnimationEnabled && LidAngleSensor.shared.isAvailable
        guard needsWindowCapture || needsHingeCapture else { return }
        guard needsHingeCapture || PermissionsManager.shared.accessibilityStatus == .granted else { return }
        guard PermissionsManager.shared.screenRecordingStatus == .notRequested else { return }
        guard !UserDefaults.standard.bool(forKey: "screenRecordingRequested") else { return }
        PermissionsManager.shared.requestPermission(.screenRecording)
    }

    private func scheduleSubscriptionValidationTimer() {
        subscriptionValidationTimer?.invalidate()
        subscriptionValidationTimer = Timer.scheduledCoalescing(withTimeInterval: 5 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in
                print("[AppDelegate] Periodic subscription validation (5-hour interval).")
                await SubscriptionManager.shared.validateSubscriptionStatus()
            }
        }
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

    private func startNearbyShareIfNeeded() {
        guard isMainAppRunning, settingsModel.current.nearbyShareEnabled else { return }
        NearbyConnectionManager.shared.becomeVisible()
    }

    private func initializeBackgroundServices() {
        guard backgroundInitializationTask == nil else { return }
        let warmUp = !StartupHealthMarker.shared.isRecoveryLaunch
        backgroundInitializationTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await MainActor.run { self.initializeCoreManagers() }
            guard warmUp else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            _ = await self.batteryManager.getBatteryTemperature()
        }
    }

    // MARK: - Session Observers

    private func setupSessionObservers() {
        guard !sessionObserversInstalled else { return }
        sessionObserversInstalled = true
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
            guard let self else { return }
            DispatchQueue.main.async {
                let isSatisfied = path.status == .satisfied
                let wasSatisfied = self.networkPathSatisfied
                self.networkPathSatisfied = isSatisfied
                guard self.isMainAppRunning, isSatisfied, wasSatisfied == false else { return }
                print("[AppDelegate] Network connection became available.")
                self.musicManager.spotifyPrivateAPI.checkAndReconnectIfNeeded()
                Task {
                    await SubscriptionManager.shared.validateSubscriptionStatus()
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue(label: "NetworkMonitor", qos: .utility))
    }

    private var hasPresentedHelperConnectionAlertThisSession = false
    private var helperHasConnectedThisSession = false

    @objc private func systemDidWake(notification: NSNotification) {
        notchDisplaysDidWake()
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
        notchDisplaysDidSleep()
        if isScreenLocked {
            LockScreenMusicPaneController.shared.reset()
            lockScreenManager.hideAndDestroyWindows(animated: false)
        }
    }

    @objc private func displayDidWake(notification: NSNotification) {
        AuthenticationManager.shared.handleDisplayDidWake()
        notchDisplaysDidWake()
        onDisplayWake()
        if isScreenLocked {
            showLockScreenWidgets()
        }
    }

    @objc private func handleApplicationDidBecomeActive(_ notification: Notification) {
        HelperManager.shared.updateStatus()
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
        lockScreenState.isFaceIDEnabled = settingsModel.current.faceIDUnlockEnabled &&
                                          settingsModel.current.hasRegisteredFaceID &&
                                          authManager.isFaceIDAllowedAtCurrentLocation()

        lockScreenState.isBluetoothUnlockEnabled = settingsModel.current.bluetoothUnlockEnabled

        if settingsModel.current.lockScreenLiveActivityEnabled {
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

        if settingsModel.current.lockScreenShowNotch {
            for window in notchWindows {
                lockScreenManager.delegateWindow(window)
            }
        }

        LiveWallpaperManager.shared.screenDidLock()

        showLockScreenWidgets()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showLockScreenWidgets() {
        guard let mainScreen = NSScreen.main else { return }
        var widgetConfigs: [LockScreenManager.LockScreenWidgetConfig] = []

        if settingsModel.current.lockScreenShowInfoWidget {
            widgetConfigs.append(.init(
                id: "infoWidget",
                initialSize: .zero,
                positioner: lockScreenManager.calculateInfoWidgetFrame(size:screen:)
            ) { manager, initialFrame, screen in
                manager.displayView(
                    LockScreenInfoWidgetView()
                        .environmentObject(self.weatherActivityViewModel)
                        .environmentObject(self.calendarService)
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

        if settingsModel.current.lockScreenShowMainWidget &&
           !settingsModel.current.lockScreenMainWidgets.isEmpty {
            widgetConfigs.append(.init(
                id: "mainWidgetContainer",
                initialSize: .zero,
                positioner: lockScreenManager.calculateMainWidgetFrame(size:screen:)
            ) { manager, initialFrame, screen in
                manager.displayView(
                    LockScreenMainWidgetContainerView()
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

        if settingsModel.current.lockScreenShowMiniWidgets &&
           !settingsModel.current.lockScreenMiniWidgets.isEmpty {
            widgetConfigs.append(.init(
                id: "miniWidgets",
                initialSize: .zero,
                positioner: lockScreenManager.calculateMiniWidgetFrame(size:screen:)
            ) { manager, initialFrame, screen in
                manager.displayView(
                    LockScreenMiniWidgetView()
                        .environmentObject(self.weatherActivityViewModel)
                        .environmentObject(self.calendarService)
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
                LockScreenFullScreenMusicPane(),
                withId: "fullScreenMusicPane",
                initialFrame: initialFrame,
                positioner: manager.calculateFullScreenMusicFrame(size:screen:),
                windowLevel: .mainMenu + 4,
                on: screen
            )
        })

        lockScreenManager.setupAndShowWindows(configs: widgetConfigs, on: mainScreen)
    }

    @objc private func screenIsUnlocked() {
        lockScreenManager.hideAndDestroyWindows()

        LiveWallpaperManager.shared.screenDidUnlock()

        LockScreenMusicPaneController.shared.reset()

        authManager.purgeFaceIDAfterUnlock()

        guard isScreenLocked else { return }
        isScreenLocked = false
        isAuthenticating = false
        lockScreenState.isUnlocked = true
        lockScreenState.isAuthenticating = false
        lockScreenState.faceIDRequiresPassword = false

        authManager.cancelPendingPasswordInjection(reason: "screen unlocked")

        liveActivityManager.finishLockScreenActivity()

        for window in notchWindows {
            lockScreenManager.removeWindow(window)
            reassertNotchSpaceMembership(window)
            if (window as? DynamicFocusWindow)?.isNotchHidden != true {
                window.orderFrontRegardless()
            }
        }
    }

    private func startAuthentication() {
        guard isScreenLocked, !isAuthenticating else { return }
        isAuthenticating = true
        lockScreenState.isAuthenticating = true
        lockScreenState.faceIDRequiresPassword = false

        if settingsModel.current.bluetoothUnlockEnabled {
            authManager.startBluetoothAuthentication()
        }
        if settingsModel.current.faceIDUnlockEnabled && settingsModel.current.hasRegisteredFaceID {
            authManager.refreshFaceIDLocation { [weak self] in
                guard let self, self.isScreenLocked, self.isAuthenticating else { return }
                self.lockScreenState.isFaceIDEnabled = self.authManager.isFaceIDAllowedAtCurrentLocation()
                self.authManager.startFaceIDAuthentication()
            }
        }
    }

    #if DEBUG
    func debugSimulateLockScreen(_ locked: Bool) {
        if locked {
            lockScreenState.isUnlocked = false
            lockScreenState.isAuthenticating = false
            lockScreenState.faceIDRequiresPassword = false
            lockScreenState.isCaffeineActive = caffeineManager.isActive
            lockScreenState.isFaceIDEnabled = true
            lockScreenState.isBluetoothUnlockEnabled = settingsModel.current.bluetoothUnlockEnabled
            liveActivityManager.startLockScreenActivity()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.lockScreenState.isAuthenticating = true
            }
        } else {
            lockScreenState.isUnlocked = true
            lockScreenState.isAuthenticating = false
            liveActivityManager.finishLockScreenActivity()
        }
    }
    #endif

    func markFaceIDRequiresPassword() {
        lockScreenState.faceIDRequiresPassword = true
    }

    func refreshFaceIDLocationAvailability() {
        guard isScreenLocked else { return }
        lockScreenState.isFaceIDEnabled = settingsModel.current.faceIDUnlockEnabled &&
                                          settingsModel.current.hasRegisteredFaceID &&
                                          authManager.isFaceIDAllowedAtCurrentLocation()
    }

    // MARK: - Activation Policy

    private func transitionToAgentApp() {
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Termination

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isMainAppRunning {
            openSettingsWindow()
        } else if let onboardingWindow {
            UtilityWindowPresenter.present(onboardingWindow)
        } else if let betaBlockerWindow {
            UtilityWindowPresenter.present(betaBlockerWindow)
        } else {
            routeAfterLaunch()
        }
        return false
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        StartupHealthMarker.shared.markCleanExit()
        mouseControlManager.restoreSystemSettings()
        settingsModel.flushPendingSave()
        NearbyConnectionManager.shared.becomeInvisible()
        continuityManager.stop()
        SandboxIntegration.shared.stop()
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
        cgsSpace?.removeAllWindows()
        cgsSpace = nil
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        backgroundInitializationTask?.cancel()
        backgroundInitializationTask = nil
        liveActivityStartTask?.cancel()
        liveActivityStartTask = nil
        if isMainAppRunning {
            liveActivityManager.stop()
            DevActivityMonitor.shared.stop()
        }
        networkMonitor?.cancel()
        networkMonitor = nil
        networkPathSatisfied = nil
        sessionObserversInstalled = false
        UpdateChecker.shared.stopPeriodicChecks()
        teardownLaunchpad()
        interactionManager?.stopMonitoring()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func cleanupNotchWindow() {
        cancelNotchDisplayRefresh()

        for window in notchWindows {
            destroyNotchWindow(window)
        }
        notchWindows.removeAll()
    }

    // MARK: - File Handling (DMG Installer & Archives)

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !Self.isRunningUnitTests else { return }
        if !isMainAppRunning, let other = DefaultFileHandler.otherRunningInstance(), let otherURL = other.bundleURL {
            appDelegateLog.info("Forwarding \(urls.count, privacy: .public) opened file(s) to the running Sapphire instance (pid \(other.processIdentifier, privacy: .public))")
            NSWorkspace.shared.open(urls, withApplicationAt: otherURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.async { exit(0) }
            }
            return
        }
        let dmgURLs = urls.filter { $0.pathExtension.lowercased() == "dmg" }
        let archiveURLs = urls.filter { !dmgURLs.contains($0) && ArchiveExtractor.isArchiveURL($0) }
        let layoutURLs = urls.filter { !dmgURLs.contains($0) && !archiveURLs.contains($0) && $0.pathExtension.lowercased() == "sapphiredocklayout" }
        if !dmgURLs.isEmpty {
            dmgInstallerManager.handleOpenURLs(dmgURLs)
        }
        if !archiveURLs.isEmpty {
            archiveExtractor.handleOpenURLs(archiveURLs)
        }
        if !layoutURLs.isEmpty {
            DockLayoutsManager.shared.importLayoutFiles(at: layoutURLs)
        }
    }

    // MARK: - URL Handling

    @objc func handleGetURL(event: NSAppleEventDescriptor!, withReplyEvent: NSAppleEventDescriptor!) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme?.lowercased() == "sapphire"
        else { return }
        if url.host == "android-widgets" {
            let focus = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "id" }?.value.flatMap(Int.init)
            continuityManager.openWidgets(focus: focus)
            return
        }
        if url.host?.lowercased() == "writedata" {
            AccessoryBatteryStore.writeData()
            return
        }
        if url.host?.lowercased() == "vm" {
            guard SandboxIntegration.validatedDestinationURL(for: url) != nil else {
                return
            }
            if !SandboxIntegration.shared.forwardValidatedDeepLink(url) {
                presentSapphireVMLaunchFailureIfNeeded()
            }
            return
        }
        musicManager.spotifyOfficialAPI.handleRedirect(url: url)
        musicManager.tidalAPI.handleRedirect(url: url)
    }

    private func presentSapphireVMLaunchFailureIfNeeded() {
        guard !isPresentingSapphireVMLaunchFailure else { return }
        isPresentingSapphireVMLaunchFailure = true

        HelperAlertPresenter.presentModal(
            messageText: "Sapphire VM Isn’t Available",
            informativeText: "Sapphire couldn’t open this virtual machine link. Make sure the standalone Sapphire VM app is installed, then try again.",
            alertStyle: .warning,
            buttonTitles: ["OK"]
        ) { [weak self] _ in
            self?.isPresentingSapphireVMLaunchFailure = false
        }
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
        if isMainAppRunning && settingsModel.current.launchpadEnabled {
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
        if launchpadWindowController == nil && settingsModel.current.launchpadEnabled {
            setupLaunchpad()
        }
        launchpadWindowController?.showLaunchpad()
    }

    private func setupLaunchpad() {
        guard isMainAppRunning,
              settingsModel.current.launchpadEnabled,
              launchpadWindowController == nil,
              !isLaunchpadSetupPending else { return }
        isLaunchpadSetupPending = true
        setupStatusBarItem()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isLaunchpadSetupPending = false }
            guard self.isMainAppRunning,
                  self.settingsModel.current.launchpadEnabled,
                  self.launchpadWindowController == nil else { return }
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
        isLaunchpadSetupPending = false
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
    private var notchScreenRefreshGeneration = 0

    func createNotchWindow() {
        guard !isCreatingNotchWindow else { return }
        isCreatingNotchWindow = true
        defer { isCreatingNotchWindow = false }

        let targetScreens = targetNotchScreens()
        guard !targetScreens.isEmpty else {
            cleanupNotchWindows(excluding: [])
            return
        }

        let orderedTargetIDs = targetScreens.compactMap { displayID(for: $0) }
        let targetDisplayIDs = Set(orderedTargetIDs)
        guard !targetDisplayIDs.isEmpty else { return }

        var seenDisplayIDs: Set<CGDirectDisplayID> = []
        notchWindows = notchWindows.filter { window in
            guard let windowDisplayID = (window as? DynamicFocusWindow)?.displayID, windowDisplayID != 0 else {
                return true
            }
            if seenDisplayIDs.contains(windowDisplayID) {
                destroyNotchWindow(window)
                return false
            }
            seenDisplayIDs.insert(windowDisplayID)
            return true
        }

        let plan = NotchDisplayRefreshPolicy.plan(
            windowDisplays: notchWindows.compactMap { ($0 as? DynamicFocusWindow)?.displayID },
            targets: orderedTargetIDs
        )
        for move in plan.moves {
            guard let window = notchWindows.first(where: { ($0 as? DynamicFocusWindow)?.displayID == move.from })
                as? DynamicFocusWindow else { continue }
            appDelegateLog.info("Moving notch window from display \(move.from, privacy: .public) to \(move.to, privacy: .public)")
            window.displayID = move.to
        }

        cleanupNotchWindows(excluding: targetDisplayIDs)

        for screen in targetScreens {
            guard let screenDisplayID = displayID(for: screen) else { continue }
            let existing = notchWindows.first { ($0 as? DynamicFocusWindow)?.displayID == screenDisplayID }
            if let existing {
                existing.sharingType = settingsModel.current.hideFromScreenSharing ? .none : .readOnly
                syncNotchWindowFrame(existing, to: screen)
                (existing as? DynamicFocusWindow)?.setDisplayDetached(false)
                continue
            }

            createNotchWindowForScreen(screen)
        }

        for move in plan.moves {
            let moved = notchWindows.first { ($0 as? DynamicFocusWindow)?.displayID == move.to } as? DynamicFocusWindow
            moved?.onDisplayConfigurationChange?()
        }

        scheduleLiveActivityStart()
    }

    private func targetNotchScreens() -> [NSScreen] {
        NotchScreens.screens(for: settingsModel.settings)
    }

    private func syncNotchWindowFrame(_ window: NSWindow, to screen: NSScreen) {
        if let window = window as? DynamicFocusWindow, window.hostSizer.reapply(on: screen) { return }
        let screenFrame = screen.frame
        let initialConfig = ResolvedNotchConfiguration(from: settingsModel.settings, screen: screen)
        let paddedWidth = ceil(screenFrame.width)
        let paddedHeight = ceil(max(initialConfig.initialSize.height + initialConfig.topInset + initialConfig.topBuffer + 24, screenFrame.height * 0.42))
        let targetRect = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - paddedHeight,
            width: paddedWidth,
            height: paddedHeight
        )

        let current = window.frame
        guard abs(current.origin.x - targetRect.origin.x) > 0.5
            || abs(current.origin.y - targetRect.origin.y) > 0.5
            || abs(current.width - targetRect.width) > 0.5
            || abs(current.height - targetRect.height) > 0.5 else {
            return
        }

        window.setFrame(targetRect, display: true, animate: false)
        window.contentView?.frame = NSRect(origin: .zero, size: targetRect.size)
        (window.contentView as? NotchStageContainerView)?.setStageSize(targetRect.size)
    }

    private func createNotchWindowForScreen(_ screen: NSScreen) {
        let initialConfig = ResolvedNotchConfiguration(from: settingsModel.settings, screen: screen)
        let initialExtent = NotchHostWindowExtent(
            isFull: false,
            notchSize: initialConfig.initialSize,
            notchTopOffset: initialConfig.topInset - initialConfig.topBuffer,
            collapsedHeight: initialConfig.initialSize.height,
            fullBandInset: initialConfig.topInset + initialConfig.topBuffer
        )
        let rect = NotchHostWindowSizer.frame(for: initialExtent, on: screen)
        let stageSize = NotchHostWindowSizer.stageSize(
            current: nil,
            extent: initialExtent,
            windowSize: rect.size,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            scale: screen.backingScaleFactor
        )

        let window = DynamicFocusWindow(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.displayID = displayID(for: screen) ?? 0
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.setMouseEventHandlingEnabled()
        window.sharingType = settingsModel.current.hideFromScreenSharing ? .none : .readOnly

        if cgsSpace == nil { cgsSpace = CGSSpace(level: Self.notchSpaceLevel) }
        cgsSpace?.windows.insert(window)
        if isScreenLocked, settingsModel.current.lockScreenShowNotch {
            lockScreenManager.delegateWindow(window)
        }

        let controllerView = NotchController(
            notchWindow: window,
            initialConfiguration: initialConfig,
            timerManager: timerManager,
            widgetEnvironment: { [weak self] view in
                guard let self else { return view }
                return AnyView(self.applyNotchEnvironment(to: view))
            }
        )
        let container = ZStack(alignment: .top) {
            controllerView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()

        let hosting = PassthroughHostingView(rootView: applyNotchEnvironment(to: container))
        hosting.frame = NSRect(origin: .zero, size: stageSize)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = NotchStageContainerView(
            frame: NSRect(origin: .zero, size: rect.size),
            stageView: hosting,
            stageSize: stageSize
        )
        window.contentView?.layoutSubtreeIfNeeded()
        if !window.isNotchHidden, !window.isDisplayDetached { window.orderFrontRegardless() }

        notchWindows.append(window)
    }

    private func destroyNotchWindow(_ window: NSWindow) {
        if let window = window as? DynamicFocusWindow {
            window.onTeardown?()
            window.onTeardown = nil
            window.onDisplayConfigurationChange = nil
            window.hostSizer.onFrameChange = nil
        }
        if focusedNotchWindow === window { focusedNotchWindow = nil }
        lockScreenManager.removeWindow(window)
        cgsSpace?.windows.remove(window)
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    func reassertNotchSpaceMembership(_ window: NSWindow) {
        guard notchWindows.contains(where: { $0 === window }) else { return }
        if isScreenLocked, settingsModel.current.lockScreenShowNotch {
            lockScreenManager.delegateWindow(window)
            return
        }
        if cgsSpace == nil { cgsSpace = CGSSpace(level: Self.notchSpaceLevel) }
        cgsSpace?.reassert(window)
    }

    private func notifyNotchDisplayConfigurationChanged() {
        for case let window as DynamicFocusWindow in notchWindows {
            window.onDisplayConfigurationChange?()
        }
    }

    private func applyNotchEnvironment<V: View>(to view: V) -> some View {
        view
            .environmentObject(lockScreenState)
            .environmentObject(systemHUDManager)
            .environment(liveActivityManager)
            .environmentObject(audioDeviceManager)
            .environmentObject(bluetoothManager)
            .environmentObject(notificationManager)
            .environmentObject(desktopManager)
            .environmentObject(focusModeManager)
            .environmentObject(eyeBreakManager)
            .environmentObject(timerManager)
            .environmentObject(focusSessionManager)
            .environmentObject(contentPickerHelper)
            .environment(geminiLiveManager)
            .environmentObject(activeAppMonitor)
            .environmentObject(batteryEstimator)
            .environmentObject(DragStateManager.shared)
            .environmentObject(calendarService)
            .environmentObject(intelligenceViewModel)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func cleanupNotchWindows(excluding targetScreenIDs: Set<CGDirectDisplayID>) {
        notchWindows = notchWindows.filter { window in
            let windowDisplayID = (window as? DynamicFocusWindow)?.displayID
                ?? (window.screen.flatMap { displayID(for: $0) } ?? 0)

            let shouldKeep = windowDisplayID != 0 && targetScreenIDs.contains(windowDisplayID)
            if !shouldKeep {
                destroyNotchWindow(window)
            }
            return shouldKeep
        }
    }

    private func scheduleLiveActivityStart() {
        guard liveActivityStartTask == nil else { return }
        liveActivityStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled, self.isMainAppRunning else { return }
            _ = self.pillHUDController
            self.liveActivityManager.start()
        }
    }

    func makeNotchWindowFocusable(_ requester: NSWindow? = nil) {
        guard let window = notchFocusTarget(requester) else { return }
        if let previous = focusedNotchWindow, previous !== window {
            if previous.isKeyWindow { previous.resignKey() }
            previous.isFocusable = false
        }
        focusedNotchWindow = window
        if previouslyFrontmostApp == nil {
            let currentFrontmost = NSWorkspace.shared.frontmostApplication
            if currentFrontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previouslyFrontmostApp = currentFrontmost
            }
        }
        window.isFocusable = true
        if !NSApp.isActive { didActivateForNotchFocus = true }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func revertNotchWindowFocus(_ requester: NSWindow? = nil) {
        let window = (requester as? DynamicFocusWindow) ?? focusedNotchWindow
        if let window {
            if window.isKeyWindow { window.resignKey() }
            window.isFocusable = false
            if focusedNotchWindow === window { focusedNotchWindow = nil }
        }
        if let focusedNotchWindow, focusedNotchWindow.isFocusable { return }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        let handedBack = previouslyFrontmostApp?.activate(options: [.activateIgnoringOtherApps]) ?? false
        if didActivateForNotchFocus, !handedBack, NSApp.isActive {
            NSApp.deactivate()
        }
        didActivateForNotchFocus = false
        previouslyFrontmostApp = nil
    }

    private func notchFocusTarget(_ requester: NSWindow?) -> DynamicFocusWindow? {
        let windows = notchWindows.compactMap { $0 as? DynamicFocusWindow }
        if let requester = requester as? DynamicFocusWindow, windows.contains(where: { $0 === requester }) {
            return requester
        }
        let displayID = NotchDisplayTargeting.display(
            requested: nil,
            pointer: NotchDisplayTargeting.pointerDisplayID,
            notchDisplays: windows.map(\.displayID)
        )
        return windows.first { $0.displayID == displayID } ?? windows.first
    }

    func attachAuxiliaryNotchWindow(_ window: NSWindow) {
        if cgsSpace == nil { cgsSpace = CGSSpace(level: Self.notchSpaceLevel) }
        cgsSpace?.windows.insert(window)
    }

    func detachAuxiliaryNotchWindow(_ window: NSWindow) {
        cgsSpace?.windows.remove(window)
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
            styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.setFrame(frame, display: false)
        window.minSize = NSSize(
            width: NotchConfiguration.settingsWindowMinWidth,
            height: NotchConfiguration.settingsWindowMinHeight
        )
        window.maxSize = NSSize(
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false

        let root = SettingsView()
            .environmentObject(powerStateController)

        let hosting = FocusableHostingView(rootView: root)
        window.contentView = hosting
        window.delegate = self
        settingsWindow = window
        applyRoundedWindowMask(to: window, cornerRadius: NotchConfiguration.settingsWindowCornerRadius)

        UtilityWindowPresenter.presentSettingsWindow(window)
    }

    private func applyRoundedWindowMask(to window: NSWindow, cornerRadius: CGFloat) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = cornerRadius
        frameView.layer?.masksToBounds = true
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
        window.isReleasedWhenClosed = false
        window.sharingType = settingsModel.current.hideFromScreenSharing ? .none : .readOnly

        let root = LyricsDetachedWindowView()

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

        if isSettings {
            NotificationCenter.default.post(name: .sapphireSettingsWillClose, object: nil)
        }

        window.contentView = nil
        window.delegate = nil
        if isSettings, settingsWindow === window { settingsWindow = nil }
        if isLyrics, lyricsWindow === window { lyricsWindow = nil }
        finishClosingUserWindow()
    }

    private func finishClosingUserWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.restoreAgentActivationIfNeeded()
            SettingsModel.shared.flushPendingSave()
            SystemAppFetcher.shared.releaseCachedApps()
            AppIconLoader.releaseCache()
            self.scheduleAllocatorRelief()
        }
    }

    private func scheduleAllocatorRelief() {
        pendingAllocatorRelief?.cancel()

        let workItem = DispatchWorkItem {
            SapphireMemoryFlushAllMallocZones()
        }
        pendingAllocatorRelief = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 0.25,
            execute: workItem
        )
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
    private var notchScreenRefreshRetryWorkItem: DispatchWorkItem?

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
        resyncNotchWindowsToDisplays()
        scheduleNotchDisplayRefresh()
    }

    private func resyncNotchWindowsToDisplays() {
        guard isMainAppRunning else { return }
        let screens = NSScreen.screens
        for case let window as DynamicFocusWindow in notchWindows where window.displayID != 0 {
            if let screen = screens.first(where: { $0.displayID == window.displayID }) {
                if !NotchHostWindowSizer.isPlaced(window.frame, onScreen: screen.frame) {
                    window.hostSizer.reapply(on: screen)
                }
                window.setDisplayDetached(false)
            } else {
                window.setDisplayDetached(true)
            }
        }
    }

    private var areNotchDisplaysAsleep = false

    private func notchDisplaysDidSleep() {
        areNotchDisplaysAsleep = true
        cancelNotchDisplayRefresh()
    }

    private func notchDisplaysDidWake() {
        areNotchDisplaysAsleep = false
        scheduleNotchDisplayRefresh()
    }

    private func cancelNotchDisplayRefresh() {
        screenParametersDebounceTimer?.invalidate()
        screenParametersDebounceTimer = nil
        notchScreenRefreshRetryWorkItem?.cancel()
        notchScreenRefreshRetryWorkItem = nil
        notchScreenRefreshGeneration += 1
    }

    private func scheduleNotchDisplayRefresh() {
        cancelNotchDisplayRefresh()
        guard isMainAppRunning, !areNotchDisplaysAsleep else { return }
        let generation = notchScreenRefreshGeneration
        screenParametersDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: NotchDisplayRefreshPolicy.debounce,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screenParametersDebounceTimer = nil
                self.readNotchDisplaysUntilStable(generation: generation, previous: nil, reads: 0)
            }
        }
    }

    private func scheduleNotchRefreshStep(after delay: TimeInterval, _ step: @escaping @MainActor () -> Void) {
        notchScreenRefreshRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { MainActor.assumeIsolated { step() } }
        notchScreenRefreshRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func isCurrentNotchRefresh(_ generation: Int) -> Bool {
        isMainAppRunning && !areNotchDisplaysAsleep && generation == notchScreenRefreshGeneration
    }

    private func currentNotchDisplaySnapshot() -> NotchDisplayRefreshPolicy.Snapshot {
        NotchDisplayRefreshPolicy.Snapshot(
            displays: NSScreen.screens.map { .init(id: $0.displayID, frame: $0.frame) },
            targets: targetNotchScreens().map(\.displayID)
        )
    }

    private func readNotchDisplaysUntilStable(
        generation: Int,
        previous: NotchDisplayRefreshPolicy.Snapshot?,
        reads: Int
    ) {
        guard isCurrentNotchRefresh(generation) else { return }
        let current = currentNotchDisplaySnapshot()
        switch NotchDisplayRefreshPolicy.step(previous: previous, current: current, reads: reads + 1) {
        case .apply:
            refreshNotchScreens(generation: generation, attempt: 0, isSettlePass: false)
        case .readAgain:
            scheduleNotchRefreshStep(after: NotchDisplayRefreshPolicy.stabilityInterval) { [weak self] in
                self?.readNotchDisplaysUntilStable(generation: generation, previous: current, reads: reads + 1)
            }
        case .skip:
            notchScreenRefreshRetryWorkItem = nil
        }
    }

    private func refreshNotchScreens(generation: Int, attempt: Int, isSettlePass: Bool) {
        guard isCurrentNotchRefresh(generation) else { return }
        guard !NSScreen.screens.isEmpty else { return }

        createNotchWindow()
        notifyNotchDisplayConfigurationChanged()

        if targetNotchScreens().isEmpty, attempt < 12 {
            scheduleNotchRefreshStep(after: 0.5) { [weak self] in
                self?.refreshNotchScreens(generation: generation, attempt: attempt + 1, isSettlePass: isSettlePass)
            }
            return
        }
        guard !isSettlePass else {
            notchScreenRefreshRetryWorkItem = nil
            return
        }
        scheduleNotchRefreshStep(after: NotchDisplayRefreshPolicy.settleDelay) { [weak self] in
            self?.refreshNotchScreens(generation: generation, attempt: 0, isSettlePass: true)
        }
    }

    // MARK: - Launch at Login

    private nonisolated static let launchAtLoginFirstCheck = OSAllocatedUnfairLock(initialState: true)

    private nonisolated static func toggleLaunchAtLogin(isOn: Bool) {
        let isLaunchCheck = launchAtLoginFirstCheck.withLock { first in
            defer { first = false }
            return first
        }
        LaunchAtLoginReconciler.reconcile(wanted: isOn, isUserChange: !isLaunchCheck) { adopted in
            adoptLaunchAtLogin(adopted)
        }
    }

    @MainActor
    private static func adoptLaunchAtLogin(_ isOn: Bool) {
        let model = SettingsModel.shared
        guard model.current.launchAtLogin != isOn else { return }
        var settings = model.settings
        settings.launchAtLogin = isOn
        model.settings = settings
    }

    // MARK: - Window Sharing

    private func updateWindowSharing(hide: Bool) {
        let sharingType: NSWindow.SharingType = hide ? .none : .readOnly
        for window in notchWindows {
            window.sharingType = sharingType
        }
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

    // MARK: - Nearby Share Transfers

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, fileURLs: [URL]) {
        DispatchQueue.main.async {
            self.liveActivityManager.startNearbyTransferActivity(transfer: transfer, device: device, fileURLs: fileURLs)
        }
    }

    func incomingTransfer(id: String, didUpdateProgress progress: Double) {
        DispatchQueue.main.async {
            self.liveActivityManager.updateNearbyTransferProgress(id: id, progress: progress)
        }
    }

    func incomingTransfer(id: String, didFinishWith error: Error?) {
        DispatchQueue.main.async {
            self.liveActivityManager.finishNearbyTransfer(id: id, error: error)
        }
    }

    // MARK: - Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == SapphireBrowserIntegration.linkNotificationCategory {
            SapphireBrowserIntegration.shared.handleLinkNotificationResponse(response)
            completionHandler()
            return
        }
        if let transferID = response.notification.request.content.userInfo["transferID"] as? String {
            let accepted = response.actionIdentifier == "ACCEPT"
            NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accepted)
            if accepted {
                liveActivityManager.updateNearbyTransferState(to: .inProgress)
            } else {
                liveActivityManager.clearNearbyTransferActivity()
            }
        }

        let info = response.notification.request.content.userInfo
        if info["continuitySMS"] as? Bool == true {
            continuityManager.messagesBridge.handleNotificationResponse(response)
            completionHandler()
            return
        }
        if info["continuityCall"] as? Bool == true {
            continuityManager.callsBridge.handleNotificationResponse(response)
            completionHandler()
            return
        }
        if info["continuityHandoff"] as? Bool == true {
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier
                || response.actionIdentifier == ContinuityHandoffBridge.openActionID {
                continuityManager.handoffBridge.handleBannerTap()
            }
            completionHandler()
            return
        }

        if let peerID = info["continuityPeerID"] as? String, let key = info["continuityKey"] as? String {
            switch response.actionIdentifier {
            case UNNotificationDismissActionIdentifier:
                continuityManager.dismissNotificationOnPhone(peerID: peerID, key: key)
            case UNNotificationDefaultActionIdentifier:
                break
            default:
                let replyText = (response as? UNTextInputNotificationResponse)?.userText
                continuityManager.invokeNotificationAction(
                    peerID: peerID, key: key,
                    actionId: response.actionIdentifier, replyText: replyText)
            }
        }
        completionHandler()
    }
}

// MARK: - Keyable window/panel base classes

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class KeyableNonMainPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct NotchScreenSelection: Equatable {
    let target: NotchDisplayTarget
    let perDisplay: [String: Bool]
}