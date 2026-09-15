//
//  ArchiveExtractor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Settings models

enum ArchiveExtractionMode: String, Codable, CaseIterable, Identifiable {
    case smart, folder, inPlace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smart: "Smart"
        case .folder: "Always into a Folder"
        case .inPlace: "In Place"
        }
    }
}

enum ArchivePostExtractAction: String, Codable, CaseIterable, Identifiable {
    case reveal, open, none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reveal: "Reveal in Finder"
        case .open: "Open Folder"
        case .none: "Nothing"
        }
    }

    var systemImage: String {
        switch self {
        case .reveal: "folder"
        case .open: "arrow.up.doc"
        case .none: "xmark.circle"
        }
    }
}

struct ArchiveDefaultHandlerStatus: Equatable {
    let matchingTypeCount: Int
    let totalTypeCount: Int

    var hasAnyMatch: Bool { matchingTypeCount > 0 }
    var isComplete: Bool { totalTypeCount > 0 && matchingTypeCount == totalTypeCount }
}

// MARK: - Manager

@MainActor
final class ArchiveExtractor: ObservableObject {

    static let shared = ArchiveExtractor()

    @Published private(set) var isProcessing = false

    @Published private(set) var currentActivity: String?

    @Published private(set) var completedExtractCount = 0

    @Published private(set) var currentTransferTask: FileTransferTask?

    private let settingsModel = SettingsModel.shared
    private var pendingURLs: [URL] = []
    private var isDrainingQueue = false

    static let defaultArchiveContentTypeIdentifiers: [String] = [
        "public.zip-archive",
        "public.tar-archive",
        "org.7-zip.7-zip-archive",
        "com.rarlab.rar-archive",
        "org.gnu.gnu-zip-archive",
        "public.bzip2-archive",
        "org.tukaani.xz-archive",
        "public.cpio-archive",
        "public.iso-image"
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "jar", "xpi", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lzma",
        "7z", "rar", "iso", "cpio", "cab", "z"
    ]

    private init() {}

    // MARK: - Detection

    static func isArchiveURL(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Default handler registration

    static func evaluateDefaultHandlerStatus(
        bundleIdentifier: String,
        handlerBundleIdentifiers: [String?]
    ) -> ArchiveDefaultHandlerStatus {
        let matchingTypeCount = handlerBundleIdentifiers.reduce(into: 0) { count, handler in
            if handler?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
                count += 1
            }
        }
        return ArchiveDefaultHandlerStatus(
            matchingTypeCount: matchingTypeCount,
            totalTypeCount: handlerBundleIdentifiers.count
        )
    }

    static func defaultArchiveHandlerStatus() -> ArchiveDefaultHandlerStatus {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return ArchiveDefaultHandlerStatus(
                matchingTypeCount: 0,
                totalTypeCount: defaultArchiveContentTypeIdentifiers.count
            )
        }

