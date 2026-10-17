#if PUBLIC_BUILD
import Foundation
import XCTest
@testable import Sapphire

final class PublicEarbudCompatibilityTests: XCTestCase {
    func testBluetoothAddressMatchingAcceptsPlatformSpellingsAndRejectsInvalidInput() {
        for spelling in ["a1:b2:c3:d4:e5:f6", "A1-B2-C3-D4-E5-F6", "a1b2c3d4e5f6", "A1-B2-C3-D4-E5-F6:output"] {
            XCTAssertEqual(ContinuityBluetoothAddress.normalize(spelling), "A1:B2:C3:D4:E5:F6")
            XCTAssertEqual(ContinuityBluetoothAddress.dashed(spelling), "A1-B2-C3-D4-E5-F6")
            XCTAssertTrue(ContinuityBluetoothAddress.matches(spelling, "a1:b2:c3:d4:e5:f6"))
        }
        for invalid in ["", "BuiltInSpeakerDevice", "A1:B2:C3:D4:E5", "A1:B2:C3:D4:E5:ZZ"] {
            XCTAssertNil(ContinuityBluetoothAddress.normalize(invalid))
            XCTAssertFalse(ContinuityBluetoothAddress.matches(invalid, invalid))
        }
        XCTAssertFalse(ContinuityBluetoothAddress.matches(nil, nil))
        XCTAssertFalse(ContinuityBluetoothAddress.matches("A1:B2:C3:D4:E5:F6", "A1:B2:C3:D4:E5:F7"))
    }

    func testEarbudStatusRoundTripPreservesUserNamesAndProtocolValues() throws {
        var original = EarbudControlSnapshot()
        original.vendor = .galaxy
        original.name = "会议室's Buds 100%"
        original.address = "A1:B2:C3:D4:E5:F6"
        original.noiseMode = "ambient"
        original.eqPreset = "bassBoost"
        original.customEQBands = [-3, 0, 5]
        original.touchLeft = .volume
        original.touchRight = .spotify
        original.supportsCustomEQ = true
        let encoded = try JSONEncoder().encode(ContinuityEarbudStatus(snapshot: original))
        let decoded = try JSONDecoder().decode(ContinuityEarbudStatus.self, from: encoded)
        XCTAssertEqual(decoded.snapshot, original)
        XCTAssertEqual(decoded.vendor, "galaxy")
        XCTAssertEqual(decoded.noiseMode, "ambient")
        XCTAssertEqual(decoded.eqPreset, "bassBoost")
    }
}
#endif
