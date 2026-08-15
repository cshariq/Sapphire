//
//  SpotifyExtendedMetadataParser.swift
//  Sapphire
//
//  Parses librespot-style `/extended-metadata/v0/extended-metadata` protobuf
//  responses into track metadata (including OGG/MP3 AudioFile entries).
//

import Foundation

enum SpotifyExtendedMetadataParser {

    /// BatchedExtensionResponse → TRACK_V4 Any.value → metadata.Track
    static func parseTrack(fromBatchedResponse data: Data) -> SpotifyTrackMetadata? {
        let root = SpotifyProtoWire.readFields(data)
        // field 2: repeated EntityExtensionDataArray extended_metadata
        guard let arrays = root[2], !arrays.isEmpty else { return nil }

        for arrayBytes in arrays {
            let array = SpotifyProtoWire.readFields(Data(arrayBytes))
            // field 3: repeated EntityExtensionData
            for extBytes in array[3] ?? [] {
                let ext = SpotifyProtoWire.readFields(Data(extBytes))
                // field 3: google.protobuf.Any extension_data
                guard let anyBytes = SpotifyProtoWire.firstBytes(ext, 3) else { continue }
                let anyFields = SpotifyProtoWire.readFields(anyBytes)
                // Any.value = field 2
                guard let trackBytes = SpotifyProtoWire.firstBytes(anyFields, 2) else { continue }
                if let track = parseTrackMessage(trackBytes) {
                    return track
                }
            }
        }
        return nil
    }

    /// metadata.Track protobuf (proto2)
    static func parseTrackMessage(_ data: Data) -> SpotifyTrackMetadata? {
        let fields = SpotifyProtoWire.readFields(data)

        let gidHex = SpotifyProtoWire.firstBytes(fields, 1).map(hexString)
        let name = SpotifyProtoWire.firstBytes(fields, 2).flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        let duration = SpotifyProtoWire.firstVarint(fields, 7).map(decodeSInt32)
        let popularity = SpotifyProtoWire.firstVarint(fields, 8).map(decodeSInt32)
        let hasLyrics: Bool? = {
            guard let v = SpotifyProtoWire.firstVarint(fields, 18) else { return nil }
            return v != 0
        }()
        let canonicalUri = SpotifyProtoWire.firstBytes(fields, 36).flatMap { String(data: $0, encoding: .utf8) }

        // field 12: repeated AudioFile file
        let files = (fields[12] ?? []).compactMap { parseAudioFile(Data($0)) }
        // field 13: repeated Track alternative — each may contain files at field 12
        let alternatives: [SpotifyTrackMetadata.AlternativeNode] = (fields[13] ?? []).compactMap { altData in
            let altFields = SpotifyProtoWire.readFields(Data(altData))
            let altGid = SpotifyProtoWire.firstBytes(altFields, 1).map(hexString)
            let altFiles = (altFields[12] ?? []).compactMap { parseAudioFile(Data($0)) }
            guard !altFiles.isEmpty || altGid != nil else { return nil }
            return SpotifyTrackMetadata.AlternativeNode(gid: altGid, file: altFiles.isEmpty ? nil : altFiles)
        }

        let artists: [SpotifyTrackMetadata.ArtistNode]? = {
            let list = (fields[4] ?? []).compactMap { artistData -> SpotifyTrackMetadata.ArtistNode? in
                let af = SpotifyProtoWire.readFields(Data(artistData))
                guard let n = SpotifyProtoWire.firstBytes(af, 2).flatMap({ String(data: $0, encoding: .utf8) }) else {
                    return nil
                }
                let agid = SpotifyProtoWire.firstBytes(af, 1).map(hexString)
                return SpotifyTrackMetadata.ArtistNode(gid: agid, name: n)
            }
            return list.isEmpty ? nil : list
        }()

        return SpotifyTrackMetadata(
            gid: gidHex,
            name: name,
            popularity: popularity,
            duration: duration,
            canonicalUri: canonicalUri,
            hasLyrics: hasLyrics,
            album: nil,
            artist: artists,
            file: files.isEmpty ? nil : files,
            alternative: alternatives.isEmpty ? nil : alternatives
        )
    }

    private static func parseAudioFile(_ data: Data) -> SpotifyTrackMetadata.AudioFile? {
        let fields = SpotifyProtoWire.readFields(data)
        guard let fileIdBytes = SpotifyProtoWire.firstBytes(fields, 1), !fileIdBytes.isEmpty else {
            return nil
        }
        let format = SpotifyProtoWire.firstVarint(fields, 2).map { Int($0) }
        return SpotifyTrackMetadata.AudioFile(fileId: hexString(fileIdBytes), format: format)
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Protobuf zigzag decode for sint32.
    private static func decodeSInt32(_ raw: UInt64) -> Int {
        let n = Int32(truncatingIfNeeded: raw)
        return Int((n >> 1) ^ (-(n & 1)))
    }
}
