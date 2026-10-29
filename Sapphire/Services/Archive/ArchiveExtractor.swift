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
        case .smart: String(localized: "Smart")
        case .folder: String(localized: "Always into a Folder")
        case .inPlace: String(localized: "In Place")
        }
    }
}

enum ArchivePostExtractAction: String, Codable, CaseIterable, Identifiable {
    case reveal, open, none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reveal: String(localized: "Reveal in Finder")
        case .open: String(localized: "Open Folder")
        case .none: String(localized: "Nothing")
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
    private var cancellables = Set<AnyCancellable>()

    static let systemArchiveHandlers = ["com.apple.archiveutility"]

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

    private init() {
        settingsModel.changes(of: { $0.archiveExtractorEnabled })
            .sink { [weak self] enabled in
                guard enabled else { return }
                self?.reconcileDefaultHandlerIfNeeded()
            }
            .store(in: &cancellables)
    }

    func reconcileDefaultHandlerIfNeeded() {
        Task { @MainActor in
            await DefaultFileHandler.reclaimFromOtherCopies(
                Self.defaultArchiveContentTypeIdentifiers.compactMap(UTType.init)
            )
        }
    }

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

        let handlerBundleIDs = defaultArchiveContentTypeIdentifiers.map { identifier -> String? in
            guard let type = UTType(identifier) else { return nil }
            let handler = DefaultFileHandler.currentHandler(for: type)
            return DefaultFileHandler.isThisApp(handlerURL: handler.url) ? handler.bundleIdentifier : nil
        }
        return evaluateDefaultHandlerStatus(
            bundleIdentifier: bundleID,
            handlerBundleIdentifiers: handlerBundleIDs
        )
    }

    static func shadowingCopy() -> URL? {
        DefaultFileHandler.shadowingCopy(for: defaultArchiveContentTypeIdentifiers.compactMap(UTType.init))
    }

    static func isDefaultArchiveHandler() -> Bool {
        defaultArchiveHandlerStatus().isComplete
    }

    @discardableResult
    static func setAsDefaultArchiveHandler() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let types = defaultArchiveContentTypeIdentifiers.compactMap(UTType.init)
        let resolvedAll = types.count == defaultArchiveContentTypeIdentifiers.count
        return await DefaultFileHandler.claim(types) && resolvedAll
    }

    // MARK: - Entry points

    func handleOpenURLs(_ urls: [URL]) {
        let archives = urls.filter(Self.isArchiveURL)
        guard !archives.isEmpty else { return }

        guard settingsModel.current.archiveExtractorEnabled else {
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
            guard let app = DefaultFileHandler.alternativeApplication(
                for: url,
                preferredBundleIdentifiers: Self.systemArchiveHandlers
            ) else {
                Task { await notify(title: String(localized: "Sapphire Archives"), body: String(localized: "No other app can open \(url.lastPathComponent). Turn on Auto-Extract Archives to let Sapphire extract it.")) }
                continue
            }
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
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
        currentActivity = String(localized: "Preparing \(archiveName)…")

        await requestNotificationAuthorizationIfNeeded()

        guard FileManager.default.fileExists(atPath: url.path) else {
            await notify(title: String(localized: "Sapphire Archives"), body: String(localized: "\(archiveName) could not be found."))
            return
        }

        currentActivity = String(localized: "Reading \(archiveName)…")

        let parent = url.deletingLastPathComponent()
        let baseName = Self.extractionBaseName(for: url)
        let fileManager = FileManager.default

        let listing = await listEntries(in: url)

        if let listing, Self.hasUnsafeEntry(listing) {
            await notify(
                title: String(localized: "Sapphire Archives"),
                body: String(localized: "\(archiveName) was not extracted: it contains entries that would be written outside the destination folder.")
            )
            return
        }

        let intoFolder: Bool
        switch settingsModel.current.archiveExtractionMode {
        case .inPlace:
            intoFolder = listing == nil
        case .folder:
            intoFolder = true
        case .smart:
            intoFolder = listing.map { Self.topLevelCount($0) > 1 } ?? true
        }
        let displayDestination = intoFolder ? parent.appendingPathComponent(baseName, isDirectory: true) : parent

        guard let staging = try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: parent,
            create: true
        ) else {
            await notify(title: String(localized: "Sapphire Archives"), body: String(localized: "Could not prepare a temporary folder to extract \(archiveName)."))
            return
        }
        defer {
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: staging) }
        }

        currentActivity = String(localized: "Extracting \(archiveName)…")

        let archiveAttrs = try? fileManager.attributesOfItem(atPath: url.path)
        let archiveBytes = (archiveAttrs?[.size] as? NSNumber)?.int64Value ?? 0
        let totalEntries = listing?.count ?? 0
        let allowDitto = listing != nil

        var result = await runExtraction(url: url, stagingDirectory: staging, displayDestination: displayDestination, passphrase: nil, totalEntries: totalEntries, totalBytes: archiveBytes, allowDitto: allowDitto)

        if !result.success, result.needsPassphrase, settingsModel.current.archivePromptForPasswords {
            if let password = await promptForPassword(archiveName: archiveName) {
                await Task.detached(priority: .utility) {
                    try? FileManager.default.removeItem(at: staging)
                    try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                }.value
                result = await runExtraction(url: url, stagingDirectory: staging, displayDestination: displayDestination, passphrase: password, totalEntries: totalEntries, totalBytes: archiveBytes, allowDitto: allowDitto)
            }
        }

        guard result.success else {
            currentTransferTask = nil
            await notify(
                title: String(localized: "Sapphire Archives"),
                body: String(localized: "Could not extract \(archiveName). It may be damaged, unsupported, or password protected.")
            )
            return
        }

        currentActivity = String(localized: "Moving \(archiveName) into place…")

        let placement: ExtractionPlacement
        do {
            placement = try await Task.detached(priority: .userInitiated) {
                try Self.placeExtractedItems(
                    from: staging,
                    into: parent,
                    folderName: intoFolder ? baseName : nil,
                    quarantineSource: url
                )
            }.value
        } catch {
            currentTransferTask = nil
            await notify(title: String(localized: "Sapphire Archives"), body: String(localized: "Could not move the extracted files of \(archiveName) into \(parent.lastPathComponent)."))
            return
        }

        markExtractionComplete()
        completedExtractCount += 1
        currentActivity = nil

        if settingsModel.current.archiveDeleteAfterExtract {
            try? fileManager.trashItem(at: url, resultingItemURL: nil)
        }

        switch settingsModel.current.archivePostExtractAction {
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(placement.items.isEmpty ? [placement.destination] : placement.items)
        case .open:
            NSWorkspace.shared.open(placement.destination)
        case .none:
            break
        }

        await notify(title: String(localized: "Sapphire Archives"), body: String(localized: "\(archiveName) extracted successfully."))
    }

    // MARK: - Placement

    private struct ExtractionPlacement: Sendable {
        let destination: URL
        let items: [URL]
    }

    private nonisolated static func placeExtractedItems(
        from staging: URL,
        into parent: URL,
        folderName: String?,
        quarantineSource: URL
    ) throws -> ExtractionPlacement {
        let fileManager = FileManager.default
        let extracted = try fileManager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { !ignoredTopLevelEntries.contains($0.lastPathComponent) }

        let destination: URL
        if let folderName {
            destination = uniqueURL(for: parent.appendingPathComponent(folderName, isDirectory: true))
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } else {
            destination = parent
        }

        var placed: [URL] = []
        for item in extracted {
            let target = uniqueURL(for: destination.appendingPathComponent(item.lastPathComponent))
            try fileManager.moveItem(at: item, to: target)
            placed.append(target)
        }

        if folderName != nil {
            QuarantineAttribute.copy(from: [quarantineSource], to: destination, recursively: true)
        } else {
            for item in placed {
                QuarantineAttribute.copy(from: [quarantineSource], to: item, recursively: true)
            }
        }

        return ExtractionPlacement(destination: destination, items: placed)
    }

    nonisolated static func uniqueURL(for proposed: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: proposed.path) else { return proposed }
        let directory = proposed.deletingLastPathComponent()
        let ext = proposed.pathExtension
        let stem = proposed.deletingPathExtension().lastPathComponent
        var counter = 2
        while true {
            var candidate = directory.appendingPathComponent("\(stem) \(counter)")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    nonisolated static func extractionBaseName(for url: URL) -> String {
        let compressionExtensions: Set<String> = ["gz", "bz2", "xz", "zst", "lz", "lzma", "z"]
        let stripped = url.deletingPathExtension()
        if compressionExtensions.contains(url.pathExtension.lowercased()),
           stripped.pathExtension.lowercased() == "tar" {
            return stripped.deletingPathExtension().lastPathComponent
        }
        return stripped.lastPathComponent
    }

    // MARK: - Extraction

    private struct ExtractResult {
        let success: Bool
        let needsPassphrase: Bool
    }

    private func runExtraction(url: URL, stagingDirectory: URL, displayDestination: URL, passphrase: String?, totalEntries: Int, totalBytes: Int64, allowDitto: Bool) async -> ExtractResult {
        let startDate = Date()
        let archiveName = url.lastPathComponent

        currentTransferTask = FileTransferTask(
            fileURL: url,
            fileName: archiveName,
            destinationURL: displayDestination,
            currentSize: 0,
            totalSize: totalBytes > 0 ? totalBytes : nil,
            speed: 0,
            lastChangeDate: startDate,
            isComplete: false,
            sourceType: .archiveExtraction
        )

        guard totalEntries > 0 else {
            return await runExtractionProcess(url: url, destination: stagingDirectory, passphrase: passphrase, allowDitto: allowDitto, onOutputLine: nil)
        }

        let throttle = ExtractionProgressThrottle(totalEntries: totalEntries)
        let onLine: @Sendable (String) -> Void = { [weak self] _ in
            guard let self, let fraction = throttle.registerEntry() else { return }
            let bytesDone = Int64(Double(totalBytes) * fraction)
            let elapsed = Date().timeIntervalSince(startDate)
            let speed = elapsed > 0 ? Double(bytesDone) / elapsed : 0
            Task { @MainActor in
                self.updateExtractionProgress(bytesDone: bytesDone, speed: speed)
            }
        }
        return await runExtractionProcess(url: url, destination: stagingDirectory, passphrase: passphrase, allowDitto: allowDitto, onOutputLine: onLine)
    }

    private func runExtractionProcess(url: URL, destination: URL, passphrase: String?, allowDitto: Bool, onOutputLine: (@Sendable (String) -> Void)?) async -> ExtractResult {

        if allowDitto, url.pathExtension.lowercased() == "zip", passphrase == nil {
            let result = await ProcessRunner.runCapturing(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", "-V", url.path, destination.path],
                timeout: 900,
                onOutputLine: onOutputLine
            )
            if result.exitStatus == 0 {
                return ExtractResult(success: true, needsPassphrase: false)
            }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
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

    private func listEntries(in url: URL) async -> [String]? {
        let result = await ProcessRunner.runCapturing(
            executableURL: URL(fileURLWithPath: "/usr/bin/bsdtar"),
            arguments: ["-tf", url.path],
            timeout: 30
        )
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return result.standardOutput
            .split(separator: "\n")
            .map(String.init)
    }

    nonisolated static func hasUnsafeEntry(_ entries: [String]) -> Bool {
        entries.contains { entry in
            entry.hasPrefix("/")
                || entry.hasPrefix("\\")
                || entry.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..")
        }
    }

    nonisolated static let ignoredTopLevelEntries: Set<String> = ["__MACOSX", ".DS_Store"]

    nonisolated static func topLevelCount(_ entries: [String]) -> Int {
        Set(entries.compactMap { entry -> String? in
            guard let first = entry.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first else {
                return nil
            }
            let name = String(first)
            return ignoredTopLevelEntries.contains(name) ? nil : name
        }).count
    }

    // MARK: - Password prompt

    private func promptForPassword(archiveName: String) async -> String? {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Password")

        return await withCheckedContinuation { continuation in
            HelperAlertPresenter.presentModal(
                messageText: String(localized: "\"\(archiveName)\" is password protected"),
                informativeText: String(localized: "Enter the password to extract this archive. Sapphire does not store it."),
                alertStyle: .informational,
                accessoryView: field,
                buttonTitles: [String(localized: "Extract"), String(localized: "Cancel")]
            ) { index in
                let password = field.stringValue
                continuation.resume(returning: index == 0 && !password.isEmpty ? password : nil)
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

    private final class ExtractionProgressThrottle: @unchecked Sendable {
        private let totalEntries: Int
        private var count = 0
        private var lastReportedFraction = -1.0
        private var lastReportDate = Date.distantPast
        private let lock = NSLock()

        init(totalEntries: Int) {
            self.totalEntries = max(1, totalEntries)
        }

        func registerEntry() -> Double? {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            let fraction = min(1.0, Double(count) / Double(totalEntries))
            let now = Date()
            guard fraction - lastReportedFraction >= 0.01
                    || now.timeIntervalSince(lastReportDate) >= 0.1 else { return nil }
            lastReportedFraction = fraction
            lastReportDate = now
            return fraction
        }
    }
}