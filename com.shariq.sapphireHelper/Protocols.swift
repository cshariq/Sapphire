//
//  Protocols.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23

import Foundation

@objc protocol Installer {
    func install()
    func uninstall()
}

@objc public protocol InstallationClient {
    func installationDidReachProgress(_ progress: Double, description: String?)
}