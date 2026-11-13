//
//  GalaxyBudsProtocol.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import Foundation

enum GalaxyCRC16 {
    static func ccitt(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc = crc ^ UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}

enum GalaxyMessageId: UInt8, Sendable {
    case resp = 81
    case logSessionOpen = 58
    case logSessionClose = 59
    case extraClearSoundCall = 72
    case statusUpdated = 96
    case extendedStatusUpdated = 97
    case customEqualizeRecv = 105
    case pauseMediaWhenOneBudRemoved = 108
    case ambientDuringCallNoti = 109
    case setCallPathControl = 110
    case setAncWithOneEarbud = 111
    case pairingMode = 114
    case autoSwitchAudioOutput = 115
    case multipointInfo = 118
    case noiseControlsUpdate = 119
    case noiseControls = 120
    case setTouchAndHoldNoiseControls = 121
    case setDetectConversations = 122
    case setDetectConversationsDuration = 123
    case setSpatialAudio = 124
    case setSpeakSeamlessly = 125
    case setAmplifyAmbientSound = 126
    case setAmbientMode = 128
    case customizeAmbientSound = 130
    case noiseReductionLevel = 131
    case ambientVolume = 132
    case adjustSoundSync = 133
    case equalizer = 134
    case gameMode = 135
    case managerInfo = 136
    case customEqualize = 137
    case setInBandRingtone = 138
    case setSidetone = 139
    case setHearingEnhancements = 143
    case lockTouchpad = 144
    case setTouchpadOption = 146
    case outsideDoubleTap = 149
    case extraHighAmbient = 150
    case setVoiceWakeUp = 151
    case checkFitOfEarbuds = 157
    case checkFitResult = 158
    case passThrough = 159
    case findMyEarbudsStart = 160
    case findMyEarbudsStop = 161
    case muteEarbud = 162
    case findMyEarbudsOnWearingStart = 166
    case updateTime = 167
    case setSeamlessConnection = 175
    case spatialAudioControl = 195
}

struct GalaxyTouchHoldNoiseOptions: Equatable, Sendable {
    var off = true
    var anc = true
    var ambient = true
    var adaptive = false

    var wire: Data {
        Data([
            off ? 1 : 0,
            anc ? 1 : 0,
            ambient ? 1 : 0,
            adaptive ? 1 : 0,
        ])
    }
}

enum GalaxyTouchOption: Int, CaseIterable, Sendable, Identifiable {
    case voiceAssistant = 1
    case noiseControl = 2
    case volume = 3
    case spotify = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .voiceAssistant: String(localized: "Voice assistant")
        case .noiseControl: String(localized: "Noise control")
        case .volume: String(localized: "Volume")
        case .spotify: String(localized: "Spotify Spot On")
        }
    }
}

enum GalaxyNoiseControlMode: Int, CaseIterable, Sendable, Identifiable {
    case off = 0
    case anc = 1
    case ambient = 2
    case adaptive = 3

    var id: Int { rawValue }

    var wireName: String {
        switch self {
        case .off: "off"
        case .anc: "anc"
        case .ambient: "ambient"
        case .adaptive: "adaptive"
        }
    }

    var displayName: String {
        switch self {
        case .off: String(localized: "Off")
        case .anc: String(localized: "Noise Cancelling")
        case .ambient: String(localized: "Ambient Sound")
        case .adaptive: String(localized: "Adaptive")
        }
    }

    static func from(wire: String) -> GalaxyNoiseControlMode {
        switch wire.lowercased() {
        case "anc", "noise", "nc": return .anc
        case "ambient", "asm": return .ambient
        case "adaptive": return .adaptive
        default: return .off
        }
    }
}

enum GalaxyEqualizerPreset: Int, CaseIterable, Sendable, Identifiable {
    case off = 0
    case bassBoost = 1
    case soft = 2
    case dynamic = 3
    case clear = 4
    case trebleBoost = 5
    case custom = 6

    var id: Int { rawValue }

    var wireValue: UInt8 { self == .custom ? 7 : UInt8(rawValue) }

    var wireName: String {
        switch self {
        case .off: "off"
        case .bassBoost: "bassBoost"
        case .soft: "soft"
        case .dynamic: "dynamic"
        case .clear: "clear"
        case .trebleBoost: "trebleBoost"
        case .custom: "custom"
        }
    }

