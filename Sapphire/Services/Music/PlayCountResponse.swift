//
//  PlayCountResponse.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-16.
//

import Foundation

fileprivate struct PlayCountResponse: Codable {
    let success: Bool
    let playcount: Int?
    let uri: String?
}

@MainActor
class PlayCountFetcher {
    static let shared = PlayCountFetcher()

    private static let decoder = JSONDecoder()

    private init() {}

    func getPlayCountValue(for trackID: String) async -> Int? {
        let cleanTrackID = trackID.components(separatedBy: ":").last ?? trackID

        guard let url = URL(string: "https://api.stats.fm/api/v1/tracks/\(cleanTrackID)") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try Self.decoder.decode(PlayCountResponse.self, from: data)
            return response.playcount
        } catch {
            print("[PlayCountFetcher] Failed to fetch or decode play count: \(error)")
            return nil
        }
    }

    func getPlayCount(for trackID: String) async -> String? {
        guard let count = await getPlayCountValue(for: trackID) else { return nil }
        return Self.formatPlayCount(count)
    }

    static func formatPlayCount(_ number: Int) -> String {
        let num = Double(number)
        let thousand = 1000.0
        let million = 1000000.0

        if num >= million {
            let formattedNum = num / million
            return "\(String(format: formattedNum < 10 ? "%.1f" : "%.0f", formattedNum))M"
        } else if num >= thousand {
            let formattedNum = num / thousand
            return "\(String(format: "%.0f", formattedNum))K"
        } else {
            return "\(number)"
        }
    }
}