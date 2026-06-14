import Foundation
import Combine
import AVFoundation
import ScreenCaptureKit

@MainActor
class GeminiLiveManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var isMicMuted = true
    @Published var currentAudioLevel: Float = 0.0

    let sessionDidEndPublisher = PassthroughSubject<Void, Never>()

    private let liveSession = GeminiLiveSession()
    private var cancellables = Set<AnyCancellable>()

    private var captureEngine: AVAudioEngine?
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioLevelTimer: Timer?

    private var isWaitingForSetupComplete = false
    private var currentScreenFilter: SCContentFilter?
    private var isInterrupted = false
    private let inputSampleRate: Double = 16000.0
    private let outputSampleRate: Double = 24000.0

    override init() {
        super.init()
        setupPlaybackEngine()
        observeMessages()
    }

    // MARK: - Playback Engine

    private func setupPlaybackEngine() {
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: outputSampleRate, channels: 1)!
        playbackEngine.attach(playerNode)
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: outputFormat)
        playbackEngine.prepare()
    }

    private func startPlaybackEngine() {
        guard !playbackEngine.isRunning else { return }
        do {
            try playbackEngine.start()
        } catch {
            print("[GeminiLiveManager] Failed to start playback engine: \(error)")
        }
    }

    private func stopPlaybackEngine() {
        playerNode.stop()
        playbackEngine.stop()
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
                print("[GeminiLiveManager] Connection error: \(error)")
                self?.cleanupSession()
            }
            .store(in: &cancellables)
    }

    private func handleServerMessage(_ message: GeminiLiveServerMessage) {
        switch message {
        case .setupComplete:
            print("[GeminiLiveManager] Setup complete")
            isWaitingForSetupComplete = false
            isSessionRunning = true
            startAudioCapture()
            startAudioLevelMonitoring()

        case .serverContent(let modelTurn, let turnComplete, let interrupted):
            if interrupted {
                isInterrupted = true
                playerNode.stop()
            }

            if let turn = modelTurn, let parts = turn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let text = part["text"] as? String {
                        print("[GeminiLiveManager] Text: \(text)")
                    }
                    if let audioData = part["audioData"] as? Data {
                        scheduleAudioPlayback(audioData)
                    }
                    if let functionCall = part["functionCall"] as? [String: Any] {
                        handleFunctionCall(functionCall)
                    }
                }
            }

            if turnComplete {
                isInterrupted = false
            }

        case .toolCall(let functionCalls):
            for fc in functionCalls {
                handleFunctionCall(fc)
            }

        case .toolCallCancellation(let ids):
            print("[GeminiLiveManager] Tool calls cancelled: \(ids)")
        }
    }

    private func handleFunctionCall(_ functionCall: [String: Any]) {
        guard let name = functionCall["name"] as? String else { return }
        print("[GeminiLiveManager] Function call: \(name)")
        let response: [String: Any] = ["name": name, "response": ["result": "Not yet implemented"]]
        liveSession.sendToolResponse(functionResponses: [response])
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        guard !isMicMuted else { return }

        stopAudioCapture()

        let engine = AVAudioEngine()
        captureEngine = engine

        let inputNode = engine.inputNode
        engine.prepare()

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            print("[GeminiLiveManager] Invalid input format: \(hardwareFormat)")
            return
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("[GeminiLiveManager] Failed to create Int16 target format")
            return
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            print("[GeminiLiveManager] Failed to create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * inputSampleRate / hardwareFormat.sampleRate
            ) + 64
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            var consumedInput = false
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if consumedInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumedInput = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard error == nil, convertedBuffer.frameLength > 0,
                  let pcmData = Self.int16PCMData(from: convertedBuffer) else {
                return
            }

            let level = Self.peakLevel(from: pcmData)
            Task { @MainActor in
                self.currentAudioLevel = level
                self.liveSession.sendRealtimeAudio(pcmData)
            }
        }

        do {
            try engine.start()
        } catch {
            print("[GeminiLiveManager] Failed to start capture engine: \(error)")
            stopAudioCapture()
        }
    }

    private static func int16PCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.format.commonFormat == .pcmFormatInt16,
              let channelData = buffer.int16ChannelData else {
            return nil
        }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData.pointee, count: byteCount)
    }

    private static func peakLevel(from pcmData: Data) -> Float {
        var maxVal: Int16 = 0
        pcmData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                maxVal = max(maxVal, abs(sample))
            }
        }
        return min(Float(maxVal) / 32768.0, 1.0)
    }

    private func stopAudioCapture() {
        guard let engine = captureEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        captureEngine = nil
    }

    // MARK: - Audio Playback

    private func scheduleAudioPlayback(_ audioData: Data) {
        guard !audioData.isEmpty else { return }

        startPlaybackEngine()

        let frameCount = audioData.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: outputSampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let floatChannel = buffer.floatChannelData?.pointee else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        audioData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<frameCount {
                floatChannel[index] = Float(samples[index]) / 32768.0
            }
        }

        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isMicMuted else { return }
                if self.currentAudioLevel > 0 {
                    self.currentAudioLevel = max(0, self.currentAudioLevel - 0.01)
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
        guard !config.apiKey.isEmpty else {
            print("[GeminiLiveManager] API key not configured")
            return
        }

        currentScreenFilter = filter
        isMicMuted = false
        currentAudioLevel = 0

        let genCfg: [String: Any] = [
            "temperature": 1.0,
            "topP": 0.95,
            "topK": 64,
            "maxOutputTokens": 8192,
            "responseModalities": ["AUDIO"]
        ]

        liveSession.connect(
            apiKey: config.apiKey,
            model: config.model,
            systemInstruction: config.systemInstruction,
            generationConfig: genCfg
        )
        isWaitingForSetupComplete = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if self?.isWaitingForSetupComplete == true {
                print("[GeminiLiveManager] Setup timed out")
                self?.cleanupSession()
            }
        }
    }

    public func signalEndOfUserTurn() {
        guard isSessionRunning else { return }
        liveSession.sendClientContent(turns: [], turnComplete: true)
    }

    func stopSession() {
        guard isSessionRunning || liveSession.isConnected else { return }
        cleanupSession()
    }

    private func cleanupSession() {
        let wasRunning = isSessionRunning

        stopAudioCapture()
        stopPlaybackEngine()
        stopAudioLevelMonitoring()
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
        audioLevelTimer = nil
        if let engine = captureEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        playerNode.stop()
        playbackEngine.stop()
        liveSession.disconnect()
    }
}
