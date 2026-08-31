//
//  DDCController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

#if !APP_STORE

import AppKit
import AudioToolbox
import IOKit
import os

@Observable
@MainActor
final class DDCController {
    private(set) var ddcBackedDevices: Set<AudioDeviceID> = []

    private(set) var probeCompleted: Bool = false

    private(set) var cachedVolumes: [AudioDeviceID: Int] = [:]

    private var services: [AudioDeviceID: DDCService] = [:]
    private var deviceUIDs: [AudioDeviceID: String] = [:]
    private var debounceTimers: [AudioDeviceID: DispatchWorkItem] = [:]
    private var probeWorkItem: DispatchWorkItem?
    private var displayChangeObserver: NSObjectProtocol?

    private let ddcQueue = DispatchQueue(label: "com.cshariq.sapphire.ddc", qos: .utility)
    private let settingsManager: SettingsManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "DDCController")

    var onProbeCompleted: (() -> Void)?

    private struct DisplayEDID: Sendable {
        let vendorID: UInt32
        let productID: UInt32
        let serialNumber: UInt32
    }

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    // MARK: - Lifecycle

    func start() {
        probe()
        setupDisplayChangeObserver()
    }

    func stop() {
        if let obs = displayChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            displayChangeObserver = nil
        }
        probeWorkItem?.cancel()
        probeWorkItem = nil
        for (_, item) in debounceTimers { item.cancel() }
        debounceTimers.removeAll()
    }

    // MARK: - Public API

    func isDDCBacked(_ deviceID: AudioDeviceID) -> Bool {
        ddcBackedDevices.contains(deviceID)
    }

    func getVolume(for deviceID: AudioDeviceID) -> Int? {
        cachedVolumes[deviceID]
    }

    func setVolume(for deviceID: AudioDeviceID, to volume: Int) {
        let clamped = max(0, min(100, volume))
        cachedVolumes[deviceID] = clamped

        if let uid = deviceUIDs[deviceID] {
            settingsManager.setDDCVolume(for: uid, to: clamped)
        }

        debounceTimers[deviceID]?.cancel()
        let service = services[deviceID]
        let item = DispatchWorkItem { [weak self] in
            do {
                try service?.setAudioVolume(clamped)
            } catch {
                self?.logger.error("DDC write failed for device \(deviceID): \(error)")
            }
        }
        debounceTimers[deviceID] = item
        ddcQueue.asyncAfter(deadline: .now() + .milliseconds(100), execute: item)
    }

    func mute(for deviceID: AudioDeviceID) {
        guard let uid = deviceUIDs[deviceID] else { return }
        let currentVolume = cachedVolumes[deviceID] ?? 50
        if currentVolume > 0 {
            settingsManager.setDDCSavedVolume(for: uid, to: currentVolume)
        }
        settingsManager.setDDCMuteState(for: uid, to: true)
        settingsManager.flushSync()
        setVolume(for: deviceID, to: 0)
    }

    func unmute(for deviceID: AudioDeviceID) {
        guard let uid = deviceUIDs[deviceID] else { return }
        let savedVolume = settingsManager.getDDCSavedVolume(for: uid) ?? 50
        settingsManager.setDDCMuteState(for: uid, to: false)
        setVolume(for: deviceID, to: savedVolume)
    }

    func isMuted(for deviceID: AudioDeviceID) -> Bool {
        guard let uid = deviceUIDs[deviceID] else { return false }
        return settingsManager.getDDCMuteState(for: uid)
    }

    // MARK: - Display Probing

    private func probe() {
        for (_, item) in debounceTimers { item.cancel() }
        debounceTimers.removeAll()

        let logger = self.logger
        ddcQueue.async { [weak self, logger] in
            guard let self else { return }

            let discovered = DDCService.discoverServices()
            logger.info("DDC probe: found \(discovered.count) DCPAVServiceProxy entries")
            guard !discovered.isEmpty else {
                Task { @MainActor [weak self] in
                    self?.ddcBackedDevices = []
                    self?.services = [:]
                    self?.probeCompleted = true
                    self?.onProbeCompleted?()
                }
                return
            }

            var audioCapable: [(entry: io_service_t, service: DDCService, displayName: String, edid: DisplayEDID?)] = []
            for (index, (entry, service)) in discovered.enumerated() {
                let name = Self.getDisplayName(for: entry)

                let edid: DisplayEDID? = {
                    guard let raw = service.readEDID() else { return nil }
                    return DisplayEDID(vendorID: raw.vendorID, productID: raw.productID, serialNumber: raw.serialNumber)
                }()

                logger.info("DDC probe: display \(index + 1) '\(name)' EDID(\(edid != nil ? "I2C" : "none")): \(edid.map { "v\($0.vendorID) p\($0.productID) s\($0.serialNumber)" } ?? "–")")
                if service.supportsAudioVolume() {
                    audioCapable.append((entry: entry, service: service, displayName: name, edid: edid))
                    logger.info("DDC audio-capable display: '\(name)'")
                } else {
                    logger.info("DDC probe: '\(name)' does not support VCP 0x62")
                    IOObjectRelease(entry)
                }
            }

            guard !audioCapable.isEmpty else {
                logger.info("DDC probe: no audio-capable displays found")
                Task { @MainActor [weak self] in
                    self?.ddcBackedDevices = []
                    self?.services = [:]
                    self?.probeCompleted = true
                    self?.onProbeCompleted?()
                }
                return
            }

            let coreAudioDevices = self.getCoreAudioOutputDevices()
            for ca in coreAudioDevices {
                logger.info("DDC probe: CoreAudio candidate: '\(ca.name)' (uid: \(ca.uid))")
            }

            var matched: [AudioDeviceID: DDCService] = [:]
            var matchedUIDs: [AudioDeviceID: String] = [:]
            var volumes: [AudioDeviceID: Int] = [:]
            var matchedDDCIndices = Set<Int>()

            for caDevice in coreAudioDevices {
                for (i, ddcDisplay) in audioCapable.enumerated() where !matchedDDCIndices.contains(i) {
                    if Self.namesMatch(caDevice.name, ddcDisplay.displayName) {
                        matched[caDevice.id] = ddcDisplay.service
                        matchedUIDs[caDevice.id] = caDevice.uid
                        matchedDDCIndices.insert(i)

                        if let vol = try? ddcDisplay.service.getAudioVolume() {
                            volumes[caDevice.id] = vol.current
                        }

                        logger.info("Matched CoreAudio '\(caDevice.name)' → DDC '\(ddcDisplay.displayName)' (by name)")
                        break
                    }
                }
            }

            for (i, ddcDisplay) in audioCapable.enumerated() where !matchedDDCIndices.contains(i) {
                guard let edid = ddcDisplay.edid else { continue }

                for caDevice in coreAudioDevices where !matched.keys.contains(caDevice.id) {
                    if Self.edidMatchesUID(edid, uid: caDevice.uid) {
                        matched[caDevice.id] = ddcDisplay.service
                        matchedUIDs[caDevice.id] = caDevice.uid
                        matchedDDCIndices.insert(i)

                        if let vol = try? ddcDisplay.service.getAudioVolume() {
                            volumes[caDevice.id] = vol.current
                        }

                        logger.info("Matched CoreAudio '\(caDevice.name)' → DDC '\(ddcDisplay.displayName)' (by I2C EDID uid prefix v\(edid.vendorID) p\(edid.productID))")
                        break
                    }
                }
            }

            let displayTransports: Set<TransportType> = [.hdmi, .displayPort, .thunderbolt]
            let unmatchedDisplayDevices = coreAudioDevices.filter { ca in
                !matched.keys.contains(ca.id) && displayTransports.contains(ca.transport)
            }
            let unmatchedDDC = audioCapable.enumerated().filter { !matchedDDCIndices.contains($0.offset) }

            for (i, ddcDisplay) in unmatchedDDC {
                for caDevice in unmatchedDisplayDevices where !matched.keys.contains(caDevice.id) {
                    matched[caDevice.id] = ddcDisplay.service
                    matchedUIDs[caDevice.id] = caDevice.uid
                    matchedDDCIndices.insert(i)

                    if let vol = try? ddcDisplay.service.getAudioVolume() {
                        volumes[caDevice.id] = vol.current
                    }

                    logger.info("Matched CoreAudio '\(caDevice.name)' → DDC '\(ddcDisplay.displayName)' (by transport fallback: \(caDevice.transport))")
                    break
                }
            }

            for item in audioCapable {
                IOObjectRelease(item.entry)
            }

            let matchedSnapshot = matched
            let matchedUIDsSnapshot = matchedUIDs
            let volumesSnapshot = volumes
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.services = matchedSnapshot
                self.deviceUIDs = matchedUIDsSnapshot
                self.ddcBackedDevices = Set(matchedSnapshot.keys)

                for (deviceID, uid) in matchedUIDsSnapshot {
                    if let savedVolume = self.settingsManager.getDDCVolume(for: uid) {
                        self.cachedVolumes[deviceID] = savedVolume
                        let service = matchedSnapshot[deviceID]
                        self.ddcQueue.async {
                            try? service?.setAudioVolume(savedVolume)
                        }
                    } else if let readVolume = volumesSnapshot[deviceID] {
                        self.cachedVolumes[deviceID] = readVolume
                    }
                }

                self.logger.info("DDC probe complete: \(matchedSnapshot.count) display(s) matched")
                self.probeCompleted = true
                self.onProbeCompleted?()
            }
        }
    }

    // MARK: - CoreAudio Device Discovery

    private struct CoreAudioDeviceInfo: Sendable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let transport: TransportType
    }

    private nonisolated func getCoreAudioOutputDevices() -> [CoreAudioDeviceInfo] {
        guard let deviceIDs = try? AudioObjectID.readDeviceList() else { return [] }

        var results: [CoreAudioDeviceInfo] = []
        for deviceID in deviceIDs {
            guard !deviceID.isAggregateDevice(),
                  !deviceID.isVirtualDevice(),
                  deviceID.hasOutputStreams() else { continue }

            guard let uid = try? deviceID.readDeviceUID(),
                  let name = try? deviceID.readDeviceName() else { continue }

            results.append(CoreAudioDeviceInfo(id: deviceID, uid: uid, name: name, transport: deviceID.readTransportType()))
        }
        return results
    }

    // MARK: - Matching Helpers

    private nonisolated static func edidMatchesUID(_ edid: DisplayEDID, uid: String) -> Bool {
        let productSwapped = ((edid.productID & 0xFF) << 8) | ((edid.productID >> 8) & 0xFF)
        let prefix = String(format: "%04x%04x", edid.vendorID, productSwapped)
        return uid.lowercased().hasPrefix(prefix)
    }

    private nonisolated static func namesMatch(_ a: String, _ b: String) -> Bool {
        let normA = a.trimmingCharacters(in: .whitespaces).lowercased()
        let normB = b.trimmingCharacters(in: .whitespaces).lowercased()
        if normA == normB { return true }
        if normA.contains(normB) || normB.contains(normA) { return true }
        return false
    }

    // MARK: - Display Name from IOKit

    private nonisolated static func getDisplayName(for entry: io_service_t) -> String {
        var current = entry
        IOObjectRetain(current)

        var needsRelease = true
        for _ in 0..<10 {
            if let name = displayNameFromEntry(current) {
                IOObjectRelease(current)
                return name
            }

            var next: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            guard kr == kIOReturnSuccess else {
                needsRelease = false
                break
            }
            current = next
        }

        if needsRelease {
            IOObjectRelease(current)
        }

        return "External Display"
    }

    private nonisolated static func displayNameFromEntry(_ entry: io_service_t) -> String? {
        guard let info = IODisplayCreateInfoDictionary(entry, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any],
              let names = info[kDisplayProductName] as? [String: String],
              let name = names.values.first else {
            return nil
        }
        return name
    }

    // MARK: - Display Change Observer

    private func setupDisplayChangeObserver() {
        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.probeWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.logger.debug("Display configuration changed, re-probing DDC (after delay)")
                        self.probe()
                    }
                }
                self.probeWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
            }
        }
    }
}

#endif