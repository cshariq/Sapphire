//
//  EQPreset.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation

enum EQPreset: String, CaseIterable, Identifiable {
    case flat
    case bassBoost
    case bassCut
    case trebleBoost
    case vocalClarity
    case podcast
    case spokenWord
    case loudness
    case lateNight
    case smallSpeakers
    case rock
    case pop
    case electronic
    case jazz
    case classical
    case hipHop
    case rnb
    case deep
    case acoustic
    case movie

    var id: String { rawValue }

    // MARK: - Categories

    enum Category: String, CaseIterable, Identifiable {
        case utility = "Utility"
        case speech = "Speech"
        case listening = "Listening"
        case music = "Music"
        case media = "Media"

        var id: String { rawValue }
    }

    var category: Category {
        switch self {
        case .flat, .bassBoost, .bassCut, .trebleBoost:
            return .utility
        case .vocalClarity, .podcast, .spokenWord:
            return .speech
        case .loudness, .lateNight, .smallSpeakers:
            return .listening
        case .rock, .pop, .electronic, .jazz, .classical, .hipHop, .rnb, .deep, .acoustic:
            return .music
        case .movie:
            return .media
        }
    }

    static func presets(for category: Category) -> [EQPreset] {
        allCases.filter { $0.category == category }
    }

    var name: String {
        switch self {
        case .flat: return "Flat"
        case .bassBoost: return "Bass Boost"
        case .bassCut: return "Bass Cut"
        case .trebleBoost: return "Treble Boost"
        case .vocalClarity: return "Vocal Clarity"
        case .podcast: return "Podcast"
        case .spokenWord: return "Spoken Word"
        case .loudness: return "Loudness"
        case .lateNight: return "Late Night"
        case .smallSpeakers: return "Small Speakers"
        case .rock: return "Rock"
        case .pop: return "Pop"
        case .electronic: return "Electronic"
        case .jazz: return "Jazz"
        case .classical: return "Classical"
        case .hipHop: return "Hip-Hop"
        case .rnb: return "R&B"
        case .deep: return "Deep"
        case .acoustic: return "Acoustic"
        case .movie: return "Movie"
        }
    }

    var settings: EQSettings {
        switch self {
        // MARK: - Utility
        case .flat:
            return EQSettings(bandGains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        case .bassBoost:
            return EQSettings(bandGains: [6, 6, 5, -1, 0, 0, 0, 0, 0, 0])
        case .bassCut:
            return EQSettings(bandGains: [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0])
        case .trebleBoost:
            return EQSettings(bandGains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6])

        // MARK: - Speech
        case .vocalClarity:
            return EQSettings(bandGains: [-4, -2, -1, -3, 0, 2, 4, 4, 1, 0])
        case .podcast:
            return EQSettings(bandGains: [-6, -4, -2, -1, 0, 2, 4, 3, 1, 0])
        case .spokenWord:
            return EQSettings(bandGains: [-8, -6, -3, -2, 0, 2, 4, 4, 2, 0])

        // MARK: - Listening
        case .loudness:
            return EQSettings(bandGains: [5, 4, 2, 0, -2, -2, 0, 2, 4, 5])
        case .lateNight:
            return EQSettings(bandGains: [-6, -4, -2, 0, 0, 1, 2, 2, 1, 0])
        case .smallSpeakers:
            return EQSettings(bandGains: [3, 4, 5, 2, 0, 1, 2, 2, 1, 0])

        // MARK: - Music
        case .rock:
            return EQSettings(bandGains: [4, 3, 2, 0, -1, 0, 2, 3, 2, 1])
        case .pop:
            return EQSettings(bandGains: [3, 3, 2, 0, -1, 1, 2, 3, 3, 4])
        case .electronic:
            return EQSettings(bandGains: [7, 6, 4, 0, -2, -2, 1, 3, 4, 3])
        case .jazz:
            return EQSettings(bandGains: [3, 2, 1, 0, 0, 0, 1, 2, 2, 1])
        case .classical:
            return EQSettings(bandGains: [0, 0, 0, 0, 0, 0, 1, 2, 2, 2])
        case .hipHop:
            return EQSettings(bandGains: [6, 5, 4, 0, -1, 0, 2, 3, 4, 3])
        case .rnb:
            return EQSettings(bandGains: [4, 4, 3, 1, -1, 0, 2, 3, 3, 2])
        case .deep:
            return EQSettings(bandGains: [5, 6, 4, 1, -2, -2, 0, 1, 2, 1])
        case .acoustic:
            return EQSettings(bandGains: [0, 1, 2, 2, 1, 0, 1, 2, 2, 1])

        // MARK: - Media
        case .movie:
            return EQSettings(bandGains: [4, 4, 3, -1, -1, 1, 3, 3, 2, 1])
        }
    }
}