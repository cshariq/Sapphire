//
//  NotchRuntimeState.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation

@MainActor
final class NotchRuntimeState: ObservableObject {
    static let shared = NotchRuntimeState()

    @Published private(set) var isUserNearNotch = true
    @Published private(set) var isNotchExpanded = false

    var shouldReduceBackgroundWork: Bool {
        !isUserNearNotch && !isNotchExpanded
    }

    private init() {}

    func setUserNearNotch(_ near: Bool) {
        guard isUserNearNotch != near else { return }
        isUserNearNotch = near
    }

    func setNotchExpanded(_ expanded: Bool) {
        guard isNotchExpanded != expanded else { return }
        isNotchExpanded = expanded
    }
}