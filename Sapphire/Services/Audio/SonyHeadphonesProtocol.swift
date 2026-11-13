//
//  SonyHeadphonesProtocol.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-20

import Foundation

enum SonyMdrDataType: UInt8 {
    case dataMdr = 12
}

struct SonyMdrFrame: Equatable {
    var type: UInt8
    var sequence: UInt8
    var payload: Data

    static let start: UInt8 = 0x3E
    static let end: UInt8 = 0x3C
    static let escape: UInt8 = 0x3D
    static let escaped60: UInt8 = 0x2C
    static let escaped61: UInt8 = 0x2D
    static let escaped62: UInt8 = 0x2E

    static let uuidV1 = "96CC203E-5068-46ad-B32D-E316F5E069BA"
    static let uuidV2 = "956C7B26-D49A-4BA8-B03F-B17D393CB6E2"

    func encode() -> Data {
        var body = Data()
        body.append(type)
        body.append(sequence)
        let size = UInt32(payload.count)
        body.append(UInt8((size >> 24) & 0xFF))
        body.append(UInt8((size >> 16) & 0xFF))
        body.append(UInt8((size >> 8) & 0xFF))
        body.append(UInt8(size & 0xFF))
        body.append(payload)
        var checksum: UInt8 = 0
        for byte in body { checksum &+= byte }
        body.append(checksum)

        var frame = Data([Self.start])
        frame.append(Self.escapeBytes(body))
        frame.append(Self.end)
        return frame
    }

    static func extract(from buffer: inout Data) -> SonyMdrFrame? {
        guard let start = buffer.firstIndex(of: Self.start) else {
            buffer.removeAll(keepingCapacity: true)
            return nil
        }
        if start > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<start)
        }
        guard let end = buffer.firstIndex(of: Self.end), end > buffer.startIndex else { return nil }
        let frameData = Data(buffer[buffer.startIndex...end])
        buffer.removeSubrange(buffer.startIndex...end)
        return decode(frameData)
    }

    static func decode(_ data: Data) -> SonyMdrFrame? {
        guard data.count >= 4, data.first == start, data.last == end else { return nil }
        let escaped = data.dropFirst().dropLast()
        guard let body = unescape(Data(escaped)), body.count >= 7 else { return nil }
        let type = body[body.startIndex]
        let sequence = body[body.startIndex + 1]
        let size = (UInt32(body[body.startIndex + 2]) << 24)
            | (UInt32(body[body.startIndex + 3]) << 16)
            | (UInt32(body[body.startIndex + 4]) << 8)
            | UInt32(body[body.startIndex + 5])
        let payloadStart = body.startIndex + 6
        let payloadEnd = payloadStart + Int(size)
        guard payloadEnd <= body.endIndex - 1 else { return nil }
        let payload = Data(body[payloadStart..<payloadEnd])
        return SonyMdrFrame(type: type, sequence: sequence, payload: payload)
    }

    private static func escapeBytes(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        for byte in data {
            switch byte {
            case end:
                out.append(contentsOf: [escape, escaped60])
            case escape:
                out.append(contentsOf: [escape, escaped61])
            case start:
                out.append(contentsOf: [escape, escaped62])
            default:
                out.append(byte)
            }
        }
        return out
    }

    private static func unescape(_ data: Data) -> Data? {
        var out = Data()
        out.reserveCapacity(data.count)
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            if byte == escape {
                let nextIndex = data.index(after: i)
                guard nextIndex < data.endIndex else { return nil }
                switch data[nextIndex] {
                case escaped60: out.append(end)
                case escaped61: out.append(escape)
                case escaped62: out.append(start)
                default: return nil
                }
                i = data.index(after: nextIndex)
            } else {
                out.append(byte)
                i = data.index(after: i)
            }
        }
        return out
    }
}

enum SonyNoiseMode: String, CaseIterable {
    case off
    case anc
    case ambient

    var displayName: String {
        switch self {
        case .off: String(localized: "Off")
        case .anc: String(localized: "Noise Cancelling")
        case .ambient: String(localized: "Ambient Sound")
        }
    }

    static func from(wire: String) -> SonyNoiseMode {
        switch wire.lowercased() {
        case "anc", "noise", "nc": return .anc
        case "ambient", "asm": return .ambient
        default: return .off
        }
    }
}

