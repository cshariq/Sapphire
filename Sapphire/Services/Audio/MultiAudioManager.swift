//
//  MultiAudioManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//
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
    var balance: Double = 0.0 // -1.0 (Left) to 1.0 (Right)
    var delay: TimeInterval = 0.0 // in seconds
    var equalizer: EQPreset = .flat
    var customEQGains: [Double] = EQPreset.flat.gainValues // Holds the 10-band EQ values
}

@MainActor
class MultiAudioManager: ObservableObject {
    static let shared = MultiAudioManager()

    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var availableInputDevices: [AudioDevice] = []
    @Published var currentInputDeviceID: AudioDeviceID?

    @Published var selectedOutputDeviceIDs: Set<AudioDeviceID> = [] {
        didSet {
            deviceSettings = deviceSettings.filter { selectedOutputDeviceIDs.contains($0.key) }
            recreateAggregateDevice()
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

    func updateSettings(for deviceID: AudioDeviceID, settings: AudioDeviceSettings) {
        self.deviceSettings[deviceID] = settings
        if let aggID = aggregateDeviceID, selectedOutputDeviceIDs.contains(deviceID) {
            applySettings(for: deviceID, settings: settings)
        }
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

        for deviceID in deviceIDs {
            guard let name = getDeviceName(for: deviceID),
                  let uid = getDeviceUID(for: deviceID),
                  !isSoftwareDevice(for: deviceID), // <-- CORRECTED: Using more comprehensive check
                  !name.contains("Sapphire Multi-Output") else {
                continue
            }

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

    }

    private func applySettings(for deviceID: AudioDeviceID, settings: AudioDeviceSettings) {
        print("[MultiAudioManager] Applying settings for device \(deviceID): Volume=\(settings.volume), Balance=\(settings.balance)")

        setDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 1, value: Float(settings.volume)) // Channel 1 (Left)
        setDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 2, value: Float(settings.volume)) // Channel 2 (Right)

        setDeviceProperty(deviceID: deviceID, selector: kAudioDevicePropertyStereoPan, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, value: Float(settings.balance))

    }

    // MARK: - Core Audio Helper Functions

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

        if status != noErr {
            return false // Assume it's a physical device if we can't get the property.
        }

        return transportType == kAudioDeviceTransportTypeVirtual || transportType == kAudioDeviceTransportTypeAggregate
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
        let totalChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }

        return totalChannels > 0
    }

    private func getDefaultDevice(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        return status == noErr ? deviceID : nil
    }

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

    private func setDeviceProperty<T>(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement, value: T) {
        var mutableValue = value
        let dataSize = UInt32(MemoryLayout.size(ofValue: mutableValue))
        var propertyAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &mutableValue)
        if status != noErr {
            print("[MultiAudioManager] Error setting property \(selector.fourCharCode) for device \(deviceID): \(status)")
        }
    }
}

extension FourCharCode {
    var fourCharCode: String {
        return String(format: "%c%c%c%c", (self >> 24) & 0xFF, (self >> 16) & 0xFF, (self >> 8) & 0xFF, self & 0xFF).trimmingCharacters(in: .whitespaces)
    }
}