//
//  Installer.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23

import Foundation

class InstallerImpl: NSObject, Installer {

    var client: InstallationClient?

    func install() {
        NSLog("[SMJBS]: \(#function)")
        client?.installationDidReachProgress(1, description: "Finished!")
    }

    func uninstall() {
        NSLog("[SMJBS]: \(#function)")

    }
}