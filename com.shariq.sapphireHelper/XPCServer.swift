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

    internal func start() {
        listener = NSXPCListener(machServiceName: Constant.helperMachLabel)
        listener?.delegate = self
        listener?.resume()
    }

    private func connetionInterruptionHandler() {
        NSLog("[SMJBS]: Connection interrupted.")
    }

    private func connectionInvalidationHandler() {
        NSLog("[SMJBS]: Connection invalidated.")
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

        let helper = Helper()

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = helper

        newConnection.remoteObjectInterface = NSXPCInterface(with: InstallationClient.self)

        newConnection.interruptionHandler = connetionInterruptionHandler
        newConnection.invalidationHandler = connectionInvalidationHandler

        newConnection.resume()

        helper.client = newConnection.remoteObjectProxy as? InstallationClient

        return true
    }
}