//
//  AppUninstaller.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import AppKit
import Foundation

enum AppArtifactCategory: String, CaseIterable, Identifiable {
    case application = "Application"
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case savedState = "Saved State"
    case containers = "Containers"
    case webData = "Web Data"
    case logs = "Logs & Reports"
    case launchItems = "Launch Items"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .application: return "app.fill"
        case .applicationSupport: return "folder.fill"
        case .caches: return "archivebox.fill"
        case .preferences: return "slider.horizontal.3"
        case .savedState: return "clock.arrow.circlepath"
        case .containers: return "shippingbox.fill"
        case .webData: return "network"
        case .logs: return "doc.text.fill"
        case .launchItems: return "bolt.fill"
        case .other: return "doc.fill"
        }
    }
}

enum AppArtifactConfidence: String {
    case exact
    case shared
    case ambiguous
    case nameMatch

    var explanation: String {
        switch self {
        case .exact: return "Exact app identifier match"
        case .shared: return "Shared app-group container — review before removing"
        case .ambiguous: return "This identifier may be shared or could not be verified — review before removing"
        case .nameMatch: return "App-name match — review before removing"
        }
    }
}

enum AppIdentifierOwnership {
    case verifiedExclusive
    case shared
    case uncertain

    var isVerifiedExclusive: Bool {
        self == .verifiedExclusive
    }
}

struct AppUninstallArtifact: Identifiable, Equatable {
    let url: URL
    let category: AppArtifactCategory
    let size: Int64
    let confidence: AppArtifactConfidence
    let requiresAuthorization: Bool
    let resourceIdentifier: String?

    var id: String { url.standardizedFileURL.path }
    var formattedSize: String { size.formatted(.byteCount(style: .file)) }
    var isApplication: Bool { category == .application }
}

struct AppUninstallScanConfiguration {
    let userLibrary: URL
    let systemLibrary: URL?

    static var live: AppUninstallScanConfiguration {
        let fileManager = FileManager.default
        return AppUninstallScanConfiguration(
            userLibrary: fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true),
            systemLibrary: URL(fileURLWithPath: "/Library", isDirectory: true)
        )
    }
}

enum AppArtifactScanner {
    private static let reusableSizeLifetime: TimeInterval = 5 * 60

    private enum MatchRule: Equatable {
        case identifiers
        case identifierFiles
        case byHostIdentifierFiles
        case identifiersAndNames
        case groups
        case diagnosticReports
    }

    private struct Location {
        let relativePath: String
        let category: AppArtifactCategory
        let rule: MatchRule
    }

    private static let userLocations: [Location] = [
        .init(relativePath: "Application Support", category: .applicationSupport, rule: .identifiersAndNames),
        .init(relativePath: "Caches", category: .caches, rule: .identifiersAndNames),
        .init(relativePath: "Preferences", category: .preferences, rule: .identifierFiles),
        .init(relativePath: "Preferences/ByHost", category: .preferences, rule: .byHostIdentifierFiles),
        .init(relativePath: "SyncedPreferences", category: .preferences, rule: .identifierFiles),
        .init(relativePath: "Saved Application State", category: .savedState, rule: .identifierFiles),
        .init(relativePath: "Containers", category: .containers, rule: .identifiers),
        .init(relativePath: "Group Containers", category: .containers, rule: .groups),
        .init(relativePath: "Application Scripts", category: .containers, rule: .groups),
        .init(relativePath: "Application Scripts", category: .containers, rule: .identifiers),
        .init(relativePath: "HTTPStorages", category: .webData, rule: .identifierFiles),
        .init(relativePath: "WebKit", category: .webData, rule: .identifiers),
        .init(relativePath: "Cookies", category: .webData, rule: .identifierFiles),
        .init(relativePath: "Logs", category: .logs, rule: .identifiersAndNames),
        .init(relativePath: "Logs/DiagnosticReports", category: .logs, rule: .diagnosticReports),
        .init(relativePath: "LaunchAgents", category: .launchItems, rule: .identifierFiles),
    ]

