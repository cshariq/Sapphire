//
//  AirPlayManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import AppKit
import CoreAudio
import ApplicationServices

enum AirPlaySwitchResult: Equatable {
    case success
    case deviceNotFound
    case soundMenuNotAvailable
    case requiresAccessibility
    case failed(String)
}

private let airPlaySwitchScript = """
on run argv
    if (count of argv) is 0 then
        return "ERROR_NO_TARGET"
    end if
    set targetDeviceName to item 1 of argv
    set soundMenuNames to {"Sound", "Dźwięk", "Volume", "Audio", "Ton", "Son"}
    tell application "System Events"
        tell process "ControlCenter"
            set soundItem to missing value
            repeat with currentName in soundMenuNames
                repeat with menuBarItem in every menu bar item of menu bar 1
                    set itemLabel to ""
                    try
                        set itemLabel to description of menuBarItem as text
                    end try
                    if itemLabel is currentName then
                        set soundItem to menuBarItem
                        exit repeat
                    end if
                    try
                        set itemLabel to title of menuBarItem as text
                    end try
                    if itemLabel is currentName then
                        set soundItem to menuBarItem
                        exit repeat
                    end if
                end repeat
                if soundItem is not missing value then
                    exit repeat
                end if
            end repeat
            if soundItem is missing value then
                return "ERROR_SOUND_MENU_NOT_FOUND"
            end if
            click soundItem
            delay 0.6
            set deviceCheckboxes to {}
            try
                set deviceCheckboxes to every checkbox of scroll area 1 of group 1 of window "Control Center"
            on error
                try
                    set deviceCheckboxes to every checkbox of window "Control Center"
                end try
            end try
            set targetCheckbox to missing value
            repeat with currentCheckbox in deviceCheckboxes
                try
                    set deviceId to value of attribute "AXIdentifier" of currentCheckbox as text
                    if deviceId contains targetDeviceName then
                        set targetCheckbox to currentCheckbox
                        exit repeat
                    end if
                end try
            end repeat
            if targetCheckbox is missing value then
                repeat with currentCheckbox in deviceCheckboxes
                    try
                        repeat with t in static texts of currentCheckbox
                            if (value of t as text) contains targetDeviceName then
                                set targetCheckbox to currentCheckbox
                                exit repeat
                            end if
                        end repeat
                    end try
                    if targetCheckbox is not missing value then
                        exit repeat
                    end if
                end repeat
            end if
            if targetCheckbox is missing value then
                click soundItem
                return "ERROR_DEVICE_NOT_FOUND"
            end if
            click targetCheckbox
            delay 0.4
            click soundItem
            return "OK"
        end tell
    end tell
end run
"""

@MainActor
final class AirPlayManager: NSObject, ObservableObject {
    static let shared = AirPlayManager()

    @Published private(set) var devices: [AirPlayDevice] = []

    private let airPlayBrowser = NetServiceBrowser()
    private let raopBrowser = NetServiceBrowser()
    private var airPlayServices: [String: NetService] = [:]
    private var raopServices: [String: NetService] = [:]
    private var isBrowsing = false

    override private init() {
        super.init()
        airPlayBrowser.delegate = self
        raopBrowser.delegate = self
    }

    // MARK: - Discovery Lifecycle

    func startDiscovery() {
        guard !isBrowsing else { return }
        isBrowsing = true
        airPlayBrowser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
        raopBrowser.searchForServices(ofType: "_raop._tcp.", inDomain: "local.")
    }

    func stopDiscovery() {
        guard isBrowsing else { return }
        isBrowsing = false
        airPlayBrowser.stop()
        raopBrowser.stop()
        airPlayServices.removeAll()
        raopServices.removeAll()
        rebuildDevices()
    }

    func refresh() {
        rebuildDevices()
    }

    // MARK: - Switching (Control Center UI scripting)

    func switchTo(_ device: AirPlayDevice) async -> AirPlaySwitchResult {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            return .requiresAccessibility
        }

