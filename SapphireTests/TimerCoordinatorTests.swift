//
//  TimerCoordinatorTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-11

import XCTest
@testable import Sapphire

final class TimerCoordinatorTests: XCTestCase {
    func testTickFollowsTheShortestRegisteredInterval() {
        XCTAssertEqual(TimerCoordinator.tickInterval(for: [5, 30, 86_400]), 5)
    }

    func testTickNeverRunsFasterThanOncePerSecond() {
        XCTAssertEqual(TimerCoordinator.tickInterval(for: [0.1, 0.5]), 1)
    }

    func testDailyAndWeeklyTasksTickOncePerMinute() {
        XCTAssertEqual(TimerCoordinator.tickInterval(for: [86_400, 7 * 86_400]), 60)
    }

    func testNoUsableIntervalsFallBackToOneSecond() {
        XCTAssertEqual(TimerCoordinator.tickInterval(for: []), 1)
        XCTAssertEqual(TimerCoordinator.tickInterval(for: [0, -3, .infinity]), 1)
    }
}