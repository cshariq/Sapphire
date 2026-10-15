//
//  SettingsStorage.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import AppKit
import Combine
import Foundation

// MARK: - Publish after store

@propertyWrapper
struct StoredThenPublished<Value> {
    private var value: Value
    private let subject: CurrentValueSubject<Value, Never>

    init(wrappedValue: Value) {
        value = wrappedValue
        subject = CurrentValueSubject(wrappedValue)
    }

    @available(*, unavailable, message: "@StoredThenPublished is only available on ObservableObject classes")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    var projectedValue: Publisher { Publisher(subject: subject) }

    static subscript<Owner: ObservableObject>(
        _enclosingInstance owner: Owner,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Owner, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Owner, Self>
    ) -> Value where Owner.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { owner[keyPath: storageKeyPath].value }
        set {
            owner.objectWillChange.send()
            owner[keyPath: storageKeyPath].value = newValue
            let subject = owner[keyPath: storageKeyPath].subject
            subject.send(newValue)
        }
    }

    struct Publisher: Combine.Publisher {
        typealias Output = Value
        typealias Failure = Never

        fileprivate let subject: CurrentValueSubject<Value, Never>

        func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Never {
            subject.receive(subscriber: subscriber)
        }
    }
}

// MARK: - Payload format

enum SettingsPayloadFormat {
    static let currentSchemaVersion = 2
    static let schemaVersionKey = "settingsSchemaVersion"
    private static let stampPrefix = Data("{\"\(schemaVersionKey)\":".utf8)

    static func stamped(_ payload: Data, version: Int = currentSchemaVersion) -> Data {
        guard payload.first == UInt8(ascii: "{") else { return payload }
        var stamped = stampPrefix
        stamped.append(Data(String(version).utf8))
        if payload.count > 2 {
            stamped.append(UInt8(ascii: ","))
        }
        stamped.append(payload.dropFirst())
        return stamped
    }

    static func schemaVersion(of payload: Data) -> Int? {
        if payload.starts(with: stampPrefix) {
            var digits = ""
            for byte in payload.dropFirst(stampPrefix.count).prefix(12) {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { break }
                digits.append(Character(UnicodeScalar(byte)))
            }
            if let version = Int(digits) { return version }
        }
        guard payload.range(of: Data("\"\(schemaVersionKey)\"".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }
        return (object[schemaVersionKey] as? NSNumber)?.intValue
    }
}

// MARK: - Launch policy

struct SettingsLoadAssessment: Equatable {
    var loadedFromPayload: Bool
    var storedSchemaVersion: Int?
    var decodedTolerantly: Bool
    var migratedOnLoad: Bool
}

struct SettingsLaunchPlan: Equatable {
    var backUpOriginal: Bool
    var persistNow: Bool
    var holdUntilUserChange: Bool

    static func make(
        for assessment: SettingsLoadAssessment,
        currentSchemaVersion: Int = SettingsPayloadFormat.currentSchemaVersion
    ) -> SettingsLaunchPlan {
        guard assessment.loadedFromPayload else {
            return SettingsLaunchPlan(backUpOriginal: false, persistNow: true, holdUntilUserChange: false)
        }
        let stored = assessment.storedSchemaVersion ?? 1
        if stored > currentSchemaVersion {
            return SettingsLaunchPlan(backUpOriginal: true, persistNow: false, holdUntilUserChange: true)
        }
        let formatChanges = stored < currentSchemaVersion || assessment.decodedTolerantly
        return SettingsLaunchPlan(
            backUpOriginal: formatChanges,
            persistNow: formatChanges || assessment.migratedOnLoad,
            holdUntilUserChange: false
        )
    }
}

// MARK: - Raw payload backups

enum SettingsPayloadBackups {
    static let directoryName = "SettingsBackups"
    static let retainedCount = 5

    static var directoryURL: URL {
        SettingsPersistence.directoryURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func fileName(appVersion: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let safeVersion = appVersion.map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "_" }
        return "settings-\(String(safeVersion))-\(formatter.string(from: date)).json"
    }

    static func backupsToPrune(_ backups: [(url: URL, date: Date)], keeping count: Int = retainedCount) -> [URL] {
        guard backups.count > count else { return [] }
        return backups
            .sorted { $0.date == $1.date ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.date > $1.date }
            .dropFirst(count)
            .map(\.url)
    }

    @discardableResult
    static func save(
        _ payload: Data,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        date: Date = Date(),
        in directory: URL = directoryURL
    ) -> URL? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("[SettingsModel] Could not create settings backup folder: \(error.localizedDescription)")
            return nil
        }
        let existing = listBackups(in: directory)
        if let newest = existing.max(by: { $0.date < $1.date }),
           let data = try? Data(contentsOf: newest.url), data == payload {
            return newest.url
        }
        let url = directory.appendingPathComponent(fileName(appVersion: appVersion, date: date))
        do {
            try payload.write(to: url, options: .atomic)
        } catch {
            print("[SettingsModel] Could not back up the settings payload: \(error.localizedDescription)")
            return nil
        }
        for stale in backupsToPrune(existing + [(url, date)]) where stale != url {
            try? fileManager.removeItem(at: stale)
        }
        return url
    }

    static func listBackups(in directory: URL = directoryURL) -> [(url: URL, date: Date)] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("settings-"), url.pathExtension == "json" else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return (url, date)
        }
    }
}

// MARK: - Dock layout presets file

enum DockLayoutPresetFile {
    static let fileName = "DockLayoutPresets.json"

