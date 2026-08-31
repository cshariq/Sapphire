//
//  DeviceVolumeMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import AudioToolbox
import os

@Observable
@MainActor
final class DeviceVolumeMonitor: DeviceVolumeProviding {
    // MARK: - Output Device State

    private(set) var volumes: [AudioDeviceID: Float] = [:]

    private(set) var muteStates: [AudioDeviceID: Bool] = [:]

    private(set) var defaultDeviceID: AudioDeviceID = .unknown

    private(set) var defaultDeviceUID: String?

    private(set) var systemDeviceID: AudioDeviceID = .unknown

    private(set) var systemDeviceUID: String?

    private(set) var isSystemFollowingDefault: Bool = true

    private(set) var alertVolume: Float = 1.0

    var onVolumeChanged: ((AudioDeviceID, Float) -> Void)?

    var onMuteChanged: ((AudioDeviceID, Bool) -> Void)?

    var onDefaultDeviceChanged: ((String) -> Void)?

    // MARK: - Input Device State

    private(set) var inputVolumes: [AudioDeviceID: Float] = [:]

    private(set) var inputMuteStates: [AudioDeviceID: Bool] = [:]

    private(set) var defaultInputDeviceID: AudioDeviceID = .unknown

    private(set) var defaultInputDeviceUID: String?

    var onInputVolumeChanged: ((AudioDeviceID, Float) -> Void)?

    var onInputMuteChanged: ((AudioDeviceID, Bool) -> Void)?

    var onDefaultInputDeviceChanged: ((String) -> Void)?

