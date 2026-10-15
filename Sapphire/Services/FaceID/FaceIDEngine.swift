//
//  FaceIDEngine.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-22

import Vision
import CoreML
import Combine
import SwiftUI
import AVFoundation
import Accelerate
import CoreImage
import CryptoKit
import Darwin
import IOKit

// MARK: - FACE ID TUNING CONFIGURATION

enum FaceIDConfig {
    static var antiSpoofVisionBoxScale: CGFloat = 1.256
    static var antiSpoofVisionBoxShiftUp: CGFloat = 0.114

    static var livenessWindow: Int = 10
    static var livenessFallbackLogitThreshold: Float = -0.42
    static var requiredConsecutiveFrames: Int = 3
    static var unlockIdentityThreshold: Float = 0.48

    static var sensorWarmupFramesToDrop: Int = 2

    static var enableDebugImageCapture: Bool = false
}

// MARK: - App State & Enums

enum RegistrationStep: Equatable {
    case scanning, finalizing
    var instruction: String {
        switch self {
        case .scanning: return "Look straight at the camera to begin."
        case .finalizing: return "Securing your face profile..."
        }
    }
}

enum CameraState: Equatable {
    case idle, registering(RegistrationStep), registeredAndIdle, detecting, recognized, authenticating, needsReenrollment
}

enum PoseCategory {
    case center, turn, pitch, tilt, distance
}

enum FacePoseBucket: String, CaseIterable {
    case center, left, right, up, down, tiltLeft, tiltRight, closer, farther

    var category: PoseCategory {
        switch self {
        case .center: return .center
        case .left, .right: return .turn
        case .up, .down: return .pitch
        case .tiltLeft, .tiltRight: return .tilt
        case .closer, .farther: return .distance
        }
    }

    var hint: String {
        switch self {
        case .center: return "Center your face"
        case .left: return "Slowly turn left"
        case .right: return "Slowly turn right"
        case .up: return "Look slightly up"
        case .down: return "Look slightly down"
        case .tiltLeft: return "Tilt head left"
        case .tiltRight: return "Tilt head right"
        case .closer: return "Move closer"
        case .farther: return "Move further back"
        }
    }

    func matches(yaw: Double, pitch: Double, roll: Double, faceWidth: CGFloat) -> Bool {
        switch self {
        case .center: return abs(yaw) < 0.15 && abs(roll) < 0.25 && abs(pitch) < 0.25 && faceWidth >= 0.10 && faceWidth <= 0.34
        case .left: return yaw < -0.10
        case .right: return yaw > 0.10
        case .up: return pitch > 0.08
        case .down: return pitch < -0.08
        case .tiltLeft: return roll < -0.12
        case .tiltRight: return roll > 0.12
        case .closer: return faceWidth > 0.30
        case .farther: return faceWidth < 0.18 && faceWidth > 0.05
        }
    }
}

// MARK: - Raw Disk Debugger (Thread-Safe 224x224 Snapshotter)

