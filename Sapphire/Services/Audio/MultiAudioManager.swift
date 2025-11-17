//
//  MultiAudioManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import Foundation
import CoreAudio
import AVFoundation
import Combine

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isInput: Bool
    let isOutput: Bool
}

struct AudioDeviceSettings: Equatable {
    var volume: Double = 1.0
    var balance: Double = 0.5
    var delay: TimeInterval = 0.0
    var equalizer: EQPreset = .flat
    var customEQGains: [Double] = EQPreset.flat.gainValues
}

@MainActor
class MultiAudioManager: ObservableObject {
    static let shared = MultiAudioManager()

    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var availableInputDevices: [AudioDevice] = []
    @Published var currentInputDeviceID: AudioDeviceID?

    @Published var selectedOutputDeviceIDs: Set<AudioDeviceID> = [] {
        didSet {
            if !selectedOutputDeviceIDs.contains(where: { getDeviceUID(for: $0) == masterDeviceUID }) {
                masterDeviceUID = getDeviceUID(for: selectedOutputDeviceIDs.first ?? 0)
            }
            deviceSettings = deviceSettings.filter { selectedOutputDeviceIDs.contains($0.key) }
            recreateAggregateDevice()
        }
    }

    @Published var masterDeviceUID: String? {
        didSet {
            if oldValue != masterDeviceUID {
                recreateAggregateDevice()
            }
        }
    }

    @Published var deviceSettings: [AudioDeviceID: AudioDeviceSettings] = [:]

    private var aggregateDeviceID: AudioDeviceID? = nil
    private var originalDefaultOutputID: AudioDeviceID? = nil

    private init() {
        self.originalDefaultOutputID = getDefaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
        discoverDevices()
        setupDeviceListeners()
    }

    deinit {}

    public func cleanup() {
        destroyAggregateDevice { [weak self] in
            guard let self = self else { return }
            self.availableOutputDevices.forEach { device in
                self.resetDeviceAdjustments(deviceID: device.id)
            }
            if let originalID = self.originalDefaultOutputID {
                self.setSystemDefaultDevice(originalID, for: kAudioHardwarePropertyDefaultOutputDevice)
            }
        }
    }

    func updateSettings(for deviceID: AudioDeviceID, settings: AudioDeviceSettings) {
        self.deviceSettings[deviceID] = settings

        if let aggID = aggregateDeviceID, selectedOutputDeviceIDs.contains(deviceID), let deviceUID = getDeviceUID(for: deviceID) {
            setSubDeviceVolume(uid: deviceUID, volume: Float(settings.volume))
        }

        applyDeviceAdjustments(deviceID: deviceID, settings: settings)
    }

    func setDefaultInputDevice(to deviceID: AudioDeviceID) {
        if setSystemDefaultDevice(deviceID, for: kAudioHardwarePropertyDefaultInputDevice) {
            self.currentInputDeviceID = deviceID
        }
    }

