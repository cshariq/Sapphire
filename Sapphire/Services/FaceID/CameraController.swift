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
enum CameraState: Equatable { case idle, registering(RegistrationStep), registeredAndIdle, detecting, recognized, authenticating }

class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, Identifiable {

    let id = UUID()
    @Published var appState: CameraState = .idle
    @Published var userInstruction: String = "Press 'Register' to begin."
    @Published var smoothedBoundingBox: CGRect?
    @Published var processedAuthImage: NSImage? = nil
    @Published var processedRegImage: NSImage? = nil
    @Published var registrationProgress: Double = 0.0

    let captureSession = AVCaptureSession()

    private var isAuthenticating = false
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.cshariq.Sapphire.sessionQueue", qos: .userInteractive)
    private let visionQueue = DispatchQueue(label: "com.cshariq.Sapphire.visionQueue", qos: .userInitiated)
    private let spoofDetector = SpoofDetector()
    private var currentRegistrationStep: RegistrationStep = .preparingFace
    private var sampleCounter = 0
    private let totalSamplesToCapture = 32
    private let registrationQualityThreshold: Float = 0.5
    private var stableFrameCounter = 0
    private let requiredStableFrames = 3
    private var registrationSamples: [(observation: VNFaceObservation, buffer: CVPixelBuffer)] = []
    private var profileForRegistration: String?

    override init() {
        super.init()
        setupSession()
        if FaceDataStore.shared.hasRegisteredFaceprints() {
            DispatchQueue.main.async {
                self.appState = .registeredAndIdle
                self.userInstruction = "Registered! Press Authenticate."
            }
        }
    }

    deinit {
        print("LOG (Memory): CameraController deinitializing.")
        videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func teardown() {
        print("LOG (AV): Tearing down CameraController explicitly...")

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.videoDataOutput.sampleBufferDelegate != nil {
                print("LOG (AV): Nullifying sample buffer delegate.")
                self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
            }

            if self.captureSession.isRunning {
                print("LOG (AV): Stopping capture session.")
                self.captureSession.beginConfiguration()
                self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }
                self.captureSession.outputs.forEach { self.captureSession.removeOutput($0) }
                self.captureSession.commitConfiguration()
                self.captureSession.stopRunning()
                print("LOG (AV): Capture session stopped and torn down.")
            }
        }
    }

    func startAuthentication() {
        guard !isAuthenticating else { return }
        MLModelManager.shared.loadModels()
        isAuthenticating = true
        DispatchQueue.main.async { self.appState = .authenticating; self.userInstruction = "Looking for your face..." }
        sessionQueue.async { if !self.captureSession.isRunning { self.captureSession.startRunning() } }
    }

    func startRegistration(forProfile name: String) {
        MLModelManager.shared.loadModels()
        profileForRegistration = name
        isAuthenticating = false
        registrationSamples.removeAll(); sampleCounter = 0; stableFrameCounter = 0
        DispatchQueue.main.async {
            self.registrationProgress = 0.0
            self.currentRegistrationStep = .preparingFace
            self.appState = .registering(self.currentRegistrationStep)
            self.updateInstruction()
        }
        sessionQueue.async { if !self.captureSession.isRunning { self.captureSession.startRunning() } }
    }

    private func setupSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else { return }
            do {
                let input = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(input) { self.captureSession.addInput(input) }
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
        guard isAuthenticating || profileForRegistration != nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                DispatchQueue.main.async { self.smoothedBoundingBox = nil }; return
            }
            if profileForRegistration != nil {
                handleSimplifiedRegistration(observation: observation, pixelBuffer: pixelBuffer)
            } else if isAuthenticating {
                Task { await performAuthenticationChecks(observation: observation, pixelBuffer: pixelBuffer) }
            }
        } catch { print("Face detection error: \(error)") }
    }

    private func handleSimplifiedRegistration(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) {
        let quality = observation.faceCaptureQuality ?? observation.confidence
        guard quality >= registrationQualityThreshold else { return }
        switch currentRegistrationStep {
        case .preparingFace:
            let boxCenter = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
            if sqrt(pow(boxCenter.x - 0.5, 2) + pow(boxCenter.y - 0.5, 2)) < 0.1 { stableFrameCounter += 1 } else { stableFrameCounter = 0 }
            if stableFrameCounter >= requiredStableFrames {
                DispatchQueue.main.async { self.currentRegistrationStep = .capturingFace; self.sampleCounter = 0; self.updateInstruction() }
            }
        case .capturingFace:
            if sampleCounter < totalSamplesToCapture {
                registrationSamples.append((observation, pixelBuffer)); sampleCounter += 1
                DispatchQueue.main.async { self.registrationProgress = Double(self.sampleCounter) / Double(self.totalSamplesToCapture) }
            } else { advanceToCompletion() }
        }
    }

    private func advanceToCompletion() {
        guard let profileName = profileForRegistration else { return }
        DispatchQueue.main.async { self.userInstruction = "Processing..." }
        FaceDataStore.shared.register(faceSamples: self.registrationSamples, forProfile: profileName)
        registrationSamples.removeAll(); profileForRegistration = nil
        DispatchQueue.main.async { self.appState = .registeredAndIdle; self.userInstruction = "Registration Complete!" }
    }

    private func performAuthenticationChecks(observation: VNFaceObservation, pixelBuffer: CVPixelBuffer) async {
        guard isAuthenticating, let preparedImage = FaceProcessor.shared.prepareImage(from: pixelBuffer, faceObservation: observation) else { return }
        let faceScore = FaceDataStore.shared.getSimilarityScore(for: preparedImage)
        if faceScore >= 0.90 { FaceDataStore.shared.learnNewFaceprint(faceImage: preparedImage) }
        guard faceScore >= 0.75 else { return }
        let depthScore = await FaceDataStore.shared.getDepthSimilarity(for: pixelBuffer)
        let metricsScore = FacialMetricsCalculator.calculateMetrics(from: observation).map { FaceDataStore.shared.getMetricsSimilarity(for: $0) } ?? 0.0
        if faceScore >= 0.8 && depthScore >= 0.75 && metricsScore >= 0.85 {
            await MainActor.run { self.completeAuthentication(reason: "Fast Lane Match") }; return
        }
        let spoofConfidence = spoofDetector.getSpoofConfidence(observation: observation, depthScore: depthScore, metricsScore: metricsScore, faceSimilarity: faceScore)
        if spoofConfidence != .low && (faceScore >= 0.85 || spoofConfidence == .high) {
            await MainActor.run { self.completeAuthentication(reason: "Confident Match") }
        }
    }

    private func completeAuthentication(reason: String) {
        guard isAuthenticating else { return }
        isAuthenticating = false
        print(" AUTHENTICATION SUCCESSFUL! Reason: \(reason)")
        DispatchQueue.main.async {
            self.appState = .recognized; self.userInstruction = "Authenticated!"
            AuthenticationManager.shared.handleUnlock()
        }
    }

    private func updateInstruction() {
        DispatchQueue.main.async {
            if self.profileForRegistration != nil {
                self.userInstruction = self.currentRegistrationStep == .capturingFace ? "Capturing... \(self.sampleCounter)/\(self.totalSamplesToCapture)" : self.currentRegistrationStep.instruction
            }
        }
    }
}