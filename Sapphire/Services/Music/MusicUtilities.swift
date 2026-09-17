//
//  MusicUtilities.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import SwiftUI
import AppKit
import Combine
import CryptoKit
import AVFoundation
import CoreAudio
import Accelerate
import Yams

// MARK: - Consolidated from LyricsFetcher.swift

enum LyricsParser {
    private static let maximumLyricsfileBytes = 1_048_576
    private static let maximumResponseBytes = 4_194_304
    private static let maximumNodeCount = 50_000
    private static let maximumNodeDepth = 64

    private struct LRCLibResponse: Decodable {
        let lyricsfile: String?
        let syncedLyrics: String?
    }

    static func parseLRCLibResponse(_ data: Data) -> [LyricLine]? {
        guard data.count <= maximumResponseBytes else {
            LyricsLog.error("LRCLIB response rejected: \(data.count) bytes exceeds limit")
            return nil
        }
        let response: LRCLibResponse
        do {
            response = try JSONDecoder().decode(LRCLibResponse.self, from: data)
        } catch {
            LyricsLog.error("LRCLIB response JSON decode failed: \(error.localizedDescription)")
            return nil
        }

        if let lyricsfile = response.lyricsfile,
           !lyricsfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let parsed = parseLyricsfile(lyricsfile) {
                let wordSynced = parsed.filter(\.hasWordTiming).count
                LyricsLog.info("LRCLIB: using lyricsfile, \(parsed.count) lines (\(wordSynced) word-synced)")
                return parsed
            }
            LyricsLog.info("LRCLIB: lyricsfile rejected, falling back to syncedLyrics")
        } else {
            LyricsLog.info("LRCLIB: no lyricsfile in response, falling back to syncedLyrics")
        }