    private static let systemLocations: [Location] = [
        .init(relativePath: "Application Support", category: .applicationSupport, rule: .identifiers),
        .init(relativePath: "Caches", category: .caches, rule: .identifiers),
        .init(relativePath: "Preferences", category: .preferences, rule: .identifierFiles),
        .init(relativePath: "Logs", category: .logs, rule: .identifiers),
        .init(relativePath: "LaunchAgents", category: .launchItems, rule: .identifierFiles),
        .init(relativePath: "LaunchDaemons", category: .launchItems, rule: .identifierFiles),
        .init(relativePath: "PrivilegedHelperTools", category: .launchItems, rule: .identifiers),
    ]

    static func scan(
        app: InstalledApp,
        identifierOwnership: AppIdentifierOwnership = .uncertain,
        configuration: AppUninstallScanConfiguration = .live,
        fileManager: FileManager = .default
    ) -> [AppUninstallArtifact] {
        guard !Task.isCancelled,
              AppSecurityValidator.isSafeIdentifier(app.bundleIdentifier) else { return [] }

        let metadata = trustedMetadata(for: app.url, primaryIdentifier: app.bundleIdentifier, fileManager: fileManager)
        let signatureIdentity = try? AppSecurityValidator.identity(at: app.url)
        let hasVerifiedTeam = signatureIdentity?.teamIdentifier?.isEmpty == false
        let identifierConfidences = Dictionary(
            uniqueKeysWithValues: metadata.identifiers.map { identifier in
                (
                    identifier,
                    identifierConfidence(
                        isPrimary: identifier == app.bundleIdentifier,
                        ownership: identifierOwnership,
                        hasVerifiedTeam: hasVerifiedTeam
                    )
                )
            }
        )
        let groups = metadata.appGroups
        let names = trustedNames(for: app)
        var artifacts: [AppUninstallArtifact] = []

        if fileManager.fileExists(atPath: app.url.path) {
            let currentResourceIdentifier = AppUninstaller.currentResourceIdentifier(at: app.url)
            let currentBundle = Bundle(url: app.url)
            let currentVersion = currentBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? currentBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                ?? "—"
            let measuredSizeAge = Date().timeIntervalSince(app.sizeMeasuredAt)
            let canReuseMeasuredSize = app.isSystem
                || (app.size > 0
                    && app.resourceIdentifier != nil
                    && currentResourceIdentifier == app.resourceIdentifier
                    && currentVersion == app.version
                    && measuredSizeAge >= 0
                    && measuredSizeAge < reusableSizeLifetime)
            artifacts.append(makeArtifact(
                at: app.url,
                category: .application,
                confidence: .exact,
                fileManager: fileManager,
                knownSize: canReuseMeasuredSize ? app.size : nil,
                knownResourceIdentifier: app.resourceIdentifier
            ))
        }

        appendMatches(
            below: configuration.userLibrary,
            locations: userLocations,
            identifierConfidences: identifierConfidences,
            groups: groups,
            names: names,
            fileManager: fileManager,
            to: &artifacts
        )
        guard !Task.isCancelled else { return [] }
        if let systemLibrary = configuration.systemLibrary {
            appendMatches(
                below: systemLibrary,
                locations: systemLocations,
                identifierConfidences: identifierConfidences,
                groups: [],
                names: [],
                fileManager: fileManager,
                to: &artifacts
            )
        }
        guard !Task.isCancelled else { return [] }

        var seen = Set<String>()
        return artifacts
            .filter { seen.insert($0.id).inserted }
            .sorted {
                if $0.isApplication != $1.isApplication { return !$0.isApplication }
                if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
                return $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
            }
    }

    static func identifierConfidence(
        isPrimary: Bool,
        ownership: AppIdentifierOwnership,
        hasVerifiedTeam: Bool
    ) -> AppArtifactConfidence {
        isPrimary && ownership.isVerifiedExclusive && hasVerifiedTeam ? .exact : .ambiguous
    }

