//
//  PlaybackTrajectory.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-09

import SwiftUI

struct PlaybackTrajectory: Equatable {
    var elapsed: TimeInterval
    var date: Date
    var rate: Double
    var duration: TimeInterval

    static let stopped = PlaybackTrajectory(elapsed: 0, date: .distantPast, rate: 0, duration: 0)

    var isAdvancing: Bool { rate > 0 }

    func elapsed(at now: Date) -> TimeInterval {
        let raw = elapsed + rate * max(0, now.timeIntervalSince(date))
        return duration > 0 ? max(0, min(duration, raw)) : max(0, raw)
    }

    var progressMotion: LinearProgressMotion {
        guard duration > 0 else { return .zero }
        return LinearProgressMotion(progress: elapsed / duration, date: date, rate: rate / duration)
    }

    func isEquivalent(to other: PlaybackTrajectory) -> Bool {
        guard abs(rate - other.rate) < 1e-6, abs(duration - other.duration) < 0.01 else { return false }
        let now = Date()
        return abs(elapsed(at: now) - other.elapsed(at: now)) < 0.1
    }

    var clockSchedule: PlaybackClockSchedule { PlaybackClockSchedule(trajectory: self) }
}

struct PlaybackClockSchedule: TimelineSchedule {
    let trajectory: PlaybackTrajectory

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let t = trajectory
        var pending: Date? = startDate
        return AnyIterator {
            guard let current = pending else { return nil }
            pending = nil
            guard t.rate > 0 else { return current }
            let e = t.elapsed(at: current)
            if t.duration > 0, e >= t.duration { return current }
            let remainderPhase = t.duration > 0 ? t.duration - t.duration.rounded(.down) : 0
            let nextWhole = e.rounded(.down) + 1
            var nextRemaining = e.rounded(.down) + remainderPhase
            if nextRemaining <= e + 1e-6 { nextRemaining += 1 }
            let target = min(nextWhole, nextRemaining)
            pending = t.date.addingTimeInterval((target - t.elapsed) / t.rate + 0.002)
            return current
        }
    }
}