        guard let syncedLyrics = response.syncedLyrics,
              !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            LyricsLog.info("LRCLIB: no syncedLyrics either")
            return nil
        }
        let parsed = parseLRC(syncedLyrics)
        LyricsLog.info("LRCLIB: syncedLyrics parsed into \(parsed?.count ?? 0) lines")
        return parsed
    }

    static func parseLyricsfile(_ yaml: String) -> [LyricLine]? {
        guard !yaml.isEmpty else { return rejectLyricsfile("empty") }
        guard yaml.utf8.count <= maximumLyricsfileBytes else { return rejectLyricsfile("exceeds size limit") }

        do {
            let parser = try Parser(
                yaml: yaml,
                resolver: lyricsfileResolver,
                encoding: .utf8
            )
            guard let root = try parser.singleRoot() else { return rejectLyricsfile("no document") }
            guard isSafeDocumentTree(root) else {
                return rejectLyricsfile("unsafe tree (alias, anchor, disallowed tag, duplicate key, or size limit)")
            }
            guard let document = stringKeyedMapping(root) else { return rejectLyricsfile("root is not a string-keyed mapping") }
            guard strictString(document["version"]) == "1.0" else { return rejectLyricsfile("unsupported version") }
            guard let metadataNode = document["metadata"],
                  let metadata = stringKeyedMapping(metadataNode) else {
                return rejectLyricsfile("missing metadata mapping")
            }
            guard validateMetadata(metadata) else { return rejectLyricsfile("metadata field has the wrong type") }

            let plain: String?
            if let plainNode = document["plain"] {
                guard let parsedPlain = strictString(plainNode) else { return rejectLyricsfile("plain is not a string") }
                plain = parsedPlain
            } else {
                plain = nil
            }

            let lineNodes: [Node]
            if let linesNode = document["lines"] {
                guard let parsedLines = sequence(linesNode) else { return rejectLyricsfile("lines is not a sequence") }
                lineNodes = parsedLines
            } else {
                lineNodes = []
            }

            let instrumental = metadata["instrumental"].flatMap { strictBool($0) } ?? false
            if instrumental, !lineNodes.isEmpty || !(plain?.isEmpty ?? true) {
                return rejectLyricsfile("instrumental document contains lyrics")
            }

            var parsedLines: [(sourceIndex: Int, line: LyricLine)] = []
            parsedLines.reserveCapacity(lineNodes.count)
            for (sourceIndex, lineNode) in lineNodes.enumerated() {
                guard let line = parseLine(lineNode) else {
                    return rejectLyricsfile("line \(sourceIndex) has a missing or mistyped field")
                }
                parsedLines.append((sourceIndex, line))
            }

            return parsedLines.sorted {
                if $0.line.timestamp == $1.line.timestamp {
                    return $0.sourceIndex < $1.sourceIndex
                }
                return $0.line.timestamp < $1.line.timestamp
            }.map(\.line)
        } catch {
            return rejectLyricsfile("YAML error \(type(of: error))")
        }
    }

    private static func rejectLyricsfile(_ reason: String) -> [LyricLine]? {
        LyricsLog.info("Lyricsfile rejected: \(reason)")
        return nil
    }

    static func parseLRC(_ lrcString: String) -> [LyricLine]? {
        guard !lrcString.isEmpty, lrcString.utf8.count <= maximumLyricsfileBytes else { return nil }

        var parsed: [(sourceIndex: Int, line: LyricLine)] = []
        var sourceIndex = 0

        for rawLine in lrcString.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = lrcTimestampRegex.matches(in: rawLine, range: fullRange)
            guard let firstMatch = matches.first, firstMatch.range.location == 0 else { continue }

            var timestamps: [TimeInterval] = []
            var lyricStart = 0
            for match in matches {
                guard match.range.location == lyricStart,
                      let timestamp = lrcTimestamp(from: match, in: nsLine) else {
                    break
                }
                timestamps.append(timestamp)
                lyricStart = NSMaxRange(match.range)
            }
            guard !timestamps.isEmpty else { continue }

            let text = nsLine.substring(from: lyricStart)
                .trimmingCharacters(in: .whitespaces)
            for timestamp in timestamps {
                parsed.append((
                    sourceIndex,
                    LyricLine(text: text, timestamp: timestamp)
                ))
                sourceIndex += 1
            }
        }

        guard !parsed.isEmpty else { return nil }
        return parsed.sorted {
            if $0.line.timestamp == $1.line.timestamp {
                return $0.sourceIndex < $1.sourceIndex
            }
            return $0.line.timestamp < $1.line.timestamp
        }.map(\.line)
    }

    private static func validateMetadata(_ metadata: [String: Node]) -> Bool {
        guard strictString(metadata["title"]) != nil,
              strictString(metadata["artist"]) != nil else {
            return false
        }
        if let album = metadata["album"], strictString(album) == nil { return false }
        if let language = metadata["language"], strictString(language) == nil { return false }
        if let instrumental = metadata["instrumental"], strictBool(instrumental) == nil { return false }
        if let offset = metadata["offset_ms"], strictInt(offset) == nil { return false }
        if let duration = metadata["duration_ms"] {
            guard let milliseconds = strictInt(duration), milliseconds >= 0 else { return false }
        }
        return true
    }

    private static func parseLine(_ node: Node) -> LyricLine? {
        guard let mapping = stringKeyedMapping(node),
              let text = strictString(mapping["text"]),
              let startMilliseconds = strictInt(mapping["start_ms"]),
              startMilliseconds >= 0 else {
            return nil
        }

        let endMilliseconds: Int?
        if let endNode = mapping["end_ms"] {
            guard let value = strictInt(endNode), value >= startMilliseconds else { return nil }
            endMilliseconds = value
        } else {
            endMilliseconds = nil
        }

        var words: [LyricWord] = []
        if let wordsNode = mapping["words"] {
            guard let wordNodes = sequence(wordsNode) else { return nil }
            words.reserveCapacity(wordNodes.count)
            for wordNode in wordNodes {
                guard let word = parseWord(wordNode) else { return nil }
                words.append(word)
            }
        }

        return LyricLine(
            text: text,
            timestamp: seconds(fromMilliseconds: startMilliseconds),
            endTimestamp: endMilliseconds.map { seconds(fromMilliseconds: $0) },
            words: words
        )
    }

    private static func parseWord(_ node: Node) -> LyricWord? {
        guard let mapping = stringKeyedMapping(node),
              let text = strictString(mapping["text"]),
              let startMilliseconds = strictInt(mapping["start_ms"]),
              startMilliseconds >= 0 else {
            return nil
        }

        let endMilliseconds: Int?
        if let endNode = mapping["end_ms"] {
            guard let value = strictInt(endNode), value >= startMilliseconds else { return nil }
            endMilliseconds = value
        } else {
            endMilliseconds = nil
        }

        return LyricWord(
            text: text,
            timestamp: seconds(fromMilliseconds: startMilliseconds),
            endTimestamp: endMilliseconds.map { seconds(fromMilliseconds: $0) }
        )
    }

    private static func isSafeDocumentTree(_ root: Node) -> Bool {
        let allowedTags: Set<String> = [
            "tag:yaml.org,2002:map",
            "tag:yaml.org,2002:seq",
            "tag:yaml.org,2002:str",
            "tag:yaml.org,2002:int",
            "tag:yaml.org,2002:bool",
            "tag:yaml.org,2002:null",
        ]
        var stack: [(node: Node, depth: Int)] = [(root, 1)]
        var nodeCount = 0

        while let current = stack.popLast() {
            nodeCount += 1
            guard nodeCount <= maximumNodeCount,
                  current.depth <= maximumNodeDepth,
                  current.node.anchor == nil,
                  allowedTags.contains(current.node.tag.rawValue) else {
                return false
            }

            switch current.node {
            case .scalar:
                break
            case .alias:
                return false
            case .sequence(let sequence):
                for child in sequence {
                    stack.append((child, current.depth + 1))
                }
            case .mapping(let mapping):
                var keys = Set<String>()
                for pair in mapping {
                    guard let key = strictString(pair.key), keys.insert(key).inserted else {
                        return false
                    }
                    stack.append((pair.key, current.depth + 1))
                    stack.append((pair.value, current.depth + 1))
                }
            }
        }
        return true
    }

    private static func stringKeyedMapping(_ node: Node) -> [String: Node]? {
        guard case .mapping(let mapping) = node else { return nil }
        var result: [String: Node] = [:]
        result.reserveCapacity(mapping.count)
        for pair in mapping {
            guard let key = strictString(pair.key), result[key] == nil else { return nil }
            result[key] = pair.value
        }
        return result
    }

    private static func sequence(_ node: Node) -> [Node]? {
        guard case .sequence(let sequence) = node else { return nil }
        return Array(sequence)
    }

    private static func strictString(_ node: Node?) -> String? {
        guard let node, case .scalar(let scalar) = node,
              node.tag.rawValue == "tag:yaml.org,2002:str" else {
            return nil
        }
        return scalar.string
    }

    private static func strictInt(_ node: Node?) -> Int? {
        guard let node, node.tag.rawValue == "tag:yaml.org,2002:int" else { return nil }
        return node.int
    }

    private static func strictBool(_ node: Node?) -> Bool? {
        guard let node, node.tag.rawValue == "tag:yaml.org,2002:bool" else { return nil }
        return node.bool
    }

    private static func seconds(fromMilliseconds milliseconds: Int) -> TimeInterval {
        TimeInterval(milliseconds) / 1_000
    }

    private static let lyricsfileResolver: Resolver = {
        let yaml12Boolean = try! Resolver.Rule(
            .bool,
            #"^(?:true|True|TRUE|false|False|FALSE)$"#
        )
        let yaml12Integer = try! Resolver.Rule(
            .int,
            #"^(?:[-+]?0b[0-1_]+|[-+]?0o[0-7_]+|[-+]?(?:0|[1-9][0-9_]*)|[-+]?0x[0-9a-fA-F_]+)$"#
        )
        let yaml12Float = try! Resolver.Rule(
            .float,
            #"^(?:[-+]?(?:[0-9][0-9_]*)(?:\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?|\.[0-9_]+(?:[eE][-+]?[0-9]+)?|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$"#
        )
        let yaml12Null = try! Resolver.Rule(
            .null,
            #"^(?:~|null|Null|NULL|)$"#
        )
        return Resolver.basic
            .appending(yaml12Boolean)
            .appending(yaml12Integer)
            .appending(yaml12Float)
            .appending(yaml12Null)
    }()

    private static let lrcTimestampRegex = try! NSRegularExpression(
        pattern: #"\[(\d+):([0-5]?\d)(?:[\.:](\d{1,3}))?\]"#
    )

    private static func lrcTimestamp(
        from match: NSTextCheckingResult,
        in line: NSString
    ) -> TimeInterval? {
        guard match.numberOfRanges == 4,
              let minutes = Int(line.substring(with: match.range(at: 1))),
              let seconds = Int(line.substring(with: match.range(at: 2))),
              seconds < 60,
              minutes <= (Int.max - seconds) / 60 else {
            return nil
        }

        var fraction = 0.0
        let fractionRange = match.range(at: 3)
        if fractionRange.location != NSNotFound {
            let digits = line.substring(with: fractionRange)
            guard let value = Int(digits) else { return nil }
            fraction = Double(value) / pow(10, Double(digits.count))
        }
        return TimeInterval(minutes * 60 + seconds) + fraction
    }
}

