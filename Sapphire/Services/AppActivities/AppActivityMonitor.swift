//
//  AppActivityMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28
//

import AppKit
import Combine

struct AppActivity: Identifiable, Equatable {
    let app: AppActivityApp
    var id: String { app.rawValue }
    var pid: pid_t
    var bundleID: String
    var title: String
    var subtitle: String?
    var startedAt: Date
    var states: [AppActivityControl: Bool] = [:]
    var controls: [AppActivityControl]
}

@MainActor
final class AppActivityMonitor: ObservableObject {
    static let shared = AppActivityMonitor()

    @Published private(set) var activities: [AppActivity] = []
    var primary: AppActivity? { activities.first }

    private let queue = DispatchQueue(label: "com.sapphire.app-activities", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var isRunning = false
    private var isEvaluating = false
    private var needsAnotherPass = false
    private var meetTabCache: [String: (tab: MeetTab?, at: Date)] = [:]

    struct MeetTab: Equatable { let browserBundleID: String; let title: String; let url: String }

    private var settingCancellable: AnyCancellable?

    private init() {}

    func bootstrap() {
        guard settingCancellable == nil else { return }
        settingCancellable = SettingsModel.shared.$settings
            .map(\.appActivitiesEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.start() } else { self?.stop() }
            }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        MicrophoneUsageManager.shared.$inputBundleIDs
            .removeDuplicates()
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.publisher(for: name)
                .sink { [weak self] _ in self?.evaluate() }
                .store(in: &cancellables)
        }
        SettingsModel.shared.$settings
            .map(\.appActivitiesDisabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
        evaluate()
    }

    func stop() {
        isRunning = false
        cancellables.removeAll()
        refreshTimer?.invalidate()
        refreshTimer = nil
        syncWindowObservers([])
        pendingWindowEvaluation?.cancel()
        pendingWindowEvaluation = nil
        activities = []
    }

    private func enabledApps() -> [AppActivityApp] {
        let disabled = SettingsModel.shared.current.appActivitiesDisabled
        return AppActivityApp.allCases.filter { !disabled.contains($0.rawValue) }
    }

    // MARK: - Evaluation

    func evaluate() {
        guard isRunning else { return }
        if isEvaluating { needsAnotherPass = true; return }
        isEvaluating = true

        let mic = MicrophoneUsageManager.shared.inputBundleIDs
        let apps = enabledApps()
        var candidates: [(AppActivityApp, pid_t, String, Bool)] = []
        for app in apps {
            let micActive = app.microphonePrefixes.contains { prefix in mic.contains { $0.hasPrefix(prefix) } }
            for bundleID in app.bundleIDs {
                guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
                if app == .googleMeet {
                    guard Self.browserIsRecording(bundleID, mic: mic) else { continue }
                }
                candidates.append((app, running.processIdentifier, bundleID, micActive))
                break
            }
        }
        let previous = Dictionary(uniqueKeysWithValues: activities.map { ($0.app, $0) })
        let meetCache = meetTabCache

        queue.async { [weak self] in
            var found: [AppActivity] = []
            var newMeetCache: [String: (tab: MeetTab?, at: Date)] = [:]
            for (app, pid, bundleID, micActive) in candidates {
                let windows = (app.windowHints.isEmpty && app != .screenSharing && app != .teams) ? [] : AX.windowTitles(pid: pid)
                let hintHit = !app.windowHints.isEmpty && windows.contains { title in
                    app.windowHints.contains { title.localizedCaseInsensitiveContains($0) }
                }
                var activity: AppActivity?
                switch app {
                case .zoom, .quickTime:
                    if micActive || hintHit {
                        let named = windows.first { title in app.windowHints.contains { title.localizedCaseInsensitiveContains($0) } }
                        activity = Self.make(app, pid, bundleID, title: app == .zoom ? "Zoom meeting" : (named ?? "Recording"),
                                             subtitle: nil, previous: previous[app])
                    }
                case .screenSharing:
                    let sessions = windows.filter { !$0.isEmpty && $0 != "Screen Sharing" }
                    if let first = sessions.first {
                        activity = Self.make(app, pid, bundleID, title: first,
                                             subtitle: sessions.count > 1 ? "+\(sessions.count - 1) more" : nil,
                                             previous: previous[app])
                    }
                case .googleMeet:
                    let cached = meetCache[bundleID]
                    let tab: MeetTab?
                    if let cached, Date().timeIntervalSince(cached.at) < 10 {
                        tab = cached.tab
                    } else {
                        tab = Self.findMeetTab(in: bundleID)
                    }
                    newMeetCache[bundleID] = (tab, cached.flatMap { Date().timeIntervalSince($0.at) < 10 ? $0.at : nil } ?? Date())
                    if micActive, let tab {
                        let code = URL(string: tab.url)?.lastPathComponent
                        let name = tab.title.replacingOccurrences(of: "Meet - ", with: "").replacingOccurrences(of: "Meet – ", with: "")
                        activity = Self.make(app, pid, bundleID, title: "Google Meet",
                                             subtitle: name.isEmpty || name == "Meet" ? code : name, previous: previous[app])
                    }
                case .teams:
                    if micActive {
                        let meeting = windows.first { !$0.isEmpty && $0 != "Microsoft Teams" }
                        activity = Self.make(app, pid, bundleID, title: "Teams call",
                                             subtitle: meeting?.components(separatedBy: " | ").first, previous: previous[app])
                    }
                default:
                    if micActive {
                        let title: String
                        switch app {
                        case .slack: title = "Huddle"
                        case .discord: title = "Voice channel"
                        case .faceTime: title = "FaceTime"
                        case .webex: title = "Webex meeting"
                        case .voiceMemos: title = "Recording"
                        default: title = app.displayName
                        }
                        activity = Self.make(app, pid, bundleID, title: title, subtitle: nil, previous: previous[app])
                    }
                }
                if var activity {
                    Self.readMenuState(into: &activity)
                    found.append(activity)
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for (key, value) in newMeetCache { self.meetTabCache[key] = value }
                    let ordered = found.sorted { $0.startedAt < $1.startedAt }
                    if ordered != self.activities { self.activities = ordered }
                    self.updateRefreshTimer()
                    self.isEvaluating = false
                    if self.needsAnotherPass {
                        self.needsAnotherPass = false
                        self.evaluate()
                    }
                }
            }
        }
    }

