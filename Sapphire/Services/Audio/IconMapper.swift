//
//  IconMapper.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-25.
//

import Foundation
import CoreAudio
import IOBluetooth

enum BatteryStatus {
    case hasBattery
    case noBattery
    case unknown
}

struct IconMapper {

    private static let learnedBatteryDevicesKey = "learnedBatteryDevices"

    static func cleanDeviceName(_ name: String) -> String {
        let suffixesToRemove = [" (ANC)", " - Find My"]
        var cleanedName = name
        for suffix in suffixesToRemove {
            cleanedName = cleanedName.replacingOccurrences(of: suffix, with: "")
        }
        return cleanedName
    }

    static func getBatteryStatus(for device: IOBluetoothDevice) -> BatteryStatus {
        guard let name = device.name, !name.isEmpty, let address = device.addressString else {
            return .noBattery
        }

        let lowercasedName = name.lowercased()
        if let matchedDevice = universalDeviceMap.first(where: { entry in
            entry.keywords.contains { keyword in lowercasedName.contains(keyword) }
        }) {
            return matchedDevice.hasBattery ? .hasBattery : .noBattery
        }

        if let learnedDevices = UserDefaults.standard.dictionary(forKey: learnedBatteryDevicesKey) as? [String: Bool] {
            if let hasBattery = learnedDevices[address] {
                return hasBattery ? .hasBattery : .noBattery
            }
        }

        return .unknown
    }

    static func learnDeviceBatteryStatus(address: String, hasBattery: Bool) {
        var learnedDevices = UserDefaults.standard.dictionary(forKey: learnedBatteryDevicesKey) as? [String: Bool] ?? [:]
        learnedDevices[address] = hasBattery
        UserDefaults.standard.set(learnedDevices, forKey: learnedBatteryDevicesKey)
        print("[IconMapper] Learned that device \(address) " + (hasBattery ? "HAS a battery." : "does NOT have a battery."))
    }

    private static let universalDeviceMap: [(keywords: [String], icon: String, hasBattery: Bool)] = [
        (["macbook"], "macbook", false),
        (["imac"], "desktopcomputer", false),
        (["mac mini"], "macmini.fill", false),
        (["mac studio"], "macstudio.fill", false),
        (["mac pro"], "macpro.gen3.fill", false),
        (["xserve"], "xserve", false),

        (["studio display", "apple display"], "display", false),

        (["iphone"], "iphone", false),
        (["ipad"], "ipad", false),
        (["apple watch"], "applewatch", false),
        (["vision pro"], "visionpro", false),

        (["magic keyboard"], "keyboard.fill", true),
        (["magic mouse"], "magicmouse.fill", true),
        (["magic trackpad"], "magictrackpad.fill", true),
        (["apple pencil"], "applepencil", true),
        (["airtag"], "airtag.fill", true),

        (["airpods max"], "airpods.max", true),
        (["airpods pro"], "airpods.pro", true),
        (["airpods 4"], "airpods.gen4", true),
        (["airpods 3"], "airpods gen3", true),
        (["airpods 2", "airpods"], "airpods", true),
        (["earpods"], "earpods", false),
        (["homepod mini"], "homepod.mini", false),
        (["homepod"], "homepod", false),
        (["beats fit pro"], "beats.fitpro", true),
        (["studio buds plus"], "beats.studiobuds.plus", true),
        (["studio buds"], "beats.studiobuds", true),
        (["solobuds"], "beats.solobuds", true),
        (["powerbeats pro 2"], "beats.powerbeats.pro.2", true),
        (["powerbeats pro"], "beats.powerbeats.pro", true),
        (["powerbeats3"], "beats.powerbeats3", true),
        (["powerbeats"], "beats.powerbeats", true),
        (["beats pill"], "beats.pill", true),
        (["beats flex", "beats ep", "beats earphones"], "beats.earphones", true),
        (["beats headphones"], "beats.headphones", true),

        (["echo dot"], "homepod.mini", false),
        (["echo show"], "homepod", false),
        (["echo studio", "echo pop", "echo plus", "echo link", "echo"], "hifispeaker", false),

        (["pixel buds pro", "pixel buds a-series", "pixel buds"], "earbuds.stemless", true),
        (["nest mini", "nest audio", "nest wifi point"], "homepod.mini", false),
        (["nest hub"], "homepod", false),

        (["galaxy buds 3 pro"], "airpods.pro", true),
        (["galaxy buds 3"], "airpods.gen4", true),
        (["galaxy buds live", "galaxy buds2 pro", "galaxy buds2", "galaxy buds pro", "galaxy buds+", "galaxy buds fe", "galaxy buds"], "earbuds.stemless", true),

        (["wh", "wf", "sony headphones"], "airpods.max", true),
        (["linkbuds s", "linkbuds"], "earbuds.in.ear", true),
        (["srs-xb43", "srs-xe200", "srs-xg300", "ht-a5000", "ht-g700", "ht-s40r", "sony speaker"], "hifispeaker", false),

        (["qc ultra earbuds", "qc earbuds ii", "bose sport earbuds"], "earbuds.in.ear", true),
        (["qc 45", "qc 35", "qc ultra headphones", "bose headphones"], "airpods.max", true),
        (["bose home speaker", "bose soundbar", "bose portable smart speaker"], "hifispeaker", false),
        (["bose frames", "bose tempo"], "headphones", true),

        (["dualsense", "dualshock", "playstation"], "gamecontroller.fill", true),
        (["xbox wireless controller", "xbox elite"], "gamecontroller.fill", true),
        (["nintendo", "joy-con", "switch pro controller"], "gamecontroller.fill", true),

        (["logitech mouse", "razer mouse", "mx master"], "computermouse.fill", true),
        (["logitech", "razer", "keychron", "nuphy", "mechanical keyboard"], "keyboard.fill", true),

        (["sennheiser", "momentum", "pxc", "hd 280", "hd 450", "hd 600", "hd 800"], "headphones.over.ear", true),
        (["jbl", "anker", "soundcore"], "hifispeaker", true),
        (["shure", "mv7", "sm7b", "sm58"], "mic.fill", false),

        (["printer"], "printer.fill", false),
        (["scanner"], "scanner.fill", false),
    ]

    static func icon(forName name: String) -> String? {
        let lowercasedName = name.lowercased()
        for (keywords, icon, _) in universalDeviceMap {
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