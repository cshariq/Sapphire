//
//  ActiveAppMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-09.
//

import AppKit
import Combine
import ApplicationServices

extension Notification.Name {
    static let activeAppDidChange = Notification.Name("com.sapphire.activeAppDidChange")
}

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let monitor = Unmanaged<ActiveAppMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleAXEvent(notification)
}

@MainActor
class ActiveAppMonitor: ObservableObject {

    static let shared = ActiveAppMonitor()

    @Published private(set) var isLyricsAllowedForActiveApp: Bool = true
    @Published private(set) var activeAppBundleID: String?
    @Published private(set) var isFullScreen: Bool = false
    @Published private(set) var activeSpaceRevision: UInt64 = 0
    @Published private(set) var fullScreenDisplayIDs: Set<CGDirectDisplayID> = [] {
        didSet {
            let anyDisplayFullScreen = !fullScreenDisplayIDs.isEmpty
            if isFullScreen != anyDisplayFullScreen {
                isFullScreen = anyDisplayFullScreen
            }
        }
    }
    @Published private(set) var isWindowDragging: Bool = false

    @Published private(set) var appVisibilityRevision: UInt64 = 0
    @Published private(set) var screenParametersRevision: UInt64 = 0
    @Published private(set) var lastLaunchedBundleID: String?
    @Published private(set) var lastTerminatedBundleID: String?

    private let settingsModel: SettingsModel
    private var cancellables = Set<AnyCancellable>()


    private var lastFullScreenRefreshTime: TimeInterval = 0
    private let fullScreenRefreshThrottle: TimeInterval = 0.3

    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var mouseUpMonitor: Any?
    private var lastMoveTime: TimeInterval = 0

    deinit {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private init() {
        self.settingsModel = SettingsModel.shared

        let spaceChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).map { _ in () }
        let appChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).map { _ in () }

        spaceChangePublisher
            .sink { [weak self] _ in
                guard let self else { return }
                self.activeSpaceRevision &+= 1
            }
            .store(in: &cancellables)

