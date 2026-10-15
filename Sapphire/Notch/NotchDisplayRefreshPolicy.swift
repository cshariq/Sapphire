//
//  NotchDisplayRefreshPolicy.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import CoreGraphics

enum NotchDisplayRefreshPolicy {
    struct Snapshot: Equatable {
        var displays: [Display]
        var targets: [CGDirectDisplayID]

        struct Display: Equatable {
            var id: CGDirectDisplayID
            var frame: CGRect
        }

        init(displays: [Display], targets: [CGDirectDisplayID]) {
            self.displays = displays.sorted { $0.id < $1.id }
            self.targets = targets.sorted()
        }
    }

    static let debounce: TimeInterval = 0.5
    static let stabilityInterval: TimeInterval = 0.3
    static let settleDelay: TimeInterval = 0.5
    static let maxStabilityReads = 6

    enum Step: Equatable {
        case apply
        case readAgain
        case skip
    }

    static func step(previous: Snapshot?, current: Snapshot, reads: Int) -> Step {
        if current.displays.isEmpty { return reads >= maxStabilityReads ? .skip : .readAgain }
        guard let previous else { return reads >= maxStabilityReads ? .apply : .readAgain }
        if previous == current || reads >= maxStabilityReads { return .apply }
        return .readAgain
    }

    struct Move: Equatable {
        var from: CGDirectDisplayID
        var to: CGDirectDisplayID
    }

    struct Plan: Equatable {
        var moves: [Move]
        var destroy: [CGDirectDisplayID]
        var create: [CGDirectDisplayID]
    }

    static func plan(windowDisplays: [CGDirectDisplayID], targets: [CGDirectDisplayID]) -> Plan {
        let targetSet = Set(targets)
        var seen = Set<CGDirectDisplayID>()
        let windows = windowDisplays.filter { $0 != 0 && seen.insert($0).inserted }
        let orphaned = windows.filter { !targetSet.contains($0) }
        let windowSet = Set(windows)
        var added: [CGDirectDisplayID] = []
        for target in targets where target != 0 && !windowSet.contains(target) && !added.contains(target) {
            added.append(target)
        }
        let pairs = min(orphaned.count, added.count)
        return Plan(
            moves: (0..<pairs).map { Move(from: orphaned[$0], to: added[$0]) },
            destroy: Array(orphaned.dropFirst(pairs)),
            create: Array(added.dropFirst(pairs))
        )
    }
}