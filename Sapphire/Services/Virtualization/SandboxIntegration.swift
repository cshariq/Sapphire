//
//  SandboxIntegration.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import AppKit
import Foundation

private enum SapphireVMLifecycleContract {
    static let schemaVersion = 1
    static let appGroupIdentifier = "group.com.cshariq.sapphire"
    static let writerBundleIdentifier = "com.cshariq.sandbox"
    static let wakeNotification = Notification.Name(
        "com.cshariq.sandbox.lifecycleSnapshotDidChange"
    )
    static let maximumSnapshotSize = 32 * 1_024
    static let integrationDirectoryName = "SandboxIntegration"
    static let snapshotFilename = "latest-lifecycle-v1.json"
    static let maximumVMNameLength = 80
    static let maximumDetailLength = 240
    static let maximumDeepLinkLength = 2_048
    static let maximumEventAge: TimeInterval = 10 * 60
    static let maximumFutureSkew: TimeInterval = 5 * 60
}

struct SapphireVMLifecycleSnapshot: Codable {
    enum State: String, Codable {
        case created
        case preparing
        case starting
        case running
        case pausing
        case paused
        case resuming
        case installing
        case saving
        case restoring
        case stopping
        case stopped
        case failed

        var displayName: String {
            switch self {
            case .created: return "Created"
            case .preparing: return "Preparing"
            case .starting: return "Starting"
            case .running: return "Running"
            case .pausing: return "Pausing"
            case .paused: return "Paused"
            case .resuming: return "Resuming"
            case .installing: return "Installing"
            case .saving: return "Saving"
            case .restoring: return "Restoring"
            case .stopping: return "Stopping"
            case .stopped: return "Stopped"
            case .failed: return "Needs attention"
            }
        }
    }

    let schemaVersion: Int
    let writerBundleIdentifier: String
    let eventID: UUID
    let virtualMachineID: UUID
    let virtualMachineName: String
    let state: State
    let detail: String?
    let occurredAt: Date

    func isValid(at now: Date) -> Bool {
        let age = now.timeIntervalSince(occurredAt)
        return schemaVersion == SapphireVMLifecycleContract.schemaVersion
            && writerBundleIdentifier == SapphireVMLifecycleContract.writerBundleIdentifier
            && !virtualMachineName.isEmpty
            && virtualMachineName.count <= SapphireVMLifecycleContract.maximumVMNameLength
            && (detail?.count ?? 0) <= SapphireVMLifecycleContract.maximumDetailLength
            && age <= SapphireVMLifecycleContract.maximumEventAge
            && age >= -SapphireVMLifecycleContract.maximumFutureSkew
    }
}

@MainActor
final class SandboxIntegration {
    static let shared = SandboxIntegration()

    private enum ForwardedAction: String {
        case open
        case start
        case pause
        case resume
        case gracefulStop = "graceful-stop"
    }

    private static let lastPresentedEventIDKey = "sapphire.vm.lastPresentedLifecycleEventID"

    private var wakeObserver: NSObjectProtocol?
    private var lastPresentedEventID: UUID?
    private var appIcon: NSImage? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: SapphireVMLifecycleContract.writerBundleIdentifier
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    private init() {
        lastPresentedEventID = UserDefaults.standard
            .string(forKey: Self.lastPresentedEventIDKey)
            .flatMap(UUID.init(uuidString:))
    }

    func start() {
        guard wakeObserver == nil else { return }

        wakeObserver = DistributedNotificationCenter.default().addObserver(
            forName: SapphireVMLifecycleContract.wakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.consumeLatestSnapshot()
            }
        }