    var displayName: String {
        switch self {
        case .off: String(localized: "Normal")
        case .bassBoost: String(localized: "Bass Boost")
        case .soft: String(localized: "Soft")
        case .dynamic: String(localized: "Dynamic")
        case .clear: String(localized: "Clear")
        case .trebleBoost: String(localized: "Treble Boost")
        case .custom: String(localized: "Custom")
        }
    }

    static func from(wire: String) -> GalaxyEqualizerPreset? {
        switch wire.lowercased() {
        case "off", "normal": return .off
        case "bassboost", "bass", "bass-boost": return .bassBoost
        case "soft": return .soft
        case "dynamic": return .dynamic
        case "clear": return .clear
        case "trebleboost", "treble", "treble-boost": return .trebleBoost
        case "custom": return .custom
        default: return nil
        }
    }

    static func from(wireValue: Int) -> GalaxyEqualizerPreset {
        if wireValue == 7 { return .custom }
        return GalaxyEqualizerPreset(rawValue: wireValue) ?? .off
    }
}

enum GalaxyBudsModel: String, CaseIterable, Sendable {
    case buds, budsPlus, budsLive, budsPro
    case buds2, buds2Pro, budsFe, budsCore
    case buds3, buds3Pro, buds3Fe
    case buds4, buds4Pro

    static func detect(from name: String) -> GalaxyBudsModel? {
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")
        let table: [(String, GalaxyBudsModel)] = [
            ("buds4pro", .buds4Pro),
            ("buds4", .buds4),
            ("buds3fe", .buds3Fe),
            ("buds3pro", .buds3Pro),
            ("buds3", .buds3),
            ("buds2pro", .buds2Pro),
            ("buds2", .buds2),
            ("budspro", .budsPro),
            ("budslive", .budsLive),
            ("budsfe", .budsFe),
            ("budscore", .budsCore),
            ("buds+", .budsPlus),
            ("budsplus", .budsPlus),
        ]
        for entry in table where normalized.contains(entry.0) {
            return entry.1
        }
        if normalized.contains("galaxybuds") || (normalized.contains("buds") && normalized.contains("galaxy")) {
            return .buds
        }
        return nil
    }

    var serviceUUID: String {
        switch self {
        case .buds:
            return "00001102-0000-1000-8000-00805f9b34fd"
        case .budsPlus, .budsLive, .budsPro:
            return "00001101-0000-1000-8000-00805f9b34fb"
        default:
            return "2e73a4ad-332d-41fc-90e2-16bef06523f2"
        }
    }

    var usesLegacyProtocol: Bool { self == .buds }

    var supportsANC: Bool {
        switch self {
        case .budsPro, .buds2Pro, .buds3, .buds3Pro, .buds3Fe, .buds4, .buds4Pro:
            return true
        default:
            return false
        }
    }

    var supportsAdaptiveANC: Bool {
        switch self {
        case .buds3Pro, .buds4Pro: return true
        default: return false
        }
    }

    var supportsDetectConversations: Bool {
        switch self {
        case .budsPro, .buds2Pro, .buds3Pro, .buds4Pro: return true
        default: return false
        }
    }

    var supportsSeamlessConnection: Bool {
        switch self {
        case .buds, .budsPlus: return false
        default: return true
        }
    }

    var supportsCustomEqualizer: Bool {
        switch self {
        case .buds2Pro, .buds3, .buds3Pro, .buds3Fe, .budsFe, .budsCore, .buds4, .buds4Pro:
            return true
        default: return false
        }
    }

    var supportsGamingMode: Bool {
        switch self {
        case .buds: return false
        default: return true
        }
    }

    var supportsSpatialAudio: Bool {
        switch self {
        case .buds, .budsPlus: return false
        default: return true
        }
    }

    var supportsTouchLock: Bool { true }

    var supportsAdvancedTouchLock: Bool {
        switch self {
        case .buds, .budsPlus, .budsLive, .budsPro: return false
        default: return true
        }
    }

    var supportsAdvancedTouchLockForCalls: Bool {
        switch self {
        case .buds2, .buds2Pro, .budsFe, .budsCore, .buds3, .buds3Pro, .buds3Fe, .buds4, .buds4Pro:
            return true
        default: return false
        }
    }

