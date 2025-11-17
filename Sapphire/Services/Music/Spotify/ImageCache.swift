//
//  ImageCache.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-23.
//

import SwiftUI

fileprivate class FileImageCache {
    static let shared = FileImageCache()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let cacheBaseUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheBaseUrl.appendingPathComponent("ImageCache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)

        Task(priority: .background) {
            cleanupOldFiles()
        }
    }

    private func cacheUrl(forKey key: String) -> URL? {
        let safeKey = key.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let finalKey = String(safeKey.prefix(100))
        return cacheDirectory.appendingPathComponent(finalKey)
    }

    func get(forKey key: String) -> NSImage? {
        guard let url = cacheUrl(forKey: key) else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    func set(_ image: NSImage, forKey key: String) {
        guard let url = cacheUrl(forKey: key) else { return }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        do {
            try pngData.write(to: url)
        } catch {
            print("Failed to write image to cache: \(error.localizedDescription)")
        }
    }

    private func cleanupOldFiles() {
        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            for file in files {
                if let modificationDate = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   Date().timeIntervalSince(modificationDate) > expirationInterval {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("Error cleaning up image cache: \(error)")
        }
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var image: NSImage?
    private let imageCache = FileImageCache.shared

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        if let nsImage = image {
            content(Image(nsImage: nsImage))
        } else {
            placeholder()
                .task(id: url) {
                    await loadImage()
                }
        }
    }

    private func loadImage() async {
        guard let url = url else { return }

        if let cachedImage = imageCache.get(forKey: url.absoluteString) {
            self.image = cachedImage
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let downloadedImage = NSImage(data: data) {
                imageCache.set(downloadedImage, forKey: url.absoluteString)
                self.image = downloadedImage
            }
        } catch {
            print("Failed to load image from \(url): \(error.localizedDescription)")
        }
    }
}