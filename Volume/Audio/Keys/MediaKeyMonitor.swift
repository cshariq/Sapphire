//
//  MediaKeyMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import AudioToolbox
import CoreGraphics
import os

@MainActor
final class MediaKeyMonitor {
    // MARK: - Collaborators

    private let decoder: any MediaKeyEventDecoding
    private let audioEngine: AudioEngine
    private let settingsManager: SettingsManager
    private let accessibility: any AccessibilityTrustProviding
    private let hudController: HUDWindowController
    private let popupVisibility: PopupVisibilityService
    private let mediaKeyStatus: MediaKeyStatus
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "MediaKeyMonitor")

    private let volumeStep: Float = 1.0 / 16.0

    // MARK: - Tap state

    private var tapToken: GlobalEventTap.Token?

    private nonisolated let handlerStateLock = NSLock()
    private nonisolated(unsafe) var mediaKeysEnabled = false

    private var disableWatchdogTask: Task<Void, Never>?
    private(set) var watchdogOpen: Bool = false

    var lastDDCRepeatTime: DispatchTime?

    private var ghostTapProbeTask: Task<Void, Never>?

    private var workspaceObservers: [NSObjectProtocol] = []

    var onRunLoopSourceRemoved: (() -> Void)?

    var iconCoordinator: MenuBarIconCoordinator?

    init(
        decoder: any MediaKeyEventDecoding,
        audioEngine: AudioEngine,
        settingsManager: SettingsManager,
        accessibility: any AccessibilityTrustProviding,
        hudController: HUDWindowController,
        popupVisibility: PopupVisibilityService,
        mediaKeyStatus: MediaKeyStatus
    ) {
        self.decoder = decoder
        self.audioEngine = audioEngine
        self.settingsManager = settingsManager
        self.accessibility = accessibility
        self.hudController = hudController
        self.popupVisibility = popupVisibility
        self.mediaKeyStatus = mediaKeyStatus
        subscribeToWorkspaceLifecycle()
    }

    deinit {
        if let tapToken {
            GlobalEventTap.shared.unregister(tapToken)
        }
        let nc = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { nc.removeObserver(observer) }
    }

    // MARK: - Lifecycle

    func start() {
        guard tapToken == nil else { return }
        guard settingsManager.appSettings.mediaKeyControlEnabled else {
            logger.debug("Media key control disabled in settings; handler not registered")
            return
        }
        guard accessibility.isTrusted else {
            logger.info("Accessibility not trusted; handler not registered")
            return
        }

        setMediaKeysEnabled(true)

        let selfRef = self
        tapToken = GlobalEventTap.shared.register(
            name: "MediaKeyMonitor",
            mask: CGEventMask(1) << CGEventMask(NX_SYSDEFINED),
            priority: EventTapPriority.media
        ) { _, event in
            selfRef.handleTapEvent(event) ? .swallow : .pass
        }

        mediaKeyStatus.isOffline = !GlobalEventTap.shared.isActive
        logger.info("Media key handler registered on the shared event tap")
    }

    func reconcile() {
        if settingsManager.appSettings.mediaKeyControlEnabled && accessibility.isTrusted {
            let wasOffline = (tapToken == nil)
            start()
            if wasOffline && tapToken != nil {
                armGhostTapProbe()
            }
        } else {
            cancelGhostTapProbe()
            stop()
        }
    }

    // MARK: - Workspace lifecycle (sleep/wake, session)

    private func subscribeToWorkspaceLifecycle() {
        let nc = NSWorkspace.shared.notificationCenter
        func add(_ name: Notification.Name, _ handler: @escaping () -> Void) {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
            workspaceObservers.append(token)
        }
        add(NSWorkspace.didWakeNotification) { [weak self] in self?.handleWake() }
        add(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.handleWake() }
        add(NSWorkspace.willSleepNotification) { [weak self] in self?.handleSuspend() }
        add(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.handleSuspend() }
    }

    private func handleWake() {
        guard let tapToken else {
            reconcile()
            return
        }
        setMediaKeysEnabled(true)
        GlobalEventTap.shared.setEnabled(tapToken, true)
        logger.info("Media key handler re-armed after wake / session activation")
        armGhostTapProbe()
    }

    private func handleSuspend() {
        guard let tapToken else { return }
        setMediaKeysEnabled(false)
        GlobalEventTap.shared.setEnabled(tapToken, false)
        logger.info("Media key handler disarmed for sleep / session resign")
    }

    // MARK: - Ghost-tap probe

    private func armGhostTapProbe() {
        cancelGhostTapProbe()
        ghostTapProbeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, self.tapToken != nil else { return }
            if !GlobalEventTap.shared.isActive {
                self.logger.error("Ghost-tap probe: tap reports disabled after regrant/wake — marking offline")
                self.mediaKeyStatus.isOffline = true
            }
            self.ghostTapProbeTask = nil
        }
    }

    private func cancelGhostTapProbe() {
        ghostTapProbeTask?.cancel()
        ghostTapProbeTask = nil
    }

    func stop() {
        disableWatchdogTask?.cancel()
        disableWatchdogTask = nil
        watchdogOpen = false
        cancelGhostTapProbe()

        setMediaKeysEnabled(false)
        if let tapToken {
            GlobalEventTap.shared.unregister(tapToken)
            onRunLoopSourceRemoved?()
        }
        tapToken = nil
        logger.info("Media key handler removed")
    }

    private nonisolated func setMediaKeysEnabled(_ enabled: Bool) {
        handlerStateLock.lock()
        mediaKeysEnabled = enabled
        handlerStateLock.unlock()
    }

    // MARK: - Event handling

    func handle(_ event: MediaKeyEvent) {
        let volumeMonitor = audioEngine.deviceVolumeMonitor
        let deviceID = volumeMonitor.defaultDeviceID
        guard deviceID.isValid else {
            logger.debug("Ignoring media key: no valid default output device")
            return
        }
        let tier = volumeMonitor.outputVolumeBackend(for: deviceID)
        let deviceName = audioEngine.deviceMonitor.outputDevices.first { $0.id == deviceID }?.name ?? ""
        handleCore(
            event: event,
            deviceID: deviceID,
            tier: tier,
            deviceName: deviceName,
            currentVolume: volumeMonitor.volumes[deviceID] ?? 0,
            currentMute: volumeMonitor.muteStates[deviceID] ?? false,
            setVolume: { id, vol in volumeMonitor.setVolume(for: id, to: vol) },
            setMute:   { id, mute in volumeMonitor.setMute(for: id, to: mute) }
        )
    }

    func handleCore(
        event: MediaKeyEvent,
        deviceID: AudioDeviceID,
        tier: VolumeControlTier,
        deviceName: String,
        currentVolume: Float,
        currentMute: Bool,
        setVolume: (AudioDeviceID, Float) -> Void,
        setMute: (AudioDeviceID, Bool) -> Void
    ) {
        let shouldShowHUD = !popupVisibility.isVisible

        switch event {
        case .volumeUp(let isRepeat):
            if isRepeat && tier == .ddc && isDDCRepeatCoalesced() {
                logger.debug("DDC repeat coalesced")
                return
            }
            let newVolume = min(1.0, currentVolume + volumeStep)
            if currentMute {
                setMute(deviceID, false)
            }
            setVolume(deviceID, newVolume)
            if shouldShowHUD {
                hudController.show(volume: newVolume, mute: false, deviceName: deviceName)
            }
            iconCoordinator?.flashDevice()

        case .volumeDown(let isRepeat):
            if isRepeat && tier == .ddc && isDDCRepeatCoalesced() {
                logger.debug("DDC repeat coalesced")
                return
            }
            let newVolume = max(0, currentVolume - volumeStep)
            let willBeSilent = newVolume <= 0.001
            if currentMute && !willBeSilent {
                setMute(deviceID, false)
            } else if !currentMute && willBeSilent {
                setMute(deviceID, true)
            }
            setVolume(deviceID, newVolume)
            if shouldShowHUD {
                hudController.show(volume: newVolume, mute: willBeSilent, deviceName: deviceName)
            }
            iconCoordinator?.flashDevice()

        case .muteToggle:
            let newMute = !currentMute
            setMute(deviceID, newMute)
            if shouldShowHUD {
                hudController.show(volume: currentVolume, mute: newMute, deviceName: deviceName)
            }
            iconCoordinator?.flashDevice()
        }
    }

    private func isDDCRepeatCoalesced() -> Bool {
        let now = DispatchTime.now()
        if let last = lastDDCRepeatTime {
            let deltaNs = now.uptimeNanoseconds &- last.uptimeNanoseconds
            if deltaNs < 80 * 1_000_000 { return true }
        }
        lastDDCRepeatTime = now
        return false
    }

    // MARK: - Tap-disabled watchdog

    func handleTapDisabled() {
        if !accessibility.isTrusted {
            logger.warning("Tap disabled and Accessibility no longer trusted — stopping tap")
            disableWatchdogTask?.cancel()
            disableWatchdogTask = nil
            watchdogOpen = false
            stop()
            return
        }

        logger.info("Tap disabled by kernel — attempting re-enable")

        if watchdogOpen {
            logger.error("Second tap-disable inside watchdog window; marking media keys offline")
            mediaKeyStatus.isOffline = true
            disableWatchdogTask?.cancel()
            disableWatchdogTask = nil
            watchdogOpen = false
            return
        }

        watchdogOpen = true
        disableWatchdogTask?.cancel()
        disableWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.watchdogOpen = false
            self?.disableWatchdogTask = nil
        }

    }

    // MARK: - Callback bridge

    nonisolated fileprivate func handleTapEvent(_ cgEvent: CGEvent) -> Bool {
        handlerStateLock.lock()
        let enabled = mediaKeysEnabled
        handlerStateLock.unlock()
        guard enabled else { return false }

        guard let nsEvent = NSEvent(cgEvent: cgEvent) else { return false }
        guard nsEvent.subtype.rawValue == 8 else { return false }
        guard let mediaEvent = decoder.decode(data1: nsEvent.data1) else { return false }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hudController.swallowObserved()
                self.handle(mediaEvent)
            }
        }
        return true
    }
}