class LyricsFetcher {

    func fetchSyncedLyrics(for title: String, artist: String, album: String) async -> [LyricLine]? {

        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album)
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(Self.lrclibUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            LyricsLog.info("LRCLIB GET '\(title)' / '\(artist)' / '\(album)': HTTP \(status), \(data.count) bytes, \(elapsedMs)ms")
            guard (200...299).contains(status) else { return nil }
            return LyricsParser.parseLRCLibResponse(data)
        } catch {
            LyricsLog.error("LRCLIB GET '\(title)' / '\(artist)' failed: \(error.localizedDescription)")
            return nil
        }
    }

    func detectLanguage(for text: String) async -> String? {

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: trimmedText.description)
        ]

        guard let url = components.url else { return nil }

        struct UnofficialGoogleDetectionResponse: Decodable {
            let detectedLanguage: String?
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                _ = try? container.nestedUnkeyedContainer()
                _ = try? container.decode(String?.self)
                self.detectedLanguage = try? container.decode(String.self)
            }
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let unofficialResponse = try Self.decoder.decode(UnofficialGoogleDetectionResponse.self, from: data)
            if let lang = unofficialResponse.detectedLanguage {
                return lang
            }
        } catch {
        }
        return nil
    }

    func translate(lyrics: inout [LyricLine], from sourceLanguage: String, to targetLanguage: String) async {
        guard !lyrics.isEmpty else { return }

        var chunks: [[(index: Int, text: String)]] = []
        var currentChunk: [(index: Int, text: String)] = []
        var currentLength = 0

        for i in 0..<lyrics.count {
            let originalText = lyrics[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if originalText.isEmpty {
                lyrics[i].translatedText = ""
                continue
            }

            if currentLength + originalText.count + 1 > 1800 && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                currentLength = 0
            }

            currentChunk.append((index: i, text: originalText))
            currentLength += originalText.count + 1
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        struct UnofficialGoogleTranslateResponse: Decodable {
            let translatedText: String?
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                if var outerArray = try? container.nestedUnkeyedContainer() {
                    var combinedTranslation = ""
                    while !outerArray.isAtEnd {
                        if var firstInnerArray = try? outerArray.nestedUnkeyedContainer(),
                           let translatedSegment = try? firstInnerArray.decode(String.self) {
                            combinedTranslation += translatedSegment
                        } else {
                            _ = try? outerArray.decode(AnyCodable.self)
                        }
                    }
                    self.translatedText = combinedTranslation.isEmpty ? nil : combinedTranslation
                } else {
                    self.translatedText = nil
                }
            }
        }

        struct AnyCodable: Decodable {}

        await withTaskGroup(of: [(Int, String)].self) { group in
            for chunk in chunks {
                group.addTask {
                    let combinedText = chunk.map { $0.text }.joined(separator: "\n")

                    var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
                    components.queryItems = [
                        URLQueryItem(name: "client", value: "gtx"),
                        URLQueryItem(name: "sl", value: sourceLanguage),
                        URLQueryItem(name: "tl", value: targetLanguage),
                        URLQueryItem(name: "dt", value: "t"),
                        URLQueryItem(name: "q", value: combinedText)
                    ]

                    guard let url = components.url else { return [] }

                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let unofficialResponse = try Self.decoder.decode(UnofficialGoogleTranslateResponse.self, from: data)

                        if let translatedResult = unofficialResponse.translatedText {
                            let translatedLines = translatedResult.components(separatedBy: "\n")
                            var results: [(Int, String)] = []
                            for (offset, item) in chunk.enumerated() {
                                if offset < translatedLines.count {
                                    let cleanText = translatedLines[offset].trimmingCharacters(in: .whitespacesAndNewlines)
                                    results.append((item.index, cleanText.isEmpty ? item.text : cleanText))
                                } else {
                                    results.append((item.index, item.text))
                                }
                            }
                            return results
                        }
                    } catch {
                    }
                    return chunk.map { ($0.index, $0.text) }
                }
            }

            for await chunkResult in group {
                for (index, translatedText) in chunkResult {
                    lyrics[index].translatedText = translatedText
                }
            }
        }

        for i in 0..<lyrics.count {
            if lyrics[i].translatedText == nil {
                lyrics[i].translatedText = lyrics[i].text
            }
        }
    }

    private static let decoder: JSONDecoder = {
        return JSONDecoder()
    }()

    private static var lrclibUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let displayVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        return "Sapphire v\(displayVersion) (https://github.com/cshariq/Sapphire)"
    }
}

