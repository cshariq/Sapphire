//
//  RunningApps.swift
//  Sapphire
//
//  Cached snapshot of NSWorkspace.runningApplications, keyed by PID, so hot
//  paths (audio process reconciliation, "is this app currently running"
//  checks) don't repeatedly walk and allocate over the full running-app list.
//

import AppKit

final class RunningApps {
    static let shared = RunningApps()

    struct AppInfo {
        let bundleID: String?
        let isAppBundle: Bool
    }

    private var cachedInfoByPID: [pid_t: AppInfo] = [:]
    private var lastRefresh: Date = .distantPast
    private let refreshInterval: TimeInterval = 1.0
    private let lock = NSLock()

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { [weak self] _ in
            self?.invalidate()
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { [weak self] _ in
            self?.invalidate()
        }
    }

    /// Snapshot of running apps' info, keyed by process ID.
    func infoByPID() -> [pid_t: AppInfo] {
        lock.lock()
        defer { lock.unlock() }
        refreshIfNeeded()
        return cachedInfoByPID
    }

    /// True if any currently-running app's bundle ID satisfies `predicate`.
    func containsBundleID(where predicate: (String) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        refreshIfNeeded()
        return cachedInfoByPID.values.contains { info in
            guard let bundleID = info.bundleID else { return false }
            return predicate(bundleID)
        }
    }

    private func invalidate() {
        lock.lock()
        lastRefresh = .distantPast
        lock.unlock()
    }

    private func refreshIfNeeded() {
        guard Date().timeIntervalSince(lastRefresh) > refreshInterval else { return }
        var result: [pid_t: AppInfo] = [:]
        result.reserveCapacity(NSWorkspace.shared.runningApplications.count)
        for app in NSWorkspace.shared.runningApplications {
            result[app.processIdentifier] = AppInfo(bundleID: app.bundleIdentifier, isAppBundle: true)
        }
        cachedInfoByPID = result
        lastRefresh = Date()
    }
}
