//
//  ActiveAppMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-09.
//

import AppKit
import Combine
import ApplicationServices
import os.log

private let activeAppLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "ActiveAppMonitor")

extension Notification.Name {
    static let activeAppDidChange = Notification.Name("com.sapphire.activeAppDidChange")
}

@MainActor
final class WindowDragState: ObservableObject {
    static let shared = WindowDragState()
    @Published fileprivate(set) var isDragging = false
    private init() {}
}

@MainActor
class ActiveAppMonitor: ObservableObject {

    static let shared = ActiveAppMonitor()

    @Published private(set) var isLyricsAllowedForActiveApp: Bool = true
    @Published private(set) var activeAppBundleID: String?
    @Published private(set) var isFullScreen: Bool = false
    @Published private(set) var fullScreenDisplayIDs: Set<CGDirectDisplayID> = [] {
        didSet {
            let anyDisplayIsFullScreen = !fullScreenDisplayIDs.isEmpty
            if isFullScreen != anyDisplayIsFullScreen {
                isFullScreen = anyDisplayIsFullScreen
            }
        }
    }
    private let windowDrag = WindowDragState.shared

    private let settingsModel: SettingsModel
    private var cancellables = Set<AnyCancellable>()

    private var axObserver: AXObserverHandle?
    private var observedPID: pid_t?
    private var mouseUpToken: UUID?
    private var lastMoveTime: TimeInterval = 0

    deinit {
        axObserver?.detach()
    }

    private init() {
        self.settingsModel = SettingsModel.shared

        let spaceChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).map { _ in () }
        let appChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).map { _ in () }
        let screenChangePublisher = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in () }

        Publishers.Merge3(spaceChangePublisher, appChangePublisher, screenChangePublisher)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveAppState() }
            .store(in: &cancellables)

        FullScreenDisplayMonitor.shared.$displayIDs
            .removeDuplicates()
            .sink { [weak self] displayIDs in self?.fullScreenDisplayIDs = displayIDs }
            .store(in: &cancellables)

        $activeAppBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLyricPermission() }
            .store(in: &cancellables)

        settingsModel.$settings
            .map { (settings: Settings) -> [String: Bool]? in
                settings.showLyricsInLiveActivity ? settings.musicAppStates : nil
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLyricPermission() }
            .store(in: &cancellables)

        settingsModel.$settings
            .map(\.snapOnWindowDragEnabled)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshWindowDragObservation() }
            .store(in: &cancellables)

        updateActiveAppState()
    }

    private func updateActiveAppState() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication, let bundleID = frontmostApp.bundleIdentifier else {
            if activeAppBundleID != nil { activeAppBundleID = nil }
            teardownAXObserver()
            return
        }
        guard bundleID != Bundle.main.bundleIdentifier else {
            return
        }

        if activeAppBundleID != bundleID || observedPID != frontmostApp.processIdentifier {
            activeAppBundleID = bundleID
            NotificationCenter.default.post(name: .activeAppDidChange, object: nil)

            setupAXObserver(for: frontmostApp.processIdentifier)
        }
    }

    func isScreenFullScreen(_ screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return fullScreenDisplayIDs.contains(screen.displayID)
    }

    private func updateLyricPermission() {
        let newPermissionState: Bool = {
            guard settingsModel.settings.showLyricsInLiveActivity else { return false }
            guard let activeBundleID = activeAppBundleID else { return true }
            if let isAllowed = settingsModel.settings.musicAppStates[activeBundleID] { return isAllowed }
            return !isBrowser(activeBundleID)
        }()
        if isLyricsAllowedForActiveApp != newPermissionState {
            isLyricsAllowedForActiveApp = newPermissionState
        }
    }

    private var browserBundleIDs: [String: Bool] = [:]

    private func isBrowser(_ bundleID: String) -> Bool {
        if let cached = browserBundleIDs[bundleID] { return cached }
        var isBrowser = false
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: appURL),
           let urlTypes = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
            isBrowser = urlTypes.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("http") ?? false }
        }
        browserBundleIDs[bundleID] = isBrowser
        return isBrowser
    }

    // MARK: - Window Drag Detection

    private func refreshWindowDragObservation() {
        let workspace = NSWorkspace.shared
        let frontmost = workspace.frontmostApplication.flatMap { application in
            application.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : application
        }
        let lastExternalApplication = activeAppBundleID.flatMap { bundleID in
            workspace.runningApplications.first { $0.bundleIdentifier == bundleID }
        }
        guard let application = frontmost ?? lastExternalApplication else {
            teardownAXObserver()
            return
        }
        setupAXObserver(for: application.processIdentifier)
    }

    private func setupAXObserver(for pid: pid_t) {
        teardownAXObserver()
        observedPID = pid

        let observer = AXObserverHandle(pid: pid) { _, notification in
            ActiveAppMonitor.shared.handleAXEvent(notification)
        }
        guard let observer else {
            print("[ActiveAppMonitor] Failed to create AXObserver for PID \(pid)")
            return
        }

        let appElement = AX.application(pid: pid)
        observer.observe([
            kAXWindowCreatedNotification as String,
            kAXWindowResizedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            kAXFocusedWindowChangedNotification as String
        ], on: appElement)
        if settingsModel.settings.snapOnWindowDragEnabled {
            observer.observe(kAXWindowMovedNotification as String, on: appElement)
        }
        observer.attach()
        self.axObserver = observer
    }

    private func teardownAXObserver() {
        axObserver?.detach()
        axObserver = nil
        observedPID = nil

        if let token = mouseUpToken {
            EventMonitorHub.shared.unregister(token: token, for: .leftMouseUp)
            mouseUpToken = nil
        }

        if windowDrag.isDragging {
            windowDrag.isDragging = false
        }
    }

    nonisolated func handleAXEvent(_ notification: String) {
        Task { @MainActor in
            guard notification == kAXWindowMovedNotification as String else {
                FullScreenDisplayMonitor.shared.setNeedsRefresh()
                return
            }

            let now = CACurrentMediaTime()
            if now - lastMoveTime < 0.016 { return }
            lastMoveTime = now

            guard NSEvent.pressedMouseButtons & 1 != 0 else { return }

            if !self.windowDrag.isDragging {
                self.windowDrag.isDragging = true
                self.startMouseUpMonitoring()
            }
        }
    }

    private func startMouseUpMonitoring() {
        guard mouseUpToken == nil else { return }

        mouseUpToken = EventMonitorHub.shared.register(for: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.windowDrag.isDragging = false
                if let token = self.mouseUpToken {
                    EventMonitorHub.shared.unregister(token: token, for: .leftMouseUp)
                    self.mouseUpToken = nil
                }
            }
        }
    }
}