    private static func trustedMetadata(
        for appURL: URL,
        primaryIdentifier: String,
        fileManager: FileManager
    ) -> (identifiers: Set<String>, appGroups: Set<String>) {
        var identifiers: Set<String> = [primaryIdentifier]
        var groups = AppSecurityValidator.applicationGroups(at: appURL)

        guard (try? AppSecurityValidator.identity(at: appURL)) != nil else {
            return (identifiers, groups)
        }

        let nestedRoots = [
            "Contents/Library/LoginItems",
            "Contents/PlugIns",
            "Contents/XPCServices",
            "Contents/Helpers",
        ]
        for relativePath in nestedRoots {
            if Task.isCancelled { return (identifiers, groups) }
            let root = appURL.appendingPathComponent(relativePath, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { return (identifiers, groups) }
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      let bundle = Bundle(url: url),
                      let identifier = bundle.bundleIdentifier,
                      AppSecurityValidator.isSafeIdentifier(identifier) else { continue }
                identifiers.insert(identifier)
                groups.formUnion(AppSecurityValidator.applicationGroups(at: url))
            }
        }
        return (identifiers, groups)
    }

    private static func trustedNames(for app: InstalledApp) -> Set<String> {
        var names = Set<String>()
        for rawName in [app.name, app.url.deletingPathExtension().lastPathComponent] {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 3,
                  !name.contains("/"),
                  name != ".",
                  name != ".." else { continue }
            names.insert(name)
        }
        return names
    }

