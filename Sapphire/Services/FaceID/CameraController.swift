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

enum RegistrationStep: CaseIterable, Equatable {
    case preparingFace
    case turnHeadLeft
    case turnHeadRight
    case finalizing

    var instruction: String {
        switch self {
        case .preparingFace: return "Position your face in the center of the frame."
        case .turnHeadLeft: return "Slowly turn your head to the right."
        case .turnHeadRight: return "Now, slowly turn your head to the left."
        case .finalizing: return "Processing your facial data..."
        }
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
    @Published var currentDepthScore: Double = 0.0
    @Published var currentMetricsScore: Double = 0.0
    @Published var cameraError: String? = nil
    @Published var registrationProgress: Double = 0.0

    private var isAuthenticating = false

    let captureSession = AVCaptureSession()

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.cshariq.Sapphire.sessionQueue", qos: .userInteractive)
    private let visionQueue = DispatchQueue(label: "com.cshariq.Sapphire.visionQueue", qos: .userInitiated)

    public var faceDataStore = FaceDataStore.shared
    private let spoofDetector = SpoofDetector()
    private var depthDetector = DepthDetector()

    private var currentRegistrationStep: RegistrationStep = .preparingFace

    private let samplesPerPose = 5
    private var poseSamples: [RegistrationStep: [(Faceprint, FacialMetricSet)]] = [:]
    private var currentPoseSampleCount = 0
    private let requiredPoseAngle: Double = 0.3

    private var registrationDepthBuffers: [CVPixelBuffer] = []
    private let totalDepthSamplesToCapture = 5

    @Published var isRegistrationMode = false
    private var profileForRegistration: String?

    private func setupSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
                print("Error: Could not find a suitable video device.")
                return
            }
            do {
                let deviceInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(deviceInput) { self.captureSession.addInput(deviceInput) }
            } catch {
                print("Camera setup failed: \(error)")
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
            if let primaryProfile = faceDataStore.getRegisteredProfileNames().first {
                let maps = faceDataStore.getSerializedDepthMaps(forProfile: primaryProfile)
                depthDetector.loadDepthMaps(from: maps)
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
        profileForRegistration = nil

        poseSamples.removeAll()
        registrationDepthBuffers.removeAll()
        currentPoseSampleCount = 0

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
        print("LOG (CameraController): Teardown complete.")
    }

    func startAuthentication() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        DispatchQueue.main.async {
            self.appState = .authenticating
            self.userInstruction = "Looking for your face..."
        }
        startCameraSession()
    }

    func startRegistration(forProfile name: String) {
        isRegistrationMode = true
        self.profileForRegistration = name

        poseSamples.removeAll()
        registrationDepthBuffers.removeAll()
        currentPoseSampleCount = 0

        DispatchQueue.main.async {
            self.registrationProgress = 0.0
            self.currentRegistrationStep = .preparingFace
            self.appState = .registering(self.currentRegistrationStep)
            self.updateInstruction()
        }
        startCameraSession()
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAuthenticating || isRegistrationMode, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                DispatchQueue.main.async { self.smoothedBoundingBox = nil }
                return
            }

