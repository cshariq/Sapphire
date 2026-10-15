//
//  CalendarSchedule.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import Foundation
import EventKit

enum SharedEventStore {
    static let store = EKEventStore()
}

struct CalendarOccurrenceKey: Hashable {
    let eventIdentifier: String
    let occurrenceStart: Date

    init?(eventIdentifier: String?, occurrenceStart: Date?) {
        guard let eventIdentifier, !eventIdentifier.isEmpty, let occurrenceStart else { return nil }
        self.eventIdentifier = eventIdentifier
        self.occurrenceStart = occurrenceStart
    }

    init?(event: EKEvent) {
        self.init(eventIdentifier: event.eventIdentifier, occurrenceStart: event.startDate)
    }
}

enum CalendarSchedule {
    static func prune<Value>(
        _ entries: [CalendarOccurrenceKey: Value],
        now: Date,
        grace: TimeInterval = 60 * 60
    ) -> [CalendarOccurrenceKey: Value] {
        entries.filter { $0.key.occurrenceStart.addingTimeInterval(grace) > now }
    }

    static let startOffsets: [TimeInterval] = [-30 * 60, -10 * 60, 0]

    static func nextRefreshBoundary(
        now: Date,
        events: [(start: Date, end: Date)],
        startOffsets: [TimeInterval] = CalendarSchedule.startOffsets,
        maxDelay: TimeInterval = 6 * 60 * 60
    ) -> Date {
        var next = now.addingTimeInterval(maxDelay)
        for event in events {
            for offset in startOffsets {
                let instant = event.start.addingTimeInterval(offset)
                if instant > now, instant < next { next = instant }
            }
            if event.end > now, event.end < next { next = event.end }
        }
        return next
    }
}