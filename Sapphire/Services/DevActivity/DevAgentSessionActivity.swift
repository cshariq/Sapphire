//
//  DevAgentSessionActivity.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12
//

import Foundation

enum DevAgentSessionActivity {

    static let activityWindow: TimeInterval = 45

    private struct CacheEntry {
        var checked: CFAbsoluteTime
        var modified: Date?
        var newestFile: String?
        var directoryModified: Date?
        var listed: CFAbsoluteTime
    }

    private static var cache: [String: CacheEntry] = [:]
    private static let cacheLifetime: CFAbsoluteTime = 2
    private static let relistInterval: CFAbsoluteTime = 15
    private static let lock = NSLock()

    static func isActive(toolID: String, workingDirectory: String?) -> Bool? {
        guard let directory = sessionDirectory(toolID: toolID, workingDirectory: workingDirectory) else {
            return nil
        }
        guard let modified = newestModification(in: directory) else { return nil }
        return Date().timeIntervalSince(modified) <= activityWindow
    }

    // MARK: - Locations

    private static func sessionDirectory(toolID: String, workingDirectory: String?) -> URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory())

        switch toolID {
        case DevToolCatalog.claude.id:
            guard let workingDirectory, let slug = projectSlug(for: workingDirectory) else { return nil }
            return home.appending(path: ".claude/projects/\(slug)", directoryHint: .isDirectory)

        case DevToolCatalog.codex.id:
            return home.appending(path: ".codex/sessions", directoryHint: .isDirectory)

        default:
            return nil
        }
    }

    private static func projectSlug(for path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let slug = path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        return slug.isEmpty ? nil : slug
    }

    // MARK: - Filesystem

    private static func newestModification(in directory: URL) -> Date? {
        let key = directory.path
        let now = CFAbsoluteTimeGetCurrent()

        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached, now - cached.checked < cacheLifetime {
            return cached.modified
        }

        let directoryModified = modificationDate(atPath: key)
        let entry: CacheEntry

        if var reused = cached,
           let file = reused.newestFile,
           directoryModified == reused.directoryModified,
           let fileModified = modificationDate(atPath: file),
           Date().timeIntervalSince(fileModified) <= activityWindow || now - reused.listed < relistInterval {
            reused.checked = now
            reused.modified = fileModified
            entry = reused
        } else {
            let newest = scanNewestFile(in: directory, depth: 0)
            entry = CacheEntry(
                checked: now,
                modified: newest?.modified,
                newestFile: newest?.path,
                directoryModified: directoryModified,
                listed: now
            )
        }

        lock.lock()
        cache[key] = entry
        lock.unlock()

        return entry.modified
    }

    private static func modificationDate(atPath path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let time = info.st_mtimespec
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
    }

    private static func scanNewestFile(in directory: URL, depth: Int) -> (path: String, modified: Date)? {
        guard depth <= 3 else { return nil }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newestFile: (path: String, modified: Date)?
        var directories: [(URL, Date)] = []

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  let modified = values.contentModificationDate else { continue }

            if values.isDirectory == true {
                directories.append((entry, modified))
            } else if newestFile.map({ modified > $0.modified }) ?? true {
                newestFile = (entry.path, modified)
            }
        }

        if let newest = directories.max(by: { $0.1 < $1.1 }),
           let deeper = scanNewestFile(in: newest.0, depth: depth + 1),
           newestFile.map({ deeper.modified > $0.modified }) ?? true {
            newestFile = deeper
        }

        return newestFile
    }
}