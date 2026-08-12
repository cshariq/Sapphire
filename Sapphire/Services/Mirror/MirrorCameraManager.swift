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
        Task { @MainActor in
            let granted = await requestPermissionIfNeeded()
            if !granted {
                self.status = .denied
                self.isTransitioning = false
                return
            }
            self.configureIfNeeded()
            self.startSession()
            self.isTransitioning = false
        }
    }

    func stop() {
        guard !isTransitioning else { return }
        isTransitioning = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in
                self.status = .idle
                self.isTransitioning = false
            }
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
        if let connection = session.outputs.compactMap({ $0.connection(with: .video) }).first {
            if connection.isVideoMirroringSupported {
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

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        sessionQueue.sync {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            if let existingInput = self.session.inputs.first as? AVCaptureDeviceInput {
                self.session.removeInput(existingInput)
            }

            guard let device = self.preferredDevice() else {
                Task { @MainActor in self.status = .error("No camera available.") }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.isConfigured = true
                    Task { @MainActor in
                        if let connection = self.session.outputs.compactMap({ $0.connection(with: .video) }).first {
                            connection.isVideoMirrored = self.currentMirrorSetting
                        }
                    }
                } else {
                    Task { @MainActor in self.status = .error("Unable to add camera input.") }
                }
            } catch {
                Task { @MainActor in self.status = .error(error.localizedDescription) }
            }
        }
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

    private func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
            Task { @MainActor in
                self.status = .live
            }
        }
    }

    func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}