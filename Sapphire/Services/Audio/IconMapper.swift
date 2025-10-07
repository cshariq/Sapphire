//
//  IconMapper.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-25.
//
//

import Foundation
import CoreAudio
import IOBluetooth

struct IconMapper {

    private static let mainsPoweredKeywords: [String] = [
        "usb hub", "receiver", "dock", "adapter", "dongle", "display audio",
        "studio display", "echo dot", "echo show", "echo studio", "echo pop",
        "nest hub", "nest audio", "google home", "homepod", "apple tv",
        "soundbar", "printer", "scanner", "xserve"
    ]

    static func cleanDeviceName(_ name: String) -> String {
        let suffixesToRemove = [" (ANC)", " - Find My"]
        var cleanedName = name
        for suffix in suffixesToRemove {
            cleanedName = cleanedName.replacingOccurrences(of: suffix, with: "")
        }
        return cleanedName
    }

    static func isBatteryPowered(for device: IOBluetoothDevice) -> Bool {
        guard let name = device.name else { return true } // Assume battery if name is unknown
        let lowercasedName = name.lowercased()

        for keyword in mainsPoweredKeywords {
            if lowercasedName.contains(keyword) {
                return false
            }
        }

        return true
    }

    private static let universalDeviceMap: [(keywords: [String], icon: String)] = [
        (["macbook"], "macbook"),
        (["imac"], "desktopcomputer"),
        (["mac mini"], "macmini.fill"),
        (["mac studio"], "macstudio.fill"),
        (["mac pro"], "macpro.gen3.fill"),
        (["studio display", "apple display"], "display"),
        (["xserve"], "xserve"),

        (["iphone"], "iphone"),
        (["ipad"], "ipad"),
        (["apple watch"], "applewatch"),
        (["vision pro"], "visionpro"),

        (["magic keyboard"], "keyboard.fill"),
        (["magic mouse"], "magicmouse.fill"),
        (["magic trackpad"], "magictrackpad.fill"),
        (["apple pencil"], "applepencil"),
        (["airtag"], "airtag.fill"),

        (["airpods max"], "airpods.max"),
        (["airpods pro"], "airpods.pro"),
        (["airpods 4"], "airpods.gen4"),
        (["airpods 3"], "airpods gen3"),
        (["airpods 2", "airpods"], "airpods"),
        (["earpods"], "earpods"),
        (["homepod mini"], "homepod.mini"),
        (["homepod"], "homepod"),
        (["beats fit pro"], "beats.fitpro"),
        (["studio buds plus"], "beats.studiobuds.plus"),
        (["studio buds"], "beats.studiobuds"),
        (["solobuds"], "beats.solobuds"),
        (["powerbeats pro 2"], "beats.powerbeats.pro.2"),
        (["powerbeats pro"], "beats.powerbeats.pro"),
        (["powerbeats3"], "beats.powerbeats3"),
        (["powerbeats"], "beats.powerbeats"),
        (["beats pill"], "beats.pill"),
        (["beats flex", "beats ep", "beats earphones"], "beats.earphones"),
        (["beats headphones"], "beats.headphones"),

        (["echo dot"], "homepod.mini"),
        (["echo show"], "homepod"),
        (["echo studio", "echo pop", "echo plus", "echo link", "echo"], "hifispeaker"),

        (["pixel buds pro", "pixel buds a-series", "pixel buds"], "earbuds.stemless"),
        (["nest mini", "nest audio", "nest wifi point"], "homepod.mini"),
        (["nest hub"], "homepod"),

        (["galaxy buds 3 pro"], "airpods.pro"),
        (["galaxy buds 3"], "airpods.gen4"),
        (["galaxy buds live", "galaxy buds2 pro", "galaxy buds2", "galaxy buds pro", "galaxy buds+", "galaxy buds fe", "galaxy buds"], "earbuds.stemless"),

        (["wh", "wf", "sony headphones"], "airpods.max"),
        (["linkbuds s", "linkbuds"], "earbuds.in.ear"),
        (["srs-xb43", "srs-xe200", "srs-xg300", "ht-a5000", "ht-g700", "ht-s40r", "sony speaker"], "hifispeaker"),

        (["qc ultra earbuds", "qc earbuds ii", "bose sport earbuds"], "earbuds.in.ear"),
        (["qc 45", "qc 35", "qc ultra headphones", "bose headphones"], "airpods.max"),
        (["bose home speaker", "bose soundbar", "bose portable smart speaker"], "hifispeaker"),
        (["bose frames", "bose tempo"], "headphones"),

        (["dualsense", "dualshock", "playstation"], "gamecontroller.fill"),
        (["xbox wireless controller", "xbox elite"], "gamecontroller.fill"),
        (["nintendo", "joy-con", "switch pro controller"], "gamecontroller.fill"),

        (["logitech mouse", "razer mouse", "mx master"], "computermouse.fill"),
        (["logitech", "razer", "keychron", "nuphy", "mechanical keyboard"], "keyboard.fill"),

        (["sennheiser", "momentum", "pxc", "hd 280", "hd 450", "hd 600", "hd 800"], "headphones.over.ear"),
        (["jbl", "anker", "soundcore"], "hifispeaker"),
        (["shure", "mv7", "sm7b", "sm58"], "mic.fill"),

        (["printer"], "printer.fill"),
        (["scanner"], "scanner.fill"),
    ]

