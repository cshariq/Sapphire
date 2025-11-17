//
//  XPCClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-26

import Foundation

class XPCClient {

    static let shared = XPCClient()

    var connection: NSXPCConnection?

    var helper: HelperProtocol? {
        return self.connection?.remoteObjectProxyWithErrorHandler { error in
            NSLog("[XPCClient] Connection Error: \(error)")
            self.connection = nil
        } as? HelperProtocol
    }

    private init() {}

    func start() {
        guard self.connection == nil else {
            return
        }

        let newConnection = NSXPCConnection(machServiceName: "com.shariq.sapphireHelper", options: .privileged)

        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            NSLog("[XPCClient] Connection invalidated")
            self?.connection = nil
        }

        newConnection.interruptionHandler = { [weak self] in
            NSLog("[XPCClient] Connection interrupted")
            self?.connection = nil
        }

        self.connection = newConnection
        self.connection?.resume()
    }

    func stop() {
        self.connection?.invalidate()
        self.connection = nil
    }
}