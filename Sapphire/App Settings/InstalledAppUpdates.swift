//
//  InstalledAppUpdates.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-04
//

import AppKit
import Foundation
import Darwin
import Network
@preconcurrency import UserNotifications

// MARK: - Update source

enum InstalledAppUpdateSource: Equatable {
    case none
    case sparkle(appcastURL: URL)
    case appStore
    case keystone(endpoint: URL, appID: String)
    case electron(ElectronUpdateFeed)
    case homebrew(token: String)
    case mozilla(MozillaProduct)
    case jsonManifest(url: URL)
    case visualStudioCode(VSCodeUpdateFeed)
    case androidStudio
    case jetBrains(productCode: String)
    case microsoftEdge(channel: MicrosoftEdgeChannel)
    case github(GitHubProject)
    case blender
    case selfUpdating

    var displayName: String {
        switch self {
        case .none: return "No update source"
        case .sparkle: return "Sparkle"
        case .appStore: return "Mac App Store"
        case .keystone: return "Google Update"
        case .electron(.github): return "electron-updater · GitHub"
        case .electron(.generic): return "electron-updater"
        case .homebrew: return "Homebrew"
        case .mozilla(.firefox): return "Mozilla"
        case .mozilla(.thunderbird): return "Mozilla"
        case .jsonManifest: return "App update manifest"
        case .visualStudioCode: return "Visual Studio Code Update"
        case .androidStudio: return "Android Studio Update"
        case .jetBrains: return "JetBrains Update"
        case .microsoftEdge: return "Microsoft Edge Update"
        case .github: return "GitHub Releases"
        case .blender: return "Blender Releases"
        case .selfUpdating: return "Self-updating"
        }
    }

    var usesOwningAppUpdater: Bool {
        switch self {
        case .sparkle, .keystone, .electron, .mozilla, .jsonManifest,
             .visualStudioCode, .androidStudio, .jetBrains, .microsoftEdge,
             .selfUpdating:
            return true
        case .none, .appStore, .homebrew, .github, .blender:
            return false
        }
    }
}

enum ElectronUpdateFeed: Equatable {
    case github(owner: String, repo: String)
    case generic(baseURL: URL)
}

struct VSCodeUpdateFeed: Equatable {
    let baseURL: URL
    let quality: String
    let commit: String
}

struct GitHubProject: Equatable {
    let owner: String
    let repository: String
}

enum MicrosoftEdgeChannel: String, Equatable {
    case stable = "Stable"
    case beta = "Beta"
    case dev = "Dev"
    case canary = "Canary"
}

enum MozillaProduct: String {
    case firefox
    case thunderbird

    var latestVersionKey: String {
        switch self {
        case .firefox: return "LATEST_FIREFOX_VERSION"
        case .thunderbird: return "LATEST_THUNDERBIRD_VERSION"
        }
    }

    var downloadProduct: String {
        switch self {
        case .firefox: return "firefox-latest"
        case .thunderbird: return "thunderbird-latest"
        }
    }
}

enum InstalledAppUpdateSourceDetector {
    static func detect(
        for bundle: Bundle,
        caskOwnership: [String: HomebrewCaskRecord] = [:]
    ) -> InstalledAppUpdateSource {
        guard let identifier = bundle.bundleIdentifier, !identifier.isEmpty else { return .none }
        if identifier == Bundle.main.bundleIdentifier { return .none }

        let bundleURL = bundle.bundleURL

        if FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path) {
            return .appStore
        }
        if identifier.hasPrefix("com.apple.") { return .none }

        if let cask = caskOwnership[bundleURL.standardizedFileURL.path],
           HomebrewCommand.isSafeToken(cask.token) {
            return .homebrew(token: cask.token)
        }
        let resolvedPath = bundleURL.resolvingSymlinksInPath().path
        if resolvedPath.contains("/Caskroom/") || resolvedPath.contains("/Cellar/"),
           let token = Self.homebrewToken(inPath: resolvedPath) {
            return .homebrew(token: token)
        }

        if let sparkleURL = sparkleFeedURL(bundleID: identifier, bundle: bundle) {
            return .sparkle(appcastURL: sparkleURL)
        }

        let electronConfigURLs = ["app-update.yml", "app-update.yaml"].map {
            bundleURL.appendingPathComponent("Contents/Resources/\($0)")
        }
        for configURL in electronConfigURLs {
            if let data = Self.readSmallBundleResource(at: configURL),
               let feed = Self.parseElectronFeed(data: data) {
                return .electron(feed)
            }
        }

        if let manifestURL = Self.httpsURL(
            from: bundle.object(forInfoDictionaryKey: "AppUpdateManifestURL") as? String
        ) {
            return .jsonManifest(url: manifestURL)
        }

        if let endpoint = Self.httpsURL(
            from: bundle.object(forInfoDictionaryKey: "KSUpdateURL") as? String
        ) {
            let productID = (bundle.object(forInfoDictionaryKey: "KSProductID") as? String) ?? identifier
            return .keystone(endpoint: endpoint, appID: productID)
        }

        if Self.visualStudioCodeBundleIDs.contains(identifier),
           let data = Self.readSmallBundleResource(
                at: bundleURL.appendingPathComponent("Contents/Resources/app/product.json")
           ),
           let feed = Self.parseVSCodeProduct(data: data) {
            return .visualStudioCode(feed)
        }

        let productInfoURL = bundleURL.appendingPathComponent("Contents/Resources/product-info.json")
        if identifier == "com.google.android.studio",
           Self.readSmallBundleResource(at: productInfoURL) != nil {
            return .androidStudio
        }
        if let data = Self.readSmallBundleResource(at: productInfoURL),
           let product = Self.parseJetBrainsProductInfo(data: data),
           product.isStable,
           product.vendor.localizedCaseInsensitiveContains("JetBrains") {
            return .jetBrains(productCode: product.code)
        }

        if identifier.hasPrefix("com.google."),
           let endpoint = URL(string: "https://tools.google.com/service/update2") {
            return .keystone(endpoint: endpoint, appID: identifier)
        }

        if identifier == "org.mozilla.firefox" { return .mozilla(.firefox) }
        if identifier == "org.mozilla.thunderbird" { return .mozilla(.thunderbird) }

        if let channel = Self.microsoftEdgeChannels[identifier] {
            return .microsoftEdge(channel: channel)
        }

        if let project = Self.githubProjects[identifier] {
            return .github(project)
        }

        if identifier == "org.blenderfoundation.blender" {
            return .blender
        }

        if Self.containsUpdaterFramework(in: bundleURL)
            || Self.knownPrivateSelfUpdaters.contains(identifier) {
            return .selfUpdating
        }

        return .none
    }

    private static let visualStudioCodeBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
    ]

    private static let microsoftEdgeChannels: [String: MicrosoftEdgeChannel] = [
        "com.microsoft.edgemac": .stable,
        "com.microsoft.edgemac.Beta": .beta,
        "com.microsoft.edgemac.Dev": .dev,
        "com.microsoft.edgemac.Canary": .canary,
    ]

    private static let githubProjects: [String: GitHubProject] = [
        "com.bambulab.bambu-studio": GitHubProject(owner: "bambulab", repository: "BambuStudio"),
        "ModrinthApp": GitHubProject(owner: "modrinth", repository: "code"),
        "com.github.GitHubClient": GitHubProject(owner: "desktop", repository: "desktop"),
    ]

    private static let knownPrivateSelfUpdaters: Set<String> = [
        "com.mojang.minecraftlauncher",
        "com.spotify.client",
    ]

    private static let updaterFrameworkNames = [
        "Sparkle.framework", "Squirrel.framework",
    ]

    private static func containsUpdaterFramework(in bundleURL: URL) -> Bool {
        let frameworksURL = bundleURL.appendingPathComponent("Contents/Frameworks")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: frameworksURL.path) else { return false }
        return names.contains { updaterFrameworkNames.contains($0) }
    }

    private static func readSmallBundleResource(at url: URL) -> Data? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= 512 * 1_024 else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    static func sparkleFeedURL(bundleID: String, bundle: Bundle) -> URL? {
        let candidates: [String?] = [
            bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            CFPreferencesCopyAppValue("SUFeedURL" as CFString, bundleID as CFString) as? String,
        ]
        for candidate in candidates {
            if let url = httpsURL(from: candidate) { return url }
        }
        return nil
    }

    static func httpsURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil else { return nil }
        return url
    }

    static func parseVSCodeProduct(data: Data) -> VSCodeUpdateFeed? {
        struct Product: Decodable {
            let updateUrl: String?
            let quality: String?
            let commit: String?
        }
        guard let product = try? JSONDecoder().decode(Product.self, from: data),
              let baseURL = httpsURL(from: product.updateUrl),
              let quality = product.quality,
              !quality.isEmpty,
              quality.count <= 32,
              quality.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
              }),
              let commit = product.commit,
              (7...64).contains(commit.count),
              commit.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) })
        else { return nil }
        return VSCodeUpdateFeed(baseURL: baseURL, quality: quality, commit: commit)
    }

    static func parseJetBrainsProductInfo(data: Data) -> (code: String, vendor: String, isStable: Bool)? {
        struct Product: Decodable {
            let productCode: String?
            let productVendor: String?
            let versionSuffix: String?
        }
        guard let product = try? JSONDecoder().decode(Product.self, from: data),
              let code = product.productCode,
              (1...16).contains(code.count),
              code.unicodeScalars.allSatisfy({
                  CharacterSet.uppercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "-_")).contains($0)
              }),
              let vendor = product.productVendor,
              !vendor.isEmpty else { return nil }
        return (code, vendor, product.versionSuffix?.isEmpty != false)
    }

    static func homebrewToken(inPath path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard let index = components.firstIndex(where: { $0 == "Caskroom" || $0 == "Cellar" }),
              index + 1 < components.count else { return nil }
        return components[index + 1]
    }

    static func parseElectronFeed(data: Data) -> ElectronUpdateFeed? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var provider = ""
        var owner = ""
        var repo = ""
        var urlText = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix(" ") && !line.hasPrefix("\t") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let value = Self.yamlScalar(parts[1])
            switch parts[0] {
            case "provider": provider = value.lowercased()
            case "owner": owner = value
            case "repo": repo = value
            case "url": urlText = value
            default: break
            }
        }
        if provider == "github", !owner.isEmpty, !repo.isEmpty {
            return .github(owner: owner, repo: repo)
        }
        if provider == "generic", let url = httpsURL(from: urlText) {
            return .generic(baseURL: url)
        }
        return nil
    }

    private static func yamlScalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }
}

// MARK: - Sparkle appcast parsing

struct AppcastItem: Equatable {
    let version: String
    let shortVersion: String?
    let downloadURL: URL?
    let releaseNotes: String?
    let releaseNotesURL: URL?
    let minimumSystemVersion: String?
    let isPrerelease: Bool

    var displayVersion: String {
        if let shortVersion, !shortVersion.isEmpty { return shortVersion }
        return version
    }
}

enum AppcastParser {
    static func parse(data: Data) -> [AppcastItem] {
        let delegate = AppcastParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.items
    }

    static func latestItem(in items: [AppcastItem]) -> AppcastItem? {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let containsStableRelease = items.contains { !$0.isPrerelease }
        let eligible = items.filter { item in
            !isTooNew(forCurrentOS: item.minimumSystemVersion, current: osVersion)
                && (!containsStableRelease || !item.isPrerelease)
        }
        return eligible.max { lhs, rhs in
            if !lhs.version.isEmpty, !rhs.version.isEmpty {
                let byBuild = AppVersionOrdering.compare(lhs.version, rhs.version)
                if byBuild != .orderedSame { return byBuild == .orderedAscending }
            }
            let byDisplay = AppVersionOrdering.compare(lhs.displayVersion, rhs.displayVersion)
            if byDisplay != .orderedSame { return byDisplay == .orderedAscending }
            return AppVersionOrdering.compare(lhs.version, rhs.version) == .orderedAscending
        }
    }

    static func plainText(fromHTML html: String) -> String {
        var text = html
        for pattern in [
            #"<\s*br\s*/?\s*>"#, #"</\s*(p|div|li|h[1-6]|tr)\s*>"#,
        ] {
            text = text.replacingOccurrences(of: pattern, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: #"<\s*li[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isTooNew(forCurrentOS minimumSystemVersion: String?, current: OperatingSystemVersion) -> Bool {
        guard let minimumSystemVersion, !minimumSystemVersion.isEmpty else { return false }
        let parts = minimumSystemVersion.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return false }
        if major > current.majorVersion { return true }
        if major < current.majorVersion { return false }
        if let minor = parts.dropFirst().first, minor > current.minorVersion { return true }
        return false
    }
}

private final class AppcastParserDelegate: NSObject, XMLParserDelegate {
    private struct ItemBuilder {
        var version = ""
        var shortVersion: String?
        var downloadURL: URL?
        var releaseNotes: String?
        var releaseNotesURL: URL?
        var minimumSystemVersion: String?
        var isPrerelease = false
    }

    private var current: ItemBuilder?
    private var currentText = ""
    private var descriptionText = ""
    private var descriptionDepth = 0
    private var hasMacEnclosure = false
    private var hasForeignEnclosure = false
    private(set) var items: [AppcastItem] = []

