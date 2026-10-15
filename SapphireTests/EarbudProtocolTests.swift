//
//  EarbudProtocolTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import XCTest
@testable import Sapphire

final class EarbudProtocolTests: XCTestCase {
    func testGalaxyCRC16SeedZero() {
        let first = GalaxyCRC16.ccitt(Data([136, 1, 1, 34]))
        XCTAssertEqual(first, GalaxyCRC16.ccitt(Data([136, 1, 1, 34])))
        XCTAssertNotEqual(first, 0)
        XCTAssertNotEqual(GalaxyCRC16.ccitt(Data([175, 0])), GalaxyCRC16.ccitt(Data([175, 1])))
    }

    func testGalaxySppRoundTripAndSeamlessInvert() {
        let message = GalaxySppMessage(id: .setSeamlessConnection, payload: GalaxyBudsHandshake.seamlessPayload(enabled: true))
        XCTAssertEqual(message.payload, Data([0]), "Seamless ON is wire 0")
        let off = GalaxyBudsHandshake.seamlessPayload(enabled: false)
        XCTAssertEqual(off, Data([1]))

        let encoded = message.encode(legacy: false)
        XCTAssertEqual(encoded.first, 0xFD)
        XCTAssertEqual(encoded.last, 0xDD)
        var buffer = encoded
        let decoded = GalaxySppMessage.extract(from: &buffer)
        XCTAssertEqual(decoded?.messageId, GalaxyMessageId.setSeamlessConnection.rawValue)
        XCTAssertEqual(decoded?.payload, Data([0]))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testGalaxyManagerInfoHandshakeBytes() {
        XCTAssertEqual(GalaxyBudsHandshake.managerInfoPayload, Data([1, 1, 34]))
        XCTAssertEqual(GalaxyBudsModel.detect(from: "Galaxy Buds3 Pro")?.supportsSeamlessConnection, true)
        XCTAssertEqual(GalaxyBudsModel.detect(from: "Galaxy Buds+")?.supportsSeamlessConnection, false)
    }

    func testGalaxyLogSessionYieldMessages() {
        XCTAssertEqual(GalaxyMessageId.logSessionOpen.rawValue, 58)
        XCTAssertEqual(GalaxyMessageId.logSessionClose.rawValue, 59)
        let open = GalaxySppMessage(id: .logSessionOpen).encode(legacy: false)
        let close = GalaxySppMessage(id: .logSessionClose).encode(legacy: false)
        XCTAssertEqual(open[3], 58)
        XCTAssertEqual(close[3], 59)
    }

    func testGalaxyModernExtendedStatusOffsets() {
        var payload = Data(repeating: 0, count: 50)
        payload[0] = 2
        payload[2] = 80
        payload[3] = 75
        payload[6] = 0x11
        payload[7] = 90
        payload[9] = 2
        payload[10] = 0x0F
        payload[11] = 0x23
        payload[12] = 1
        payload[19] = 0
        payload[22] = 1
        payload[23] = 3
        payload[24] = 1
        payload[26] = 1
        payload[27] = 1
        payload[28] = 1
        payload[32] = 1
        payload[33] = 1
        payload[34] = 0
        payload[35] = 1
        payload[36] = 0
        payload[37] = 0
        payload[38] = 0
        payload[39] = 0
        payload[40] = 0
        payload[41] = 0
        payload[42] = 0
        payload[43] = 1
        payload[44] = 1
        payload[45] = 1

        var status = GalaxyBudsStatus()
        status.applyExtendedStatus(payload, model: .buds4Pro)
        XCTAssertEqual(status.batteryLeft, 80)
        XCTAssertEqual(status.batteryRight, 75)
        XCTAssertTrue(status.touchpadLocked)
        XCTAssertEqual(status.noiseControlMode, .anc)
        XCTAssertTrue(status.seamlessConnectionEnabled)
        XCTAssertTrue(status.detectConversations)
        XCTAssertEqual(status.detectConversationsDuration, 1)
        XCTAssertTrue(status.ancWithOneEarbud)
        XCTAssertTrue(status.sidetone)
        XCTAssertTrue(status.callPathControl)
        XCTAssertTrue(status.spatialAudio)
        XCTAssertTrue(status.extraClearCall)
        XCTAssertTrue(status.extraHighAmbient)
        XCTAssertTrue(status.pauseOnOneBud)
        XCTAssertTrue(GalaxyBudsModel.buds4Pro.supportsAdvancedTouchLock)
        XCTAssertFalse(GalaxyBudsModel.buds4Pro.supportsOutsideDoubleTap)
    }

    func testSonyFrameRoundTripAndV1BatteryIsNotPowerOff() {
        let frame = SonyMdrFrame(type: SonyMdrDataType.dataMdr.rawValue, sequence: 1, payload: SonyMdrCommands.getBatteryV1())
        XCTAssertEqual(SonyMdrCommands.getBatteryV1(), Data([0x10, 0x00]))
        XCTAssertNotEqual(SonyMdrCommands.getBatteryV1().first, 0x22)

        var encoded = frame.encode()
        XCTAssertEqual(encoded.first, 0x3E)
        XCTAssertEqual(encoded.last, 0x3C)
        let decoded = SonyMdrFrame.extract(from: &encoded)
        XCTAssertEqual(decoded?.payload, Data([0x10, 0x00]))
        XCTAssertEqual(decoded?.type, 12)
    }

    func testSonyV2NoiseAndDseeOpcodes() {
        let nc = SonyMdrCommands.setNoiseV2(mode: .anc, ambientLevel: 20, focusOnVoice: false)
        XCTAssertEqual(Array(nc.prefix(3)), [0x68, 0x17, 0x01])
        XCTAssertEqual(SonyMdrCommands.setDsee(true), Data([0xE8, 0x01, 0x01]))
        XCTAssertTrue(SonyDeviceName.matches("WH-1000XM5"))
        XCTAssertTrue(SonyDeviceName.matches("Sony WF-1000XM4"))
        XCTAssertEqual(EarbudVendor.detect(name: "Galaxy Buds2 Pro"), .galaxy)
        XCTAssertEqual(EarbudVendor.detect(name: "WH-1000XM4"), .sony)
    }
}