        let output = await Task.detached(priority: .userInitiated) {
            Self.runOsascript(airPlaySwitchScript, arguments: [device.name])
        }.value

        guard let output else { return .failed("osascript failed") }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmed {
        case "OK":
            return .success
        case "ERROR_DEVICE_NOT_FOUND":
            return .deviceNotFound
        case "ERROR_SOUND_MENU_NOT_FOUND":
            return .soundMenuNotAvailable
        default:
            return .failed(trimmed.isEmpty ? "empty result" : trimmed)
        }
    }

    // MARK: - Volume

    func setVolume(_ volume: Int, forDeviceNamed name: String) {
        guard let deviceID = Self.outputDeviceID(named: name) else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float(min(max(volume, 0), 100)) / 100.0
        var status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
        if status != noErr {
            address.mElement = 1
            status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
        }
    }

    // MARK: - Device Aggregation

    private func rebuildDevices() {
        let currentOutputName = Self.defaultOutputDeviceName()?.lowercased()

        var byName: [String: AirPlayDevice] = [:]

        for service in airPlayServices.values {
            let name = Self.displayName(for: service.name, isRAOP: false)
            guard !name.isEmpty else { continue }
            let isSelected = name.lowercased() == currentOutputName
            let volume = isSelected ? Self.outputVolumePercent(forDeviceNamed: name) : nil
            byName[name] = AirPlayDevice(name: name, isAudioOnly: false, isSelected: isSelected, volume: volume)
        }

        for service in raopServices.values {
            let name = Self.displayName(for: service.name, isRAOP: true)
            guard !name.isEmpty, byName[name] == nil else { continue }
            let isSelected = name.lowercased() == currentOutputName
            let volume = isSelected ? Self.outputVolumePercent(forDeviceNamed: name) : nil
            byName[name] = AirPlayDevice(name: name, isAudioOnly: true, isSelected: isSelected, volume: volume)
        }

        let rebuilt = byName.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard rebuilt != devices else { return }
        devices = rebuilt
    }

    private static func displayName(for rawName: String, isRAOP: Bool) -> String {
        var name = rawName
        if isRAOP, let atIndex = name.firstIndex(of: "@") {
            name = String(name[name.index(after: atIndex)...])
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Core Audio Helpers

    private static func defaultOutputDeviceName() -> String? {
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }

        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    private static func outputDeviceID(named name: String) -> AudioDeviceID? {
        let target = name.lowercased()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return nil }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return nil
        }

        for deviceID in deviceIDs {
            guard hasOutputChannels(deviceID) else { continue }

            var deviceName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = withUnsafeMutablePointer(to: &deviceName) { ptr in
                AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
            }
            guard status == noErr else { continue }
            if (deviceName as String).lowercased() == target {
                return deviceID
            }
        }
        return nil
    }

    private static func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func outputVolumePercent(forDeviceNamed name: String) -> Int? {
        guard let deviceID = outputDeviceID(named: name) else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) != noErr {
            address.mElement = 1
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else { return nil }
        }
        return Int((volume * 100).rounded())
    }

    // MARK: - osascript

    private nonisolated static func runOsascript(_ script: String, arguments: [String]) -> String? {
        guard let result = ProcessRunner.runSync(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", script] + arguments,
            timeout: 8
        ), result.succeeded else { return nil }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}

// MARK: - NetServiceBrowserDelegate

extension AirPlayManager: @preconcurrency NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if browser === airPlayBrowser {
            airPlayServices[service.name] = service
        } else {
            raopServices[service.name] = service
        }
        if !moreComing { rebuildDevices() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if browser === airPlayBrowser {
            airPlayServices.removeValue(forKey: service.name)
        } else {
            raopServices.removeValue(forKey: service.name)
        }
        if !moreComing { rebuildDevices() }
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        rebuildDevices()
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        rebuildDevices()
    }
}