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

    private init() {}

    func getPlayCount(for trackID: String) async -> String? {
        let cleanTrackID = trackID.components(separatedBy: ":").last ?? trackID

        guard let url = URL(string: "https://api.stats.fm/api/v1/tracks/\(cleanTrackID)") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PlayCountResponse.self, from: data)
            if let count = response.playcount {
                return Self.formatPlayCount(count)
            }
            return nil
        } catch {
            print("[PlayCountFetcher] Failed to fetch or decode play count: \(error)")
            return nil
        }
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