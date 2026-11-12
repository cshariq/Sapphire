//
//  LiveActivityOrderTests.swift
//  Sapphire
//
//  Created by Borys Babas on 2026-11-12

import Testing
@testable import Sapphire

struct LiveActivityOrderTests {
    @Test func focusSessionRanksWithFocusRow() {
        #expect(ActivityType.evaluationOrder(for: [.focus, .timers, .music])
            == [.focusModeChange, .focusSession, .timer, .music])
        #expect(ActivityType.evaluationOrder(for: [.music, .focus])
            == [.music, .focusModeChange, .focusSession])
    }

    @Test func otherRowsKeepTheirOrder() {
        let order = ActivityType.evaluationOrder(for: LiveActivityType.allCases)
        #expect(order.filter { $0 != .focusSession } == LiveActivityType.allCases.compactMap(ActivityType.init(from:)))
        #expect(order.filter { $0 == .focusSession }.count == 1)
    }
}
