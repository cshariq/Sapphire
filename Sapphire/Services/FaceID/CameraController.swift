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
    case preparingFace, capturingFace
    var instruction: String {
        switch self {
        case .preparingFace: return "Position your face in the center of the frame."
        case .capturingFace: return "Capturing your face... Please hold still."
        }
    }
}

enum CameraState: Equatable {
    case idle, registering(RegistrationStep), registeredAndIdle, detecting, recognized, authenticating
}

class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

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

    public var faceDataStore = FaceDataStore()
    private let spoofDetector = SpoofDetector()

    private var currentRegistrationStep: RegistrationStep = .preparingFace
    private var sampleCounter = 0
    private let totalSamplesToCapture = 32
    private let registrationQualityThreshold: Float = 0.5

    private var stableFrameCounter = 0
    private var requiredStableFrames = 3
    private var registrationSamples: [(observation: VNFaceObservation, buffer: CVPixelBuffer)] = []

    private var captureCooldown = 0
    private let captureCooldownFrames = 2

    @Published var isRegistrationMode = false
    private var profileForRegistration: String?

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
        registrationSamples.removeAll()
        sampleCounter = 0
        stableFrameCounter = 0

        DispatchQueue.main.async {
            self.registrationProgress = 0.0
            self.currentRegistrationStep = .preparingFace
            self.appState = .registering(self.currentRegistrationStep)
            self.updateInstruction()
        }
        startCameraSession()
    }

    func reset() {
        isAuthenticating = false
        faceDataStore.reset()
        registrationSamples.removeAll()
        sampleCounter = 0
        stableFrameCounter = 0
        DispatchQueue.main.async {
            self.appState = .idle
            self.userInstruction = "Press 'Register' to begin."
            self.registrationProgress = 0.0
        }
    }

    func startSession() { startAuthentication() }
    func stopSession() { isAuthenticating = false; stopCameraSession() }
    func handleManualUnlock() {
        isAuthenticating = false
        if captureSession.isRunning { stopCameraSession() }
        DispatchQueue.main.async {
            if [.authenticating, .detecting, .recognized].contains(self.appState) {
                self.appState = .registeredAndIdle
                self.userInstruction = "Authentication stopped"
            }
        }
    }

    private func setupSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else { return }
            do {
                let deviceInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(deviceInput) { self.captureSession.addInput(deviceInput) }
            } catch { print("Camera setup failed: \(error)") }
            if self.captureSession.canSetSessionPreset(.hd1280x720) { self.captureSession.sessionPreset = .hd1280x720 }
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            if self.captureSession.canAddOutput(self.videoDataOutput) { self.captureSession.addOutput(self.videoDataOutput) }
            if let connection = self.videoDataOutput.connection(with: .video) { connection.isVideoMirrored = true }
            self.captureSession.commitConfiguration()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAuthenticating || isRegistrationMode, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                DispatchQueue.main.async { self.smoothedBoundingBox = nil }
                return
            }
            self.processFaceObservation(observation, pixelBuffer: pixelBuffer)
        } catch {  }
    }

    private func processFaceObservation(_ observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let newBox = observation.boundingBox
        DispatchQueue.main.async {
            if self.smoothedBoundingBox == nil { self.smoothedBoundingBox = newBox }
            else { self.smoothedBoundingBox = self.smoothedBoundingBox!.lerp(to: newBox, alpha: 0.2) }
        }

        switch self.appState {
        case .registering:
            handleSimplifiedRegistration(observation: observation, pixelBuffer: pixelBuffer)
        case .authenticating, .detecting, .recognized:
            performAuthenticationChecks(observation: observation, pixelBuffer: pixelBuffer)
        default: break
        }
    }

    private func handleSimplifiedRegistration(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        if captureCooldown > 0 { captureCooldown -= 1; return }

        let quality = observation.faceCaptureQuality ?? observation.confidence
        guard quality >= registrationQualityThreshold else {
            if currentRegistrationStep == .preparingFace {
                DispatchQueue.main.async { self.userInstruction = "Please improve lighting or move closer." }
            }
            return
        }

        switch currentRegistrationStep {
        case .preparingFace:
            let boxCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
            let isCentered = sqrt(pow(boxCenter.x - 0.5, 2) + pow(boxCenter.y - 0.5, 2)) < 0.1
            let isFacingForward = abs(observation.yaw?.doubleValue ?? 0) < 0.2 && abs(observation.pitch?.doubleValue ?? 0) < 0.2
            if isCentered && isFacingForward { stableFrameCounter += 1 } else { stableFrameCounter = 0 }

            DispatchQueue.main.async {
                self.userInstruction = self.stableFrameCounter > 0 ? "Hold position..." : "Please center your face and look forward."
            }

            if stableFrameCounter >= requiredStableFrames {
                currentRegistrationStep = .capturingFace
                DispatchQueue.main.async { self.appState = .registering(.capturingFace) }
                sampleCounter = 0
                updateInstruction()
            }

        case .capturingFace:
            captureSample(observation, pixelBuffer)
            if sampleCounter >= totalSamplesToCapture { advanceToCompletion() }
        }
    }

    private func captureSample(_ observation: VNFaceObservation, _ buffer: CVPixelBuffer) {
        sampleCounter += 1
        registrationSamples.append((observation, buffer))
        captureCooldown = captureCooldownFrames

        DispatchQueue.main.async {
            self.registrationProgress = Double(self.sampleCounter) / Double(self.totalSamplesToCapture)
            self.updateInstruction()
        }

        if let preparedImage = FaceProcessor.shared.prepareImage(from: buffer, faceObservation: observation) {
            DispatchQueue.main.async { self.processedRegImage = preparedImage }
        }
    }

    private func advanceToCompletion() {
        guard let profileName = self.profileForRegistration else {
            print(" CRITICAL: Tried to complete registration without a profile name.")
            return
        }
        DispatchQueue.main.async { self.userInstruction = "Processing..." }
        faceDataStore.register(faceSamples: self.registrationSamples, forProfile: profileName)
        DispatchQueue.main.async {
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
                self.userInstruction = step == .capturingFace ? "Capturing... \(self.sampleCounter)/\(self.totalSamplesToCapture)" : step.instruction
            }
        }
    }

    private func performAuthenticationChecks(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        guard isAuthenticating, let preparedImage = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) else { return }

        let faceScore = faceDataStore.getSimilarityScore(for: preparedImage)

        if faceScore >= 0.90 {
            print(" High-confidence match (\(String(format: "%.2f", faceScore * 100))%). Learning face variation.")
            faceDataStore.learnNewFaceprint(faceImage: preparedImage)
        }

        let mediumConfidenceThreshold: Double = 0.75
        guard faceScore >= mediumConfidenceThreshold else { return }

        let metricsScore = FacialMetricsCalculator.calculateMetrics(from: observation).map { faceDataStore.getMetricsSimilarity(for: $0) } ?? 0.0
        let depthScore = faceDataStore.getDepthSimilarity(for: pixelBuffer)

        let excellentFaceScoreThreshold: Double = 0.8
        let excellentDepthScoreThreshold: Double = 0.75
        let excellentmetricsScoreThreshold: Double = 0.85

        if faceScore >= excellentFaceScoreThreshold && depthScore >= excellentDepthScoreThreshold && metricsScore >= excellentmetricsScoreThreshold{
            DispatchQueue.main.async {
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

        DispatchQueue.main.async {
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.stopCameraSession()
            }
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