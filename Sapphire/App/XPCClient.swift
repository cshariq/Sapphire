//
//  XPCClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-26

import Foundation

final class XPCClient {
    static let shared = XPCClient()

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var failureNotificationSent = false
    private var lastForcedReconnect = Date.distantPast
    private let forcedReconnectInterval: TimeInterval = 1
    private let machServiceName = "com.idansh.sapphireHelper"

    private init() {}

    func proxy(onError: ((Error) -> Void)? = nil) -> HelperProtocol? {
        start()

        lock.lock()
        let currentConnection = connection
        lock.unlock()
        guard let currentConnection else { return nil }

        return currentConnection.remoteObjectProxyWithErrorHandler { [weak self, weak currentConnection] error in
            if let currentConnection {
                self?.handleConnectionFailure(currentConnection)
            }
            onError?(error)
        } as? HelperProtocol
    }

    var helper: HelperProtocol? {
        proxy()
    }

    func start(force: Bool = false) {
        var oldConnection: NSXPCConnection?
        var newConnection: NSXPCConnection?

        lock.lock()
        if force {
            oldConnection = connection
            if let oldConnection {
                oldConnection.invalidationHandler = nil
                oldConnection.interruptionHandler = nil
            }
            connection = nil
        }

        if connection == nil {
            let candidate = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
            candidate.remoteObjectInterface = makeRemoteInterface()
            installHandlers(on: candidate)
            connection = candidate
            newConnection = candidate
        }
        lock.unlock()

        oldConnection?.invalidate()
        newConnection?.resume()
    }

    func stop() {
        lock.lock()
        let existing = connection
        if let existing {
            existing.invalidationHandler = nil
            existing.interruptionHandler = nil
        }
        connection = nil
        failureNotificationSent = false
        lock.unlock()

        existing?.invalidate()
    }

    func ping(timeout: TimeInterval = 5) async -> Bool {
        if await pingOnce(timeout: timeout, forceReconnect: false) {
            return true
        }
        forceReconnectIfAllowed()
        return await pingOnce(timeout: timeout, forceReconnect: false)
    }

    func helperProtocolVersion(timeout: TimeInterval = 2) async -> Int? {
        await withCheckedContinuation { continuation in
            let stateLock = NSLock()
            var resumed = false

            func resumeOnce(_ value: Int?) {
                stateLock.lock()
                guard !resumed else {
                    stateLock.unlock()
                    return
                }
                resumed = true
                stateLock.unlock()
                continuation.resume(returning: value)
            }

            guard let helper = proxy() else {
                resumeOnce(nil)
                return
            }

            helper.getProtocolVersion { version in
                resumeOnce(version)
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                resumeOnce(nil)
            }
        }
    }

    private func pingOnce(timeout: TimeInterval, forceReconnect: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let stateLock = NSLock()
            var resumed = false

            func resumeOnce(_ value: Bool) {
                stateLock.lock()
                guard !resumed else {
                    stateLock.unlock()
                    return
                }
                resumed = true
                stateLock.unlock()
                continuation.resume(returning: value)
            }

            start(force: forceReconnect)
            guard let helper = proxy() else {
                resumeOnce(false)
                return
            }

            helper.getVersion { [weak self] _ in
                self?.noteSuccessfulHandshake()
                resumeOnce(true)
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                resumeOnce(false)
            }
        }
    }

    private func forceReconnectIfAllowed() {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastForcedReconnect) >= forcedReconnectInterval else {
            lock.unlock()
            return
        }
        lastForcedReconnect = now
        lock.unlock()
        start(force: true)
    }

    private func makeRemoteInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: HelperProtocol.self)
        interface.setClasses(
            NSSet(array: [FanInfo.self, NSNull.self]) as! Set<AnyHashable>,
            for: #selector(HelperProtocol.getFanInfo(fanIndex:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        return interface
    }

    private func installHandlers(on connection: NSXPCConnection) {
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let connection else { return }
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            self?.detach(connection, notifyLost: true)
            connection.invalidate()
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let connection else { return }
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            self?.detach(connection, notifyLost: true)
        }
    }

    private func noteSuccessfulHandshake() {
        var shouldNotify = false
        lock.lock()
        if failureNotificationSent {
            failureNotificationSent = false
            shouldNotify = true
        }
        lock.unlock()
        if shouldNotify {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sapphireHelperConnectionRestored, object: nil)
            }
        }
    }

    private func detach(_ failedConnection: NSXPCConnection, notifyLost: Bool) {
        var shouldNotify = false

        lock.lock()
        if connection === failedConnection {
            connection = nil
            if notifyLost, !failureNotificationSent {
                failureNotificationSent = true
                shouldNotify = true
            }
        }
        lock.unlock()

        if shouldNotify {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sapphireHelperConnectionLost, object: nil)
            }
        }
    }

    private func handleConnectionFailure(_ failedConnection: NSXPCConnection) {
        failedConnection.invalidationHandler = nil
        failedConnection.interruptionHandler = nil
        detach(failedConnection, notifyLost: true)
        failedConnection.invalidate()
    }
}