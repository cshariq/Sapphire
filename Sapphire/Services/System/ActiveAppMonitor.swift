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
    @Published private(set) var isWindowDragging: Bool = false

    private let settingsModel: SettingsModel
    private var cancellables = Set<AnyCancellable>()

    private let kAXMainWindowAttribute = "AXMainWindow" as CFString
    private let kAXFullScreenAttribute = "AXFullScreen" as CFString

    private var axObserver: AXObserver?
    private var mouseUpMonitor: Any?
    private var lastMoveTime: TimeInterval = 0

    private init() {
        self.settingsModel = SettingsModel.shared

        let spaceChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).map { _ in () }
        let appChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).map { _ in () }

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

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var window: AnyObject?

        AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute, &window)

        var isCurrentlyFullScreen = false
        if let window = window {
            let windowElement = window as! AXUIElement
            var isFullScreenValue: AnyObject?

            let result = AXUIElementCopyAttributeValue(windowElement, kAXFullScreenAttribute, &isFullScreenValue)

            if result == .success, let isFullScreenNumber = isFullScreenValue as? NSNumber {
                isCurrentlyFullScreen = isFullScreenNumber.boolValue
            }
        }

        if self.isFullScreen != isCurrentlyFullScreen {
            self.isFullScreen = isCurrentlyFullScreen
        }
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