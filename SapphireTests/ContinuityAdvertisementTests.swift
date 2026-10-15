//
//  ContinuityAdvertisementTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import Foundation
import CryptoKit
import Testing
@testable import Sapphire

@Suite("Continuity BLE advertisement")
struct ContinuityAdvertisementTests {
    private let peripheral = UUID()

    private func manufacturerData(deviceId: String, battery: UInt8 = 80, flags: UInt8? = nil) -> Data {
        let company = ContinuityProtocol.manufacturerID
        var bytes: [UInt8] = [UInt8(company & 0xFF), UInt8(company >> 8), 1, 1]
        bytes += Array(SHA256.hash(data: Data(deviceId.utf8)).prefix(8))
        bytes += [0x0F, 0x00, battery]
        if let flags { bytes.append(flags) }
        return Data(bytes)
    }

    private func record(id: String) -> ContinuityPairedPeer {
        ContinuityPairedPeer(id: id, name: "Phone", deviceType: .phone, publicKeyBase64: "",
                             linkKeyBase64: "", addedAt: Date(), lastSeenAt: nil)
    }

    @Test("The handle identifies the paired phone it was derived from, and only that one")
    func handleMatchesOnlyItsOwnPhone() throws {
        let ad = try #require(ContinuityAdvertisement.parse(
            manufacturerData: manufacturerData(deviceId: "phone-a"), peripheralID: peripheral))
        #expect(ad.matches(pairedPeer: record(id: "phone-a")))
        #expect(!ad.matches(pairedPeer: record(id: "phone-b")))
    }

    @Test("Phones that predate the flags byte report no pairing state")
    func legacyPayloadHasNoPairingFlag() throws {
        let ad = try #require(ContinuityAdvertisement.parse(
            manufacturerData: manufacturerData(deviceId: "phone-a"), peripheralID: peripheral))
        #expect(ad.isPairing == nil)
        #expect(ad.batteryPercent == 80)
    }

    @Test("The pairing flag is read from byte 13")
    func pairingFlagRoundTrips() throws {
        let pairing = try #require(ContinuityAdvertisement.parse(
            manufacturerData: manufacturerData(deviceId: "phone-a", flags: 0x01), peripheralID: peripheral))
        let linked = try #require(ContinuityAdvertisement.parse(
            manufacturerData: manufacturerData(deviceId: "phone-a", flags: 0x00), peripheralID: peripheral))
        #expect(pairing.isPairing == true)
        #expect(linked.isPairing == false)
    }
}