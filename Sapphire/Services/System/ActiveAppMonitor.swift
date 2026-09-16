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
private let fullScreenLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "FullScreenDetection")

extension Notification.Name {
    static let activeAppDidChange = Notification.Name("com.sapphire.activeAppDidChange")
}

@MainActor
final class WindowDragState: ObservableObject {
    static let shared = WindowDragState()
    @Published private(set) var isDragging = false
    @Published private(set) var isSnapZoneDismissedForCurrentDrag = false
    private init() {}

    func beginDrag() {
        isSnapZoneDismissedForCurrentDrag = false
        isDragging = true
    }

    func dismissSnapZonesForCurrentDrag() {
        guard isDragging else { return }
        isSnapZoneDismissedForCurrentDrag = true
    }

    func endDrag() {
        isDragging = false
        isSnapZoneDismissedForCurrentDrag = false
    }
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

    private let fullScreenQueue = DispatchQueue(label: "com.sapphire.fullscreen-detection", qos: .userInitiated)
    private var fullScreenGeneration = 0
    private var hasLoggedUntrustedAccessibility = false

    deinit {
        axObserver?.detach()
    }

    private init() {
        self.settingsModel = SettingsModel.shared

        let spaceChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).map { _ in "activeSpaceDidChange" }
        let appChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).map { _ in "didActivateApplication" }
        let screenChangePublisher = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in "didChangeScreenParameters" }

        Publishers.Merge3(spaceChangePublisher, appChangePublisher, screenChangePublisher)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] reason in self?.updateActiveAppState(reason: reason) }
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

        updateActiveAppState(reason: "launch")
    }

    private func updateActiveAppState(reason: String) {
        refreshFullScreenState(reason: reason)

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

    private func refreshFullScreenState(reason: String) {
        fullScreenGeneration += 1
        let generation = fullScreenGeneration
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let isAccessibilityTrusted = AXIsProcessTrusted()

        fullScreenQueue.async { [weak self] in
            let evaluation = FullScreenDetector.evaluate(ownPID: ownPID, isAccessibilityTrusted: isAccessibilityTrusted)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.fullScreenGeneration else { return }
                    self.applyFullScreenEvaluation(evaluation, reason: reason)
                }
            }
        }
    }

    private func applyFullScreenEvaluation(_ evaluation: FullScreenDetector.Evaluation, reason: String) {
        if !evaluation.isAccessibilityTrusted {
            if !hasLoggedUntrustedAccessibility {
                fullScreenLog.error("Accessibility is not trusted; AXFullScreen cannot be read, so no display is treated as full screen")
                hasLoggedUntrustedAccessibility = true
            }
        } else {
            hasLoggedUntrustedAccessibility = false
        }

        let summary = evaluation.displays.map(\.logDescription).joined(separator: "; ")
        fullScreenLog.info("Evaluated reason=\(reason, privacy: .public) displays=[\(summary, privacy: .public)]")

        guard fullScreenDisplayIDs != evaluation.displayIDs else { return }
        let previous = Self.describe(fullScreenDisplayIDs)
        let current = Self.describe(evaluation.displayIDs)
        fullScreenLog.notice("Full-screen displays changed [\(previous, privacy: .public)] -> [\(current, privacy: .public)] reason=\(reason, privacy: .public)")
        fullScreenDisplayIDs = evaluation.displayIDs
    }

    private static func describe(_ displayIDs: Set<CGDirectDisplayID>) -> String {
        displayIDs.sorted().map(String.init).joined(separator: ",")
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

        guard settingsModel.settings.snapOnWindowDragEnabled else { return }

        let observer = AXObserverHandle(pid: pid) { _, _ in
            ActiveAppMonitor.shared.handleWindowMoved()
        }
        guard let observer else {
            print("[ActiveAppMonitor] Failed to create AXObserver for PID \(pid)")
            return
        }

        observer.observe(kAXWindowMovedNotification as String, on: AX.application(pid: pid))
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
            windowDrag.endDrag()
        }
    }

    nonisolated func handleWindowMoved() {
        Task { @MainActor in
            let now = CACurrentMediaTime()
            if now - lastMoveTime < 0.016 { return }
            lastMoveTime = now

            guard NSEvent.pressedMouseButtons & 1 != 0 else { return }

            if !self.windowDrag.isDragging {
                self.windowDrag.beginDrag()
                self.startMouseUpMonitoring()
            }
        }
    }

    private func startMouseUpMonitoring() {
        guard mouseUpToken == nil else { return }

        mouseUpToken = EventMonitorHub.shared.register(for: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.windowDrag.endDrag()
                if let token = self.mouseUpToken {
                    EventMonitorHub.shared.unregister(token: token, for: .leftMouseUp)
                    self.mouseUpToken = nil
                }
            }
        }
    }
}