// MARK: - Consolidated from PlayCountResponse.swift

fileprivate struct PlayCountResponse: Codable {
    let success: Bool
    let playcount: Int?
    let uri: String?
}

@MainActor
class PlayCountFetcher {
    static let shared = PlayCountFetcher()

    private static let decoder = JSONDecoder()

    private init() {}

    func getPlayCountValue(for trackID: String) async -> Int? {
        let cleanTrackID = trackID.components(separatedBy: ":").last ?? trackID

        guard let url = URL(string: "https://api.stats.fm/api/v1/tracks/\(cleanTrackID)") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try Self.decoder.decode(PlayCountResponse.self, from: data)
            return response.playcount
        } catch {
            print("[PlayCountFetcher] Failed to fetch or decode play count: \(error)")
            return nil
        }
    }

    func getPlayCount(for trackID: String) async -> String? {
        guard let count = await getPlayCountValue(for: trackID) else { return nil }
        return Self.formatPlayCount(count)
    }

    static func formatPlayCount(_ number: Int) -> String {
        let num = Double(number)
        let thousand = 1000.0
        let million = 1000000.0

        if num >= million {
            let formattedNum = num / million
            return "\(String(format: formattedNum < 10 ? "%.1f" : "%.0f", formattedNum))M"
        } else if num >= thousand {
            let formattedNum = num / thousand
            return "\(String(format: "%.0f", formattedNum))K"
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Consolidated from BrowserAppleScriptManager.swift

@MainActor
class BrowserAppleScriptManager {
    static let shared = BrowserAppleScriptManager()

    private init() {}

    private func escapeStringForAppleScript(_ input: String) -> String {
        return input.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func focusTab(for bundleID: String, with trackTitle: String) {
        print("[BrowserAppleScriptManager] LOG: Received request to focus tab for bundleID: '\(bundleID)' with track title: '\(trackTitle)'")

        let appName: String
        let script: String
        let escapedTitle = escapeStringForAppleScript(trackTitle)

        switch bundleID {
        case "com.apple.Safari":
            appName = "Safari"
            script = """
            tell application "\(appName)"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if name of t contains "\(escapedTitle)" then
                            set current tab of w to t
                            set index of w to 1
                            return "FOUND"
                        end if
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """

        case "com.google.Chrome", "com.microsoft.edgemac":
            appName = bundleID == "com.google.Chrome" ? "Google Chrome" : "Microsoft Edge"
            script = """
            tell application "\(appName)"
                activate
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if title of t contains "\(escapedTitle)" then
                            set active tab index of w to i
                            set index of w to 1
                            return "FOUND"
                        end if
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """

        case "company.thebrowser.Browser":
            appName = "Arc"
            script = """
            tell application "\(appName)"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if title of t contains "\(escapedTitle)" then
                            select t
                            set index of w to 1
                            return "FOUND"
                        end if
                    end repeat
                end repeat
                return "NOT_FOUND"
            end tell
            """

        default:
            print("[BrowserAppleScriptManager] LOG: BundleID '\(bundleID)' is not a supported browser. Aborting.")
            return
        }

        print("[BrowserAppleScriptManager] LOG: Determined app name: '\(appName)'.")
        print("[BrowserAppleScriptManager] LOG: Preparing to execute the following AppleScript:\n---\n\(script)\n---")

        Task {
            let result = await runAppleScriptInBackground(script)
            if result == "NOT_FOUND" {
                print("[BrowserAppleScriptManager] LOG: Tab not found. Activating app as a fallback.")
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.open(appURL)
                }
            }
        }
    }

    private func runAppleScriptInBackground(_ script: String) async -> String {
        print("[BrowserAppleScriptManager] LOG: Executing AppleScript via osascript...")
        guard let result = await ProcessRunner.run(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: 5
        ) else {
            print("[BrowserAppleScriptManager] ERROR: AppleScript execution failed to launch.")
            return "ERROR"
        }
        if result.exitCode != 0 { return "ERROR" }
        let resultString = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[BrowserAppleScriptManager] LOG: AppleScript execution SUCCEEDED. Result: \(resultString)")
        return resultString
    }
}

// MARK: - Consolidated from SystemAudioMonitor.swift

class SystemAudioMonitor: ObservableObject {
    @Published var audioLevel: Float = 0.0

    private let engine = AVAudioEngine()
    private var isMonitoring = false
    private var lastUpdateTime: TimeInterval = 0

    init() {}

    func start() {
        guard !isMonitoring else { return }
        setupAndStartEngine()
    }

    func stop() {
        guard isMonitoring else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isMonitoring = false
    }

    private func setupAndStartEngine() {
        let inputNode = engine.inputNode

        guard let blackHoleDeviceID = findBlackHoleDeviceID() else {
            return
        }

        do {
            var deviceID = blackHoleDeviceID
            guard let audioUnit = inputNode.audioUnit else {
                print("[SystemAudioMonitor] Could not get AudioUnit for input node."); return
            }
            let error = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            if error != noErr {
                print("[SystemAudioMonitor] Failed to set input device. Error: \(error)"); return
            }
            try engine.start()
        } catch {
            print("[SystemAudioMonitor] Failed to start audio engine: \(error.localizedDescription)"); return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateRMS(from: buffer)

            let now = CACurrentMediaTime()
            if now - self.lastUpdateTime >= 0.033 {
                self.lastUpdateTime = now
                DispatchQueue.main.async { self.audioLevel = level }
            }
        }

        isMonitoring = true
    }

    private func findBlackHoleDeviceID() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        if status == noErr, let deviceName = CoreAudioDevices.name(of: deviceID), deviceName.contains("BlackHole") {
            return deviceID
        }

        guard let deviceIDs = CoreAudioDevices.all() else { return nil }

        for id in deviceIDs {
            if let name = CoreAudioDevices.name(of: id), name.contains("BlackHole") {
                return id
            }
        }

        return nil
    }

    private func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        var rms: Float = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var channelRms: Float = 0.0
            vDSP_rmsqv(samples, 1, &channelRms, vDSP_Length(frameLength))
            rms += channelRms
        }

        let averageRms = rms / Float(channelCount)
        let amplifier: Float = 4.5
        let processedRms = min(1.0, averageRms * amplifier)

        return processedRms
    }
}

