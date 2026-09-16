//
//  NativeLockScreenWallpaperController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit
import AVFoundation

@MainActor
final class NativeLockScreenWallpaperController {
    private var desiredCacheKey: String?
    private var installedCacheKey = NativeLockScreenWallpaperInstaller.installedCacheKey
    private var task: Task<Void, Never>?
    private var generation = 0

    var onChange: (() -> Void)?

    func configure(media: WallpaperMedia?) {
        let media = media?.isVideo == true ? media : nil
        let cacheKey = media.map { WallpaperAssetStore.cacheKey(for: $0.url) }
        guard cacheKey != desiredCacheKey || (cacheKey == nil && installedCacheKey != nil) else { return }

        desiredCacheKey = cacheKey
        generation &+= 1
        let requestGeneration = generation
        task?.cancel()

        guard let media, let cacheKey else {
            installedCacheKey = nil
            task = Task { [weak self] in
                await NativeLockScreenWallpaperInstaller.shared.restore()
                guard let self, self.generation == requestGeneration else { return }
                self.onChange?()
            }
            return
        }

        if installedCacheKey == cacheKey {
            return
        }

        task = Task { [weak self] in
            let installed = await NativeLockScreenWallpaperInstaller.shared.install(
                media: media,
                cacheKey: cacheKey
            )
            guard let self, !Task.isCancelled, self.generation == requestGeneration else { return }
            self.installedCacheKey = installed ? cacheKey : nil
            self.onChange?()
        }
    }

    func isInstalled(for media: WallpaperMedia?) -> Bool {
        guard let media else { return false }
        return installedCacheKey == WallpaperAssetStore.cacheKey(for: media.url)
    }

    func screenDidLock() {
        guard installedCacheKey != nil else { return }
        Task.detached(priority: .utility) {
            NativeLockScreenWallpaperInstaller.restartAerialPlayer()
        }
    }

    func shutdown() {
        generation &+= 1
        task?.cancel()
        task = nil
        desiredCacheKey = nil
        installedCacheKey = nil
        NativeLockScreenWallpaperInstaller.restoreSynchronously()
    }
}

