//
//  RunningApps.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import AppKit

final class RunningApps: @unchecked Sendable {
    static let shared = RunningApps()

    private let lock = NSLock()
    private var bundleIDs: [String] = []
    private var bundleIDSet: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        reload()

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.reload() },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.reload() }
        ]
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }

    func isRunning(_ bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return bundleIDSet.contains(bundleID)
    }

    func containsBundleID(where predicate: (String) -> Bool) -> Bool {
        lock.lock()
        let snapshot = bundleIDs
        lock.unlock()
        return snapshot.contains(where: predicate)
    }

    struct AppInfo {
        let bundleID: String?
        let isAppBundle: Bool
    }

    func infoByPID() -> [pid_t: AppInfo] {
        lock.lock()
        defer { lock.unlock() }
        return infoByPIDCache
    }

    private var infoByPIDCache: [pid_t: AppInfo] = [:]

    private func reload() {
        let apps = NSWorkspace.shared.runningApplications
        let ids = apps.compactMap(\.bundleIdentifier)
        var byPID: [pid_t: AppInfo] = [:]
        byPID.reserveCapacity(apps.count)
        for app in apps {
            byPID[app.processIdentifier] = AppInfo(
                bundleID: app.bundleIdentifier,
                isAppBundle: app.bundleURL?.pathExtension == "app"
            )
        }
        lock.lock()
        bundleIDs = ids
        bundleIDSet = Set(ids)
        infoByPIDCache = byPID
        lock.unlock()
    }
}