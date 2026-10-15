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
import os

@MainActor
final class MirrorCameraManager: ObservableObject {

    static var shared: MirrorCameraManager {
        if let existing { return existing }
        let manager = MirrorCameraManager()
        existing = manager
        return manager
    }

    private(set) static var existing: MirrorCameraManager?

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
    @Published private(set) var automaticPreviewRotationAngle: CGFloat = 0
    @Published private(set) var automaticCaptureRotationAngle: CGFloat = 0
    @Published private(set) var cameras: [MirrorCameraOption] = []
    @Published private(set) var activeCameraID: String?
    @Published private(set) var preferredCameraID: String?

    var effectivePreviewRotationAngle: CGFloat {
        if let angle = SettingsModel.shared.current.mirrorRotationMode.angle {
            return angle
        }
        return automaticPreviewRotationAngle
    }

    private func isExternalCamera(_ device: AVCaptureDevice) -> Bool {
        let transport = device.transportType
        return transport != DeviceTransportType.builtIn
            && transport != DeviceTransportType.airPlay
            && transport != DeviceTransportType.virtual
    }

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

    var isPending: Bool {
        status == .starting || status == .requestingPermission
    }

    var errorMessage: String? {
        if case .error(let msg) = status { return msg }
        return nil
    }

    var session: AVCaptureSession { worker.session }

    private let worker = MirrorSessionWorker()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var generation: UInt64 = 0
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    private var deviceObservers: [NSObjectProtocol] = []

    private enum DeviceTransportType {
        static let builtIn: Int32 = 1
        static let airPlay: Int32 = 6
        static let virtual: Int32 = 7
    }

    private init() {
        preferredCameraID = UserDefaults.standard.string(forKey: MirrorSessionWorker.preferredCameraDefaultsKey)
        refreshDeviceAvailability()
    }

    func refreshDeviceAvailability() {
        let worker = worker
        worker.queue.async {
            let discovery = MirrorSessionWorker.discover()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MirrorCameraManager.existing?.applyDiscovery(discovery)
                }
            }
        }
    }

    private func applyDiscovery(_ discovery: MirrorSessionWorker.Discovery) {
        if cameras != discovery.options {
            cameras = discovery.options
        }
        let usable = !discovery.options.isEmpty || discovery.systemDefaultID != nil
        if hasUsableCamera != usable {
            hasUsableCamera = usable
        }
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
        guard !isLive, !isPending else { return }
        beginDeviceMonitoring()

        let generation = advanceGeneration()
        status = .starting

        Task { @MainActor in
            guard generation == self.generation else { return }
            let granted = await self.requestPermissionIfNeeded(generation: generation)
            guard generation == self.generation else { return }
            guard granted else {
                self.status = .denied
                return
            }
            self.status = .starting
            self.configureAndStart(generation: generation)
        }
    }

    func stop() {
        advanceGeneration()
        teardownRotationCoordinator()
        previewLayer = nil
        activeCameraID = nil
        status = .idle
        let worker = worker
        worker.queue.async {
            worker.dismantle()
        }
    }

    func cancelPendingStart() {
        guard isPending else { return }
        stop()
    }

    func teardown() {
        MirrorFullscreenWindowController.shared.dismiss(destroy: true)
        stop()
        endDeviceMonitoring()
    }

    func restartPreviewIfNeeded() {
        guard isLive else { return }
        configureAndStart(generation: advanceGeneration())
    }

    func selectCamera(id: String) {
        guard preferredCameraID != id else { return }
        preferredCameraID = id
        UserDefaults.standard.set(id, forKey: MirrorSessionWorker.preferredCameraDefaultsKey)
        if isLive, activeCameraID != id {
            restartPreviewIfNeeded()
        }
    }

    @discardableResult
    private func advanceGeneration() -> UInt64 {
        generation &+= 1
        worker.setCurrentGeneration(generation)
        return generation
    }

    // MARK: - Hot-plug

    private func beginDeviceMonitoring() {
        guard deviceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let device = notification.object as? AVCaptureDevice,
                      device.hasMediaType(.video) || device.hasMediaType(.muxed) else { return }
                MainActor.assumeIsolated {
                    MirrorCameraManager.existing?.videoDevicesChanged()
                }
            }
            deviceObservers.append(observer)
        }
        refreshDeviceAvailability()
    }

    private func endDeviceMonitoring() {
        for observer in deviceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        deviceObservers.removeAll()
    }

    private func videoDevicesChanged() {
        let worker = worker
        worker.queue.async {
            let discovery = MirrorSessionWorker.discover()
            let resolved = MirrorCameraSelection.resolve(
                rememberedID: MirrorSessionWorker.rememberedCameraID(),
                options: discovery.options,
                systemDefaultID: discovery.systemDefaultID
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let manager = MirrorCameraManager.existing else { return }
                    manager.applyDiscovery(discovery)
                    if manager.isLive,
                       MirrorCameraSelection.shouldReconfigure(activeID: manager.activeCameraID, resolvedID: resolved) {
                        manager.restartPreviewIfNeeded()
                    }
                }
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
        if let connection = previewLayer?.connection {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = flipHorizontally
            }
        }
    }

    // MARK: - Rotation

    private func setupRotationCoordinator(for device: AVCaptureDevice) {
        teardownRotationCoordinator()
        guard isExternalCamera(device) else {
            automaticPreviewRotationAngle = 0
            automaticCaptureRotationAngle = 0
            return
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator

        let observation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor in
                self?.automaticPreviewRotationAngle = angle
                self?.automaticCaptureRotationAngle = angle
            }
        }
        rotationObservations = [observation]
    }

    private func teardownRotationCoordinator() {
        rotationObservations.removeAll()
        rotationCoordinator = nil
    }

    // MARK: - Permission

    private func requestPermissionIfNeeded(generation: UInt64) async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            if generation == self.generation {
                self.status = .requestingPermission
            }
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

    private func configureAndStart(generation: UInt64) {
        let worker = worker
        worker.queue.async {
            let result = worker.configureAndStart(generation: generation)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MirrorCameraManager.existing?.applyStartResult(result, generation: generation)
                }
            }
        }
    }

    private func applyStartResult(_ result: MirrorSessionWorker.StartResult, generation: UInt64) {
        guard generation == self.generation else { return }
        switch result {
        case .stale:
            return
        case .started(let deviceID, let discovery):
            applyDiscovery(discovery)
            activeCameraID = deviceID
            if let device = AVCaptureDevice(uniqueID: deviceID) {
                setupRotationCoordinator(for: device)
            } else {
                teardownRotationCoordinator()
            }
            sessionEpoch &+= 1
            status = .live
            updateMirroring(flipHorizontally: currentMirrorSetting)
        case .failed(let message, let discovery):
            applyDiscovery(discovery)
            activeCameraID = nil
            teardownRotationCoordinator()
            status = .error(message)
        }
    }

    private var currentMirrorSetting: Bool {
        SettingsModel.shared.current.mirrorFlipHorizontally
    }

    func openSystemPrivacySettings() {
        SystemPreferencesPane.camera.open()
    }
}