    private func discoverDevices() {
        var outputs: [AudioDevice] = []
        var inputs: [AudioDevice] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize) == noErr else { return }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceIDs) == noErr else { return }

        let existingAggregateUID = "com.shariq.sapphire.multi-output-device"

        for deviceID in deviceIDs {
            guard let name = getDeviceName(for: deviceID),
                  let uid = getDeviceUID(for: deviceID) else {
                continue
            }

            if uid == existingAggregateUID {
                self.aggregateDeviceID = deviceID
                continue
            }

            guard !isSoftwareDevice(for: deviceID) else { continue }

            let isInput = hasChannels(for: deviceID, scope: kAudioObjectPropertyScopeInput)
            let isOutput = hasChannels(for: deviceID, scope: kAudioObjectPropertyScopeOutput)

            if isInput || isOutput {
                let device = AudioDevice(id: deviceID, uid: uid, name: name, isInput: isInput, isOutput: isOutput)
                if isOutput { outputs.append(device) }
                if isInput { inputs.append(device) }
            }
        }

        self.availableOutputDevices = outputs
        self.availableInputDevices = inputs
        self.currentInputDeviceID = getDefaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
    }

    private func setupDeviceListeners() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, { _, _, _, _ in
            DispatchQueue.main.async {
                MultiAudioManager.shared.discoverDevices()
            }
            return 0
        }, nil)
    }

    private func recreateAggregateDevice() {
        destroyAggregateDevice { [weak self] in
            guard let self = self else { return }

            guard self.selectedOutputDeviceIDs.count > 1 else {
                if let singleDeviceID = self.selectedOutputDeviceIDs.first {
                    self.setSystemDefaultDevice(singleDeviceID, for: kAudioHardwarePropertyDefaultOutputDevice)
                } else if let originalID = self.originalDefaultOutputID {
                    self.setSystemDefaultDevice(originalID, for: kAudioHardwarePropertyDefaultOutputDevice)
                }
                return
            }

            guard let masterUID = self.masterDeviceUID,
                  let masterDevice = self.availableOutputDevices.first(where: { $0.uid == masterUID }) else {
                return
            }

            let subDeviceUIDs = self.selectedOutputDeviceIDs.compactMap { self.getDeviceUID(for: $0) }

            BatteryManager.shared.getHelper()?.createAggregateDevice(subDeviceUIDs: subDeviceUIDs, masterDeviceUID: masterUID) { newDeviceID in
                guard newDeviceID != 0 else { return }

                DispatchQueue.main.async {
                    self.aggregateDeviceID = newDeviceID
                    self.setSystemDefaultDevice(newDeviceID, for: kAudioHardwarePropertyDefaultOutputDevice)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if let sampleRate = self.getDeviceSampleRate(deviceID: masterDevice.id) {
                            self.setDeviceProperty(deviceID: newDeviceID, selector: kAudioDevicePropertyNominalSampleRate, scope: kAudioObjectPropertyScopeOutput, value: sampleRate)
                            print("[MultiAudioManager] Stably set sample rate to \(sampleRate)Hz on aggregate device \(newDeviceID).")
                        }
                    }
                }
            }
        }
    }

    private func destroyAggregateDevice(completion: (() -> Void)? = nil) {
        guard let deviceID = self.aggregateDeviceID else {
            completion?()
            return
        }

        self.aggregateDeviceID = nil

        BatteryManager.shared.getHelper()?.destroyAggregateDevice(id: deviceID) { success in
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    private func setSubDeviceVolume(uid: String, volume: Float) {
        guard let aggID = aggregateDeviceID else { return }
        BatteryManager.shared.getHelper()?.setAggregateSubDeviceVolume(aggregateDeviceID: aggID, subDeviceUID: uid, volume: volume, reply: { _ in })
    }

    private func applyDeviceAdjustments(deviceID: AudioDeviceID, settings: AudioDeviceSettings) {
        setDeviceProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyStereoPan,
            scope: kAudioObjectPropertyScopeOutput,
            value: Float(settings.balance)
        )

        let sampleRate = getDeviceSampleRate(deviceID: deviceID) ?? 44100.0
        let latencyInFrames = UInt32(settings.delay * sampleRate)

        setDeviceProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyLatency,
            scope: kAudioObjectPropertyScopeOutput,
            value: latencyInFrames
        )
    }

    private func resetDeviceAdjustments(deviceID: AudioDeviceID) {
        setDeviceProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyStereoPan,
            scope: kAudioObjectPropertyScopeOutput,
            value: Float(0.0)
        )
        setDeviceProperty(
            deviceID: deviceID,
            selector: kAudioDevicePropertyLatency,
            scope: kAudioObjectPropertyScopeOutput,
            value: UInt32(0)
        )
    }

    // MARK: - Core Audio Helper Functions

    private func getDeviceSampleRate(deviceID: AudioDeviceID) -> Double? {
        var sampleRate: Double = 0
        var propertySize = UInt32(MemoryLayout.size(ofValue: sampleRate))

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &sampleRate) == noErr else {
            return nil
        }
        return sampleRate
    }

    private func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &name) == noErr else { return nil }
        return name as String
    }

    private func getDeviceUID(for deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &uid) == noErr else { return nil }
        return uid as String
    }

    private func isSoftwareDevice(for deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &transportType)
        if status != noErr { return false }
        return transportType == kAudioDeviceTransportTypeVirtual
    }

    private func hasChannels(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize) == noErr, propertySize > 0 else {
            return false
        }
        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferListPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, bufferListPtr) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func getDefaultDevice(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        return status == noErr ? deviceID : nil
    }

    @discardableResult
    private func setSystemDefaultDevice(_ deviceID: AudioDeviceID, for selector: AudioObjectPropertySelector) -> Bool {
        var deviceIDVar = deviceID
        let propertySize = UInt32(MemoryLayout.size(ofValue: deviceIDVar))
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, propertySize, &deviceIDVar)
        if status != noErr {
            print("[MultiAudioManager] Error setting default device (\(selector.fourCharCode)): \(status)")
        }
        return status == noErr
    }

    private func setDeviceProperty<T>(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, value: T) {
        var mutableValue = value
        let dataSize = UInt32(MemoryLayout.size(ofValue: mutableValue))
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &mutableValue)
        if status != noErr {
            print("[MultiAudioManager] Error \(status) setting property \(selector.fourCharCode) for device \(deviceID)")
        }
    }
}

extension UInt32 {
    var fourCharCode: String {
        return String(format: "%c%c%c%c", (self >> 24) & 0xFF, (self >> 16) & 0xFF, (self >> 8) & 0xFF, self & 0xFF).trimmingCharacters(in: .whitespaces)
    }
}