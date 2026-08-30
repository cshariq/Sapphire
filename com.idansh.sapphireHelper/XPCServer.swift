//
//  XPCServer.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02
//

import Foundation

class XPCServer: NSObject {

    internal static let shared = XPCServer()
    private var listener: NSXPCListener?
    private let helper = Helper()

    internal func start() {
        guard listener == nil else { return }

        let newListener = NSXPCListener(machServiceName: Constant.helperMachLabel)
        newListener.delegate = self
        listener = newListener
        newListener.resume()
        NSLog("[SMJBS]: XPC listener resumed for \(Constant.helperMachLabel)")
    }

    private func connectionInterruptionHandler(_ connection: NSXPCConnection) {
        NSLog("[SMJBS]: Client connection interrupted (pid=\(connection.processIdentifier)).")
    }

    private func connectionInvalidationHandler(_ connection: NSXPCConnection) {
        NSLog("[SMJBS]: Client connection invalidated (pid=\(connection.processIdentifier)).")
    }

    private func isValidClient(forConnection connection: NSXPCConnection) -> Bool {
        do {
            return try CodesignCheck.codeSigningMatches(pid: connection.processIdentifier)
        } catch {
            NSLog("[SMJBS]: Code signing check failed with error: \(error)")
            return false
        }
    }
}

extension XPCServer: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        NSLog("[SMJBS]: New connection received. Validating client...")

        if (!isValidClient(forConnection: newConnection)) {
            NSLog("[SMJBS]: Client is NOT valid. Rejecting connection.")
            return false
        }

        NSLog("[SMJBS]: Client is valid. Accepting connection.")

        let interface = NSXPCInterface(with: HelperProtocol.self)
        interface.setClasses(
            NSSet(array: [FanInfo.self, NSNull.self]) as! Set<AnyHashable>,
            for: #selector(HelperProtocol.getFanInfo(fanIndex:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        newConnection.exportedInterface = interface
        newConnection.exportedObject = helper

        newConnection.remoteObjectInterface = NSXPCInterface(with: InstallationClient.self)

        newConnection.interruptionHandler = { [weak self, weak newConnection] in
            guard let newConnection else { return }
            self?.connectionInterruptionHandler(newConnection)
        }
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let newConnection else { return }
            self?.connectionInvalidationHandler(newConnection)
        }

        newConnection.resume()

        helper.client = newConnection.remoteObjectProxy as? InstallationClient

        return true
    }
}