// MARK: - Session worker

private final class MirrorSessionWorker: @unchecked Sendable {
    static let preferredCameraDefaultsKey = "MirrorCamera.preferredUniqueID"

    struct Discovery: Sendable {
        let options: [MirrorCameraOption]
        let systemDefaultID: String?
    }

    enum StartResult: Sendable {
        case started(deviceID: String, discovery: Discovery)
        case failed(String, discovery: Discovery)
        case stale
    }

    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "com.sapphire.mirrorSession", qos: .userInitiated)
    private let currentGeneration = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    func setCurrentGeneration(_ generation: UInt64) {
        currentGeneration.withLock { $0 = generation }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        currentGeneration.withLock { $0 == generation }
    }

    static func rememberedCameraID() -> String? {
        UserDefaults.standard.string(forKey: preferredCameraDefaultsKey)
    }

    static func discover() -> Discovery {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        let options = discovery.devices
            .filter { $0.isConnected && !$0.isSuspended }
            .map {
                MirrorCameraOption(
                    id: $0.uniqueID,
                    name: $0.localizedName,
                    isBuiltIn: $0.deviceType == .builtInWideAngleCamera,
                    isFrontFacing: $0.position == .front
                )
            }
        return Discovery(options: options, systemDefaultID: AVCaptureDevice.default(for: .video)?.uniqueID)
    }

    func configureAndStart(generation: UInt64) -> StartResult {
        guard isCurrent(generation) else { return .stale }

        let discovery = Self.discover()
        dismantle()

        guard let deviceID = MirrorCameraSelection.resolve(
            rememberedID: Self.rememberedCameraID(),
            options: discovery.options,
            systemDefaultID: discovery.systemDefaultID
        ), let device = AVCaptureDevice(uniqueID: deviceID) else {
            return .failed("No camera available.", discovery: discovery)
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            return .failed(error.localizedDescription, discovery: discovery)
        }

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return .failed("Unable to add camera input.", discovery: discovery)
        }
        session.addInput(input)
        session.commitConfiguration()

        guard isCurrent(generation) else {
            dismantle()
            return .stale
        }
        session.startRunning()
        guard isCurrent(generation) else {
            dismantle()
            return .stale
        }
        guard session.isRunning else {
            dismantle()
            return .failed("The camera could not be started. It may be in use by another app.", discovery: discovery)
        }
        return .started(deviceID: deviceID, discovery: discovery)
    }

    func dismantle() {
        if session.isRunning {
            session.stopRunning()
        }
        guard !session.inputs.isEmpty || !session.outputs.isEmpty else { return }
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        session.commitConfiguration()
    }
}