    var supportsAmbientExtras: Bool {
        switch self {
        case .buds: return false
        default: return true
        }
    }

    var supportsCallExtras: Bool {
        switch self {
        case .buds: return false
        default: return true
        }
    }

    var supportsExtraClearCall: Bool {
        switch self {
        case .buds2Pro, .buds3Pro, .buds4Pro, .buds3, .buds4: return true
        default: return false
        }
    }

    var supportsPassthrough: Bool {
        switch self {
        case .budsLive: return true
        default: return false
        }
    }

    var supportsBixbyWakeup: Bool {
        switch self {
        case .buds, .budsPlus: return false
        default: return true
        }
    }

    var supportsFitTest: Bool {
        switch self {
        case .budsPro, .buds2Pro, .buds3Pro, .buds4Pro, .buds3, .buds4, .buds3Fe, .budsFe, .budsCore:
            return true
        default: return false
        }
    }

    var supportsOutsideDoubleTap: Bool {
        switch self {
        case .buds4Pro: return false
        case .buds, .budsLive: return false
        default: return true
        }
    }
}

struct GalaxySppMessage: Sendable {
    let messageId: UInt8
    let payload: Data
    let isResponse: Bool

    init(messageId: UInt8, payload: Data = Data(), isResponse: Bool = false) {
        self.messageId = messageId
        self.payload = payload
        self.isResponse = isResponse
    }

    init(id: GalaxyMessageId, payload: Data = Data(), isResponse: Bool = false) {
        self.init(messageId: id.rawValue, payload: payload, isResponse: isResponse)
    }

    var knownId: GalaxyMessageId? { GalaxyMessageId(rawValue: messageId) }

    func encode(legacy: Bool) -> Data {
        legacy ? encodeLegacy() : encodeStandard()
    }

    private func crcBytes() -> (UInt8, UInt8) {
        var crcData = Data([messageId])
        crcData.append(payload)
        let crc = GalaxyCRC16.ccitt(crcData)
        return (UInt8(crc & 0xFF), UInt8(crc >> 8))
    }

    private func encodeLegacy() -> Data {
        var data = Data()
        let payloadSize = 1 + payload.count + 2
        data.append(0xFE)
        data.append(isResponse ? 1 : 0)
        data.append(UInt8(payloadSize))
        data.append(messageId)
        data.append(payload)
        let crc = crcBytes()
        data.append(crc.0)
        data.append(crc.1)
        data.append(0xEE)
        return data
    }

    private func encodeStandard() -> Data {
        var data = Data()
        let payloadSize = UInt16(1 + payload.count + 2)
        var header: UInt16 = payloadSize & 0x3FF
        if isResponse { header |= 0x1000 }
        data.append(0xFD)
        data.append(UInt8(header & 0xFF))
        data.append(UInt8(header >> 8))
        data.append(messageId)
        data.append(payload)
        let crc = crcBytes()
        data.append(crc.0)
        data.append(crc.1)
        data.append(0xDD)
        return data
    }

    static func extract(from buffer: inout Data) -> GalaxySppMessage? {
        guard buffer.count >= 5 else { return nil }
        let preamble = buffer[buffer.startIndex]
        let needed: Int
        switch preamble {
        case 0xFE:
            needed = 4 + Int(buffer[buffer.startIndex + 2])
        case 0xFD, 0xFC:
            let header = UInt16(buffer[buffer.startIndex + 1]) | (UInt16(buffer[buffer.startIndex + 2]) << 8)
            needed = 4 + Int(header & 0x3FF)
        default:
            buffer.removeFirst()
            return extract(from: &buffer)
        }
        guard buffer.count >= needed else { return nil }
        let frame = Data(buffer.prefix(needed))
        buffer.removeFirst(needed)
        return decode(frame)
    }

    static func decode(_ data: Data) -> GalaxySppMessage? {
        guard data.count >= 5 else { return nil }
        switch data[data.startIndex] {
        case 0xFE: return decodeLegacy(data)
        case 0xFD, 0xFC: return decodeModern(data)
        default: return nil
        }
    }

