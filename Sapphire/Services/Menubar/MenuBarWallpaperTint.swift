//
//  MenuBarWallpaperTint.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27
//

import AppKit
import ImageIO

extension Notification.Name {
    static let menuBarWallpaperTintDidChange = Notification.Name("com.sapphire.menuBarWallpaperTintDidChange")
}

@MainActor
final class MenuBarWallpaperTint {
    static let shared = MenuBarWallpaperTint()

    struct Tint: Equatable {
        let leading: NSColor
        let trailing: NSColor

        var average: NSColor {
            leading.blended(withFraction: 0.5, of: trailing) ?? leading
        }
    }

    private(set) var tints: [CGDirectDisplayID: Tint] = [:]

    private var isRunning = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var storeWatcher: DispatchSourceFileSystemObject?
    private var pendingSample: DispatchWorkItem?
    private var cache: [URL: Tint] = [:]

    private let sampleQueue = DispatchQueue(label: "com.sapphire.menubar-wallpaper-tint", qos: .utility)

    private init() {}

    func tint(for displayID: CGDirectDisplayID) -> Tint? {
        tints[displayID]
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSample() }
        }))
        let app = NotificationCenter.default
        observers.append((app, app.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSample() }
        }))
        watchWallpaperStore()
        scheduleSample(delay: 0)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        storeWatcher?.cancel()
        storeWatcher = nil
        pendingSample?.cancel()
        pendingSample = nil
    }

    // MARK: - Change sources

    private func watchWallpaperStore() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleSample() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        storeWatcher = source
    }

    private func scheduleSample(delay: TimeInterval = 0.4) {
        pendingSample?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.sample() }
        }
        pendingSample = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Sampling

    private func sample() {
        let requests: [(CGDirectDisplayID, URL)] = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, URL)? in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return (screen.displayID, url)
        }
        let cached = cache
        sampleQueue.async { [weak self] in
            var sampled: [CGDirectDisplayID: Tint] = [:]
            var fresh: [URL: Tint] = [:]
            for (displayID, url) in requests {
                if let tint = cached[url] ?? fresh[url] ?? Self.sampleTopStrip(of: url) {
                    sampled[displayID] = tint
                    fresh[url] = tint
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    self.cache = fresh
                    guard sampled != self.tints else { return }
                    self.tints = sampled
                    NotificationCenter.default.post(name: .menuBarWallpaperTintDidChange, object: nil)
                }
            }
        }
    }

    private nonisolated static func sampleTopStrip(of url: URL) -> Tint? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let stripHeight = max(2, Int(Double(thumbnail.height) * 0.06))
        guard let strip = thumbnail.cropping(to: CGRect(x: 0, y: 0, width: thumbnail.width, height: stripHeight)) else { return nil }

        var pixels = [UInt8](repeating: 0, count: 8)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(strip, in: CGRect(x: 0, y: 0, width: 2, height: 1))
            return true
        }
        guard drawn else { return nil }

        func color(at offset: Int) -> NSColor {
            NSColor(
                srgbRed: CGFloat(pixels[offset]) / 255,
                green: CGFloat(pixels[offset + 1]) / 255,
                blue: CGFloat(pixels[offset + 2]) / 255,
                alpha: 1
            )
        }
        return Tint(leading: color(at: 0), trailing: color(at: 4))
    }
}