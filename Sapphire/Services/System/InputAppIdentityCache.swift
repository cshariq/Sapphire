//
//  InputAppIdentityCache.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import AppKit

/// pid → app identity and the frontmost pid, readable from any thread without
/// LaunchServices. Event-tap handlers used `NSWorkspace.frontmostApplication` and
/// `NSRunningApplication` getters per event; after any activation those are a
/// synchronous LaunchServices XPC each (see nsrunningapplication-ls-fetch).
/// Identities are captured once, from the workspace notifications' own instances.
final class InputAppIdentityCache: @unchecked Sendable {
    static let shared = InputAppIdentityCache()

    struct Identity: Equatable {
        let bundleID: String?
        let name: String?
    }

    private let lock = NSLock()
    private var identities: [pid_t: Identity] = [:]
    private var frontmostPID: pid_t = 0
    private var pendingLookups: Set<pid_t> = []
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    /// The instance from the latest activation notification. Its LaunchServices-backed
    /// properties are already fetched, so reads are free; `NSWorkspace.frontmostApplication`
    /// returns a fresh instance whose first `bundleIdentifier`/`processIdentifier` read is
    /// another LaunchServices round trip (~2 ms each in this process).
    @MainActor private var activatedApplication: NSRunningApplication?

    let ownPID = getpid()

    private init() {}

    /// Idempotent, callable from any thread. Seeds from the running apps off main.
    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start() }
            return
        }
        MainActor.assumeIsolated { startOnMain() }
    }

    @MainActor
    private func startOnMain() {
        guard !isStarted else { return }
        isStarted = true

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.record(app, activated: true) }
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.record(app, activated: false) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated {
                    if self?.activatedApplication?.processIdentifier == pid { self?.activatedApplication = nil }
                }
                self?.forget(pid)
            },
        ]

        if let front = NSWorkspace.shared.frontmostApplication {
            record(front, activated: true)
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let apps = NSWorkspace.shared.runningApplications
            var seeded: [pid_t: Identity] = [:]
            for app in apps {
                seeded[app.processIdentifier] = Identity(bundleID: app.bundleIdentifier, name: app.localizedName)
            }
            guard let self else { return }
            self.lock.lock()
            for (pid, identity) in seeded where self.identities[pid] == nil {
                self.identities[pid] = identity
            }
            self.lock.unlock()
        }
    }

    // MARK: - Reads (any thread)

    var frontmost: (pid: pid_t, identity: Identity?) {
        lock.lock()
        defer { lock.unlock() }
        return (frontmostPID, identities[frontmostPID])
    }

    var frontmostBundleID: String? {
        frontmost.identity?.bundleID
    }

    /// Main-thread stand-in for `NSWorkspace.shared.frontmostApplication` that reuses the
    /// activation notification's instance. Synchronous observers of the same activation
    /// notification may run before this cache records it, so they should read the
    /// notification's own instance instead.
    @MainActor
    var frontmostApplication: NSRunningApplication? {
        activatedApplication ?? NSWorkspace.shared.frontmostApplication
    }

    /// The bundle ID for `pid`, or nil if unknown yet. A miss schedules a one-off
    /// lookup on main, so the next event for that app resolves.
    func bundleID(forPID pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        lock.lock()
        if let identity = identities[pid] {
            lock.unlock()
            return identity.bundleID
        }
        let shouldLookUp = pendingLookups.insert(pid).inserted
        lock.unlock()

        if shouldLookUp {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let identity = NSRunningApplication(processIdentifier: pid).map {
                    Identity(bundleID: $0.bundleIdentifier, name: $0.localizedName)
                }
                self.lock.lock()
                self.pendingLookups.remove(pid)
                if let identity, self.identities[pid] == nil { self.identities[pid] = identity }
                self.lock.unlock()
            }
        }
        return nil
    }

    // MARK: - Updates (main)

    @MainActor
    private func record(_ app: NSRunningApplication, activated: Bool) {
        if activated { activatedApplication = app }
        let pid = app.processIdentifier
        let identity = Identity(bundleID: app.bundleIdentifier, name: app.localizedName)
        lock.lock()
        identities[pid] = identity
        if activated { frontmostPID = pid }
        lock.unlock()
    }

    private func forget(_ pid: pid_t) {
        lock.lock()
        identities.removeValue(forKey: pid)
        if frontmostPID == pid { frontmostPID = 0 }
        lock.unlock()
    }
}
