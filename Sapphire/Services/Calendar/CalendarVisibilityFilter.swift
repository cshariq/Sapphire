//
//  CalendarVisibilityFilter.swift
//  Sapphire
//

import Foundation

enum CalendarVisibilityFilter {
    // EventKit does not expose Calendar's sidebar visibility. Calendar stores
    // unchecked identifiers in this undocumented preference. Fail open if
    // Apple changes its name or shape so calendar access does not disappear.
    static let calendarPreferencesDomain = "com.apple.iCal"

    static func isVisible(
        calendarIdentifier: String,
        calendarPreferences: [String: Any]?
    ) -> Bool {
        guard let disabledCalendars = calendarPreferences?["DisabledCalendars"] as? [String: Any],
              let disabledIdentifiers = disabledCalendars["MainWindow"] as? [String] else {
            return true
        }

        return !disabledIdentifiers.contains(calendarIdentifier)
    }
}
