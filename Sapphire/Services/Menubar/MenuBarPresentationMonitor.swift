//
//  MenuBarPresentationMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27
//

import AppKit
import Combine
import CoreMediaIO
import Darwin
import os

@MainActor
final class MenuBarPresentationMonitor {
    private struct Configuration: Equatable {
        let whilePresenting: Bool
        let whileCameraInUse: Bool
    }

    private static let sharingPollInterval: TimeInterval = 5
    private static let cameraHoldDelay: TimeInterval = 3

    private let onChange: (Bool) -> Void
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MenuBarPresentation")

    private var configuration = Configuration(whilePresenting: false, whileCameraInUse: false)
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var sharingTimer: Timer?
    private var cameraHoldTimer: Timer?
    private var camera: CameraUsageObserver?

    private var isMirroring = false
    private var isSharing = false
    private var isCameraEngaged = false
    private var isEngaged = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard cancellables.isEmpty else { return }
        SettingsModel.shared.$settings
            .map { Configuration(whilePresenting: $0.menuBarAutoZenWhilePresenting, whileCameraInUse: $0.menuBarAutoZenWhileCameraInUse) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configuration in self?.apply(configuration) }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        apply(Configuration(whilePresenting: false, whileCameraInUse: false))
    }

    private func apply(_ configuration: Configuration) {
        self.configuration = configuration

        if configuration.whilePresenting {
            startPresentationSignals()
        } else {
            stopPresentationSignals()
        }

        if configuration.whileCameraInUse, camera == nil {
            let observer = CameraUsageObserver { [weak self] inUse in self?.cameraUsageChanged(inUse) }
            camera = observer
            observer.start()
        } else if !configuration.whileCameraInUse, let camera {
            camera.stop()
            self.camera = nil
            cameraHoldTimer?.invalidate()
            cameraHoldTimer = nil
            isCameraEngaged = false
        }

        evaluate()
    }

    // MARK: - Mirroring and Screen Sharing

    private func startPresentationSignals() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isMirroring = Self.anyDisplayMirrored()
                self.evaluate()
            }
        }
        isMirroring = Self.anyDisplayMirrored()

        let timer = Timer(timeInterval: Self.sharingPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleScreenSharing() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        sharingTimer = timer
        sampleScreenSharing()
    }

    private func stopPresentationSignals() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        sharingTimer?.invalidate()
        sharingTimer = nil
        isMirroring = false
        isSharing = false
    }

    private func sampleScreenSharing() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let sharing = Self.isProcessRunning(named: "screensharingd")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.sharingTimer != nil, sharing != self.isSharing else { return }
                    self.isSharing = sharing
                    self.evaluate()
                }
            }
        }
    }

    private static func anyDisplayMirrored() -> Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsInMirrorSet(id) != 0
        }
    }

    private nonisolated static func isProcessRunning(named name: String) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return false }
            let capacity = size / MemoryLayout<kinfo_proc>.stride + 16
            var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var readSize = capacity * MemoryLayout<kinfo_proc>.stride
            guard sysctl(&mib, 4, &processes, &readSize, nil, 0) == 0 else { continue }
            let count = readSize / MemoryLayout<kinfo_proc>.stride
            for index in 0..<count {
                var comm = processes[index].kp_proc.p_comm
                let matches = withUnsafeBytes(of: &comm) { raw in
                    String(cString: raw.bindMemory(to: CChar.self).baseAddress!) == name
                }
                if matches { return true }
            }
            return false
        }
        return false
    }

    // MARK: - Camera

    private func cameraUsageChanged(_ inUse: Bool) {
        cameraHoldTimer?.invalidate()
        cameraHoldTimer = nil
        guard inUse else {
            isCameraEngaged = false
            evaluate()
            return
        }
        let timer = Timer(timeInterval: Self.cameraHoldDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.camera?.isInUse == true else { return }
                self.isCameraEngaged = true
                self.evaluate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cameraHoldTimer = timer
    }

    // MARK: - Decision

    private func evaluate() {
        let engaged = (configuration.whilePresenting && (isMirroring || isSharing))
            || (configuration.whileCameraInUse && isCameraEngaged)
        guard engaged != isEngaged else { return }
        isEngaged = engaged
        log.info("Presenter mode \(engaged ? "engaging" : "withdrawing") Zen mode (mirroring: \(self.isMirroring), sharing: \(self.isSharing), camera: \(self.isCameraEngaged))")
        onChange(engaged)
    }
}

// MARK: - Camera usage

@MainActor
private final class CameraUsageObserver {
    private let onChange: (Bool) -> Void
    private var deviceListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var deviceListListener: CMIOObjectPropertyListenerBlock?
    private(set) var isInUse = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        var address = Self.address(kCMIOHardwarePropertyDevices)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshDevices() }
        }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block) == 0 {
            deviceListListener = block
        }
        refreshDevices()
    }

    func stop() {
        if let block = deviceListListener {
            var address = Self.address(kCMIOHardwarePropertyDevices)
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block)
            deviceListListener = nil
        }
        for id in Array(deviceListeners.keys) { removeListener(from: id) }
        isInUse = false
    }

    private func refreshDevices() {
        let devices = Set(Self.deviceIDs())
        for id in deviceListeners.keys where !devices.contains(id) { removeListener(from: id) }
        for id in devices where deviceListeners[id] == nil {
            var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            }
            if CMIOObjectAddPropertyListenerBlock(id, &address, .main, block) == 0 {
                deviceListeners[id] = block
            }
        }
        update()
    }

    private func removeListener(from id: CMIOObjectID) {
        guard let block = deviceListeners.removeValue(forKey: id) else { return }
        var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        CMIOObjectRemovePropertyListenerBlock(id, &address, .main, block)
    }

    private func update() {
        let inUse = deviceListeners.keys.contains { Self.isRunningSomewhere($0) }
        guard inUse != isInUse else { return }
        isInUse = inUse
        onChange(inUse)
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func deviceIDs() -> [CMIOObjectID] {
        var address = address(kCMIOHardwarePropertyDevices)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == 0 else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func isRunningSomewhere(_ id: CMIOObjectID) -> Bool {
        var address = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == 0 else { return false }
        return value != 0
    }
}