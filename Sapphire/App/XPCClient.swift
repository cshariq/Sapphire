//
//  XPCClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-26

import Foundation

class XPCClient {

    static let shared = XPCClient()

    private let lock = NSLock()
    private var connection: NSXPCConnection?

    var helper: HelperProtocol? {
        lock.lock()
        let connection = self.connection
        lock.unlock()
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("[XPCClient] Connection Error: \(error)")
        } as? HelperProtocol
    }

    private init() {}

    func start(force: Bool = false) {
        lock.lock()
        defer { lock.unlock() }

        if force, let existing = connection {
            existing.invalidationHandler = nil
            existing.interruptionHandler = nil
            existing.invalidate()
            connection = nil
        }

        guard connection == nil else { return }

        let newConnection = NSXPCConnection(machServiceName: "com.shariq.sapphireHelper", options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            NSLog("[XPCClient] Connection invalidated")
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }
        newConnection.interruptionHandler = { [weak self] in
            NSLog("[XPCClient] Connection interrupted")
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }

        connection = newConnection
        newConnection.resume()
    }

    func stop() {
        lock.lock()
        let existing = connection
        existing?.invalidationHandler = nil
        existing?.interruptionHandler = nil
        connection = nil
        lock.unlock()
        existing?.invalidate()
    }

    func ping(timeout: TimeInterval = 5) async -> Bool {
        if await pingOnce(timeout: timeout, forceReconnect: false) {
            return true
        }
        return await pingOnce(timeout: timeout, forceReconnect: true)
    }

    private func pingOnce(timeout: TimeInterval, forceReconnect: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            func resumeOnce(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            start(force: forceReconnect)
            guard let helper else {
                resumeOnce(false)
                return
            }

            helper.getVersion { _ in
                resumeOnce(true)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce(false)
            }
        }
    }
}
