// Public-build interfaces for the local headphone controls. The Continuity transport
// remains unavailable; full builds use the private protocol and transport implementation.
#if PUBLIC_BUILD
import Foundation
import OSLog

struct ContinuityEarbudCommand: Codable, Equatable, Sendable {
    var action: String
    var stringValue: String? = nil
    var boolValue: Bool? = nil
    var intValue: Int? = nil
}

struct ContinuityEarbudStatus: Codable, Equatable, Sendable {
    var vendor: String = "none"
    var name: String = ""
    var address: String?
    var connected = false
    var ownedLocally = false
    var noiseMode = "off"
    var ancHigh = true
    var eqPreset = "off"
    var batteryLeft = 0
    var batteryRight = 0
    var batteryCase = 0
    var batteryMain = 0
    var dsee = false
    var seamless = false
    var detectConversations = false
    var ambientLevel = 2
    var supportsANC = false
    var supportsAdaptive = false
    var supportsEQ = true
    var supportsDSEE = false
    var supportsSeamless = false
    var supportsFind = false
    var supportsCustomEQ = false
    var customEQBands: [Int] = Array(repeating: 0, count: 9)
    var gamingMode = false
    var spatialAudio = false
    var touchpadLocked = false
    var touchLeft: Int = 2
    var touchRight: Int = 2
    var speakSeamlessly = false
    var ancOneEarbud = false
    var autoSwitchAudio = false
    var pauseOnOneBudRemoved = false
    var sidetone = false
    var extraHighAmbient = false
    var amplifyAmbient = false
    var inBandRingtone = false
    var callPathControl = true
    var ambientDuringCall = false
    var detectConversationsDuration = 1
    var outsideDoubleTap = false
    var muteLeft = false
    var muteRight = false
    var wearingLeft = false
    var wearingRight = false
    var fitTesting = false
    var fitLeftGood = false
    var fitRightGood = false
    var supportsGaming = false
    var supportsSpatial = false
    var supportsTouchLock = false
    var supportsFitTest = false
    var supportsAmbientExtras = false
    var supportsCallExtras = false
    var supportsDetectConversations = false
    var supportsExtraClearCall = false
    var supportsPassthrough = false
    var supportsOutsideDoubleTap = false
    var extraClearCall = false
    var passthrough = false
}

enum ContinuityEarbudMessageKind {
    case earbudCommand, earbudStatus
}

extension ContinuityPeer {
    func send<Payload: Encodable>(_ kind: ContinuityEarbudMessageKind, _ payload: Payload) {}
}

enum ContinuityBluetoothAddress {
    static func normalize(_ address: String?) -> String? {
        guard var value = address?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        for suffix in [":output", ":input"] where value.lowercased().hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        let hex = value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard hex.utf8.count == 12, hex.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        let characters = Array(hex.uppercased())
        return stride(from: 0, to: characters.count, by: 2)
            .map { String(characters[$0...($0 + 1)]) }
            .joined(separator: ":")
    }

    static func dashed(_ address: String?) -> String? {
        normalize(address)?.replacingOccurrences(of: ":", with: "-")
    }

    static func matches(_ first: String?, _ second: String?) -> Bool {
        guard let first = normalize(first), let second = normalize(second) else { return false }
        return first == second
    }
}

enum ContinuityLog {
    private static let logger = Logger(subsystem: "com.cshariq.sapphire", category: "EarbudControls")
    static func f(_ message: String) { logger.debug("\(message, privacy: .private)") }
    static func fErr(_ message: String) { logger.error("\(message, privacy: .private)") }
}
#endif