    static func icon(forName name: String) -> String? {
        let lowercasedName = name.lowercased()
        for (keywords, icon) in universalDeviceMap {
            if keywords.contains(where: { lowercasedName.contains($0) }) {
                return icon
            }
        }
        return nil
    }

    static func icon(for device: AudioDevice) -> String {
        let name = device.name
        let lowerName = name.lowercased()
        if lowerName.contains("macbook pro speakers") || lowerName.contains("macbook air speakers") { return "laptopcomputer" }
        if lowerName.contains("macbook pro microphone") || lowerName.contains("macbook air microphone") { return "mic.fill" }
        if lowerName.contains("studio display") || lowerName.contains("display audio") { return "display" }
        if lowerName.contains("mac studio speakers") { return "desktopcomputer" }
        if lowerName.contains("apple tv") { return "tv" }

        if let universalIcon = icon(forName: name) {
            return universalIcon
        }

        if lowerName.contains("mic") || device.isInput { return "mic.circle.fill" }
        if lowerName.contains("earbuds") || lowerName.contains("earphones") || lowerName.contains("buds") { return "earbuds" }
        if lowerName.contains("headphones") || lowerName.contains("headset") || lowerName.contains("over-ear") { return "headphones.over.ear" }
        if lowerName.contains("speaker") || lowerName.contains("soundbar") { return "hifispeaker" }

        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device.id, &propertyAddress, 0, nil, &propertySize, &transportType)

        guard status == noErr else { return device.isInput ? "mic.circle.fill" : "hifispeaker" }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: return device.isInput ? "mic.fill" : "speaker.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return lowerName.contains("head") || lowerName.contains("buds") ? "headphones" : "hifispeaker"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker.and.appletv.fill"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeThunderbolt: return "bolt.fill"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        default: return device.isInput ? "mic.circle.fill" : "hifispeaker"
        }
    }

    static func icon(for device: IOBluetoothDevice) -> String {
        let name = device.name ?? ""

        if let universalIcon = icon(forName: name) {
            return universalIcon
        }

        let lowerName = name.lowercased()
        let majorClass = device.deviceClassMajor
        let minorClass = device.deviceClassMinor

        switch majorClass {
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            switch minorClass {
            case UInt32(kBluetoothDeviceClassMinorPeripheral1Keyboard): return "keyboard.fill"
            case UInt32(kBluetoothDeviceClassMinorPeripheral1Pointing):
                if lowerName.contains("trackpad") { return "magictrackpad.fill" }
                if lowerName.contains("mouse") { return "magicmouse.fill" }
                return "computermouse.fill"
            default:
                if lowerName.contains("controller") || lowerName.contains("gamepad") { return "gamecontroller.fill" }
                return "platter.filled.top.applewatch.case"
            }
        case UInt32(kBluetoothDeviceClassMajorAudio):
            if lowerName.contains("headphone") { return "airpods.max" }
            if lowerName.contains("earbud") || lowerName.contains("buds") { return "earbuds" }
            if lowerName.contains("speaker") { return "hifispeaker.fill" }
            return "headphones"
        case UInt32(kBluetoothDeviceClassMajorComputer): return "desktopcomputer"
        case UInt32(kBluetoothDeviceClassMajorPhone): return "iphone"
        case UInt32(kBluetoothDeviceClassMajorWearable): return "applewatch"
        default: return "b.circle.fill"
        }
    }
}