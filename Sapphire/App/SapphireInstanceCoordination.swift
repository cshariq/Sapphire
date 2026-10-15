//
//  SapphireInstanceCoordination.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-20

import AppKit
import FileProvider
import Foundation

enum SapphireInstanceCoordination {
    struct Peer: Equatable {
        var bundleURL: URL
        var processIdentifier: pid_t
    }

    static var currentBundleURL: URL {
        Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    static var currentProcessIdentifier: pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    static func isApplicationsURL(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path == "/Applications"
    }

    static func isBuildFolderURL(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        if path.contains("/DerivedData/") { return true }
        if path.contains("/Build/Products/") { return true }
        if path.contains("/.build/") { return true }
        return false
    }

    static func otherRunningPeers(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [Peer] {
        guard let bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .compactMap { app in
                guard !app.isTerminated, app.processIdentifier != currentPID else { return nil }
                guard let url = app.bundleURL?.resolvingSymlinksInPath() else { return nil }
                return Peer(bundleURL: url, processIdentifier: app.processIdentifier)
            }
    }

    static func shouldIsolateFirestorePersistence(
        bundleURL: URL = currentBundleURL,
        otherPeers: [Peer]? = nil
    ) -> Bool {
        if isBuildFolderURL(bundleURL) { return true }
        if !(otherPeers ?? otherRunningPeers()).isEmpty { return true }
        return false
    }

    static func shouldRegisterFileProvider(
        bundleURL: URL = currentBundleURL,
        processIdentifier: pid_t = currentProcessIdentifier,
        otherPeers: [Peer]? = nil
    ) -> Bool {
        let others = otherPeers ?? otherRunningPeers()
        guard !others.isEmpty else { return true }

        let weAreInstalled = isApplicationsURL(bundleURL)
        let installedPeer = others.contains { isApplicationsURL($0.bundleURL) }
        if installedPeer && !weAreInstalled { return false }
        if weAreInstalled && others.contains(where: { isApplicationsURL($0.bundleURL) }) {
            return isPreferredProcess(
                bundleURL: bundleURL,
                processIdentifier: processIdentifier,
                candidates: others + [Peer(bundleURL: bundleURL, processIdentifier: processIdentifier)]
            )
        }
        if weAreInstalled { return true }

        return isPreferredProcess(
            bundleURL: bundleURL,
            processIdentifier: processIdentifier,
            candidates: others + [Peer(bundleURL: bundleURL, processIdentifier: processIdentifier)]
        )
    }

    static func fileProviderSkipReason(
        bundleURL: URL = currentBundleURL,
        otherPeers: [Peer]? = nil
    ) -> String {
        let others = otherPeers ?? otherRunningPeers()
        if let installed = others.first(where: { isApplicationsURL($0.bundleURL) }),
           !isApplicationsURL(bundleURL) {
            return "Finder phone drive is owned by \(installed.bundleURL.path). This copy is running from a build folder, so it is not registering a second File Provider."
        }
        if let other = others.first {
            return "Another Sapphire process (pid \(other.processIdentifier)) is already running, so this copy is not registering the Finder phone drive."
        }
        return "File Provider registration was skipped."
    }

    static func fileProviderRegistrationHint(error: Error, bundleURL: URL = currentBundleURL) -> String {
        let description = error.localizedDescription
        let fromBuildFolder = isBuildFolderURL(bundleURL) || !isApplicationsURL(bundleURL)
        if isApplicationCannotBeUsed(error) {
            if fromBuildFolder {
                return "Finder refused to attach the phone drive while Sapphire is running from \(bundleURL.path). A signed copy in /Applications usually works; if one is already installed, quit it before using this build, or use Repair after replacing that copy."
            }
            return "Finder refused to attach the phone drive (\(description)). Try Repair, or quit other Sapphire copies and reopen this one."
        }
        if fromBuildFolder {
            return "Could not register the phone drive with Finder (\(description)). This build is not in /Applications; registration was still attempted."
        }
        return "Could not register the phone drive with Finder (\(description))."
    }

    static func isApplicationCannotBeUsed(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSFileProviderErrorDomain,
           nsError.localizedDescription.localizedCaseInsensitiveContains("cannot be used right now") {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("cannot be used right now")
    }

    private static func isPreferredProcess(
        bundleURL: URL,
        processIdentifier: pid_t,
        candidates: [Peer]
    ) -> Bool {
        let installed = candidates.filter { isApplicationsURL($0.bundleURL) }
        let pool = installed.isEmpty ? candidates : installed
        let winner = pool.min { lhs, rhs in
            if lhs.processIdentifier != rhs.processIdentifier {
                return lhs.processIdentifier < rhs.processIdentifier
            }
            return lhs.bundleURL.path < rhs.bundleURL.path
        }
        return winner?.processIdentifier == processIdentifier
            && winner?.bundleURL.resolvingSymlinksInPath() == bundleURL.resolvingSymlinksInPath()
    }
}