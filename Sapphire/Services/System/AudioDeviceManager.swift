//
//  AudioDeviceManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-08.
//

import Foundation
import Combine
import AudioToolbox

struct AudioSwitchEvent: Hashable {
    enum Direction: Hashable {
        case switchedToMac
        case switchedAwayFromMac
    }

    let id = UUID()
    let deviceName: String
    let direction: Direction
}

class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published var lastSwitchEvent: AudioSwitchEvent?

    private var previousDeviceName: String?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {

        DispatchQueue.main.async {
            self.setupAudioListener()

            self.previousDeviceName = self.getCurrentDeviceName()
        }
    }

    deinit {
        if let defaultOutputListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, defaultOutputListener)
        }
    }

    private func setupAudioListener() {
        guard defaultOutputListener == nil else { return }
        let propertyListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceChange()
        }

        var address = Self.defaultOutputAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            propertyListener
        )
        if status == noErr {
            defaultOutputListener = propertyListener
        }
    }

    private func handleDeviceChange() {
        let newDeviceName = getCurrentDeviceName()

        guard newDeviceName != previousDeviceName else { return }

        let didSwitchAway = isAutoSwitchDevice(name: previousDeviceName) && !isAutoSwitchDevice(name: newDeviceName)
        let didSwitchTo = !isAutoSwitchDevice(name: previousDeviceName) && isAutoSwitchDevice(name: newDeviceName)

        if didSwitchAway, let name = previousDeviceName {
            lastSwitchEvent = AudioSwitchEvent(deviceName: name, direction: .switchedAwayFromMac)
        } else if didSwitchTo, let name = newDeviceName {
            lastSwitchEvent = AudioSwitchEvent(deviceName: name, direction: .switchedToMac)
        }

        self.previousDeviceName = newDeviceName
    }

    private func isAutoSwitchDevice(name: String?) -> Bool {
        guard let lowercasedName = name?.lowercased() else { return false }
        let keywords = ["airpods", "beats", "powerbeats"]
        return keywords.contains { lowercasedName.contains($0) }
    }

    func getCurrentOutputDevice() -> AudioDevice? {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID) == noErr else {
            return nil
        }

        guard let name = CoreAudioDevices.name(of: deviceID), let uid = CoreAudioDevices.uid(of: deviceID) else {
            return nil
        }

        return AudioDevice(id: deviceID, uid: uid, name: name, isInput: false, isOutput: true)
    }

    private func getCurrentDeviceName() -> String? {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID) == noErr else {
            return nil
        }

        return CoreAudioDevices.name(of: deviceID)
    }

}