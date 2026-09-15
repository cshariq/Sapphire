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
    private var lastFullScreenRefreshTime: TimeInterval = 0
    private let fullScreenRefreshThrottle: TimeInterval = 0.3
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
        refreshFullScreenState()

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

    // MARK: - Full Screen Detection

    private func refreshFullScreenState() {
        let nativeSpaceIDs = fullScreenDisplayIDsFromManagedSpaces() ?? []
        let borderlessWindowIDs = fullScreenDisplayIDsFromOnScreenWindows()
        let displayIDs = nativeSpaceIDs.union(borderlessWindowIDs)

        guard fullScreenDisplayIDs != displayIDs else { return }
        let ids = displayIDs.sorted().map(String.init).joined(separator: ",")
        activeAppLog.info("WindowServer full-screen displays changed: displayIDs=[\(ids)]")
        fullScreenDisplayIDs = displayIDs
    }

    private func fullScreenDisplayIDsFromManagedSpaces() -> Set<CGDirectDisplayID>? {
        let connection = CGSMainConnectionID()
        guard connection != 0,
              let displayEntries = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]],
              !displayEntries.isEmpty else {
            return nil
        }

        var entriesByIdentifier: [String: [String: Any]] = [:]
        for entry in displayEntries {
            if let identifier = entry["Display Identifier"] as? String {
                entriesByIdentifier[identifier.uppercased()] = entry
            }
        }

        var matchedDisplayCount = 0
        var displayIDs = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            let identifier = screen.cgsDisplayIdentifier?.uppercased()
            let entry = identifier.flatMap { entriesByIdentifier[$0] }
                ?? (screen.displayID == CGMainDisplayID() ? entriesByIdentifier["MAIN"] : nil)
            guard let entry,
                  let currentSpace = currentSpace(in: entry),
                  let type = integerValue(currentSpace["type"]) else {
                continue
            }

            matchedDisplayCount += 1
            if type == Int(CGSSpaceType.fullscreen.rawValue) {
                displayIDs.insert(screen.displayID)
            }
        }

        return matchedDisplayCount > 0 ? displayIDs : nil
    }

    private func currentSpace(in displayEntry: [String: Any]) -> [String: Any]? {
        if let current = displayEntry["Current Space"] as? [String: Any] {
            return current
        }
        return (displayEntry["Spaces"] as? [[String: Any]])?.first {
            ($0["is-current"] as? Bool) == true
        }
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private func fullScreenDisplayIDsFromOnScreenWindows() -> Set<CGDirectDisplayID> {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidateFrames: [CGRect] = windowList.compactMap { info in
            guard integerValue(info[kCGWindowLayer as String]) == 0,
                  integerValue(info[kCGWindowOwnerPID as String]) != Int(ownPID),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width > 0, bounds.height > 0 else {
                return nil
            }
            return bounds
        }

        return Set(NSScreen.screens.compactMap { screen in
            let displayBounds = CGDisplayBounds(screen.displayID)
            let isCovered = candidateFrames.contains { frame in
                let intersection = frame.intersection(displayBounds)
                return !intersection.isNull
                    && intersection.width >= displayBounds.width * 0.99
                    && intersection.height >= displayBounds.height * 0.99
            }
            return isCovered ? screen.displayID : nil
        })
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
            kAXWindowResizedNotification as String,
            kAXFocusedUIElementChangedNotification as String
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
            let now = CACurrentMediaTime()

            if notification != kAXWindowMovedNotification as String {
                guard now - lastFullScreenRefreshTime >= fullScreenRefreshThrottle else { return }
                lastFullScreenRefreshTime = now
                refreshFullScreenState()
                return
            }

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