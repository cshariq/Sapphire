//
//  ActivityType.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-09
//

import Foundation

enum ActivityType: Int, Equatable, Comparable, CaseIterable {
    case none = 0
    case persistentBattery = 1
    case persistentStats = 2
    case persistentWeather = 3
    case weather = 5
    case music = 10
    case continuityMedia = 11
    case timer = 20
    case fileShelf = 25
    case desktopChange = 30
    case stats = 40
    case updateAvailable = 45
    case battery = 50
    case focusModeChange = 55
    case reminder = 59
    case calendar = 60
    case bluetooth = 65
    case continuity = 67
    case continuityExternal = 68
    case audioSwitch = 70
    case fileProgress = 75
    case parcel = 78
    case notification = 80
    case continuityNotification = 81
    case otp = 82
    case geminiLive = 85
    case microphone = 86
    case nearbyShare = 90
    case eyeBreak = 95
    case focusSession = 96
    case systemHUD = 100
    case unlocked = 105
    case lockScreen = 110
    case intelligenceAgent = 120
    case devActivity = 121
    case sports = 125
    case finance = 130

    static func < (lhs: ActivityType, rhs: ActivityType) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    init?(from settingsType: LiveActivityType) {
        switch settingsType {
        case .music: self = .music
        case .weather: self = .weather
        case .calendar: self = .calendar
        case .reminders: self = .reminder
        case .timers: self = .timer
        case .battery: self = .battery
        case .eyeBreak: self = .eyeBreak
        case .desktop: self = .desktopChange
        case .focus: self = .focusModeChange
        case .fileShelf: self = .fileShelf
        case .fileProgress: self = .fileProgress
        case .stats: self = .stats
        case .microphone: self = .microphone
        case .sports: self = .sports
        case .finance: self = .finance
        }
    }

    func toLiveActivityType() -> LiveActivityType? {
        switch self {
        case .music: return .music
        case .weather, .persistentWeather: return .weather
        case .calendar: return .calendar
        case .reminder: return .reminders
        case .timer: return .timers
        case .battery, .persistentBattery: return .battery
        case .eyeBreak: return .eyeBreak
        case .desktopChange: return .desktop
        case .focusModeChange: return .focus
        case .fileShelf: return .fileShelf
        case .fileProgress: return .fileProgress
        case .microphone: return .microphone
        case .stats, .persistentStats: return .stats
        case .sports: return .sports
        case .finance: return .finance
        default: return nil
        }
    }
}