        Publishers.Merge(spaceChangePublisher, appChangePublisher)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveAppState() }
            .store(in: &cancellables)

        $activeAppBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLyricPermission() }
            .store(in: &cancellables)

        settingsModel.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLyricPermission() }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didHideApplicationNotification)
            .sink { [weak self] _ in self?.appVisibilityRevision &+= 1 }
            .store(in: &cancellables)
        workspace.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .sink { [weak self] _ in self?.appVisibilityRevision &+= 1 }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenParametersRevision &+= 1 }
            .store(in: &cancellables)

        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.lastLaunchedBundleID = app?.bundleIdentifier
            }
            .store(in: &cancellables)
        workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.lastTerminatedBundleID = app?.bundleIdentifier
            }
            .store(in: &cancellables)

        updateActiveAppState()
    }

    private func updateActiveAppState() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication, let bundleID = frontmostApp.bundleIdentifier else {
            if isFullScreen != false { isFullScreen = false }
            if !fullScreenDisplayIDs.isEmpty { fullScreenDisplayIDs = [] }
            if activeAppBundleID != nil { activeAppBundleID = nil }
            teardownAXObserver()
            return
        }
        guard bundleID != Bundle.main.bundleIdentifier else {
            return
        }

        if activeAppBundleID != bundleID {
            activeAppBundleID = bundleID
            NotificationCenter.default.post(name: .activeAppDidChange, object: nil)

            setupAXObserver(for: frontmostApp.processIdentifier)
        }

        refreshFullScreenState(for: frontmostApp)
    }

    func isScreenFullScreen(_ screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return fullScreenDisplayIDs.contains(screen.displayID)
    }

    // MARK: - Full Screen Detection

    private func refreshFullScreenState(for app: NSRunningApplication) {
        // Use CGWindowListCopyWindowInfo instead of the Accessibility API: it needs
        // no Accessibility permission and always reflects the real on-screen geometry
        // of the frontmost app's windows. A window counts as full screen when its
        // frame covers an entire display's full bounds (including the strip under the
        // menu bar and behind the Dock); a merely maximized window only fills the
        // display's visible area, so it won't match.
        let pid = app.processIdentifier

        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return
        }

        var displayIDs = Set<CGDirectDisplayID>()
        for info in windows {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  pid_t(ownerPID) == pid,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }
            for screen in NSScreen.screens {
                if isFrame(bounds, coveringDisplay: screen.displayID) {
                    displayIDs.insert(screen.displayID)
                }
            }
        }

        if fullScreenDisplayIDs != displayIDs {
            fullScreenDisplayIDs = displayIDs
        }
    }

    private func isFrame(_ frame: CGRect, coveringDisplay displayID: CGDirectDisplayID, tolerance: CGFloat = 2) -> Bool {
        // CGWindowList bounds and CGDisplayBounds share the same top-left/Down
        // coordinate space, so compare them directly.
        let displayBounds = CGDisplayBounds(displayID)
        return abs(frame.minX - displayBounds.minX) <= tolerance
            && abs(frame.minY - displayBounds.minY) <= tolerance
            && abs(frame.maxX - displayBounds.maxX) <= tolerance
            && abs(frame.maxY - displayBounds.maxY) <= tolerance
    }

    private func updateLyricPermission() {
        let newPermissionState: Bool = {
            guard settingsModel.settings.showLyricsInLiveActivity else { return false }
            guard let activeBundleID = activeAppBundleID else { return true }
            if let isAllowed = settingsModel.settings.musicAppStates[activeBundleID] { return isAllowed }
            var isBrowser = false
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: activeBundleID),
               let bundle = Bundle(url: appURL),
               let urlTypes = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
                isBrowser = urlTypes.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("http") ?? false }
            }
            return !isBrowser
        }()
        if isLyricsAllowedForActiveApp != newPermissionState {
            isLyricsAllowedForActiveApp = newPermissionState
        }
    }

    // MARK: - AX Event Handling

    nonisolated func handleAXEvent(_ notification: CFString) {
        Task { @MainActor in
            let now = CACurrentMediaTime()

            if notification as String == kAXWindowMovedNotification as String {
                handleWindowMove(now: now)
            } else {
                handleFullScreenEvent(now: now)
            }
        }
    }

    private func handleFullScreenEvent(now: TimeInterval) {
        guard now - lastFullScreenRefreshTime >= fullScreenRefreshThrottle else { return }
        lastFullScreenRefreshTime = now

        guard let pid = observedPID,
              let app = NSRunningApplication(processIdentifier: pid),
              app.isFinishedLaunching && !app.isTerminated else { return }

        refreshFullScreenState(for: app)
    }

    // MARK: - AX Observer Setup

    private func setupAXObserver(for pid: pid_t) {
        teardownAXObserver()

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &observer)

        guard result == .success, let observer = observer else {
            print("[ActiveAppMonitor] Failed to create AXObserver for PID \(pid)")
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)

        AXObserverAddNotification(observer, appElement, kAXWindowResizedNotification as CFString, selfPtr)
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)

        if settingsModel.settings.snapOnWindowDragEnabled {
            AXObserverAddNotification(observer, appElement, kAXWindowMovedNotification as CFString, selfPtr)
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.axObserver = observer
        self.observedPID = pid
    }

    private func teardownAXObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            axObserver = nil
        }
        observedPID = nil

        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }

        if isWindowDragging {
            isWindowDragging = false
        }
    }

    // MARK: - Window Drag Detection

    private func handleWindowMove(now: TimeInterval) {
        if now - lastMoveTime < 0.016 { return }
        lastMoveTime = now

        guard NSEvent.pressedMouseButtons == 1 else { return }

        if !self.isWindowDragging {
            self.isWindowDragging = true
            self.startMouseUpMonitoring()
        }
    }

    private func startMouseUpMonitoring() {
        guard mouseUpMonitor == nil else { return }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.isWindowDragging = false
                if let monitor = self?.mouseUpMonitor {
                    NSEvent.removeMonitor(monitor)
                    self?.mouseUpMonitor = nil
                }
            }
        }
    }
}