private actor NativeLockScreenWallpaperInstaller {
    struct Installation: Codable {
        let slotURL: URL
        let backupURL: URL
        var sourceCacheKey: String?
        var indexURL: URL?
        var originalIdleConfigurations: [String: Data]?
        var configurationVersion: Int?
    }

    static let shared = NativeLockScreenWallpaperInstaller()

    private static var nativeDirectory: URL {
        WallpaperAssetStore.directory.appendingPathComponent("NativeLockScreen", isDirectory: true)
    }

    private static var convertedDirectory: URL {
        nativeDirectory.appendingPathComponent("Converted", isDirectory: true)
    }

    private static var stateURL: URL {
        nativeDirectory.appendingPathComponent("installation.plist")
    }

    nonisolated static var installedCacheKey: String? {
        guard let installation = loadInstallation(), installation.configurationVersion == 2 else {
            return nil
        }
        return installation.sourceCacheKey
    }

    func install(media: WallpaperMedia, cacheKey: String) async -> Bool {
        do {
            let convertedURL = try await Self.convertToAerialMovie(media.url, cacheKey: cacheKey)
            try Task.checkCancellation()
            try Self.install(convertedURL, cacheKey: cacheKey)
            Self.restartWallpaperServices()
            return true
        } catch is CancellationError {
            return false
        } catch {
            NSLog("[LiveWallpaper] Native lock-screen setup failed: \(error.localizedDescription)")
            return false
        }
    }

    func restore() {
        Self.restoreSynchronously()
    }

    nonisolated static func restoreSynchronously() {
        guard let installation = loadInstallation() else { return }
        do {
            try replaceItem(at: installation.slotURL, with: installation.backupURL)
            try restoreIdlePlist(using: installation)
            try? FileManager.default.removeItem(at: installation.backupURL)
            try? FileManager.default.removeItem(at: stateURL)
            restartWallpaperServices()
        } catch {
            NSLog("[LiveWallpaper] Couldn't restore the original Aerial: \(error.localizedDescription)")
        }
    }

    nonisolated static func restartAerialPlayer() {
        terminateProcess(named: "WallpaperAerialsExtension")
    }

    private nonisolated static func restartWallpaperServices() {
        terminateProcess(named: "WallpaperAerialsExtension")
        terminateProcess(named: "WallpaperAgent")
    }

    private nonisolated static func terminateProcess(named name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
        }
    }

    private static func install(_ movieURL: URL, cacheKey: String) throws {
        let fileManager = FileManager.default
        WallpaperAssetStore.ensureDirectory(nativeDirectory)

        var installation = loadInstallation()
        if let existing = installation,
           !fileManager.fileExists(atPath: existing.backupURL.path) {
            try? fileManager.removeItem(at: stateURL)
            installation = nil
        }

        if installation == nil {
            guard let slotURL = selectedAerialSlotURL() else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "Select and download an Apple Aerial wallpaper in System Settings first."
                ])
            }
            let backupURL = nativeDirectory.appendingPathComponent("\(slotURL.deletingPathExtension().lastPathComponent)-original.mov")
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: slotURL, to: backupURL)
            installation = Installation(
                slotURL: slotURL,
                backupURL: backupURL,
                sourceCacheKey: nil,
                indexURL: nil,
                originalIdleConfigurations: nil,
                configurationVersion: nil
            )
            try saveInstallation(installation!)
        }

        guard var installation else { return }
        try replaceItem(at: installation.slotURL, with: movieURL)
        try configureIdlePlist(
            aerialID: installation.slotURL.deletingPathExtension().lastPathComponent,
            installation: &installation
        )
        installation.sourceCacheKey = cacheKey
        installation.configurationVersion = 2
        try saveInstallation(installation)
    }

    private static func selectedAerialSlotURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: indexURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let assetID = selectedAerialID(in: plist) else {
            return nil
        }

        let videoURL = home.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/aerials/videos/\(assetID).mov"
        )
        return FileManager.default.fileExists(atPath: videoURL.path) ? videoURL : nil
    }

    private static func selectedAerialID(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let provider = dictionary["Provider"] as? String,
               provider.localizedCaseInsensitiveContains("aerial"),
               let configuration = dictionary["Configuration"] as? Data,
               let decoded = try? PropertyListSerialization.propertyList(
                   from: configuration,
                   options: [],
                   format: nil
               ) as? [String: Any],
               let identifier = (decoded["assetID"] ?? decoded["selectedID"]) as? String {
                return identifier
            }
            for child in dictionary.values {
                if let identifier = selectedAerialID(in: child) { return identifier }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let identifier = selectedAerialID(in: child) { return identifier }
            }
        }
        return nil
    }

    private static func configureIdlePlist(
        aerialID: String,
        installation: inout Installation
    ) throws {
        let indexURL = installation.indexURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        let data = try Data(contentsOf: indexURL)
        var root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let replacement = try PropertyListSerialization.data(
            fromPropertyList: [
                "selectedID": aerialID,
                "showAsScreenSaver": true
            ],
            format: .binary,
            options: 0
        )
        var originals = installation.originalIdleConfigurations ?? [:]
        rewriteIdleAerialConfigurations(
            in: &root,
            path: "root",
            insideIdle: false,
            replacement: replacement,
            originals: &originals,
            captureOriginals: installation.originalIdleConfigurations == nil
        )
        guard !originals.isEmpty else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "No native Aerial lock-screen configuration was found."
            ])
        }

        installation.indexURL = indexURL
        installation.originalIdleConfigurations = originals
        try saveInstallation(installation)

        let updated = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try updated.write(to: indexURL, options: .atomic)
    }

    private static func restoreIdlePlist(using installation: Installation) throws {
        guard let indexURL = installation.indexURL,
              let originals = installation.originalIdleConfigurations,
              !originals.isEmpty,
              FileManager.default.fileExists(atPath: indexURL.path) else {
            return
        }
        let data = try Data(contentsOf: indexURL)
        var root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        restoreIdleAerialConfigurations(in: &root, path: "root", originals: originals)
        let restored = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try restored.write(to: indexURL, options: .atomic)
    }

    private static func rewriteIdleAerialConfigurations(
        in value: inout Any,
        path: String,
        insideIdle: Bool,
        replacement: Data,
        originals: inout [String: Data],
        captureOriginals: Bool
    ) {
        if var dictionary = value as? [String: Any] {
            if insideIdle,
               let provider = dictionary["Provider"] as? String,
               provider.localizedCaseInsensitiveContains("aerial") || provider.localizedCaseInsensitiveContains("sonoma"),
               let current = dictionary["Configuration"] as? Data {
                if captureOriginals, originals[path] == nil {
                    originals[path] = current
                }
                dictionary["Configuration"] = replacement
            }
            for key in dictionary.keys {
                guard var child = dictionary[key] else { continue }
                rewriteIdleAerialConfigurations(
                    in: &child,
                    path: "\(path).\(key)",
                    insideIdle: insideIdle || key == "Idle",
                    replacement: replacement,
                    originals: &originals,
                    captureOriginals: captureOriginals
                )
                dictionary[key] = child
            }
            value = dictionary
        } else if var array = value as? [Any] {
            for index in array.indices {
                var child = array[index]
                rewriteIdleAerialConfigurations(
                    in: &child,
                    path: "\(path)[\(index)]",
                    insideIdle: insideIdle,
                    replacement: replacement,
                    originals: &originals,
                    captureOriginals: captureOriginals
                )
                array[index] = child
            }
            value = array
        }
    }

    private static func restoreIdleAerialConfigurations(
        in value: inout Any,
        path: String,
        originals: [String: Data]
    ) {
        if var dictionary = value as? [String: Any] {
            if let original = originals[path] {
                dictionary["Configuration"] = original
            }
            for key in dictionary.keys {
                guard var child = dictionary[key] else { continue }
                restoreIdleAerialConfigurations(
                    in: &child,
                    path: "\(path).\(key)",
                    originals: originals
                )
                dictionary[key] = child
            }
            value = dictionary
        } else if var array = value as? [Any] {
            for index in array.indices {
                var child = array[index]
                restoreIdleAerialConfigurations(
                    in: &child,
                    path: "\(path)[\(index)]",
                    originals: originals
                )
                array[index] = child
            }
            value = array
        }
    }

    private static func convertToAerialMovie(_ sourceURL: URL, cacheKey: String) async throws -> URL {
        let fileManager = FileManager.default
        WallpaperAssetStore.ensureDirectory(convertedDirectory)
        let destination = convertedDirectory.appendingPathComponent("\(cacheKey).mov")
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        let temporary = convertedDirectory.appendingPathComponent("\(cacheKey)-\(UUID().uuidString).tmp.mov")
        defer { try? fileManager.removeItem(at: temporary) }

        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let formatDescriptions = try await tracks.first?.load(.formatDescriptions) ?? []
        let isNativeHEVC = sourceURL.pathExtension.caseInsensitiveCompare("mov") == .orderedSame
            && formatDescriptions.contains {
                CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC
            }
        if isNativeHEVC {
            try Task.checkCancellation()
            try fileManager.copyItem(at: sourceURL, to: temporary)
            try fileManager.moveItem(at: temporary, to: destination)
            return destination
        }

        let compatiblePresets = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetHEVCHighestQuality, with: asset, outputFileType: .mov)
        guard compatiblePresets else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "The selected video can't be converted to a native HEVC wallpaper."
            ])
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        exporter.outputURL = temporary
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }
        try Task.checkCancellation()
        guard exporter.status == .completed else {
            throw exporter.error ?? CocoaError(.fileWriteUnknown)
        }

        try fileManager.moveItem(at: temporary, to: destination)
        return destination
    }

    private nonisolated static func replaceItem(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".sapphire-\(UUID().uuidString).mov")
        do {
            try fileManager.copyItem(at: source, to: temporary)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private nonisolated static func loadInstallation() -> Installation? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? PropertyListDecoder().decode(Installation.self, from: data)
    }

    private static func saveInstallation(_ installation: Installation) throws {
        WallpaperAssetStore.ensureDirectory(nativeDirectory)
        let data = try PropertyListEncoder().encode(installation)
        try data.write(to: stateURL, options: .atomic)
    }
}