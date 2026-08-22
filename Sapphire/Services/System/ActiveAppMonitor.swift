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
    monitor.handleWindowMoved()
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

    private let settingsModel: SettingsModel
    private var cancellables = Set<AnyCancellable>()

    private let kAXMainWindowAttribute = "AXMainWindow" as CFString
    private let kAXFullScreenAttribute = "AXFullScreen" as CFString
    private let kAXWindowsAttribute = "AXWindows" as CFString
    private let kAXWindowNumberAttribute = "AXWindowNumber" as CFString
    private let kAXPositionAttribute = "AXPosition" as CFString
    private let kAXSizeAttribute = "AXSize" as CFString

    private var fullScreenWindows: [CGWindowID: (pid: pid_t, displayID: CGDirectDisplayID)] = [:]

    private var axObserver: AXObserver?
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
                self.fullScreenWindows.removeAll()
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

        updateActiveAppState()
    }

    private func updateActiveAppState() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication, let bundleID = frontmostApp.bundleIdentifier else {
            if isFullScreen != false { isFullScreen = false }
            if !fullScreenDisplayIDs.isEmpty { fullScreenDisplayIDs = [] }
            fullScreenWindows.removeAll()
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
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var currentFullScreenWindows: [CGWindowID: (pid: pid_t, displayID: CGDirectDisplayID)] = [:]

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        if result == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                guard let windowNumber = windowNumber(of: window) else { continue }
                if let displayID = fullScreenDisplayID(for: window) {
                    currentFullScreenWindows[windowNumber] = (app.processIdentifier, displayID)
                }
            }
        } else if let window = mainWindow(of: appElement), let windowNumber = windowNumber(of: window),
                  let displayID = fullScreenDisplayID(for: window) {
            currentFullScreenWindows[windowNumber] = (app.processIdentifier, displayID)
        }

        fullScreenWindows = currentFullScreenWindows

        let displayIDs = Set(currentFullScreenWindows.values.map { $0.displayID })
        if fullScreenDisplayIDs != displayIDs {
            fullScreenDisplayIDs = displayIDs
        }
    }

    private func mainWindow(of appElement: AXUIElement) -> AXUIElement? {
        var window: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute, &window)
        return window as! AXUIElement?
    }

    private func windowNumber(of window: AXUIElement) -> CGWindowID? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXWindowNumberAttribute as CFString, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }
        return CGWindowID(number.uint32Value)
    }

    private func windowFrame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private func fullScreenDisplayID(for window: AXUIElement) -> CGDirectDisplayID? {
        var isFullScreenValue: AnyObject?
        let isAXFullScreen = AXUIElementCopyAttributeValue(window, kAXFullScreenAttribute as CFString, &isFullScreenValue) == .success
            && (isFullScreenValue as? NSNumber)?.boolValue == true

        guard let frame = windowFrame(of: window) else { return nil }
        if isAXFullScreen {
            if let displayID = NSScreen.screens.first(where: { $0.frame.contains(frame.origin) })?.displayID {
                return displayID
            }
        }
        return displayID(fullyCoveredBy: frame)
    }

    private func displayID(fullyCoveredBy frame: CGRect) -> CGDirectDisplayID? {
        NSScreen.screens.first { screen in
            let intersection = frame.intersection(screen.frame)
            return intersection.width >= screen.frame.width * 0.99
                && intersection.height >= screen.frame.height * 0.99
        }?.displayID
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

    // MARK: - Window Drag Detection

    private func setupAXObserver(for pid: pid_t) {
        teardownAXObserver()

        guard settingsModel.settings.snapOnWindowDragEnabled else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &observer)

        guard result == .success, let observer = observer else {
            print("[ActiveAppMonitor] Failed to create AXObserver for PID \(pid)")
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AXObserverAddNotification(observer, AXUIElementCreateApplication(pid), kAXWindowMovedNotification as CFString, selfPtr)

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.axObserver = observer
    }

    private func teardownAXObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            axObserver = nil
        }

        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }

        if isWindowDragging {
            isWindowDragging = false
        }
    }

    nonisolated func handleWindowMoved() {
        Task { @MainActor in
            let now = CACurrentMediaTime()
            if now - lastMoveTime < 0.016 { return }
            lastMoveTime = now

            guard NSEvent.pressedMouseButtons == 1 else { return }

            if !self.isWindowDragging {
                self.isWindowDragging = true
                self.startMouseUpMonitoring()
            }
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