//
//  CalendarVisibilityFilterTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import Foundation
import Testing
@testable import Sapphire

struct CalendarVisibilityFilterTests {
    @Test func excludesCalendarsDisabledInCalendarMainWindow() {
        let preferences: [String: Any] = [
            "DisabledCalendars": [
                "MainWindow": ["hidden-calendar", "another-hidden-calendar"]
            ]
        ]

        #expect(!CalendarVisibilityFilter.isVisible(
            calendarIdentifier: "hidden-calendar",
            calendarPreferences: preferences
        ))
        #expect(CalendarVisibilityFilter.isVisible(
            calendarIdentifier: "visible-calendar",
            calendarPreferences: preferences
        ))
    }

    @Test func keepsCalendarsVisibleWhenPreferencesAreUnavailable() {
        #expect(CalendarVisibilityFilter.isVisible(
            calendarIdentifier: "calendar",
            calendarPreferences: nil
        ))
    }

    @Test func keepsCalendarsVisibleWhenDisabledCalendarsValueIsMalformed() {
        #expect(CalendarVisibilityFilter.isVisible(
            calendarIdentifier: "calendar",
            calendarPreferences: ["DisabledCalendars": "unexpected-value"]
        ))
    }

    @Test func keepsCalendarsVisibleWhenMainWindowSelectionIsMissing() {
        #expect(CalendarVisibilityFilter.isVisible(
            calendarIdentifier: "calendar",
            calendarPreferences: ["DisabledCalendars": ["OtherWindow": ["calendar"]]]
        ))
    }

    @Test func keepsCalendarsVisibleWhenMainWindowSelectionIsMalformed() {
        #expect(CalendarVisibilityFilter.isVisible(
            calendarIdentifier: "calendar",
            calendarPreferences: ["DisabledCalendars": ["MainWindow": "unexpected-value"]]
        ))
    }

    @Test func keepsCalendarsVisibleWhenDisabledSelectionIsEmpty() {
        #expect(CalendarVisibilityFilter.isVisible(
            calendarIdentifier: "calendar",
            calendarPreferences: ["DisabledCalendars": ["MainWindow": [String]()]]
        ))
    }
}