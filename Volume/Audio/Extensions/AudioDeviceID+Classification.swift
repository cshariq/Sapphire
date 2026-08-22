//
//  AudioDeviceID+Classification.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import AudioToolbox

// MARK: - Device Classification

extension AudioDeviceID {
    func isAggregateDevice() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyClass,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var classID: AudioClassID = 0
        var size = UInt32(MemoryLayout<AudioClassID>.size)
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &classID)
        guard err == noErr else { return false }
        return classID == kAudioAggregateDeviceClassID
    }

    func isVirtualDevice() -> Bool {
        readTransportType() == .virtual
    }

    func isHidden() -> Bool {
        (try? readBool(kAudioDevicePropertyIsHidden)) ?? false
    }
}

// MARK: - AutoEQ Eligibility

extension AudioDeviceID {
    func supportsAutoEQ() -> Bool {
        let transport = readTransportType()

        switch transport {
        case .hdmi, .displayPort, .airPlay, .virtual:
            return false
        case .builtIn:
            return builtInHasHeadphonesActive()
        default:
            break
        }

        let name = (try? readDeviceName()) ?? ""
        let excludedNames = ["HomePod", "Apple TV", "Studio Display", "Pro Display XDR"]
        for excluded in excludedNames {
            if name.localizedCaseInsensitiveContains(excluded) { return false }
        }

        return true
    }

    func builtInHasHeadphonesActive() -> Bool {
        guard let sourceID: UInt32 = try? read(
            kAudioDevicePropertyDataSource,
            scope: .output,
            defaultValue: 0
        ), sourceID != 0 else {
            return false
        }

        return sourceID == 0x6864706E
    }
}
// MARK: - Device Icon

extension AudioDeviceID {
    func readDeviceIcon() -> NSImage? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIcon,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        var iconURL: Unmanaged<CFURL>?
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &iconURL)

        guard err == noErr, let url = iconURL?.takeRetainedValue() as URL? else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    func suggestedIconSymbol() -> String {
        let name = (try? readDeviceName()) ?? ""
        let transport = readTransportType()

        if name.contains("AirPods Pro") { return "airpodspro" }
        if name.contains("AirPods Max") { return "airpodsmax" }
        if name.contains("AirPods") { return "airpods.gen3" }

        if name.contains("HomePod mini") { return "homepodmini" }
        if name.contains("HomePod") { return "homepod" }

        if name.contains("Apple TV") { return "appletv" }

        if name.contains("Beats") { return "beats.headphones" }

        if name.contains("Mac Studio") { return "macstudio.fill" }
        if name.contains("Mac mini") { return "macmini.fill" }
        if name.contains("MacBook") { return "macbook" }
        if name.contains("iMac") { return "desktopcomputer" }

        if name.contains("Studio Display") { return "display" }
        if name.contains("Pro Display XDR") { return "display" }

        return transport.defaultIconSymbol
    }

    func suggestedInputIconSymbol() -> String {
        let name = (try? readDeviceName()) ?? ""
        let transport = readTransportType()

        if name.contains("iPhone") { return "iphone" }

        if name.contains("iPad") { return "ipad" }

        if name.contains("AirPods Pro") { return "airpodspro" }
        if name.contains("AirPods Max") { return "airpodsmax" }
        if name.contains("AirPods") { return "airpods.gen3" }

        if name.contains("Beats") { return "beats.headphones" }

        if name.contains("MacBook") { return "laptopcomputer" }

        if name.contains("Studio Display") { return "display" }
        if name.contains("Pro Display XDR") { return "display" }

        switch transport {
        case .builtIn:
            return "mic"
        case .usb:
            return "cable.connector"
        case .bluetooth, .bluetoothLE:
            return "mic"
        default:
            return "mic"
        }
    }
}