//
//  AppStorageModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import AppKit
import SwiftUI

struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let url: URL
    let size: Int64
    let isSystem: Bool
    let icon: NSImage
    var formattedSize: String { size.formatted(.byteCount(style: .file)) }
}

@MainActor final class InstalledAppsViewModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published var confirmingRemoval = false
    @Published private(set) var isLoading = false
    private var pendingRemoval: InstalledApp?
    var removalMessage: String { pendingRemoval.map { "\($0.name) and its application bundle will be moved to the Trash." } ?? "" }

    func scan() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            var result: [InstalledApp] = []
            var seen = Set<String>()
            for root in roots where fm.fileExists(atPath: root.path) {
                guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                for url in items where url.pathExtension == "app" {
                    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, seen.insert(id).inserted else { continue }
                    let size = (try? Self.directorySize(url, fileManager: fm)) ?? 0
                    let system = url.path.hasPrefix("/System/") || id.hasPrefix("com.apple.")
                    result.append(InstalledApp(id: id, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent, bundleIdentifier: id, url: url, size: size, isSystem: system, icon: NSWorkspace.shared.icon(forFile: url.path)))
                }
            }
            let sorted = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run { self.apps = sorted; self.isLoading = false }
        }
    }

    func requestRemoval(_ app: InstalledApp) { guard !app.isSystem else { return }; pendingRemoval = app; confirmingRemoval = true }
    func removeConfirmed() { defer { pendingRemoval = nil; confirmingRemoval = false }; guard let app = pendingRemoval else { return }; NSWorkspace.shared.recycle([app.url], completionHandler: nil) }

    private nonisolated static func directorySize(_ url: URL, fileManager: FileManager) throws -> Int64 {
        var total: Int64 = 0
        if let e = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) { for case let file as URL in e { total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } }
        return total
    }
}

struct StorageEntry: Identifiable { let id = UUID(); let name: String; let size: Int64 }

@MainActor final class StorageViewModel: ObservableObject {
    @Published private(set) var entries: [StorageEntry] = []
    @Published private(set) var total: Int64 = 0
    @Published private(set) var used: Int64 = 0
    var volumeName: String { FileManager.default.displayName(atPath: NSHomeDirectory()) }

    func refresh() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        total = Int64(values?.volumeTotalCapacity ?? 0); used = max(0, total - Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0))
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let folders = (try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let result = folders.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map { StorageEntry(name: $0.lastPathComponent, size: Self.size($0, fm)) }.sorted { $0.size > $1.size }.prefix(20)
            await MainActor.run { self.entries = Array(result) }
        }
    }
    private nonisolated static func size(_ url: URL, _ fm: FileManager) -> Int64 { guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }; return e.reduce(Int64(0)) { total, item in total + Int64((try? (item as! URL).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } }
}