struct FaceIDDebugger {
    static let debugFolder: URL = {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = downloads.appendingPathComponent("Sapphire_Debug_Captures")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    static func saveCroppedInputBuffer(pixelBuffer: CVPixelBuffer, name: String) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let cgImage = context.makeImage() else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        DispatchQueue.global(qos: .utility).async {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) else { return }
            let fileURL = debugFolder.appendingPathComponent("\(name)_224x224_CROP.jpg")
            try? jpegData.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Anti-Spoof Result & Quality Gate

enum FaceIDTiming {
    static func mark(_ event: String, since start: Date?) {
        guard let start else { return }
        print(String(format: "[FaceID timing] %@ +%.0f ms", event, Date().timeIntervalSince(start) * 1000))
    }
}

struct AntiSpoofResult {
    let isReal: Bool
    let rawScore: Float
    let smoothScore: Float
    let logit: Float

    var scoreLine: String {
        let score = smoothScore.isFinite ? min(max(smoothScore, 0), 1) : 1
        if isReal {
            let pct = Int((score * 100).rounded())
            return "REAL: \(pct)%"
        } else {
            let pct = Int(((1.0 - score) * 100).rounded())
            return "SPOOF: \(pct)%"
        }
    }
}

enum FaceIDSecurityEvent {
    case spoofLocked
    case mismatchTimeout
}

enum AntiSpoofQualityGate {
    static let minFacePixels = 64
    static let edgeMarginPixels = 5

    static func passes(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) -> Bool {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bb = observation.boundingBox

        let faceW = Int(bb.width * CGFloat(w))
        let faceH = Int(bb.height * CGFloat(h))
        guard min(faceW, faceH) >= minFacePixels else { return false }

        let left = Int(bb.minX * CGFloat(w))
        let right = Int(bb.maxX * CGFloat(w))
        let top = Int((1.0 - bb.maxY) * CGFloat(h))
        let bottom = Int((1.0 - bb.minY) * CGFloat(h))

        guard left >= edgeMarginPixels,
              top >= edgeMarginPixels,
              right <= w - edgeMarginPixels,
              bottom <= h - edgeMarginPixels else { return false }

        if let quality = observation.faceCaptureQuality, quality < 0.10 { return false }
        return true
    }
}

// MARK: - Camera & Face ID Controller

final class CameraController: NSObject, ObservableObject, Identifiable, AVCaptureVideoDataOutputSampleBufferDelegate {
    public let id = UUID()
    @Published var appState: CameraState = .idle
    @Published var userInstruction: String = "Press 'Register' to begin."
    @Published var faceIsRecognized: Bool = false
    @Published var smoothedBoundingBox: CGRect?
    @Published var registrationProgress: Double = 0.0
    @Published var holdProgress: Double = 0.0
    @Published var registrationPoseCaptured: Set<String> = []

    let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var faceIDDevice: AVCaptureDevice?
    private var currentFaceIDRotationAngle: CGFloat = 0

    private enum DeviceTransportType {
        static let builtIn: Int32 = 1
        static let airPlay: Int32 = 6
        static let virtual: Int32 = 7
    }

    private static let sessionQueueKey = DispatchSpecificKey<Bool>()
    private static let sharedSessionQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.sapphire.faceID.sessionQueue", qos: .userInteractive)
        queue.setSpecific(key: CameraController.sessionQueueKey, value: true)
        return queue
    }()
    private let sessionQueue = CameraController.sharedSessionQueue
    private var isOnSessionQueue: Bool { DispatchQueue.getSpecific(key: CameraController.sessionQueueKey) == true }

    private let visionQueue = DispatchQueue(label: "com.sapphire.visionQueue", qos: .userInitiated)

    private var isAuthenticating = false
    private var isRegistrationMode = false
    private var isProcessingFrame = false
    private var profileForRegistration: String?

    private var embeddingWindow: [FaceAuthEmbedding] = []
    private var poseBucketSamples: [FacePoseBucket: [[Float]]] = [:]

    private var accumulatedEmbeddings: [[Float]] = []
    private let framesPerPose = 4

    private let poseOrder: [FacePoseBucket] = [.center, .left, .right]

    private func targetCount(for bucket: FacePoseBucket) -> Int {
        switch bucket {
        case .center: return 2
        case .left, .right: return 1
        default: return 1
        }
    }

    private var verifiedConsecutiveFrames = 0
    private let embeddingWindowSize = 1

    private var sessionStartDate: Date?
    private var didLogFirstFrame = false
    private var didLogFirstFace = false
    private var lastLogTime: TimeInterval = 0
    private var frameCounter: Int = 0

    private var livenessHistory: [Float] = []
    private var clearSpoofStart: Date?
    private var mismatchStart: Date?
    private var lastLivenessResult: AntiSpoofResult?
    var onSecurityEvent: ((FaceIDSecurityEvent) -> Void)?

    private lazy var faceRectanglesRequest = VNDetectFaceRectanglesRequest()
    private var lastFaceSeenAt: CFTimeInterval = 0
    private var lastIdleProbeAt: CFTimeInterval = 0

    private enum IdleSampling {
        static let faceGrace: CFTimeInterval = 1.5
        static let probeInterval: CFTimeInterval = 0.2
        static let deepIdleAfter: CFTimeInterval = 15
        static let deepIdleProbeInterval: CFTimeInterval = 0.5
    }

    private lazy var faceLandmarksRequest: VNDetectFaceLandmarksRequest = {
        let r = VNDetectFaceLandmarksRequest()
        r.revision = VNDetectFaceLandmarksRequestRevision3
        return r
    }()

    override init() {
        super.init()
        setupCaptureSession()
    }

    private var hasCameraInput = false

    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.configureSessionIfNeeded()
        }
    }

    private var cameraAttempts = 0

    private func preferredCamera() -> AVCaptureDevice? {
        if let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ??
                         AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) {
            return builtIn
        }
        let lidOpenOnLaptop = Self.isClamshellClosed == false
        return (lidOpenOnLaptop && cameraAttempts < 6) ? nil : AVCaptureDevice.default(for: .video)
    }

    private static var isClamshellClosed: Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    private func configureSessionIfNeeded() {
        guard !hasCameraInput else { return }

        guard let device = preferredCamera(),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .hd1280x720

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            hasCameraInput = true
        }

        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)

        if captureSession.canAddOutput(videoDataOutput) { captureSession.addOutput(videoDataOutput) }

        if let conn = videoDataOutput.connection(with: .video) {
            if conn.isVideoMirroringSupported {
                if conn.automaticallyAdjustsVideoMirroring { conn.automaticallyAdjustsVideoMirroring = false }
                conn.isVideoMirrored = true
            }
        }

        faceIDDevice = device
        setupRotationCoordinatorIfNeeded(for: device)
    }

    private func setupRotationCoordinatorIfNeeded(for device: AVCaptureDevice) {
        rotationObservation = nil
        rotationCoordinator = nil

        let transport = device.transportType
        guard transport != DeviceTransportType.builtIn,
              transport != DeviceTransportType.airPlay,
              transport != DeviceTransportType.virtual else {
            return
        }

        Task { @MainActor in
            guard self.faceIDDevice === device else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            self.rotationCoordinator = coordinator
            self.rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
                let autoAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                Task { @MainActor in
                    self?.applyFaceIDRotation(autoAngle: autoAngle)
                }
            }
        }
    }

    private func applyFaceIDRotation(autoAngle: CGFloat) {
        guard let device = faceIDDevice else { return }

        let angle: CGFloat
        let transport = device.transportType
        if transport != DeviceTransportType.builtIn,
           transport != DeviceTransportType.airPlay,
           transport != DeviceTransportType.virtual,
           let manual = SettingsModel.shared.current.mirrorRotationMode.angle {
            angle = manual
        } else {
            angle = autoAngle
        }

        currentFaceIDRotationAngle = angle
        guard let conn = videoDataOutput.connection(with: .video),
              conn.isVideoRotationAngleSupported(angle) else { return }
        conn.videoRotationAngle = angle
    }

    func startCameraSession() {
        sessionQueue.async {
            self.ensureCameraAccessThenStart()
        }
    }

    private func ensureCameraAccessThenStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartIfPossible()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                self.sessionQueue.async {
                    if granted {
                        self.configureAndStartIfPossible()
                    } else {
                        self.notifyCameraUnavailable()
                    }
                }
            }
        case .denied, .restricted:
            notifyCameraUnavailable()
        @unknown default:
            break
        }
    }

    private func configureAndStartIfPossible() {
        configureSessionIfNeeded()
        guard hasCameraInput else {
            cameraAttempts += 1
            guard cameraAttempts < 20, isAuthenticating || isRegistrationMode else { return }
            sessionQueue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.configureAndStartIfPossible() }
            return
        }
        guard !captureSession.isRunning else { return }
        captureSession.startRunning()
        FaceIDTiming.mark("camera running", since: sessionStartDate)
    }

    private func notifyCameraUnavailable() {
        DispatchQueue.main.async {
            self.appState = .idle
            self.userInstruction = "Camera access is required for Face ID. Enable it in System Settings → Privacy & Security → Camera."
        }
    }

    func stopCameraSession() {
        sessionQueue.async {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
        }
    }

    deinit {
        if captureSession.isRunning {
            if isOnSessionQueue {
                captureSession.stopRunning()
            } else {
                sessionQueue.sync {
                    if self.captureSession.isRunning { self.captureSession.stopRunning() }
                }
            }
        }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer?

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existing = previewLayer, existing.session === captureSession {
            return existing
        }

        var layer: AVCaptureVideoPreviewLayer?
        sessionQueue.sync {
            let newLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            newLayer.videoGravity = .resizeAspectFill
            self.applyMirroringLocked(to: newLayer)
            self.applyRotationLocked(to: newLayer)
            layer = newLayer
        }
        previewLayer = layer
        return layer ?? AVCaptureVideoPreviewLayer()
    }

    func applyMirroring(to previewLayer: AVCaptureVideoPreviewLayer) {
        sessionQueue.sync {
            applyMirroringLocked(to: previewLayer)
        }
    }

    func applyRotation(to previewLayer: AVCaptureVideoPreviewLayer) {
        sessionQueue.sync {
            applyRotationLocked(to: previewLayer)
        }
    }

    private func applyMirroringLocked(to previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        if connection.automaticallyAdjustsVideoMirroring { connection.automaticallyAdjustsVideoMirroring = false }
        connection.isVideoMirrored = true
    }

    private func applyRotationLocked(to previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(currentFaceIDRotationAngle) else { return }
        connection.videoRotationAngle = currentFaceIDRotationAngle
    }

    func cleanupFaceIDResources() {
        isAuthenticating = false
        isRegistrationMode = false
        rotationObservation = nil
        rotationCoordinator = nil
        faceIDDevice = nil
        stopCameraSession()
        FaceIDDataStore.shared.teardownBuffers()
        FaceIDModelManager.shared.sessionEnded()
    }

    func startAuthentication() {
        isAuthenticating = true
        isRegistrationMode = false
        verifiedConsecutiveFrames = 0
        embeddingWindow.removeAll()
        livenessHistory.removeAll()
        frameCounter = 0
        lastLivenessResult = nil
        clearSpoofStart = nil
        mismatchStart = nil
        sessionStartDate = Date()
        didLogFirstFrame = false
        didLogFirstFace = false
        lastLogTime = 0
        lastFaceSeenAt = CACurrentMediaTime()

        FaceIDModelManager.shared.prewarm()

        DispatchQueue.main.async {
            self.appState = .authenticating
            self.userInstruction = "Looking for your face…"
        }
        startCameraSession()
    }

    func resumeAfterDisplayWake() {
        guard isAuthenticating else { return }
        sessionStartDate = Date()
        didLogFirstFrame = false
        didLogFirstFace = false
        lastFaceSeenAt = CACurrentMediaTime()
        FaceIDModelManager.shared.prewarm()
        startCameraSession()
    }

    func startRegistration(forProfile name: String) {
        isRegistrationMode = true
        isAuthenticating = false
        profileForRegistration = name
        poseBucketSamples.removeAll()
        accumulatedEmbeddings.removeAll()
        registrationPoseCaptured.removeAll()
        livenessHistory.removeAll()
        frameCounter = 0
        sessionStartDate = Date()
        lastLogTime = 0

        FaceIDModelManager.shared.prewarm()

        DispatchQueue.main.async {
            self.registrationProgress = 0.0
            self.holdProgress = 0.0
            self.appState = .registering(.scanning)
            self.userInstruction = FacePoseBucket.center.hint
        }
        startCameraSession()
    }

    func cancelCurrentOperation() {
        isAuthenticating = false
        isRegistrationMode = false
        sessionQueue.async {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
            FaceIDDataStore.shared.teardownBuffers()
            DispatchQueue.main.async { FaceIDModelManager.shared.sessionEnded() }
        }
        DispatchQueue.main.async {
            self.holdProgress = 0.0
            self.appState = .idle
        }
    }

    private func finalizeRegistration() {
        guard let profile = profileForRegistration else { return }
        isRegistrationMode = false
        DispatchQueue.main.async {
            self.holdProgress = 0.0
            self.appState = .registering(.finalizing)
            self.userInstruction = "Securing face profile..."
        }

        let allPrints = poseBucketSamples.values.flatMap { $0 }
        FaceIDDataStore.shared.register(faceprints: allPrints, forProfile: profile)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.appState = .registeredAndIdle
            self.userInstruction = "Registration Complete!"
            self.cleanupFaceIDResources()
            AuthenticationManager.shared.fetchRegisteredFaces()
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAuthenticating || isRegistrationMode, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if isProcessingFrame { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        frameCounter += 1
        if !didLogFirstFrame { didLogFirstFrame = true; FaceIDTiming.mark("first frame", since: sessionStartDate) }

        guard frameCounter > FaceIDConfig.sensorWarmupFramesToDrop else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        if !isRegistrationMode {
            let now = CACurrentMediaTime()
            let idleFor = now - lastFaceSeenAt
            if idleFor > IdleSampling.faceGrace {
                let interval = idleFor > IdleSampling.deepIdleAfter
                    ? IdleSampling.deepIdleProbeInterval
                    : IdleSampling.probeInterval
                guard now - lastIdleProbeAt >= interval else { return }
                lastIdleProbeAt = now
                try? handler.perform([faceRectanglesRequest])
                guard faceRectanglesRequest.results?.isEmpty == false else { return }
            }
            lastFaceSeenAt = now
        }

        try? handler.perform([faceLandmarksRequest])

        guard let obs = faceLandmarksRequest.results?.first else {
            DispatchQueue.main.async {
                self.smoothedBoundingBox = nil
                if self.isRegistrationMode {
                    self.userInstruction = "Position your face in the camera view."
                    if !self.accumulatedEmbeddings.isEmpty { self.accumulatedEmbeddings.removeLast() }
                }
            }
            return
        }

        if let quality = obs.faceCaptureQuality, quality < 0.10 { return }
        if !didLogFirstFace { didLogFirstFace = true; FaceIDTiming.mark("first face", since: sessionStartDate) }
        DispatchQueue.main.async { self.smoothedBoundingBox = obs.boundingBox }

        if isRegistrationMode {
            handleRegistration(observation: obs, pixelBuffer: pixelBuffer)
        } else if isAuthenticating {
            handleAuthentication(observation: obs, pixelBuffer: pixelBuffer)
        }
    }

    private func getPitch(from observation: VNFaceObservation) -> Double {
        let visionPitch = observation.pitch?.doubleValue ?? 0
        if abs(visionPitch) > 0.08 { return visionPitch }

        guard let lm = observation.landmarks,
              let leftEye = lm.leftEye,
              let rightEye = lm.rightEye,
              let nose = lm.nose,
              let lips = lm.outerLips else { return 0 }

        let avgY = { (reg: VNFaceLandmarkRegion2D) -> CGFloat in
            let pts = reg.normalizedPoints
            guard !pts.isEmpty else { return 0 }
            return pts.reduce(0) { $0 + $1.y } / CGFloat(pts.count)
        }

        let eyeMidY = (avgY(leftEye) + avgY(rightEye)) / 2.0
        let noseY = avgY(nose)
        let mouthY = avgY(lips)

        let eyeToNose = eyeMidY - noseY
        let noseToMouth = noseY - mouthY

        guard noseToMouth > 0 else { return 0 }
        let ratio = eyeToNose / noseToMouth

        if ratio < 0.85 { return 0.15 }
        if ratio > 1.30 { return -0.15 }
        return 0
    }

    // MARK: - Registration Flow

    private func handleRegistration(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let activeOrder = poseOrder

        guard let currentTarget = activeOrder.first(where: { (poseBucketSamples[$0]?.count ?? 0) < targetCount(for: $0) }) else {
            checkRegistrationComplete()
            return
        }

        let yaw = observation.yaw?.doubleValue ?? 0
        let pitch = getPitch(from: observation)
        let roll = observation.roll?.doubleValue ?? 0
        let faceW = observation.boundingBox.width

        var actualPose: FacePoseBucket? = nil
        if currentTarget.matches(yaw: yaw, pitch: pitch, roll: roll, faceWidth: faceW) {
            actualPose = currentTarget
        } else {
            for bucket in activeOrder where bucket.category == currentTarget.category {
                if bucket.matches(yaw: yaw, pitch: pitch, roll: roll, faceWidth: faceW) {
                    actualPose = bucket
                    break
                }
            }
        }

        if let pose = actualPose {
            let capturedCount = poseBucketSamples[pose]?.count ?? 0
            if capturedCount < targetCount(for: pose) {
                guard AntiSpoofQualityGate.passes(observation: observation, pixelBuffer: pixelBuffer) else { return }

                let debugTag = FaceIDConfig.enableDebugImageCapture ? "enroll_f\(frameCounter)" : nil
                if false && SettingsModel.shared.current.faceIDAntiSpoofEnabled,
                   let spoof = FaceIDModelManager.shared.evaluateAntiSpoof(
                    pixelBuffer: pixelBuffer,
                    observation: observation,
                    debugTag: debugTag
                ) {
                    if spoof.logit <= FaceIDModelManager.shared.livenessLogitThreshold {
                        DispatchQueue.main.async { self.userInstruction = "Live face required — photo detected." }
                        return
                    }
                }

                guard let embedding = FaceIDDataStore.shared.generateEnrollmentEmbedding(
                    for: observation,
                    from: pixelBuffer,
                    tag: "enroll_\(pose.rawValue)_\(capturedCount)",
                    checkSharpness: true
                ) else { return }

                accumulatedEmbeddings.append(embedding)
                let currentPoseTotalNeeded = targetCount(for: pose) * framesPerPose
                let currentPoseCaptured = capturedCount * framesPerPose + accumulatedEmbeddings.count

                DispatchQueue.main.async {
                    self.holdProgress = Double(currentPoseCaptured) / Double(currentPoseTotalNeeded)
                }

                if accumulatedEmbeddings.count >= framesPerPose {
                    let averaged = FaceIDDataStore.averageEmbeddings(accumulatedEmbeddings)
                    if poseBucketSamples[pose] == nil { poseBucketSamples[pose] = [] }
                    poseBucketSamples[pose]?.append(averaged)
                    accumulatedEmbeddings.removeAll()

                    let newCapturedCount = poseBucketSamples[pose]?.count ?? 0
                    if newCapturedCount >= targetCount(for: pose) {
                        DispatchQueue.main.async {
                            self.registrationPoseCaptured.insert(pose.rawValue)
                            self.holdProgress = 0.0
                        }
                    }

                    let totalNeeded = activeOrder.reduce(0) { $0 + targetCount(for: $1) }
                    let totalCurrent = activeOrder.reduce(0) { $0 + (poseBucketSamples[$1]?.count ?? 0) }
                    DispatchQueue.main.async { self.registrationProgress = Double(totalCurrent) / Double(totalNeeded) }
                    checkRegistrationComplete()
                }
            }
        } else {
            DispatchQueue.main.async {
                if self.userInstruction != currentTarget.hint {
                    self.userInstruction = currentTarget.hint
                }
            }
            if !accumulatedEmbeddings.isEmpty {
                accumulatedEmbeddings.removeLast()
                let capturedCount = poseBucketSamples[currentTarget]?.count ?? 0
                let currentPoseTotalNeeded = targetCount(for: currentTarget) * framesPerPose
                let currentPoseCaptured = capturedCount * framesPerPose + accumulatedEmbeddings.count
                DispatchQueue.main.async { self.holdProgress = Double(currentPoseCaptured) / Double(currentPoseTotalNeeded) }
            }
        }
    }

    private func checkRegistrationComplete() {
        let activeOrder = poseOrder
        let isComplete = activeOrder.allSatisfy { (poseBucketSamples[$0]?.count ?? 0) >= targetCount(for: $0) }
        guard isComplete else { return }
        finalizeRegistration()
    }

    // MARK: - Authentication Flow (Strict Synchronized 3-Frame Gate)

    private func stopForSecurityEvent(_ event: FaceIDSecurityEvent) {
        guard isAuthenticating else { return }
        isAuthenticating = false
        cleanupFaceIDResources()
        DispatchQueue.main.async { self.appState = .idle }
        onSecurityEvent?(event)
    }

    private func handleAuthentication(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let yaw = observation.yaw?.doubleValue ?? 0
        let pitch = getPitch(from: observation)
        if abs(yaw) > 0.45 || abs(pitch) > 0.40 { return }

        let activeThreshold: Float = FaceIDModelManager.shared.livenessLogitThreshold

        let antiSpoofEnabled = SettingsModel.shared.current.faceIDAntiSpoofEnabled
        var frameIsReal = !antiSpoofEnabled
        var spoofResult: AntiSpoofResult?

        let debugTag = FaceIDConfig.enableDebugImageCapture ? "auth_f\(frameCounter)" : nil

        if antiSpoofEnabled, let unavailable = FaceIDModelManager.shared.livenessUnavailableReason {
            DispatchQueue.main.async { self.userInstruction = unavailable }
        }

        if antiSpoofEnabled,
           let liveness = FaceIDModelManager.shared.evaluateAntiSpoof(
            pixelBuffer: pixelBuffer,
            observation: observation,
            debugTag: debugTag
        ) {
            livenessHistory.append(liveness.logit)
            if livenessHistory.count > FaceIDConfig.livenessWindow { livenessHistory.removeFirst() }

            let meanLogit = livenessHistory.reduce(0, +) / Float(livenessHistory.count)

            frameIsReal = (meanLogit > activeThreshold)

            spoofResult = AntiSpoofResult(
                isReal: frameIsReal,
                rawScore: liveness.rawScore,
                smoothScore: 1.0 / (1.0 + exp(-meanLogit)),
                logit: meanLogit
            )
            lastLivenessResult = spoofResult

            let now = Date()
            if !frameIsReal {
                if clearSpoofStart == nil { clearSpoofStart = now }
                if let start = clearSpoofStart, now.timeIntervalSince(start) >= 2.5 {
                    print("[FaceID Security] Sustained spoof detected — locking Face ID.")
                    stopForSecurityEvent(.spoofLocked)
                    return
                }
                DispatchQueue.main.async { self.userInstruction = "Checking liveness…" }
            } else {
                clearSpoofStart = nil
            }
        }

        guard let embedding = FaceIDDataStore.shared.generateAuthEmbedding(
            observation: observation,
            pixelBuffer: pixelBuffer,
            tag: "auth_f\(frameCounter)",
            checkSharpness: true
        ) else {
            return
        }

        if abs(yaw) < 0.35 && abs(pitch) < 0.35 {
            embeddingWindow.append(embedding)
            if embeddingWindow.count > embeddingWindowSize { embeddingWindow.removeFirst() }
        }

        let averagedEmbedding = embeddingWindow.count >= 2 ? FaceIDDataStore.averageEmbeddings(embeddingWindow) : embedding
        let score = FaceIDDataStore.shared.verify(currentEmbedding: averagedEmbedding)
        let frameMatched = (score >= FaceIDConfig.unlockIdentityThreshold)

        if frameMatched && frameIsReal {
            verifiedConsecutiveFrames += 1
        } else {
            verifiedConsecutiveFrames = 0
        }

        let livenessScores = spoofResult?.scoreLine ?? "REAL: -%"
        let thresholdTag = "[Thresh: \(Int((100 / (1 + exp(-activeThreshold))).rounded()))%]"
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastLogTime > 0.30 {
            lastLogTime = now
            let matchPct = Int((score * 100).rounded())
            print("[FaceID] Match: \(matchPct)% | \(livenessScores) | \(thresholdTag) | Real Streak: \(verifiedConsecutiveFrames)/\(FaceIDConfig.requiredConsecutiveFrames)")
        }

        let nowDate = Date()
        if !frameMatched {
            if mismatchStart == nil { mismatchStart = nowDate }
            if let start = mismatchStart, nowDate.timeIntervalSince(start) >= 6.0 {
                print("[FaceID] Mismatch timeout reached.")
                stopForSecurityEvent(.mismatchTimeout)
                return
            }
            DispatchQueue.main.async {
                self.userInstruction = String(format: "Verifying... %.0f%%", min(99, score / FaceIDConfig.unlockIdentityThreshold * 100))
            }
            return
        } else {
            mismatchStart = nil
        }

        if verifiedConsecutiveFrames >= FaceIDConfig.requiredConsecutiveFrames {
            let matchPct = Int((score * 100).rounded())
            print("[FaceID] Unlocked | Match: \(matchPct)% | \(livenessScores) | Streak: 3/3")
            FaceIDTiming.mark("unlocked", since: sessionStartDate)
            self.isAuthenticating = false
            self.cleanupFaceIDResources()

            DispatchQueue.main.async {
                self.appState = .recognized
                self.faceIsRecognized = true
                self.userInstruction = "Authenticated!"
                AuthenticationManager.shared.handleFaceIDAuthenticated()
            }
        }
    }
}