enum SonyEqualizerPreset: Int, CaseIterable {
    case off = 0
    case bright = 1
    case excited = 2
    case mellow = 3
    case relaxed = 4
    case vocal = 5
    case trebleBoost = 6
    case bassBoost = 7
    case speech = 8
    case manual = 0xA0

    var wireName: String {
        switch self {
        case .off: "off"
        case .bright: "bright"
        case .excited: "excited"
        case .mellow: "mellow"
        case .relaxed: "relaxed"
        case .vocal: "vocal"
        case .trebleBoost: "trebleBoost"
        case .bassBoost: "bassBoost"
        case .speech: "speech"
        case .manual: "custom"
        }
    }

    var displayName: String {
        switch self {
        case .off: String(localized: "Off")
        case .bright: String(localized: "Bright")
        case .excited: String(localized: "Excited")
        case .mellow: String(localized: "Mellow")
        case .relaxed: String(localized: "Relaxed")
        case .vocal: String(localized: "Vocal")
        case .trebleBoost: String(localized: "Treble Boost")
        case .bassBoost: String(localized: "Bass Boost")
        case .speech: String(localized: "Speech")
        case .manual: String(localized: "Manual")
        }
    }

    static func from(wire: String) -> SonyEqualizerPreset? {
        switch wire.lowercased() {
        case "off": return .off
        case "bright": return .bright
        case "excited": return .excited
        case "mellow": return .mellow
        case "relaxed": return .relaxed
        case "vocal": return .vocal
        case "trebleboost", "treble", "treble-boost": return .trebleBoost
        case "bassboost", "bass", "bass-boost": return .bassBoost
        case "speech": return .speech
        case "custom", "manual": return .manual
        default: return nil
        }
    }
}

enum SonyMdrCommands {
    static func setNoiseV2(mode: SonyNoiseMode, ambientLevel: Int, focusOnVoice: Bool) -> Data {
        let effect: UInt8 = mode == .off ? 0 : 1
        let settingType: UInt8 = mode == .ambient ? 1 : 0
        let level = UInt8(max(1, min(20, ambientLevel)))
        return Data([0x68, 0x17, 0x01, effect, settingType, focusOnVoice ? 1 : 0, level])
    }

    static func setNoiseV1(mode: SonyNoiseMode, ambientLevel: Int, focusOnVoice: Bool) -> Data {
        let off = mode == .off
        let ambient = mode == .ambient
        let level: UInt8 = ambient ? UInt8(max(1, min(20, ambientLevel))) : 0
        return Data([
            0x68, 0x02,
            off ? 0x00 : 0x11,
            0x01,
            (ambient || off) ? 0x00 : 0x02,
            0x01,
            focusOnVoice ? 1 : 0,
            level
        ])
    }

    static func setEqualizerPresetV2(_ preset: SonyEqualizerPreset) -> Data {
        Data([0x58, 0x00, UInt8(preset.rawValue), 0x00])
    }

    static func setEqualizerPresetV1(_ preset: SonyEqualizerPreset) -> Data {
        Data([0x58, 0x01, UInt8(preset.rawValue), 0x00])
    }

    static func setEqualizerCustom(isV2: Bool, clearBass: Int, bands: [Int]) -> Data {
        var payload = Data([0x58, isV2 ? 0x00 : 0x01, 0xA0, 0x06, UInt8(clamping: clearBass + 10)])
        for index in 0..<5 {
            let value = bands.indices.contains(index) ? bands[index] : 0
            payload.append(UInt8(clamping: value + 10))
        }
        return payload
    }

    static func setDsee(_ enabled: Bool) -> Data {
        Data([0xE8, 0x01, enabled ? 1 : 0])
    }

    static func getBatteryV1() -> Data { Data([0x10, 0x00]) }

    static func getBatteryV2Main() -> Data { Data([0x22, 0x00]) }
    static func getBatteryV2Dual() -> Data { Data([0x22, 0x09]) }
    static func getNoiseV2() -> Data { Data([0x66, 0x17]) }
    static func getEqualizerV2() -> Data { Data([0x56, 0x00]) }
    static func getDsee() -> Data { Data([0xE6, 0x01]) }
}

enum SonyDeviceName {
    static func matches(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("sony") { return true }
        let prefixes = ["wh-1000", "wf-1000", "wh-ch", "wf-c", "wh-xb", "wf-xb", "linkbuds", "wh-100", "wf-100"]
        return prefixes.contains(where: { n.contains($0) })
    }
}