    private static func decodeLegacy(_ data: Data) -> GalaxySppMessage? {
        guard data.count >= 6, data[data.startIndex] == 0xFE else { return nil }
        let isResponse = data[data.startIndex + 1] == 1
        let payloadSize = Int(data[data.startIndex + 2])
        let id = data[data.startIndex + 3]
        let payloadStart = data.startIndex + 4
        let payloadEnd = payloadStart + max(0, payloadSize - 3)
        let payload = payloadEnd > payloadStart && payloadEnd <= data.endIndex
            ? Data(data[payloadStart..<min(payloadEnd, data.endIndex - 1)])
            : Data()
        return GalaxySppMessage(messageId: id, payload: payload, isResponse: isResponse)
    }

    private static func decodeModern(_ data: Data) -> GalaxySppMessage? {
        guard data.count >= 7 else { return nil }
        let header = UInt16(data[data.startIndex + 1]) | (UInt16(data[data.startIndex + 2]) << 8)
        let isResponse = (header & 0x1000) != 0
        let id = data[data.startIndex + 3]
        let total = Int(header & 0x3FF)
        let payloadSize = max(0, total - 3)
        let payloadStart = data.startIndex + 4
        let payload = payloadSize > 0 && payloadStart + payloadSize <= data.endIndex
            ? Data(data[payloadStart..<(payloadStart + payloadSize)])
            : Data()
        return GalaxySppMessage(messageId: id, payload: payload, isResponse: isResponse)
    }
}

struct GalaxyBudsStatus: Equatable, Sendable {
    var batteryLeft = 0
    var batteryRight = 0
    var batteryCase = 0
    var noiseControlMode: GalaxyNoiseControlMode = .off
    var equalizerPreset: GalaxyEqualizerPreset = .off
    var customEqualizerBands: [Int] = Array(repeating: 0, count: 9)
    var seamlessConnectionEnabled = false
    var ancLevelHigh = true
    var detectConversations = false
    var detectConversationsDuration = 1
    var ambientSoundVolume = 2
    var isLeftWearing = false
    var isRightWearing = false
    var touchpadLocked = false
    var touchLeft: GalaxyTouchOption = .noiseControl
    var touchRight: GalaxyTouchOption = .noiseControl
    var outsideDoubleTap = false
    var gamingMode = false
    var sidetone = false
    var passthrough = false
    var extraHighAmbient = false
    var amplifyAmbient = false
    var ambientCustomOn = false
    var ambientCustomLeft: Int = 2
    var ambientCustomRight: Int = 2
    var ambientCustomTone: Int = 1
    var ancWithOneEarbud = false
    var callPathControl = true
    var extraClearCall = false
    var speakSeamlessly = false
    var spatialAudio = false
    var adjustSoundSync = false
    var stereoBalance = 16
    var bixbyWakeup = false
    var pauseOnOneBud = false
    var ambientDuringCall = false
    var inBandRingtone = false
    var autoSwitchAudio = false
    var muteLeft = false
    var muteRight = false
    var fitTesting = false
    var fitLeftGood = false
    var fitRightGood = false
    var singleTapOn = true
    var doubleTapOn = true
    var tripleTapOn = true
    var touchHoldOn = true
    var doubleTapForCallOn = true
    var touchHoldForCallOn = true
    var revision = 0