    private static func appendMatches(
        below libraryRoot: URL,
        locations: [Location],
        identifierConfidences: [String: AppArtifactConfidence],
        groups: Set<String>,
        names: Set<String>,
        fileManager: FileManager,
        to artifacts: inout [AppUninstallArtifact]
    ) {
        for location in locations {
            if Task.isCancelled { return }
            let root = libraryRoot.appendingPathComponent(location.relativePath, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for candidate in children {
                if Task.isCancelled { return }
                guard isDirectChild(candidate, of: root) else { continue }
                let filename = candidate.lastPathComponent
                if let confidence = confidence(
                    for: filename,
                    rule: location.rule,
                    identifierConfidences: identifierConfidences,
                    groups: groups,
                    names: names
                ) {
                    artifacts.append(makeArtifact(
                        at: candidate,
                        category: location.category,
                        confidence: confidence,
                        fileManager: fileManager
                    ))
                    continue
                }

                let searchesNestedIdentifierFolders: Bool
                switch location.rule {
                case .identifiers, .identifiersAndNames:
                    searchesNestedIdentifierFolders = true
                default:
                    searchesNestedIdentifierFolders = false
                }
                guard searchesNestedIdentifierFolders,
                      let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      let nestedChildren = try? fileManager.contentsOfDirectory(
                        at: candidate,
                        includingPropertiesForKeys: [.isSymbolicLinkKey],
                        options: [.skipsHiddenFiles]
                ) else { continue }
                for nested in nestedChildren where isDirectChild(nested, of: candidate) {
                    if Task.isCancelled { return }
                    let nestedName = nested.lastPathComponent
                    let confidence: AppArtifactConfidence?
                    if let identifierConfidence = identifierConfidences[nestedName] {
                        confidence = identifierConfidence
                    } else if location.rule == .identifiersAndNames,
                              names.contains(where: {
                                nestedName.caseInsensitiveCompare($0) == .orderedSame
                              }) {
                        confidence = .nameMatch
                    } else {
                        confidence = nil
                    }
                    guard let confidence else { continue }
                    artifacts.append(makeArtifact(
                        at: nested,
                        category: location.category,
                        confidence: confidence,
                        fileManager: fileManager
                    ))
                }
            }
        }
    }

    private static func confidence(
        for filename: String,
        rule: MatchRule,
        identifierConfidences: [String: AppArtifactConfidence],
        groups: Set<String>,
        names: Set<String>
    ) -> AppArtifactConfidence? {
        switch rule {
        case .identifiers:
            return identifierConfidences[filename]
        case .groups:
            return groups.contains(filename) ? .shared : nil
        case .identifierFiles:
            return matchedIdentifierConfidence(in: identifierConfidences) {
                identifierFile(filename, belongsTo: $0)
            }
        case .byHostIdentifierFiles:
            return matchedIdentifierConfidence(in: identifierConfidences) {
                byHostIdentifierFile(filename, belongsTo: $0)
            }
        case .identifiersAndNames:
            if let identifierConfidence = identifierConfidences[filename] {
                return identifierConfidence
            }
            return names.contains(where: { filename.caseInsensitiveCompare($0) == .orderedSame }) ? .nameMatch : nil
        case .diagnosticReports:
            let base = (filename as NSString).deletingPathExtension
            guard names.contains(where: {
                base.caseInsensitiveCompare($0) == .orderedSame
                    || base.lowercased().hasPrefix($0.lowercased() + "_")
                    || base.lowercased().hasPrefix($0.lowercased() + "-")
            }) else { return nil }
            return .nameMatch
        }
    }

    private static func matchedIdentifierConfidence(
        in confidences: [String: AppArtifactConfidence],
        where matches: (String) -> Bool
    ) -> AppArtifactConfidence? {
        let matched = confidences.compactMap { identifier, confidence in
            matches(identifier) ? confidence : nil
        }
        if matched.contains(.exact) { return .exact }
        return matched.first
    }

    private static func identifierFile(_ filename: String, belongsTo identifier: String) -> Bool {
        if filename == identifier { return true }
        let knownExactSuffixes = [".plist", ".savedState", ".binarycookies", ".ShipIt"]
        return knownExactSuffixes.contains(where: { filename == identifier + $0 })
    }

    private static func byHostIdentifierFile(_ filename: String, belongsTo identifier: String) -> Bool {
        let prefix = identifier + "."
        let suffix = ".plist"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else { return false }
        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
        guard start < end else { return false }
        return UUID(uuidString: String(filename[start..<end])) != nil
    }

    private static func isDirectChild(_ candidate: URL, of root: URL) -> Bool {
        candidate.standardizedFileURL.deletingLastPathComponent().pathComponents
            == root.standardizedFileURL.pathComponents
    }

    private static func makeArtifact(
        at url: URL,
        category: AppArtifactCategory,
        confidence: AppArtifactConfidence,
        fileManager: FileManager,
        knownSize: Int64? = nil,
        knownResourceIdentifier: String? = nil
    ) -> AppUninstallArtifact {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        let size: Int64
        if let knownSize {
            size = knownSize
        } else if values?.isDirectory == true, values?.isSymbolicLink != true {
            size = DirectorySize.of(
                url,
                using: fileManager,
                preferAllocated: false,
                isCancelled: { Task.isCancelled }
            )
        } else {
            size = Int64(values?.fileSize ?? 0)
        }
        return AppUninstallArtifact(
            url: url,
            category: category,
            size: size,
            confidence: confidence,
            requiresAuthorization: !fileManager.isWritableFile(atPath: url.deletingLastPathComponent().path),
            resourceIdentifier: knownResourceIdentifier ?? AppUninstaller.currentResourceIdentifier(at: url)
        )
    }
}

struct AppUninstallFailure: Identifiable, Equatable {
    let url: URL
    let message: String
    var id: String { url.path }
}

struct AppUninstallResult: Identifiable, Equatable {
    let id = UUID()
    let appName: String
    let applicationURL: URL
    let removed: [URL]
    let failures: [AppUninstallFailure]

    var succeeded: Bool { failures.isEmpty }
    var applicationRemoved: Bool {
        removed.contains { $0.standardizedFileURL == applicationURL.standardizedFileURL }
    }
}

struct AppLaunchctlResult: Equatable {
    let terminationStatus: Int32
    let errorOutput: String
}

enum AppUninstaller {
    enum ValidationError: LocalizedError {
        case protectedApplication
        case applicationChanged
        case applicationDidNotQuit
        case artifactChanged(URL)
        case unsafePath(URL)
        case launchItemDeactivationFailed(URL, String)

