//
//  WallpaperVideoOptimizer.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-09.
//

import AppKit
import AVFoundation

struct WallpaperVideoTarget: Hashable {
    var longEdge: Double
    var shortEdge: Double
    var maxFrameRate: Int = WallpaperVideoOptimizer.maxFrameRate

    @MainActor
    static var current: WallpaperVideoTarget {
        var long = 0.0
        var short = 0.0
        for screen in NSScreen.screens {
            let width = screen.frame.width * screen.backingScaleFactor
            let height = screen.frame.height * screen.backingScaleFactor
            long = max(long, max(width, height))
            short = max(short, min(width, height))
        }
        if long == 0 { long = 3840; short = 2160 }
        return WallpaperVideoTarget(longEdge: long, shortEdge: short)
    }
}

struct WallpaperVideoProfile: Equatable {
    var codec: CMVideoCodecType
    var isQuickTimeMovie: Bool
    var size: CGSize
    var frameRate: Float

    var isHardwareFriendlyCodec: Bool {
        codec == kCMVideoCodecType_HEVC || codec == kCMVideoCodecType_H264
    }
}

struct WallpaperVideoEncodePlan: Hashable {
    var renderSize: CGSize
    var frameRate: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(renderSize.width)
        hasher.combine(renderSize.height)
        hasher.combine(frameRate)
    }

    init(renderSize: CGSize, frameRate: Int) {
        self.renderSize = renderSize
        self.frameRate = frameRate
    }

    init?(fileSuffix: String) {
        let parts = fileSuffix.split(whereSeparator: { $0 == "x" || $0 == "@" }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(renderSize: CGSize(width: parts[0], height: parts[1]), frameRate: parts[2])
    }

    var fileSuffix: String {
        "\(Int(renderSize.width))x\(Int(renderSize.height))@\(frameRate)"
    }
}

