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
    static func detect(for bundle: Bundle) -> InstalledAppUpdateSource {
        guard let identifier = bundle.bundleIdentifier, !identifier.isEmpty else { return .none }
        if identifier.hasPrefix("com.apple.") || identifier == Bundle.main.bundleIdentifier {
            return .none
        }

        let bundleURL = bundle.bundleURL

        if FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path) {
            return .appStore
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

        return .appStore
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
            let byDisplay = AppVersionOrdering.compare(lhs.displayVersion, rhs.displayVersion)
            if byDisplay != .orderedSame { return byDisplay == .orderedAscending }
            return AppVersionOrdering.compare(lhs.version, rhs.version) == .orderedAscending
        }
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
    private(set) var items: [AppcastItem] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = qName ?? elementName
        if name == "item" {
            current = ItemBuilder()
            currentText = ""
            descriptionText = ""
            descriptionDepth = 0
            if (attributeDict["sparkle:prerelease"] ?? attributeDict["prerelease"]) == "true" {
                current?.isPrerelease = true
            }
            return
        }
        guard current != nil else { return }

        switch name {
        case "enclosure":
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
             "sparkle:channel", "channel":
            currentText = ""
        case "description":
            descriptionText = ""
            descriptionDepth = 1
        case "link":
            if current?.releaseNotesURL == nil, let href = attributeDict["href"], let url = URL(string: href) {
                current?.releaseNotesURL = url
            }
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

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard current != nil else { return }
        let name = qName ?? elementName

        switch name {
        case "item":
            var item = current!
            item.releaseNotes = descriptionText.isEmpty
                ? nil
                : descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.version.isEmpty || item.shortVersion != nil {
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
            let channel = currentText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if channel == "prerelease" || channel == "beta" {
                current?.isPrerelease = true
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

    var errorDescription: String? {
        switch self {
        case .insecureResponse: return "Update service redirected to an insecure address"
        case .responseTooLarge: return "Update metadata was unexpectedly large"
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
    }

    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]

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
        let version: String?
        let trackViewUrl: String?
        let releaseNotes: String?
    }
    let results: [Result]
}

// MARK: - Homebrew casks

private struct BrewCaskInfo: Codable {
    let token: String?
    let version: String?
    let outdated: Bool?
}

private struct BrewInfoResponse: Codable {
    let casks: [BrewCaskInfo]?
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
    private let maximumOutputBytes = 5 * 1_024 * 1_024

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
        timeout: TimeInterval,
        captureOutput: Bool
    ) async -> BrewProcessResult? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                DispatchQueue.global(qos: .utility).async { [self] in
                    launch(
                        executable: executable,
                        arguments: arguments,
                        timeout: timeout,
                        captureOutput: captureOutput
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
        timeout: TimeInterval,
        captureOutput: Bool
    ) {
        guard !hasFailureRequest else {
            outputQueue.async { [self] in finish(nil) }
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        if captureOutput {
            let configured = outputQueue.sync { [self] in configureOutput(for: process) }
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
            guard let target, target.process.isRunning else { return }
            send(SIGKILL, to: target)
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
        guard child.process.isRunning else { return }
        if child.ownsProcessGroup, Darwin.getpgid(child.pid) == child.pid {
            _ = Darwin.kill(-child.pid, signal)
        } else {
            _ = Darwin.kill(child.pid, signal)
        }
    }

    private func configureOutput(for process: Process) -> Bool {
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
                if !discardFurtherOutput {
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
    typealias CheckResult = (id: String, status: InstalledAppUpdateEntry.Status)

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

    static func check(token: String, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        let result = await checkBatch([
            (id: token, token: token, currentVersion: currentVersion)
        ])
        return result.first?.status ?? .error("brew info failed for this cask")
    }

    static func checkBatch(_ requests: [CheckRequest]) async -> [CheckResult] {
        guard !requests.isEmpty else { return [] }
        guard let brew = executablePath() else {
            return requests.map { ($0.id, .error("Homebrew is not installed")) }
        }
        let tokens = Array(Set(requests.map { $0.token })).sorted()
        guard let result = await Self.runProcess(
            executable: URL(fileURLWithPath: brew),
            arguments: ["info", "--cask", "--json=v2"] + tokens,
            timeout: max(30, TimeInterval(tokens.count) * 2),
            captureOutput: true
        ), result.exitCode == 0 else {
            return requests.map { ($0.id, .error("brew info failed for this cask")) }
        }

        let casks = (try? JSONDecoder().decode(BrewInfoResponse.self, from: result.output))?.casks ?? []
        let caskByToken = Dictionary(
            casks.compactMap { cask in cask.token.map { ($0.lowercased(), cask) } },
            uniquingKeysWith: { first, _ in first }
        )
        return requests.map { request in
            guard let cask = caskByToken[request.token.lowercased()] else {
                return (request.id, .error("Unknown cask “\(request.token)”"))
            }
            let latest = normalizedVersion(cask.version)
            if HomebrewUpdateDecision.shouldOffer(
                latestVersion: latest,
                currentVersion: request.currentVersion,
                receiptIsOutdated: cask.outdated == true
            ) {
                return (
                    request.id,
                    .updateAvailable(
                        latestVersion: latest ?? "Latest",
                        downloadURL: nil,
                        pageURL: nil,
                        releaseNotes: nil,
                        releaseNotesURL: nil
                    )
                )
            }
            if let latest,
               latest.contains(where: \.isNumber),
               request.currentVersion.contains(where: \.isNumber),
               AppVersionOrdering.compare(latest, request.currentVersion) == .orderedAscending {
                let installed = request.currentVersion.isEmpty ? latest : request.currentVersion
                return (request.id, .upToDate(latestVersion: installed))
            }
            if latest == nil, isLatestSentinel(cask.version) {
                let installed = request.currentVersion.isEmpty ? "Latest" : request.currentVersion
                return (request.id, .upToDate(latestVersion: installed))
            }
            guard let latest else {
                return (request.id, .error("Homebrew returned no comparable version for “\(request.token)”"))
            }
            return (request.id, .upToDate(latestVersion: latest))
        }
    }

    static func upgrade(token: String) async -> Bool {
        guard let brew = executablePath() else { return false }
        guard let result = await Self.runProcess(
            executable: URL(fileURLWithPath: brew),
            arguments: ["upgrade", "--cask", token],
            timeout: 30 * 60,
            captureOutput: false
        ) else { return false }
        return result.exitCode == 0
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        captureOutput: Bool
    ) async -> BrewProcessResult? {
        await BrewProcessState().run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            captureOutput: captureOutput
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

struct InstalledAppUpdateEntry: Identifiable, @unchecked Sendable {
    enum Status: Equatable {
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
    let icon: NSImage
    var currentVersion: String
    var currentBuildVersion: String
    let source: InstalledAppUpdateSource
    var status: Status
}

// MARK: - Checker

@MainActor
final class InstalledAppUpdatesChecker: ObservableObject {
    static let shared = InstalledAppUpdatesChecker()

    nonisolated(unsafe) private static let installedAppIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    @Published private(set) var entries: [InstalledAppUpdateEntry] = []
    @Published private(set) var isChecking = false
    @Published private(set) var checkProgress: Double = 0
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var updatingBundleID: String?
    @Published private(set) var ignoredBundleIDs: Set<String> = []
    @Published var releaseNotesEntry: ReleaseNotesEntry?

    struct ReleaseNotesEntry: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
        let latestVersion: String
        let releaseNotes: String?
        let releaseNotesURL: URL?

        init(entry: InstalledAppUpdateEntry) {
            id = entry.id
            name = entry.name
            icon = entry.icon
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
    private var lastBackgroundCheck: Date = .distantPast
    private let minimumBackgroundCheckGap: TimeInterval = 30 * 60
    private let backgroundCheckInterval: TimeInterval = 3 * 60 * 60

    // MARK: Settings integration

    private var notificationsEnabled = true

    private init() {
        if let data = UserDefaults.standard.data(forKey: ignoredAppsKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            ignoredBundleIDs = Set(ids)
        }
        lastCheckedAt = UserDefaults.standard.object(forKey: lastCheckedKey) as? Date
        lastBackgroundCheck = lastCheckedAt ?? .distantPast
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
        updatingBundleID == entryID
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
        guard !isChecking, updatingBundleID == nil else { return }
        markFullCheckStarted()
        Task { await runFullCheck() }
    }

    func checkInBackgroundIfNeeded(force: Bool = false) {
        guard !isChecking, updatingBundleID == nil else { return }
        if !force, !entries.isEmpty,
           Date().timeIntervalSince(lastBackgroundCheck) < minimumBackgroundCheckGap {
            return
        }
        markFullCheckStarted()
        let previouslyAvailable = Set(entries.filter { $0.status.isUpdateAvailable }.map(\.id))
        Task {
            await runFullCheck()
            let nowAvailable = entries.filter { $0.status.isUpdateAvailable }
            let newlyAvailable = nowAvailable.filter { !previouslyAvailable.contains($0.id) }
            if !newlyAvailable.isEmpty {
                postBackgroundUpdateNotification(for: newlyAvailable)
            }
        }
    }

    private func markFullCheckStarted() {
        for task in entryCheckTasks.values { task.cancel() }
        entryCheckTasks.removeAll(keepingCapacity: true)
        lastBackgroundCheck = Date()
        isChecking = true
        checkProgress = 0
    }

    private func runFullCheck() async {
        entries = await Task.detached(priority: .utility) {
            Self.scanInstalledApps()
        }.value
        for index in entries.indices {
            if entries[index].source == .none {
                entries[index].status = .unsupported
            } else if ignoredBundleIDs.contains(entries[index].id) {
                entries[index].status = .ignored
            }
        }

        let appsToCheck = entries.filter { $0.source != .none && !ignoredBundleIDs.contains($0.id) }
        let everyCheckFailed = await performChecks(for: appsToCheck)

        checkProgress = 1
        isChecking = false
        if everyCheckFailed {
            scheduleFailedCheckRetry()
        } else {
            awaitingConnectivityRetry = false
            failedCheckRetryWorkItem?.cancel()
            failedCheckRetryWorkItem = nil
            lastCheckedAt = Date()
            if let lastCheckedAt {
                UserDefaults.standard.set(lastCheckedAt, forKey: lastCheckedKey)
            }
        }
    }

    private func performChecks(for apps: [InstalledAppUpdateEntry]) async -> Bool {
        guard !apps.isEmpty else { return false }
        let total = apps.count
        let limit = 6
        var completed = 0
        var failures = 0

        let brewRequests: [HomebrewClient.CheckRequest] = apps.compactMap { app in
            guard case .homebrew(let token) = app.source else { return nil }
            return (id: app.id, token: token, currentVersion: app.currentVersion)
        }
        let individualApps = apps.filter {
            if case .homebrew = $0.source { return false }
            return true
        }

        await withTaskGroup(of: [HomebrewClient.CheckResult].self) { group in
            var iterator = individualApps.makeIterator()
            var primed = 0
            if !brewRequests.isEmpty {
                group.addTask { await HomebrewClient.checkBatch(brewRequests) }
                primed = 1
            }
            while primed < limit, let app = iterator.next() {
                group.addTask { [weak self] in
                    let status = await self?.performCheck(for: app) ?? .error("Check failed")
                    return [(app.id, status)]
                }
                primed += 1
            }
            while let results = await group.next() {
                for (id, status) in results {
                    apply(status, toEntryWithID: id)
                    completed += 1
                    if status.isError { failures += 1 }
                }
                checkProgress = Double(completed) / Double(max(total, 1))
                if let app = iterator.next() {
                    group.addTask { [weak self] in
                        let status = await self?.performCheck(for: app) ?? .error("Check failed")
                        return [(app.id, status)]
                    }
                }
            }
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

    private func performCheck(for app: InstalledAppUpdateEntry) async -> InstalledAppUpdateEntry.Status {
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
            return await Self.checkAppStore(bundleIdentifier: app.bundleIdentifier, currentVersion: app.currentVersion)
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
            let latestMarketingIsNewer = AppVersionOrdering.isNewer(latestVersion, than: currentVersion)
            let marketingVersionsMatch = AppVersionOrdering.compare(latestVersion, currentVersion) == .orderedSame
            let buildOnlyUpdate = latest.shortVersion != nil
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

    private nonisolated static func checkAppStore(bundleIdentifier: String, currentVersion: String) async -> InstalledAppUpdateEntry.Status {
        let storefront = Locale.current.region?.identifier.lowercased() ?? "us"
        guard let escaped = bundleIdentifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(escaped)&country=\(storefront)") else {
            return .unsupported
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Sapphire/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, http) = try await InstalledAppHTTPClient.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                return .error("App Store lookup failed")
            }
            let lookup = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            guard let result = lookup.results.first, let latest = result.version, !latest.isEmpty else {
                return .unsupported
            }
            let pageURL = result.trackViewUrl.flatMap { URL(string: $0) }
            if AppVersionOrdering.isNewer(latest, than: currentVersion) {
                return .updateAvailable(
                    latestVersion: latest,
                    downloadURL: nil,
                    pageURL: pageURL,
                    releaseNotes: result.releaseNotes,
                    releaseNotesURL: pageURL
                )
            }
            return .upToDate(latestVersion: latest)
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

    private func apply(_ status: InstalledAppUpdateEntry.Status, toEntryWithID id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let checkedVersion = entries[index].currentVersion
        let checkedBuildVersion = entries[index].currentBuildVersion
        refreshInstalledVersions(at: index)
        let installedVersionChanged = checkedVersion != entries[index].currentVersion
            || checkedBuildVersion != entries[index].currentBuildVersion
        entries[index].status = Self.validatedStatus(
            status,
            currentVersion: entries[index].currentVersion,
            demoteEquivalentUpdate: installedVersionChanged
        )
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

    nonisolated static func scanInstalledApps() -> [InstalledAppUpdateEntry] {
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
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                      let values = try? url.resourceValues(forKeys: [
                          .isDirectoryKey,
                          .isSymbolicLinkKey,
                          .contentModificationDateKey,
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
                let source = InstalledAppUpdateSourceDetector.detect(for: bundle)
                result.append(InstalledAppUpdateEntry(
                    id: identifier,
                    name: name,
                    bundleIdentifier: identifier,
                    url: url,
                    icon: cachedIcon(for: url, modifiedAt: values.contentModificationDate),
                    currentVersion: version,
                    currentBuildVersion: buildVersion,
                    source: source,
                    status: .checking
                ))
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func cachedIcon(for url: URL, modifiedAt: Date?) -> NSImage {
        let stamp = modifiedAt?.timeIntervalSinceReferenceDate ?? 0
        let key = "\(url.path)|\(stamp)" as NSString
        if let cached = installedAppIconCache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        installedAppIconCache.setObject(icon, forKey: key)
        return icon
    }

    // MARK: Ignore list

    func isIgnored(_ entry: InstalledAppUpdateEntry) -> Bool {
        ignoredBundleIDs.contains(entry.id)
    }

    func setIgnored(_ ignored: Bool, for entryID: String) {
        if ignored {
            ignoredBundleIDs.insert(entryID)
        } else {
            ignoredBundleIDs.remove(entryID)
        }
        if let index = entries.firstIndex(where: { $0.id == entryID }) {
            entries[index].status = ignored ? .ignored : .checking
        }
        if let data = try? JSONEncoder().encode(Array(ignoredBundleIDs)) {
            UserDefaults.standard.set(data, forKey: ignoredAppsKey)
        }
        if !ignored {
            checkAgain(entryID: entryID)
        }
    }

    // MARK: Update actions

    func updateAction(for entryID: String) {
        guard let entry = entries.first(where: { $0.id == entryID }),
              case .updateAvailable = entry.status else { return }

        switch entry.source {
        case .homebrew:
            runBrewUpgrade(for: entry)
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

    private func runBrewUpgrade(for entry: InstalledAppUpdateEntry) {
        guard case .homebrew(let token) = entry.source, updatingBundleID == nil else { return }
        updatingBundleID = entry.id
        Task.detached(priority: .userInitiated) { [weak self] in
            let success = await HomebrewClient.upgrade(token: token)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updatingBundleID = nil
                if success {
                    self.refreshAfterBrewUpgrade(entryID: entry.id)
                } else if let index = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    self.entries[index].status = .error("brew upgrade failed — run it in Terminal for details.")
                }
            }
        }
    }

    private func refreshAfterBrewUpgrade(entryID: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        refreshInstalledVersions(at: index)
        checkAgain(entryID: entryID)
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

        backgroundTimer = Timer.scheduledCoalescing(withTimeInterval: backgroundCheckInterval, repeats: true) { [weak self] _ in
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
        guard !isChecking,
              entryCheckTasks[entryID] == nil,
              let index = entries.firstIndex(where: { $0.id == entryID }),
              entries[index].source != .none,
              entries[index].status != .checking,
              updatingBundleID != entryID,
              !ignoredBundleIDs.contains(entryID) else { return }
        refreshInstalledVersions(at: index)
        entries[index].status = .checking
        let app = entries[index]
        entryCheckTasks[entryID] = Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await performCheck(for: app)
            guard !Task.isCancelled,
                  !self.isChecking,
                  self.entryCheckTasks[entryID] != nil else { return }
            self.entryCheckTasks[entryID] = nil
            self.apply(status, toEntryWithID: entryID)
        }
    }

    private func refreshInstalledVersions(at index: Int) {
        guard entries.indices.contains(index),
              let versions = InstalledAppBundleVersionReader.read(at: entries[index].url) else { return }
        entries[index].currentVersion = versions.currentVersion
        entries[index].currentBuildVersion = versions.currentBuildVersion
    }

    func forgetApp(bundleIdentifier: String, url: URL, preserveBundlePreferences: Bool = false) {
        entryCheckTasks[bundleIdentifier]?.cancel()
        entryCheckTasks[bundleIdentifier] = nil
        entries.removeAll {
            $0.bundleIdentifier == bundleIdentifier
                && $0.url.standardizedFileURL == url.standardizedFileURL
        }
        if !preserveBundlePreferences {
            ignoredBundleIDs.remove(bundleIdentifier)
        }
        if let data = try? JSONEncoder().encode(Array(ignoredBundleIDs)) {
            UserDefaults.standard.set(data, forKey: ignoredAppsKey)
        }
    }
}