// MARK: - Consolidated from MusicLongPressSupport.swift

extension Notification.Name {
    static let sapphireOpenMusicQueue = Notification.Name("sapphireOpenMusicQueue")
    static let sapphireOpenMusicDevices = Notification.Name("sapphireOpenMusicDevices")
}

struct MusicLongPressNavigation {
    var openQueue: (() -> Void)?
    var openDevices: (() -> Void)?

    static let notifications = MusicLongPressNavigation(
        openQueue: { NotificationCenter.default.post(name: .sapphireOpenMusicQueue, object: nil) },
        openDevices: { NotificationCenter.default.post(name: .sapphireOpenMusicDevices, object: nil) }
    )
}

extension MusicLongPressAction {
    var isRepeatableWhileHeld: Bool {
        switch self {
        case .repeatMode, .shuffle, .playPause, .like, .nextTrack, .previousTrack:
            return true
        default:
            return false
        }
    }

    @MainActor
    func feedbackSystemImage(musicManager: MusicManager) -> String {
        switch self {
        case .shuffle:
            return musicManager.spotifyPrivateAPI.isSmartShuffleActive ? "sparkles" : "shuffle"
        case .repeatMode:
            switch musicManager.repeatState {
            case .track: return "repeat.1"
            case .context: return "repeat"
            case .off: return "repeat"
            }
        case .like:
            return musicManager.isLiked ? "heart.fill" : "heart"
        case .playPause:
            return musicManager.isPlaying ? "pause.fill" : "play.fill"
        case .nextTrack:
            return "forward.fill"
        case .previousTrack:
            return "backward.fill"
        case .openQueue:
            return "list.bullet"
        case .openDevices:
            return "hifispeaker.fill"
        case .seek:
            return "goforward"
        case .none:
            return "ellipsis"
        }
    }