            processFaceObservation(observation, pixelBuffer: pixelBuffer)

        } catch {
            print("Error performing face detection: \(error)")
        }
    }

    private func processFaceObservation(_ observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let newBox = observation.boundingBox
        DispatchQueue.main.async {
            if self.smoothedBoundingBox == nil { self.smoothedBoundingBox = newBox }
            else { self.smoothedBoundingBox = self.smoothedBoundingBox!.lerp(to: newBox, alpha: 0.2) }
        }

        if isRegistrationMode {
            handleRegistrationStep(observation: observation, pixelBuffer: pixelBuffer)
        } else if isAuthenticating {
            Task {
                await performAuthenticationChecks(observation: observation, pixelBuffer: pixelBuffer)
            }
        }
    }

    private func handleRegistrationStep(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let yaw = observation.yaw?.doubleValue ?? 0
        let pitch = observation.pitch?.doubleValue ?? 0

        var poseAchieved = false

        switch currentRegistrationStep {
        case .preparingFace:
            let isCentered = abs(yaw) < 0.2 && abs(pitch) < 0.2
            if isCentered { poseAchieved = true }

        case .turnHeadLeft:
            if yaw > requiredPoseAngle { poseAchieved = true }

        case .turnHeadRight:
            if yaw < -requiredPoseAngle { poseAchieved = true }

        case .finalizing:
            return
        }

        if poseAchieved {
            captureSampleForCurrentPose(observation, pixelBuffer)
        }
    }

    private func captureSampleForCurrentPose(_ observation: VNFaceObservation, _ buffer: CVPixelBuffer) {
        guard let faceprint = faceDataStore.generateEmbedding(for: observation, from: buffer),
              let metrics = FacialMetricsCalculator.calculateMetrics(from: observation) else {
            return
        }

        if poseSamples[currentRegistrationStep] == nil {
            poseSamples[currentRegistrationStep] = []
        }

        poseSamples[currentRegistrationStep]?.append((faceprint, metrics))
        currentPoseSampleCount += 1

        if registrationDepthBuffers.count < totalDepthSamplesToCapture && (poseSamples.count + currentPoseSampleCount) % samplesPerPose == 0 {
            registrationDepthBuffers.append(buffer)
        }

        let totalSteps = Double(RegistrationStep.allCases.count - 2)
        let completedSteps = Double(poseSamples.keys.count - 1)
        let progressInCurrentStep = Double(currentPoseSampleCount) / Double(samplesPerPose)
        let totalProgress = (completedSteps + progressInCurrentStep) / totalSteps

        DispatchQueue.main.async {
            self.registrationProgress = totalProgress
            if let preparedImage = FaceProcessor.shared.prepareImage(from: buffer, faceObservation: observation) {
                self.processedRegImage = preparedImage
            }
        }

        if currentPoseSampleCount >= samplesPerPose {
            advanceToNextRegistrationStep()
        }
    }

    private func advanceToNextRegistrationStep() {
        currentPoseSampleCount = 0

        let allSteps = RegistrationStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentRegistrationStep) else { return }

        let nextIndex = currentIndex + 1
        if nextIndex < allSteps.count {
            let nextStep = allSteps[nextIndex]
            currentRegistrationStep = nextStep

            if nextStep == .finalizing {
                completeRegistration()
            }

            DispatchQueue.main.async {
                self.appState = .registering(self.currentRegistrationStep)
                self.updateInstruction()
            }
        }
    }

    private func completeRegistration() {
        guard let profileName = self.profileForRegistration else { return }

        var allFaceprints: [Faceprint] = []
        var allMetrics: [FacialMetricSet] = []

        for (_, samples) in poseSamples {
            allFaceprints.append(contentsOf: samples.map { $0.0 })
            allMetrics.append(contentsOf: samples.map { $0.1 })
        }

        faceDataStore.register(
            faceprints: allFaceprints,
            metrics: allMetrics,
            depthBuffers: registrationDepthBuffers,
            forProfile: profileName
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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

    private func performAuthenticationChecks(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) async {
        guard isAuthenticating, let preparedImage = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) else { return }

        let faceScore = faceDataStore.getSimilarityScore(for: preparedImage)

        if faceScore >= 0.90 {
            print(" High-confidence match (\(String(format: "%.2f", faceScore * 100))%). Learning face variation.")
            faceDataStore.learnNewFaceprint(faceImage: preparedImage)
        }

        let mediumConfidenceThreshold: Double = 0.75
        guard faceScore >= mediumConfidenceThreshold else { return }

        let depthScore = await depthDetector.getDepthSimilarity(for: pixelBuffer)
        let metricsScore = FacialMetricsCalculator.calculateMetrics(from: observation).map { faceDataStore.getMetricsSimilarity(for: $0) } ?? 0.0

        let excellentFaceScoreThreshold: Double = 0.8
        let excellentDepthScoreThreshold: Double = 0.75
        let excellentmetricsScoreThreshold: Double = 0.85

        if faceScore >= excellentFaceScoreThreshold && depthScore >= excellentDepthScoreThreshold && metricsScore >= excellentmetricsScoreThreshold{
            await MainActor.run {
                self.completeAuthentication(reason: "Fast Lane Match", faceScore: faceScore, metricsScore: metricsScore, depthScore: depthScore)
            }
            return
        }

        let spoofConfidence = spoofDetector.getSpoofConfidence(observation: observation, depthScore: depthScore, metricsScore: metricsScore, faceSimilarity: faceScore)
        let highConfidenceThreshold: Double = 0.85

        var authenticated = false
        var reason = "No Match"

        if spoofConfidence != .low {
            if faceScore >= highConfidenceThreshold {
                authenticated = true
                reason = "Excellent Match"
            } else if spoofConfidence == .high {
                authenticated = true
                reason = "Confident Match (Verified)"
            }
        } else {
            reason = "Spoof Detected"
        }

        await MainActor.run {
            guard self.isAuthenticating else { return }
            self.currentMetricsScore = metricsScore
            self.currentDepthScore = depthScore
            self.processedAuthImage = preparedImage

            if authenticated {
                self.completeAuthentication(reason: reason, faceScore: faceScore, metricsScore: metricsScore, depthScore: depthScore)
            } else {
                let scoreStr = String(format: "Face: %.2f", faceScore)
                self.userInstruction = "Verifying... (\(scoreStr))"
            }
        }
    }

    private func completeAuthentication(reason: String, faceScore: Double, metricsScore: Double, depthScore: Double) {
        guard isAuthenticating else { return }
        isAuthenticating = false

        print(" AUTHENTICATION SUCCESSFUL!")
        print("   - Reason: \(reason)")
        print("   - Final Scores:")
        print(String(format: "     - Face Similarity: %.3f", faceScore))
        print(String(format: "     - Facial Metrics:  %.3f", metricsScore))
        print(String(format: "     - Depth Score:     %.3f", depthScore))
        print("-------------------------------------------------")

        DispatchQueue.main.async {
            self.appState = .recognized
            self.faceIsRecognized = true
            self.userInstruction = "Authenticated!"
            AuthenticationManager.shared.handleUnlock()

        }
    }
}

extension CGRect {
    func lerp(to other: CGRect, alpha: CGFloat) -> CGRect {
        let x = self.origin.x + (other.origin.x - self.origin.x) * alpha
        let y = self.origin.y + (other.origin.y - self.origin.y) * alpha
        let width = self.width + (other.width - self.width) * alpha
        let height = self.height + (other.height - self.height) * alpha
        return CGRect(x: x, y: y, width: width, height: height)
    }
}