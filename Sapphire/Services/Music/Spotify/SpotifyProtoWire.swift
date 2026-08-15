//
//  SpotifyProtoWire.swift
//  Sapphire
//
//  Minimal protobuf2 writer / field reader used by Spotify private APIs.
//

import Foundation

// MARK: - Minimal protobuf2 writer / field reader

enum SpotifyProtoWire {
    static func writeVarint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v > 0x7F {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v & 0x7F))
        return out
    }

    static func key(_ field: UInt64, _ wire: UInt64) -> Data {
        writeVarint((field << 3) | wire)
    }

    static func writeBytes(field: UInt64, _ data: Data) -> Data {
        key(field, 2) + writeVarint(UInt64(data.count)) + data
    }

    static func writeString(field: UInt64, _ string: String) -> Data {
        writeBytes(field: field, Data(string.utf8))
    }

    static func writeVarintField(field: UInt64, _ value: UInt64) -> Data {
        key(field, 0) + writeVarint(value)
    }

    static func writeUInt64(field: UInt64, _ value: UInt64) -> Data {
        writeVarintField(field: field, value)
    }

    static func writeMessage(field: UInt64, _ message: Data) -> Data {
        writeBytes(field: field, message)
    }

    static func readFields(_ data: Data) -> [UInt64: [Data]] {
        var map: [UInt64: [Data]] = [:]
        var i = data.startIndex
        while i < data.endIndex {
            guard let (tag, ni) = readVarint(data, at: i) else { break }
            i = ni
            let field = tag >> 3
            let wire = tag & 0x7
            switch wire {
            case 0:
                guard let (value, n2) = readVarint(data, at: i) else { return map }
                i = n2
                map[field, default: []].append(writeVarint(value))
            case 2:
                guard let (len, n2) = readVarint(data, at: i) else { return map }
                i = n2
                let end = data.index(i, offsetBy: Int(len), limitedBy: data.endIndex) ?? data.endIndex
                map[field, default: []].append(data[i..<end])
                i = end
            case 5:
                let end = data.index(i, offsetBy: 4, limitedBy: data.endIndex) ?? data.endIndex
                map[field, default: []].append(data[i..<end])
                i = end
            case 1:
                let end = data.index(i, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
                map[field, default: []].append(data[i..<end])
                i = end
            default:
                return map
            }
        }
        return map
    }

    static func readVarint(_ data: Data, at start: Data.Index) -> (UInt64, Data.Index)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < data.endIndex {
            let b = data[i]
            i = data.index(after: i)
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return (result, i) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    static func firstBytes(_ fields: [UInt64: [Data]], _ field: UInt64) -> Data? {
        fields[field]?.first.map { Data($0) }
    }

    static func firstVarint(_ fields: [UInt64: [Data]], _ field: UInt64) -> UInt64? {
        guard let raw = fields[field]?.first, let (v, _) = readVarint(Data(raw), at: 0) else { return nil }
        return v
    }
}
