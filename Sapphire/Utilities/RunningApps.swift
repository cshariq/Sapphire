//
//  RunningApps.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import AppKit

@MainActor
private final class RunningApplicationTerminationWaiter {
    private let application: NSRunningApplication
    private var observer: NSObjectProtocol?
    private var timeoutWorkItem: DispatchWorkItem?
    private var continuation: CheckedContinuation<Bool, Never>?

    init(application: NSRunningApplication) {
        self.application = application
    }

    func terminateAndWait(timeout: TimeInterval) async -> Bool {
        guard !application.isTerminated else { return true }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let processIdentifier = application.processIdentifier
            let center = NSWorkspace.shared.notificationCenter

            observer = center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let terminatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                      terminatedApplication.processIdentifier == processIdentifier else { return }
                MainActor.assumeIsolated {
                    self?.finish(didTerminate: true)
                }
            }

            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finish(didTerminate: self.application.isTerminated)
                }
            }
            self.timeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            application.terminate()
            if application.isTerminated {
                finish(didTerminate: true)
            }
        }
    }

    private func finish(didTerminate: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        continuation.resume(returning: didTerminate)
    }
}

@MainActor
extension NSRunningApplication {
    func sapphireTerminateAndWait(timeout: TimeInterval) async -> Bool {
        await RunningApplicationTerminationWaiter(application: self)
            .terminateAndWait(timeout: timeout)
    }
}

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