//
//  DefaultFileHandler.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-11
//

import AppKit
import UniformTypeIdentifiers

enum DefaultFileHandler {
    static func isThisApp(handlerURL: URL?, ownURL: URL = Bundle.main.bundleURL) -> Bool {
        guard let handlerURL else { return false }
        return canonical(handlerURL) == canonical(ownURL)
    }

    static func pointsAtAnotherCopy(
        handlerBundleIdentifier: String?,
        handlerURL: URL?,
        ownBundleIdentifier: String?,
        ownURL: URL = Bundle.main.bundleURL
    ) -> Bool {
        guard let ownBundleIdentifier, let handlerBundleIdentifier, let handlerURL,
              handlerBundleIdentifier.caseInsensitiveCompare(ownBundleIdentifier) == .orderedSame else { return false }
        return !isThisApp(handlerURL: handlerURL, ownURL: ownURL)
    }

    static func alternative(
        candidates: [URL],
        preferredBundleIdentifiers: [String],
        ownBundleIdentifier: String?,
        bundleIdentifier: (URL) -> String?
    ) -> URL? {
        let identified = candidates.map { ($0, bundleIdentifier($0)) }
        for preferred in preferredBundleIdentifiers {
            if let match = identified.first(where: { $0.1?.caseInsensitiveCompare(preferred) == .orderedSame }) {
                return match.0
            }
        }
        return identified.first { candidate in
            guard let identifier = candidate.1, let own = ownBundleIdentifier else { return true }
            return identifier.caseInsensitiveCompare(own) != .orderedSame
        }?.0
    }

    @MainActor
    static func alternativeApplication(for file: URL, preferredBundleIdentifiers: [String]) -> URL? {
        var candidates = preferredBundleIdentifiers.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
        candidates += NSWorkspace.shared.urlsForApplications(toOpen: file)
        return alternative(
            candidates: candidates,
            preferredBundleIdentifiers: preferredBundleIdentifiers,
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier }
        )
    }

    @MainActor
    static func currentHandler(for type: UTType) -> (bundleIdentifier: String?, url: URL?) {
        let url = NSWorkspace.shared.urlForApplication(toOpen: type)
        return (url.flatMap { Bundle(url: $0)?.bundleIdentifier }, url)
    }

    @MainActor
    @discardableResult
    static func claim(_ types: [UTType]) async -> Bool {
        var allSucceeded = true
        for type in types {
            let handler = currentHandler(for: type)
            if isThisApp(handlerURL: handler.url) { continue }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
            } catch {
                allSucceeded = false
            }
        }
        return allSucceeded && types.allSatisfy { isThisApp(handlerURL: currentHandler(for: $0).url) }
    }

    @MainActor
    static func shadowingCopy(for types: [UTType]) -> URL? {
        let own = Bundle.main.bundleIdentifier
        for type in types {
            let handler = currentHandler(for: type)
            if pointsAtAnotherCopy(
                handlerBundleIdentifier: handler.bundleIdentifier,
                handlerURL: handler.url,
                ownBundleIdentifier: own
            ) {
                return handler.url
            }
        }
        return nil
    }

    @MainActor
    static func reclaimFromOtherCopies(_ types: [UTType]) async {
        let own = Bundle.main.bundleIdentifier
        let stale = types.filter { type in
            let handler = currentHandler(for: type)
            return pointsAtAnotherCopy(
                handlerBundleIdentifier: handler.bundleIdentifier,
                handlerURL: handler.url,
                ownBundleIdentifier: own
            )
        }
        guard !stale.isEmpty else { return }
        await claim(stale)
    }

    static func otherRunningInstance() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != own && !$0.isTerminated }
    }

    static func canonical(_ url: URL) -> String {
        canonicalPath(url.standardizedFileURL.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func canonicalPath(_ path: String) -> String {
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let nsPath = path as NSString
        let parent = nsPath.deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return path }
        return (canonicalPath(parent) as NSString).appendingPathComponent(nsPath.lastPathComponent)
    }
}