//
//  DeviceIconCache.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit

@MainActor
final class DeviceIconCache {
    static let shared = DeviceIconCache()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let maxSize: Int

    init(maxSize: Int = 30) {
        self.maxSize = maxSize
    }

    func icon(for uid: String, loader: () -> NSImage?) -> NSImage? {
        if let cached = cache[uid] {
            moveToFront(uid)
            return cached
        }
        guard let icon = loader() else { return nil }
        insert(uid, icon)
        return icon
    }

    func clear() {
        cache.removeAll()
        order.removeAll()
    }

    private func moveToFront(_ uid: String) {
        order.removeAll { $0 == uid }
        order.insert(uid, at: 0)
    }

    private func insert(_ uid: String, _ icon: NSImage) {
        cache[uid] = icon
        order.insert(uid, at: 0)

        while order.count > maxSize {
            if let removed = order.popLast() {
                cache.removeValue(forKey: removed)
            }
        }
    }
}