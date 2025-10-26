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
        NSLog("[SMJBS]: \(#function)")
    }

    private func connectionInvalidationHandler() {
        NSLog("[SMJBS]: \(#function)")
    }

    private func isValidClient(forConnection connection: NSXPCConnection) -> Bool {

        var token = connection.auditToken;
        let tokenData = Data(bytes: &token, count: MemoryLayout.size(ofValue:token))
        let attributes = [kSecGuestAttributeAudit : tokenData]

        let flags: SecCSFlags = []
        var code: SecCode? = nil
        var status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, flags, &code)

        if status != errSecSuccess {
            return false
        }

        guard let dynamicCode = code else {
            return false
        }

        let entitlements = "identifier \"com.shariq.sapphire\" and anchor apple generic"
        var requirement: SecRequirement?

        status = SecRequirementCreateWithString(entitlements as CFString, flags, &requirement)

        if status != errSecSuccess {
            return false
        }

        status = SecCodeCheckValidity(dynamicCode, flags, requirement)

        return status == errSecSuccess
    }
}

extension XPCServer: NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        NSLog("[SMJBS]: \(#function)")

        if (!isValidClient(forConnection: newConnection)) {
            NSLog("[SMJBS]: Client is not valid")
            return false
        }

        NSLog("[SMJBS]: Client is valid")

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