actor WallpaperVideoOptimizer {
    static let shared = WallpaperVideoOptimizer()

    nonisolated static let maxFrameRate = 60
    nonisolated static let downscaleThreshold = 0.85

    nonisolated static var directory: URL {
        WallpaperAssetStore.directory.appendingPathComponent("Optimized", isDirectory: true)
    }

    private var inFlight: [URL: Task<URL, Error>] = [:]

    nonisolated static func plan(
        for profile: WallpaperVideoProfile,
        target: WallpaperVideoTarget,
        requireHEVCMovie: Bool
    ) -> WallpaperVideoEncodePlan? {
        guard profile.size.width > 0, profile.size.height > 0 else { return nil }

        let sourceLong = max(profile.size.width, profile.size.height)
        let sourceShort = min(profile.size.width, profile.size.height)
        let scale = min(1, max(target.longEdge / sourceLong, target.shortEdge / sourceShort))
        let shrinks = scale < downscaleThreshold
        let frameRate = profile.frameRate > Float(target.maxFrameRate) + 1
            ? target.maxFrameRate
            : max(1, Int(profile.frameRate.rounded()))
        let capsFrameRate = frameRate < Int(profile.frameRate.rounded())
        let needsCodec = !profile.isHardwareFriendlyCodec
            || (requireHEVCMovie && !(profile.codec == kCMVideoCodecType_HEVC && profile.isQuickTimeMovie))

        guard shrinks || capsFrameRate || needsCodec else { return nil }

        let factor = shrinks ? scale : 1
        let renderSize = CGSize(
            width: evenPixels(profile.size.width * factor),
            height: evenPixels(profile.size.height * factor)
        )
        return WallpaperVideoEncodePlan(renderSize: renderSize, frameRate: frameRate)
    }

    nonisolated static func profile(of url: URL) async throws -> (WallpaperVideoProfile, AVAssetTrack, AVURLAsset) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let (naturalSize, transform, frameRate, formats) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions
        )
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform).size
        let profile = WallpaperVideoProfile(
            codec: formats.first.map(CMFormatDescriptionGetMediaSubType) ?? 0,
            isQuickTimeMovie: url.pathExtension.caseInsensitiveCompare("mov") == .orderedSame,
            size: CGSize(width: abs(oriented.width), height: abs(oriented.height)),
            frameRate: frameRate
        )
        return (profile, track, asset)
    }

    func playableURL(
        for source: URL,
        target: WallpaperVideoTarget,
        requireHEVCMovie: Bool = false
    ) async throws -> URL {
        let (profile, track, asset) = try await Self.profile(of: source)
        guard let plan = Self.plan(for: profile, target: target, requireHEVCMovie: requireHEVCMovie) else {
            return source
        }

        let sourceKey = WallpaperAssetStore.cacheKey(for: source)
        if let cached = Self.cachedCopy(of: sourceKey, satisfying: plan) {
            return cached
        }
        let destination = Self.directory.appendingPathComponent("\(sourceKey)-\(plan.fileSuffix).mov")
        if let task = inFlight[destination] {
            return try await task.value
        }

        let task = Task.detached(priority: .utility) {
            try await Self.encode(asset: asset, track: track, plan: plan, to: destination)
        }
        inFlight[destination] = task
        defer { inFlight[destination] = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    nonisolated static func cachedCopy(of sourceKey: String, satisfying plan: WallpaperVideoEncodePlan) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files
            .compactMap { file -> (URL, WallpaperVideoEncodePlan)? in
                let name = file.deletingPathExtension().lastPathComponent
                guard name.hasPrefix(sourceKey + "-"),
                      let cached = WallpaperVideoEncodePlan(fileSuffix: String(name.dropFirst(sourceKey.count + 1))),
                      cached.renderSize.width >= plan.renderSize.width,
                      cached.renderSize.height >= plan.renderSize.height,
                      cached.frameRate <= plan.frameRate else { return nil }
                return (file, cached)
            }
            .min { $0.1.renderSize.width < $1.1.renderSize.width }?
            .0
    }

    nonisolated static func prune(keepingSources sources: [URL]) {
        let keep = Set(sources.map { WallpaperAssetStore.cacheKey(for: $0) })
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where !file.lastPathComponent.hasPrefix(".") {
            let key = file.lastPathComponent.split(separator: "-").first.map(String.init) ?? ""
            if !keep.contains(key) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Encoding

    private nonisolated static func encode(
        asset: AVURLAsset,
        track: AVAssetTrack,
        plan: WallpaperVideoEncodePlan,
        to destination: URL
    ) async throws -> URL {
        let fileManager = FileManager.default
        WallpaperAssetStore.ensureDirectory(directory)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp.mov")
        defer { try? fileManager.removeItem(at: temporary) }

        let composition = AVMutableComposition()
        let timeRange = try await track.load(.timeRange)
        let transform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try compositionTrack.insertTimeRange(timeRange, of: track, at: .zero)

        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let scale = plan.renderSize.width / max(1, abs(oriented.width))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        layer.setTransform(
            transform
                .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)),
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: timeRange.duration)
        instruction.layerInstructions = [layer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = plan.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(plan.frameRate))
        videoComposition.instructions = [instruction]

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHEVCHighestQuality
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        exporter.outputURL = temporary
        exporter.outputFileType = .mov
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = false

        try Task.checkCancellation()
        let started = Date()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                exporter.exportAsynchronously {
                    continuation.resume()
                }
            }
        } onCancel: {
            exporter.cancelExport()
        }
        try Task.checkCancellation()
        guard exporter.status == .completed else {
            throw exporter.error ?? CocoaError(.fileWriteUnknown)
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        NSLog(
            "[LiveWallpaper] Optimized \(asset.url.lastPathComponent) → \(plan.fileSuffix) in %.1fs",
            Date().timeIntervalSince(started)
        )
        return destination
    }

    private nonisolated static func evenPixels(_ value: Double) -> Double {
        max(2, (value / 2).rounded() * 2)
    }
}