    private static func isMacEnclosure(_ attributeDict: [String: String]) -> Bool {
        guard let os = (attributeDict["sparkle:os"] ?? attributeDict["os"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !os.isEmpty else { return true }
        return os == "macos" || os == "osx"
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = qName ?? elementName
        if name == "item" {
            current = ItemBuilder()
            currentText = ""
            descriptionText = ""
            descriptionDepth = 0
            hasMacEnclosure = false
            hasForeignEnclosure = false
            if (attributeDict["sparkle:prerelease"] ?? attributeDict["prerelease"]) == "true" {
                current?.isPrerelease = true
            }
            return
        }
        guard current != nil else { return }
        if descriptionDepth > 0 {
            descriptionDepth += 1
            return
        }

        switch name {
        case "enclosure":
            guard attributeDict["sparkle:deltaFrom"] == nil, attributeDict["deltaFrom"] == nil else { break }
            guard Self.isMacEnclosure(attributeDict) else {
                hasForeignEnclosure = true
                break
            }
            hasMacEnclosure = true
            if let urlString = attributeDict["url"], let url = URL(string: urlString) {
                current?.downloadURL = url
            }
            if let build = attributeDict["sparkle:version"] ?? attributeDict["version"] {
                current?.version = build
            }
            if let marketing = attributeDict["sparkle:shortVersionString"] ?? attributeDict["shortVersionString"] {
                current?.shortVersion = marketing
            }
            if let minimumOS = attributeDict["sparkle:minimumSystemVersion"] ?? attributeDict["minimumSystemVersion"] {
                current?.minimumSystemVersion = minimumOS
            }
            if (attributeDict["sparkle:prerelease"] ?? attributeDict["prerelease"]) == "true" {
                current?.isPrerelease = true
            }
        case "sparkle:version", "version",
             "sparkle:shortVersionString", "shortVersionString",
             "sparkle:minimumSystemVersion", "minimumSystemVersion",
             "sparkle:prerelease", "prerelease",
             "sparkle:channel", "channel",
             "sparkle:releaseNotesLink", "releaseNotesLink",
             "link":
            currentText = ""
            if name == "link", current?.releaseNotesURL == nil,
               let href = attributeDict["href"], let url = URL(string: href) {
                current?.releaseNotesURL = url
            }
        case "description":
            descriptionText = ""
            descriptionDepth = 1
        default:
            if descriptionDepth > 0 { descriptionDepth += 1 }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard current != nil else { return }
        if descriptionDepth > 0 {
            descriptionText += string
        } else {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        self.parser(parser, foundCharacters: string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard current != nil else { return }
        let name = qName ?? elementName
        if descriptionDepth > 0, name != "description" {
            descriptionDepth -= 1
            return
        }

        switch name {
        case "item":
            var item = current!
            let notes = AppcastParser.plainText(fromHTML: descriptionText)
            item.releaseNotes = notes.isEmpty ? nil : notes
            let describesMacRelease = hasMacEnclosure || !hasForeignEnclosure
            if describesMacRelease, !item.version.isEmpty || item.shortVersion != nil {
                items.append(AppcastItem(
                    version: item.version,
                    shortVersion: item.shortVersion,
                    downloadURL: item.downloadURL,
                    releaseNotes: item.releaseNotes,
                    releaseNotesURL: item.releaseNotesURL,
                    minimumSystemVersion: item.minimumSystemVersion,
                    isPrerelease: item.isPrerelease
                ))
            }
            current = nil
        case "sparkle:version", "version":
            current?.version = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "sparkle:shortVersionString", "shortVersionString":
            current?.shortVersion = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "sparkle:minimumSystemVersion", "minimumSystemVersion":
            current?.minimumSystemVersion = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "sparkle:prerelease", "prerelease":
            if currentText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
                current?.isPrerelease = true
            }
        case "sparkle:channel", "channel":
            let channel = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !channel.isEmpty {
                current?.isPrerelease = true
            }
        case "sparkle:releaseNotesLink", "releaseNotesLink":
            if let url = InstalledAppUpdateSourceDetector.httpsURL(from: currentText) {
                current?.releaseNotesURL = url
            }
        case "link":
            if current?.releaseNotesURL == nil,
               let url = InstalledAppUpdateSourceDetector.httpsURL(from: currentText) {
                current?.releaseNotesURL = url
            }
        case "description":
            descriptionDepth = 0
        default:
            if descriptionDepth > 0 { descriptionDepth -= 1 }
        }
    }
}

// MARK: - Google Keystone (Omaha) update check

private struct KeystoneResponse {
    var appStatus: String?
    var updatecheckStatus: String?
    var manifestVersion: String?
    var downloadURL: URL?

    var isUpToDate: Bool {
        updatecheckStatus == "no-update"
    }
}

private enum KeystoneClient {
    static let productPages: [String: String] = [
        "com.google.Chrome": "https://www.google.com/chrome/",
        "com.google.drivefs": "https://www.google.com/drive/download/",
        "com.google.earth": "https://www.google.com/earth/versions/#earth-pro",
    ]

    static func requestXML(appID: String, currentVersion: String) -> String {
        let escapedID = appID
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <request protocol="3.0" ismachine="0">
            <os platform="mac" version="\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)" arch="\(processArchitecture)"/>
            <app appid="\(escapedID)" version="\(escaped(currentVersion))">
                <updatecheck/>
            </app>
        </request>
        """
    }

    private static var processArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func parseResponse(data: Data) -> KeystoneResponse {
        let delegate = KeystoneResponseDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        var result = delegate.response
        if let codebase = delegate.response.downloadURL {
            result.downloadURL = codebase
        }
        return result
    }

    static func productPage(for appID: String) -> URL? {
        productPages[appID].flatMap { URL(string: $0) }
    }
}

private final class KeystoneResponseDelegate: NSObject, XMLParserDelegate {
    private(set) var response = KeystoneResponse()
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch qName ?? elementName {
        case "app":
            response.appStatus = attributeDict["status"]
        case "updatecheck":
            response.updatecheckStatus = attributeDict["status"]
        case "manifest":
            response.manifestVersion = attributeDict["version"]
        case "url":
            if let codebase = attributeDict["codebase"], response.downloadURL == nil {
                response.downloadURL = URL(string: codebase)
            }
        case "package":
            if let name = attributeDict["name"], let base = response.downloadURL {
                let joined = base.absoluteString.hasSuffix("/")
                    ? base.absoluteString + name
                    : base.absoluteString + "/" + name
                response.downloadURL = URL(string: joined) ?? base
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
}

// MARK: - Bounded update metadata transport

private enum InstalledAppHTTPError: LocalizedError {
    case insecureResponse
    case responseTooLarge
    case tooManyRedirects

    var errorDescription: String? {
        switch self {
        case .insecureResponse: return "Update service redirected to an insecure address"
        case .responseTooLarge: return "Update metadata was unexpectedly large"
        case .tooManyRedirects: return "Update service redirected too many times"
        }
    }
}

private final class InstalledAppHTTPTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func install(_ task: URLSessionDataTask) -> Bool {
        lock.lock()
        self.task = task
        let cancelled = isCancelled
        lock.unlock()
        return cancelled
    }

    func cancel() -> URLSessionDataTask? {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        return task
    }
}

private final class InstalledAppHTTPDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Pending {
        let maximumBytes: Int
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
        var response: HTTPURLResponse?
        var data: Data
        var redirectCount = 0
    }

    static let maximumRedirects = 5

    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var failure: Error?
        lock.lock()
        if var state = pending[task.taskIdentifier] {
            state.redirectCount += 1
            if state.redirectCount > Self.maximumRedirects {
                failure = InstalledAppHTTPError.tooManyRedirects
            } else if request.url?.scheme?.lowercased() != "https" || request.url?.host?.isEmpty != false {
                failure = InstalledAppHTTPError.insecureResponse
            }
            pending[task.taskIdentifier] = state
        }
        lock.unlock()

        guard let failure else {
            completionHandler(request)
            return
        }
        fail(taskIdentifier: task.taskIdentifier, error: failure)
        completionHandler(nil)
        task.cancel()
    }

    func register(
        _ task: URLSessionDataTask,
        maximumBytes: Int,
        continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    ) {
        lock.lock()
        pending[task.taskIdentifier] = Pending(
            maximumBytes: maximumBytes,
            continuation: continuation,
            response: nil,
            data: Data()
        )
        lock.unlock()
    }

    func cancel(_ task: URLSessionDataTask) {
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        lock.lock()
        continuation = pending.removeValue(forKey: task.taskIdentifier)?.continuation
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
        task.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        let isSecure = http?.url?.scheme?.lowercased() == "https"
        let isTooLarge = response.expectedContentLength > 0
            && response.expectedContentLength > Int64(maximumBytes(for: dataTask.taskIdentifier) ?? 0)
        guard let http, isSecure, !isTooLarge else {
            fail(
                taskIdentifier: dataTask.taskIdentifier,
                error: isTooLarge ? InstalledAppHTTPError.responseTooLarge : InstalledAppHTTPError.insecureResponse
            )
            completionHandler(.cancel)
            return
        }

        lock.lock()
        if var state = pending[dataTask.taskIdentifier] {
            state.response = http
            if response.expectedContentLength > 0 {
                state.data.reserveCapacity(
                    min(Int(response.expectedContentLength), state.maximumBytes)
                )
            }
            pending[dataTask.taskIdentifier] = state
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var overflowContinuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        lock.lock()
        if var state = pending[dataTask.taskIdentifier] {
            if data.count > state.maximumBytes - state.data.count {
                overflowContinuation = state.continuation
                pending.removeValue(forKey: dataTask.taskIdentifier)
            } else {
                state.data.append(data)
                pending[dataTask.taskIdentifier] = state
            }
        }
        lock.unlock()

        if let overflowContinuation {
            overflowContinuation.resume(throwing: InstalledAppHTTPError.responseTooLarge)
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let state: Pending?
        lock.lock()
        state = pending.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let state else { return }

        if let error {
            state.continuation.resume(throwing: error)
        } else if let response = state.response {
            state.continuation.resume(returning: (state.data, response))
        } else {
            state.continuation.resume(throwing: InstalledAppHTTPError.insecureResponse)
        }
    }

    private func maximumBytes(for taskIdentifier: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return pending[taskIdentifier]?.maximumBytes
    }

    private func fail(taskIdentifier: Int, error: Error) {
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        lock.lock()
        continuation = pending.removeValue(forKey: taskIdentifier)?.continuation
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

private enum InstalledAppHTTPClient {
    static let defaultMaximumBytes = 2 * 1_024 * 1_024
    private static let delegate = InstalledAppHTTPDelegate()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 25
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 0,
            diskPath: nil
        )
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()

    static func data(
        for request: URLRequest,
        maximumBytes: Int = defaultMaximumBytes
    ) async throws -> (Data, HTTPURLResponse) {
        guard maximumBytes > 0 else { throw InstalledAppHTTPError.responseTooLarge }
        let taskBox = InstalledAppHTTPTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                delegate.register(
                    task,
                    maximumBytes: maximumBytes,
                    continuation: continuation
                )
                if taskBox.install(task) || Task.isCancelled {
                    delegate.cancel(task)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            if let task = taskBox.cancel() { delegate.cancel(task) }
        }
    }
}

// MARK: - electron-updater feeds

private struct ElectronGitHubRelease: Codable {
    struct Asset: Codable {
        let name: String
        let browserDownloadUrl: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String?
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body
        case htmlUrl = "html_url"
        case prerelease, assets
    }

    var version: String {
        var value = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["release-", "version-", "desktop-v", "desktop-"]
        where value.lowercased().hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        return value
    }
}

private enum ElectronUpdater {
    static func checkGitHub(
        owner: String,
        repo: String,
        currentVersion: String,
        requireMacAsset: Bool = true
    ) async -> InstalledAppUpdateEntry.Status {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=10") else {
            return .error("Invalid update URL")
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return .error("GitHub releases unavailable")
            }
            let releases = try JSONDecoder().decode([ElectronGitHubRelease].self, from: data)
            let stableReleases = releases.filter { !$0.prerelease }
            let candidates = stableReleases.isEmpty ? releases : stableReleases
            guard let release = candidates.max(by: {
                AppVersionOrdering.compare($0.version, $1.version) == .orderedAscending
            }),
                  !release.version.isEmpty else {
                return .error("No releases found")
            }
            if AppVersionOrdering.isNewer(release.version, than: currentVersion) {
                let asset = macAsset(in: release)
                guard asset != nil || !requireMacAsset else {
                    return .error("No macOS asset in latest release")
                }
                return .updateAvailable(
                    latestVersion: release.version,
                    downloadURL: requireMacAsset ? asset?.browserDownloadUrl : nil,
                    pageURL: release.htmlUrl.flatMap { URL(string: $0) },
                    releaseNotes: release.body?.isEmpty == false ? release.body : nil,
                    releaseNotesURL: release.htmlUrl.flatMap { URL(string: $0) }
                )
            }
            return .upToDate(latestVersion: release.version)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func macAsset(in release: ElectronGitHubRelease) -> ElectronGitHubRelease.Asset? {
        let macAssets = release.assets.filter { $0.name.hasSuffix(".dmg") || $0.name.hasSuffix(".zip") }
        return macAssets.first { $0.name.hasSuffix(".dmg") }
            ?? macAssets.first { $0.name.lowercased().contains("mac") || $0.name.lowercased().contains("darwin") }
            ?? macAssets.first
    }

    static func checkGeneric(baseURL: URL, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        let manifestURL = baseURL.absoluteString.hasSuffix("/")
            ? baseURL.appendingPathComponent("latest-mac.yml")
            : URL(string: baseURL.absoluteString + "/latest-mac.yml") ?? baseURL.appendingPathComponent("latest-mac.yml")
        do {
            var request = URLRequest(url: manifestURL)
            request.timeoutInterval = 12
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return .error("Update manifest unavailable")
            }
            guard let text = String(data: data, encoding: .utf8),
                  let parsed = parseLatestMacYAML(text) else {
                return .error("Malformed update manifest")
            }
            if AppVersionOrdering.isNewer(parsed.version, than: currentVersion) {
                let path = parsed.path ?? ""
                guard !path.isEmpty, let downloadURL = URL(string: baseURL.absoluteString.hasSuffix("/")
                    ? baseURL.absoluteString + path
                    : baseURL.absoluteString + "/" + path) else {
                    return .error("Update manifest has no download")
                }
                return .updateAvailable(
                    latestVersion: parsed.version,
                    downloadURL: downloadURL,
                    pageURL: nil,
                    releaseNotes: parsed.releaseNotes,
                    releaseNotesURL: nil
                )
            }
            return .upToDate(latestVersion: parsed.version)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func parseLatestMacYAML(_ text: String) -> (version: String, path: String?, releaseNotes: String?)? {
        var version = ""
        var path: String?
        var notes: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix(" ") && !line.hasPrefix("\t") else { continue }
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: ":", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "version": version = parts[1]
            case "path": path = parts[1]
            case "releaseNotes":
                let note = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                notes = note.isEmpty ? nil : note
            default: break
            }
        }
        guard !version.isEmpty else { return nil }
        return (version, path, notes)
    }
}

// MARK: - Mac App Store lookup

private struct AppStoreLookupResponse: Codable {
    struct Result: Codable {
        let bundleId: String?
        let kind: String?
        let version: String?
        let trackViewUrl: String?
        let releaseNotes: String?
        let minimumOsVersion: String?
    }
    let results: [Result]
}

private enum AppStoreClient {
    typealias CheckRequest = (id: String, bundleIdentifier: String, currentVersion: String)
    typealias CheckResult = (id: String, status: InstalledAppUpdateEntry.Status)

    static let batchSize = 20

    static func lookupURL(bundleIdentifiers: [String], country: String) -> URL? {
        guard !bundleIdentifiers.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIdentifiers.joined(separator: ",")),
            URLQueryItem(name: "entity", value: "macSoftware"),
            URLQueryItem(name: "country", value: country),
        ]
        return components?.url
    }

    static func checkBatch(_ requests: [CheckRequest]) async -> [CheckResult] {
        guard !requests.isEmpty else { return [] }
        let storefront = Locale.current.region?.identifier.lowercased() ?? "us"
        let identifiers = Array(Set(requests.map { $0.bundleIdentifier })).sorted()
        guard let url = lookupURL(bundleIdentifiers: identifiers, country: storefront) else {
            return requests.map { ($0.id, .unsupported) }
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return requests.map { ($0.id, .error("App Store lookup failed")) }
            }
            let lookup = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            let osVersion = ProcessInfo.processInfo.operatingSystemVersion
            var resultsByBundleID: [String: AppStoreLookupResponse.Result] = [:]
            for result in lookup.results {
                guard result.kind == "mac-software",
                      let bundleID = result.bundleId?.lowercased(), !bundleID.isEmpty,
                      !AppcastParser.isTooNew(forCurrentOS: result.minimumOsVersion, current: osVersion),
                      resultsByBundleID[bundleID] == nil else { continue }
                resultsByBundleID[bundleID] = result
            }
            return requests.map { request in
                (request.id, status(for: request, result: resultsByBundleID[request.bundleIdentifier.lowercased()]))
            }
        } catch {
            return requests.map { ($0.id, .error(error.localizedDescription)) }
        }
    }

    private static func status(
        for request: CheckRequest,
        result: AppStoreLookupResponse.Result?
    ) -> InstalledAppUpdateEntry.Status {
        guard let result, let latest = result.version, !latest.isEmpty else {
            return .unsupported
        }
        let pageURL = result.trackViewUrl.flatMap { URL(string: $0) }
        if AppVersionOrdering.isNewer(latest, than: request.currentVersion) {
            return .updateAvailable(
                latestVersion: latest,
                downloadURL: nil,
                pageURL: pageURL,
                releaseNotes: result.releaseNotes,
                releaseNotesURL: pageURL
            )
        }
        return .upToDate(latestVersion: latest)
    }
}

// MARK: - Homebrew casks

private struct BrewCaskInfo: Codable {
    let token: String?
    let version: String?
    let installed: String?
    let outdated: Bool?
}

private struct BrewInfoResponse: Codable {
    let casks: [BrewCaskInfo]?
}

struct HomebrewCaskRecord: Equatable, Sendable {
    let token: String
    let installedVersion: String?
    let appPaths: [String]
    let requiresAdministrator: Bool
}

enum HomebrewCaskInventory {
    static func load() async -> [String: HomebrewCaskRecord] {
        guard let brew = HomebrewClient.executablePath() else { return [:] }
        guard let result = await HomebrewClient.runInventoryProcess(
            executable: URL(fileURLWithPath: brew),
            arguments: ["info", "--cask", "--json=v2", "--installed"]
        ), result.exitCode == 0 else { return [:] }
        let records = parseRecords(result.output)
        return ownershipMap(
            for: records,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    static func parseRecords(_ data: Data) -> [HomebrewCaskRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap(parseRecord)
    }

    private static func parseRecord(_ item: [String: Any]) -> HomebrewCaskRecord? {
        guard let token = item["token"] as? String, HomebrewCommand.isSafeToken(token) else { return nil }
        let installed = (item["installed"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artifacts = item["artifacts"] as? [Any] ?? []
        var appPaths: [String] = []
        for case let artifact as [String: Any] in artifacts {
            guard let apps = artifact["app"] as? [Any] else { continue }
            var targets: [String] = []
            var sources: [String] = []
            if let target = artifact["target"] as? String { targets.append(target) }
            for app in apps {
                if let source = app as? String {
                    sources.append(source)
                } else if let mapping = app as? [String: Any], let target = mapping["target"] as? String {
                    targets.append(target)
                }
            }
            for candidate in targets.isEmpty ? sources : targets
            where candidate.hasSuffix(".app") && !candidate.contains("..") && !appPaths.contains(candidate) {
                appPaths.append(candidate)
            }
        }
        return HomebrewCaskRecord(
            token: token,
            installedVersion: installed?.isEmpty == false ? installed : nil,
            appPaths: appPaths,
            requiresAdministrator: HomebrewCaskPrivilege.requiresAdministrator(artifacts: artifacts)
        )
    }

    static func ownershipMap(
        for records: [HomebrewCaskRecord],
        homeDirectory: String,
        fileManager: FileManager = .default
    ) -> [String: HomebrewCaskRecord] {
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: homeDirectory, isDirectory: true).appendingPathComponent("Applications", isDirectory: true),
        ]
        var map: [String: HomebrewCaskRecord] = [:]
        for record in records {
            for declared in record.appPaths {
                let candidates: [URL]
                if declared.hasPrefix("/") {
                    candidates = [URL(fileURLWithPath: declared)]
                } else {
                    let fileName = URL(fileURLWithPath: declared).lastPathComponent
                    candidates = applicationRoots.map { $0.appendingPathComponent(fileName, isDirectory: true) }
                }
                guard let present = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else { continue }
                let path = present.standardizedFileURL.path
                if map[path] == nil { map[path] = record }
            }
        }
        return map
    }

    static func uninstall(_ record: HomebrewCaskRecord) async -> String? {
        let command = "brew uninstall --cask \(record.token)"
        guard !record.requiresAdministrator else {
            return "Homebrew needs your administrator password to finish removing this cask. Run “\(command)” in Terminal."
        }
        switch await HomebrewClient.uninstallCask(token: record.token) {
        case .succeeded:
            return nil
        case .needsAdministrator:
            return "Homebrew needs your administrator password to finish removing this cask. Run “\(command)” in Terminal."
        case .failed(let summary):
            return "Homebrew could not remove the cask receipt: \(summary ?? "run “\(command)” in Terminal for details")."
        }
    }

    static func caskroomURL(token: String) -> URL? {
        HomebrewClient.caskroomURL(token: token)
    }
}

private struct BrewAPICaskResponse: Decodable {
    let token: String?
    let version: String?
}

enum HomebrewUpdateDecision {
    static func shouldOffer(
        latestVersion: String?,
        currentVersion: String,
        receiptIsOutdated: Bool
    ) -> Bool {
        if let latestVersion,
           latestVersion.contains(where: \.isNumber),
           currentVersion.contains(where: \.isNumber) {
            return AppVersionOrdering.isNewer(latestVersion, than: currentVersion)
        }
        return receiptIsOutdated
    }
}

private typealias BrewProcessResult = (exitCode: Int32, output: Data)

private enum BrewProcessTree {
    struct Member: Hashable {
        let pid: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    static func member(_ pid: pid_t) -> Member? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Member(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
    }

    static func isAlive(_ member: Member) -> Bool {
        self.member(member.pid) == member
    }

    static func descendants(of root: pid_t, limit: Int = 256) -> [Member] {
        var result: [Member] = []
        var queue: [pid_t] = [root]
        var visited: Set<pid_t> = [root]
        var buffer = [pid_t](repeating: 0, count: 256)
        while !queue.isEmpty, result.count < limit {
            let parent = queue.removeFirst()
            let count = buffer.withUnsafeMutableBytes { bytes in
                proc_listchildpids(parent, bytes.baseAddress, Int32(bytes.count))
            }
            guard count > 0 else { continue }
            for child in buffer.prefix(min(Int(count), buffer.count))
            where child > 0 && visited.insert(child).inserted {
                if let member = member(child) {
                    result.append(member)
                    queue.append(child)
                }
            }
        }
        return result
    }
}

private final class BrewProcessState: @unchecked Sendable {
    private struct RunningProcess {
        let process: Process
        let pid: pid_t
        let ownsProcessGroup: Bool
    }

    private let lock = NSLock()
    private let outputQueue = DispatchQueue(
        label: "com.cshariq.sapphire.homebrew-output",
        qos: .utility
    )
    private var maximumOutputBytes = 5 * 1_024 * 1_024
    private var keepsOutputTail = false
    private var knownDescendants: Set<BrewProcessTree.Member> = []

    private var continuation: CheckedContinuation<BrewProcessResult?, Never>?
    private var running: RunningProcess?
    private var timeoutWork: DispatchWorkItem?
    private var forceKillWork: DispatchWorkItem?
    private var failureRequested = false
    private var terminationSignalSent = false
    private var finished = false

    private var output = Data()
    private var discardFurtherOutput = false
    private var readSource: DispatchSourceRead?
    private var readDescriptor: Int32 = -1
    private var readHandle: FileHandle?
    private var writeHandle: FileHandle?

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        captureOutput: Bool,
        mergeStandardError: Bool = false,
        keepOutputTail: Bool = false
    ) async -> BrewProcessResult? {
        if keepOutputTail {
            outputQueue.sync {
                keepsOutputTail = true
                maximumOutputBytes = 256 * 1_024
            }
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                DispatchQueue.global(qos: .utility).async { [self] in
                    launch(
                        executable: executable,
                        arguments: arguments,
                        environment: environment,
                        timeout: timeout,
                        captureOutput: captureOutput,
                        mergeStandardError: mergeStandardError
                    )
                }
            }
        } onCancel: { [self] in
            requestTermination()
        }
    }

    private func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        captureOutput: Bool,
        mergeStandardError: Bool
    ) {
        guard !hasFailureRequest else {
            outputQueue.async { [self] in finish(nil) }
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        if captureOutput {
            let configured = outputQueue.sync { [self] in
                configureOutput(for: process, mergeStandardError: mergeStandardError)
            }
            guard configured else {
                outputQueue.async { [self] in
                    cleanUpOutput()
                    finish(nil)
                }
                return
            }
        } else {
            process.standardOutput = FileHandle.nullDevice
        }

        guard !hasFailureRequest else {
            outputQueue.async { [self] in
                cleanUpOutput()
                finish(nil)
            }
            return
        }

        process.terminationHandler = { [weak self] process in
            self?.processDidExit(process)
        }

        do {
            try process.run()
            outputQueue.sync { [self] in closeParentWriteHandle() }
        } catch {
            outputQueue.async { [self] in
                cleanUpOutput()
                finish(nil)
            }
            return
        }

        let pid = process.processIdentifier
        let child = RunningProcess(
            process: process,
            pid: pid,
            ownsProcessGroup: pid > 0 && Darwin.getpgid(pid) == pid
        )

        var shouldTerminate = false
        lock.lock()
        if !finished {
            running = child
            if failureRequested, !terminationSignalSent {
                terminationSignalSent = true
                shouldTerminate = true
            }
        }
        lock.unlock()

        if shouldTerminate {
            terminate(child)
        } else {
            scheduleTimeout(after: timeout)
        }
    }

    private var hasFailureRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failureRequested
    }

    private func requestTermination() {
        var child: RunningProcess?
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        failureRequested = true
        if let running, !terminationSignalSent {
            terminationSignalSent = true
            child = running
        }
        lock.unlock()

        if let child { terminate(child) }
    }

    private func scheduleTimeout(after timeout: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.requestTermination() }
        lock.lock()
        let shouldSchedule = !finished && !failureRequested
        if shouldSchedule { timeoutWork = work }
        lock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeout,
            execute: work
        )
    }

    private func terminate(_ child: RunningProcess) {
        send(SIGTERM, to: child)

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            lock.lock()
            let target = !finished && failureRequested ? running : nil
            lock.unlock()
            if let target, target.process.isRunning {
                send(SIGKILL, to: target)
            } else {
                killRememberedDescendants(SIGKILL)
            }
        }
        lock.lock()
        let shouldSchedule = !finished && forceKillWork == nil
        if shouldSchedule { forceKillWork = work }
        lock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 5,
            execute: work
        )
    }

    private func send(_ signal: Int32, to child: RunningProcess) {
        let descendants = BrewProcessTree.descendants(of: child.pid)
        lock.lock()
        knownDescendants.formUnion(descendants)
        lock.unlock()
        killRememberedDescendants(signal)
        guard child.process.isRunning else { return }
        if child.ownsProcessGroup, Darwin.getpgid(child.pid) == child.pid {
            _ = Darwin.kill(-child.pid, signal)
        } else {
            _ = Darwin.kill(child.pid, signal)
        }
    }

    private func killRememberedDescendants(_ signal: Int32) {
        lock.lock()
        let members = knownDescendants
        lock.unlock()
        for member in members where BrewProcessTree.isAlive(member) {
            _ = Darwin.kill(member.pid, signal)
        }
    }

    private func configureOutput(for process: Process, mergeStandardError: Bool) -> Bool {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let descriptor = reader.fileDescriptor
        let flags = Darwin.fcntl(descriptor, F_GETFL)
        guard flags >= 0, Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            try? reader.close()
            try? pipe.fileHandleForWriting.close()
            return false
        }

        process.standardOutput = pipe
        if mergeStandardError { process.standardError = pipe }
        readDescriptor = descriptor
        readHandle = reader
        writeHandle = pipe.fileHandleForWriting

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: outputQueue)
        source.setEventHandler { [weak self] in self?.drainAvailableOutput() }
        source.setCancelHandler { try? reader.close() }
        readSource = source
        source.resume()
        return true
    }

    private func drainAvailableOutput() {
        guard readDescriptor >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var exceededLimit = false

        for _ in 0..<16 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(readDescriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                if keepsOutputTail {
                    output.append(contentsOf: buffer.prefix(count))
                    if output.count > maximumOutputBytes {
                        output.removeFirst(output.count - maximumOutputBytes)
                    }
                } else if !discardFurtherOutput {
                    if count <= maximumOutputBytes - output.count {
                        output.append(contentsOf: buffer.prefix(count))
                    } else {
                        discardFurtherOutput = true
                        exceededLimit = true
                    }
                }
                continue
            }
            if count == 0 {
                cancelReadSource()
                break
            }
            if errno == EINTR { continue }
            break
        }

        if exceededLimit { requestTermination() }
    }

    private func processDidExit(_ process: Process) {
        let status = process.terminationStatus
        outputQueue.async { [self] in
            drainAvailableOutput()
            cleanUpOutput()
            finish((status, output))
        }
    }

    private func cancelReadSource() {
        guard let source = readSource else { return }
        source.setEventHandler {}
        source.cancel()
        readSource = nil
        readDescriptor = -1
        readHandle = nil
    }

    private func cleanUpOutput() {
        closeParentWriteHandle()
        cancelReadSource()
    }

    private func closeParentWriteHandle() {
        try? writeHandle?.close()
        writeHandle = nil
    }

    private func finish(_ result: BrewProcessResult?) {
        var awaiting: CheckedContinuation<BrewProcessResult?, Never>?
        var timeout: DispatchWorkItem?
        var forceKill: DispatchWorkItem?
        var process: Process?
        var delivered = result

        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        if failureRequested { delivered = nil }
        awaiting = continuation
        continuation = nil
        timeout = timeoutWork
        timeoutWork = nil
        forceKill = forceKillWork
        forceKillWork = nil
        process = running?.process
        running = nil
        lock.unlock()

        timeout?.cancel()
        forceKill?.cancel()
        process?.terminationHandler = nil
        awaiting?.resume(returning: delivered)
    }
}

private enum HomebrewClient {
    typealias CheckRequest = (id: String, token: String, currentVersion: String)
    typealias CheckResult = (id: String, status: InstalledAppUpdateEntry.Status, requiresAdministrator: Bool)

    enum UpgradeOutcome: Equatable {
        case succeeded
        case needsAdministrator
        case failed(summary: String?)
    }

    static func executablePath() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func normalizedVersion(_ raw: String?) -> String? {
        guard var version = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else { return nil }
        if isLatestSentinel(version) || version.hasPrefix(":") { return nil }
        if let comma = version.firstIndex(of: ",") {
            version = String(version[..<comma])
        }
        return version.isEmpty ? nil : version
    }

    private static func isLatestSentinel(_ raw: String?) -> Bool {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return value == "latest" || value == ":latest"
    }

    static func environment() -> [String: String] {
        HomebrewCommand.environment(
            inherited: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    static func check(token: String, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        let result = await checkBatch([
            (id: token, token: token, currentVersion: currentVersion)
        ])
        return result.first?.status ?? .error("brew info failed for this cask")
    }

    private static func administratorTokens(in output: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return [] }
        var tokens = Set<String>()
        for cask in casks {
            guard let token = cask["token"] as? String,
                  let artifacts = cask["artifacts"] as? [Any],
                  HomebrewCaskPrivilege.requiresAdministrator(artifacts: artifacts) else { continue }
            tokens.insert(token.lowercased())
        }
        return tokens
    }

    static func checkBatch(_ requests: [CheckRequest]) async -> [CheckResult] {
        guard !requests.isEmpty else { return [] }
        guard let brew = executablePath() else {
            return requests.map { ($0.id, .error("Homebrew is not installed"), false) }
        }
        let tokens = Array(Set(requests.map { $0.token })).sorted().filter(HomebrewCommand.isSafeToken)
        guard !tokens.isEmpty else {
            return requests.map { ($0.id, .error("Unrecognised Homebrew cask name"), false) }
        }
        guard let result = await Self.runProcess(
            executable: URL(fileURLWithPath: brew),
            arguments: ["info", "--cask", "--json=v2"] + tokens,
            timeout: max(30, TimeInterval(tokens.count) * 2),
            captureOutput: true
        ), result.exitCode == 0 else {
            return requests.map { ($0.id, .error("brew info failed for this cask"), false) }
        }

        let casks = (try? JSONDecoder().decode(BrewInfoResponse.self, from: result.output))?.casks ?? []
        let adminTokens = administratorTokens(in: result.output)
        let caskByToken = Dictionary(
            casks.compactMap { cask in cask.token.map { ($0.lowercased(), cask) } },
            uniquingKeysWith: { first, _ in first }
        )
        let apiVersions = await latestVersionsFromAPI(tokens: tokens)
        return requests.map { request in
            let key = request.token.lowercased()
            let status = status(for: request, cask: caskByToken[key], apiVersion: apiVersions[key])
            return (request.id, status, adminTokens.contains(key))
        }
    }

    private static func latestVersionsFromAPI(tokens: [String]) async -> [String: String] {
        await withTaskGroup(of: (String, String)?.self) { group in
            var iterator = tokens.makeIterator()
            var primed = 0
            while primed < 4, let token = iterator.next() {
                group.addTask { await latestVersionFromAPI(token: token) }
                primed += 1
            }
            var versions: [String: String] = [:]
            while let result = await group.next() {
                if let (token, version) = result { versions[token.lowercased()] = version }
                if let token = iterator.next() {
                    group.addTask { await latestVersionFromAPI(token: token) }
                }
            }
            return versions
        }
    }

    private static func latestVersionFromAPI(token: String) async -> (String, String)? {
        guard HomebrewCommand.isSafeToken(token),
              let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://formulae.brew.sh/api/cask/\(encoded).json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        guard let loaded = try? await InstalledAppHTTPClient.data(for: request, maximumBytes: 512 * 1_024),
              (200..<300).contains(loaded.1.statusCode),
              let response = try? JSONDecoder().decode(BrewAPICaskResponse.self, from: loaded.0),
              let version = response.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return nil }
        return (token, version)
    }

    private static func status(
        for request: CheckRequest,
        cask: BrewCaskInfo?,
        apiVersion: String?
    ) -> InstalledAppUpdateEntry.Status {
        guard let cask else {
            return .error("Unknown cask “\(request.token)”")
        }
        let latest = normalizedVersion(apiVersion ?? cask.version)
        let currentVersion = request.currentVersion.contains(where: \.isNumber)
            ? request.currentVersion
            : (normalizedVersion(cask.installed) ?? request.currentVersion)
        let request = (id: request.id, token: request.token, currentVersion: currentVersion)
        if HomebrewUpdateDecision.shouldOffer(
            latestVersion: latest,
            currentVersion: request.currentVersion,
            receiptIsOutdated: cask.outdated == true
        ) {
            return .updateAvailable(
                latestVersion: latest ?? "Latest",
                downloadURL: nil,
                pageURL: nil,
                releaseNotes: nil,
                releaseNotesURL: nil
            )
        }
        if let latest,
           latest.contains(where: \.isNumber),
           request.currentVersion.contains(where: \.isNumber),
           AppVersionOrdering.compare(latest, request.currentVersion) == .orderedAscending {
            let installed = request.currentVersion.isEmpty ? latest : request.currentVersion
            return .upToDate(latestVersion: installed)
        }
        if latest == nil, isLatestSentinel(cask.version) {
            let installed = request.currentVersion.isEmpty ? "Latest" : request.currentVersion
            return .upToDate(latestVersion: installed)
        }
        guard let latest else {
            return .error("Homebrew returned no comparable version for “\(request.token)”")
        }
        return .upToDate(latestVersion: latest)
    }

    static func upgrade(tokens: [String]) async -> UpgradeOutcome {
        guard let brew = executablePath() else {
            return .failed(summary: "Homebrew is not installed")
        }
        guard let arguments = HomebrewCommand.upgradeArguments(tokens: tokens) else {
            return .failed(summary: "Unrecognised Homebrew cask name")
        }
        guard let result = await Self.runProcess(
            executable: URL(fileURLWithPath: brew),
            arguments: arguments,
            timeout: HomebrewCommand.upgradeTimeout(caskCount: tokens.count),
            captureOutput: true,
            mergeStandardError: true,
            keepOutputTail: true
        ) else {
            return .failed(summary: "brew upgrade timed out or was cancelled")
        }
        if result.exitCode == 0 { return .succeeded }
        let text = String(decoding: result.output, as: UTF8.self)
        if HomebrewCaskPrivilege.outputRequestsAdministrator(text) { return .needsAdministrator }
        return .failed(summary: HomebrewCommand.failureSummary(text))
    }

    static func uninstallCask(token: String) async -> UpgradeOutcome {
        guard let brew = executablePath() else {
            return .failed(summary: "Homebrew is not installed")
        }
        guard HomebrewCommand.isSafeToken(token) else {
            return .failed(summary: "Unrecognised Homebrew cask name")
        }
        guard let result = await Self.runProcess(
            executable: URL(fileURLWithPath: brew),
            arguments: ["uninstall", "--cask", token],
            timeout: 5 * 60,
            captureOutput: true,
            mergeStandardError: true,
            keepOutputTail: true
        ) else {
            return .failed(summary: "brew uninstall timed out or was cancelled")
        }
        if result.exitCode == 0 { return .succeeded }
        let text = String(decoding: result.output, as: UTF8.self)
        if HomebrewCaskPrivilege.outputRequestsAdministrator(text) { return .needsAdministrator }
        return .failed(summary: HomebrewCommand.failureSummary(text))
    }

    static func caskroomURL(token: String) -> URL? {
        guard let brew = executablePath(), HomebrewCommand.isSafeToken(token) else { return nil }
        let prefix = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent()
        return prefix.appendingPathComponent("Caskroom", isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
    }

    static func runInventoryProcess(executable: URL, arguments: [String]) async -> BrewProcessResult? {
        await Self.runProcess(
            executable: executable,
            arguments: arguments,
            timeout: 90,
            captureOutput: true
        )
    }

    static func openUpgradeInTerminal(tokens: [String]) async -> Bool {
        guard let brew = executablePath(),
              let script = HomebrewCommand.terminalScript(brewPath: brew, tokens: tokens) else { return false }
        let scriptURL: URL? = await Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Sapphire-brew-upgrade-\(UUID().uuidString).command")
            do {
                try Data(script.utf8).write(to: url, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                return url
            } catch {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
        }.value
        guard let scriptURL else { return false }
        let opened = await MainActor.run { NSWorkspace.shared.open(scriptURL) }
        if !opened {
            try? FileManager.default.removeItem(at: scriptURL)
        }
        return opened
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        captureOutput: Bool,
        mergeStandardError: Bool = false,
        keepOutputTail: Bool = false
    ) async -> BrewProcessResult? {
        await BrewProcessState().run(
            executable: executable,
            arguments: arguments,
            environment: environment(),
            timeout: timeout,
            captureOutput: captureOutput,
            mergeStandardError: mergeStandardError,
            keepOutputTail: keepOutputTail
        )
    }
}

// MARK: - Mozilla updates

private enum MozillaUpdater {
    static func check(product: MozillaProduct, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        guard let url = URL(string: "https://product-details.mozilla.org/1.0/\(product.rawValue)_versions.json") else {
            return .error("Invalid update URL")
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return .error("Mozilla version info unavailable")
            }
            let versions = try JSONDecoder().decode([String: String].self, from: data)
            guard let latest = versions[product.latestVersionKey], !latest.isEmpty else {
                return .error("No release information found")
            }
            if AppVersionOrdering.isNewer(latest, than: currentVersion) {
                let downloadURL = URL(string: "https://download.mozilla.org/?product=\(product.downloadProduct)&os=osx&lang=en-US")
                return .updateAvailable(
                    latestVersion: latest,
                    downloadURL: downloadURL,
                    pageURL: URL(string: "https://www.mozilla.org/"),
                    releaseNotes: nil,
                    releaseNotesURL: nil
                )
            }
            return .upToDate(latestVersion: latest)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - App-declared JSON manifests

struct ParsedJSONUpdateManifest: Equatable {
    let version: String
    let releaseNotes: String?
    let releaseNotesURL: URL?
}

enum JSONUpdateManifestParser {
    static func parse(data: Data) -> ParsedJSONUpdateManifest? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var payload = root

        if let currentRelease = string(in: root, keys: ["currentRelease"]),
           let releases = root["releases"] as? [[String: Any]],
           let selected = releases.first(where: { string(in: $0, keys: ["version"]) == currentRelease }),
           let updateTo = selected["updateTo"] as? [String: Any] {
            payload.merge(updateTo) { _, selectedValue in selectedValue }
            payload["version"] = currentRelease
        }

        guard let version = string(
            in: payload,
            keys: ["version", "latest_version", "latestVersion", "app_version", "currentRelease"]
        ),
        (1...128).contains(version.count),
        version.contains(where: \.isNumber) else { return nil }

        let notes = string(in: payload, keys: ["release_notes", "releaseNotes", "notes"])
            .map { String($0.prefix(20_000)) }
        let pageText = string(
            in: payload,
            keys: ["release_notes_url", "releaseNotesURL", "page_url", "html_url"]
        )
        return ParsedJSONUpdateManifest(
            version: version,
            releaseNotes: notes,
            releaseNotesURL: InstalledAppUpdateSourceDetector.httpsURL(from: pageText)
        )
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

private enum JSONManifestUpdater {
    static func check(url: URL, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            if http.statusCode == 204 {
                return .upToDate(latestVersion: currentVersion)
            }
            guard (200..<300).contains(http.statusCode),
                  let release = JSONUpdateManifestParser.parse(data: data) else {
                return .error("App update manifest unavailable")
            }
            if AppVersionOrdering.isNewer(release.version, than: currentVersion) {
                return .updateAvailable(
                    latestVersion: release.version,
                    downloadURL: nil,
                    pageURL: release.releaseNotesURL,
                    releaseNotes: release.releaseNotes,
                    releaseNotesURL: release.releaseNotesURL
                )
            }
            return .upToDate(latestVersion: release.version)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - Visual Studio Code update service

private struct VSCodeUpdateResponse: Decodable {
    let name: String?
    let productVersion: String?
    let notes: String?
}

private enum VSCodeUpdater {
    static func check(feed: VSCodeUpdateFeed, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        #if arch(arm64)
        let platform = "darwin-arm64"
        #else
        let platform = "darwin"
        #endif
        let url = feed.baseURL
            .appendingPathComponent("api/update")
            .appendingPathComponent(platform)
            .appendingPathComponent(feed.quality)
            .appendingPathComponent(feed.commit)
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            if http.statusCode == 204 {
                return .upToDate(latestVersion: currentVersion)
            }
            guard (200..<300).contains(http.statusCode) else {
                return .error("Visual Studio Code update service unavailable")
            }
            let release = try JSONDecoder().decode(VSCodeUpdateResponse.self, from: data)
            guard let latest = [release.productVersion, release.name]
                .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else {
                return .error("Visual Studio Code returned no release version")
            }
            let pageURL = URL(string: "https://code.visualstudio.com/updates")
            if AppVersionOrdering.isNewer(latest, than: currentVersion) {
                return .updateAvailable(
                    latestVersion: latest,
                    downloadURL: nil,
                    pageURL: pageURL,
                    releaseNotes: release.notes,
                    releaseNotesURL: pageURL
                )
            }
            return .upToDate(latestVersion: latest)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - Android Studio stable channel

struct AndroidStudioRelease: Equatable {
    let buildNumber: String
    let displayVersion: String
    let pageURL: URL?
}

enum AndroidStudioUpdateParser {
    static func latestStableRelease(data: Data) -> AndroidStudioRelease? {
        let delegate = AndroidStudioUpdateParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return nil }
        return delegate.releases.max {
            AppVersionOrdering.compare($0.buildNumber, $1.buildNumber) == .orderedAscending
        }
    }

    static func conciseVersion(from value: String, fallback: String) -> String {
        let pattern = #"\d{4}\.\d+(?:\.\d+)?(?:\s+Patch\s+\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              let range = Range(match.range, in: value) else { return fallback }
        return String(value[range])
    }
}

private final class AndroidStudioUpdateParserDelegate: NSObject, XMLParserDelegate {
    private(set) var releases: [AndroidStudioRelease] = []
    private var inStableChannel = false
    private var stablePageURL: URL?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch qName ?? elementName {
        case "channel":
            inStableChannel = attributeDict["status"]?.lowercased() == "release"
            stablePageURL = inStableChannel
                ? InstalledAppUpdateSourceDetector.httpsURL(from: attributeDict["url"])
                : nil
        case "build" where inStableChannel:
            guard let number = attributeDict["number"], !number.isEmpty else { return }
            let label = attributeDict["version"] ?? number
            releases.append(AndroidStudioRelease(
                buildNumber: number,
                displayVersion: AndroidStudioUpdateParser.conciseVersion(from: label, fallback: number),
                pageURL: stablePageURL
            ))
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if (qName ?? elementName) == "channel" {
            inStableChannel = false
            stablePageURL = nil
        }
    }
}

private enum AndroidStudioUpdater {
    static let feedURL = URL(string: "https://dl.google.com/android/studio/patches/updates.xml")!

    static func check(currentBuild: String) async -> InstalledAppUpdateEntry.Status {
        do {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 12
            request.setValue("application/xml", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode),
                  let latest = AndroidStudioUpdateParser.latestStableRelease(data: data) else {
                return .error("Android Studio update service unavailable")
            }
            if AppVersionOrdering.isNewer(latest.buildNumber, than: currentBuild) {
                return .updateAvailable(
                    latestVersion: latest.displayVersion,
                    downloadURL: nil,
                    pageURL: latest.pageURL,
                    releaseNotes: nil,
                    releaseNotesURL: latest.pageURL
                )
            }
            return .upToDate(latestVersion: latest.displayVersion)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - JetBrains product catalog

private struct JetBrainsRelease: Decodable {
    let version: String
    let build: String?
    let notesLink: String?
    let whatsnew: String?
}

struct ParsedJetBrainsRelease: Equatable {
    let version: String
    let notesLink: String?
}

enum JetBrainsReleaseParser {
    static func latestRelease(data: Data) -> ParsedJetBrainsRelease? {
        guard let catalog = try? JSONDecoder().decode([String: [JetBrainsRelease]].self, from: data),
              let latest = catalog.values.joined().max(by: {
                  AppVersionOrdering.compare($0.version, $1.version) == .orderedAscending
              }) else { return nil }
        return ParsedJetBrainsRelease(version: latest.version, notesLink: latest.notesLink)
    }
}

private enum JetBrainsUpdater {
    static func check(productCode: String, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        var components = URLComponents(string: "https://data.services.jetbrains.com/products/releases")!
        components.queryItems = [
            URLQueryItem(name: "code", value: productCode),
            URLQueryItem(name: "latest", value: "true"),
            URLQueryItem(name: "type", value: "release"),
        ]
        guard let url = components.url else { return .error("Invalid JetBrains update URL") }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return .error("JetBrains update service unavailable")
            }
            guard let latest = JetBrainsReleaseParser.latestRelease(data: data) else {
                return .error("No JetBrains release information found")
            }
            let pageURL = InstalledAppUpdateSourceDetector.httpsURL(from: latest.notesLink)
            if AppVersionOrdering.isNewer(latest.version, than: currentVersion) {
                return .updateAvailable(
                    latestVersion: latest.version,
                    downloadURL: nil,
                    pageURL: pageURL,
                    releaseNotes: nil,
                    releaseNotesURL: pageURL
                )
            }
            return .upToDate(latestVersion: latest.version)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - Microsoft Edge catalog

struct MicrosoftEdgeCatalogProduct: Decodable {
    struct Release: Decodable {
        let productVersion: String
        let platform: String

        enum CodingKeys: String, CodingKey {
            case productVersion = "ProductVersion"
            case platform = "Platform"
        }
    }

    let product: String
    let releases: [Release]

    enum CodingKeys: String, CodingKey {
        case product = "Product"
        case releases = "Releases"
    }
}

enum MicrosoftEdgeCatalogParser {
    static func latestVersion(data: Data, channel: MicrosoftEdgeChannel) -> String? {
        guard let catalog = try? JSONDecoder().decode([MicrosoftEdgeCatalogProduct].self, from: data),
              let product = catalog.first(where: { $0.product.caseInsensitiveCompare(channel.rawValue) == .orderedSame })
        else { return nil }
        return product.releases
            .filter { $0.platform.caseInsensitiveCompare("MacOS") == .orderedSame }
            .map(\.productVersion)
            .max { AppVersionOrdering.compare($0, $1) == .orderedAscending }
    }
}

private enum MicrosoftEdgeUpdater {
    static let catalogURL = URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!

    static func check(channel: MicrosoftEdgeChannel, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        do {
            var request = URLRequest(url: catalogURL)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode),
                  let latest = MicrosoftEdgeCatalogParser.latestVersion(data: data, channel: channel) else {
                return .error("Microsoft Edge update service unavailable")
            }
            let pageURL = URL(string: "https://www.microsoft.com/edge/download")
            if AppVersionOrdering.isNewer(latest, than: currentVersion) {
                return .updateAvailable(
                    latestVersion: latest,
                    downloadURL: nil,
                    pageURL: pageURL,
                    releaseNotes: nil,
                    releaseNotesURL: nil
                )
            }
            return .upToDate(latestVersion: latest)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - Blender releases

enum BlenderUpdateParser {
    static func latestVersion(in html: String) -> String? {
        let pattern = #"blender-(\d+\.\d+\.\d+)-(?:macos|darwin)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let matches = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }.max { AppVersionOrdering.compare($0, $1) == .orderedAscending }
    }
}

private enum BlenderUpdater {
    static let pageURL = URL(string: "https://www.blender.org/download/")!

    static func check(currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        do {
            var request = URLRequest(url: pageURL)
            request.timeoutInterval = 12
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8),
                  let latest = BlenderUpdateParser.latestVersion(in: html) else {
                return .error("Blender release information unavailable")
            }
            if AppVersionOrdering.isNewer(latest, than: currentVersion) {
                return .updateAvailable(
                    latestVersion: latest,
                    downloadURL: nil,
                    pageURL: pageURL,
                    releaseNotes: nil,
                    releaseNotesURL: nil
                )
            }
            return .upToDate(latestVersion: latest)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - Installed bundle versions

struct InstalledAppBundleVersions: Equatable, Sendable {
    let currentVersion: String
    let currentBuildVersion: String
}

enum InstalledAppBundleVersionReader {
    nonisolated static func read(at appURL: URL) -> InstalledAppBundleVersions? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL, options: .mappedIfSafe),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let info = propertyList as? [String: Any] else { return nil }

        let shortVersion = nonEmpty(info["CFBundleShortVersionString"] as? String)
        let buildVersion = nonEmpty(info["CFBundleVersion"] as? String)
        guard let currentVersion = shortVersion ?? buildVersion else { return nil }
        return InstalledAppBundleVersions(
            currentVersion: currentVersion,
            currentBuildVersion: buildVersion ?? currentVersion
        )
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Per-app check state

struct InstalledAppUpdateEntry: Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case checking
        case upToDate(latestVersion: String)
        case updateAvailable(latestVersion: String, downloadURL: URL?, pageURL: URL?, releaseNotes: String?, releaseNotesURL: URL?)
        case unsupported
        case ignored
        case error(String)

        var isUpdateAvailable: Bool {
            if case .updateAvailable = self { return true }
            return false
        }

        var isUpToDate: Bool {
            if case .upToDate = self { return true }
            return false
        }

        var isUnsupported: Bool {
            if case .unsupported = self { return true }
            return false
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    let id: String
    let name: String
    let bundleIdentifier: String
    let url: URL
    var currentVersion: String
    var currentBuildVersion: String
    let source: InstalledAppUpdateSource
    var status: Status
}

// MARK: - Checker

@MainActor
final class InstalledAppUpdatesChecker: ObservableObject {
    static let shared = InstalledAppUpdatesChecker()

    @Published private(set) var entries: [InstalledAppUpdateEntry] = []
    @Published private(set) var isChecking = false
    @Published private(set) var checkProgress: Double = 0
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var updatingBundleIDs: Set<String> = []
    @Published private(set) var ignoredBundleIDs: Set<String> = []
    @Published private(set) var skippedVersions: [String: String] = [:]
    @Published var selectedEntryIDs: Set<String> = []
    @Published var homebrewNotice: String?
    @Published var releaseNotesEntry: ReleaseNotesEntry?

    var updatingBundleID: String? { updatingBundleIDs.min() }

    struct ReleaseNotesEntry: Identifiable {
        let id: String
        let name: String
        let url: URL
        let latestVersion: String
        let releaseNotes: String?
        let releaseNotesURL: URL?

        init(entry: InstalledAppUpdateEntry) {
            id = entry.id
            name = entry.name
            url = entry.url
            if case .updateAvailable(let latestVersion, _, _, let releaseNotes, let releaseNotesURL) = entry.status {
                self.latestVersion = latestVersion
                self.releaseNotes = releaseNotes
                self.releaseNotesURL = releaseNotesURL
            } else {
                latestVersion = ""
                releaseNotes = nil
                releaseNotesURL = nil
            }
        }
    }

    private let ignoredAppsKey = "SapphireIgnoredInstalledAppUpdates"
    private let lastCheckedKey = "SapphireInstalledAppsLastChecked"
    private let skippedVersionsKey = "SapphireInstalledAppsSkippedVersions"
    private let announcedUpdatesKey = "SapphireInstalledAppsAnnouncedUpdates"
    private let resultCacheKey = "SapphireInstalledAppsUpdateResultCache"
    private var backgroundTimer: Timer?
    private var backgroundLaunchWorkItem: DispatchWorkItem?
    private var failedCheckRetryWorkItem: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private var wakeCheckTask: Task<Void, Never>?
    private var entryCheckTasks: [String: Task<Void, Never>] = [:]
    private var networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(
        label: "com.cshariq.sapphire.installed-app-update-network",
        qos: .utility
    )
    private var backgroundChecksEnabled = false
    private var awaitingConnectivityRetry = false
    private let backgroundCheckInterval: TimeInterval = 3 * 60 * 60
    private let backgroundTimerInterval: TimeInterval = 30 * 60
    private var announcedUpdateKeys: Set<String> = []
    private var resultCache: [String: InstalledAppUpdateCacheRecord] = [:]
    private var rawStatuses: [String: InstalledAppUpdateEntry.Status] = [:]
    private var homebrewAdministratorIDs: Set<String> = []
    private var pendingRecheckIDs: Set<String> = []
    private let resultPublicationInterval: TimeInterval = 0.2
    private let resultPublicationBatchSize = 4
    private var caskOwnership: [String: HomebrewCaskRecord] = [:]
    private var caskInventoryLoadedAt: Date?
    private var caskInventoryTask: Task<[String: HomebrewCaskRecord], Never>?
    private let caskInventoryLifetime: TimeInterval = 10 * 60

    // MARK: Homebrew cask ownership

    func homebrewCask(forAppAt url: URL) async -> HomebrewCaskRecord? {
        let isFresh = caskInventoryLoadedAt.map { Date().timeIntervalSince($0) < caskInventoryLifetime } ?? false
        let ownership = isFresh ? caskOwnership : await refreshCaskInventory()
        return ownership[url.standardizedFileURL.path]
    }

    private func refreshCaskInventory() async -> [String: HomebrewCaskRecord] {
        if let caskInventoryTask { return await caskInventoryTask.value }
        let task = Task.detached(priority: .utility) { await HomebrewCaskInventory.load() }
        caskInventoryTask = task
        let loaded = await task.value
        caskOwnership = loaded
        caskInventoryLoadedAt = Date()
        caskInventoryTask = nil
        return loaded
    }

    private struct CompletedCheck: Sendable {
        let id: String
        let status: InstalledAppUpdateEntry.Status
        let installedVersions: InstalledAppBundleVersions?
        var homebrewRequiresAdministrator: Bool? = nil
    }

    // MARK: Settings integration

    private var notificationsEnabled = true

    private init() {
        if let data = UserDefaults.standard.data(forKey: ignoredAppsKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            ignoredBundleIDs = Set(ids)
        }
        lastCheckedAt = UserDefaults.standard.object(forKey: lastCheckedKey) as? Date
        if let data = UserDefaults.standard.data(forKey: skippedVersionsKey),
           let skipped = try? JSONDecoder().decode([String: String].self, from: data) {
            skippedVersions = skipped
        }
        if let data = UserDefaults.standard.data(forKey: announcedUpdatesKey),
           let keys = try? JSONDecoder().decode([String].self, from: data) {
            announcedUpdateKeys = Set(keys)
        }
        if let data = UserDefaults.standard.data(forKey: resultCacheKey),
           let cache = try? JSONDecoder().decode([String: InstalledAppUpdateCacheRecord].self, from: data) {
            resultCache = cache
        }
    }

    private func saveSkippedVersions() {
        if let data = try? JSONEncoder().encode(skippedVersions) {
            UserDefaults.standard.set(data, forKey: skippedVersionsKey)
        }
    }

    private func saveAnnouncements() {
        if let data = try? JSONEncoder().encode(announcedUpdateKeys.sorted()) {
            UserDefaults.standard.set(data, forKey: announcedUpdatesKey)
        }
    }

    private func saveResultCache() {
        if let data = try? JSONEncoder().encode(resultCache) {
            UserDefaults.standard.set(data, forKey: resultCacheKey)
        }
    }

    private func saveIgnoredApps() {
        if let data = try? JSONEncoder().encode(Array(ignoredBundleIDs)) {
            UserDefaults.standard.set(data, forKey: ignoredAppsKey)
        }
    }

    // MARK: Summary counts

    var updatesAvailableCount: Int { entries.filter { $0.status.isUpdateAvailable && !ignoredBundleIDs.contains($0.id) }.count }
    var upToDateCount: Int { entries.filter { $0.status.isUpToDate && !ignoredBundleIDs.contains($0.id) }.count }
    var checkingCount: Int { entries.filter { $0.status == .checking }.count }
    var unsupportedCount: Int { entries.filter { $0.status.isUnsupported && !ignoredBundleIDs.contains($0.id) }.count }

    var lastCheckedDescription: String {
        guard let lastCheckedAt else { return "Never" }
        return lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Action routing

    func buttonLabel(for entry: InstalledAppUpdateEntry) -> String {
        guard case .updateAvailable = entry.status else { return "Update" }
        switch entry.source {
        case .appStore:
            return "App Store"
        case .homebrew:
            return "Upgrade"
        case .selfUpdating, .sparkle, .electron, .keystone, .mozilla,
             .jsonManifest, .visualStudioCode, .androidStudio, .jetBrains,
             .microsoftEdge:
            return "Open App"
        case .github, .blender:
            return "View Release"
        default:
            return "Update"
        }
    }

    func isBusy(_ entryID: String) -> Bool {
        updatingBundleIDs.contains(entryID)
    }

    func isAppStoreEntry(_ entry: InstalledAppUpdateEntry) -> Bool {
        entry.source == .appStore
    }

    func canOpenManagedUpdater(for entry: InstalledAppUpdateEntry) -> Bool {
        entry.source.usesOwningAppUpdater
    }

    static func appStoreOpenURL(from url: URL) -> URL {
        let httpsPrefix = "https://"
        guard url.scheme == "https",
              url.host?.hasSuffix("apps.apple.com") == true,
              url.absoluteString.hasPrefix(httpsPrefix) else { return url }
        return URL(string: "macappstore://" + url.absoluteString.dropFirst(httpsPrefix.count)) ?? url
    }

    // MARK: Checking

    func checkNow() {
        guard !isChecking else { return }
        startFullCheck(scope: .all, announce: false)
    }

    func checkInBackgroundIfNeeded(force: Bool = false, announce: Bool = true) {
        guard !isChecking else { return }
        let isDue = InstalledAppUpdatePolicy.isCheckDue(
            lastCheckedAt: lastCheckedAt,
            now: Date(),
            interval: backgroundCheckInterval
        )
        let hasUnresolvedEntries = entries.contains {
            $0.status == .checking && !updatingBundleIDs.contains($0.id)
        }
        guard let scope = InstalledAppUpdatePolicy.backgroundScope(
            force: force,
            isDue: isDue,
            hasEntries: !entries.isEmpty,
            hasUnresolvedEntries: hasUnresolvedEntries
        ) else { return }
        startFullCheck(scope: scope, announce: announce)
    }

    private func startFullCheck(scope: InstalledAppUpdatePolicy.CheckScope, announce: Bool) {
        for task in entryCheckTasks.values { task.cancel() }
        entryCheckTasks.removeAll(keepingCapacity: true)
        isChecking = true
        checkProgress = 0
        Task { await runFullCheck(scope: scope, announce: announce) }
    }

    private func runFullCheck(scope: InstalledAppUpdatePolicy.CheckScope, announce: Bool) async {
        let caskOwnership = await refreshCaskInventory()
        let scannedEntries = await Task.detached(priority: .utility) {
            Self.scanInstalledApps(caskOwnership: caskOwnership)
        }.value
        entries = mergedEntries(scannedEntries)

        let appsToCheck = entries.filter { app in
            app.source != .none
                && !ignoredBundleIDs.contains(app.id)
                && !updatingBundleIDs.contains(app.id)
                && (scope == .all || app.status == .checking)
        }
        let everyCheckFailed = await performChecks(for: appsToCheck)

        checkProgress = 1
        isChecking = false
        if everyCheckFailed {
            scheduleFailedCheckRetry()
        } else {
            awaitingConnectivityRetry = false
            failedCheckRetryWorkItem?.cancel()
            failedCheckRetryWorkItem = nil
            if scope == .all {
                let checkedAt = Date()
                lastCheckedAt = checkedAt
                UserDefaults.standard.set(checkedAt, forKey: lastCheckedKey)
            }
        }
        finishFullCheckBookkeeping(announce: announce)

        let pending = pendingRecheckIDs
        pendingRecheckIDs.removeAll()
        for entryID in pending.sorted() { checkAgain(entryID: entryID) }
    }

    private func mergedEntries(_ scanned: [InstalledAppUpdateEntry]) -> [InstalledAppUpdateEntry] {
        let prior = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return scanned.map { scannedEntry in
            var entry = scannedEntry
            if entry.source == .none {
                entry.status = .unsupported
                return entry
            }
            if ignoredBundleIDs.contains(entry.id) {
                entry.status = .ignored
                return entry
            }
            if updatingBundleIDs.contains(entry.id), let existing = prior[entry.id] {
                return existing
            }
            if let existing = prior[entry.id],
               let carried = InstalledAppUpdatePolicy.carriedStatus(
                   scannedVersion: entry.currentVersion,
                   scannedBuildVersion: entry.currentBuildVersion,
                   priorVersion: existing.currentVersion,
                   priorBuildVersion: existing.currentBuildVersion,
                   priorStatus: existing.status
               ) {
                entry.status = carried
                return entry
            }
            if let raw = resultCache[entry.id]?.status(
                forInstalledVersion: entry.currentVersion,
                buildVersion: entry.currentBuildVersion
            ) {
                rawStatuses[entry.id] = raw
                entry.status = InstalledAppUpdatePolicy.presentedStatus(
                    raw,
                    skippedVersion: skippedVersions[entry.id]
                )
                return entry
            }
            entry.status = .checking
            return entry
        }
    }

    private func finishFullCheckBookkeeping(announce: Bool) {
        let ids = Set(entries.map(\.id))
        resultCache = resultCache.filter { ids.contains($0.key) }
        rawStatuses = rawStatuses.filter { ids.contains($0.key) }
        homebrewAdministratorIDs.formIntersection(ids)
        selectedEntryIDs = selectedEntryIDs.filter { ids.contains($0) }

        let installedVersions = Dictionary(
            entries.map { ($0.id, $0.currentVersion) },
            uniquingKeysWith: { first, _ in first }
        )
        let prunedSkips = InstalledAppUpdatePolicy.prunedSkips(
            skippedVersions,
            installedVersions: installedVersions,
            inventoryIsComplete: true
        )
        if prunedSkips != skippedVersions {
            skippedVersions = prunedSkips
            saveSkippedVersions()
        }

        recordAnnouncements(for: entries, notify: announce)

        let outcomes = Dictionary(
            entries.map { entry in
                (entry.id, InstalledAppUpdatePolicy.outcome(for: rawStatuses[entry.id] ?? entry.status))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let prunedAnnouncements = InstalledAppUpdatePolicy.prunedAnnouncements(
            announcedUpdateKeys,
            outcomes: outcomes
        )
        if prunedAnnouncements != announcedUpdateKeys {
            announcedUpdateKeys = prunedAnnouncements
            saveAnnouncements()
        }
        saveResultCache()
    }

    private func recordAnnouncements(for candidates: [InstalledAppUpdateEntry], notify: Bool) {
        let available: [InstalledAppUpdatePolicy.AvailableUpdate] = candidates.compactMap { entry in
            guard !ignoredBundleIDs.contains(entry.id),
                  case .updateAvailable(let latestVersion, _, _, _, _) = entry.status else { return nil }
            return InstalledAppUpdatePolicy.AvailableUpdate(id: entry.id, version: latestVersion)
        }
        guard !available.isEmpty else { return }
        let fresh = InstalledAppUpdatePolicy.updatesToAnnounce(
            available,
            alreadyAnnounced: announcedUpdateKeys
        )
        guard !fresh.isEmpty else { return }
        if notify {
            let freshIDs = Set(fresh.map(\.id))
            postBackgroundUpdateNotification(for: candidates.filter { freshIDs.contains($0.id) })
        }
        for update in fresh {
            announcedUpdateKeys.insert(
                InstalledAppUpdatePolicy.announcementKey(bundleID: update.id, version: update.version)
            )
        }
        saveAnnouncements()
    }

    private func performChecks(for apps: [InstalledAppUpdateEntry]) async -> Bool {
        guard !apps.isEmpty else { return false }
        let total = apps.count
        let limit = 6
        var completed = 0
        var failures = 0
        var pendingPublications: [CompletedCheck] = []
        var lastPublicationAt = ProcessInfo.processInfo.systemUptime

        let brewRequests: [HomebrewClient.CheckRequest] = apps.compactMap { app in
            guard case .homebrew(let token) = app.source else { return nil }
            return (id: app.id, token: token, currentVersion: app.currentVersion)
        }
        let appStoreRequests: [AppStoreClient.CheckRequest] = apps.compactMap { app in
            guard app.source == .appStore else { return nil }
            return (id: app.id, bundleIdentifier: app.bundleIdentifier, currentVersion: app.currentVersion)
        }
        let individualApps = apps.filter {
            if case .homebrew = $0.source { return false }
            if $0.source == .appStore { return false }
            return true
        }

        let appURLs = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.url) })
        await withTaskGroup(of: [CompletedCheck].self) { group in
            var iterator = individualApps.makeIterator()
            var primed = 0
            for start in stride(from: 0, to: appStoreRequests.count, by: AppStoreClient.batchSize) {
                let batch = Array(appStoreRequests[start..<min(start + AppStoreClient.batchSize, appStoreRequests.count)])
                group.addTask {
                    await AppStoreClient.checkBatch(batch).map { result in
                        CompletedCheck(
                            id: result.id,
                            status: result.status,
                            installedVersions: appURLs[result.id].flatMap {
                                InstalledAppBundleVersionReader.read(at: $0)
                            }
                        )
                    }
                }
                primed += 1
            }
            if !brewRequests.isEmpty {
                group.addTask {
                    await HomebrewClient.checkBatch(brewRequests).map { result in
                        CompletedCheck(
                            id: result.id,
                            status: result.status,
                            installedVersions: appURLs[result.id].flatMap {
                                InstalledAppBundleVersionReader.read(at: $0)
                            },
                            homebrewRequiresAdministrator: result.status.isError
                                ? nil
                                : result.requiresAdministrator
                        )
                    }
                }
                primed = 1
            }
            while primed < limit, let app = iterator.next() {
                group.addTask {
                    let status = await Self.performCheck(for: app)
                    return [CompletedCheck(
                        id: app.id,
                        status: status,
                        installedVersions: InstalledAppBundleVersionReader.read(at: app.url)
                    )]
                }
                primed += 1
            }
            while let results = await group.next() {
                for result in results {
                    pendingPublications.append(result)
                    completed += 1
                    if result.status.isError { failures += 1 }
                }
                let now = ProcessInfo.processInfo.systemUptime
                if pendingPublications.count >= resultPublicationBatchSize
                    || now - lastPublicationAt >= resultPublicationInterval
                    || completed == total {
                    apply(pendingPublications)
                    pendingPublications.removeAll(keepingCapacity: true)
                    checkProgress = Double(completed) / Double(max(total, 1))
                    lastPublicationAt = now
                }
                if let app = iterator.next() {
                    group.addTask {
                        let status = await Self.performCheck(for: app)
                        return [CompletedCheck(
                            id: app.id,
                            status: status,
                            installedVersions: InstalledAppBundleVersionReader.read(at: app.url)
                        )]
                    }
                }
            }
        }
        if !pendingPublications.isEmpty {
            apply(pendingPublications)
            checkProgress = Double(completed) / Double(max(total, 1))
        }
        return completed > 0 && failures == completed
    }

    private func scheduleFailedCheckRetry() {
        guard backgroundChecksEnabled,
              networkMonitor?.currentPath.status != .satisfied else {
            awaitingConnectivityRetry = false
            return
        }
        awaitingConnectivityRetry = true
        failedCheckRetryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.backgroundChecksEnabled else { return }
                self.checkInBackgroundIfNeeded(force: true)
            }
        }
        failedCheckRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15 * 60, execute: work)
    }

    private nonisolated static func performCheck(
        for app: InstalledAppUpdateEntry
    ) async -> InstalledAppUpdateEntry.Status {
        switch app.source {
        case .none:
            return .unsupported
        case .sparkle(let appcastURL):
            return await Self.checkSparkleFeed(
                appcastURL: appcastURL,
                currentVersion: app.currentVersion,
                currentBuildVersion: app.currentBuildVersion
            )
        case .appStore:
            let results = await AppStoreClient.checkBatch([
                (id: app.id, bundleIdentifier: app.bundleIdentifier, currentVersion: app.currentVersion)
            ])
            return results.first?.status ?? .unsupported
        case .keystone(let endpoint, let appID):
            return await Self.checkKeystone(endpoint: endpoint, appID: appID, currentVersion: app.currentVersion)
        case .electron(let feed):
            switch feed {
            case .github(let owner, let repo):
                return await ElectronUpdater.checkGitHub(owner: owner, repo: repo, currentVersion: app.currentVersion)
            case .generic(let baseURL):
                return await ElectronUpdater.checkGeneric(baseURL: baseURL, currentVersion: app.currentVersion)
            }
        case .homebrew(let token):
            return await HomebrewClient.check(token: token, currentVersion: app.currentVersion)
        case .mozilla(let product):
            return await MozillaUpdater.check(product: product, currentVersion: app.currentVersion)
        case .jsonManifest(let url):
            return await JSONManifestUpdater.check(url: url, currentVersion: app.currentVersion)
        case .visualStudioCode(let feed):
            return await VSCodeUpdater.check(feed: feed, currentVersion: app.currentVersion)
        case .androidStudio:
            return await AndroidStudioUpdater.check(currentBuild: app.currentBuildVersion)
        case .jetBrains(let productCode):
            return await JetBrainsUpdater.check(productCode: productCode, currentVersion: app.currentVersion)
        case .microsoftEdge(let channel):
            return await MicrosoftEdgeUpdater.check(channel: channel, currentVersion: app.currentVersion)
        case .github(let project):
            return await ElectronUpdater.checkGitHub(
                owner: project.owner,
                repo: project.repository,
                currentVersion: app.currentVersion,
                requireMacAsset: false
            )
        case .blender:
            return await BlenderUpdater.check(currentVersion: app.currentVersion)
        case .selfUpdating:
            if let bundle = Bundle(url: app.url),
               let feedURL = InstalledAppUpdateSourceDetector.sparkleFeedURL(bundleID: app.bundleIdentifier, bundle: bundle) {
                return await Self.checkSparkleFeed(
                    appcastURL: feedURL,
                    currentVersion: app.currentVersion,
                    currentBuildVersion: app.currentBuildVersion
                )
            }
            return .unsupported
        }
    }

    private nonisolated static func checkSparkleFeed(
        appcastURL: URL,
        currentVersion: String,
        currentBuildVersion: String
    ) async -> InstalledAppUpdateEntry.Status {
        do {
            var request = URLRequest(url: appcastURL)
            request.timeoutInterval = 12
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return .error("Update feed unavailable")
            }
            let items = AppcastParser.parse(data: data)
            guard let latest = AppcastParser.latestItem(in: items) else {
                return .error("No releases found in update feed")
            }
            let latestVersion = latest.displayVersion
            let feedHasOnlyBuildNumbers = (latest.shortVersion ?? "").isEmpty
                && !latest.version.isEmpty
                && !currentBuildVersion.isEmpty
            let latestMarketingIsNewer = feedHasOnlyBuildNumbers
                ? AppVersionOrdering.isNewer(latest.version, than: currentBuildVersion)
                : AppVersionOrdering.isNewer(latestVersion, than: currentVersion)
            let marketingVersionsMatch = AppVersionOrdering.compare(latestVersion, currentVersion) == .orderedSame
            let buildOnlyUpdate = !feedHasOnlyBuildNumbers
                && latest.shortVersion != nil
                && marketingVersionsMatch
                && !latest.version.isEmpty
                && !currentBuildVersion.isEmpty
                && AppVersionOrdering.isNewer(latest.version, than: currentBuildVersion)
            if latestMarketingIsNewer || buildOnlyUpdate {
                return .updateAvailable(
                    latestVersion: latestVersion,
                    downloadURL: latest.downloadURL,
                    pageURL: latest.releaseNotesURL,
                    releaseNotes: latest.releaseNotes,
                    releaseNotesURL: latest.releaseNotesURL
                )
            }
            return .upToDate(latestVersion: latestVersion)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private nonisolated static func checkKeystone(endpoint: URL, appID: String, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.httpMethod = "POST"
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = KeystoneClient.requestXML(appID: appID, currentVersion: currentVersion).data(using: .utf8)
        do {
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return .error("Google Update unavailable")
            }
            let parsed = KeystoneClient.parseResponse(data: data)
            guard parsed.updatecheckStatus != "error", parsed.appStatus != "error" else {
                return .error("Google Update reported an error")
            }
            guard let latest = parsed.manifestVersion, !latest.isEmpty else {
                return parsed.isUpToDate ? .upToDate(latestVersion: currentVersion) : .error("No release information found")
            }
            if AppVersionOrdering.isNewer(latest, than: currentVersion) {
                return .updateAvailable(
                    latestVersion: latest,
                    downloadURL: parsed.downloadURL,
                    pageURL: KeystoneClient.productPage(for: appID),
                    releaseNotes: nil,
                    releaseNotesURL: nil
                )
            }
            return .upToDate(latestVersion: latest)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func apply(_ results: [CompletedCheck]) {
        guard !results.isEmpty else { return }
        var updatedEntries = entries
        let indicesByID = Dictionary(
            uniqueKeysWithValues: updatedEntries.indices.map { (updatedEntries[$0].id, $0) }
        )
        var changed = false
        var cacheChanged = false
        for result in results {
            if let requiresAdministrator = result.homebrewRequiresAdministrator {
                if requiresAdministrator {
                    homebrewAdministratorIDs.insert(result.id)
                } else {
                    homebrewAdministratorIDs.remove(result.id)
                }
            }
            guard let index = indicesByID[result.id],
                  !updatingBundleIDs.contains(result.id),
                  !ignoredBundleIDs.contains(result.id) else { continue }
            let checkedVersion = updatedEntries[index].currentVersion
            let checkedBuildVersion = updatedEntries[index].currentBuildVersion
            if let installedVersions = result.installedVersions {
                updatedEntries[index].currentVersion = installedVersions.currentVersion
                updatedEntries[index].currentBuildVersion = installedVersions.currentBuildVersion
            }
            let installedVersionChanged = checkedVersion != updatedEntries[index].currentVersion
                || checkedBuildVersion != updatedEntries[index].currentBuildVersion
            let validated = Self.validatedStatus(
                result.status,
                currentVersion: updatedEntries[index].currentVersion,
                demoteEquivalentUpdate: installedVersionChanged
            )
            rawStatuses[result.id] = validated
            updatedEntries[index].status = InstalledAppUpdatePolicy.presentedStatus(
                validated,
                skippedVersion: skippedVersions[result.id]
            )
            if let record = InstalledAppUpdateCacheRecord(
                status: validated,
                checkedVersion: updatedEntries[index].currentVersion,
                checkedBuildVersion: updatedEntries[index].currentBuildVersion
            ), resultCache[result.id] != record {
                resultCache[result.id] = record
                cacheChanged = true
            }
            if !updatedEntries[index].status.isUpdateAvailable, selectedEntryIDs.contains(result.id) {
                selectedEntryIDs.remove(result.id)
            }
            changed = true
        }
        if changed { entries = updatedEntries }
        if cacheChanged, !isChecking { saveResultCache() }
    }

    nonisolated static func validatedStatus(
        _ status: InstalledAppUpdateEntry.Status,
        currentVersion: String,
        demoteEquivalentUpdate: Bool = false
    ) -> InstalledAppUpdateEntry.Status {
        guard case .updateAvailable(
            let latestVersion,
            _,
            _,
            _,
            _
        ) = status,
        latestVersion.contains(where: \.isNumber),
        currentVersion.contains(where: \.isNumber) else {
            return status
        }
        let comparison = AppVersionOrdering.compare(latestVersion, currentVersion)
        guard comparison == .orderedAscending
                || (demoteEquivalentUpdate && comparison == .orderedSame) else { return status }
        return .upToDate(latestVersion: currentVersion)
    }

    // MARK: Scanning

    nonisolated static func scanInstalledApps(
        caskOwnership: [String: HomebrewCaskRecord] = [:]
    ) -> [InstalledAppUpdateEntry] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var result: [InstalledAppUpdateEntry] = []
        var seen = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isPackageKey,
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                      let values = try? url.resourceValues(forKeys: [
                          .isDirectoryKey,
                          .isSymbolicLinkKey,
                      ]),
                      values.isDirectory == true || values.isSymbolicLink == true else { continue }
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url),
                      let identifier = bundle.bundleIdentifier,
                      seen.insert(identifier).inserted else { continue }
                let diskVersions = InstalledAppBundleVersionReader.read(at: url)
                let version = diskVersions?.currentVersion
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? ""
                let buildVersion = diskVersions?.currentBuildVersion
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? version
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let source = InstalledAppUpdateSourceDetector.detect(for: bundle, caskOwnership: caskOwnership)
                result.append(InstalledAppUpdateEntry(
                    id: identifier,
                    name: name,
                    bundleIdentifier: identifier,
                    url: url,
                    currentVersion: version,
                    currentBuildVersion: buildVersion,
                    source: source,
                    status: .checking
                ))
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Ignore list

    func isIgnored(_ entry: InstalledAppUpdateEntry) -> Bool {
        ignoredBundleIDs.contains(entry.id)
    }

    func setIgnored(_ ignored: Bool, for entryID: String) {
        if ignored {
            ignoredBundleIDs.insert(entryID)
            selectedEntryIDs.remove(entryID)
        } else {
            ignoredBundleIDs.remove(entryID)
        }
        saveIgnoredApps()
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        if ignored {
            entryCheckTasks[entryID]?.cancel()
            entryCheckTasks[entryID] = nil
            entries[index].status = .ignored
        } else {
            entries[index].status = rawStatuses[entryID].map {
                InstalledAppUpdatePolicy.presentedStatus($0, skippedVersion: skippedVersions[entryID])
            } ?? .checking
            checkAgain(entryID: entryID)
        }
    }

    // MARK: Skipped versions

    func skippedVersion(for entryID: String) -> String? {
        skippedVersions[entryID]
    }

    func skippableVersion(for entry: InstalledAppUpdateEntry) -> String? {
        guard !ignoredBundleIDs.contains(entry.id),
              case .updateAvailable(let latestVersion, _, _, _, _) = entry.status else { return nil }
        return latestVersion
    }

    var skippedEntries: [InstalledAppUpdateEntry] {
        entries.filter { skippedVersions[$0.id] != nil }
    }

    func skipCurrentUpdate(for entryID: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              let version = skippableVersion(for: entries[index]) else { return }
        let raw = rawStatuses[entryID] ?? entries[index].status
        rawStatuses[entryID] = raw
        skippedVersions[entryID] = version
        saveSkippedVersions()
        selectedEntryIDs.remove(entryID)
        if !updatingBundleIDs.contains(entryID) {
            entries[index].status = InstalledAppUpdatePolicy.presentedStatus(raw, skippedVersion: version)
        }
    }

    func unskip(entryID: String) {
        guard skippedVersions.removeValue(forKey: entryID) != nil else { return }
        saveSkippedVersions()
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              !ignoredBundleIDs.contains(entryID),
              !updatingBundleIDs.contains(entryID),
              let raw = rawStatuses[entryID] else { return }
        entries[index].status = raw
    }

    // MARK: Selection

    nonisolated static func supportsBatchUpdate(_ source: InstalledAppUpdateSource) -> Bool {
        switch source {
        case .homebrew, .appStore:
            return true
        case .none, .sparkle, .keystone, .electron, .mozilla, .jsonManifest, .visualStudioCode,
             .androidStudio, .jetBrains, .microsoftEdge, .github, .blender, .selfUpdating:
            return false
        }
    }

    func isSelectable(_ entry: InstalledAppUpdateEntry) -> Bool {
        entry.status.isUpdateAvailable
            && !ignoredBundleIDs.contains(entry.id)
            && !updatingBundleIDs.contains(entry.id)
            && Self.supportsBatchUpdate(entry.source)
    }

    func isSelected(_ entryID: String) -> Bool {
        selectedEntryIDs.contains(entryID)
    }

    func setSelected(_ selected: Bool, for entryID: String) {
        if selected {
            guard let entry = entries.first(where: { $0.id == entryID }), isSelectable(entry) else { return }
            selectedEntryIDs.insert(entryID)
        } else {
            selectedEntryIDs.remove(entryID)
        }
    }

    func selectAllUpdates() {
        selectedEntryIDs = Set(entries.filter(isSelectable).map(\.id))
    }

    func clearSelection() {
        if !selectedEntryIDs.isEmpty { selectedEntryIDs.removeAll() }
    }

    var selectedUpdatableCount: Int {
        entries.filter { selectedEntryIDs.contains($0.id) && isSelectable($0) }.count
    }

    // MARK: Update actions

    func updateAction(for entryID: String) {
        guard let entry = entries.first(where: { $0.id == entryID }),
              case .updateAvailable = entry.status else { return }

        switch entry.source {
        case .homebrew:
            upgradeHomebrew([entry])
            return
        case .selfUpdating, .sparkle, .electron, .keystone, .mozilla,
             .jsonManifest, .visualStudioCode, .androidStudio, .jetBrains,
             .microsoftEdge:
            openApp(for: entry)
            return
        case .github, .blender:
            if case .updateAvailable(_, _, let pageURL, _, _) = entry.status,
               let pageURL {
                openUpdatePage(for: entry, pageURL: pageURL)
            }
            return
        case .appStore:
            if case .updateAvailable(_, _, let pageURL, _, _) = entry.status,
               let pageURL {
                openUpdatePage(for: entry, pageURL: pageURL)
            }
            return
        case .none:
            return
        }
    }

    func openUpdatePage(for entry: InstalledAppUpdateEntry, pageURL: URL? = nil) {
        let url: URL
        if let pageURL {
            url = pageURL
        } else if case .updateAvailable(_, _, let availableURL, _, _) = entry.status, let availableURL {
            url = availableURL
        } else {
            return
        }
        let target = entry.source == .appStore ? Self.appStoreOpenURL(from: url) : url
        NSWorkspace.shared.open(target)
    }

    private func openApp(for entry: InstalledAppUpdateEntry) {
        let configuration = NSWorkspace.OpenConfiguration()
        Task { try? await NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) }
    }

    func openManagedUpdater(entryID: String) {
        guard let entry = entries.first(where: { $0.id == entryID }),
              entry.source.usesOwningAppUpdater else { return }
        openApp(for: entry)
    }

    func updateSelected() {
        let targets = entries.filter { selectedEntryIDs.contains($0.id) && isSelectable($0) }
        clearSelection()
        guard !targets.isEmpty else { return }
        let plan = InstalledAppBatchUpdatePlanner.plan(for: targets.map {
            InstalledAppBatchUpdatePlanner.Candidate(id: $0.id, route: batchRoute(for: $0))
        })

        startHomebrewUpgrades(plan)

        if plan.appStoreIDs.count == 1, let entryID = plan.appStoreIDs.first {
            updateAction(for: entryID)
        } else if plan.appStoreIDs.count > 1, let updatesURL = URL(string: "macappstore://showUpdatesPage") {
            NSWorkspace.shared.open(updatesURL)
        }
    }

    private func batchRoute(for entry: InstalledAppUpdateEntry) -> InstalledAppBatchUpdatePlanner.Route {
        switch entry.source {
        case .homebrew(let token):
            return .homebrew(token: token, requiresAdministrator: homebrewNeedsAdministrator(entry))
        case .appStore:
            return .appStore
        case .none:
            return .notUpdatable
        case .sparkle, .keystone, .electron, .mozilla, .jsonManifest, .visualStudioCode,
             .androidStudio, .jetBrains, .microsoftEdge, .github, .blender, .selfUpdating:
            return .perItem
        }
    }

    private func upgradeHomebrew(_ targets: [InstalledAppUpdateEntry]) {
        let plan = InstalledAppBatchUpdatePlanner.plan(for: targets.map {
            InstalledAppBatchUpdatePlanner.Candidate(id: $0.id, route: batchRoute(for: $0))
        })
        startHomebrewUpgrades(plan)
    }

    private func startHomebrewUpgrades(_ plan: InstalledAppBatchUpdatePlanner.Plan) {
        let items = (plan.homebrew + plan.homebrewInTerminal).filter { !updatingBundleIDs.contains($0.id) }
        guard !items.isEmpty else { return }
        let knownToNeedAdministrator = Set(plan.homebrewInTerminal.map { $0.id })
        let ids = items.map { $0.id }
        let targets = entries.filter { ids.contains($0.id) }
        let requests: [HomebrewClient.CheckRequest] = targets.compactMap { entry in
            guard let item = items.first(where: { $0.id == entry.id }) else { return nil }
            return (id: entry.id, token: item.token, currentVersion: entry.currentVersion)
        }
        let versionsBefore = Dictionary(
            targets.map {
                ($0.id, InstalledAppBundleVersions(
                    currentVersion: $0.currentVersion,
                    currentBuildVersion: $0.currentBuildVersion
                ))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let urls = Dictionary(targets.map { ($0.id, $0.url) }, uniquingKeysWith: { first, _ in first })
        updatingBundleIDs.formUnion(ids)
        selectedEntryIDs.subtract(ids)
        homebrewNotice = nil

        Task { @MainActor [weak self] in
            let preflight = await HomebrewClient.checkBatch(requests)
            guard let self else { return }
            let preflightAdministrator = Set(preflight.filter { $0.requiresAdministrator }.map { $0.id })
            self.homebrewAdministratorIDs.formUnion(preflightAdministrator)
            let terminalIDs = knownToNeedAdministrator.union(preflightAdministrator)
            let inTerminal = items.filter { terminalIDs.contains($0.id) }
            let inProcess = items.filter { !terminalIDs.contains($0.id) }
            if !inTerminal.isEmpty {
                self.updatingBundleIDs.subtract(inTerminal.map { $0.id })
                self.openHomebrewUpgradeInTerminal(inTerminal)
            }
            guard !inProcess.isEmpty else { return }
            await self.performBrewUpgrade(inProcess, versionsBefore: versionsBefore, urls: urls)
        }
    }

    private func homebrewNeedsAdministrator(_ entry: InstalledAppUpdateEntry) -> Bool {
        if homebrewAdministratorIDs.contains(entry.id) { return true }
        let fileManager = FileManager.default
        return !fileManager.isWritableFile(atPath: entry.url.path)
            || !fileManager.isWritableFile(atPath: entry.url.deletingLastPathComponent().path)
    }

    private func openHomebrewUpgradeInTerminal(_ items: [(id: String, token: String)]) {
        let names = items.compactMap { item in entries.first(where: { $0.id == item.id })?.name }
        Task { @MainActor [weak self] in
            let opened = await HomebrewClient.openUpgradeInTerminal(tokens: items.map { $0.token })
            guard let self else { return }
            let list = ListFormatter.localizedString(byJoining: names.isEmpty ? items.map { $0.token } : names)
            self.homebrewNotice = opened
                ? "Opened Terminal to upgrade \(list) — Homebrew needs your administrator password."
                : "Couldn't open Terminal. Run “brew upgrade --cask \(items.map { $0.token }.joined(separator: " "))” yourself."
        }
    }

    private func performBrewUpgrade(
        _ items: [(id: String, token: String)],
        versionsBefore: [String: InstalledAppBundleVersions],
        urls: [String: URL]
    ) async {
        let ids = items.map { $0.id }
        let outcome = await HomebrewClient.upgrade(tokens: items.map { $0.token })
        let versionsAfter = await Task.detached(priority: .utility) {
            urls.filter { ids.contains($0.key) }.compactMapValues { InstalledAppBundleVersionReader.read(at: $0) }
        }.value
        updatingBundleIDs.subtract(ids)

        switch outcome {
        case .succeeded:
            for entryID in ids { checkAgain(entryID: entryID) }
        case .needsAdministrator:
            homebrewAdministratorIDs.formUnion(ids)
            openHomebrewUpgradeInTerminal(items)
            for entryID in ids { checkAgain(entryID: entryID) }
        case .failed(let summary):
            let message = "brew upgrade failed: \(summary ?? "run it in Terminal for details")"
            for entryID in ids {
                if versionsAfter[entryID] != versionsBefore[entryID] {
                    checkAgain(entryID: entryID)
                } else if let index = entries.firstIndex(where: { $0.id == entryID }) {
                    entries[index].status = .error(message)
                }
            }
            if ids.count > 1 { homebrewNotice = message }
        }
    }

    // MARK: Background checks

    func setBackgroundChecksEnabled(_ enabled: Bool) {
        guard enabled != backgroundChecksEnabled else { return }
        backgroundChecksEnabled = enabled
        if enabled {
            startBackgroundChecks()
        } else {
            stopBackgroundChecks()
        }
    }

    private func startBackgroundChecks() {
        stopBackgroundChecks()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.checkInBackgroundIfNeeded()
            }
        }
        backgroundLaunchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)

        backgroundTimer = Timer.scheduledCoalescing(withTimeInterval: backgroundTimerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInBackgroundIfNeeded()
            }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self,
                      self.backgroundChecksEnabled,
                      self.awaitingConnectivityRetry else { return }
                self.failedCheckRetryWorkItem?.cancel()
                self.failedCheckRetryWorkItem = nil
                self.checkInBackgroundIfNeeded(force: true)
            }
        }
        networkMonitor = monitor
        monitor.start(queue: networkMonitorQueue)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wakeCheckTask?.cancel()
                self.wakeCheckTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled, let self, self.backgroundChecksEnabled else { return }
                    self.wakeCheckTask = nil
                    self.checkInBackgroundIfNeeded()
                }
            }
        }
    }

    private func stopBackgroundChecks() {
        backgroundLaunchWorkItem?.cancel()
        backgroundLaunchWorkItem = nil
        failedCheckRetryWorkItem?.cancel()
        failedCheckRetryWorkItem = nil
        wakeCheckTask?.cancel()
        wakeCheckTask = nil
        awaitingConnectivityRetry = false
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        networkMonitor?.cancel()
        networkMonitor = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func postBackgroundUpdateNotification(for apps: [InstalledAppUpdateEntry]) {
        guard notificationsEnabled, !apps.isEmpty else { return }
        let names = apps.prefix(3).map(\.name).joined(separator: ", ")
        let title: String
        if apps.count == 1 {
            title = "Update available for \(names)"
        } else {
            title = "\(apps.count) apps have updates available"
        }
        let body = apps.count > 3
            ? "\(names) and \(apps.count - 3) more. Open Settings → Apps to update them."
            : "Open Settings → Apps to update them."
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { notificationSettings in
            guard notificationSettings.authorizationStatus == .authorized
                || notificationSettings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "sapphire-installed-app-updates-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    // MARK: Settings integration

    func applySettings(installedAppUpdatesEnabled: Bool, notificationsEnabled: Bool) {
        self.notificationsEnabled = notificationsEnabled
        setBackgroundChecksEnabled(installedAppUpdatesEnabled)
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Per-app actions

    func checkAgain(entryID: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              entries[index].source != .none,
              !updatingBundleIDs.contains(entryID),
              !ignoredBundleIDs.contains(entryID) else { return }
        if isChecking {
            pendingRecheckIDs.insert(entryID)
            return
        }
        guard entryCheckTasks[entryID] == nil else { return }
        entries[index].status = .checking
        let app = entries[index]
        entryCheckTasks[entryID] = Task { @MainActor [weak self] in
            guard let self else { return }
            let refreshed = await Task.detached(priority: .utility) {
                let versions = InstalledAppBundleVersionReader.read(at: app.url)
                var refreshedApp = app
                if let versions {
                    refreshedApp.currentVersion = versions.currentVersion
                    refreshedApp.currentBuildVersion = versions.currentBuildVersion
                }
                return (refreshedApp, versions)
            }.value
            let status = await Self.performCheck(for: refreshed.0)
            guard !Task.isCancelled,
                  !self.isChecking,
                  self.entryCheckTasks[entryID] != nil else { return }
            self.entryCheckTasks[entryID] = nil
            self.apply([CompletedCheck(
                id: entryID,
                status: status,
                installedVersions: refreshed.1
            )])
            if let entry = self.entries.first(where: { $0.id == entryID }) {
                self.recordAnnouncements(for: [entry], notify: false)
            }
        }
    }

    func forgetApp(bundleIdentifier: String, url: URL, preserveBundlePreferences: Bool = false) {
        entryCheckTasks[bundleIdentifier]?.cancel()
        entryCheckTasks[bundleIdentifier] = nil
        entries.removeAll {
            $0.bundleIdentifier == bundleIdentifier
                && $0.url.standardizedFileURL == url.standardizedFileURL
        }
        selectedEntryIDs.remove(bundleIdentifier)
        rawStatuses[bundleIdentifier] = nil
        homebrewAdministratorIDs.remove(bundleIdentifier)
        pendingRecheckIDs.remove(bundleIdentifier)
        if resultCache.removeValue(forKey: bundleIdentifier) != nil { saveResultCache() }
        if !preserveBundlePreferences {
            ignoredBundleIDs.remove(bundleIdentifier)
            if skippedVersions.removeValue(forKey: bundleIdentifier) != nil { saveSkippedVersions() }
        }
        saveIgnoredApps()
    }
}