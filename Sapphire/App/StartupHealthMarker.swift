//
//  StartupHealthMarker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import Foundation
import os

final class StartupHealthMarker {
    enum LaunchMode: Equatable {
        case normal
        case recovery
    }

    static let shared = StartupHealthMarker(defaults: .standard)
    static let healthyAfter: TimeInterval = 20

    private static let markerKey = "startupIncompleteMarker"
    private static let consecutiveKey = "startupIncompleteConsecutiveCount"

    private let defaults: UserDefaults
    private(set) var mode: LaunchMode = .normal
    private var healthyWork: DispatchWorkItem?

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "StartupHealth")

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var isRecoveryLaunch: Bool { mode == .recovery }

    var consecutiveIncompleteLaunches: Int { defaults.integer(forKey: Self.consecutiveKey) }

    @discardableResult
    func beginLaunch(now: Date = Date()) -> LaunchMode {
        let previousIncomplete = defaults.object(forKey: Self.markerKey) != nil
        if previousIncomplete {
            mode = .recovery
            defaults.set(consecutiveIncompleteLaunches + 1, forKey: Self.consecutiveKey)
            log.error("The previous launch did not finish starting up (\(self.consecutiveIncompleteLaunches) in a row); skipping optional startup work this launch.")
        } else {
            mode = .normal
            defaults.removeObject(forKey: Self.consecutiveKey)
        }
        defaults.set(now.timeIntervalSince1970, forKey: Self.markerKey)
        return mode
    }

    func scheduleHealthyCheckpoint(after delay: TimeInterval = StartupHealthMarker.healthyAfter) {
        healthyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.markHealthy() }
        healthyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func markHealthy() {
        healthyWork?.cancel()
        healthyWork = nil
        defaults.removeObject(forKey: Self.markerKey)
        defaults.removeObject(forKey: Self.consecutiveKey)
    }

    func markCleanExit() {
        markHealthy()
    }
}