        consumeLatestSnapshot()
    }

    func stop() {
        guard let wakeObserver else { return }
        DistributedNotificationCenter.default().removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    @discardableResult
    func forwardValidatedDeepLink(_ sourceURL: URL) -> Bool {
        guard let destinationURL = Self.validatedDestinationURL(for: sourceURL),
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: SapphireVMLifecycleContract.writerBundleIdentifier
              ) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [destinationURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, _ in }
        return true
    }

    private func consumeLatestSnapshot() {
        guard let snapshot = Self.loadLatestSnapshot(at: Date()) else {
            clearPresentedSnapshotIfNeeded()
            return
        }
        guard snapshot.eventID != lastPresentedEventID else {
            return
        }

        let name = Self.sanitizedText(
            snapshot.virtualMachineName,
            maximumLength: SapphireVMLifecycleContract.maximumVMNameLength
        )
        guard !name.isEmpty else { return }

        let detail = snapshot.detail.map {
            Self.sanitizedText(
                $0,
                maximumLength: SapphireVMLifecycleContract.maximumDetailLength
            )
        }.flatMap { $0.isEmpty ? nil : $0 }
        let body = detail ?? "\(name) is \(snapshot.state.displayName.lowercased())."

        NotificationManager.shared.latestNotification = NotificationPayload(
            id: "sandbox-\(snapshot.eventID.uuidString)",
            appIdentifier: SapphireVMLifecycleContract.writerBundleIdentifier,
            title: "Sapphire VM · \(snapshot.state.displayName)",
            body: body,
            date: snapshot.occurredAt,
            appIcon: appIcon
        )

        lastPresentedEventID = snapshot.eventID
        UserDefaults.standard.set(
            snapshot.eventID.uuidString,
            forKey: Self.lastPresentedEventIDKey
        )
    }

    private func clearPresentedSnapshotIfNeeded() {
        guard let notification = NotificationManager.shared.latestNotification,
              notification.appIdentifier == SapphireVMLifecycleContract.writerBundleIdentifier,
              notification.id.hasPrefix("sandbox-") else {
            return
        }
        NotificationManager.shared.latestNotification = nil
    }

    private static func loadLatestSnapshot(
        at now: Date,
        fileManager: FileManager = .default
    ) -> SapphireVMLifecycleSnapshot? {
        loadLatestSnapshot(
            from: candidateSnapshotURLs(fileManager: fileManager),
            at: now,
            fileManager: fileManager
        )
    }

    static func loadLatestSnapshot(
        from sourceURLs: [URL],
        at now: Date,
        fileManager: FileManager = .default
    ) -> SapphireVMLifecycleSnapshot? {
        var newestSnapshot: SapphireVMLifecycleSnapshot?

        for sourceURL in sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path),
                  let values = try? sourceURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let fileSize = values.fileSize,
                  fileSize >= 0,
                  fileSize <= SapphireVMLifecycleContract.maximumSnapshotSize,
                  let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe),
                  data.count <= SapphireVMLifecycleContract.maximumSnapshotSize else {
                continue
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            if let snapshot = try? decoder.decode(
                SapphireVMLifecycleSnapshot.self,
                from: data
            ), snapshot.isValid(at: now),
               newestSnapshot == nil || snapshot.occurredAt > newestSnapshot!.occurredAt {
                newestSnapshot = snapshot
            }
        }
        return newestSnapshot
    }

    private static func candidateSnapshotURLs(
        fileManager: FileManager
    ) -> [URL] {
        let groupContainer = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SapphireVMLifecycleContract.appGroupIdentifier
        )
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first

        return candidateSnapshotURLs(
            groupContainer: groupContainer,
            applicationSupport: applicationSupport
        )
    }

    static func candidateSnapshotURLs(
        groupContainer: URL?,
        applicationSupport: URL?
    ) -> [URL] {
        let integrationDirectory: URL?
        if let groupContainer {
            integrationDirectory = groupContainer.appendingPathComponent(
                SapphireVMLifecycleContract.integrationDirectoryName,
                isDirectory: true
            )
        } else {
            integrationDirectory = applicationSupport?
                .appendingPathComponent("Sapphire", isDirectory: true)
                .appendingPathComponent(
                    SapphireVMLifecycleContract.integrationDirectoryName,
                    isDirectory: true
                )
        }

        guard let integrationDirectory else { return [] }
        return [integrationDirectory.appendingPathComponent(
            SapphireVMLifecycleContract.snapshotFilename,
            isDirectory: false
        )]
    }

    static func validatedDestinationURL(for sourceURL: URL) -> URL? {
        guard sourceURL.absoluteString.utf8.count
                <= SapphireVMLifecycleContract.maximumDeepLinkLength,
              let source = URLComponents(
                url: sourceURL,
                resolvingAgainstBaseURL: false
              ),
              source.scheme?.lowercased() == "sapphire",
              source.host?.lowercased() == "vm",
              source.user == nil,
              source.password == nil,
              source.port == nil,
              source.fragment == nil,
              source.percentEncodedPath.hasPrefix("/"),
              !source.percentEncodedPath.dropFirst().contains("/"),
              let action = ForwardedAction(
                rawValue: String(source.percentEncodedPath.dropFirst()).lowercased()
              ) else {
            return nil
        }

        let queryItems = source.queryItems ?? []
        guard queryItems.count <= 1,
              queryItems.allSatisfy({ $0.name == "vm" }) else {
            return nil
        }

        var canonicalVMID: String?
        if let value = queryItems.first?.value {
            guard let id = UUID(uuidString: value) else { return nil }
            canonicalVMID = id.uuidString
        } else if !queryItems.isEmpty {
            return nil
        }
        guard action == .open || canonicalVMID != nil else { return nil }

        var destination = URLComponents()
        destination.scheme = "sandbox"
        destination.host = action.rawValue
        if let canonicalVMID {
            destination.queryItems = [
                URLQueryItem(name: "vm", value: canonicalVMID),
            ]
        }
        return destination.url
    }

    private static func sanitizedText(
        _ value: String,
        maximumLength: Int
    ) -> String {
        let visibleScalars = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.illegalCharacters.contains(scalar) {
                return " "
            }
            return Character(String(scalar))
        }
        let collapsed = String(visibleScalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(maximumLength))
    }
}