// MARK: - Data Store & Model Interface

enum FaceInputOrder: String, Codable {
    case rgb, bgr
}

typealias FaceAuthEmbedding = [FaceInputOrder: [Float]]

final class FaceIDDataStore {
    static let shared = FaceIDDataStore()

    private struct Profile: Codable {
        var prints: [[Float]]
        var order: FaceInputOrder
    }
    private struct StoredProfiles: Codable {
        var version = 2
        var profiles: [String: Profile]
    }

    private var profiles: [String: Profile] = [:]
    private var centroids: [FaceInputOrder: [Float]] = [:]

    private let secureFileURL: URL
    let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
        .highQualityDownsample: true,
        .workingColorSpace: NSNull()
    ])
    private let bufferLock = NSLock()

    private var facePixels = [UInt8](repeating: 0, count: 112 * 112 * 4)
    private var faceArray: MLMultiArray?
    private var faceArrayFlipped: MLMultiArray?

    private init() {
        let fm = FileManager.default
        let sup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = sup.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FaceIDApp")
        if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        secureFileURL = dir.appendingPathComponent("faceprints_fast.encrypted")
        loadDatabase()
    }

    func getRegisteredProfileNames() -> [String] { Array(profiles.keys).sorted() }

    func deleteProfile(name: String) {
        profiles.removeValue(forKey: name)
        updateCentroids()
        saveDatabase()
        if profiles.isEmpty { DispatchQueue.main.async { SettingsModel.shared.settings.hasRegisteredFaceID = false } }
    }

    func register(faceprints: [[Float]], forProfile name: String) {
        profiles[name] = Profile(prints: faceprints, order: .rgb)
        updateCentroids()
        saveDatabase()
        DispatchQueue.main.async { SettingsModel.shared.settings.hasRegisteredFaceID = true }
    }

    func teardownBuffers() {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        faceArray = nil
        faceArrayFlipped = nil
        ciContext.clearCaches()
    }

    func verify(currentEmbedding: FaceAuthEmbedding) -> Float {
        guard !profiles.isEmpty else { return 0 }
        var maxScore: Float = 0
        var centroidScore: Float = 0

        for (_, profile) in profiles {
            guard let current = currentEmbedding[profile.order] else { continue }
            for p in profile.prints {
                let sim = Self.cosineSimilarity(current, p)
                if sim > maxScore { maxScore = sim }
            }
        }
        for (order, centroid) in centroids {
            guard let current = currentEmbedding[order] else { continue }
            centroidScore = max(centroidScore, Self.cosineSimilarity(current, centroid))
        }
        return (maxScore * 0.85) + (centroidScore * 0.15)
    }

    func generateAuthEmbedding(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer, tag: String? = nil, checkSharpness: Bool = true) -> FaceAuthEmbedding? {
        let orders = Set(profiles.values.map(\.order))
        guard !orders.isEmpty,
              let faceImg = FaceAligner.alignFace(pixelBuffer: pixelBuffer, observation: observation, size: 112) else { return nil }

        bufferLock.lock()
        defer { bufferLock.unlock() }

        if faceArray == nil { faceArray = try? MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32) }
        guard let fArr = faceArray else { return nil }

        if facePixels.count != 112 * 112 * 4 { facePixels = [UInt8](repeating: 0, count: 112 * 112 * 4) }
        ciContext.render(faceImg, toBitmap: &facePixels, rowBytes: 112 * 4, bounds: CGRect(x: 0, y: 0, width: 112, height: 112), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        if checkSharpness && !FaceAligner.isBufferSharp(&facePixels, size: 112, blurThreshold: 3.5) { return nil }

        FaceAligner.normalizeFaceExposure(pixels: &facePixels, size: 112)
        FaceAligner.applyCLAHE(pixels: &facePixels, size: 112)

        var result: FaceAuthEmbedding = [:]
        for order in orders {
            FaceAligner.fillInputArray(array: fArr, from: &facePixels, size: 112, flipped: false, order: order)
            guard let embedding = FaceIDModelManager.shared.predictEmbeddingOnly(embeddingArray: fArr) else { return nil }
            result[order] = embedding
        }
        return result
    }

    func generateEnrollmentEmbedding(for observation: VNFaceObservation, from pixelBuffer: CVPixelBuffer, tag: String? = nil, checkSharpness: Bool = true) -> [Float]? {
        guard let faceImg = FaceAligner.alignFace(pixelBuffer: pixelBuffer, observation: observation, size: 112) else { return nil }

        bufferLock.lock()
        defer { bufferLock.unlock() }

        if faceArray == nil { faceArray = try? MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32) }
        if faceArrayFlipped == nil { faceArrayFlipped = try? MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32) }
        guard let fArr = faceArray, let fArrFlipped = faceArrayFlipped else { return nil }

        if facePixels.count != 112 * 112 * 4 { facePixels = [UInt8](repeating: 0, count: 112 * 112 * 4) }
        ciContext.render(faceImg, toBitmap: &facePixels, rowBytes: 112 * 4, bounds: CGRect(x: 0, y: 0, width: 112, height: 112), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        if checkSharpness && !FaceAligner.isBufferSharp(&facePixels, size: 112, blurThreshold: 5.5) { return nil }

        FaceAligner.normalizeFaceExposure(pixels: &facePixels, size: 112)
        FaceAligner.applyCLAHE(pixels: &facePixels, size: 112)
        FaceAligner.fillInputArray(array: fArr, from: &facePixels, size: 112, flipped: false, order: .rgb)
        FaceAligner.fillInputArray(array: fArrFlipped, from: &facePixels, size: 112, flipped: true, order: .rgb)

        return FaceIDModelManager.shared.predictEmbeddingTTA(original: fArr, flipped: fArrFlipped)
    }

    static func averageEmbeddings(_ embeddings: [FaceAuthEmbedding]) -> FaceAuthEmbedding {
        guard let first = embeddings.first else { return [:] }
        var out: FaceAuthEmbedding = [:]
        for order in first.keys {
            out[order] = averageEmbeddings(embeddings.compactMap { $0[order] })
        }
        return out
    }

    static func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first, !first.isEmpty else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in embeddings { vDSP_vadd(sum, 1, v, 1, &sum, 1, vDSP_Length(first.count)) }
        return l2Normalize(sum)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var r: Float = 0; vDSP_dotpr(a, 1, b, 1, &r, vDSP_Length(a.count)); return r
    }

    static func l2Normalize(_ v: [Float]) -> [Float] {
        var sq: Float = 0; vDSP_svesq(v, 1, &sq, vDSP_Length(v.count))
        let n = sqrtf(sq); guard n > 0 else { return v }
        return v.map { $0 / n }
    }

    private func updateCentroids() {
        centroids = [:]
        for order in Set(profiles.values.map(\.order)) {
            centroids[order] = Self.averageEmbeddings(profiles.values.filter { $0.order == order }.flatMap(\.prints))
        }
    }

    private func saveDatabase() {
        guard let d = try? JSONEncoder().encode(StoredProfiles(profiles: profiles)),
              let e = CryptoManager.shared.encrypt(data: d) else { return }
        try? e.write(to: secureFileURL, options: .atomic)
    }

    private func loadDatabase() {
        guard let e = try? Data(contentsOf: secureFileURL), let d = CryptoManager.shared.decrypt(data: e) else { return }
        if let stored = try? JSONDecoder().decode(StoredProfiles.self, from: d) {
            profiles = stored.profiles
        } else if let legacy = try? JSONDecoder().decode([String: [[Float]]].self, from: d) {
            profiles = legacy.mapValues { Profile(prints: $0, order: .bgr) }
        }
        updateCentroids()
    }
}