    private let deviceMonitor: AudioDeviceMonitor
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "DeviceVolumeMonitor")

    #if !APP_STORE
    private let ddcController: DDCController?
    #endif

    private var volumeListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var muteListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var systemDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    private var inputVolumeListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var inputMuteListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var defaultInputDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    private var registeredVolumeAddresses: [AudioDeviceID: AudioObjectPropertyAddress] = [:]

    private var isObservingDeviceList = false
    private var isObservingInputDeviceList = false
    private var pendingBluetoothOutputConfirmTasks: [AudioDeviceID: Task<Void, Never>] = [:]
    private var pendingBluetoothInputConfirmTasks: [AudioDeviceID: Task<Void, Never>] = [:]

    private var pendingVolumeLogTasks: [AudioDeviceID: Task<Void, Never>] = [:]

    private var alertVolumeDebounceTask: Task<Void, Never>?

    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var systemDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private var defaultInputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var inputVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    private var inputMuteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    #if !APP_STORE
    init(deviceMonitor: AudioDeviceMonitor, settingsManager: SettingsManager, ddcController: DDCController? = nil) {
        self.deviceMonitor = deviceMonitor
        self.settingsManager = settingsManager
        self.ddcController = ddcController
    }
    #else
    init(deviceMonitor: AudioDeviceMonitor, settingsManager: SettingsManager) {
        self.deviceMonitor = deviceMonitor
        self.settingsManager = settingsManager
    }
    #endif

    func outputVolumeBackend(for deviceID: AudioDeviceID) -> VolumeControlTier {
        guard deviceID.isValid else { return .software }
        if let uid = deviceMonitor.device(for: deviceID)?.uid,
           let override = settingsManager.getDeviceVolumeTierOverride(for: uid) {
            return override
        }
        return autoDetectBackend(for: deviceID)
    }

    func autoDetectedOutputVolumeBackend(for deviceID: AudioDeviceID) -> VolumeControlTier {
        guard deviceID.isValid else { return .software }
        return autoDetectBackend(for: deviceID)
    }

    private func autoDetectBackend(for deviceID: AudioDeviceID) -> VolumeControlTier {
        if deviceID.hasOutputVolumeControl() {
            return .hardware
        }

        #if !APP_STORE
        if let ddcController {
            if !ddcController.probeCompleted {
                return .hardware
            }
            if ddcController.isDDCBacked(deviceID) {
                return .ddc
            }
        }
        #endif

        return .software
    }

    func outputProcessingGain(for deviceID: AudioDeviceID) -> Float {
        guard outputVolumeBackend(for: deviceID) == .software else { return 1.0 }
        if muteStates[deviceID] ?? false { return 0.0 }
        return volumes[deviceID] ?? 1.0
    }

    func refreshOutputDeviceStates() {
        readAllStates()
    }

    func start() {
        guard defaultDeviceListenerBlock == nil else { return }

        logger.debug("Starting device volume monitor")

        isSystemFollowingDefault = settingsManager.isSystemSoundsFollowingDefault

        refreshDefaultDevice()

        refreshSystemDevice()

        refreshDeviceListeners()

        defaultDeviceListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDefaultDeviceChanged()
            }
        }

        let defaultDeviceStatus = AudioObjectAddPropertyListenerBlock(
            .system,
            &defaultDeviceAddress,
            .main,
            defaultDeviceListenerBlock!
        )

        if defaultDeviceStatus != noErr {
            logger.error("Failed to add default device listener: \(defaultDeviceStatus)")
        }

        systemDeviceListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleSystemDeviceChanged()
            }
        }

        let systemDeviceStatus = AudioObjectAddPropertyListenerBlock(
            .system,
            &systemDeviceAddress,
            .main,
            systemDeviceListenerBlock!
        )

        if systemDeviceStatus != noErr {
            logger.error("Failed to add system device listener: \(systemDeviceStatus)")
        }

        startObservingDeviceList()

        refreshDefaultInputDevice()
        refreshInputDeviceListeners()

        defaultInputDeviceListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDefaultInputDeviceChanged()
            }
        }

        let defaultInputDeviceStatus = AudioObjectAddPropertyListenerBlock(
            .system,
            &defaultInputDeviceAddress,
            .main,
            defaultInputDeviceListenerBlock!
        )

        if defaultInputDeviceStatus != noErr {
            logger.error("Failed to add default input device listener: \(defaultInputDeviceStatus)")
        }

        startObservingInputDeviceList()

        refreshAlertVolume()

        validateSystemSoundState()
    }

    func stop() {
        logger.debug("Stopping device volume monitor")

        isObservingDeviceList = false
        isObservingInputDeviceList = false

        if let block = defaultDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &defaultDeviceAddress, .main, block)
            defaultDeviceListenerBlock = nil
        }

        if let block = systemDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &systemDeviceAddress, .main, block)
            systemDeviceListenerBlock = nil
        }

        if let block = defaultInputDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &defaultInputDeviceAddress, .main, block)
            defaultInputDeviceListenerBlock = nil
        }

        for deviceID in Array(volumeListeners.keys) {
            removeVolumeListener(for: deviceID)
        }

        for deviceID in Array(muteListeners.keys) {
            removeMuteListener(for: deviceID)
        }

        for deviceID in Array(inputVolumeListeners.keys) {
            removeInputVolumeListener(for: deviceID)
        }

        for deviceID in Array(inputMuteListeners.keys) {
            removeInputMuteListener(for: deviceID)
        }

        cancelAllBluetoothConfirmationTasks()
        cancelAllVolumeLogTasks()

        volumes.removeAll()
        muteStates.removeAll()
        systemDeviceID = .unknown
        systemDeviceUID = nil

        inputVolumes.removeAll()
        inputMuteStates.removeAll()
        defaultInputDeviceID = .unknown
        defaultInputDeviceUID = nil
    }

    private func clampedVolume(_ volume: Float) -> Float {
        volume < 0.01 ? 0 : volume
    }

    func setVolume(for deviceID: AudioDeviceID, to volume: Float) {
        guard deviceID.isValid else {
            logger.warning("Cannot set volume: invalid device ID")
            return
        }

        let clamped = clampedVolume(volume)
        switch outputVolumeBackend(for: deviceID) {
        case .hardware:
            let success = deviceID.setOutputVolumeScalar(clamped)
            if success {
                volumes[deviceID] = clamped
            } else {
                logger.warning("Failed to set volume on device \(deviceID)")
            }

        case .ddc:
            #if !APP_STORE
            if let ddcController {
                let ddcVolume = Int(round(clamped * 100))
                ddcController.setVolume(for: deviceID, to: ddcVolume)
                volumes[deviceID] = clamped
            } else {
                logger.warning("Failed to set DDC volume on device \(deviceID)")
            }
            #else
            logger.warning("DDC volume not available on device \(deviceID)")
            #endif

        case .software:
            guard let deviceUID = outputDeviceUID(for: deviceID) else {
                logger.warning("Cannot persist software volume: missing device UID for \(deviceID)")
                return
            }
            volumes[deviceID] = clamped
            settingsManager.setSoftwareDeviceVolume(for: deviceUID, to: clamped)
            onVolumeChanged?(deviceID, clamped)
        }
    }

    @discardableResult
    func setDefaultDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID.isValid else {
            logger.warning("Cannot set default device: invalid device ID")
            return false
        }

        do {
            try AudioDeviceID.setDefaultOutputDevice(deviceID)
            logger.debug("Set default output device to \(deviceID)")
            return true
        } catch {
            logger.error("Failed to set default device: \(error.localizedDescription)")
            return false
        }
    }

    func setMute(for deviceID: AudioDeviceID, to muted: Bool) {
        guard deviceID.isValid else {
            logger.warning("Cannot set mute: invalid device ID")
            return
        }

        switch outputVolumeBackend(for: deviceID) {
        case .hardware:
            let success = deviceID.setMuteState(muted)
            if success {
                muteStates[deviceID] = muted
            } else {
                logger.warning("Failed to set mute on device \(deviceID)")
            }

        case .ddc:
            #if !APP_STORE
            if let ddcController {
                if muted {
                    ddcController.mute(for: deviceID)
                } else {
                    ddcController.unmute(for: deviceID)
                }
                muteStates[deviceID] = muted
            } else {
                logger.warning("Failed to set DDC mute on device \(deviceID)")
            }
            #else
            logger.warning("DDC mute not available on device \(deviceID)")
            #endif

        case .software:
            guard let deviceUID = outputDeviceUID(for: deviceID) else {
                logger.warning("Cannot persist software mute: missing device UID for \(deviceID)")
                return
            }

            if muted {
                let currentVisibleVolume = volumes[deviceID] ?? settingsManager.getSoftwareDeviceVolume(for: deviceUID) ?? 1.0
                if currentVisibleVolume > 0 {
                    settingsManager.setSoftwareDeviceSavedVolume(for: deviceUID, to: currentVisibleVolume)
                }
                settingsManager.setSoftwareDeviceMuteState(for: deviceUID, to: true)
                settingsManager.setSoftwareDeviceVolume(for: deviceUID, to: 0)
                volumes[deviceID] = 0
                muteStates[deviceID] = true
                onVolumeChanged?(deviceID, 0)
                onMuteChanged?(deviceID, true)
            } else {
                settingsManager.setSoftwareDeviceMuteState(for: deviceUID, to: false)

                let currentVisibleVolume = volumes[deviceID] ?? settingsManager.getSoftwareDeviceVolume(for: deviceUID) ?? 0
                if currentVisibleVolume == 0 {
                    let restoredVolume = settingsManager.getSoftwareDeviceSavedVolume(for: deviceUID) ?? 0.5
                    settingsManager.setSoftwareDeviceVolume(for: deviceUID, to: restoredVolume)
                    volumes[deviceID] = restoredVolume
                    onVolumeChanged?(deviceID, restoredVolume)
                }

                muteStates[deviceID] = false
                onMuteChanged?(deviceID, false)
            }
        }
    }

    #if !APP_STORE
    func refreshAfterDDCProbe() {
        refreshOutputDeviceStates()
    }
    #endif

    // MARK: - Input Device Control

    func setInputVolume(for deviceID: AudioDeviceID, to volume: Float) {
        guard deviceID.isValid else {
            logger.warning("Cannot set input volume: invalid device ID")
            return
        }

        let success = deviceID.setInputVolumeScalar(volume)
        if success {
            inputVolumes[deviceID] = volume
        } else {
            logger.warning("Failed to set input volume on device \(deviceID)")
        }
    }

    func setInputMute(for deviceID: AudioDeviceID, to muted: Bool) {
        guard deviceID.isValid else {
            logger.warning("Cannot set input mute: invalid device ID")
            return
        }

        let success = deviceID.setInputMuteState(muted)
        if success {
            inputMuteStates[deviceID] = muted
        } else {
            logger.warning("Failed to set input mute on device \(deviceID)")
        }
    }

    @discardableResult
    func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID.isValid else {
            logger.warning("Cannot set default input device: invalid device ID")
            return false
        }

        do {
            try AudioDeviceID.setDefaultInputDevice(deviceID)
            logger.debug("Set default input device to \(deviceID)")
            return true
        } catch {
            logger.error("Failed to set default input device: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Methods

    private func refreshDefaultDevice() {
        do {
            let newDeviceID = try AudioDeviceID.readDefaultOutputDevice()

            if newDeviceID.isValid {
                defaultDeviceID = newDeviceID
                defaultDeviceUID = try? newDeviceID.readDeviceUID()
                logger.debug("Default device ID: \(self.defaultDeviceID), UID: \(self.defaultDeviceUID ?? "nil")")
            } else {
                logger.warning("Default output device is invalid")
                defaultDeviceID = .unknown
                defaultDeviceUID = nil
            }

        } catch {
            logger.error("Failed to read default output device: \(error.localizedDescription)")
        }
    }

    private func handleDefaultDeviceChanged() {
        let oldUID = defaultDeviceUID
        logger.debug("Default output device changed")
        refreshDefaultDevice()
        if let newUID = defaultDeviceUID, newUID != oldUID {
            onDefaultDeviceChanged?(newUID)

            if isSystemFollowingDefault {
                refreshDefaultDevice()
                if defaultDeviceID.isValid {
                    setSystemDevice(defaultDeviceID)
                    refreshSystemDevice()
                    if systemDeviceUID != defaultDeviceUID {
                        logger.warning("Failed to sync system sounds to new default device")
                    } else {
                        logger.debug("System sounds followed default to new device")
                    }
                }
            }
        }
    }

    private func refreshSystemDevice() {
        do {
            let newDeviceID = try AudioDeviceID.readSystemOutputDevice()

            if newDeviceID.isValid {
                systemDeviceID = newDeviceID
                systemDeviceUID = try? newDeviceID.readDeviceUID()
                logger.debug("System device ID: \(self.systemDeviceID), UID: \(self.systemDeviceUID ?? "nil")")
            } else {
                logger.warning("System output device is invalid")
                systemDeviceID = .unknown
                systemDeviceUID = nil
            }

        } catch {
            logger.error("Failed to read system output device: \(error.localizedDescription)")
        }
    }

    private func validateSystemSoundState() {
        guard defaultDeviceUID != nil, systemDeviceUID != nil else {
            logger.debug("Cannot validate system sound state: missing device UIDs")
            return
        }

        let systemMatchesDefault = (systemDeviceUID == defaultDeviceUID)

        if isSystemFollowingDefault && !systemMatchesDefault {
            if defaultDeviceID.isValid {
                setSystemDevice(defaultDeviceID)
                refreshSystemDevice()
                if systemDeviceUID != defaultDeviceUID {
                    logger.warning("Startup: failed to enforce system sounds to follow default")
                } else {
                    logger.info("Startup: enforced system sounds to follow default device")
                }
            }
        }
    }

    private func handleSystemDeviceChanged() {
        logger.debug("System output device changed")
        refreshSystemDevice()

        if isSystemFollowingDefault {
            let stillFollowing = (systemDeviceUID == defaultDeviceUID)
            if !stillFollowing {
                isSystemFollowingDefault = false
                settingsManager.setSystemSoundsFollowDefault(false)
                logger.info("System device changed externally, no longer following default")
            }
        }
    }

    func setSystemDevice(_ deviceID: AudioDeviceID) {
        guard deviceID.isValid else {
            logger.warning("Cannot set system device: invalid device ID")
            return
        }

        do {
            try AudioDeviceID.setSystemOutputDevice(deviceID)
            logger.debug("Set system output device to \(deviceID)")
        } catch {
            logger.error("Failed to set system device: \(error.localizedDescription)")
        }
    }

    func setSystemFollowDefault() {
        isSystemFollowingDefault = true
        settingsManager.setSystemSoundsFollowDefault(true)

        if defaultDeviceID.isValid {
            setSystemDevice(defaultDeviceID)
        }
        logger.debug("System sounds now following default")
    }

    func setSystemDeviceExplicit(_ deviceID: AudioDeviceID) {
        isSystemFollowingDefault = false
        settingsManager.setSystemSoundsFollowDefault(false)
        setSystemDevice(deviceID)
        logger.debug("System sounds set to explicit device: \(deviceID)")
    }

    // MARK: - Alert Volume

    func refreshAlertVolume() {
        guard alertVolumeDebounceTask == nil else { return }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "get alert volume of (get volume settings)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            guard proc.terminationStatus == 0 else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let pct = Int(str) {
                let volume = Float(pct) / 100.0
                Task { @MainActor [weak self] in self?.alertVolume = volume }
            }
        }
        try? process.run()
    }

    func setAlertVolume(_ volume: Float) {
        let clamped = max(0, min(1, volume))
        let pct = Int(round(clamped * 100))
        let newVolume = Float(pct) / 100.0

        guard newVolume != alertVolume else { return }

        alertVolume = newVolume

        alertVolumeDebounceTask?.cancel()
        alertVolumeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "set volume alert volume \(pct)"]
            process.terminationHandler = { [weak self] proc in
                if proc.terminationStatus != 0 {
                    Task { @MainActor [weak self] in
                        self?.logger.warning(
                            "osascript exited with status \(proc.terminationStatus) setting alert volume"
                        )
                    }
                }
            }
            do {
                try process.run()
            } catch {
                self.logger.warning("Failed to launch osascript for alert volume: \(error)")
            }

            self.alertVolumeDebounceTask = nil
        }
    }

    private func refreshDeviceListeners() {
        let currentDeviceIDs = Set(deviceMonitor.outputDevices.map(\.id))
        let trackedVolumeIDs = Set(volumeListeners.keys)
        let trackedMuteIDs = Set(muteListeners.keys)

        let newVolumeIDs = currentDeviceIDs.subtracting(trackedVolumeIDs)
        let newMuteIDs = currentDeviceIDs.subtracting(trackedMuteIDs)
        for deviceID in newVolumeIDs {
            addVolumeListener(for: deviceID)
        }
        for deviceID in newMuteIDs {
            addMuteListener(for: deviceID)
        }

        let staleVolumeIDs = trackedVolumeIDs.subtracting(currentDeviceIDs)
        for deviceID in staleVolumeIDs {
            removeVolumeListener(for: deviceID)
            volumes.removeValue(forKey: deviceID)
            cancelBluetoothOutputConfirmation(for: deviceID)
        }

        let staleMuteIDs = trackedMuteIDs.subtracting(currentDeviceIDs)
        for deviceID in staleMuteIDs {
            removeMuteListener(for: deviceID)
            muteStates.removeValue(forKey: deviceID)
        }

        readAllStates()
    }

    private func addVolumeListener(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        guard volumeListeners[deviceID] == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleVolumeChanged(for: deviceID)
            }
        }

        volumeListeners[deviceID] = block

        var address = volumeAddress
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            .main,
            block
        )

        if status == noErr {
            return
        }

        var fallbackAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let fallback1Status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &fallbackAddr,
            .main,
            block
        )

        if fallback1Status == noErr {
            registeredVolumeAddresses[deviceID] = fallbackAddr
            logger.debug("Volume listener fallback to VolumeScalar element 0 for device \(deviceID)")
            return
        }

        var fallbackAddr2 = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 1
        )
        let fallback2Status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &fallbackAddr2,
            .main,
            block
        )

        if fallback2Status == noErr {
            registeredVolumeAddresses[deviceID] = fallbackAddr2
            logger.debug("Volume listener fallback to VolumeScalar element 1 for device \(deviceID)")
            return
        }

        logger.warning("Failed to add volume listener for device \(deviceID): \(status)")
        volumeListeners.removeValue(forKey: deviceID)
    }

    private func removeVolumeListener(for deviceID: AudioDeviceID) {
        guard let block = volumeListeners.removeValue(forKey: deviceID) else { return }

        let status: OSStatus
        if let registeredAddr = registeredVolumeAddresses.removeValue(forKey: deviceID) {
            var addr = registeredAddr
            status = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
        } else {
            var address = volumeAddress
            status = AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        }
        if status != noErr && status != OSStatus(kAudioHardwareBadObjectError) {
            logger.warning("Failed to remove volume listener for device \(deviceID): \(status)")
        }
    }

    private func handleVolumeChanged(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }

        if outputVolumeBackend(for: deviceID) == .software { return }

        #if !APP_STORE
        if let ddcController, ddcController.isDDCBacked(deviceID) { return }
        #endif

        let newVolume = clampedVolume(deviceID.readOutputVolumeScalar())

        if let currentVolume = volumes[deviceID], currentVolume == newVolume { return }

        volumes[deviceID] = newVolume
        onVolumeChanged?(deviceID, newVolume)

        pendingVolumeLogTasks[deviceID]?.cancel()
        pendingVolumeLogTasks[deviceID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.pendingVolumeLogTasks.removeValue(forKey: deviceID)
            let settled = self.volumes[deviceID] ?? newVolume
            self.logger.info("Volume settled for device \(deviceID): \(settled)")
        }
    }

    private func addMuteListener(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        guard muteListeners[deviceID] == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleMuteChanged(for: deviceID)
            }
        }

        muteListeners[deviceID] = block

        var address = muteAddress
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            .main,
            block
        )

        if status != noErr {
            logger.warning("Failed to add mute listener for device \(deviceID): \(status)")
            muteListeners.removeValue(forKey: deviceID)
        }
    }

    private func removeMuteListener(for deviceID: AudioDeviceID) {
        guard let block = muteListeners.removeValue(forKey: deviceID) else { return }

        var address = muteAddress
        let status = AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        if status != noErr && status != OSStatus(kAudioHardwareBadObjectError) {
            logger.warning("Failed to remove mute listener for device \(deviceID): \(status)")
        }
    }

    private func handleMuteChanged(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        if outputVolumeBackend(for: deviceID) == .software { return }
        let newMuteState = deviceID.readMuteState()
        muteStates[deviceID] = newMuteState
        onMuteChanged?(deviceID, newMuteState)
        logger.debug("Mute changed for device \(deviceID): \(newMuteState)")
    }

    private func readAllStates() {
        for device in deviceMonitor.outputDevices {
            readOneState(for: device.id, device: device)
        }
    }

    private func readOneState(for deviceID: AudioDeviceID, device: AudioDevice) {
        guard deviceID.isDeviceAlive() else { return }

        let backend = outputVolumeBackend(for: deviceID)

        if backend == .software {
            let muted = settingsManager.getSoftwareDeviceMuteState(for: device.uid)
            let defaultVolume: Float = muted ? 0 : 1.0
            let visibleVolume = settingsManager.getSoftwareDeviceVolume(for: device.uid) ?? defaultVolume
            volumes[deviceID] = clampedVolume(visibleVolume)
            muteStates[deviceID] = muted
            return
        }

        #if !APP_STORE
        if backend == .ddc, let ddcController {
            if let ddcVolume = ddcController.getVolume(for: deviceID) {
                volumes[deviceID] = Float(ddcVolume) / 100.0
            } else {
                volumes[deviceID] = 0.5
            }
            muteStates[deviceID] = ddcController.isMuted(for: deviceID)
            return
        }
        #endif

        let volume = clampedVolume(deviceID.readOutputVolumeScalar())
        volumes[deviceID] = volume

        let muted = deviceID.readMuteState()
        muteStates[deviceID] = muted

        let transportType = deviceID.readTransportType()
        if transportType == .bluetooth || transportType == .bluetoothLE {
            scheduleBluetoothOutputConfirmation(for: deviceID)
        }
    }

    func applyTierOverrideChange(for deviceID: AudioDeviceID) {
        guard let device = deviceMonitor.device(for: deviceID) else { return }
        let newBackend = outputVolumeBackend(for: deviceID)
        let previousMute = muteStates[deviceID] ?? false
        switch newBackend {
        case .software:
            settingsManager.setSoftwareDeviceMuteState(for: device.uid, to: previousMute)
            if previousMute {
                _ = deviceID.setMuteState(false)
            }
        case .hardware, .ddc:
            let softwareMute = settingsManager.getSoftwareDeviceMuteState(for: device.uid)
            if softwareMute {
                if newBackend == .hardware {
                    _ = deviceID.setMuteState(true)
                }
                #if !APP_STORE
                if newBackend == .ddc, let ddcController {
                    ddcController.mute(for: deviceID)
                }
                #endif
            }
        }
        readOneState(for: deviceID, device: device)
    }

    private func outputDeviceUID(for deviceID: AudioDeviceID) -> String? {
        deviceMonitor.device(for: deviceID)?.uid
    }

    private func startObservingDeviceList() {
        guard !isObservingDeviceList else { return }
        isObservingDeviceList = true

        func observe() {
            guard isObservingDeviceList else { return }
            withObservationTracking {
                _ = self.deviceMonitor.outputDevices
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isObservingDeviceList else { return }
                    self.logger.debug("Device list changed, refreshing volume listeners")
                    self.refreshDeviceListeners()
                    observe()
                }
            }
        }
        observe()
    }

    // MARK: - Input Device Private Methods

    private func refreshDefaultInputDevice() {
        do {
            let newDeviceID = try AudioDeviceID.readDefaultInputDevice()

            if newDeviceID.isValid {
                defaultInputDeviceID = newDeviceID
                defaultInputDeviceUID = try? newDeviceID.readDeviceUID()
                logger.debug("Default input device ID: \(self.defaultInputDeviceID), UID: \(self.defaultInputDeviceUID ?? "nil")")
            } else {
                logger.warning("Default input device is invalid")
                defaultInputDeviceID = .unknown
                defaultInputDeviceUID = nil
            }

        } catch {
            logger.error("Failed to read default input device: \(error.localizedDescription)")
        }
    }

    private func handleDefaultInputDeviceChanged() {
        let oldUID = defaultInputDeviceUID
        logger.debug("Default input device changed")
        refreshDefaultInputDevice()
        if let newUID = defaultInputDeviceUID, newUID != oldUID {
            onDefaultInputDeviceChanged?(newUID)
        }
    }

    private func refreshInputDeviceListeners() {
        let currentDeviceIDs = Set(deviceMonitor.inputDevices.map(\.id))
        let trackedVolumeIDs = Set(inputVolumeListeners.keys)
        let trackedMuteIDs = Set(inputMuteListeners.keys)

        let newDeviceIDs = currentDeviceIDs.subtracting(trackedVolumeIDs)
        for deviceID in newDeviceIDs {
            addInputVolumeListener(for: deviceID)
            addInputMuteListener(for: deviceID)
        }

        let staleVolumeIDs = trackedVolumeIDs.subtracting(currentDeviceIDs)
        for deviceID in staleVolumeIDs {
            removeInputVolumeListener(for: deviceID)
            inputVolumes.removeValue(forKey: deviceID)
            cancelBluetoothInputConfirmation(for: deviceID)
        }

        let staleMuteIDs = trackedMuteIDs.subtracting(currentDeviceIDs)
        for deviceID in staleMuteIDs {
            removeInputMuteListener(for: deviceID)
            inputMuteStates.removeValue(forKey: deviceID)
        }

        readAllInputStates()
    }

    private func addInputVolumeListener(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        guard inputVolumeListeners[deviceID] == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleInputVolumeChanged(for: deviceID)
            }
        }

        inputVolumeListeners[deviceID] = block

        var address = inputVolumeAddress
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            .main,
            block
        )

        if status != noErr {
            logger.warning("Failed to add input volume listener for device \(deviceID): \(status)")
            inputVolumeListeners.removeValue(forKey: deviceID)
        }
    }

    private func removeInputVolumeListener(for deviceID: AudioDeviceID) {
        guard let block = inputVolumeListeners.removeValue(forKey: deviceID) else { return }

        var address = inputVolumeAddress
        let status = AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        if status != noErr && status != OSStatus(kAudioHardwareBadObjectError) {
            logger.warning("Failed to remove input volume listener for device \(deviceID): \(status)")
        }
    }

    private func handleInputVolumeChanged(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        let newVolume = deviceID.readInputVolumeScalar()

        if let currentVolume = inputVolumes[deviceID], currentVolume == newVolume { return }

        inputVolumes[deviceID] = newVolume
        onInputVolumeChanged?(deviceID, newVolume)
        logger.debug("Input volume changed for device \(deviceID): \(newVolume)")
    }

    private func addInputMuteListener(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        guard inputMuteListeners[deviceID] == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleInputMuteChanged(for: deviceID)
            }
        }

        inputMuteListeners[deviceID] = block

        var address = inputMuteAddress
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            .main,
            block
        )

        if status != noErr {
            logger.warning("Failed to add input mute listener for device \(deviceID): \(status)")
            inputMuteListeners.removeValue(forKey: deviceID)
        }
    }

    private func removeInputMuteListener(for deviceID: AudioDeviceID) {
        guard let block = inputMuteListeners.removeValue(forKey: deviceID) else { return }

        var address = inputMuteAddress
        let status = AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        if status != noErr && status != OSStatus(kAudioHardwareBadObjectError) {
            logger.warning("Failed to remove input mute listener for device \(deviceID): \(status)")
        }
    }

    private func handleInputMuteChanged(for deviceID: AudioDeviceID) {
        guard deviceID.isValid else { return }
        let newMuteState = deviceID.readInputMuteState()
        inputMuteStates[deviceID] = newMuteState
        onInputMuteChanged?(deviceID, newMuteState)
        logger.debug("Input mute changed for device \(deviceID): \(newMuteState)")
    }

    private func readAllInputStates() {
        for device in deviceMonitor.inputDevices {
            guard device.id.isDeviceAlive() else { continue }

            let volume = device.id.readInputVolumeScalar()
            inputVolumes[device.id] = volume

            let muted = device.id.readInputMuteState()
            inputMuteStates[device.id] = muted

            let transportType = device.id.readTransportType()
            if transportType == .bluetooth || transportType == .bluetoothLE {
                scheduleBluetoothInputConfirmation(for: device.id)
            }
        }
    }

    private func startObservingInputDeviceList() {
        guard !isObservingInputDeviceList else { return }
        isObservingInputDeviceList = true

        func observe() {
            guard isObservingInputDeviceList else { return }
            withObservationTracking {
                _ = self.deviceMonitor.inputDevices
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isObservingInputDeviceList else { return }
                    self.logger.debug("Input device list changed, refreshing input volume listeners")
                    self.refreshInputDeviceListeners()
                    observe()
                }
            }
        }
        observe()
    }

    // MARK: - Bluetooth Confirmation Tasks

    private func scheduleBluetoothOutputConfirmation(for deviceID: AudioDeviceID) {
        pendingBluetoothOutputConfirmTasks[deviceID]?.cancel()
        pendingBluetoothOutputConfirmTasks[deviceID] = Task { @MainActor [weak self] in
            defer { self?.pendingBluetoothOutputConfirmTasks.removeValue(forKey: deviceID) }
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.volumes.keys.contains(deviceID) else { return }
            let confirmedVolume = self.clampedVolume(deviceID.readOutputVolumeScalar())
            let confirmedMute = deviceID.readMuteState()
            self.volumes[deviceID] = confirmedVolume
            self.muteStates[deviceID] = confirmedMute
            self.logger.debug("Bluetooth device \(deviceID) confirmed volume: \(confirmedVolume), muted: \(confirmedMute)")
        }
    }

    private func cancelBluetoothOutputConfirmation(for deviceID: AudioDeviceID) {
        pendingBluetoothOutputConfirmTasks.removeValue(forKey: deviceID)?.cancel()
    }

    private func scheduleBluetoothInputConfirmation(for deviceID: AudioDeviceID) {
        pendingBluetoothInputConfirmTasks[deviceID]?.cancel()
        pendingBluetoothInputConfirmTasks[deviceID] = Task { @MainActor [weak self] in
            defer { self?.pendingBluetoothInputConfirmTasks.removeValue(forKey: deviceID) }
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.inputVolumes.keys.contains(deviceID) else { return }
            let confirmedVolume = deviceID.readInputVolumeScalar()
            let confirmedMute = deviceID.readInputMuteState()
            self.inputVolumes[deviceID] = confirmedVolume
            self.inputMuteStates[deviceID] = confirmedMute
            self.logger.debug("Bluetooth input device \(deviceID) confirmed volume: \(confirmedVolume), muted: \(confirmedMute)")
        }
    }

    private func cancelBluetoothInputConfirmation(for deviceID: AudioDeviceID) {
        pendingBluetoothInputConfirmTasks.removeValue(forKey: deviceID)?.cancel()
    }

    private func cancelAllBluetoothConfirmationTasks() {
        for (_, task) in pendingBluetoothOutputConfirmTasks { task.cancel() }
        pendingBluetoothOutputConfirmTasks.removeAll()
        for (_, task) in pendingBluetoothInputConfirmTasks { task.cancel() }
        pendingBluetoothInputConfirmTasks.removeAll()
    }

    private func cancelAllVolumeLogTasks() {
        for (_, task) in pendingVolumeLogTasks { task.cancel() }
        pendingVolumeLogTasks.removeAll()
    }

}