    nonisolated private static func make(_ app: AppActivityApp, _ pid: pid_t, _ bundleID: String,
                                         title: String, subtitle: String?, previous: AppActivity?) -> AppActivity {
        AppActivity(app: app, pid: pid, bundleID: bundleID, title: title, subtitle: subtitle,
                    startedAt: previous?.startedAt ?? Date(), states: previous?.states ?? [:],
                    controls: app.controls)
    }

    nonisolated private static func readMenuState(into activity: inout AppActivity) {
        let app = activity.app
        let needsMenu = app.controls.contains { if case .menu = app.action(for: $0) { return true }; return false }
        guard needsMenu else { return }
        let items = AX.menuItems(pid: activity.pid)
        let titles = Set(items.filter(\.isEnabled).map { $0.title.lowercased() })
        activity.controls = app.controls.filter { control in
            guard case .menu(let names)? = app.action(for: control) else { return true }
            return names.contains { titles.contains($0.lowercased()) }
        }
        for control in app.controls {
            guard let state = app.stateTitles(for: control) else { continue }
            if state.on.contains(where: { titles.contains($0.lowercased()) }) { activity.states[control] = true }
            else if state.off.contains(where: { titles.contains($0.lowercased()) }) { activity.states[control] = false }
        }
    }

    private func updateRefreshTimer() {
        let windowApps = enabledApps().filter { !$0.windowHints.isEmpty || $0 == .screenSharing }
        var watchedPIDs = Set<pid_t>()
        for app in windowApps {
            for bundleID in app.bundleIDs {
                for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                    watchedPIDs.insert(running.processIdentifier)
                }
            }
        }
        let isLive = !activities.isEmpty
        syncWindowObservers(isLive ? [] : watchedPIDs)

        let interval: TimeInterval? = isLive ? 2 : (watchedPIDs.isEmpty ? nil : Self.watchFallbackInterval)
        if let interval {
            guard refreshTimer?.timeInterval != interval else { return }
            refreshTimer?.invalidate()
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            timer.tolerance = interval * 0.25
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private static let watchFallbackInterval: TimeInterval = 30

    private var windowObservers: [pid_t: AXObserverHandle] = [:]
    private var pendingWindowEvaluation: DispatchWorkItem?

    private func syncWindowObservers(_ pids: Set<pid_t>) {
        for (pid, observer) in windowObservers where !pids.contains(pid) {
            observer.detach()
            windowObservers.removeValue(forKey: pid)
        }
        guard AccessibilityPermission.isProcessTrusted else { return }
        for pid in pids where windowObservers[pid] == nil {
            guard let observer = AXObserverHandle(pid: pid, handler: { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleWindowEvaluation() }
            }) else { continue }
            let count = observer.observe(
                [kAXWindowCreatedNotification as String, kAXTitleChangedNotification as String],
                on: AX.application(pid: pid)
            )
            guard count > 0 else { continue }
            observer.attach()
            windowObservers[pid] = observer
        }
    }

