//
//  GeminiLiveManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import Combine
import AVFoundation
import AppKit
import ScreenCaptureKit
import CoreAudio
import CoreMedia

@MainActor
final class GeminiLiveManager: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var isSessionRunning = false
    @Published var isMicMuted = true
    @Published var currentAudioLevel: Float = 0.0
    @Published var inputTranscript = ""
    @Published var outputTranscript = ""
    @Published var lastError: String?

    let sessionDidEndPublisher = PassthroughSubject<Void, Never>()

    private let liveSession = GeminiLiveSession()
    private var cancellables = Set<AnyCancellable>()

    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playerAttached = false
    private var audioLevelTimer: Timer?
    private var setupTimeoutTask: Task<Void, Never>?
    private var screenCaptureTask: Task<Void, Never>?
    private var hardwarePlaybackFormat: AVAudioFormat?

    private let captureSession = AVCaptureSession()
    private let captureOutput = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "sapphire.gemini.live.mic")
    private var captureConfigured = false
    nonisolated(unsafe) private var micConverter: AVAudioConverter?
    nonisolated(unsafe) private var micSourceFormat: AVAudioFormat?

    private var isWaitingForSetupComplete = false
    private var currentScreenFilter: SCContentFilter?
    private let inputSampleRate: Double = 16000.0
    private let outputSampleRate: Double = 24000.0
    private let maxAudioFramesPerBuffer = 240
    private let liveFrameIntervalNanoseconds: UInt64 = 1_000_000_000

    override init() {
        super.init()
        observeMessages()
    }

    // MARK: - Engine

    private var geminiPlaybackFormat: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: outputSampleRate, channels: 1)
    }

    private func startMicrophoneCapture() throws {
        if captureSession.isRunning { return }

        let device = Self.builtInCaptureDevice() ?? AVCaptureDevice.default(for: .audio)
        guard let device else {
            throw NSError(
                domain: "GeminiLive",
                code: -10875,
                userInfo: [NSLocalizedDescriptionKey: "No microphone is available."]
            )
        }

        captureSession.beginConfiguration()
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        if !captureSession.outputs.contains(captureOutput) {
            captureOutput.setSampleBufferDelegate(self, queue: captureQueue)
            if captureSession.canAddOutput(captureOutput) {
                captureSession.addOutput(captureOutput)
            }
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw NSError(
                domain: "GeminiLive",
                code: -10875,
                userInfo: [NSLocalizedDescriptionKey: "Could not open the built-in microphone."]
            )
        }
        captureSession.addInput(input)
        captureSession.commitConfiguration()
        captureConfigured = true
        captureSession.startRunning()
        print("[GeminiLiveManager] Capturing from \(device.localizedName) via AVCaptureSession.")
    }

    private static func builtInCaptureDevice() -> AVCaptureDevice? {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        if let builtInUID = builtInInputUID() {
            if let match = session.devices.first(where: { $0.uniqueID == builtInUID }) {
                return match
            }
        }
        return session.devices.first { device in
            let name = device.localizedName.lowercased()
            return name.contains("macbook") || name.contains("imac") || name.contains("built-in") || name.contains("microphone")
        } ?? session.devices.first
    }

    private static func builtInInputUID() -> String? {
        guard let deviceID = builtInInputDeviceID() else { return nil }
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr else { return nil }
        let value = uid as String
        return value.isEmpty ? nil : value
    }

    private static func builtInInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return nil
        }

        for deviceID in deviceIDs {
            guard deviceHasInputChannels(deviceID) else { continue }
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType) == noErr else {
                continue
            }
            if transportType == kAudioDeviceTransportTypeBuiltIn {
                return deviceID
            }
        }
        return nil
    }

    private static func deviceHasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func ensurePlaybackEngine() throws {
        if playbackEngine.isRunning { return }

        let hardwareFormat = playbackEngine.outputNode.outputFormat(forBus: 0)
        let playerFormat = AVAudioFormat(
            standardFormatWithSampleRate: hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 48000,
            channels: 1
        )
        guard let playerFormat else {
            throw NSError(domain: "GeminiLive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create playback format."])
        }
        hardwarePlaybackFormat = playerFormat

        if !playerAttached {
            playbackEngine.attach(playerNode)
            playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: playerFormat)
            playerAttached = true
        }

        playbackEngine.mainMixerNode.auAudioUnit.maximumFramesToRender = 4096
        playbackEngine.outputNode.auAudioUnit.maximumFramesToRender = 4096
        playerNode.auAudioUnit.maximumFramesToRender = 4096

        playbackEngine.prepare()
        try playbackEngine.start()
        playerNode.play()
    }

    private func stopEngines() {
        screenCaptureTask?.cancel()
        screenCaptureTask = nil

        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        captureSession.beginConfiguration()
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.commitConfiguration()
        micConverter = nil
        micSourceFormat = nil

        playerNode.stop()
        if playbackEngine.isRunning {
            playbackEngine.stop()
            playbackEngine.reset()
        }
        hardwarePlaybackFormat = nil
    }

    // MARK: - Message Observation

    private func observeMessages() {
        liveSession.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if !connected && self.isSessionRunning {
                    self.cleanupSession()
                }
            }
            .store(in: &cancellables)

        liveSession.serverMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleServerMessage(message)
            }
            .store(in: &cancellables)

        liveSession.connectionErrorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self else { return }
                let message = self.sanitizedConnectionError(error)
                print("[GeminiLiveManager] Connection error: \(message)")
                self.lastError = message
                self.cleanupSession()
            }
            .store(in: &cancellables)
    }

    private func handleServerMessage(_ message: GeminiLiveServerMessage) {
        switch message {
        case .setupComplete:
            print("[GeminiLiveManager] Setup complete")
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            isWaitingForSetupComplete = false
            isSessionRunning = true
            isMicMuted = false
            startAudioLevelMonitoring()
            do {
                try startMicrophoneCapture()
            } catch {
                print("[GeminiLiveManager] Failed to start capture engine: \(error)")
                lastError = error.localizedDescription
            }
            startScreenCaptureLoop()

        case .inputTranscription(let text, let finished):
            if finished {
                inputTranscript = text
            } else {
                inputTranscript += text
            }

        case .outputTranscription(let text, let finished):
            if finished {
                outputTranscript = text
            } else {
                outputTranscript += text
            }

        case .serverContent(let modelTurn, let turnComplete, let interrupted, _):
            if interrupted {
                playerNode.stop()
                if playbackEngine.isRunning { playerNode.play() }
                liveSession.sendAudioStreamEnd()
            }

            if let turn = modelTurn, let parts = turn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let audioData = part["audioData"] as? Data {
                        scheduleAudioPlayback(audioData)
                    }
                    if let functionCall = part["functionCall"] as? [String: Any] {
                        handleFunctionCall(functionCall)
                    }
                }
            }

            if turnComplete {
                inputTranscript = ""
            }

        case .toolCall(let functionCalls):
            for fc in functionCalls {
                handleFunctionCall(fc)
            }

        case .toolCallCancellation(let ids):
            print("[GeminiLiveManager] Tool calls cancelled: \(ids)")

        case .error(let message):
            if isSessionRunning {
                print("[GeminiLiveManager] API warning during active session: \(message)")
            } else {
                lastError = message
                print("[GeminiLiveManager] API error: \(message)")
            }
        }
    }

    private func handleFunctionCall(_ functionCall: [String: Any]) {
        guard let name = functionCall["name"] as? String else { return }
        print("[GeminiLiveManager] Function call: \(name)")

        var response: [String: Any] = [
            "name": name,
            "response": ["result": "Not yet implemented on Sapphire Live"]
        ]
        if let id = functionCall["id"] as? String {
            response["id"] = id
        }
        liveSession.sendToolResponse(functionResponses: [response])
    }

    // MARK: - Audio Capture

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pcmData = convertSampleBufferToGeminiPCM(sampleBuffer) else { return }
        let level = Self.peakLevel(from: pcmData)
        Task { @MainActor in
            guard !self.isMicMuted, self.isSessionRunning else { return }
            self.currentAudioLevel = level
            self.sendAudioChunks(pcmData)
        }
    }

    nonisolated private func convertSampleBufferToGeminiPCM(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        var asbd = asbdPointer.pointee
        guard asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else { return nil }
        guard let sourceFormat = AVAudioFormat(streamDescription: &asbd),
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
              ) else {
            return nil
        }

        let needsNewConverter = micSourceFormat?.sampleRate != sourceFormat.sampleRate
            || micSourceFormat?.channelCount != sourceFormat.channelCount
            || micConverter == nil

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let dataPointer, length > 0 else {
            return nil
        }

        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let frameCount = AVAudioFrameCount(length / bytesPerFrame)
        guard frameCount > 0,
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            return nil
        }
        sourceBuffer.frameLength = frameCount
        if let audioBuffer = sourceBuffer.audioBufferList.pointee.mBuffers.mData {
            memcpy(audioBuffer, dataPointer, length)
        } else {
            return nil
        }

        let converter: AVAudioConverter
        if !needsNewConverter, let existing = micConverter {
            converter = existing
        } else if let created = AVAudioConverter(from: sourceFormat, to: targetFormat) {
            micConverter = created
            micSourceFormat = sourceFormat
            converter = created
        } else {
            return nil
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let destFrames = AVAudioFrameCount(Double(frameCount) * ratio) + 16
        guard let destBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: destFrames) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: destBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return sourceBuffer
        }
        guard error == nil, destBuffer.frameLength > 0 else { return nil }
        return Self.int16PCMData(from: destBuffer)
    }

    private func sendAudioChunks(_ pcmData: Data) {
        let bytesPerFrame = MemoryLayout<Int16>.size
        let maxChunkBytes = maxAudioFramesPerBuffer * bytesPerFrame
        guard maxChunkBytes > 0 else { return }

        var offset = 0
        while offset < pcmData.count {
            let end = min(offset + maxChunkBytes, pcmData.count)
            let chunk = pcmData.subdata(in: offset..<end)
            liveSession.sendRealtimeAudio(chunk)
            offset = end
        }
    }

    nonisolated private static func int16PCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              let channelData = buffer.int16ChannelData else {
            return nil
        }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData.pointee, count: byteCount)
    }

    nonisolated private static func peakLevel(from pcmData: Data) -> Float {
        var maxVal: Int16 = 0
        pcmData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                maxVal = max(maxVal, abs(sample))
            }
        }
        return min(Float(maxVal) / 32768.0, 1.0)
    }

    // MARK: - Audio Playback

    private func scheduleAudioPlayback(_ audioData: Data) {
        guard !audioData.isEmpty else { return }
        do {
            try ensurePlaybackEngine()
        } catch {
            print("[GeminiLiveManager] Playback engine failed: \(error)")
            return
        }
        guard let sourceFormat = geminiPlaybackFormat,
              let destinationFormat = hardwarePlaybackFormat else { return }

        let bytesPerFrame = MemoryLayout<Int16>.size
        let totalFrames = audioData.count / bytesPerFrame
        guard totalFrames > 0 else { return }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(totalFrames)),
              let floatChannel = sourceBuffer.floatChannelData?.pointee else { return }
        sourceBuffer.frameLength = AVAudioFrameCount(totalFrames)
        audioData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for index in 0..<totalFrames {
                floatChannel[index] = Float(base[index].littleEndian) / 32768.0
            }
        }

        let ratio = destinationFormat.sampleRate / sourceFormat.sampleRate
        let destinationFrames = AVAudioFrameCount(Double(totalFrames) * ratio) + 32
        guard let destinationBuffer = AVAudioPCMBuffer(pcmFormat: destinationFormat, frameCapacity: destinationFrames),
              let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: destinationBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return sourceBuffer
        }

        guard error == nil, destinationBuffer.frameLength > 0 else { return }
        playerNode.scheduleBuffer(destinationBuffer)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    // MARK: - Screen

    private func startScreenCaptureLoop() {
        screenCaptureTask?.cancel()
        screenCaptureTask = Task { [weak self] in
            await self?.sendLiveScreenFrame()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.liveFrameIntervalNanoseconds ?? 1_000_000_000)
                guard let self, !Task.isCancelled, self.isSessionRunning else { break }
                await self.sendLiveScreenFrame()
            }
        }
    }

    private func sendLiveScreenFrame() async {
        guard isSessionRunning, let filter = currentScreenFilter else { return }
        guard let jpeg = await captureLiveJPEG(filter: filter) else { return }
        liveSession.sendRealtimeVideo(jpeg)
    }

    private func captureLiveJPEG(filter: SCContentFilter) async -> Data? {
        let config = SCStreamConfiguration()
        let maxEdge: CGFloat = 1280
        var width = 1280
        var height = 720

        let contentRect = filter.contentRect
        let pixelScale = CGFloat(filter.pointPixelScale)
        if contentRect.width > 1, contentRect.height > 1 {
            width = max(2, Int(contentRect.width * pixelScale))
            height = max(2, Int(contentRect.height * pixelScale))
        } else if let screen = NSScreen.main {
            let scale = screen.backingScaleFactor
            width = max(2, Int(screen.frame.width * scale))
            height = max(2, Int(screen.frame.height * scale))
        }

        let longEdge = CGFloat(max(width, height))
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            width = max(2, Int(CGFloat(width) * scale))
            height = max(2, Int(CGFloat(height) * scale))
        }

        config.width = width
        config.height = height
        config.showsCursor = false
        config.capturesAudio = false

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            return nsImage.jpegData(maxPixel: maxEdge, quality: 0.55)
        } catch {
            print("[GeminiLiveManager] Screen capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isMicMuted else { return }
                if self.currentAudioLevel > 0 {
                    self.currentAudioLevel = max(0, self.currentAudioLevel - 0.02)
                }
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        currentAudioLevel = 0
    }

    // MARK: - Session Management

    func startSession(with filter: SCContentFilter) {
        let config = GeminiLiveConfiguration()
        let rawGeminiKey = APIKeyManager.shared.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !config.apiKey.isEmpty else {
            if !rawGeminiKey.isEmpty {
                lastError = misplacedGeminiKeyMessage(for: rawGeminiKey)
            } else {
                lastError = "Add a Google Gemini API key in Settings → Intelligence (keys start with AIza)."
            }
            print("[GeminiLiveManager] \(lastError ?? "API key not configured")")
            return
        }

        currentScreenFilter = filter
        isMicMuted = true
        currentAudioLevel = 0
        inputTranscript = ""
        outputTranscript = ""
        lastError = nil

        Task { [weak self] in
            guard let self else { return }

            let granted = await self.requestMicrophoneAccess()
            guard granted else {
                self.lastError = "Microphone access is required for Gemini Live."
                return
            }

            let genCfg: [String: Any] = [
                "temperature": 1.0,
                "topP": 0.95,
                "topK": 64,
                "maxOutputTokens": 8192,
                "responseModalities": ["AUDIO"],
                "mediaResolution": "MEDIA_RESOLUTION_MEDIUM"
            ]

            self.liveSession.connect(
                apiKey: config.apiKey,
                model: config.model,
                systemInstruction: config.systemInstruction,
                generationConfig: genCfg,
                voiceName: config.voiceName
            )
            self.isWaitingForSetupComplete = true

            self.setupTimeoutTask?.cancel()
            self.setupTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, self.isWaitingForSetupComplete else { return }
                print("[GeminiLiveManager] Setup timed out")
                self.lastError = GeminiLiveError.setupTimeout.localizedDescription
                self.cleanupSession()
            }
        }
    }

    func toggleMicrophone() {
        isMicMuted.toggle()
        if isMicMuted {
            liveSession.sendAudioStreamEnd()
            currentAudioLevel = 0
        }
    }

    func signalEndOfUserTurn() {
        guard isSessionRunning else { return }
        liveSession.sendClientContent(turnComplete: true)
    }

    func stopSession() {
        guard isSessionRunning || liveSession.isConnected || isWaitingForSetupComplete else { return }
        cleanupSession()
    }

    private func cleanupSession() {
        let wasRunning = isSessionRunning

        setupTimeoutTask?.cancel()
        setupTimeoutTask = nil
        stopAudioLevelMonitoring()
        stopEngines()
        liveSession.disconnect()

        isSessionRunning = false
        isMicMuted = true
        currentAudioLevel = 0
        isWaitingForSetupComplete = false
        currentScreenFilter = nil

        if wasRunning {
            sessionDidEndPublisher.send()
        }
    }

    deinit {
        audioLevelTimer?.invalidate()
        setupTimeoutTask?.cancel()
        screenCaptureTask?.cancel()
        if captureSession.isRunning { captureSession.stopRunning() }
        playerNode.stop()
        if playbackEngine.isRunning { playbackEngine.stop() }
    }

    private func sanitizedConnectionError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
            let rawKey = APIKeyManager.shared.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawKey.isEmpty, !APIKeyManager.isValidGoogleGeminiAPIKey(rawKey) {
                return misplacedGeminiKeyMessage(for: rawKey)
            }
            return "Could not connect to Gemini Live. Check your Google API key and network."
        }
        return error.localizedDescription
    }

    private func misplacedGeminiKeyMessage(for key: String) -> String {
        if key.hasPrefix("sk-hc-") {
            return "Gemini Live needs a Google API key (AIza…). Your Hack Club key belongs under Hack Club in Settings."
        }
        if key.hasPrefix("sk-or-") {
            return "Gemini Live needs a Google API key (AIza…). OpenRouter keys won't work here."
        }
        if key.hasPrefix("sk-") {
            return "Gemini Live needs a Google API key from Google AI Studio (starts with AIza)."
        }
        return "Gemini Live needs a valid Google Gemini API key (starts with AIza)."
    }
}