        var errorDescription: String? {
            switch self {
            case .protectedApplication:
                return "Sapphire and macOS system apps cannot be removed here."
            case .applicationChanged:
                return "The application changed after it was scanned. Scan it again before removing it."
            case .applicationDidNotQuit:
                return "The application did not quit. Save your work, quit it manually, and try again."
            case .artifactChanged(let url):
                return "A related item changed after it was scanned and was left in place: \(url.path)"
            case .unsafePath(let url):
                return "Sapphire refused to remove an unsafe path: \(url.path)"
            case .launchItemDeactivationFailed(let url, let reason):
                return "The launch item could not be stopped and was left in place: \(url.path). \(reason)"
            }
        }
    }

    @MainActor
    static func uninstall(app: InstalledApp, artifacts: [AppUninstallArtifact]) async -> AppUninstallResult {
        do {
            try validate(app: app, artifacts: artifacts)
        } catch {
            return AppUninstallResult(
                appName: app.name,
                applicationURL: app.url,
                removed: [],
                failures: [.init(url: app.url, message: error.localizedDescription)]
            )
        }

        let selectedAppPath = app.url.standardizedFileURL.resolvingSymlinksInPath()
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            guard $0.bundleIdentifier == app.bundleIdentifier,
                  let runningURL = $0.bundleURL else { return false }
            return runningURL.standardizedFileURL.resolvingSymlinksInPath() == selectedAppPath
        }) {
            guard await running.sapphireTerminateAndWait(timeout: 6) else {
                return AppUninstallResult(
                    appName: app.name,
                    applicationURL: app.url,
                    removed: [],
                    failures: [.init(
                        url: app.url,
                        message: ValidationError.applicationDidNotQuit.localizedDescription
                    )]
                )
            }
        }

