//
//  ClipboardSecureStore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27

import CryptoKit
import Foundation
import OSLog

nonisolated final class ClipboardSecureStore: @unchecked Sendable {
    private let directory: URL
    private let indexURL: URL
    private let legacyFileURL: URL
    private let lock = NSLock()
    private var persistedIDs: Set<String> = []
    private var reencodePending: Set<String> = []

    init(appDirectory: URL, legacyFileURL: URL) {
        directory = appDirectory.appendingPathComponent("clipboard_items", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.encrypted")
        self.legacyFileURL = legacyFileURL
    }

    // MARK: Load

    func load() -> (items: [ClipboardItem], needsMigration: Bool) {
        if let ids = readIndex() {
            var items: [ClipboardItem] = []
            items.reserveCapacity(ids.count)
            var jsonEncoded: [ClipboardItem] = []
            let plistDecoder = PropertyListDecoder()
            let jsonDecoder = JSONDecoder()
            var imagesSeen = 0
            for id in ids {
                guard let data = try? Data(contentsOf: fileURL(for: id)),
                      let decrypted = CryptoManager.shared.decrypt(data: data) else { continue }
                if decrypted.starts(with: Self.binaryPlistMagic) {
                    guard let item = try? plistDecoder.decode(ClipboardItem.self, from: decrypted) else { continue }
                    if item.kind == .image { imagesSeen += 1 }
                    items.append(imagesSeen > Self.residentImageCount ? item.withoutImageData() : item)
                } else {
                    guard let item = try? jsonDecoder.decode(ClipboardItem.self, from: decrypted) else { continue }
                    if item.kind == .image { imagesSeen += 1 }
                    items.append(imagesSeen > Self.residentImageCount ? item.withoutImageData() : item)
                    jsonEncoded.append(item)
                }
            }
            lock.lock(); persistedIDs = Set(items.map(\.id)); lock.unlock()
            Logger(subsystem: "com.cshariq.sapphire", category: "Clipboard")
                .notice("Loaded \(items.count, privacy: .public) of \(ids.count, privacy: .public) clipboard items")
            if !jsonEncoded.isEmpty { scheduleReencode(jsonEncoded) }
            return (items, false)
        }

        guard let encrypted = try? Data(contentsOf: legacyFileURL),
              let decrypted = CryptoManager.shared.decrypt(data: encrypted),
              let items = try? JSONDecoder().decode([ClipboardItem].self, from: decrypted) else {
            return ([], false)
        }
        return (items, true)
    }

    static let residentImageCount = 6

    func loadImageData(id: String) -> Data? {
        loadImageDataUnlocked(id: id)
    }

    private func loadImageDataUnlocked(id: String) -> Data? {
        guard let data = try? Data(contentsOf: fileURL(for: id)),
              let decrypted = CryptoManager.shared.decrypt(data: data) else { return nil }
        if decrypted.starts(with: Self.binaryPlistMagic) {
            return (try? PropertyListDecoder().decode(ClipboardItem.self, from: decrypted))?.imagePNGData
        }
        return (try? JSONDecoder().decode(ClipboardItem.self, from: decrypted))?.imagePNGData
    }

    func persistedIDSnapshot() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return persistedIDs
    }

    // MARK: Save

    func persist(_ snapshot: [ClipboardItem], rewriting: Set<String> = []) {
        lock.lock()
        defer { lock.unlock() }

        if snapshot.isEmpty {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: legacyFileURL)
            persistedIDs = []
            return
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ids = snapshot.map(\.id)
        let wanted = Set(ids)
        let encoder = JSONEncoder()

        for item in snapshot where !persistedIDs.contains(item.id) || rewriting.contains(item.id) {
            var toWrite = item
            if item.kind == .image, item.imagePNGData == nil, persistedIDs.contains(item.id) {
                guard let stored = loadImageDataUnlocked(id: item.id) else { continue }
                toWrite = ClipboardItem(
                    id: item.id, preview: item.preview, copiedAt: item.copiedAt, kind: item.kind,
                    textContent: item.textContent, imagePNGData: stored, fileURLString: item.fileURLString,
                    fileBookmarkData: item.fileBookmarkData, isPinned: item.isPinned, byteSize: item.byteSize,
                    contentHash: item.contentHash, isTextTruncated: item.isTextTruncated
                )
            }
            if writeItem(toWrite) {
                persistedIDs.insert(item.id)
                reencodePending.remove(item.id)
            }
        }

        for id in persistedIDs.subtracting(wanted) {
            try? FileManager.default.removeItem(at: fileURL(for: id))
            persistedIDs.remove(id)
        }

        let savedOrder = ids.filter { persistedIDs.contains($0) }
        if let json = try? encoder.encode(savedOrder),
           let encrypted = CryptoManager.shared.encrypt(data: json) {
            try? encrypted.write(to: indexURL, options: [.atomic])
        }

        if persistedIDs.isSuperset(of: wanted), FileManager.default.fileExists(atPath: legacyFileURL.path) {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
    }

    // MARK: Item encoding

    private static let binaryPlistMagic = Data("bplist".utf8)

    private static func encode(_ item: ClipboardItem) -> Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(item)
    }

    @discardableResult
    private func writeItem(_ item: ClipboardItem) -> Bool {
        guard let encoded = Self.encode(item),
              let encrypted = CryptoManager.shared.encrypt(data: encoded) else { return false }
        do {
            try encrypted.write(to: fileURL(for: item.id), options: [.atomic])
            return true
        } catch {
            print("[ClipboardSecureStore] Failed to save item: \(error)")
            return false
        }
    }

    private func scheduleReencode(_ items: [ClipboardItem]) {
        lock.lock(); reencodePending.formUnion(items.map(\.id)); lock.unlock()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            for item in items {
                self.lock.lock()
                if self.persistedIDs.contains(item.id), self.reencodePending.remove(item.id) != nil {
                    self.writeItem(item)
                }
                self.lock.unlock()
            }
        }
    }

    // MARK: Files

    private func readIndex() -> [String]? {
        guard let data = try? Data(contentsOf: indexURL),
              let decrypted = CryptoManager.shared.decrypt(data: data) else { return nil }
        return try? JSONDecoder().decode([String].self, from: decrypted)
    }

    private func fileURL(for id: String) -> URL {
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).encrypted")
    }
}

nonisolated enum ClipboardImageLoader {
    nonisolated(unsafe) static var store: ClipboardSecureStore?
    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func load(id: String) -> Data? {
        if let hit = cache.object(forKey: id as NSString) { return hit as Data }
        guard let data = store?.loadImageData(id: id) else { return nil }
        cache.setObject(data as NSData, forKey: id as NSString, cost: data.count)
        return data
    }
}