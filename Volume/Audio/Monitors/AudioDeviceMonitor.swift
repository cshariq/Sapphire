//
//  AudioDeviceMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import AudioToolbox
import os

@Observable
@MainActor
final class AudioDeviceMonitor: AudioDeviceProviding {
    // MARK: - Output Devices

    private(set) var outputDevices: [AudioDevice] = []

    private(set) var devicesByUID: [String: AudioDevice] = [:]

    private(set) var devicesByID: [AudioDeviceID: AudioDevice] = [:]

    var onDeviceDisconnected: ((_ uid: String, _ name: String) -> Void)?

    var onDeviceConnected: ((_ uid: String, _ name: String) -> Void)?

    // MARK: - Input Devices

    private(set) var inputDevices: [AudioDevice] = []

    private(set) var inputDevicesByUID: [String: AudioDevice] = [:]

    private(set) var inputDevicesByID: [AudioDeviceID: AudioDevice] = [:]

    var onInputDeviceDisconnected: ((_ uid: String, _ name: String) -> Void)?

    var onInputDeviceConnected: ((_ uid: String, _ name: String) -> Void)?

    var outputPriorityOrder: (() -> [String])?

    var inputPriorityOrder: (() -> [String])?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "AudioDeviceMonitor")

    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var knownDeviceUIDs: Set<String> = []
    private var knownInputDeviceUIDs: Set<String> = []

    @ObservationIgnored private var dataSourceListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]

    private var deviceListDebounceTask: Task<Void, Never>?

    func start() {
        guard deviceListListenerBlock == nil else { return }

        logger.debug("Starting audio device monitor")

        refresh()

        deviceListListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.scheduleDeviceListRefresh()
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            .system,
            &deviceListAddress,
            .main,
            deviceListListenerBlock!
        )

        if status != noErr {
            logger.error("Failed to add device list listener: \(status)")
        }
    }

    func stop() {
        logger.debug("Stopping audio device monitor")

        deviceListDebounceTask?.cancel()
        deviceListDebounceTask = nil

        if let block = deviceListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &deviceListAddress, .main, block)
            deviceListListenerBlock = nil
        }
        removeAllDataSourceListeners()
    }

    func device(for uid: String) -> AudioDevice? {
        devicesByUID[uid]
    }

    func device(for id: AudioDeviceID) -> AudioDevice? {
        devicesByID[id]
    }

    func inputDevice(for uid: String) -> AudioDevice? {
        inputDevicesByUID[uid]
    }

    func inputDevice(for id: AudioDeviceID) -> AudioDevice? {
        inputDevicesByID[id]
    }

    private func refresh() {
        do {
            let deviceIDs = try AudioObjectID.readDeviceList()
            var outputDeviceList: [AudioDevice] = []
            var inputDeviceList: [AudioDevice] = []

            for deviceID in deviceIDs {
                guard let uid = try? deviceID.readDeviceUID(),
                      let name = try? deviceID.readDeviceName() else {
                    continue
                }

                if deviceID.isAggregateDevice() && name.hasPrefix("Sapphire-") { continue }

                if deviceID.isHidden() { continue }

                if deviceID.hasOutputStreams() {
                    let icon = DeviceIconCache.shared.icon(for: uid) {
                        deviceID.readDeviceIcon()
                    } ?? NSImage(systemSymbolName: deviceID.suggestedIconSymbol(), accessibilityDescription: name)

                    let device = AudioDevice(
                        id: deviceID,
                        uid: uid,
                        name: name,
                        icon: icon,
                        supportsAutoEQ: deviceID.supportsAutoEQ()
                    )
                    outputDeviceList.append(device)
                }

                if deviceID.hasInputStreams() {
                    let icon = DeviceIconCache.shared.icon(for: uid) {
                        deviceID.readDeviceIcon()
                    } ?? NSImage(systemSymbolName: deviceID.suggestedInputIconSymbol(),
                                 accessibilityDescription: name)

                    let device = AudioDevice(
                        id: deviceID,
                        uid: uid,
                        name: name,
                        icon: icon,
                        supportsAutoEQ: false
                    )
                    inputDeviceList.append(device)
                }
            }

            outputDevices = outputDeviceList.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            knownDeviceUIDs = Set(outputDeviceList.map(\.uid))
            devicesByUID = Dictionary(uniqueKeysWithValues: outputDevices.map { ($0.uid, $0) })
            devicesByID = Dictionary(uniqueKeysWithValues: outputDevices.map { ($0.id, $0) })

            inputDevices = inputDeviceList.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            knownInputDeviceUIDs = Set(inputDeviceList.map(\.uid))
            inputDevicesByUID = Dictionary(uniqueKeysWithValues: inputDevices.map { ($0.uid, $0) })
            inputDevicesByID = Dictionary(uniqueKeysWithValues: inputDevices.map { ($0.id, $0) })

            syncDataSourceListeners(outputDeviceIDs: outputDeviceList.map(\.id))

        } catch {
            logger.error("Failed to refresh device list: \(error.localizedDescription)")
        }
    }

    private func syncDataSourceListeners(outputDeviceIDs: [AudioDeviceID]) {
        let builtInIDs = Set(outputDeviceIDs.filter { $0.readTransportType() == .builtIn })
        let currentIDs = Set(dataSourceListeners.keys)

        for deviceID in currentIDs.subtracting(builtInIDs) {
            removeDataSourceListener(for: deviceID)
        }

        for deviceID in builtInIDs.subtracting(currentIDs) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDataSource,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.scheduleDeviceListRefresh()
                }
            }
            let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block)
            if status == noErr {
                dataSourceListeners[deviceID] = block
            } else {
                logger.warning("Failed to add data source listener for device \(deviceID): \(status)")
            }
        }
    }

    private func removeDataSourceListener(for deviceID: AudioDeviceID) {
        guard let block = dataSourceListeners.removeValue(forKey: deviceID) else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        if status != noErr && status != OSStatus(kAudioHardwareBadObjectError) {
            logger.warning("Failed to remove data source listener for device \(deviceID): \(status)")
        }
    }

    private func removeAllDataSourceListeners() {
        for deviceID in dataSourceListeners.keys {
            removeDataSourceListener(for: deviceID)
        }
    }

    private func sortByPriority(uids: Set<String>, priorityOrder: [String]) -> [String] {
        guard uids.count > 1 else { return Array(uids) }
        var sorted: [String] = []
        for uid in priorityOrder where uids.contains(uid) {
            sorted.append(uid)
        }
        let remaining = uids.subtracting(sorted).sorted()
        sorted.append(contentsOf: remaining)
        return sorted
    }

    private func scheduleDeviceListRefresh() {
        deviceListDebounceTask?.cancel()
        deviceListDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.handleDeviceListChanged()
        }
    }

    private func handleDeviceListChanged() {
        let previousOutputUIDs = knownDeviceUIDs
        let previousInputUIDs = knownInputDeviceUIDs

        var outputDeviceNames: [String: String] = [:]
        for device in outputDevices {
            outputDeviceNames[device.uid] = device.name
        }
        var inputDeviceNames: [String: String] = [:]
        for device in inputDevices {
            inputDeviceNames[device.uid] = device.name
        }

        refresh()

        let currentOutputUIDs = knownDeviceUIDs
        let disconnectedOutputUIDs = previousOutputUIDs.subtracting(currentOutputUIDs)
        for uid in disconnectedOutputUIDs {
            let name = outputDeviceNames[uid] ?? uid
            logger.info("Output device disconnected: \(name) (\(uid))")
            onDeviceDisconnected?(uid, name)
        }
        let connectedOutputUIDs = currentOutputUIDs.subtracting(previousOutputUIDs)
        let sortedConnectedOutput = sortByPriority(uids: connectedOutputUIDs, priorityOrder: outputPriorityOrder?() ?? [])
        for uid in sortedConnectedOutput {
            if let device = devicesByUID[uid] {
                logger.info("Output device connected: \(device.name) (\(uid))")
                onDeviceConnected?(uid, device.name)
            }
        }

        let currentInputUIDs = knownInputDeviceUIDs
        let disconnectedInputUIDs = previousInputUIDs.subtracting(currentInputUIDs)
        for uid in disconnectedInputUIDs {
            let name = inputDeviceNames[uid] ?? uid
            logger.info("Input device disconnected: \(name) (\(uid))")
            onInputDeviceDisconnected?(uid, name)
        }
        let connectedInputUIDs = currentInputUIDs.subtracting(previousInputUIDs)
        let sortedConnectedInput = sortByPriority(uids: connectedInputUIDs, priorityOrder: inputPriorityOrder?() ?? [])
        for uid in sortedConnectedInput {
            if let device = inputDevicesByUID[uid] {
                logger.info("Input device connected: \(device.name) (\(uid))")
                onInputDeviceConnected?(uid, device.name)
            }
        }
    }

}