//
//  InstalledAppUpdatePolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import Foundation

// MARK: - Scheduling, announcements, skips

enum InstalledAppUpdatePolicy {
    enum CheckScope: Equatable {
        case all
        case unresolved
    }

    static func isCheckDue(lastCheckedAt: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastCheckedAt else { return true }
        let elapsed = now.timeIntervalSince(lastCheckedAt)
        if elapsed < -60 { return true }
        return elapsed >= interval
    }

    static func backgroundScope(
        force: Bool,
        isDue: Bool,
        hasEntries: Bool,
        hasUnresolvedEntries: Bool
    ) -> CheckScope? {
        if isDue { return .all }
        if force && hasEntries { return .all }
        if !hasEntries || hasUnresolvedEntries { return .unresolved }
        return nil
    }

    static func announcementKey(bundleID: String, version: String) -> String {
        "\(bundleID)|\(version)"
    }

    struct AvailableUpdate: Equatable {
        let id: String
        let version: String
    }

    static func updatesToAnnounce(
        _ available: [AvailableUpdate],
        alreadyAnnounced: Set<String>
    ) -> [AvailableUpdate] {
        var seen = Set<String>()
        return available.filter { update in
            let key = announcementKey(bundleID: update.id, version: update.version)
            return !alreadyAnnounced.contains(key) && seen.insert(key).inserted
        }
    }

    enum CheckOutcome: Equatable {
        case updateAvailable(version: String)
        case noUpdate
        case unknown
    }

    static func prunedAnnouncements(
        _ announced: Set<String>,
        outcomes: [String: CheckOutcome]
    ) -> Set<String> {
        announced.filter { key in
            guard let separator = key.firstIndex(of: "|") else { return false }
            let id = String(key[..<separator])
            let version = String(key[key.index(after: separator)...])
            switch outcomes[id] {
            case nil, .noUpdate:
                return false
            case .unknown:
                return true
            case .updateAvailable(let offered):
                return offered == version
            }
        }
    }

    static func outcome(for status: InstalledAppUpdateEntry.Status) -> CheckOutcome {
        switch status {
        case .updateAvailable(let latestVersion, _, _, _, _):
            return .updateAvailable(version: latestVersion)
        case .upToDate, .unsupported:
            return .noUpdate
        case .checking, .ignored, .error:
            return .unknown
        }
    }

    static func isSkipped(latestVersion: String, skippedVersion: String?) -> Bool {
        guard let skippedVersion, !skippedVersion.isEmpty else { return false }
        if latestVersion == skippedVersion { return true }
        guard latestVersion.contains(where: \.isNumber),
              skippedVersion.contains(where: \.isNumber) else { return false }
        return AppVersionOrdering.compare(latestVersion, skippedVersion) != .orderedDescending
    }

    static func presentedStatus(
        _ raw: InstalledAppUpdateEntry.Status,
        skippedVersion: String?
    ) -> InstalledAppUpdateEntry.Status {
        guard case .updateAvailable(let latestVersion, _, _, _, _) = raw,
              isSkipped(latestVersion: latestVersion, skippedVersion: skippedVersion) else { return raw }
        return .upToDate(latestVersion: latestVersion)
    }

    static func prunedSkips(
        _ skipped: [String: String],
        installedVersions: [String: String],
        inventoryIsComplete: Bool
    ) -> [String: String] {
        skipped.filter { id, skippedVersion in
            guard let installed = installedVersions[id] else { return !inventoryIsComplete }
            if installed == skippedVersion { return false }
            guard installed.contains(where: \.isNumber),
                  skippedVersion.contains(where: \.isNumber) else { return true }
            return AppVersionOrdering.compare(installed, skippedVersion) == .orderedAscending
        }
    }

    static func carriedStatus(
        scannedVersion: String,
        scannedBuildVersion: String,
        priorVersion: String,
        priorBuildVersion: String,
        priorStatus: InstalledAppUpdateEntry.Status
    ) -> InstalledAppUpdateEntry.Status? {
        guard scannedVersion == priorVersion, scannedBuildVersion == priorBuildVersion else { return nil }
        switch priorStatus {
        case .checking, .ignored:
            return nil
        case .upToDate, .updateAvailable, .unsupported, .error:
            return priorStatus
        }
    }
}

// MARK: - Persisted check results

struct InstalledAppUpdateCacheRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case upToDate
        case updateAvailable
        case unsupported
    }

    static let maximumReleaseNotesLength = 8_000

    let checkedVersion: String
    let checkedBuildVersion: String
    let kind: Kind
    let latestVersion: String?
    let downloadURL: URL?
    let pageURL: URL?
    let releaseNotes: String?
    let releaseNotesURL: URL?

    init?(
        status: InstalledAppUpdateEntry.Status,
        checkedVersion: String,
        checkedBuildVersion: String
    ) {
        self.checkedVersion = checkedVersion
        self.checkedBuildVersion = checkedBuildVersion
        switch status {
        case .upToDate(let latestVersion):
            kind = .upToDate
            self.latestVersion = latestVersion
            downloadURL = nil
            pageURL = nil
            releaseNotes = nil
            releaseNotesURL = nil
        case .updateAvailable(let latestVersion, let downloadURL, let pageURL, let releaseNotes, let releaseNotesURL):
            kind = .updateAvailable
            self.latestVersion = latestVersion
            self.downloadURL = downloadURL
            self.pageURL = pageURL
            self.releaseNotes = releaseNotes.map { String($0.prefix(Self.maximumReleaseNotesLength)) }
            self.releaseNotesURL = releaseNotesURL
        case .unsupported:
            kind = .unsupported
            latestVersion = nil
            downloadURL = nil
            pageURL = nil
            releaseNotes = nil
            releaseNotesURL = nil
        case .checking, .ignored, .error:
            return nil
        }
    }

    func status(forInstalledVersion version: String, buildVersion: String) -> InstalledAppUpdateEntry.Status? {
        guard version == checkedVersion, buildVersion == checkedBuildVersion else { return nil }
        switch kind {
        case .upToDate:
            return .upToDate(latestVersion: latestVersion ?? version)
        case .updateAvailable:
            guard let latestVersion else { return nil }
            return .updateAvailable(
                latestVersion: latestVersion,
                downloadURL: downloadURL,
                pageURL: pageURL,
                releaseNotes: releaseNotes,
                releaseNotesURL: releaseNotesURL
            )
        case .unsupported:
            return .unsupported
        }
    }
}

// MARK: - Batch updates

enum InstalledAppBatchUpdatePlanner {
    enum Route: Equatable {
        case homebrew(token: String, requiresAdministrator: Bool)
        case appStore
        case perItem
        case notUpdatable
    }

    struct Candidate: Equatable {
        let id: String
        let route: Route
    }

    struct Plan: Equatable {
        var homebrew: [(id: String, token: String)] = []
        var homebrewInTerminal: [(id: String, token: String)] = []
        var appStoreIDs: [String] = []
        var perItemIDs: [String] = []

        var isEmpty: Bool {
            homebrew.isEmpty && homebrewInTerminal.isEmpty && appStoreIDs.isEmpty && perItemIDs.isEmpty
        }

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.homebrew.map { "\($0.id)=\($0.token)" } == rhs.homebrew.map { "\($0.id)=\($0.token)" }
                && lhs.homebrewInTerminal.map { "\($0.id)=\($0.token)" }
                    == rhs.homebrewInTerminal.map { "\($0.id)=\($0.token)" }
                && lhs.appStoreIDs == rhs.appStoreIDs
                && lhs.perItemIDs == rhs.perItemIDs
        }
    }

    static func plan(for candidates: [Candidate]) -> Plan {
        var plan = Plan()
        var seenIDs = Set<String>()
        var seenTokens = Set<String>()
        for candidate in candidates where seenIDs.insert(candidate.id).inserted {
            switch candidate.route {
            case .homebrew(let token, let requiresAdministrator):
                guard HomebrewCommand.isSafeToken(token),
                      seenTokens.insert(token.lowercased()).inserted else { continue }
                if requiresAdministrator {
                    plan.homebrewInTerminal.append((candidate.id, token))
                } else {
                    plan.homebrew.append((candidate.id, token))
                }
            case .appStore:
                plan.appStoreIDs.append(candidate.id)
            case .perItem:
                plan.perItemIDs.append(candidate.id)
            case .notUpdatable:
                continue
            }
        }
        return plan
    }
}

// MARK: - Homebrew invocation