    @MainActor
    func feedbackColor(musicManager: MusicManager) -> Color {
        switch self {
        case .shuffle:
            return (musicManager.shuffleState || musicManager.spotifyPrivateAPI.isSmartShuffleActive) ? .green : .secondary
        case .repeatMode:
            return musicManager.repeatState != .off ? .green : .secondary
        case .like:
            return musicManager.isLiked ? .pink : .secondary
        default:
            return .primary
        }
    }
}

@MainActor
extension MusicManager {
    func performLongPressAction(_ action: MusicLongPressAction, navigation: MusicLongPressNavigation? = nil) async {
        switch action {
        case .none, .seek:
            break
        case .shuffle:
            await toggleShuffle()
        case .repeatMode:
            await cycleRepeatMode()
        case .like:
            await toggleLike()
        case .playPause:
            if isPlaying {
                await pause()
            } else {
                await play()
            }
        case .nextTrack:
            await nextTrack()
        case .previousTrack:
            await previousTrack()
        case .openQueue:
            if let openQueue = navigation?.openQueue {
                openQueue()
            } else {
                NotificationCenter.default.post(name: .sapphireOpenMusicQueue, object: nil)
            }
        case .openDevices:
            if let openDevices = navigation?.openDevices {
                openDevices()
            } else {
                NotificationCenter.default.post(name: .sapphireOpenMusicDevices, object: nil)
            }
        }
    }
}

enum MusicLongPressUI {
    @MainActor
    static func skipHoldHandler(
        for target: MusicLongPressTarget,
        settings: Settings,
        musicManager: MusicManager,
        navigation: MusicLongPressNavigation? = nil
    ) -> (() -> Void)? {
        let action = settings.resolvedSkipHoldAction(for: target)
        guard action != .seek, action != .none else { return nil }
        return {
            Task { await musicManager.performLongPressAction(action, navigation: navigation) }
        }
    }

