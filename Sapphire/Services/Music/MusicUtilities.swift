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

// MARK: - Consolidated from LyricsFetcher.swift
class LyricsFetcher {

    func fetchSyncedLyrics(for title: String, artist: String, album: String) async -> [LyricLine]? {

        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album)
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            struct LrcLibResponse: Decodable {
                let syncedLyrics: String?
            }

            let response = try Self.decoder.decode(LrcLibResponse.self, from: data)

            if let lrcString = response.syncedLyrics, !lrcString.isEmpty {
                return parseLRC(lrcString)
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    private func parseLRC(_ lrcString: String) -> [LyricLine] {
        var lyrics: [LyricLine] = []
        let lines = lrcString.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("[") && line.contains("]") {
                let components = line.components(separatedBy: "]")
                if components.count > 1 {
                    let timestampString = String(components[0].dropFirst())
                    let text = components[1].trimmingCharacters(in: .whitespaces)

                    let timeComponents = timestampString.components(separatedBy: ":")
                    if timeComponents.count == 2,
                       let minutes = Double(timeComponents[0]),
                       let seconds = Double(timeComponents[1]) {

                        let timestamp = (minutes * 60) + seconds
                        lyrics.append(LyricLine(text: text, timestamp: timestamp))
                    }
                }
            }
        }
        return lyrics.sorted { $0.timestamp < $1.timestamp }
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
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                let timeoutItem = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: timeoutItem)
                process.waitUntilExit()
                timeoutItem.cancel()
                if process.terminationStatus != 0 { return "ERROR" }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let resultString = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "No result string"
                print("[BrowserAppleScriptManager] LOG: AppleScript execution SUCCEEDED. Result: \(resultString)")
                return resultString
            } catch {
                print("[BrowserAppleScriptManager] ERROR: AppleScript execution failed: \(error.localizedDescription)")
                return "ERROR"
            }
        }.value
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

        if status == noErr, let deviceName = getDeviceName(deviceID), deviceName.contains("BlackHole") {
            return deviceID
        }

        var devicesPropertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var devicesPropertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devicesPropertyAddress, 0, nil, &devicesPropertySize) == noErr else { return nil }

        let deviceCount = Int(devicesPropertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devicesPropertyAddress, 0, nil, &devicesPropertySize, &deviceIDs) == noErr else { return nil }

        for id in deviceIDs {
            if let name = getDeviceName(id), name.contains("BlackHole") {
                return id
            }
        }

        return nil
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &name) == noErr else { return nil }
        return name as String
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

final class FileImageCache {
    static let shared = FileImageCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.sapphire.imagecache.io", qos: .utility)
    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        let cacheBaseUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cacheBaseUrl.appendingPathComponent("ImageCache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)

        Task.detached(priority: .background) { [weak self] in
            self?.cleanupOldFiles()
        }
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
        let cacheKey = NSString(string: key)
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }
        let url = cacheUrl(forKey: key)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return nil }
        memoryCache.setObject(image, forKey: cacheKey, cost: approximateCost(for: image))
        return image
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

        lock.lock()
        if let existing = inFlight[key] {
            lock.unlock()
            return await existing.value
        }
        let task = Task<NSImage?, Never> {
            defer {
                self.lock.lock()
                self.inFlight[key] = nil
                self.lock.unlock()
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let image = NSImage(data: data) else { return nil }
                self.set(image, forKey: key, rawData: data)
                return image
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        lock.unlock()
        return await task.value
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
        if let nsImage = image {
            content(Image(nsImage: nsImage))
        } else {
            placeholder()
                .task(id: url) {
                    guard let url else { return }
                    image = await FileImageCache.shared.image(for: url)
                }
        }
    }
}