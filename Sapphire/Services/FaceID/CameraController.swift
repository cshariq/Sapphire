//
//  CameraController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-15
//

import Vision
import CoreML
import Combine
import SwiftUI
import AppKit
import AVFoundation
import os

enum RegistrationStep: CaseIterable, Equatable {
    case scanning
    case finalizing

    var instruction: String {
        switch self {
        case .scanning: return "Center your face, then slowly look left and right."
        case .finalizing: return "Securing your face profile..."
        }
    }
}

private enum FacePoseBucket: String, CaseIterable {
    case center
    case left
    case right

    static func detect(yaw: Double) -> FacePoseBucket? {
        if abs(yaw) < 0.12 { return .center }
        // Front camera is mirrored: user's RIGHT turn = face appears to turn LEFT in preview = positive yaw
        // User's LEFT turn = face appears to turn RIGHT in preview = negative yaw
        if yaw > 0.12 { return .right }
        if yaw < -0.12 { return .left }
        return nil
    }
}

enum CameraState: Equatable {
    case idle, registering(RegistrationStep), registeredAndIdle, detecting, recognized, authenticating
}

class CameraController: NSObject, ObservableObject, Identifiable, AVCaptureVideoDataOutputSampleBufferDelegate {

    public let id = UUID()
    @Published var appState: CameraState = .idle
    @Published var userInstruction: String = "Press 'Register' to begin."
    @Published var faceIsRecognized: Bool = false
    @Published var smoothedBoundingBox: CGRect?
    @Published var processedAuthImage: NSImage? = nil
    @Published var processedRegImage: NSImage? = nil
    @Published var cameraError: String? = nil
    @Published var registrationProgress: Double = 0.0
    @Published var registrationPoseCaptured: Set<String> = []

    private var isAuthenticating = false
    private var isProcessingAuthFrame = false
    private var authFrameCounter = 0
    private var consecutiveMatchCount = 0
    private let logger = Logger(subsystem: "com.sapphire.app", category: "FaceID.CameraController")

    // Temporal Score History Buffer
    private var similarityHistory: [Double] = []
    private let temporalWindowSize = 4

    let captureSession = AVCaptureSession()

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.cshariq.Sapphire.sessionQueue", qos: .userInteractive)
    private let visionQueue = DispatchQueue(label: "com.cshariq.Sapphire.visionQueue", qos: .userInitiated)

    public var faceDataStore = FaceDataStore.shared

    private lazy var faceLandmarksRequest: VNDetectFaceLandmarksRequest = {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        return request
    }()

    private var currentRegistrationStep: RegistrationStep = .scanning

    private var poseBucketSamples: [FacePoseBucket: [Faceprint]] = [:]
    private var stablePoseFrames = 0
    private var lastStableBucket: FacePoseBucket?
    private let samplesPerBucket = 1
    private let requiredStableFrames = 2
    private let maxSamplesPerBucket = 2

    private let unlockThreshold: Double = 0.84
    private let instantUnlockThreshold: Double = 0.92
    private let consecutiveMatchesRequired = 2
    private let authFrameStride = 1

    @Published var isRegistrationMode = false
    private var profileForRegistration: String?