    static func skipHelp(primary: String, target: MusicLongPressTarget, settings: Settings) -> String {
        if !settings.musicLongPressActionsEnabled {
            return "\(primary) · hold to seek"
        }
        let action = settings.resolvedSkipHoldAction(for: target)
        if action == .none {
            return primary
        }
        if action == .seek {
            return "\(primary) · hold to seek"
        }
        return "\(primary) · hold for \(action.displayName)"
    }

    static func accessoryHelp(primary: String, target: MusicLongPressTarget, settings: Settings) -> String {
        guard let action = settings.resolvedAccessoryHoldAction(for: target) else {
            return primary
        }
        return "\(primary) · hold for \(action.displayName)"
    }
}

@MainActor
final class MusicHoldFeedbackController: ObservableObject {
    enum Palette {
        case standard
        case lightOverlay
    }

    @Published private(set) var action: MusicLongPressAction?
    @Published private(set) var icon: String?
    @Published private(set) var color: Color
    @Published private(set) var buttonID: String?

    private let palette: Palette
    private var restoreTask: Task<Void, Never>?
    private var actionInFlight = false

    init(palette: Palette = .standard) {
        self.palette = palette
        self.color = palette == .lightOverlay ? .white : .primary
    }

    func skipAction(for target: MusicLongPressTarget, settings: Settings) -> MusicLongPressAction? {
        let action = settings.resolvedSkipHoldAction(for: target)
        return action == .none || action == .seek ? nil : action
    }

    func handler(
        for action: MusicLongPressAction,
        musicManager: MusicManager,
        navigation: MusicLongPressNavigation?,
        onCompletion: @escaping @MainActor () -> Void = {}
    ) -> () -> Void {
        { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.actionInFlight else { return }
                self.actionInFlight = true
                defer { self.actionInFlight = false }
                await musicManager.performLongPressAction(action, navigation: navigation)
                self.refresh(using: musicManager)
                onCompletion()
            }
        }
    }

    func begin(action: MusicLongPressAction, buttonID: String, musicManager: MusicManager) {
        restoreTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            self.buttonID = buttonID
            self.action = action
            updateFeedback(for: action, using: musicManager)
        }
    }

    func end() {
        restoreTask?.cancel()
        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.action = nil
                self.icon = nil
                self.buttonID = nil
            }
        }
    }

    func reset() {
        restoreTask?.cancel()
        restoreTask = nil
        action = nil
        icon = nil
        buttonID = nil
    }

    private func refresh(using musicManager: MusicManager) {
        guard let action else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            updateFeedback(for: action, using: musicManager)
        }
    }

    private func updateFeedback(for action: MusicLongPressAction, using musicManager: MusicManager) {
        icon = action.feedbackSystemImage(musicManager: musicManager)
        let actionColor = action.feedbackColor(musicManager: musicManager)
        color = palette == .lightOverlay && actionColor == .secondary ? .white.opacity(0.7) : actionColor
    }
}

struct LongPressControlButton<Label: View>: View {
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil
    var onHoldBegan: ((MusicLongPressAction) -> Void)? = nil
    var holdAction: MusicLongPressAction? = nil
    var onHoldRepeat: (() -> Void)? = nil
    var onHoldEnded: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        if onLongPress != nil || holdAction != nil {
            LongPressControlButtonBody(
                onTap: onTap,
                onLongPress: onLongPress,
                onHoldBegan: onHoldBegan,
                holdAction: holdAction,
                onHoldRepeat: onHoldRepeat,
                onHoldEnded: onHoldEnded,
                label: label
            )
        } else {
            Button(action: onTap, label: label)
        }
    }
}

private struct LongPressControlButtonBody<Label: View>: View {
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    let onHoldBegan: ((MusicLongPressAction) -> Void)?
    let holdAction: MusicLongPressAction?
    let onHoldRepeat: (() -> Void)?
    let onHoldEnded: (() -> Void)?
    @ViewBuilder var label: () -> Label