    private func scheduleWindowEvaluation() {
        guard pendingWindowEvaluation == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingWindowEvaluation = nil
                self?.evaluate()
            }
        }
        pendingWindowEvaluation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Google Meet (browser tabs)

    nonisolated private static func browserIsRecording(_ bundleID: String, mic: Set<String>) -> Bool {
        let prefix: String
        switch bundleID {
        case "com.apple.Safari": prefix = "com.apple.WebKit"
        case "company.thebrowser.Browser": prefix = "company.thebrowser"
        default: prefix = bundleID
        }
        return mic.contains { $0.hasPrefix(prefix) }
    }

    nonisolated private static func appName(for browser: String) -> String? {
        switch browser {
        case "com.google.Chrome": "Google Chrome"
        case "com.microsoft.edgemac": "Microsoft Edge"
        case "com.brave.Browser": "Brave Browser"
        case "company.thebrowser.Browser": "Arc"
        case "com.apple.Safari": "Safari"
        default: nil
        }
    }

    nonisolated private static func findMeetTab(in browser: String) -> MeetTab? {
        guard let name = appName(for: browser) else { return nil }
        let titleKey = browser == "com.apple.Safari" ? "name" : "title"
        let script = """
        tell application "\(name)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u starts with "https://meet.google.com/" and u is not "https://meet.google.com/" and u does not contain "/landing" then
                        return (\(titleKey) of t) & "||" & u
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        var error: NSDictionary?
        guard let result = AppleScriptRunner.execute(script, error: &error)?.stringValue,
              let separator = result.range(of: "||") else { return nil }
        return MeetTab(browserBundleID: browser,
                       title: String(result[..<separator.lowerBound]),
                       url: String(result[separator.upperBound...]))
    }

    nonisolated private static func meetTab(in browser: String, close: Bool) -> Bool {
        guard let name = appName(for: browser) else { return false }
        let select = browser == "com.apple.Safari"
            ? "set current tab of w to t"
            : "set active tab index of w to i"
        let act = close ? "close t" : "\(select)\n                        set index of w to 1\n                        activate"
        let script = """
        tell application "\(name)"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if URL of t starts with "https://meet.google.com/" and URL of t does not contain "/landing" then
                        \(act)
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        var error: NSDictionary?
        return AppleScriptRunner.execute(script, error: &error)?.stringValue == "ok"
    }

    // MARK: - Controls

    func perform(_ control: AppActivityControl, on activity: AppActivity) {
        guard let action = activity.app.action(for: control) else { return }
        let previousApp = NSWorkspace.shared.frontmostApplication
        let restore = SettingsModel.shared.current.appActivityRestoreFocus && control != .show && control != .leave
        switch action {
        case .menu(let names):
            let pid = activity.pid
            queue.async {
                let items = AX.menuItems(pid: pid)
                if let item = items.first(where: { item in item.isEnabled && names.contains { $0.caseInsensitiveCompare(item.title) == .orderedSame } }) {
                    AX.press(item)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        case .focus:
            bringForward(activity)
        case .closeTab:
            let browser = activity.bundleID
            queue.async { _ = Self.meetTab(in: browser, close: true) }
        case .shortcut(let key, let flags):
            bringForward(activity)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Self.postKey(key, flags: flags)
                if restore, let previousApp, previousApp.bundleIdentifier != activity.bundleID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { previousApp.activate() }
                }
            }
            if let known = activity.states[control], let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index].states[control] = !known
            }
        }
    }

    private func bringForward(_ activity: AppActivity) {
        if activity.app == .googleMeet {
            let browser = activity.bundleID
            queue.async { _ = Self.meetTab(in: browser, close: false) }
        } else {
            NSRunningApplication(processIdentifier: activity.pid)?.activate()
        }
    }

    nonisolated private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}