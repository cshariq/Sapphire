//
//  DisplayableApp.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import UniformTypeIdentifiers

enum DisplayableApp: Identifiable {
    case active(AudioApp)
    case pinnedInactive(PinnedAppInfo)

    var id: String {
        switch self {
        case .active(let app):
            return app.persistenceIdentifier
        case .pinnedInactive(let info):
            return info.persistenceIdentifier
        }
    }

    var isPinnedInactive: Bool {
        switch self {
        case .active:
            return false
        case .pinnedInactive:
            return true
        }
    }

    var isActive: Bool {
        switch self {
        case .active:
            return true
        case .pinnedInactive:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .active(let app):
            return app.name
        case .pinnedInactive(let info):
            return info.displayName
        }
    }

    var icon: NSImage {
        switch self {
        case .active(let app):
            return app.icon
        case .pinnedInactive(let info):
            return Self.loadIcon(bundleID: info.bundleID)
        }
    }

    static func loadIcon(bundleID: String?) -> NSImage {
        if let bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}