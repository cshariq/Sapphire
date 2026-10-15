//
//  SapphirePerformanceTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import Foundation
import XCTest
@testable import Sapphire

final class SapphirePerformanceTests: XCTestCase {
    @MainActor
    func testFirebaseCompatibleValidation() {
        XCTAssertEqual(SapphirePerformance.validatedName("  launch  "), "launch")
        XCTAssertNil(SapphirePerformance.validatedName("_reserved"))
        XCTAssertNil(SapphirePerformance.validatedName(String(repeating: "a", count: 101)))

        XCTAssertNotNil(SapphirePerformance.validatedAttribute(name: "screen_name", value: "main"))
        XCTAssertNil(SapphirePerformance.validatedAttribute(name: "firebase_name", value: "main"))
        XCTAssertNil(SapphirePerformance.validatedAttribute(name: "café", value: "main"))
        XCTAssertNil(SapphirePerformance.validatedAttribute(name: "screen-name", value: "main"))
    }

    @MainActor
    func testNormalizedDictionaryKeysDoNotCollide() {
        XCTAssertEqual(
            SapphirePerformance.validatedCounters(["launch": 1, " launch ": 2]),
            ["launch": 1]
        )
        XCTAssertEqual(
            SapphirePerformance.validatedAttributes(["screen": "first", " screen ": "second"]),
            ["screen": "first"]
        )
    }

    @MainActor
    func testPublicFirebaseStubIsNotRoutable() {
        XCTAssertFalse(
            SapphirePerformance.isUsableFirebaseProject(
                appID: "1:000000000000:ios:0000000000000000",
                projectID: "sapphire-stub"
            )
        )
        XCTAssertTrue(
            SapphirePerformance.isUsableFirebaseProject(
                appID: "1:123456789012:ios:abcdef0123456789",
                projectID: "sapphire-example"
            )
        )
    }

    func testTraceEncodingMatchesFirebasePerfMetricSchema() throws {
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let encoded = PerformanceMetricEncoder.encodeTrace(
            appID: "1:123456789012:ios:abcdef0123456789",
            installationID: "installation-id",
            firebaseVersion: "12.18.0",
            bundleShortVersion: "3.0",
            networkType: 9,
            name: "macos_app_start",
            startTime: startTime,
            duration: 1.25,
            counters: ["items": 3],
            attributes: ["platform": "macos"]
        )

        let metric = try ProtoMessage(encoded)
        let applicationInfo = try ProtoMessage(XCTUnwrap(metric.bytes(field: 1)))
        let iosInfo = try ProtoMessage(XCTUnwrap(applicationInfo.bytes(field: 4)))
        let networkInfo = try ProtoMessage(XCTUnwrap(iosInfo.bytes(field: 5)))
        let trace = try ProtoMessage(XCTUnwrap(metric.bytes(field: 2)))
        let counter = try ProtoMessage(XCTUnwrap(trace.bytes(field: 6)))
        let attribute = try ProtoMessage(XCTUnwrap(trace.bytes(field: 8)))

        XCTAssertEqual(applicationInfo.string(field: 1), "1:123456789012:ios:abcdef0123456789")
        XCTAssertEqual(applicationInfo.string(field: 2), "installation-id")
        XCTAssertEqual(applicationInfo.varint(field: 5), 1)
        XCTAssertEqual(iosInfo.string(field: 2), "12.18.0")
        XCTAssertEqual(iosInfo.string(field: 3), "3.0")
        XCTAssertEqual(networkInfo.varint(field: 1), 9)
        XCTAssertEqual(trace.string(field: 1), "macos_app_start")
        XCTAssertEqual(trace.varint(field: 2), 0)
        XCTAssertEqual(trace.varint(field: 4), 1_700_000_000_000_000)
        XCTAssertEqual(trace.varint(field: 5), 1_250_000)
        XCTAssertEqual(counter.string(field: 1), "items")
        XCTAssertEqual(counter.varint(field: 2), 3)
        XCTAssertEqual(attribute.string(field: 1), "platform")
        XCTAssertEqual(attribute.string(field: 2), "macos")
    }
}

private struct ProtoMessage {
    private enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        var cursor = data.startIndex
        while cursor < data.endIndex {
            let key = try Self.readVarint(data, cursor: &cursor)
            let field = Int(key >> 3)
            switch key & 0x7 {
            case 0:
                fields[field, default: []].append(.varint(try Self.readVarint(data, cursor: &cursor)))
            case 2:
                let count = try Self.readVarint(data, cursor: &cursor)
                guard count <= UInt64(data.distance(from: cursor, to: data.endIndex)) else {
                    throw DecodeError.truncated
                }
                let end = data.index(cursor, offsetBy: Int(count))
                fields[field, default: []].append(.bytes(data[cursor..<end]))
                cursor = end
            default:
                throw DecodeError.unsupportedWireType
            }
        }
    }

    func varint(field: Int) -> UInt64? {
        guard case let .varint(value)? = fields[field]?.first else { return nil }
        return value
    }

    func bytes(field: Int) -> Data? {
        guard case let .bytes(value)? = fields[field]?.first else { return nil }
        return value
    }

    func string(field: Int) -> String? {
        bytes(field: field).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func readVarint(_ data: Data, cursor: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard cursor < data.endIndex else { throw DecodeError.truncated }
            let byte = data[cursor]
            cursor = data.index(after: cursor)
            result |= UInt64(byte & 0x7f) << UInt64(shift)
            if byte & 0x80 == 0 { return result }
        }
        throw DecodeError.invalidVarint
    }

    private enum DecodeError: Error {
        case truncated
        case invalidVarint
        case unsupportedWireType
    }
}