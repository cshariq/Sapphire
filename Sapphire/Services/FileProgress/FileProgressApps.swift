//
//  FileProgressApps.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28
//

import AppKit

enum FileProgressMethod {
    case publishedProgress
    case partialFile
}

enum FileProgressApp: String, CaseIterable, Identifiable, Codable {
    case safari, chrome, edge, brave, arc, opera, vivaldi, chromium
    case firefox, zen
    case finder, airDrop
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .edge: "Microsoft Edge"
        case .brave: "Brave"
        case .arc: "Arc"
        case .opera: "Opera"
        case .vivaldi: "Vivaldi"
        case .chromium: "Chromium"
        case .firefox: "Firefox"
        case .zen: "Zen Browser"
        case .finder: "Finder copies"
        case .airDrop: "AirDrop"
        case .other: "Other apps"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .safari: ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        case .chrome: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"]
        case .edge: ["com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary"]
        case .brave: ["com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly"]
        case .arc: ["company.thebrowser.Browser"]
        case .opera: ["com.operasoftware.Opera", "com.operasoftware.OperaGX"]
        case .vivaldi: ["com.vivaldi.Vivaldi"]
        case .chromium: ["org.chromium.Chromium"]
        case .firefox: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]
        case .zen: ["app.zen-browser.zen"]
        case .finder: ["com.apple.finder"]
        case .airDrop: ["com.apple.finder"]
        case .other: []
        }
    }

    var method: FileProgressMethod {
        switch self {
        case .firefox, .zen: .partialFile
        default: .publishedProgress
        }
    }

    var isChromium: Bool {
        switch self {
        case .chrome, .edge, .brave, .arc, .opera, .vivaldi, .chromium: true
        default: false
        }
    }

    var trackingDetail: String {
        switch self {
        case .safari: "Exact progress from Safari's download bundle and the system progress Safari publishes."
        case .chrome, .edge, .brave, .arc, .opera, .vivaldi, .chromium:
            "Exact progress from the system progress Chromium publishes for .crdownload files, in the folder set in its settings."
        case .firefox, .zen: "Follows the growing .part file in the folder set in Firefox's settings; the total size isn't known until it finishes."
        case .finder: "Copies and moves Finder shows a progress bar for."
        case .airDrop: "Files arriving over AirDrop."
        case .other: "Any other app that publishes file progress, and .part/.partial files in watched folders."
        }
    }

    var isInstalled: Bool {
        switch self {
        case .finder, .airDrop, .other: return true
        default:
            return bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        }
    }

    var icon: NSImage? {
        switch self {
        case .airDrop:
            return NSImage(systemSymbolName: "airplayaudio", accessibilityDescription: "AirDrop")
        case .other:
            return NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        default:
            for id in bundleIDs {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
            }
            return nil
        }
    }

    // MARK: - Where each app downloads

    private static var appSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    var configuredDownloadDirectories: [URL] {
        switch self {
        case .chrome: Self.chromiumDirectories("Google/Chrome")
        case .edge: Self.chromiumDirectories("Microsoft Edge")
        case .brave: Self.chromiumDirectories("BraveSoftware/Brave-Browser")
        case .arc: Self.chromiumDirectories("Arc/User Data")
        case .opera: Self.chromiumDirectories("com.operasoftware.Opera", flatProfile: true)
        case .vivaldi: Self.chromiumDirectories("Vivaldi")
        case .chromium: Self.chromiumDirectories("Chromium")
        case .firefox: Self.firefoxDirectories("Firefox")
        case .zen: Self.firefoxDirectories("zen")
        case .safari: Self.safariDirectory().map { [$0] } ?? []
        default: []
        }
    }

    private static func chromiumDirectories(_ root: String, flatProfile: Bool = false) -> [URL] {
        let base = appSupport.appendingPathComponent(root)
        var profiles: [URL] = []
        if flatProfile {
            profiles = [base]
        } else if let entries = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            profiles = entries.filter {
                let name = $0.lastPathComponent
                return name == "Default" || name.hasPrefix("Profile ")
            }
        }
        return profiles.compactMap { profile in
            let prefs = profile.appendingPathComponent("Preferences")
            guard let data = try? Data(contentsOf: prefs),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let download = json["download"] as? [String: Any],
                  let path = download["default_directory"] as? String, !path.isEmpty else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
    }

    private static func firefoxDirectories(_ root: String) -> [URL] {
        let profilesDir = appSupport.appendingPathComponent(root).appendingPathComponent("Profiles")
        guard let profiles = try? FileManager.default.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil) else { return [] }
        return profiles.compactMap { profile in
            guard let text = try? String(contentsOf: profile.appendingPathComponent("prefs.js"), encoding: .utf8),
                  text.contains("\"browser.download.folderList\", 2"),
                  let range = text.range(of: "\"browser.download.dir\", \"") else { return nil }
            let rest = text[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            let path = String(rest[..<end]).replacingOccurrences(of: "\\\\", with: "\\")
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private static func safariDirectory() -> URL? {
        guard let path = CFPreferencesCopyAppValue("DownloadsPath" as CFString, "com.apple.Safari" as CFString) as? String,
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: - Recognizing a transfer

    static func owner(ofPartialFile url: URL) -> FileProgressApp? {
        switch url.pathExtension.lowercased() {
        case "download": return .safari
        case "crdownload": return runningChromium(for: url) ?? .chrome
        case "part": return runningFirefoxFamily() ?? .firefox
        case "partial", "!qb", "opdownload": return .other
        default: return nil
        }
    }

    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "!qb"]

    private static func runningChromium(for url: URL) -> FileProgressApp? {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let candidates = allCases.filter { app in app.isChromium && app.bundleIDs.contains { running.contains($0) } }
        let folder = url.deletingLastPathComponent().standardizedFileURL.path
        if let byFolder = candidates.first(where: { app in
            app.configuredDownloadDirectories.contains { $0.standardizedFileURL.path == folder }
        }) { return byFolder }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let app = candidates.first(where: { $0.bundleIDs.contains(front) }) { return app }
        return candidates.first
    }

    private static func runningFirefoxFamily() -> FileProgressApp? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return [FileProgressApp.firefox, .zen].first { app in app.bundleIDs.contains { running.contains($0) } }
    }
}