    private func setupSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
                self.logger.error("Could not find a suitable video device.")
                return
            }
            do {
                let deviceInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(deviceInput) { self.captureSession.addInput(deviceInput) }

                try videoDevice.lockForConfiguration()
                if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                    videoDevice.focusMode = .continuousAutoFocus
                }
                if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                    videoDevice.exposureMode = .continuousAutoExposure
                }
                videoDevice.unlockForConfiguration()
            } catch {
                self.logger.error("Camera setup failed: \(error.localizedDescription)")
            }
            if self.captureSession.canSetSessionPreset(.hd1280x720) { self.captureSession.sessionPreset = .hd1280x720 }
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            if self.captureSession.canAddOutput(self.videoDataOutput) { self.captureSession.addOutput(self.videoDataOutput) }
            if let connection = self.videoDataOutput.connection(with: .video) { connection.isVideoMirrored = true }
            self.captureSession.commitConfiguration()
        }
    }

    override init() {
        super.init()
        setupSession()
        if faceDataStore.hasRegisteredFaceprints() {
            DispatchQueue.main.async {
                self.appState = .registeredAndIdle
                self.userInstruction = "Registered! Press Authenticate."
            }
        }
    }

    func startCameraSession() {
        sessionQueue.async {
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
        }
    }

    func stopCameraSession() {
        sessionQueue.async {
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
        }
    }

    func cancelCurrentOperation() {
        isAuthenticating = false
        isRegistrationMode = false
        isProcessingAuthFrame = false
        consecutiveMatchCount = 0
        authFrameCounter = 0
        profileForRegistration = nil

        poseBucketSamples.removeAll()
        stablePoseFrames = 0
        lastStableBucket = nil
        registrationPoseCaptured.removeAll()
        similarityHistory.removeAll()

        stopCameraSession()

        DispatchQueue.main.async {
            if self.appState != .registeredAndIdle {
                self.appState = .idle
                self.userInstruction = "Press 'Register' to begin."
                self.registrationProgress = 0.0
            } else {
                 self.userInstruction = "Registration cancelled."
            }
        }
    }

    func teardown() {
        if captureSession.isRunning {
            stopCameraSession()
        }
        videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        logger.info("Teardown complete.")
    }

    func startAuthentication() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        isProcessingAuthFrame = false
        consecutiveMatchCount = 0
        authFrameCounter = 0
        similarityHistory.removeAll()
        
        DispatchQueue.main.async {
            self.appState = .authenticating
            self.userInstruction = "Looking for your face..."
        }
        startCameraSession()
    }

    func startRegistration(forProfile name: String) {
        isRegistrationMode = true
        self.profileForRegistration = name

        poseBucketSamples.removeAll()
        stablePoseFrames = 0
        lastStableBucket = nil
        registrationPoseCaptured.removeAll()

        DispatchQueue.main.async {
            self.registrationProgress = 0.0
            self.currentRegistrationStep = .scanning
            self.appState = .registering(self.currentRegistrationStep)
            self.updateInstruction()
        }
        startCameraSession()
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAuthenticating || isRegistrationMode, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([faceLandmarksRequest])
            guard let observation = bestFaceObservation(from: faceLandmarksRequest.results) else {
                DispatchQueue.main.async { self.smoothedBoundingBox = nil }
                return
            }

            processFaceObservation(observation, pixelBuffer: pixelBuffer)

        } catch {
            logger.error("Error performing face detection: \(error.localizedDescription)")
        }
    }

    private func bestFaceObservation(from results: [VNFaceObservation]?) -> VNFaceObservation? {
        guard let results, !results.isEmpty else { return nil }
        return results.max { lhs, rhs in
            let lhsQuality = lhs.faceCaptureQuality ?? lhs.confidence
            let rhsQuality = rhs.faceCaptureQuality ?? rhs.confidence
            if lhsQuality == rhsQuality {
                let lhsArea = lhs.boundingBox.width * lhs.boundingBox.height
                let rhsArea = rhs.boundingBox.width * rhs.boundingBox.height
                return lhsArea < rhsArea
            }
            return lhsQuality < rhsQuality
        }
    }

    private func processFaceObservation(_ observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let newBox = observation.boundingBox
        DispatchQueue.main.async {
            if self.smoothedBoundingBox == nil { self.smoothedBoundingBox = newBox }
            else { self.smoothedBoundingBox = self.smoothedBoundingBox!.lerp(to: newBox, alpha: 0.25) }
        }

        if isRegistrationMode {
            handleRegistrationStep(observation: observation, pixelBuffer: pixelBuffer)
        } else if isAuthenticating {
            guard !isProcessingAuthFrame else { return }
            authFrameCounter += 1
            guard authFrameCounter % authFrameStride == 0 else { return }
            performAuthenticationChecks(observation: observation, pixelBuffer: pixelBuffer)
        }
    }

    private func handleRegistrationStep(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        guard currentRegistrationStep == .scanning else { return }

        let yaw = observation.yaw?.doubleValue ?? 0
        let pitch = observation.pitch?.doubleValue ?? 0
        let roll = observation.roll?.doubleValue ?? 0
        
        logger.debug("Face pose - yaw: \(yaw, privacy: .public), pitch: \(pitch, privacy: .public), roll: \(roll, privacy: .public)")

        guard let bucket = FacePoseBucket.detect(yaw: yaw) else {
            logger.debug("No bucket detected for yaw: \(yaw, privacy: .public)")
            stablePoseFrames = 0
            lastStableBucket = nil
            return
        }

        DispatchQueue.main.async {
            self.userInstruction = self.registrationHint()
        }

        if bucket == lastStableBucket {
            stablePoseFrames += 1
        } else {
            lastStableBucket = bucket
            stablePoseFrames = 1
        }

        logger.debug("Stable frames for \(bucket.rawValue, privacy: .public): \(self.stablePoseFrames, privacy: .public)")

        guard stablePoseFrames >= requiredStableFrames else { return }

        let existingCount = poseBucketSamples[bucket]?.count ?? 0
        guard existingCount < maxSamplesPerBucket else { return }

        let success = captureSample(for: bucket, observation: observation, pixelBuffer: pixelBuffer)
        if success {
            stablePoseFrames = 0
        } else {
            stablePoseFrames = requiredStableFrames
        }

        let filledBuckets = FacePoseBucket.allCases.filter { (poseBucketSamples[$0]?.isEmpty == false) }.count
        let totalSamples = poseBucketSamples.values.reduce(0) { $0 + $1.count }
        let targetSamples = FacePoseBucket.allCases.count * samplesPerBucket
        
        DispatchQueue.main.async {
            self.registrationProgress = min(1.0, Double(filledBuckets) / Double(FacePoseBucket.allCases.count))
        }

        if filledBuckets == FacePoseBucket.allCases.count && totalSamples >= targetSamples {
            advanceToFinalizingRegistration()
        }
    }

    private func registrationHint() -> String {
        let missing = FacePoseBucket.allCases.filter { poseBucketSamples[$0]?.isEmpty != false }
        guard let next = missing.first else {
            return "Almost done — hold still."
        }
        switch next {
        case .center: return "Look straight at the camera."
        case .left: return "Slowly turn your head to the left."
        case .right: return "Slowly turn your head to the right."
        }
    }

    @discardableResult
    private func captureSample(for bucket: FacePoseBucket, observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) -> Bool {
        guard isFaceQualityAcceptable(observation) else {
            logger.debug("⚠️ captureSample aborted: Face quality standards not met.")
            return false
        }
        guard let faceprint = faceDataStore.generateEmbedding(for: observation, from: pixelBuffer) else {
            logger.debug("❌ captureSample aborted: Failed to generate faceprint embedding.")
            return false
        }

        if poseBucketSamples[bucket] == nil {
            poseBucketSamples[bucket] = []
        }
        poseBucketSamples[bucket]?.append(faceprint)

        DispatchQueue.main.async {
            self.registrationPoseCaptured.insert(bucket.rawValue)
            if let preparedImage = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) {
                self.processedRegImage = FaceProcessor.shared.makeUiImage(from: preparedImage)
            }
            let filled = FacePoseBucket.allCases.filter { self.poseBucketSamples[$0]?.isEmpty == false }.count
            self.registrationProgress = min(1.0, Double(filled) / Double(FacePoseBucket.allCases.count))
        }
        
        logger.debug("✅ Successfully captured sample for bucket: \(bucket.rawValue, privacy: .public)")
        return true
    }

    private func advanceToFinalizingRegistration() {
        currentRegistrationStep = .finalizing
        DispatchQueue.main.async {
            self.appState = .registering(.finalizing)
            self.updateInstruction()
        }
        completeRegistration()
    }

    private func completeRegistration() {
        guard let profileName = self.profileForRegistration else { return }

        var allFaceprints: [Faceprint] = []
        for bucket in FacePoseBucket.allCases {
            allFaceprints.append(contentsOf: poseBucketSamples[bucket] ?? [])
        }

        guard !allFaceprints.isEmpty else {
            DispatchQueue.main.async {
                self.userInstruction = "Couldn't capture enough angles. Try again with more light."
                self.currentRegistrationStep = .scanning
                self.appState = .registering(.scanning)
            }
            return
        }

        faceDataStore.register(faceprints: allFaceprints, forProfile: profileName)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.appState = .registeredAndIdle
            self.userInstruction = "Registration Complete!"
            self.isRegistrationMode = false
            self.profileForRegistration = nil
            self.stopCameraSession()
        }
    }

    private func updateInstruction() {
        DispatchQueue.main.async {
            if case .registering(let step) = self.appState {
                self.userInstruction = step.instruction
            }
        }
    }

    private func performAuthenticationChecks(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        guard isAuthenticating else { return }
        guard isFaceQualityAcceptable(observation) else {
            consecutiveMatchCount = 0
            similarityHistory.removeAll()
            return
        }

        isProcessingAuthFrame = true
        
        // Ensure static buffers are allocated prior to processing
        FaceDataStore.shared.allocateStaticBuffers()

        // Multi-Model Concurrency on Background Thread
        Task.detached(priority: .userInitiated) {
            
            // 1. CoreImage Similarity Alignment (GPU only) for Face Match
            guard let preparedFace = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) else {
                await self.finishAuthFrame()
                return
            }

            // 2. Full Center-Square Crop of the Widescreen Frame (Bypasses face detector coordinates entirely)
            guard let wideFace = FaceProcessor.shared.prepareFullSquareImage(from: pixelBuffer) else {
                await self.finishAuthFrame()
                return
            }
            
            // 3. Zero-Heap-Allocation CoreML Array Instantiation
            guard let faceArray = FaceDataStore.shared.preallocatedFaceArray112,
                  let livenessArray = FaceDataStore.shared.preallocatedLivenessArray128 else {
                await self.finishAuthFrame()
                return
            }
            
            // 4. Pre-allocated Static Buffer References
            guard let faceBuf = FaceDataStore.shared.faceBuffer112,
                  let liveBuf = FaceDataStore.shared.livenessBuffer128 else {
                await self.finishAuthFrame()
                return
            }
            
            // 5. Zero-Copy Fast Pointer preprocessing
            // - EdgeFace expects standard RGB (isBGR: false, isNormalizedTo01: false) scaled to 112x112 from tight crop
            // - MiniFAS expects standard RGB (isBGR: false, isNormalizedTo01: true) scaled to 128x128 from full center-square crop
            guard FaceDataStore.shared.preprocess(ciImage: preparedFace, size: 112, targetBuffer: faceBuf, targetArray: faceArray, isBGR: false, isNormalizedTo01: false),
                  FaceDataStore.shared.preprocess(ciImage: wideFace, size: 128, targetBuffer: liveBuf, targetArray: livenessArray, isBGR: false, isNormalizedTo01: true) else {
                await self.finishAuthFrame()
                return
            }
            
            // 6. Parallel Apple Neural Engine (ANE) Inference
            async let similarityScore = self.calculateFaceSimilarity(array: faceArray)
            async let livenessScore = self.calculateLiveness(array: livenessArray)
            
            let finalSimilarity = await similarityScore
            let finalLiveness = await livenessScore
            
            // 7. Temporal Scoring Matrix
            await MainActor.run {
                self.similarityHistory.append(finalSimilarity)
                if self.similarityHistory.count > self.temporalWindowSize {
                    self.similarityHistory.removeFirst()
                }
            }
            
            let smoothedFaceScore = await MainActor.run {
                self.similarityHistory.reduce(0.0, +) / Double(self.similarityHistory.count)
            }

            // 8. Dynamic Pose Compensation
            let yaw = abs(observation.yaw?.doubleValue ?? 0)
            let pitch = abs(observation.pitch?.doubleValue ?? 0)
            let poseOffset = (yaw * 0.04) + (pitch * 0.04)
            let dynamicUnlockThreshold = max(0.79, self.unlockThreshold - poseOffset)
            let dynamicInstantUnlockThreshold = max(0.87, self.instantUnlockThreshold - poseOffset)

            // OPTIMIZATION: Fast-Path Instant Bypass
            // If the current frame produces an exceptional match and liveness, we bypass the
            // temporal rolling window entirely to execute an instant unlock (<100ms).
            let isInstantSuccess = finalSimilarity >= dynamicInstantUnlockThreshold && finalLiveness >= 0.85

            let shouldUnlockInstantly = smoothedFaceScore >= dynamicInstantUnlockThreshold || isInstantSuccess
            let shouldUnlockWithConfirmation = smoothedFaceScore >= dynamicUnlockThreshold
            let requiredMatches = shouldUnlockInstantly ? 1 : self.consecutiveMatchesRequired

            await MainActor.run {
                guard self.isAuthenticating else { return }

                // Liveness Cutoff: 85% threshold using CelebA Spoof MiniFASNet weights
                let isGenuineFace = finalLiveness >= 0.85
                
                if isGenuineFace && (shouldUnlockInstantly || shouldUnlockWithConfirmation) {
                    if shouldUnlockInstantly {
                        self.consecutiveMatchCount = requiredMatches
                    } else {
                        self.consecutiveMatchCount += 1
                    }
                } else {
                    self.consecutiveMatchCount = 0
                }

                let authenticated = self.consecutiveMatchCount >= requiredMatches

                if authenticated {
                    self.logger.info("Auth success. Matching score: \(smoothedFaceScore), Liveness: \(finalLiveness)")
                    if smoothedFaceScore >= 0.90 {
                        FaceDataStore.shared.learnNewFaceprint(faceImage: FaceProcessor.shared.makeUiImage(from: preparedFace) ?? NSImage())
                    }
                    // Generate UI display image ONLY on success to conserve background CPU cycles
                    self.processedAuthImage = FaceProcessor.shared.makeUiImage(from: preparedFace)
                    self.similarityHistory.removeAll()
                    self.completeAuthentication(reason: "Face Match", faceScore: smoothedFaceScore)
                } else {
                    if !isGenuineFace && (shouldUnlockInstantly || shouldUnlockWithConfirmation) {
                        self.userInstruction = "Spoof Attempt Blocked."
                    } else {
                        let scoreStr = String(format: "Face: %.1f%%", smoothedFaceScore * 100)
                        if shouldUnlockWithConfirmation {
                            self.userInstruction = "Almost there... (\(scoreStr))"
                        } else {
                            self.userInstruction = "Verifying... (\(scoreStr))"
                        }
                    }
                }
                self.isProcessingAuthFrame = false
            }
        }
    }

    private func calculateFaceSimilarity(array: MLMultiArray) async -> Double {
        guard let embedding = try? MLModelManager.shared.predictEmbedding(from: array) else { return 0.0 }
        return FaceDataStore.shared.getSimilarityScore(from: embedding)
    }

    private func calculateLiveness(array: MLMultiArray) async -> Float {
        guard let score = try? MLModelManager.shared.predictLiveness(from: array) else { return 0.0 }
        return score
    }

    private func finishAuthFrame() async {
        await MainActor.run { self.isProcessingAuthFrame = false }
    }

    private func isFaceQualityAcceptable(_ observation: VNFaceObservation) -> Bool {
        let faceSize = observation.boundingBox.width * observation.boundingBox.height
        guard faceSize > 0.05 else {
            logger.debug("❌ Rejected: Face too small (\(faceSize))")
            return false
        }

        let yaw = abs(observation.yaw?.doubleValue ?? 0)
        let pitch = abs(observation.pitch?.doubleValue ?? 0)
        let roll = abs(observation.roll?.doubleValue ?? 0)
        
        guard yaw < 0.85 else {
            logger.debug("❌ Rejected: Yaw too high (\(yaw))")
            return false
        }
        guard pitch < 0.45 else {
            logger.debug("❌ Rejected: Pitch too high (\(pitch))")
            return false
        }
        
        // OPTIMIZATION: Loosened roll threshold from 0.45 to 1.1 radians (approx. 63 degrees).
        // Since our 5-point Similarity Transform solves for translation, scale, and in-plane
        // rotation (roll) in closed form, the face is automatically rotated right-side up
        // before embedding generation, making recognition fully invariant to head tilts.
        guard roll < 1.1 else {
            logger.debug("❌ Rejected: Roll too high (\(roll))")
            return false
        }

        if let quality = observation.faceCaptureQuality {
            let requiredQuality: Float = (yaw > 0.15) ? 0.12 : 0.15
            if quality < requiredQuality {
                logger.debug("❌ Rejected: Quality too low (\(quality) < required \(requiredQuality))")
                return false
            }
        }

        guard let landmarks = observation.landmarks else {
            logger.debug("❌ Rejected: Landmarks missing completely")
            return false
        }
        
        let hasAtLeastOneEye = landmarks.leftEye != nil || landmarks.rightEye != nil
        guard hasAtLeastOneEye, landmarks.nose != nil, landmarks.outerLips != nil else {
            logger.debug("❌ Rejected: Missing critical landmarks")
            return false
        }
        
        return true
    }

    private func completeAuthentication(reason: String, faceScore: Double) {
        guard isAuthenticating else { return }
        isAuthenticating = false
        consecutiveMatchCount = 0

        // IMMEDIATE HARDWARE SHUTDOWN OPTIMIZATION:
        // Disable the video connection and stop the capture session synchronously on this queue.
        // This cuts off frame delivery and turns off the camera hardware/green light
        // the exact millisecond authentication succeeds.
        if let connection = self.videoDataOutput.connection(with: .video) {
            connection.isEnabled = false
        }
        stopCameraSession()

        logger.info("✅ AUTHENTICATION SUCCESSFUL!")
        logger.info("   - Reason: \(reason, privacy: .public)")
        logger.info("   - Face Similarity: \(String(format: "%.3f (%.1f%%)", faceScore, faceScore * 100), privacy: .public)")

        DispatchQueue.main.async {
            self.appState = .recognized
            self.faceIsRecognized = true
            self.userInstruction = "Authenticated!"
            AuthenticationManager.shared.handleUnlock()
        }
    }
}

// MARK: - CoreGraphics Helper Extensions

extension CGRect {
    func lerp(to other: CGRect, alpha: CGFloat) -> CGRect {
        let x = self.origin.x + (other.origin.x - self.origin.x) * alpha
        let y = self.origin.y + (other.origin.y - self.origin.y) * alpha
        let width = self.width + (other.width - self.width) * alpha
        let height = self.height + (other.height - self.height) * alpha
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