enum HomebrewCaskPrivilege {
    static func requiresAdministrator(artifacts: [Any]) -> Bool {
        for case let artifact as [String: Any] in artifacts {
            if artifact["pkg"] != nil || artifact["installer"] != nil { return true }
            for key in ["uninstall", "uninstall_preflight", "uninstall_postflight"] {
                guard let value = artifact[key] else { continue }
                let directives = (value as? [Any]) ?? [value]
                for case let directive as [String: Any] in directives where directiveNeedsSudo(directive) {
                    return true
                }
            }
        }
        return false
    }

    private static func directiveNeedsSudo(_ directive: [String: Any]) -> Bool {
        if directive["pkgutil"] != nil || directive["kext"] != nil { return true }
        for key in ["script", "early_script"] {
            if let script = directive[key] as? [String: Any], script["sudo"] as? Bool == true {
                return true
            }
        }
        for key in ["delete", "rmdir"] {
            let paths = (directive[key] as? [String]) ?? (directive[key] as? String).map { [$0] } ?? []
            if paths.contains(where: isSystemOwnedPath) { return true }
        }
        return false
    }

    private static func isSystemOwnedPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        return !path.hasPrefix("/Applications/") && !path.hasPrefix("/Users/")
    }

    static func outputRequestsAdministrator(_ output: String) -> Bool {
        let lowered = output.lowercased()
        let markers = [
            "sudo: a terminal is required",
            "sudo: no tty present",
            "sudo: a password is required",
            "a password is required",
            "password:",
        ]
        return markers.contains { lowered.contains($0) }
    }
}

enum HomebrewCommand {
    static let searchPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    private static let passthroughKeys: Set<String> = [
        "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
    ]

    static func environment(inherited: [String: String], home: String) -> [String: String] {
        var environment: [String: String] = [:]
        for (key, value) in inherited where passthroughKeys.contains(key) || key.hasPrefix("HOMEBREW_") {
            environment[key] = value
        }
        environment["PATH"] = searchPath
        environment["HOME"] = home
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        environment["HOMEBREW_NO_EMOJI"] = "1"
        environment.removeValue(forKey: "HOMEBREW_AUTO_UPDATE_SECS")
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        return environment
    }

    static func isSafeToken(_ token: String) -> Bool {
        guard (1...200).contains(token.count),
              let first = token.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._+-/")
        return token.unicodeScalars.allSatisfy { allowed.contains($0) } && !token.contains("..")
    }

    static func upgradeArguments(tokens: [String]) -> [String]? {
        guard !tokens.isEmpty, tokens.allSatisfy(isSafeToken) else { return nil }
        return ["upgrade", "--cask"] + tokens
    }

    static func upgradeTimeout(caskCount: Int) -> TimeInterval {
        let count = max(1, caskCount)
        return min(60 * 60, 15 * 60 + TimeInterval(count - 1) * 10 * 60)
    }

    static func terminalScript(brewPath: String, tokens: [String]) -> String? {
        guard let arguments = upgradeArguments(tokens: tokens),
              brewPath.hasPrefix("/"),
              !brewPath.contains("'") else { return nil }
        let quoted = arguments.map { "'\($0)'" }.joined(separator: " ")
        return """
        #!/bin/zsh
        rm -f -- "$0"
        export PATH='\(searchPath)'
        export HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_NO_ENV_HINTS=1
        echo "Sapphire is upgrading: \(tokens.joined(separator: " "))"
        echo "Homebrew may ask for your administrator password."
        echo
        '\(brewPath)' \(quoted)
        brew_status=$?
        echo
        if [ $brew_status -eq 0 ]; then
          echo "Done. You can close this window."
        else
          echo "brew exited with status $brew_status."
        fi
        """
    }

    static func failureSummary(_ output: String, limit: Int = 200) -> String? {
        let withoutEscapes = output.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        let lines = withoutEscapes
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let chosen = lines.last(where: { $0.hasPrefix("Error:") }) ?? lines.last else { return nil }
        var summary = chosen
        if summary.hasPrefix("Error:") {
            summary = summary.dropFirst("Error:".count).trimmingCharacters(in: .whitespaces)
        }
        guard !summary.isEmpty else { return nil }
        if summary.count > limit {
            summary = String(summary.prefix(max(1, limit - 1))) + "…"
        }
        return summary
    }
}