// MARK: - Fast Image Pre-Processor

struct FaceAligner {
    private static let canonical112: [CGPoint] = [
        CGPoint(x: 38.2946, y: 112 - 51.6963),
        CGPoint(x: 73.5318, y: 112 - 51.5014),
        CGPoint(x: 56.0252, y: 112 - 71.7366),
        CGPoint(x: 41.5493, y: 112 - 92.3655),
        CGPoint(x: 70.7299, y: 112 - 92.2041)
    ]

    static func isBufferSharp(_ pixels: inout [UInt8], size: Int, blurThreshold: Float) -> Bool {
        let n = size * size
        var luma = [Float](repeating: 0, count: n)

        pixels.withUnsafeBufferPointer { px in
            for p in 0..<n {
                let i = p * 4
                luma[p] = (0.299 * Float(px[i]) + 0.587 * Float(px[i + 1]) + 0.114 * Float(px[i + 2])) / 255.0
            }
        }

        var lap = [Float](repeating: 0, count: n)
        for y in 1..<(size - 1) {
            let rb = y * size
            for x in 1..<(size - 1) {
                let current = 4 * luma[rb + x]
                let top = luma[(y - 1) * size + x]
                let bottom = luma[(y + 1) * size + x]
                let left = luma[rb + x - 1]
                let right = luma[rb + x + 1]
                lap[rb + x] = current - top - bottom - left - right
            }
        }

        var mean: Float = 0
        vDSP_meanv(lap, 1, &mean, vDSP_Length(n))
        var s = [Float](repeating: -mean, count: n)
        vDSP_vadd(lap, 1, s, 1, &s, 1, vDSP_Length(n))
        var v: Float = 0
        vDSP_measqv(s, 1, &v, vDSP_Length(n))

        let variance = v * 1000
        if variance < blurThreshold { return false }
        return true
    }