    mutating func applyExtendedStatus(_ payload: Data, model: GalaxyBudsModel) {
        guard payload.count >= 14 else { return }
        revision = Int(payload[0])
        batteryLeft = Int(payload[2])
        batteryRight = Int(payload[3])

        if model == .buds {
            applyLegacyBudsStatus(payload)
            return
        }

        let placement = payload[6]
        isLeftWearing = ((placement >> 4) & 0x0F) == 1
        isRightWearing = (placement & 0x0F) == 1
        batteryCase = Int(payload[7])

        if model == .budsPlus {
            applyBudsPlusStatus(payload)
            return
        }

        equalizerPreset = GalaxyEqualizerPreset.from(wireValue: Int(payload[9]))

        if model.supportsAdvancedTouchLock, payload.count > 10 {
            let touch = payload[10]
            touchHoldOn = (touch & 0x01) != 0
            tripleTapOn = (touch & 0x02) != 0
            doubleTapOn = (touch & 0x04) != 0
            singleTapOn = (touch & 0x08) != 0
            if model.supportsAdvancedTouchLockForCalls {
                doubleTapForCallOn = (touch & 0x10) != 0
                touchHoldForCallOn = (touch & 0x20) != 0
            }
            touchpadLocked = (touch & 0x80) == 0
        } else if payload.count > 10 {
            touchpadLocked = payload[10] == 1
        }

        if payload.count > 11 {
            let options = payload[11]
            touchLeft = GalaxyTouchOption(rawValue: Int((options & 0xF0) >> 4)) ?? .noiseControl
            touchRight = GalaxyTouchOption(rawValue: Int(options & 0x0F)) ?? .noiseControl
        }

        if model == .budsLive {
            noiseControlMode = payload.count > 12 && payload[12] == 1 ? .anc : .off
        } else if payload.count > 12 {
            noiseControlMode = GalaxyNoiseControlMode(rawValue: Int(payload[12])) ?? .off
        }

        if payload.count > 13 {
            bixbyWakeup = payload[13] == 1
        }

        if model.supportsSeamlessConnection, payload.count > 19 {
            seamlessConnectionEnabled = payload[19] == 0
        }

        if model == .budsLive {
            if revision >= 5, payload.count > 21 { passthrough = payload[21] == 1 }
            if revision >= 8, payload.count > 23 { callPathControl = payload[23] == 0 }
            if revision >= 9, payload.count > 24 { spatialAudio = payload[24] == 1 }
            return
        }

        if payload.count > 22 {
            if model == .budsPro, revision < 3 {
                extraHighAmbient = payload[22] == 1
            } else {
                speakSeamlessly = payload[22] == 1
            }
        }
        if payload.count > 23 { ambientSoundVolume = Int(payload[23]) }
        if payload.count > 24 { ancLevelHigh = payload[24] == 1 }

        switch model {
        case .budsPro:
            applyBudsProTail(payload)
        case .buds2:
            applyBuds2Tail(payload)
        case .buds2Pro:
            applyBuds2ProTail(payload)
        default:
            applyModernTail(payload)
        }
    }

    private mutating func applyLegacyBudsStatus(_ payload: Data) {
        equalizerPreset = GalaxyEqualizerPreset.from(wireValue: Int(payload.count > 11 ? payload[11] : 0))
        if payload.count > 13 {
            touchpadLocked = payload[12] == 1
            let options = payload[13]
            touchLeft = GalaxyTouchOption(rawValue: Int((options & 0xF0) >> 4)) ?? .noiseControl
            touchRight = GalaxyTouchOption(rawValue: Int(options & 0x0F)) ?? .noiseControl
        }
        if revision >= 3, payload.count > 14 {
            seamlessConnectionEnabled = payload[14] == 0
        }
    }

    private mutating func applyBudsPlusStatus(_ payload: Data) {
        if payload.count > 9 { ambientSoundVolume = Int(payload[9]) }
        if payload.count > 10 { adjustSoundSync = payload[10] == 1 }
        if payload.count > 11 { equalizerPreset = GalaxyEqualizerPreset.from(wireValue: Int(payload[11])) }
        if payload.count > 12 { touchpadLocked = payload[12] != 0 }
        if payload.count > 13 {
            let options = payload[13]
            touchLeft = GalaxyTouchOption(rawValue: Int((options & 0xF0) >> 4)) ?? .noiseControl
            touchRight = GalaxyTouchOption(rawValue: Int(options & 0x0F)) ?? .noiseControl
        }
        if payload.count > 14 { outsideDoubleTap = payload[14] == 1 }
        if revision >= 8, payload.count > 19 { sidetone = payload[19] == 1 }
        if revision >= 9, payload.count > 20 { extraHighAmbient = payload[20] == 1 }
        if revision >= 11, payload.count > 21 { seamlessConnectionEnabled = payload[21] == 0 }
        if revision >= 13, payload.count > 23 { callPathControl = payload[23] == 0 }
    }

