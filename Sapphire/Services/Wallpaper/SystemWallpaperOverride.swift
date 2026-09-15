//
//  SystemWallpaperOverride.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-28.
//

import AppKit
import SQLite

@MainActor
final class SystemWallpaperOverride {
    static let shared = SystemWallpaperOverride()

    struct DisplaySnapshot: Codable, Equatable {
        var url: URL
        var imageScaling: UInt?
        var allowClipping: Bool?

        init(url: URL, imageScaling: UInt?, allowClipping: Bool?) {
            self.url = url
            self.imageScaling = imageScaling
            self.allowClipping = allowClipping
        }

        init(url: URL, options: [NSWorkspace.DesktopImageOptionKey: Any]) {
            self.url = url
            self.imageScaling = (options[.imageScaling] as? NSNumber)?.uintValue
            self.allowClipping = (options[.allowClipping] as? NSNumber)?.boolValue
        }

        var options: [NSWorkspace.DesktopImageOptionKey: Any] {
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            if let imageScaling { options[.imageScaling] = imageScaling }
            if let allowClipping { options[.allowClipping] = allowClipping }
            return options
        }
    }

    struct State: Codable, Equatable {
        var originals: [String: DisplaySnapshot] = [:]
        var appliedURL: URL?
        var appliedScaling: WallpaperScaling?
    }

    private let stateURL: URL
    private var state: State?
    private var didLoadState = false

    init(stateURL: URL = WallpaperAssetStore.directory.appendingPathComponent("system-wallpaper-override.json")) {
        self.stateURL = stateURL
    }

    var isApplied: Bool { loadState()?.appliedURL != nil }
    var appliedURL: URL? { loadState()?.appliedURL }

    func apply(_ url: URL, scaling: WallpaperScaling) {
        let target = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: target.path) else { return }

        var next = loadState() ?? State()
        let optionsChanged = next.appliedScaling != scaling
        for screen in NSScreen.screens {
            let key = Self.displayKey(for: screen)
            let current = Self.currentImageURL(for: screen)

            if let current, Self.shouldAdoptAsOriginal(current: current, applied: next.appliedURL, target: target) {
                next.originals[key] = DisplaySnapshot(
                    url: current,
                    options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                )
            }

            guard current?.standardizedFileURL != target || optionsChanged else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(target, for: screen, options: scaling.desktopImageOptions)
            } catch {
                NSLog("[SystemWallpaperOverride] Failed to set wallpaper on display \(key): \(error.localizedDescription)")
            }
        }
        next.appliedURL = target
        next.appliedScaling = scaling
        save(next)
    }

    func restore() {
        guard let current = loadState() else { return }
        if let applied = current.appliedURL {
            for screen in NSScreen.screens {
                let key = Self.displayKey(for: screen)
                guard let original = current.originals[key],
                      FileManager.default.fileExists(atPath: original.url.path) else { continue }
                let shown = Self.currentImageURL(for: screen)
                if let shown, !Self.isSapphireWallpaper(shown, applied: applied) { continue }
                do {
                    try NSWorkspace.shared.setDesktopImageURL(original.url, for: screen, options: original.options)
                } catch {
                    NSLog("[SystemWallpaperOverride] Failed to restore wallpaper on display \(key): \(error.localizedDescription)")
                }
            }
        }
        save(nil)
    }

    nonisolated static func shouldAdoptAsOriginal(current: URL, applied: URL?, target: URL) -> Bool {
        let current = current.standardizedFileURL
        if current == target.standardizedFileURL { return false }
        return !isSapphireWallpaper(current, applied: applied)
    }

    nonisolated static func isSapphireWallpaper(_ url: URL, applied: URL?) -> Bool {
        let url = url.standardizedFileURL
        return url == applied?.standardizedFileURL || WallpaperAssetStore.contains(url)
    }

    // MARK: - Persistence

    private func loadState() -> State? {
        if !didLoadState {
            didLoadState = true
            if let data = try? Data(contentsOf: stateURL) {
                state = try? JSONDecoder().decode(State.self, from: data)
            }
        }
        return state
    }

    private func save(_ newState: State?) {
        state = newState
        didLoadState = true
        guard let newState else {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        WallpaperAssetStore.ensureDirectory(stateURL.deletingLastPathComponent())
        do {
            let data = try JSONEncoder().encode(newState)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("[SystemWallpaperOverride] Failed to persist override state: \(error.localizedDescription)")
        }
    }

    // MARK: - Display helpers

    static func displayKey(for screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }
        return String(displayID)
    }

    private static func currentImageURL(for screen: NSScreen) -> URL? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return url
        }

        if #available(macOS 26, *) {
            return url
        }

        return resolveImageFromDirectory(url)
    }

    private static func resolveImageFromDirectory(_ directory: URL) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return directory
        }
        let databaseURL = appSupport.appendingPathComponent("Dock/desktoppicture.db", isDirectory: false)
        guard let db = try? Connection(databaseURL.path, readonly: true) else { return directory }

        let table = Table("data")
        let value = Expression<String>("value")
        let rowID = Expression<Int64>("rowid")
        guard let maxID = try? db.scalar(table.select(rowID.max)),
              let imagePath = try? db.pluck(table.filter(rowID == maxID))?.get(value) else {
            return directory
        }
        return directory.appendingPathComponent(imagePath, isDirectory: false)
    }
}