    static func alignFace(pixelBuffer: CVPixelBuffer, observation: VNFaceObservation, size: Int) -> CIImage? {
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let sz = CGSize(width: w, height: h)
        let baseImg = CIImage(cvPixelBuffer: pixelBuffer).clampedToExtent()

        if let lm = observation.landmarks, let le = lm.leftEye, let re = lm.rightEye, let ns = lm.nose, let ol = lm.outerLips {
            let lPts = le.pointsInImage(imageSize: sz)
            let rPts = re.pointsInImage(imageSize: sz)
            let nPts = ns.pointsInImage(imageSize: sz)
            let mPts = ol.pointsInImage(imageSize: sz)

            let lc = avgPt(lPts)
            let rc = avgPt(rPts)
            if let tip = nPts.min(by: { $0.y < $1.y }), let ml = mPts.min(by: { $0.x < $1.x }), let mr = mPts.max(by: { $0.x < $1.x }) {
                let src = [lc.x <= rc.x ? lc : rc, lc.x <= rc.x ? rc : lc, tip, ml, mr]
                if let aligned = computeUmeyama(baseImg: baseImg, source: src, dest: canonical112, size: size) { return aligned }
            }
        }

        let bb = observation.boundingBox
        let margin: CGFloat = 0.15
        let rectX = max(0, bb.minX - bb.width * margin) * w
        let rectY = max(0, bb.minY - bb.height * margin) * h
        let rectW = min(1, bb.width * (1 + 2 * margin)) * w
        let rectH = min(1, bb.height * (1 + 2 * margin)) * h
        let rect = CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
        let scale = CGFloat(size) / max(rect.width, rect.height)

        return baseImg.cropped(to: rect)
                      .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                      .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    static func fillInputArray(array: MLMultiArray, from pixels: inout [UInt8], size: Int, flipped: Bool, order: FaceInputOrder) {
        let ptr = array.dataPointer.assumingMemoryBound(to: Float32.self)
        let plane = size * size
        let (rPlane, bPlane) = order == .rgb ? (0, 2 * plane) : (2 * plane, 0)

        pixels.withUnsafeBufferPointer { px in
            for y in 0..<size {
                let rowOffset = y * size
                for x in 0..<size {
                    let srcX = flipped ? (size - 1 - x) : x
                    let pi = (rowOffset + srcX) * 4

                    let r = Float(px[pi]) / 255.0
                    let g = Float(px[pi + 1]) / 255.0
                    let b = Float(px[pi + 2]) / 255.0

                    let idx = rowOffset + x

                    ptr[rPlane + idx] = (r - 0.5) / 0.5
                    ptr[plane + idx] = (g - 0.5) / 0.5
                    ptr[bPlane + idx] = (b - 0.5) / 0.5
                }
            }
        }
    }

    static func normalizeFaceExposure(pixels: inout [UInt8], size: Int) {
        pixels.withUnsafeMutableBufferPointer { px in
            var totalLuma = 0
            var count = 0

            let margin = Int(Double(size) * 0.20)
            let end = size - margin

            for y in margin..<end {
                let rowBase = y * size
                for x in margin..<end {
                    let base = (rowBase + x) * 4
                    let r = Int(px[base])
                    let g = Int(px[base + 1])
                    let b = Int(px[base + 2])
                    totalLuma += (299 * r + 587 * g + 114 * b + 500) / 1000
                    count += 1
                }
            }

            guard count > 0 else { return }
            let mean = Float(totalLuma) / Float(count)
            guard mean > 5, abs(mean - 127.0) > 8 else { return }

            let gamma = log(127.0 / 255.0) / log(mean / 255.0)
            var lut = [UInt8](repeating: 0, count: 256)
            for i in 0..<256 {
                let normalized = Float(i) / 255.0
                let corrected = powf(normalized, gamma) * 255.0 + 0.5
                lut[i] = UInt8(min(255, max(0, Int(corrected))))
            }

            let n = size * size
            for p in 0..<n {
                let b = p * 4
                px[b]   = lut[Int(px[b])]
                px[b+1] = lut[Int(px[b+1])]
                px[b+2] = lut[Int(px[b+2])]
            }
        }
    }

    static func applyCLAHE(pixels: inout [UInt8], size: Int) {
        let numTiles = 8
        let tSz = size / numTiles
        let ppt = tSz * tSz
        let clipLimit = max(2, (4 * ppt) / 256)

        pixels.withUnsafeMutableBufferPointer { px in
            var luma = [UInt8](repeating: 0, count: size * size)
            luma.withUnsafeMutableBufferPointer { lumaPx in
                for p in 0..<(size * size) {
                    let b = p * 4
                    let r = Int(px[b])
                    let g = Int(px[b+1])
                    let c = Int(px[b+2])
                    let y = (299 * r + 587 * g + 114 * c + 500) / 1000
                    lumaPx[p] = UInt8(min(255, max(0, y)))
                }

                var luts = [UInt8](repeating: 0, count: numTiles * numTiles * 256)
                for ty in 0..<numTiles {
                    for tx in 0..<numTiles {
                        var hist = [Int](repeating: 0, count: 256)
                        let y0 = ty * tSz
                        let x0 = tx * tSz
                        for yy in y0..<(y0 + tSz) {
                            let rb = yy * size
                            for xx in x0..<(x0 + tSz) { hist[Int(lumaPx[rb + xx])] += 1 }
                        }
                        var excess = 0
                        for i in 0..<256 { if hist[i] > clipLimit { excess += hist[i] - clipLimit; hist[i] = clipLimit } }
                        let add = excess / 256
                        let left = excess % 256
                        for i in 0..<256 { hist[i] += add + (i < left ? 1 : 0) }
                        let lb = (ty * numTiles + tx) * 256
                        var cum = 0
                        for i in 0..<256 { cum += hist[i]; luts[lb + i] = UInt8(min(255, (cum * 255) / ppt)) }
                    }
                }

                let tsF = Float(tSz); let half = tsF * 0.5; let last = numTiles - 1
                for y in 0..<size {
                    let tyF = (Float(y) - half) / tsF; var ty0 = Int(floor(tyF)); let dy = tyF - Float(ty0); var ty1 = ty0 + 1
                    if ty0 < 0 { ty0 = 0 } else if ty0 > last { ty0 = last }
                    if ty1 < 0 { ty1 = 0 } else if ty1 > last { ty1 = last }
                    let rb = y * size

                    for x in 0..<size {
                        let txF = (Float(x) - half) / tsF; var tx0 = Int(floor(txF)); let dx = txF - Float(tx0); var tx1 = tx0 + 1
                        if tx0 < 0 { tx0 = 0 } else if tx0 > last { tx0 = last }
                        if tx1 < 0 { tx1 = 0 } else if tx1 > last { tx1 = last }

                        let yv = Int(lumaPx[rb + x])
                        let v00 = Float(luts[(ty0 * numTiles + tx0) * 256 + yv])
                        let v01 = Float(luts[(ty0 * numTiles + tx1) * 256 + yv])
                        let v10 = Float(luts[(ty1 * numTiles + tx0) * 256 + yv])
                        let v11 = Float(luts[(ty1 * numTiles + tx1) * 256 + yv])

                        let a1 = v00 * (1 - dx) + v01 * dx
                        let a2 = v10 * (1 - dx) + v11 * dx
                        let newY = a1 * (1 - dy) + a2 * dy
                        let gain: Float = Float(yv) > 1 ? newY / Float(yv) : 1

                        let pi = (rb + x) * 4
                        let newR = Float(px[pi]) * gain + 0.5
                        let newG = Float(px[pi+1]) * gain + 0.5
                        let newB = Float(px[pi+2]) * gain + 0.5

                        px[pi]   = UInt8(min(255, max(0, newR)))
                        px[pi+1] = UInt8(min(255, max(0, newG)))
                        px[pi+2] = UInt8(min(255, max(0, newB)))
                    }
                }
            }
        }
    }

    private static func avgPt(_ pts: [CGPoint]) -> CGPoint {
        let s = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x+$1.x, y: $0.y+$1.y) }
        return CGPoint(x: s.x/CGFloat(pts.count), y: s.y/CGFloat(pts.count))
    }

    private static func computeUmeyama(baseImg: CIImage, source: [CGPoint], dest: [CGPoint], size: Int) -> CIImage? {
        let n = source.count; var mp = CGPoint.zero, mq = CGPoint.zero
        for i in 0..<n { mp.x += source[i].x; mp.y += source[i].y; mq.x += dest[i].x; mq.y += dest[i].y }
        mp.x /= CGFloat(n); mp.y /= CGFloat(n); mq.x /= CGFloat(n); mq.y /= CGFloat(n)
        var sPP: CGFloat = 0, sXX: CGFloat = 0, sXY: CGFloat = 0
        for i in 0..<n {
            let px = source[i].x - mp.x; let py = source[i].y - mp.y
            let qx = dest[i].x - mq.x; let qy = dest[i].y - mq.y
            sPP += px*px + py*py; sXX += px*qx + py*qy; sXY += px*qy - py*qx
        }
        guard sPP > 1e-6 else { return nil }
        let a = sXX/sPP; let b = sXY/sPP
        let tx = mq.x - (a*mp.x - b*mp.y); let ty = mq.y - (b*mp.x + a*mp.y)
        let t = CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
        return baseImg.transformed(by: t).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }
}