    @GestureState private var isPressing = false
    @State private var longPressTimer: Timer?
    @State private var repeatTimer: Timer?
    @State private var tapIsEligible = false
    @State private var didFireLongPress = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in state = true }
            )
            .onChange(of: isPressing) { _, nowPressing in
                if nowPressing {
                    tapIsEligible = true
                    didFireLongPress = false
                    longPressTimer?.invalidate()
                    repeatTimer?.invalidate()
                    let timer = Timer(timeInterval: 0.45, repeats: false) { _ in
                        tapIsEligible = false
                        didFireLongPress = true
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        if let holdAction {
                            onHoldBegan?(holdAction)
                        }
                        onLongPress?()
                        let shouldRepeat = holdAction?.isRepeatableWhileHeld == true || onHoldRepeat != nil
                        guard shouldRepeat else { return }
                        let repeating = Timer(timeInterval: 0.55, repeats: true) { _ in
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            onLongPress?()
                            onHoldRepeat?()
                        }
                        RunLoop.main.add(repeating, forMode: .common)
                        repeatTimer = repeating
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    longPressTimer = timer
                } else {
                    longPressTimer?.invalidate()
                    repeatTimer?.invalidate()
                    repeatTimer = nil
                    if didFireLongPress {
                        onHoldEnded?()
                    } else if tapIsEligible {
                        onTap()
                    }
                    didFireLongPress = false
                }
            }
            .blur(radius: (isPressing && !didFireLongPress) ? 3 : 0)
            .scaleEffect(isPressing ? 0.92 : 1.0)
            .opacity((isPressing && !didFireLongPress) ? 0.85 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isPressing)
            .animation(.easeInOut(duration: 0.12), value: didFireLongPress)
    }
}

// MARK: - Consolidated from ImageCache.swift

final class FileImageCache: @unchecked Sendable {
    static let shared = FileImageCache()

    private struct InFlightImage {
        let token: UUID
        let task: Task<NSImage?, Never>
    }

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.sapphire.imagecache.io", qos: .utility)
    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    private var inFlight: [String: InFlightImage] = [:]
    private let lock = NSLock()

    private init() {
        let cacheBaseUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        cacheDirectory = cacheBaseUrl.appendingPathComponent("ImageCache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)

        Task.detached(priority: .background) { [weak self] in
            self?.cleanupOldFiles()
        }
    }

    private func withLockedState<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func cacheKey(for urlKey: String) -> String {
        let digest = SHA256.hash(data: Data(urlKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheUrl(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(cacheKey(for: key)).appendingPathExtension("img")
    }

    private func approximateCost(for image: NSImage) -> Int {
        let size = image.size
        let pixels = max(1, Int(size.width * size.height))
        return min(pixels * 4, 8 * 1024 * 1024)
    }

    func get(forKey key: String) -> NSImage? {
        memoryCache.object(forKey: NSString(string: key))
    }

    func set(_ image: NSImage, forKey key: String, rawData: Data? = nil) {
        let cacheKey = NSString(string: key)
        memoryCache.setObject(image, forKey: cacheKey, cost: approximateCost(for: image))

        let url = cacheUrl(forKey: key)
        let dataToWrite: Data? = {
            if let rawData, !rawData.isEmpty { return rawData }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        }()

        guard let dataToWrite else { return }
        ioQueue.async {
            try? dataToWrite.write(to: url, options: .atomic)
        }
    }

    func image(for url: URL) async -> NSImage? {
        let key = url.absoluteString
        if let cached = get(forKey: key) { return cached }

        let request: InFlightImage = withLockedState {
            if let existing = inFlight[key] { return existing }
            let token = UUID()
            let task = Task.detached(priority: .utility) { [weak self] in
                await self?.loadOrDownloadImage(for: url, key: key)
            }
            let request = InFlightImage(token: token, task: task)
            inFlight[key] = request
            return request
        }

        let image = await request.task.value
        withLockedState {
            if inFlight[key]?.token == request.token {
                inFlight.removeValue(forKey: key)
            }
        }
        return image
    }

    private func loadOrDownloadImage(for url: URL, key: String) async -> NSImage? {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  !Task.isCancelled,
                  let image = NSImage(data: data) else { return nil }
            memoryCache.setObject(
                image,
                forKey: NSString(string: key),
                cost: approximateCost(for: image)
            )
            return image
        }

        let diskURL = cacheUrl(forKey: key)
        if fileManager.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL),
           let image = NSImage(data: data) {
            memoryCache.setObject(
                image,
                forKey: NSString(string: key),
                cost: approximateCost(for: image)
            )
            return image
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = NSImage(data: data) else { return nil }
            set(image, forKey: key, rawData: data)
            return image
        } catch {
            return nil
        }
    }

    func remove(forKey key: String) {
        memoryCache.removeObject(forKey: NSString(string: key))
    }

    func trimMemoryCache() {
        memoryCache.removeAllObjects()
    }

    private func cleanupOldFiles() {
        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60
        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            for file in files {
                if let modificationDate = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   Date().timeIntervalSince(modificationDate) > expirationInterval {
                    try fileManager.removeItem(at: file)
                }
            }
        } catch {
            print("Error cleaning up image cache: \(error)")
        }
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var loadedURL: URL?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let nsImage = image, url == loadedURL {
                content(Image(nsImage: nsImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                loadedURL = nil
                return
            }
            let nsImage = await FileImageCache.shared.image(for: url)
            image = nsImage
            loadedURL = url
        }
    }
}