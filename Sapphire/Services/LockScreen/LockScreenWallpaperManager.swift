//
//  LockScreenWallpaperManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-28.
//

import Foundation
import AppKit
import SQLite

final class LockScreenWallpaperManager {
    static let shared = LockScreenWallpaperManager()

    private struct WallpaperSnapshot {
        let url: URL
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    private var snapshots: [CGDirectDisplayID: WallpaperSnapshot] = [:]
    private var isApplied = false

    private init() {}

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return id?.uint32Value ?? 0
    }

    private func currentImageURL(for screen: NSScreen) -> URL? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return url
        }

        if #available(macOS 26, *) {
            return url
        }

        return resolveImageFromDirectory(url, screen: screen)
    }

    private func resolveImageFromDirectory(_ directory: URL, screen: NSScreen) -> URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return directory
        }
        let databaseURL = appSupport.appendingPathComponent("Dock/desktoppicture.db", isDirectory: false)
        guard let db = try? Connection(databaseURL.path) else { return directory }

        let table = Table("data")
        let value = Expression<String>("value")
        let rowID = Expression<Int64>("rowid")
        guard let maxID = try? db.scalar(table.select(rowID.max)),
              let imagePath = try? db.pluck(table.filter(rowID == maxID))?.get(value) else {
            return directory
        }
        return directory.appendingPathComponent(imagePath, isDirectory: false)
    }

    func applyCustomWallpaperIfEnabled(path: String?) {
        guard let path,
              URL(fileURLWithPath: path).isFileURL,
              FileManager.default.fileExists(atPath: path) else {
            if isApplied { restore() }
            return
        }

        let screens = NSScreen.screens
        if !isApplied || snapshots.isEmpty {
            var fresh: [CGDirectDisplayID: WallpaperSnapshot] = [:]
            for screen in screens {
                guard let url = currentImageURL(for: screen),
                      url != URL(fileURLWithPath: path) else { continue }
                fresh[displayID(for: screen)] = WallpaperSnapshot(
                    url: url,
                    options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                )
            }
            snapshots = fresh
        }

        let imageURL = URL(fileURLWithPath: path)
        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
            } catch {
                NSLog("[LockScreenWallpaper] Failed to set wallpaper on display \(displayID(for: screen)): \(error.localizedDescription)")
            }
        }
        isApplied = true
    }

    func restore() {
        guard isApplied, !snapshots.isEmpty else {
            snapshots.removeAll()
            isApplied = false
            return
        }
        for screen in NSScreen.screens {
            let id = displayID(for: screen)
            guard let snapshot = snapshots[id] else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(snapshot.url, for: screen, options: snapshot.options)
            } catch {
                NSLog("[LockScreenWallpaper] Failed to restore wallpaper on display \(id): \(error.localizedDescription)")
            }
        }
        snapshots.removeAll()
        isApplied = false
    }

    var isCurrentlyApplied: Bool { isApplied }
}