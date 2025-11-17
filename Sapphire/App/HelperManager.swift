//
//  HelperManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import ServiceManagement
import AppKit

class AlertHelper {
    static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
class HelperManager: ObservableObject {
    static let shared = HelperManager()

    let helperToolIdentifier = "com.shariq.sapphireHelper"

    @Published var status: SMAppService.Status = .notRegistered

    private init() {
        updateStatus()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatus),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc func updateStatus() {
        let newStatus = SMAppService.daemon(plistName: "\(helperToolIdentifier).plist").status
        if self.status != newStatus {
            self.status = newStatus
        }
    }

    func installIfNeeded() {
        guard status == .notRegistered || status == .notFound else {
            if status == .requiresApproval {
                AlertHelper.showAlert(
                    title: "Helper Service Approval Required",
                    message: "Sapphire needs you to enable its helper service in System Settings for certain functions like battery management to work correctly. Please go to System Settings > General > Login Items and enable it."
                )
                SMAppService.openSystemSettingsLoginItems()
            }
            return
        }

        do {
            try SMAppService.daemon(plistName: "\(helperToolIdentifier).plist").register()
            AlertHelper.showAlert(
                title: "Helper Service Installed",
                message: "The helper service for Sapphire has been properly installed."
            )

        } catch {
            NSLog("[HelperManager] Helper registration failed with error: \(error.localizedDescription)")
            AlertHelper.showAlert(
                title: "Installation Failed",
                message: "Failed to install the helper service. Please try again. Error: \(error.localizedDescription)"
            )
        }
        updateStatus()
    }

    func uninstall() {
        do {
            try SMAppService.daemon(plistName: "\(helperToolIdentifier).plist").unregister()
            NSLog("[HelperManager] Helper unregistration successful.")
            XPCClient.shared.stop()
        } catch {
            NSLog("[HelperManager] Helper unregistration failed with error: \(error.localizedDescription)")
        }
        updateStatus()
    }
}

extension SMAppService.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notRegistered: return "Not Registered"
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires Approval"
        case .notFound: return "Not Found"
        @unknown default: return "Unknown"
        }
    }
}