// MARK: - CoreML Dynamic RAM Manager (Evicts on Idle, Fast-Loads on Demand)

final class FaceIDModelManager {
    static let shared = FaceIDModelManager()
    private let lock = NSLock()
    private let modelLoadingQueue = DispatchQueue(label: "com.sapphire.modelLoadingQueue", qos: .userInitiated)

    private static let idleTimeout: TimeInterval = 20
    private var lastUse = DispatchTime.now()
    private var idleTimer: DispatchSourceTimer?
    private var generation = 0

    private var embeddingModel: MLModel?
    private var embeddingInputName: String = ""
    private var embeddingOutputName: String = ""

    private var livenessModel: MLModel?
    private var livenessInputName: String = "colorImage"
    private var livenessOutputName: String = "liveness_logit"
    private(set) var livenessCropScale: CGFloat = 1.5
    private(set) var livenessLogitThreshold: Float = FaceIDConfig.livenessFallbackLogitThreshold

    private var isCurrentlyLoading = false
    private var sharedAntiSpoofBuffer: CVPixelBuffer?

    private static let livenessModelName = "PassiveLiveness_v4_ANE"
    private static var didPurgeLegacyModelCopies = false

    private(set) var livenessUnavailableReason: String?
    private var livenessRetryAfter = Date.distantPast

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private init() {}

