//
//  NotchRuntimeState.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Combine
import Foundation

@MainActor
final class NotchRuntimeState: ObservableObject {
    static let shared = NotchRuntimeState()

    @Published private(set) var isUserNearNotch = true
    @Published private(set) var isNotchExpanded = false

    private struct SourceState {
        var isUserNear = false
        var isExpanded = false
    }

    private var sources: [ObjectIdentifier: SourceState] = [:]
    private let reductionSubject = CurrentValueSubject<Bool, Never>(false)

    var reductionChanges: AnyPublisher<Bool, Never> {
        reductionSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var shouldReduceBackgroundWork: Bool {
        reductionSubject.value
    }

    init() {}

    func register(
        source: ObjectIdentifier,
        isUserNear: Bool = false,
        isExpanded: Bool = false
    ) {
        sources[source] = SourceState(isUserNear: isUserNear, isExpanded: isExpanded)
        publishAggregateState()
    }

    func update(
        source: ObjectIdentifier,
        isUserNear: Bool? = nil,
        isExpanded: Bool? = nil
    ) {
        guard var state = sources[source] else { return }
        var changed = false
        if let isUserNear, state.isUserNear != isUserNear {
            state.isUserNear = isUserNear
            changed = true
        }
        if let isExpanded, state.isExpanded != isExpanded {
            state.isExpanded = isExpanded
            changed = true
        }
        guard changed else { return }
        sources[source] = state
        publishAggregateState()
    }

    func unregister(source: ObjectIdentifier) {
        guard sources.removeValue(forKey: source) != nil else { return }
        publishAggregateState()
    }

    private func publishAggregateState() {
        let hasSources = !sources.isEmpty
        let userIsNear = sources.values.contains(where: \.isUserNear)
        let notchIsExpanded = sources.values.contains(where: \.isExpanded)
        let shouldReduce = hasSources && !userIsNear && !notchIsExpanded

        if isUserNearNotch != userIsNear {
            isUserNearNotch = userIsNear
        }
        if isNotchExpanded != notchIsExpanded {
            isNotchExpanded = notchIsExpanded
        }
        if reductionSubject.value != shouldReduce {
            reductionSubject.send(shouldReduce)
        }
    }
}