    private mutating func applyBudsProTail(_ payload: Data) {
        if payload.count > 25 { autoSwitchAudio = payload[25] == 1 }
        if payload.count > 26 { detectConversations = payload[26] == 1 }
        if payload.count > 27 {
            detectConversationsDuration = Int(payload[27])
            if detectConversationsDuration > 2 { detectConversationsDuration = 1 }
        }
        if revision > 1, payload.count > 28 { spatialAudio = payload[28] == 1 }
        if revision >= 6, payload.count > 30 { extraHighAmbient = payload[30] == 1 }
        if revision >= 7, payload.count > 31 { outsideDoubleTap = payload[31] == 1 }
        if revision >= 8, payload.count > 32 { ancWithOneEarbud = payload[32] == 1 }
        if revision >= 9, payload.count > 36 { sidetone = payload[36] == 1 }
        if revision >= 10, payload.count > 37 { callPathControl = payload[37] == 0 }
    }

    private mutating func applyBuds2Tail(_ payload: Data) {
        if payload.count > 26 { extraHighAmbient = payload[26] == 1 }
        if revision >= 3, payload.count > 28 { ancWithOneEarbud = payload[28] == 1 }
        if revision >= 5, payload.count > 32 { outsideDoubleTap = payload[32] == 1 }
        if revision >= 6, payload.count > 33 { sidetone = payload[33] == 1 }
        if revision >= 7, payload.count > 34 { callPathControl = payload[34] == 0 }
        if revision >= 8, payload.count > 35 { spatialAudio = payload[35] == 1 }
    }

    private mutating func applyBuds2ProTail(_ payload: Data) {
        applyModernSharedFrom25(payload)
        var idx = 34
        func take() -> UInt8? {
            guard payload.count > idx else { return nil }
            defer { idx += 1 }
            return payload[idx]
        }
        if revision >= 1 {
            if let v = take() { callPathControl = v == 0 }
            if let v = take() { spatialAudio = v == 1 }
            _ = take()
            _ = take()
            _ = take()
            _ = take()
            _ = take()
        }
        if revision >= 3, let v = take() { adjustSoundSync = v == 1 }
        if revision >= 8, let v = take() {  _ = v }
        if revision >= 13 {
            if let v = take() { extraClearCall = v == 1 }
            if let v = take() { extraHighAmbient = v == 1 }
        }
    }

    private mutating func applyModernTail(_ payload: Data) {
        applyModernSharedFrom25(payload)
        var idx = 34
        func take() -> UInt8? {
            guard payload.count > idx else { return nil }
            defer { idx += 1 }
            return payload[idx]
        }
        if let v = take() { callPathControl = v == 0 }
        if let v = take() { spatialAudio = v == 1 }
        _ = take()
        _ = take()
        _ = take()
        _ = take()
        _ = take()
        if let v = take() {  _ = v }
        _ = take()
        if let v = take() { extraClearCall = v == 1 }
        if let v = take() { extraHighAmbient = v == 1 }
        if let v = take() { pauseOnOneBud = v == 1 }
    }

    private mutating func applyModernSharedFrom25(_ payload: Data) {
        if payload.count > 26 { detectConversations = payload[26] == 1 }
        if payload.count > 27 {
            detectConversationsDuration = Int(payload[27])
            if detectConversationsDuration > 2 { detectConversationsDuration = 1 }
        }
        if payload.count > 28 { ancWithOneEarbud = payload[28] == 1 }
        if payload.count > 29 { ambientCustomOn = payload[29] == 1 }
        if payload.count > 32 { outsideDoubleTap = payload[32] == 1 }
        if payload.count > 33 { sidetone = payload[33] == 1 }
    }
}

enum GalaxyBudsHandshake {
    static let managerInfoPayload = Data([1, 1, 34])

    static func seamlessPayload(enabled: Bool) -> Data {
        Data([enabled ? 0 : 1])
    }

    static func updateTimePayload(now: Date = Date(), calendar: Calendar = .current) -> Data {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let tz = TimeZone.current.secondsFromGMT() / 3600
        var payload = Data()
        let year = UInt16(components.year ?? 2024)
        payload.append(UInt8(year & 0xFF))
        payload.append(UInt8(year >> 8))
        payload.append(UInt8(components.month ?? 1))
        payload.append(UInt8(components.day ?? 1))
        payload.append(UInt8(components.hour ?? 0))
        payload.append(UInt8(components.minute ?? 0))
        payload.append(UInt8(components.second ?? 0))
        payload.append(UInt8(bitPattern: Int8(clamping: tz)))
        return payload
    }
}