    private var keepsModelsResident: Bool {
        let settings = SettingsModel.shared.settings
        return settings.faceIDKeepModelsInMemory && settings.faceIDUnlockEnabled && settings.hasRegisteredFaceID
    }

    func prewarm() {
        modelLoadingQueue.async { [weak self] in
            self?.loadModelsIfNeeded()
        }
    }

    @MainActor
    func applyResidencyPolicy() {
        if keepsModelsResident {
            installMemoryPressureHandler()
            prewarm()
        } else if !AuthenticationManager.shared.isFaceIDSessionActive {
            unloadModels()
        }
    }

    func sessionEnded() {
        if !keepsModelsResident { unloadModels() }
    }

    @MainActor
    private func installMemoryPressureHandler() {
        guard memoryPressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !AuthenticationManager.shared.isFaceIDSessionActive else { return }
                print("[FaceID Model Manager] Critical memory pressure: releasing kept models")
                self.unloadModels()
            }
        }
        memoryPressureSource = source
        source.resume()
    }

    func unloadModels() {
        lock.lock()
        defer { lock.unlock() }
        unloadLocked()
    }

    private func unloadLocked() {
        generation += 1
        embeddingModel = nil
        embeddingInputName = ""
        embeddingOutputName = ""
        sharedAntiSpoofBuffer = nil
        idleTimer?.cancel()
        idleTimer = nil
    }

    private func markUsedLocked() {
        lastUse = .now()
        guard idleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: modelLoadingQueue)
        timer.schedule(deadline: .now() + Self.idleTimeout, repeating: .never, leeway: .seconds(1))
        timer.setEventHandler { [weak self, weak timer] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.keepsModelsResident {
                timer?.cancel()
                if self.idleTimer === timer { self.idleTimer = nil }
                return
            }
            let idleNanos = DispatchTime.now().uptimeNanoseconds - self.lastUse.uptimeNanoseconds
            let timeoutNanos = UInt64(Self.idleTimeout * 1e9)
            if idleNanos >= timeoutNanos {
                self.unloadLocked()
            } else {
                timer?.schedule(deadline: .now() + .nanoseconds(Int(timeoutNanos - idleNanos)),
                                repeating: .never, leeway: .seconds(1))
            }
        }
        idleTimer = timer
        timer.resume()
    }

    private func loadModelsIfNeeded() {
        lock.lock()
        let needEmbedding = embeddingModel == nil
        let needLiveness = livenessModel == nil && Date() >= livenessRetryAfter
        if isCurrentlyLoading || (!needEmbedding && !needLiveness) {
            lock.unlock()
            return
        }
        isCurrentlyLoading = true
        let startGeneration = generation
        let livenessResident = livenessModel != nil
        lock.unlock()

        let loadStart = Date()
        purgeLegacyModelCopies()
        let embedding = needEmbedding ? (self.loadModelWithIO("ArcFace", preferredOutput: "embedding") ??
                                         self.loadModelWithIO("ModernFace", preferredOutput: "embedding") ??
                                         self.loadModelWithIO("FaceEmbedding", preferredOutput: "embedding")) : nil
        let embeddingMs = Date().timeIntervalSince(loadStart) * 1000
        let liveness = needLiveness ? self.loadLivenessModel() : nil

        lock.lock()
        defer { lock.unlock() }
        isCurrentlyLoading = false
        guard generation == startGeneration else { return }
        if let (model, input, output) = embedding {
            self.embeddingModel = model
            self.embeddingInputName = input
            self.embeddingOutputName = output
        }
        if needLiveness && liveness == nil {
            if keepsModelsResident && livenessRetryAfter != .distantFuture {
                modelLoadingQueue.asyncAfter(deadline: .now() + 30) { [weak self] in self?.loadModelsIfNeeded() }
            }
        }
        if let (model, meta) = liveness {
            self.livenessUnavailableReason = nil
            self.livenessModel = model
            self.resolveLivenessIONames(model: model)
            if let s = meta["crop_scale"].flatMap(Double.init) { self.livenessCropScale = CGFloat(s) }
            if let t = meta["thr_default"].flatMap(Float.init) { self.livenessLogitThreshold = t }
            print("[FaceID Model Manager] Loaded \(Self.livenessModelName) (crop x\(livenessCropScale), logit threshold \(livenessLogitThreshold))")
        }
        if embedding != nil || liveness != nil { markUsedLocked() }
        print(String(format: "[FaceID timing] models loaded in %.0f ms (embedding %@, liveness %@)",
                     Date().timeIntervalSince(loadStart) * 1000,
                     needEmbedding ? String(format: "%.0f ms", embeddingMs) : "resident",
                     needLiveness ? String(format: "%.0f ms", Date().timeIntervalSince(loadStart) * 1000 - embeddingMs) : (livenessResident ? "resident" : "backing off")))
    }

    private func loadLivenessModel() -> (MLModel, [String: String])? {
        let name = FaceIDModelManager.livenessModelName

        let livenessCfg = MLModelConfiguration()
        livenessCfg.computeUnits = .all

        var result: Result<MLModel, Error>
        if let encryptedURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            result = Self.loadSynchronously { done in
                MLModel.load(contentsOf: encryptedURL, configuration: livenessCfg, completionHandler: done)
            }
        } else {
            result = .failure(CocoaError(.fileNoSuchFile))
        }

        switch result {
        case .success(let loaded):
            return (loaded, loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String] ?? [:])
        case .failure(let error):
            print("[FaceID Model Manager] Could not load \(name): \(error). Face ID won't unlock while anti-spoofing is on.")
            let reason: String
            let retryAfter: Date
            switch (error as? MLModelError)?.code {
            case .modelDecryptionKeyFetch:
                reason = "Go online once so Apple can unlock spoof protection. Face ID itself runs only on this Mac."
                retryAfter = Date().addingTimeInterval(5)
            case .modelDecryption:
                reason = "Face ID spoof protection couldn't start. Restart your Mac to restore it; use your password for now."
                retryAfter = .distantFuture
            default:
                reason = "Face ID spoof protection is unavailable. Use your password."
                retryAfter = Date().addingTimeInterval(5)
            }
            lock.lock(); livenessUnavailableReason = reason; livenessRetryAfter = retryAfter; lock.unlock()
            return nil
        }
    }

    private static func loadSynchronously(_ start: (@escaping (Result<MLModel, Error>) -> Void) -> Void) -> Result<MLModel, Error> {
        var result: Result<MLModel, Error> = .failure(CocoaError(.featureUnsupported))
        let done = DispatchSemaphore(value: 0)
        start { result = $0; done.signal() }
        done.wait()
        return result
    }

    private func purgeLegacyModelCopies() {
        guard !Self.didPurgeLegacyModelCopies else { return }
        Self.didPurgeLegacyModelCopies = true
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? fm.removeItem(at: caches.appendingPathComponent("com.sapphire.faceid", isDirectory: true))
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "faceID.purgedE5Cache.v1"), let bundleID = Bundle.main.bundleIdentifier {
            try? fm.removeItem(at: caches.appendingPathComponent(bundleID).appendingPathComponent("com.apple.e5rt.e5bundlecache"))
            defaults.set(true, forKey: "faceID.purgedE5Cache.v1")
        }
    }

    private func locateResource(name: String, ext: String) -> URL? {
        let bundles = [Bundle.main, Bundle(for: FaceIDModelManager.self)]
        for b in bundles {
            if let url = b.url(forResource: name, withExtension: ext) ??
                         b.url(forResource: name.lowercased(), withExtension: ext) ??
                         b.url(forResource: name.capitalized, withExtension: ext) {
                return url
            }
        }
        for b in bundles {
            if let resURL = b.resourceURL {
                let enumerator = FileManager.default.enumerator(at: resURL, includingPropertiesForKeys: nil)
                while let fileURL = enumerator?.nextObject() as? URL {
                    if fileURL.pathExtension.lowercased() == ext.lowercased() {
                        let baseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                        if baseName == name.lowercased() {
                            return fileURL
                        }
                    }
                }
            }
        }
        return nil
    }

    private func resolveLivenessIONames(model: MLModel) {
        if let inName = model.modelDescription.inputDescriptionsByName.keys.first {
            self.livenessInputName = inName
        }
        if let outName = model.modelDescription.outputDescriptionsByName.keys.first {
            self.livenessOutputName = outName
        }
    }

    private func loadModelWithIO(_ name: String, preferredOutput: String?) -> (MLModel, String, String)? {
        guard let url = locateResource(name: name, ext: "mlmodelc") ?? locateResource(name: name, ext: "mlpackage") else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: cfg) else { return nil }
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first else { return nil }
        let outputs = model.modelDescription.outputDescriptionsByName
        let outputName = (preferredOutput != nil && outputs[preferredOutput!] != nil) ? preferredOutput! : (outputs.keys.first ?? "")
        return (model, inputName, outputName)
    }

    private func getAntiSpoofBuffer() -> CVPixelBuffer? {
        if let buf = sharedAntiSpoofBuffer { return buf }
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, 224, 224, kCVPixelFormatType_32BGRA, attrs, &sharedAntiSpoofBuffer)
        return sharedAntiSpoofBuffer
    }

    private func rawCropAndResize(
        sourceBuffer: CVPixelBuffer,
        cropRect: CGRect,
        destBuffer: CVPixelBuffer
    ) -> Bool {
        CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(destBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(destBuffer, [])
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(sourceBuffer),
              let dstBase = CVPixelBufferGetBaseAddress(destBuffer) else {
            return false
        }

        let srcWidth = CVPixelBufferGetWidth(sourceBuffer)
        let srcHeight = CVPixelBufferGetHeight(sourceBuffer)
        let srcRowBytes = CVPixelBufferGetBytesPerRow(sourceBuffer)

        let dstWidth = CVPixelBufferGetWidth(destBuffer)
        let dstHeight = CVPixelBufferGetHeight(destBuffer)
        let dstRowBytes = CVPixelBufferGetBytesPerRow(destBuffer)

        var dstAll = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(dstHeight),
            width: vImagePixelCount(dstWidth),
            rowBytes: dstRowBytes
        )
        let black: [UInt8] = [0, 0, 0, 255]
        guard vImageBufferFill_ARGB8888(&dstAll, black, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return false }

        let inside = cropRect.intersection(CGRect(x: 0, y: 0, width: srcWidth, height: srcHeight))
        guard !inside.isNull, inside.width >= 1, inside.height >= 1 else { return false }

        let x = Int(inside.minX.rounded(.down)), y = Int(inside.minY.rounded(.down))
        let w = max(1, min(srcWidth - x, Int(inside.width.rounded()))), h = max(1, min(srcHeight - y, Int(inside.height.rounded())))

        let kx = CGFloat(dstWidth) / cropRect.width, ky = CGFloat(dstHeight) / cropRect.height
        let dx = max(0, min(dstWidth - 1, Int(((inside.minX - cropRect.minX) * kx).rounded())))
        let dy = max(0, min(dstHeight - 1, Int(((inside.minY - cropRect.minY) * ky).rounded())))
        let dw = max(1, min(dstWidth - dx, Int((inside.width * kx).rounded())))
        let dh = max(1, min(dstHeight - dy, Int((inside.height * ky).rounded())))

        var srcVImage = vImage_Buffer(
            data: srcBase.advanced(by: y * srcRowBytes + x * 4),
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: srcRowBytes
        )
        var dstVImage = vImage_Buffer(
            data: dstBase.advanced(by: dy * dstRowBytes + dx * 4),
            height: vImagePixelCount(dh),
            width: vImagePixelCount(dw),
            rowBytes: dstRowBytes
        )

        let error = vImageScale_ARGB8888(&srcVImage, &dstVImage, nil, vImage_Flags(kvImageNoFlags))
        return error == kvImageNoError
    }

    func evaluateAntiSpoof(
        pixelBuffer: CVPixelBuffer,
        observation: VNFaceObservation,
        debugTag: String? = nil
    ) -> AntiSpoofResult? {
        lock.lock()
        guard let model = livenessModel else {
            lock.unlock()
            prewarm()
            return nil
        }
        let inKey = livenessInputName
        let outKey = livenessOutputName
        let cropScale = livenessCropScale
        markUsedLocked()
        lock.unlock()

        let srcW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let srcH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let bb = observation.boundingBox

        let visionSide = max(bb.width * srcW, bb.height * srcH)
        let boxSide = visionSide * FaceIDConfig.antiSpoofVisionBoxScale
        let centerX = bb.midX * srcW
        let centerY = (1.0 - bb.midY) * srcH - FaceIDConfig.antiSpoofVisionBoxShiftUp * visionSide
        let cropSize = boxSide * cropScale

        guard cropSize >= 30 else { return nil }

        let cropRect = CGRect(x: centerX - cropSize / 2.0, y: centerY - cropSize / 2.0, width: cropSize, height: cropSize)

        guard let cropped224 = getAntiSpoofBuffer(),
              rawCropAndResize(sourceBuffer: pixelBuffer, cropRect: cropRect, destBuffer: cropped224) else {
            return nil
        }

        if let tag = debugTag {
            FaceIDDebugger.saveCroppedInputBuffer(pixelBuffer: cropped224, name: tag)
        }

        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [inKey: MLFeatureValue(pixelBuffer: cropped224)])
            let output = try model.prediction(from: input)

            guard let logitArray = output.featureValue(for: outKey)?.multiArrayValue ??
                                   output.featureValue(for: "liveness_logit")?.multiArrayValue ??
                                   output.featureValue(for: output.featureNames.first ?? "")?.multiArrayValue else { return nil }

            let logit = logitArray[0].floatValue
            guard logit.isFinite else { return nil }
            let rawScore = 1.0 / (1.0 + exp(-logit))

            return AntiSpoofResult(
                isReal: false,
                rawScore: rawScore,
                smoothScore: rawScore,
                logit: logit
            )
        } catch { return nil }
    }

    func predictEmbeddingTTA(original: MLMultiArray, flipped: MLMultiArray) -> [Float]? {
        lock.lock()
        guard let model = embeddingModel, !embeddingInputName.isEmpty, !embeddingOutputName.isEmpty else {
            lock.unlock()
            prewarm()
            return nil
        }
        let inKey = embeddingInputName
        let outKey = embeddingOutputName
        markUsedLocked()
        lock.unlock()

        let runPred = { (array: MLMultiArray) -> [Float]? in
            do {
                let provider = try MLDictionaryFeatureProvider(dictionary: [inKey: MLFeatureValue(multiArray: array)])
                let out = try model.prediction(from: provider)
                guard let arr = out.featureValue(for: outKey)?.multiArrayValue else { return nil }
                let ptr = arr.dataPointer.assumingMemoryBound(to: Float32.self)
                return Array(UnsafeBufferPointer(start: ptr, count: arr.count))
            } catch { return nil }
        }

        guard let origVec = runPred(original), let flipVec = runPred(flipped), origVec.count == flipVec.count else { return nil }
        var mean = [Float](repeating: 0, count: origVec.count)
        for i in 0..<origVec.count { mean[i] = (origVec[i] + flipVec[i]) * 0.5 }
        return FaceIDDataStore.l2Normalize(mean)
    }

    func predictEmbeddingOnly(embeddingArray: MLMultiArray) -> [Float]? {
        lock.lock()
        guard let model = embeddingModel, !embeddingInputName.isEmpty, !embeddingOutputName.isEmpty else {
            lock.unlock()
            prewarm()
            return nil
        }
        let inKey = embeddingInputName
        let outKey = embeddingOutputName
        markUsedLocked()
        lock.unlock()

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: [inKey: MLFeatureValue(multiArray: embeddingArray)])
            let out = try model.prediction(from: provider)
            guard let arr = out.featureValue(for: outKey)?.multiArrayValue else { return nil }
            let ptr = arr.dataPointer.assumingMemoryBound(to: Float32.self)
            return FaceIDDataStore.l2Normalize(Array(UnsafeBufferPointer(start: ptr, count: arr.count)))
        } catch {
            return nil
        }
    }
}