        let handlerBundleIDs = defaultArchiveContentTypeIdentifiers.map { identifier in
            UTType(identifier).flatMap(defaultApplicationBundleIdentifier)
        }
        return evaluateDefaultHandlerStatus(
            bundleIdentifier: bundleID,
            handlerBundleIdentifiers: handlerBundleIDs
        )
    }

    static func isDefaultArchiveHandler() -> Bool {
        defaultArchiveHandlerStatus().isComplete
    }

    @discardableResult
    static func setAsDefaultArchiveHandler() async -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }

        var allSucceeded = true
        for identifier in defaultArchiveContentTypeIdentifiers {
            guard let contentType = UTType(identifier) else {
                allSucceeded = false
                continue
            }
            if defaultApplicationBundleIdentifier(for: contentType)?
                .caseInsensitiveCompare(bundleID) == .orderedSame {
                continue
            }

            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: Bundle.main.bundleURL,
                    toOpen: contentType
                )
            } catch {
                allSucceeded = false
            }
        }
        return allSucceeded
    }

    private static func defaultApplicationBundleIdentifier(for contentType: UTType) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: contentType)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    // MARK: - Entry points

    func handleOpenURLs(_ urls: [URL]) {
        let archives = urls.filter(Self.isArchiveURL)
        guard !archives.isEmpty else { return }

        guard settingsModel.settings.archiveExtractorEnabled else {
            handOffToSystem(archives)
            return
        }

        pendingURLs.append(contentsOf: archives)
        drainQueueIfNeeded()
    }

    func extractArchives(_ urls: [URL]) {
        handleOpenURLs(urls)
    }

    private func handOffToSystem(_ urls: [URL]) {
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    private func drainQueueIfNeeded() {
        guard !isDrainingQueue else { return }
        isDrainingQueue = true
        isProcessing = true

        Task { @MainActor in
            while !pendingURLs.isEmpty {
                let url = pendingURLs.removeFirst()
                await extract(url)
            }
            isDrainingQueue = false
            isProcessing = false
            currentActivity = nil
        }
    }

    // MARK: - Single archive pipeline

    private func extract(_ url: URL) async {
        let archiveName = url.lastPathComponent
        currentActivity = "Preparing \(archiveName)…"

        await requestNotificationAuthorizationIfNeeded()

        guard FileManager.default.fileExists(atPath: url.path) else {
            await notify(title: "Sapphire Archives", body: "\(archiveName) could not be found.")
            return
        }

        currentActivity = "Reading \(archiveName)…"

        let parent = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let mode = settingsModel.settings.archiveExtractionMode

        let listing = await listEntries(in: url)
        let destination: URL
        switch mode {
        case .inPlace:
            destination = parent
        case .folder:
            destination = parent.appendingPathComponent(baseName)
        case .smart:
            destination = Self.topLevelCount(listing) > 1
                ? parent.appendingPathComponent(baseName)
                : parent
        }

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            await notify(title: "Sapphire Archives", body: "Could not create \(destination.lastPathComponent) to extract \(archiveName).")
            return
        }

        currentActivity = "Extracting \(archiveName)…"

        let archiveAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let archiveBytes = (archiveAttrs?[.size] as? NSNumber)?.int64Value ?? 0
        let totalEntries = listing.count

        var result = await runExtraction(url: url, destination: destination, passphrase: nil, totalEntries: totalEntries, totalBytes: archiveBytes)

        if !result.success, result.needsPassphrase, settingsModel.settings.archivePromptForPasswords {
            if let password = await promptForPassword(archiveName: archiveName) {
                result = await runExtraction(url: url, destination: destination, passphrase: password, totalEntries: totalEntries, totalBytes: archiveBytes)
            }
        }

        guard result.success else {
            currentTransferTask = nil
            await notify(
                title: "Sapphire Archives",
                body: "Could not extract \(archiveName). It may be damaged, unsupported, or password protected."
            )
            return
        }

        markExtractionComplete()
        completedExtractCount += 1
        currentActivity = nil

        if settingsModel.settings.archiveDeleteAfterExtract {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }

        switch settingsModel.settings.archivePostExtractAction {
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        case .open:
            NSWorkspace.shared.open(destination)
        case .none:
            break
        }

        await notify(title: "Sapphire Archives", body: "\(archiveName) extracted successfully.")
    }

    // MARK: - Extraction

    private struct ExtractResult {
        let success: Bool
        let needsPassphrase: Bool
    }

    private func runExtraction(url: URL, destination: URL, passphrase: String?, totalEntries: Int, totalBytes: Int64) async -> ExtractResult {
        let startDate = Date()
        let archiveName = url.lastPathComponent

        currentTransferTask = FileTransferTask(
            fileURL: url,
            fileName: archiveName,
            destinationURL: destination,
            currentSize: 0,
            totalSize: totalBytes > 0 ? totalBytes : nil,
            speed: 0,
            lastChangeDate: startDate,
            isComplete: false,
            sourceType: .archiveExtraction
        )

        guard totalEntries > 0 else {
            return await runExtractionProcess(url: url, destination: destination, passphrase: passphrase, onOutputLine: nil)
        }

        let counter = ExtractionLineCounter()
        let onLine: @Sendable (String) -> Void = { [weak self] _ in
            guard let self else { return }
            let done = counter.increment()
            let fraction = min(1.0, Double(done) / Double(totalEntries))
            let bytesDone = Int64(Double(totalBytes) * fraction)
            let elapsed = Date().timeIntervalSince(startDate)
            let speed = elapsed > 0 ? Double(bytesDone) / elapsed : 0
            Task { @MainActor in
                self.updateExtractionProgress(bytesDone: bytesDone, speed: speed)
            }
        }
        return await runExtractionProcess(url: url, destination: destination, passphrase: passphrase, onOutputLine: onLine)
    }

    private func runExtractionProcess(url: URL, destination: URL, passphrase: String?, onOutputLine: (@Sendable (String) -> Void)?) async -> ExtractResult {

        if url.pathExtension.lowercased() == "zip", passphrase == nil {
            let result = await ProcessRunner.runCapturing(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", "-v", url.path, destination.path],
                timeout: 900,
                onOutputLine: onOutputLine
            )
            if result.exitStatus == 0 {
                return ExtractResult(success: true, needsPassphrase: false)
            }
        }

        var args: [String] = []
        if let passphrase, !passphrase.isEmpty {
            args += ["--passphrase", passphrase]
        }
        args += ["-xvf", url.path, "-C", destination.path]

        let result = await ProcessRunner.runCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/bsdtar"),
            arguments: args,
            timeout: 900,
            onOutputLine: onOutputLine
        )

        let stderr = result.standardError.lowercased()
        let needsPassphrase = result.exitStatus != 0 && (
            stderr.contains("passphrase")
                || stderr.contains("password")
                || stderr.contains("encrypted")
        )

        if result.exitStatus == 0 {
            return ExtractResult(success: true, needsPassphrase: false)
        }
        return ExtractResult(success: false, needsPassphrase: needsPassphrase)
    }

    private func updateExtractionProgress(bytesDone: Int64, speed: Double) {
        guard var task = currentTransferTask else { return }
        task.currentSize = bytesDone
        task.speed = speed
        task.lastChangeDate = Date()
        currentTransferTask = task
    }

    private func markExtractionComplete() {
        guard var task = currentTransferTask else { return }
        task.isComplete = true
        task.currentSize = task.totalSize ?? task.currentSize
        currentTransferTask = task
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, self.currentTransferTask?.fileURL == task.fileURL else { return }
            self.currentTransferTask = nil
        }
    }

    // MARK: - Archive listing

    private func listEntries(in url: URL) async -> [String] {
        let result = await ProcessRunner.runCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/bsdtar"),
            arguments: ["-tf", url.path],
            timeout: 30
        )
        guard result.exitStatus == 0 else { return [] }
        return result.standardOutput
            .split(separator: "\n")
            .map(String.init)
    }

    private nonisolated static func topLevelCount(_ entries: [String]) -> Int {
        Set(entries.compactMap { entry -> String? in
            guard let first = entry.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first else {
                return nil
            }
            return String(first)
        }).count
    }

    // MARK: - Password prompt

    private func promptForPassword(archiveName: String) async -> String? {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "\"\(archiveName)\" is password protected"
            alert.informativeText = "Enter the password to extract this archive. Sapphire does not store it."
            alert.alertStyle = .informational

            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.placeholderString = "Password"
            alert.accessoryView = field

            alert.addButton(withTitle: "Extract")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let password = field.stringValue
                continuation.resume(returning: password.isEmpty ? nil : password)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorizationIfNeeded() async {
        guard canUseNotifications else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func notify(title: String, body: String) async {
        guard canUseNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "sapphire-archive-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Extraction Progress

    private final class ExtractionLineCounter: @unchecked Sendable {
        private var count = 0
        private let lock = NSLock()
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }
}