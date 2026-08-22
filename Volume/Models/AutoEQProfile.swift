//
//  AutoEQProfile.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

struct AutoEQFilter: Codable, Equatable {
    enum FilterType: String, Codable {
        case peaking, lowShelf, highShelf
    }
    let type: FilterType
    let frequency: Double
    let gainDB: Float
    let q: Double
}

struct AutoEQProfile: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let source: AutoEQSource
    let preampDB: Float
    let filters: [AutoEQFilter]
    let measuredBy: String?
    var optimizedSampleRate: Double

    static let maxFilters = 10

    enum CodingKeys: String, CodingKey {
        case id, name, source, preampDB, filters, measuredBy, optimizedSampleRate
    }

    init(
        id: String, name: String, source: AutoEQSource,
        preampDB: Float, filters: [AutoEQFilter],
        measuredBy: String? = nil,
        optimizedSampleRate: Double = 48000
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.preampDB = preampDB
        self.filters = filters
        self.measuredBy = measuredBy
        self.optimizedSampleRate = optimizedSampleRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(AutoEQSource.self, forKey: .source)
        preampDB = try container.decode(Float.self, forKey: .preampDB)
        filters = try container.decode([AutoEQFilter].self, forKey: .filters)
        measuredBy = try container.decodeIfPresent(String.self, forKey: .measuredBy)
        optimizedSampleRate = try container.decodeIfPresent(Double.self, forKey: .optimizedSampleRate) ?? 48000
    }
}

extension AutoEQProfile {
    func validated() -> AutoEQProfile {
        let validFilters = filters.filter { f in
            f.frequency > 0 && f.q > 0 && abs(f.gainDB) <= 30
        }
        let clampedPreamp = max(-30, min(30, preampDB))
        return AutoEQProfile(
            id: id, name: name, source: source,
            preampDB: clampedPreamp,
            filters: Array(validFilters.prefix(Self.maxFilters)),
            measuredBy: measuredBy,
            optimizedSampleRate: optimizedSampleRate
        )
    }
}

enum AutoEQSource: String, Codable {
    case bundled, imported, fetched
}

struct AutoEQCatalogEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let measuredBy: String
    let relativePath: String
}

struct AutoEQSelection: Codable, Equatable {
    let profileID: String
    var isEnabled: Bool
}