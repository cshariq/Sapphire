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

    static func isActive(toolID: String, pid: pid_t, workingDirectory: String?) -> Bool? {
        switch toolID {
        case DevToolCatalog.claude.id:
            return claudeIsActive(pid: pid, workingDirectory: workingDirectory)
        case DevToolCatalog.codex.id:
            return codexIsActive(workingDirectory: workingDirectory)
        default:
            return nil
        }
    }

    // MARK: - Claude

    static let claudeConfigRoots: [URL] = {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var roots: [URL] = []
        if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            roots.append(URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true))
        }
        roots.append(home.appending(path: ".claude", directoryHint: .isDirectory))
        roots.append(home.appending(path: ".config/claude", directoryHint: .isDirectory))
        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }()

    private struct ClaudeRegistryRecord {
        var path: String
        var modified: Date
        var sessionID: String?
        var status: String?
        var cwd: String?
    }

    private static var registryCache: [pid_t: ClaudeRegistryRecord] = [:]

    private static func claudeIsActive(pid: pid_t, workingDirectory: String?) -> Bool? {
        if let record = claudeRegistryRecord(for: pid) {
            if let status = record.status { return status == "busy" }

            if let sessionID = record.sessionID,
               let directory = record.cwd ?? workingDirectory,
               let slug = projectSlug(for: directory) {
                for root in claudeConfigRoots {
                    let log = root.appending(path: "projects/\(slug)/\(sessionID).jsonl").path
                    if let modified = modificationDate(atPath: log) {
                        return Date().timeIntervalSince(modified) <= activityWindow
                    }
                }
            }
            return nil
        }

        guard let workingDirectory, let slug = projectSlug(for: workingDirectory) else { return nil }
        for root in claudeConfigRoots {
            let directory = root.appending(path: "projects/\(slug)", directoryHint: .isDirectory)
            if let modified = newestModification(in: directory) {
                return Date().timeIntervalSince(modified) <= activityWindow
            }
        }
        return nil
    }

    private static func claudeRegistryRecord(for pid: pid_t) -> ClaudeRegistryRecord? {
        lock.lock()
        let cached = registryCache[pid]
        lock.unlock()

        for root in claudeConfigRoots {
            let path = root.appending(path: "sessions/\(pid).json").path
            guard let modified = modificationDate(atPath: path) else { continue }
            if let cached, cached.path == path, cached.modified == modified { return cached }

            guard let parsed = parseClaudeRegistry(atPath: path, pid: pid, modified: modified) else {
                return cached?.path == path ? cached : nil
            }
            lock.lock()
            registryCache[pid] = parsed
            lock.unlock()
            return parsed
        }

        if cached != nil {
            lock.lock()
            registryCache.removeValue(forKey: pid)
            lock.unlock()
        }
        return nil
    }

    private static func parseClaudeRegistry(atPath path: String, pid: pid_t, modified: Date) -> ClaudeRegistryRecord? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count < 1 << 16,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let recordedPID = json["pid"] as? Int, recordedPID == Int(pid) else { return nil }
        if let domain = json["pidDomain"] as? String, domain != "darwin" { return nil }
        guard isRunning(pid) else { return nil }

        return ClaudeRegistryRecord(
            path: path,
            modified: modified,
            sessionID: (json["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            status: json["status"] as? String,
            cwd: (json["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func isRunning(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    static func projectSlug(for path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var units: [UInt16] = []
        units.reserveCapacity(path.utf16.count)
        let dash = UInt16(UInt8(ascii: "-"))
        for unit in path.utf16 {
            let isAlphanumeric = (0x30...0x39).contains(unit)
                || (0x41...0x5A).contains(unit)
                || (0x61...0x7A).contains(unit)
            units.append(isAlphanumeric ? unit : dash)
        }
        let slug = String(decoding: units, as: UTF16.self)
        return slug.isEmpty ? nil : slug
    }

    // MARK: - Codex

    static let codexSessionsRoot: URL = {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
                .appending(path: "sessions", directoryHint: .isDirectory)
        }
        return home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
    }()

    private static let codexDayWindow = 3

    private struct CodexRollout {
        var inode: UInt64
        var created: Date
        var cwd: String?
    }

    private static var codexRolloutCache: [String: CodexRollout] = [:]
    private static var codexListing: (listed: CFAbsoluteTime, files: [String])?

    private static func codexIsActive(workingDirectory: String?) -> Bool? {
        guard let workingDirectory else { return nil }
        let wanted = normalizedPath(workingDirectory)

        var newest: Date?
        for file in codexRolloutFiles() {
            guard let rollout = codexRolloutInfo(atPath: file) else { continue }
            guard Date().timeIntervalSince(rollout.modified) <= activityWindow else { continue }
            guard codexWorkingDirectory(atPath: file, inode: rollout.inode, created: rollout.created) == wanted else {
                continue
            }
            if newest.map({ rollout.modified > $0 }) ?? true { newest = rollout.modified }
        }

        guard let newest else { return nil }
        return Date().timeIntervalSince(newest) <= activityWindow
    }

    static func newestCodexRollout(forWorkingDirectory workingDirectory: String) -> String? {
        let wanted = normalizedPath(workingDirectory)
        var newest: (path: String, modified: Date)?
        for file in codexRolloutFiles() {
            guard let rollout = codexRolloutInfo(atPath: file) else { continue }
            if let newest, rollout.modified <= newest.modified { continue }
            guard codexWorkingDirectory(atPath: file, inode: rollout.inode, created: rollout.created) == wanted else {
                continue
            }
            newest = (file, rollout.modified)
        }
        return newest?.path
    }

    static func recentCodexRollouts() -> [String] { codexRolloutFiles() }

    private static func codexRolloutFiles() -> [String] {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let listing = codexListing
        lock.unlock()
        if let listing, now - listing.listed < relistInterval { return listing.files }

        let manager = FileManager.default
        func sortedNames(in directory: URL) -> [String] {
            ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted(by: >)
        }

        var days: [URL] = []
        for year in sortedNames(in: codexSessionsRoot) where days.count < codexDayWindow {
            let yearURL = codexSessionsRoot.appending(path: year, directoryHint: .isDirectory)
            for month in sortedNames(in: yearURL) where days.count < codexDayWindow {
                let monthURL = yearURL.appending(path: month, directoryHint: .isDirectory)
                for day in sortedNames(in: monthURL) where days.count < codexDayWindow {
                    days.append(monthURL.appending(path: day, directoryHint: .isDirectory))
                }
            }
        }

        var files: [String] = []
        for day in days {
            for name in sortedNames(in: day) where name.hasSuffix(".jsonl") {
                files.append(day.appending(path: name).path)
            }
        }

        lock.lock()
        codexListing = (listed: now, files: files)
        let live = Set(files)
        codexRolloutCache = codexRolloutCache.filter { live.contains($0.key) }
        lock.unlock()
        return files
    }

    private static func codexRolloutInfo(atPath path: String) -> (modified: Date, inode: UInt64, created: Date)? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return (date(from: info.st_mtimespec), UInt64(info.st_ino), date(from: info.st_birthtimespec))
    }

    private static func codexWorkingDirectory(atPath path: String, inode: UInt64, created: Date) -> String? {
        lock.lock()
        let cached = codexRolloutCache[path]
        lock.unlock()
        if let cached, cached.inode == inode, cached.created == created { return cached.cwd }

        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64 * 1024), !head.isEmpty else { return nil }

        let newline = UInt8(ascii: "\n")
        let line = head.firstIndex(of: newline).map { head[head.startIndex..<$0] } ?? head[...]
        guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            return nil
        }

        let payload = json["payload"] as? [String: Any]
        let recorded = (payload?["cwd"] as? String) ?? (json["cwd"] as? String)
        let cwd = recorded.flatMap { $0.isEmpty ? nil : normalizedPath($0) }

        lock.lock()
        codexRolloutCache[path] = CodexRollout(inode: inode, created: created, cwd: cwd)
        lock.unlock()
        return cwd
    }

    private static func normalizedPath(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/")
            ? String(standardized.dropLast()) : standardized
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
        return date(from: info.st_mtimespec)
    }

    private static func date(from time: timespec) -> Date {
        Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
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