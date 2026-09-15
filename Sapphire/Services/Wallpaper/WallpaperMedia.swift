//
//  WallpaperMedia.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15.
//

import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct WallpaperMedia: Hashable {
    enum Kind: Hashable {
        case image
        case video
    }

    let url: URL
    let kind: Kind

    init(url: URL, kind: Kind) {
        self.url = url.standardizedFileURL
        self.kind = kind
    }

    init?(path: String?) {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.init(url: url, kind: Self.kind(of: url))
    }

    var isVideo: Bool { kind == .video }

    static func isVideo(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return kind(of: URL(fileURLWithPath: path)) == .video
    }

    static func kind(of url: URL) -> Kind {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension.lowercased())
        if let type, type.conforms(to: .movie) || type.conforms(to: .video) {
            return .video
        }
        return .image
    }

    static let allowedContentTypes: [UTType] = [.image, .movie]
}

enum WallpaperScaling: String, Codable, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: return "Fill Screen"
        case .fit: return "Fit to Screen"
        case .stretch: return "Stretch to Fill"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }

    var desktopImageOptions: [NSWorkspace.DesktopImageOptionKey: Any] {
        switch self {
        case .fill:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true
            ]
        case .fit:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: false,
                .fillColor: NSColor.black
            ]
        case .stretch:
            return [
                .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                .allowClipping: true
            ]
        }
    }
}

enum WallpaperAssetStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Sapphire/Wallpapers", isDirectory: true)
    }

    static var postersDirectory: URL {
        directory.appendingPathComponent("Posters", isDirectory: true)
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
    }

    static func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fingerprint = [
            url.standardizedFileURL.path,
            String(values?.fileSize ?? 0),
            String(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func stillImageURL(for media: WallpaperMedia) async -> URL? {
        switch media.kind {
        case .image:
            return media.url
        case .video:
            return await posterFrameURL(forVideoAt: media.url)
        }
    }

    static func posterFrameURL(forVideoAt url: URL) async -> URL? {
        let destination = postersDirectory.appendingPathComponent("\(cacheKey(for: url)).jpg")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)

        let image: CGImage
        do {
            image = try await generator.image(at: .zero).image
        } catch {
            NSLog("[LiveWallpaper] Poster frame generation failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }

        ensureDirectory(postersDirectory)
        let temporary = destination.appendingPathExtension("tmp")
        guard let target = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(target) else {
            try? FileManager.default.removeItem(at: temporary)
            return nil
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            return FileManager.default.fileExists(atPath: destination.path) ? destination : nil
        }
        return destination
    }

    static func thumbnail(for media: WallpaperMedia, maxPixelSize: Int) async -> CGImage? {
        switch media.kind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(media.url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        case .video:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: media.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
            return try? await generator.image(at: .zero).image
        }
    }

    static func prunePosters(keeping media: [WallpaperMedia]) {
        let keep = Set(media.filter(\.isVideo).map { "\(cacheKey(for: $0.url)).jpg" })
        guard let files = try? FileManager.default.contentsOfDirectory(at: postersDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}