#if !SAPPHIRE_FULL_BUILD
import Foundation
import Combine

enum VerificationCodeDetector {
    /// Stub: OTP/verification extraction lives in the private Intelligence package.
    static func find(in text: String) -> String? {
        let pattern = #"(?<!\d)(\d{4,8})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let codeRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[codeRange])
    }
}

struct OTPEvent: Identifiable, Equatable {
    let id: String
    let code: String
    let source: String
    let title: String
    let body: String
    let date: Date
}

struct ParcelShipment: Identifiable, Equatable, Codable {
    let id: String
    var trackingNumber: String
    var carrier: ParcelCarrier
    var title: String
    var status: String
    var detail: String
    var lastUpdated: Date
    var sourceEmailSubject: String?
    var isDelivered: Bool

    var trackingURL: URL? { carrier.trackingURL(trackingNumber) }
}

enum ParcelCarrier: String, Codable, CaseIterable {
    case ups, fedex, usps, dhl, amazon, unknown

    var displayName: String {
        switch self {
        case .ups: return "UPS"
        case .fedex: return "FedEx"
        case .usps: return "USPS"
        case .dhl: return "DHL"
        case .amazon: return "Amazon"
        case .unknown: return "Carrier"
        }
    }

    var trackingURL: (String) -> URL? { { _ in nil } }
}

final class SmartInboxMonitor: ObservableObject {
    static let shared = SmartInboxMonitor()
    private init() {}

    @Published private(set) var latestOTP: OTPEvent?
    @Published private(set) var activeParcels: [ParcelShipment] = []

    func presentOTP(code: String, source: String, title: String, body: String) {}
    func consumeOTP(_ code: String) {}
    func hasConsumedOTP(_ code: String) -> Bool { false }
    func dismissOTP() {}
}
#endif
