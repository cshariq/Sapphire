//
//  LiveActivityRegistry.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-08
//

import Foundation

typealias ActivityCandidate = (type: ActivityType, content: LiveActivityContent, dismissAfter: TimeInterval?)

struct LiveActivityProvider {

    enum Slot: Hashable {
        case critical(Int)
        case userOrdered
        case ambient(Int)
    }

    let type: ActivityType
    let slot: Slot

    let isEphemeral: Bool

    let check: @MainActor (LiveActivityManager) -> ActivityCandidate?

    struct Identity: Hashable {
        let type: ActivityType
        let slot: Slot
    }

    var identity: Identity { Identity(type: type, slot: slot) }

    init(
        _ type: ActivityType,
        _ slot: Slot,
        ephemeral: Bool = false,
        check: @escaping @MainActor (LiveActivityManager) -> ActivityCandidate?
    ) {
        self.type = type
        self.slot = slot
        self.isEphemeral = ephemeral
        self.check = check
    }
}

struct LiveActivityRegistry {
    private let critical: [LiveActivityProvider]
    private let userOrdered: [ActivityType: LiveActivityProvider]
    private let ambient: [LiveActivityProvider]
    private let byType: [ActivityType: [LiveActivityProvider]]
    let ephemeralProviders: [LiveActivityProvider]

    init(_ providers: [LiveActivityProvider]) {
        func rank(_ provider: LiveActivityProvider) -> Int? {
            switch provider.slot {
            case .critical(let index), .ambient(let index): return index
            case .userOrdered: return nil
            }
        }

        critical = providers
            .filter { if case .critical = $0.slot { return true } else { return false } }
            .sorted { (rank($0) ?? 0) < (rank($1) ?? 0) }
        ambient = providers
            .filter { if case .ambient = $0.slot { return true } else { return false } }
            .sorted { (rank($0) ?? 0) < (rank($1) ?? 0) }
        userOrdered = providers.reduce(into: [:]) { result, provider in
            guard provider.slot == .userOrdered else { return }
            result[provider.type] = provider
        }

        byType = (critical + providers.filter { $0.slot == .userOrdered } + ambient)
            .reduce(into: [:]) { result, provider in
                result[provider.type, default: []].append(provider)
            }
        ephemeralProviders = providers.filter(\.isEphemeral)
    }

    @MainActor
    func forEachInPriorityOrder(
        userOrder: [LiveActivityType],
        _ body: (LiveActivityProvider) -> Bool
    ) {
        for provider in critical where !body(provider) { return }
        for settingsType in userOrder {
            guard let type = ActivityType(from: settingsType),
                  let provider = userOrdered[type] else { continue }
            if !body(provider) { return }
        }
        for provider in ambient where !body(provider) { return }
    }

    func providers(for type: ActivityType) -> [LiveActivityProvider] {
        byType[type] ?? []
    }

    @MainActor
    func candidate(for type: ActivityType, on manager: LiveActivityManager) -> ActivityCandidate? {
        for provider in providers(for: type) {
            if let candidate = provider.check(manager) { return candidate }
        }
        return nil
    }
}