        let ordered = artifacts.sorted {
            if $0.isApplication != $1.isApplication { return $0.isApplication }
            return $0.url.path.count > $1.url.path.count
        }
        var removed: [URL] = []
        var failures: [AppUninstallFailure] = []
        let fileManager = FileManager.default
        for artifact in ordered {
            do {
                guard try artifactExistsForRemoval(app: app, artifact: artifact, fileManager: fileManager) else {
                    continue
                }
                try validateImmediatelyBeforeRemoval(app: app, artifact: artifact)
                if artifact.category == .launchItems {
                    try deactivateLaunchItemIfPossible(at: artifact.url)
                }
                try await moveToTrash(artifact.url)
                removed.append(artifact.url)
            } catch {
                failures.append(.init(url: artifact.url, message: error.localizedDescription))
                if artifact.isApplication { break }
            }
        }
        return AppUninstallResult(
            appName: app.name,
            applicationURL: app.url,
            removed: removed,
            failures: failures
        )
    }

    private static func validate(app: InstalledApp, artifacts: [AppUninstallArtifact]) throws {
        guard !app.isSystem,
              app.url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else {
            throw ValidationError.protectedApplication
        }
        guard !isSymbolicLink(app.url) else {
            throw ValidationError.unsafePath(app.url)
        }
        guard let expectedResourceIdentifier = app.resourceIdentifier,
              Bundle(url: app.url)?.bundleIdentifier == app.bundleIdentifier,
              currentResourceIdentifier(at: app.url) == expectedResourceIdentifier else {
            throw ValidationError.applicationChanged
        }

        let applicationArtifacts = artifacts.filter(\.isApplication)
        guard applicationArtifacts.count == 1,
              applicationArtifacts[0].url.standardizedFileURL == app.url.standardizedFileURL else {
            throw ValidationError.applicationChanged
        }

        for artifact in artifacts {
            guard let root = allowedRoot(containing: artifact.url),
                  !hasSymbolicLinkAncestor(artifact.url, stoppingAt: root) else {
                throw ValidationError.unsafePath(artifact.url)
            }
        }
    }

    static func artifactExistsForRemoval(
        app: InstalledApp,
        artifact: AppUninstallArtifact,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: artifact.url.path) else {
            if artifact.isApplication { throw ValidationError.applicationChanged }
            return false
        }
        return true
    }

    private static func validateImmediatelyBeforeRemoval(
        app: InstalledApp,
        artifact: AppUninstallArtifact
    ) throws {
        guard let root = allowedRoot(containing: artifact.url),
              !hasSymbolicLinkAncestor(artifact.url, stoppingAt: root) else {
            throw ValidationError.unsafePath(artifact.url)
        }
        guard let expectedIdentifier = artifact.resourceIdentifier,
              currentResourceIdentifier(at: artifact.url) == expectedIdentifier else {
            throw ValidationError.artifactChanged(artifact.url)
        }
        if artifact.isApplication {
            guard !isSymbolicLink(artifact.url),
                  artifact.url.standardizedFileURL == app.url.standardizedFileURL,
                  Bundle(url: artifact.url)?.bundleIdentifier == app.bundleIdentifier else {
                throw ValidationError.applicationChanged
            }
        }
    }

    @MainActor
    private static func moveToTrash(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func launchctlArguments(for url: URL) -> [String]? {
        guard url.pathExtension.caseInsensitiveCompare("plist") == .orderedSame else { return nil }
        let standardizedURL = url.standardizedFileURL
        let parent = standardizedURL.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userLaunchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .standardizedFileURL
        let systemLaunchAgents = URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)
            .standardizedFileURL
        let systemLaunchDaemons = URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
            .standardizedFileURL

        let domain: String
        if parent == userLaunchAgents || parent == systemLaunchAgents {
            domain = "gui/\(getuid())"
        } else if parent == systemLaunchDaemons {
            domain = "system"
        } else {
            return nil
        }
        return ["bootout", domain, standardizedURL.path]
    }

    static func deactivateLaunchItemIfPossible(
        at url: URL,
        runner: ([String]) throws -> AppLaunchctlResult = runLaunchctl
    ) throws {
        guard let arguments = launchctlArguments(for: url) else { return }
        let result: AppLaunchctlResult
        do {
            result = try runner(arguments)
        } catch {
            throw ValidationError.launchItemDeactivationFailed(url, error.localizedDescription)
        }

        let normalizedError = result.errorOutput.lowercased()
        let wasNotLoaded = result.terminationStatus == 3
            || normalizedError.contains("no such process")
            || normalizedError.contains("could not find service")
        guard result.terminationStatus == 0 || wasNotLoaded else {
            let reason = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ValidationError.launchItemDeactivationFailed(
                url,
                reason.isEmpty ? "launchctl exited with status \(result.terminationStatus)." : reason
            )
        }
    }

    private static func runLaunchctl(arguments: [String]) throws -> AppLaunchctlResult {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return AppLaunchctlResult(
            terminationStatus: process.terminationStatus,
            errorOutput: String(data: errorData, encoding: .utf8) ?? ""
        )
    }

    private static var allowedRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
        ]
    }

    private static func allowedRoot(containing candidate: URL) -> URL? {
        allowedRoots.first { isDescendant(candidate, of: $0) }
    }

    private static func hasSymbolicLinkAncestor(_ candidate: URL, stoppingAt root: URL) -> Bool {
        let standardizedRoot = root.standardizedFileURL
        if (try? standardizedRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return true
        }
        var cursor = candidate.standardizedFileURL.deletingLastPathComponent()
        while cursor != standardizedRoot {
            guard isDescendant(cursor, of: standardizedRoot) else { return true }
            if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return true
            }
            let parent = cursor.deletingLastPathComponent()
            guard parent != cursor else { return true }
            cursor = parent
        }
        return false
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func currentResourceIdentifier(at url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .volumeURLKey,
            .fileResourceIdentifierKey
        ]),
              let volume = stableIdentifier(values.volumeIdentifier)
                ?? values.volume.map({ "volume-url:\($0.standardizedFileURL.path)" }),
              let file = stableIdentifier(values.fileResourceIdentifier) else { return nil }
        return "\(volume):\(file)"
    }

    private static func stableIdentifier(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let data = value as? Data { return data.base64EncodedString() }
        if let data = value as? NSData { return (data as Data).base64EncodedString() }
        return String(describing: value)
    }

    static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }
}