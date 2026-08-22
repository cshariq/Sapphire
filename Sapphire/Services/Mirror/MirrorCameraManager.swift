//
//  MirrorCameraManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-11
//

import Foundation
import AVFoundation
import Combine
import AppKit

@MainActor
final class MirrorCameraManager: ObservableObject {

    static let shared = MirrorCameraManager()

    enum CameraStatus: Equatable {
        case idle
        case requestingPermission
        case denied
        case starting
        case live
        case error(String)
    }

    @Published private(set) var status: CameraStatus = .idle
    @Published private(set) var hasUsableCamera: Bool = false
    @Published private(set) var sessionEpoch: UInt64 = 0

    var isLive: Bool {
        if case .live = status { return true }
        return false
    }

    var isDenied: Bool {
        if case .denied = status { return true }
        return false
    }

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let msg) = status { return msg }
        return nil
    }

    let session: AVCaptureSession
    private let sessionQueue = DispatchQueue(label: "com.sapphire.mirrorSession", qos: .userInteractive)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var isTransitioning = false
    private var startGeneration: UInt64 = 0

    private init() {
        self.session = AVCaptureSession()
        refreshDeviceAvailability()
    }

    func refreshDeviceAvailability() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .front
        )
        let frontAvailable = !discovery.devices.isEmpty
        let anyAvailable = AVCaptureDevice.default(for: .video) != nil
        hasUsableCamera = frontAvailable || anyAvailable
    }

    func toggle() {
        switch status {
        case .idle, .denied, .error:
            start()
        case .live, .starting, .requestingPermission:
            stop()
        }
    }

    func start() {
        guard !isTransitioning else { return }
        isTransitioning = true
        status = .starting
        startGeneration &+= 1
        let generation = startGeneration

        Task { @MainActor in
            let granted = await requestPermissionIfNeeded()
            guard generation == self.startGeneration else {
                self.isTransitioning = false
                return
            }
            if !granted {
                self.status = .denied
                self.isTransitioning = false
                return
            }

            let configured = await self.reconfigureSession()
            guard generation == self.startGeneration else {
                self.isTransitioning = false
                return
            }
            guard configured else {
                self.isTransitioning = false
                return
            }

            self.startSession(generation: generation)
        }
    }

    func stop(force: Bool = false) {
        if isTransitioning && !force { return }
        isTransitioning = true
        startGeneration &+= 1
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.dismantleSessionLocked()
            Task { @MainActor in
                self.previewLayer = nil
                self.isConfigured = false
                self.status = .idle
                self.isTransitioning = false
            }
        }
    }

    func teardown() {
        MirrorFullscreenWindowController.shared.dismiss(destroy: true)
        stop(force: true)
    }

    func restartPreviewIfNeeded() {
        guard isLive else { return }
        startGeneration &+= 1
        let generation = startGeneration
        Task { @MainActor in
            _ = await self.reconfigureSession()
            guard generation == self.startGeneration else { return }
            self.startSession(generation: generation)
        }
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existing = previewLayer, existing.session === session {
            return existing
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer = layer
        return layer
    }

    func updateMirroring(flipHorizontally: Bool) {
        if let connection = previewLayer?.connection {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = flipHorizontally
            }
        }
    }

    // MARK: - Permission

    private func requestPermissionIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            self.status = .requestingPermission
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Configuration

    private func reconfigureSession() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.dismantleSessionLocked()

                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                guard let device = self.preferredDevice() else {
                    Task { @MainActor in
                        self.status = .error("No camera available.")
                        continuation.resume(returning: false)
                    }
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        Task { @MainActor in
                            self.status = .error("Unable to add camera input.")
                            continuation.resume(returning: false)
                        }
                        return
                    }
                    self.session.addInput(input)
                    Task { @MainActor in
                        self.isConfigured = true
                        self.sessionEpoch &+= 1
                        continuation.resume(returning: true)
                    }
                } catch {
                    Task { @MainActor in
                        self.status = .error(error.localizedDescription)
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    private func dismantleSessionLocked() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        session.commitConfiguration()
    }

    private var currentMirrorSetting: Bool {
        UserDefaults.standard.object(forKey: "mirrorFlipHorizontally") as? Bool ?? true
    }

    private func preferredDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .front
        )
        if let front = discovery.devices.first {
            return front
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func startSession(generation: UInt64) {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
            Task { @MainActor in
                guard generation == self.startGeneration else { return }
                self.status = .live
                self.isTransitioning = false
                self.updateMirroring(flipHorizontally: self.currentMirrorSetting)
            }
        }
    }

    func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}