    static var fileURL: URL { SettingsPersistence.directoryURL.appendingPathComponent(fileName) }

    private struct Document: Codable {
        var version: Int
        var presets: [DockLayout]
    }

    enum LoadResult {
        case missing
        case loaded([DockLayout])
        case unreadable
    }

    static func load(from url: URL = fileURL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data) else {
            print("[SettingsModel] Dock layout presets file is unreadable; using the presets stored with settings.")
            return .unreadable
        }
        return .loaded(document.presets)
    }

    private static func preserveUnreadableFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        if case .loaded = load(from: url) { return true }
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent("DockLayoutPresets.unreadable-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            print("[SettingsModel] Moved the unreadable Dock layout presets file to \(aside.lastPathComponent).")
            return true
        } catch {
            print("[SettingsModel] Could not move the unreadable Dock layout presets file aside: \(error.localizedDescription)")
            return false
        }
    }

    static func write(_ presets: [DockLayout], previouslyLoaded: Bool, to url: URL = fileURL) -> Bool {
        if !previouslyLoaded, !preserveUnreadableFile(at: url) { return false }
        return write(presets, to: url)
    }

    private static func write(_ presets: [DockLayout], to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Document(version: 1, presets: presets))
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("[SettingsModel] Could not write Dock layout presets: \(error.localizedDescription)")
            return false
        }
    }

    static func merged(file: [DockLayout]?, payload: [DockLayout]) -> [DockLayout] {
        guard let file else { return payload }
        let fileIDs = Set(file.map(\.id))
        return file + payload.filter { !fileIDs.contains($0.id) }
    }
}

// MARK: - Multiple running copies

enum SettingsWriterElection {
    static func isWriter(
        bundleURL: URL,
        processIdentifier: pid_t,
        peers: [SapphireInstanceCoordination.Peer]
    ) -> Bool {
        guard !peers.isEmpty else { return true }
        let me = SapphireInstanceCoordination.Peer(bundleURL: bundleURL, processIdentifier: processIdentifier)
        let everyone = peers + [me]
        let installed = everyone.filter { SapphireInstanceCoordination.isApplicationsURL($0.bundleURL) }
        let pool = installed.isEmpty ? everyone : installed
        let winner = pool.min { lhs, rhs in
            lhs.processIdentifier != rhs.processIdentifier
                ? lhs.processIdentifier < rhs.processIdentifier
                : lhs.bundleURL.path < rhs.bundleURL.path
        }
        return winner?.processIdentifier == processIdentifier
    }
}

final class SettingsInstanceGuard {
    static let didPersistNotification = Notification.Name("com.cshariq.sapphire.settings.didPersist")
    static let instanceLaunchedNotification = Notification.Name("com.cshariq.sapphire.settings.instanceLaunched")
    static let instanceTerminatingNotification = Notification.Name("com.cshariq.sapphire.settings.instanceTerminating")

    struct Role: Equatable {
        var isWriter: Bool
        var hasPeers: Bool
    }

    private(set) var role: Role
    private let onRoleChange: (Role, Role) -> Void
    private let onPeerPersisted: () -> Void
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var terminationObserver: NSObjectProtocol?
    private static var ownPID: String { String(ProcessInfo.processInfo.processIdentifier) }

    init(onRoleChange: @escaping (_ old: Role, _ new: Role) -> Void, onPeerPersisted: @escaping () -> Void) {
        self.onRoleChange = onRoleChange
        self.onPeerPersisted = onPeerPersisted
        role = Self.evaluate(excluding: nil)
        if role.hasPeers {
            print("[SettingsModel] Another Sapphire is running; this copy \(role.isWriter ? "owns" : "will not write") settings.")
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Bundle.main.bundleIdentifier,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.reevaluate(excluding: nil)
            })
        }

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(forName: Self.didPersistNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isFromPeer(note) else { return }
            self?.onPeerPersisted()
        })
        distributedObservers.append(distributed.addObserver(forName: Self.instanceLaunchedNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isFromPeer(note) else { return }
            self?.reevaluate(excluding: nil)
        })
        distributedObservers.append(distributed.addObserver(forName: Self.instanceTerminatingNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isFromPeer(note), let pid = (note.object as? String).flatMap({ pid_t($0) }) else { return }
            self?.reevaluate(excluding: pid)
        })
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.post(Self.instanceTerminatingNotification)
        }
        Self.post(Self.instanceLaunchedNotification)
    }

    deinit {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func postDidPersist() {
        Self.post(Self.didPersistNotification)
    }

    private static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: ownPID,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static func isFromPeer(_ note: Notification) -> Bool {
        guard let sender = note.object as? String else { return false }
        return sender != ownPID
    }

    private func reevaluate(excluding departingPID: pid_t?) {
        let updated = Self.evaluate(excluding: departingPID)
        guard updated != role else { return }
        let old = role
        role = updated
        print("[SettingsModel] Sapphire copies changed; this copy \(updated.isWriter ? "now owns" : "no longer writes") settings.")
        onRoleChange(old, updated)
    }

    private static func evaluate(excluding departingPID: pid_t?) -> Role {
        let peers = SapphireInstanceCoordination.otherRunningPeers()
            .filter { $0.processIdentifier != departingPID }
        return Role(
            isWriter: SettingsWriterElection.isWriter(
                bundleURL: SapphireInstanceCoordination.currentBundleURL,
                processIdentifier: SapphireInstanceCoordination.currentProcessIdentifier,
                peers: peers
            ),
            hasPeers: !peers.isEmpty
        )
    }
}