// MARK: - AXFullScreen per display

enum FullScreenDetector {
    struct DisplayResult {
        let displayID: CGDirectDisplayID
        let pid: pid_t?
        let appName: String?
        let isFullScreen: Bool
        let detail: String

        var logDescription: String {
            let app = pid.map { "\(appName ?? "?")(pid \($0))" } ?? "no app"
            return "display \(displayID): \(app) fullScreen=\(isFullScreen) \(detail)"
        }
    }

    struct Evaluation {
        let displayIDs: Set<CGDirectDisplayID>
        let displays: [DisplayResult]
        let isAccessibilityTrusted: Bool
    }

    private struct Display {
        let id: CGDirectDisplayID
        let bounds: CGRect
    }

    private struct FrontWindow {
        let pid: pid_t
        let appName: String?
        let bounds: CGRect
    }

    private struct AXWindowState {
        let frame: CGRect
        let isFullScreen: Bool
        let isMainWindow: Bool
    }

    nonisolated static func evaluate(ownPID: pid_t, isAccessibilityTrusted: Bool) -> Evaluation {
        let displays = activeDisplays()
        let windows = normalLevelWindows(excluding: ownPID)
        var windowsByPID: [pid_t: [AXWindowState]] = [:]
        var results: [DisplayResult] = []
        var fullScreenIDs = Set<CGDirectDisplayID>()

        for display in displays {
            guard let front = frontWindow(on: display, in: windows) else {
                results.append(DisplayResult(displayID: display.id, pid: nil, appName: nil, isFullScreen: false, detail: "(no app window on display)"))
                continue
            }
            guard isAccessibilityTrusted else {
                results.append(DisplayResult(displayID: display.id, pid: front.pid, appName: front.appName, isFullScreen: false, detail: "(accessibility not trusted)"))
                continue
            }

            let axWindows = windowsByPID[front.pid] ?? axWindowStates(pid: front.pid)
            windowsByPID[front.pid] = axWindows

            let onDisplay = axWindows.filter { display.bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            let fullScreenWindow = onDisplay.first { $0.isFullScreen }
            let isFullScreen = fullScreenWindow != nil
            let detail: String
            if let fullScreenWindow {
                detail = "(AXFullScreen on \(fullScreenWindow.isMainWindow ? "main window" : "window") frame=\(Int(fullScreenWindow.frame.width))x\(Int(fullScreenWindow.frame.height)))"
            } else if axWindows.isEmpty {
                detail = "(no AX windows readable)"
            } else {
                detail = "(\(onDisplay.count) AX window(s) on display, none AXFullScreen)"
            }
            if isFullScreen { fullScreenIDs.insert(display.id) }
            results.append(DisplayResult(displayID: display.id, pid: front.pid, appName: front.appName, isFullScreen: isFullScreen, detail: detail))
        }

        return Evaluation(displayIDs: fullScreenIDs, displays: results, isAccessibilityTrusted: isAccessibilityTrusted)
    }

    nonisolated private static func activeDisplays() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { Display(id: $0, bounds: CGDisplayBounds($0)) }
    }

    nonisolated private static func normalLevelWindows(excluding ownPID: pid_t) -> [FrontWindow] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownPID,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width > 1, bounds.height > 1 else {
                return nil
            }
            return FrontWindow(pid: pid, appName: info[kCGWindowOwnerName as String] as? String, bounds: bounds)
        }
    }

    nonisolated private static func frontWindow(on display: Display, in windows: [FrontWindow]) -> FrontWindow? {
        let displayArea = display.bounds.width * display.bounds.height
        guard displayArea > 0 else { return nil }
        return windows.first { window in
            let overlap = window.bounds.intersection(display.bounds)
            return !overlap.isNull && overlap.width * overlap.height >= displayArea * 0.1
        }
    }

    nonisolated private static func axWindowStates(pid: pid_t) -> [AXWindowState] {
        let application = AX.application(pid: pid)
        let mainWindow = AX.mainWindow(ofApplication: application)
        var elements = AX.elements(kAXWindowsAttribute as String, of: application, limit: 32)
        if let mainWindow, !elements.contains(where: { CFEqual($0, mainWindow) }) {
            elements.insert(mainWindow, at: 0)
        }
        return elements.compactMap { window in
            guard let frame = AX.windowFrame(of: window) else { return nil }
            return AXWindowState(
                frame: frame,
                isFullScreen: AX.bool("AXFullScreen", of: window) ?? false,
                isMainWindow: mainWindow.map { CFEqual($0, window) } ?? false
            )
        }
    }
}