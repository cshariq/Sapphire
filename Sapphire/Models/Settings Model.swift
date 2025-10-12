//
//  Settings Model.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-07
//
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Customizable Configuration
struct CustomizableNotchConfiguration: Codable, Equatable {
    var universalWidth: CGFloat = 195
    var universalHeight: CGFloat = 32
    var initialCornerRadius: CGFloat = 10
    var topBuffer: CGFloat = 0

    var scaleFactor: CGFloat = 1.10
    var hoverExpandedCornerRadius: CGFloat = 18

    var autoExpandedCornerRadius: CGFloat = 13
    var autoExpandedTallHeight: CGFloat = 80
    var autoExpandedContentVerticalPadding: CGFloat = 8

    var clickExpandedCornerRadius: CGFloat = 40
    var liveActivityBottomCornerRadius: CGFloat = 20

    var collapseAnimationDelay: TimeInterval = 0.07
    var initialOpenCollapseDelay: TimeInterval = 1.5
    var widgetSwitchCollapseDelay: TimeInterval = 3.0
    var dragActivationCollapseDelay: TimeInterval = 0.1

    var expandAnimationResponse: Double = 0.45
    var expandAnimationDamping: Double = 0.68
    var swipeOpenAnimationResponse: Double = 0.5
    var swipeOpenAnimationDamping: Double = 0.85
    var collapseAnimationResponse: Double = 0.3
    var collapseAnimationDamping: Double = 0.98

    var widgetBlurRadiusMax: CGFloat = 30
    var activityBlurRadiusMax: CGFloat = 40
    var expandedShadowRadius: CGFloat = 18
    var expandedShadowOffsetY: CGFloat = 8

    var contentTopPadding: CGFloat = 10
    var contentBottomPadding: CGFloat = 10
    var contentHorizontalPadding: CGFloat = 35

    static func == (lhs: CustomizableNotchConfiguration, rhs: CustomizableNotchConfiguration) -> Bool {
        return lhs.universalWidth == rhs.universalWidth &&
               lhs.universalHeight == rhs.universalHeight &&
               lhs.initialCornerRadius == rhs.initialCornerRadius &&
               lhs.topBuffer == rhs.topBuffer &&
               lhs.scaleFactor == rhs.scaleFactor &&
               lhs.hoverExpandedCornerRadius == rhs.hoverExpandedCornerRadius &&
               lhs.autoExpandedCornerRadius == rhs.autoExpandedCornerRadius &&
               lhs.autoExpandedTallHeight == rhs.autoExpandedTallHeight &&
               lhs.autoExpandedContentVerticalPadding == rhs.autoExpandedContentVerticalPadding &&
               lhs.clickExpandedCornerRadius == rhs.clickExpandedCornerRadius &&
               lhs.liveActivityBottomCornerRadius == rhs.liveActivityBottomCornerRadius &&
               lhs.collapseAnimationDelay == rhs.collapseAnimationDelay &&
               lhs.initialOpenCollapseDelay == rhs.initialOpenCollapseDelay &&
               lhs.widgetSwitchCollapseDelay == rhs.widgetSwitchCollapseDelay &&
               lhs.dragActivationCollapseDelay == rhs.dragActivationCollapseDelay &&
               lhs.expandAnimationResponse == rhs.expandAnimationResponse &&
               lhs.expandAnimationDamping == rhs.expandAnimationDamping &&
               lhs.swipeOpenAnimationResponse == rhs.swipeOpenAnimationResponse &&
               lhs.swipeOpenAnimationDamping == rhs.swipeOpenAnimationDamping &&
               lhs.collapseAnimationResponse == rhs.collapseAnimationResponse &&
               lhs.collapseAnimationDamping == rhs.collapseAnimationDamping &&
               lhs.widgetBlurRadiusMax == rhs.widgetBlurRadiusMax &&
               lhs.activityBlurRadiusMax == rhs.activityBlurRadiusMax &&
               lhs.expandedShadowRadius == rhs.expandedShadowRadius &&
               lhs.expandedShadowOffsetY == rhs.expandedShadowOffsetY &&
               lhs.contentTopPadding == rhs.contentTopPadding &&
               lhs.contentBottomPadding == rhs.contentBottomPadding &&
               lhs.contentHorizontalPadding == rhs.contentHorizontalPadding
    }
}

enum WeatherInfoType: String, Codable, CaseIterable, Identifiable {
    case temperature, condition, wind, humidity, feelsLike, precipitation, sunrise, sunset, uvIndex, visibility, pressure, locationName, conditionDescription, highLowTemp
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .temperature: "Current Temperature"
        case .condition: "Condition Icon"
        case .wind: "Wind"
        case .humidity: "Humidity"
        case .feelsLike: "Feels Like"
        case .precipitation: "Precipitation"
        case .sunrise: "Sunrise"
        case .sunset: "Sunset"
        case .uvIndex: "UV Index"
        case .visibility: "Visibility"
        case .pressure: "Pressure"
        case .locationName: "Location Name"
        case .conditionDescription: "Condition Description"
        case .highLowTemp: "High / Low Temperature"
        }
    }

    static var selectableCases: [WeatherInfoType] {
        return [.temperature, .condition, .conditionDescription, .highLowTemp, .locationName, .wind, .humidity, .feelsLike, .precipitation, .sunrise, .sunset, .uvIndex, .visibility, .pressure]
    }
}

enum FocusDisplayMode: String, Codable, CaseIterable, Identifiable {
    case full, compact
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .full: "Show Full Name"
        case .compact: "Icon Only (On/Off)"
        }
    }
}

enum LockScreenMainWidgetType: String, Codable, CaseIterable, Identifiable {
    case music, weather, calendar
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.capitalized }

    static var selectableCases: [LockScreenMainWidgetType] {
        return [.music, .weather, .calendar]
    }
}

enum LockScreenWidgetType: String, Codable, CaseIterable, Identifiable {
    case none, weather, calendar, music, focus, bluetooth, battery
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.capitalized }

    static var selectableCases: [LockScreenWidgetType] {
        return [.weather, .calendar, .music, .focus, .bluetooth, .battery]
    }
}

enum LockScreenMiniWidgetType: String, Codable, CaseIterable, Identifiable {
    case none, weather, calendar, music, battery
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.capitalized }

    static var selectableCases: [LockScreenMiniWidgetType] {
        return [.weather, .calendar, .music, .battery]
    }
}

enum BatteryInfoType: String, Codable, CaseIterable, Identifiable {
    case percentage, statusIcon, batteryIcon, estimatedTime
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .percentage: "Percentage"
        case .statusIcon: "Status Icon"
        case .batteryIcon: "Battery Icon"
        case .estimatedTime: "Estimated Time"
        }
    }
}

enum SnapZoneViewMode: String, Codable, CaseIterable, Identifiable {
    case single, multi
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.capitalized }
}

enum AppSnapLayoutConfiguration: Codable, Equatable {
    case useGlobalDefault
    case single(layoutID: UUID)
    case multi(layoutIDs: [UUID])

    enum CodingKeys: String, CodingKey {
        case type, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "useGlobalDefault":
            self = .useGlobalDefault
        case "single":
            let layoutID = try container.decode(UUID.self, forKey: .payload)
            self = .single(layoutID: layoutID)
        case "multi":
            let layoutIDs = try container.decode([UUID].self, forKey: .payload)
            self = .multi(layoutIDs: layoutIDs)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .useGlobalDefault:
            try container.encode("useGlobalDefault", forKey: .type)
        case .single(let layoutID):
            try container.encode("single", forKey: .type)
            try container.encode(layoutID, forKey: .payload)
        case .multi(let layoutIDs):
            try container.encode("multi", forKey: .type)
            try container.encode(layoutIDs, forKey: .payload)
        }
    }
}

enum RestorableNotchMenu: String, Codable, Equatable {
    case defaultWidgets
    case musicPlayer
    case musicQueueAndPlaylists
    case musicDevices
    case nearDrop
    case fileShelf
    case multiAudio
    case weatherPlayer
    case calendarPlayer
    case timerDetailView

    func toNotchWidgetMode() -> NotchWidgetMode {
        switch self {
        case .defaultWidgets: return .defaultWidgets
        case .musicPlayer: return .musicPlayer
        case .musicQueueAndPlaylists: return .musicQueueAndPlaylists
        case .musicDevices: return .musicDevices
        case .nearDrop: return .nearDrop
        case .fileShelf: return .fileShelf
        case .multiAudio: return .multiAudio
        case .weatherPlayer: return .weatherPlayer
        case .calendarPlayer: return .calendarPlayer
        case .timerDetailView: return .timerDetailView
        }
    }
}

struct NotchAppearanceSettings: Codable, Equatable {
    var backgroundStyle: NotchBackgroundStyle = .solid
    var solidColor: CodableColor = CodableColor(color: .black)
    var gradientColors: [CodableColor] = [
        CodableColor(color: Color(red: 0.2, green: 0.3, blue: 0.9), location: 0.0),
        CodableColor(color: .black, location: 1.0)
    ]
    var gradientAngle: Double = 90.0
    var opacity: Double = 1.0
    var enableTransparencyBlur: Bool = true
    var liquidGlassLook: Bool = false
}

enum MediaSource: String, Codable, CaseIterable, Identifiable {
    case system, spotify, appleMusic
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .system: "System Wide"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }
}

enum NotchDisplayTarget: String, Codable, CaseIterable, Identifiable {
    case macbookDisplay, mainDisplay, allDisplays
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .macbookDisplay: "MacBook Display Only"
        case .mainDisplay: "Main Display Only"
        case .allDisplays: "All Displays"
        }
    }
}

enum HUDVisualStyle: String, Codable, CaseIterable, Identifiable {
    case white, color, adaptive
    var id: String { self.rawValue.capitalized }
}

enum NotchBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, radial
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.capitalized }
}

enum MusicPlayerButtonType: String, Codable, CaseIterable, Identifiable, Equatable {
    case like, shuffle, `repeat`, playlists, devices
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .like: "Like"
        case .shuffle: "Shuffle"
        case .repeat: "Repeat"
        case .playlists: "Queue & Playlists"
        case .devices: "Devices"
        }
    }

    var systemImage: String {
        switch self {
        case .like: "heart.fill"
        case .shuffle: "shuffle"
        case .repeat: "repeat"
        case .playlists: "list.bullet"
        case .devices: "hifispeaker"
        }
    }
}

// MARK: - Main Settings Struct (Refactored)
struct Settings: Codable, Equatable {
    var useCustomNotchConfiguration: Bool = false
    var customNotchConfiguration: CustomizableNotchConfiguration = .init()
    var lockScreenShowInfoWidget: Bool = true
    var lockScreenWidgets: [LockScreenWidgetType] = [.weather, .bluetooth]
    var lockScreenHideInactiveInfoWidgets: Bool = true
    var lockScreenShowMainWidget: Bool = false
    var lockScreenMainWidgets: [LockScreenMainWidgetType] = [.weather]
    var lockScreenShowMiniWidgets: Bool = true
    var lockScreenMiniWidgets: [LockScreenMiniWidgetType] = [.music]
    var lockScreenShowNotch: Bool = true
    var lockScreenLiveActivityEnabled: Bool = true
    var lockScreenLiquidGlassLook: Bool = true

    var lockScreenWeatherInfo: [WeatherInfoType] = [.temperature]
    var lockScreenBatteryInfo: [BatteryInfoType] = [.batteryIcon, .percentage]

    var notchWidgetAppearance: NotchAppearanceSettings = .init()
    var notchLiveActivityAppearance: NotchAppearanceSettings = .init()

    var launchAtLogin: Bool = true
    var appLanguage: String = "en"
    var hapticFeedbackEnabled: Bool = true
    var hideFromScreenSharing: Bool = false
    var notchDisplayTarget: NotchDisplayTarget = .macbookDisplay

    // MARK: - Features & Notch Bar
    var expandOnHover: Bool = false
    var launchpadEnabled: Bool = false
    var caffeinateEnabled: Bool = true
    var fileShelfIconEnabled: Bool = true
    var batteryEstimatorEnabled: Bool = true
    var geminiEnabled: Bool = true
    var pinEnabled: Bool = true
    var hideNotchWhenInactive: Bool = false
    var notchButtonOrder: [NotchButtonType] = [
        .settings, .fileShelf, .gemini, .spacer, .battery, .multiAudio, .caffeine, .pin
    ]

    // MARK: - Widgets
    var rememberLastMenu: Bool = false
    var lastNotchNavigationStack: [RestorableNotchMenu]? = nil

    var showDividersBetweenWidgets: Bool = false
    var widgetOrder: [WidgetType] = [.music, .weather, .calendar, .shortcuts]
    var musicWidgetEnabled: Bool = true
    var weatherWidgetEnabled: Bool = true
    var calendarWidgetEnabled: Bool = true
    var shortcutsWidgetEnabled: Bool = false
    var timerWidgetEnabled: Bool = true
    var selectedShortcuts: [ShortcutInfo] = []

    // MARK: - Live Activities
    var liveActivityOrder: [LiveActivityType] = LiveActivityType.allCases
    var musicLiveActivityEnabled: Bool = true
    var weatherLiveActivityEnabled: Bool = true
    var calendarLiveActivityEnabled: Bool = true
    var remindersLiveActivityEnabled: Bool = true
    var timersLiveActivityEnabled: Bool = true
    var batteryLiveActivityEnabled: Bool = true
    var eyeBreakLiveActivityEnabled: Bool = false
    var desktopLiveActivityEnabled: Bool = true
    var focusLiveActivityEnabled: Bool = true
    var fileShelfLiveActivityEnabled: Bool = true
    var fileProgressLiveActivityEnabled: Bool = false
    var swipeToDismissLiveActivity: Bool = true
    var hideLiveActivityInFullScreen: Bool = false
    var hideActivitiesInFullScreen: [String: Bool] = [:]
    var showPersistentBatteryLiveActivity: Bool = false
    var showPersistentWeatherLiveActivity: Bool = true
    var weatherLiveActivityInterval: Int = 10

    var focusDisplayMode: FocusDisplayMode = .full

    // MARK: - Music & Spotify
    var mediaSource: MediaSource = .system
    var prioritizeMediaSource: Bool = true
    var hideLiveActivityWhenSourceActive: Bool = true
    var enableQuickPeekOnHover: Bool = true
    var showQuickPeekOnTrackChange: Bool = true
    var swipeToSkipMusic: Bool = true
    var swipeToRewindMusic: Bool = true
    var invertMusicGestures: Bool = false
    var twoFingerTapToPauseMusic: Bool = true
    var waveformUseGradient: Bool = true
    var useStaticWaveform: Bool = false
    var waveformBarCount: Int = 3
    var waveformBarThickness: Double = 4.0
    var musicWaveformIsVolumeSensitive: Bool = true
    var spotifyClientId: String = ""
    var spotifyClientSecret: String = ""
    var skipSpotifyAd: Bool = false
    var defaultMusicPlayer: DefaultMusicPlayer = .appleMusic
    var showLyricsInLiveActivity: Bool = false
    var enableLyricTranslation: Bool = true
    var lyricTranslationLanguage: String = "en"
    var musicAppStates: [String: Bool] = [:]
    var musicOpenOnClick: Bool = true
    var musicPlayerButtonOrder: [MusicPlayerButtonType] = [.playlists, .devices, .like, .shuffle, .repeat]
    var musicLikeButtonEnabled: Bool = false
    var musicShuffleButtonEnabled: Bool = false
    var musicRepeatButtonEnabled: Bool = false
    var musicPlaylistsButtonEnabled: Bool = true
    var musicDevicesButtonEnabled: Bool = true
    var showPopularityInMusicPlayer: Bool = true
    var hideMusicWidgetWhenNotPlaying: Bool = false
    var preferAirPlayOverSpotify: Bool = true

    // MARK: - System HUD
    var hudDuration: Double = 2.5
    var hudShowPercentage: Bool = true
    var hudVisualStyle: HUDVisualStyle = .adaptive
    var hudCustomColor: CodableColor? = CodableColor(color: .accentColor)
    var enableVolumeHUD: Bool = true
    var volumeHUDStyle: HUDStyle = .default
    var volumeHUDSoundEnabled: Bool = true
    var showSpotifyVolumeHUD: Bool = true
    var volumeHUDShowDeviceIcon: Bool = true
    var excludeBuiltInSpeakersFromHUDIcon: Bool = true
    var enableBrightnessHUD: Bool = true
    var brightnessHUDStyle: HUDStyle = .default
    var volumesliderstep: Int = 6
    var brightnessliderstep: Int = 6

    // MARK: - Snap Zones & Planes
    var snapZoneViewMode: SnapZoneViewMode = .multi
    var snapOnWindowDragEnabled: Bool = true
    var defaultSnapLayout: SnapLayout = LayoutTemplate.columns
    var appSpecificLayoutConfigurations: [String: AppSnapLayoutConfiguration] = [:]
    var customSnapLayouts: [SnapLayout] = []
    var snapZoneLayoutOptions: [UUID] = [
        LayoutTemplate.columns.id,
        LayoutTemplate.splitscreen.id,
        LayoutTemplate.focus.id
    ]
    var planes: [Plane] = []

    // MARK: - Battery & Charging
    var batteryChargeLimit: Int = 80
    var lowBatteryNotificationPercentage: Int = 20
    var lowBatteryNotificationSoundEnabled: Bool = true
    var batteryNotificationStyle: BatteryNotificationStyle = .default
    var promptForLowPowerMode: Bool = true
    var showEstimatedBatteryTime: Bool = true
    var automaticDischargeEnabled: Bool = true
    var heatProtectionEnabled: Bool = true
    var heatProtectionThreshold: Double = 40.0
    var sailingModeEnabled: Bool = true
    var sailingModeLowerLimit: Int = 10
    var useHardwareBatteryPercentage: Bool = false
    var controlMagSafeLEDEnabled: Bool = true
    var stopChargingWhenSleeping: Bool = false
    var disableSleepUntilChargeLimit: Bool = false
    var lowPowerMode: LowPowerMode = .never
    var scheduledTasks: [ScheduledTask] = []
    var stopChargingWhenAppClosed: Bool = false
    var magSafeLEDBlinkOnDischarge: Bool = false
    var magSafeLEDSetting: MagSafeLEDSetting = .alwaysOn
    var preventSleepDuringCalibration: Bool = true
    var preventSleepDuringDischarge: Bool = true
    var enableBiweeklyCalibration: Bool = false
    var magSafeGreenAtLimit: Bool = true

    // MARK: - Bluetooth
    var bluetoothNotifyLowBattery: Bool = true
    var bluetoothNotifySound: Bool = true
    var showBluetoothDeviceName: Bool = false

    // MARK: - Proximity Unlock Settings

    var bluetoothUnlockEnabled: Bool = false
    var bluetoothUnlockDeviceID: String? = nil
    var bluetoothUnlockUnlockRSSI: Int = -65
    var bluetoothUnlockLockRSSI: Int = -75
    var bluetoothUnlockTimeout: Double = 5.0
    var bluetoothUnlockNoSignalTimeout: Double = 60.0
    var bluetoothUnlockMinScanRSSI: Int = -80
    var bluetoothUnlockPassiveMode: Bool = false

    var faceIDUnlockEnabled: Bool = false
    var hasRegisteredFaceID: Bool = false

    var bluetoothUnlockWakeOnProximity: Bool = true
    var bluetoothUnlockWakeWithoutUnlocking: Bool = false
    var bluetoothUnlockPauseMusicOnLock: Bool = false
    var bluetoothUnlockUseScreensaver: Bool = false
    var bluetoothUnlockTurnOffScreenOnLock: Bool = true

    // MARK: - Notifications
    var masterNotificationsEnabled: Bool = true
    var iMessageNotificationsEnabled: Bool = true
    var airDropNotificationsEnabled: Bool = true
    var faceTimeNotificationsEnabled: Bool = true
    var systemNotificationsEnabled: Bool = true
    var appNotificationStates: [String: Bool] = [:]

    var onlyShowVerificationCodeNotifications: Bool = true
    var showCopyButtonForVerificationCodes: Bool = true

    // MARK: - Neardrop
    var neardropEnabled: Bool = true
    var neardropDeviceDisplayName: String = Host.current().localizedName ?? "My Mac"
    var neardropDownloadLocationPath: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path
    var neardropOpenOnClick: Bool = true

    // MARK: - File Shelf
    var clickToOpenFileShelf: Bool = true
    var hoverToOpenFileShelf: Bool = true

    // MARK: - Launchpad
    var launchpadLayout: [[LaunchpadPageItem]] = []

    // MARK: - Weather
    var weatherUseCelsius: Bool = false
    var weatherOpenOnClick: Bool = false

    // MARK: - Calendar & Reminders
    var calendarShowAllDayEvents: Bool = true
    var calendarStartOfWeek: Day = .sunday
    var calendarOpenOnClick: Bool = true

    // MARK: - Eye Break
    var eyeBreakWorkInterval: Double = 20
    var eyeBreakBreakDuration: Double = 20
    var eyeBreakSoundAlerts: Bool = true
    var showEyeBreakGraph: Bool = true

    // MARK: - Gemini
    var geminiApiKey: String = ""

    // MARK: - Timer & Stopwatch
    var clickToShowTimerView: Bool = true
}

// MARK: - SettingsModel Class
class SettingsModel: ObservableObject {
    static let shared = SettingsModel()
    @Published var settings: Settings = Settings() {
        didSet {
            if oldValue != settings {
                saveSettings(settings: settings, from: oldValue)
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let settingsAccessQueue = DispatchQueue(label: "com.shariq.sapphire.settings.sync.queue")

    private init() {
        loadSettings()
    }

    private func decode<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? PropertyListDecoder().decode(T.self, from: data)
    }

    private func encode<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? PropertyListEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func loadSettings() {
        settingsAccessQueue.sync {
            var loadedSettings = Settings()

            loadedSettings.useCustomNotchConfiguration = defaults.object(forKey: "useCustomNotchConfiguration") as? Bool ?? loadedSettings.useCustomNotchConfiguration
            loadedSettings.customNotchConfiguration = decode(CustomizableNotchConfiguration.self, forKey: "customNotchConfiguration") ?? loadedSettings.customNotchConfiguration
            loadedSettings.lockScreenShowInfoWidget = defaults.object(forKey: "lockScreenShowInfoWidget") as? Bool ?? loadedSettings.lockScreenShowInfoWidget
            if let widgetsRaw = defaults.array(forKey: "lockScreenWidgets") as? [String] {
                loadedSettings.lockScreenWidgets = widgetsRaw.compactMap { LockScreenWidgetType(rawValue: $0) }
            }
            loadedSettings.lockScreenHideInactiveInfoWidgets = defaults.object(forKey: "lockScreenHideInactiveInfoWidgets") as? Bool ?? loadedSettings.lockScreenHideInactiveInfoWidgets

            loadedSettings.lockScreenShowMainWidget = defaults.object(forKey: "lockScreenShowMainWidget") as? Bool ?? loadedSettings.lockScreenShowMainWidget
            var mainWidgets: [LockScreenMainWidgetType] = []
            if let mainWidgetsRaw = defaults.array(forKey: "lockScreenMainWidgets") as? [String] {
                mainWidgets = mainWidgetsRaw.compactMap { LockScreenMainWidgetType(rawValue: $0) }
            } else if let oldMainWidgetRaw = defaults.string(forKey: "lockScreenMainWidget"),
                      let oldMainWidget = LockScreenMainWidgetType(rawValue: oldMainWidgetRaw) {
                mainWidgets.append(oldMainWidget)
            } else {
                mainWidgets = loadedSettings.lockScreenMainWidgets
            }
            loadedSettings.lockScreenMainWidgets = mainWidgets

            loadedSettings.lockScreenShowMiniWidgets = defaults.object(forKey: "lockScreenShowMiniWidgets") as? Bool ?? loadedSettings.lockScreenShowMiniWidgets
            if let miniWidgetsRaw = defaults.array(forKey: "lockScreenMiniWidgets") as? [String] {
                loadedSettings.lockScreenMiniWidgets = miniWidgetsRaw.compactMap { LockScreenMiniWidgetType(rawValue: $0) }
            }

            if let weatherInfoRaw = defaults.array(forKey: "lockScreenWeatherInfo") as? [String] {
                loadedSettings.lockScreenWeatherInfo = weatherInfoRaw.compactMap { WeatherInfoType(rawValue: $0) }
            }

            if let batteryInfoRaw = defaults.array(forKey: "lockScreenBatteryInfo") as? [String] {
                loadedSettings.lockScreenBatteryInfo = batteryInfoRaw.compactMap { BatteryInfoType(rawValue: $0) }
            }

            loadedSettings.lockScreenShowNotch = defaults.object(forKey: "lockScreenShowNotch") as? Bool ?? loadedSettings.lockScreenShowNotch
            loadedSettings.lockScreenLiveActivityEnabled = defaults.object(forKey: "lockScreenLiveActivityEnabled") as? Bool ?? loadedSettings.lockScreenLiveActivityEnabled
            loadedSettings.lockScreenLiquidGlassLook = defaults.object(forKey: "lockScreenLiquidGlassLook") as? Bool ?? loadedSettings.lockScreenLiquidGlassLook

            loadedSettings.notchWidgetAppearance = decode(NotchAppearanceSettings.self, forKey: "notchWidgetAppearance") ?? .init()
            loadedSettings.notchLiveActivityAppearance = decode(NotchAppearanceSettings.self, forKey: "notchLiveActivityAppearance") ?? .init()

            loadedSettings.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? loadedSettings.launchAtLogin
            loadedSettings.appLanguage = defaults.string(forKey: "appLanguage") ?? loadedSettings.appLanguage
            loadedSettings.hapticFeedbackEnabled = defaults.object(forKey: "hapticFeedbackEnabled") as? Bool ?? loadedSettings.hapticFeedbackEnabled
            loadedSettings.hideFromScreenSharing = defaults.object(forKey: "hideFromScreenSharing") as? Bool ?? loadedSettings.hideFromScreenSharing
            if let target = defaults.string(forKey: "notchDisplayTarget"), let displayTarget = NotchDisplayTarget(rawValue: target) {
                loadedSettings.notchDisplayTarget = displayTarget
            }

            loadedSettings.expandOnHover = defaults.object(forKey: "expandOnHover") as? Bool ?? loadedSettings.expandOnHover
            loadedSettings.launchpadEnabled = defaults.object(forKey: "launchpadEnabled") as? Bool ?? loadedSettings.launchpadEnabled
            loadedSettings.caffeinateEnabled = defaults.object(forKey: "caffeinateEnabled") as? Bool ?? loadedSettings.caffeinateEnabled
            loadedSettings.fileShelfIconEnabled = defaults.object(forKey: "fileShelfIconEnabled") as? Bool ?? loadedSettings.fileShelfIconEnabled
            loadedSettings.batteryEstimatorEnabled = defaults.object(forKey: "batteryEstimatorEnabled") as? Bool ?? loadedSettings.batteryEstimatorEnabled
            loadedSettings.geminiEnabled = defaults.object(forKey: "geminiEnabled") as? Bool ?? loadedSettings.geminiEnabled
            loadedSettings.pinEnabled = defaults.object(forKey: "pinEnabled") as? Bool ?? loadedSettings.pinEnabled
            loadedSettings.hideNotchWhenInactive = defaults.object(forKey: "hideNotchWhenInactive") as? Bool ?? loadedSettings.hideNotchWhenInactive
            loadedSettings.notchButtonOrder = decode([NotchButtonType].self, forKey: "notchButtonOrder") ?? loadedSettings.notchButtonOrder

            loadedSettings.showDividersBetweenWidgets = defaults.object(forKey: "showDividersBetweenWidgets") as? Bool ?? loadedSettings.showDividersBetweenWidgets
            loadedSettings.widgetOrder = decode([WidgetType].self, forKey: "widgetOrder") ?? loadedSettings.widgetOrder
            loadedSettings.musicWidgetEnabled = defaults.object(forKey: "musicWidgetEnabled") as? Bool ?? loadedSettings.musicWidgetEnabled
            loadedSettings.weatherWidgetEnabled = defaults.object(forKey: "weatherWidgetEnabled") as? Bool ?? loadedSettings.weatherWidgetEnabled
            loadedSettings.calendarWidgetEnabled = defaults.object(forKey: "calendarWidgetEnabled") as? Bool ?? loadedSettings.calendarWidgetEnabled
            loadedSettings.shortcutsWidgetEnabled = defaults.object(forKey: "shortcutsWidgetEnabled") as? Bool ?? loadedSettings.shortcutsWidgetEnabled
            loadedSettings.timerWidgetEnabled = defaults.object(forKey: "timerWidgetEnabled") as? Bool ?? loadedSettings.timerWidgetEnabled
            loadedSettings.selectedShortcuts = decode([ShortcutInfo].self, forKey: "selectedShortcuts") ?? loadedSettings.selectedShortcuts

            loadedSettings.rememberLastMenu = defaults.object(forKey: "rememberLastMenu") as? Bool ?? loadedSettings.rememberLastMenu
            loadedSettings.lastNotchNavigationStack = decode([RestorableNotchMenu].self, forKey: "lastNotchNavigationStack")

            loadedSettings.liveActivityOrder = decode([LiveActivityType].self, forKey: "liveActivityOrder") ?? loadedSettings.liveActivityOrder
            loadedSettings.musicLiveActivityEnabled = defaults.object(forKey: "musicLiveActivityEnabled") as? Bool ?? loadedSettings.musicLiveActivityEnabled
            loadedSettings.weatherLiveActivityEnabled = defaults.object(forKey: "weatherLiveActivityEnabled") as? Bool ?? loadedSettings.weatherLiveActivityEnabled
            loadedSettings.calendarLiveActivityEnabled = defaults.object(forKey: "calendarLiveActivityEnabled") as? Bool ?? loadedSettings.calendarLiveActivityEnabled
            loadedSettings.remindersLiveActivityEnabled = defaults.object(forKey: "remindersLiveActivityEnabled") as? Bool ?? loadedSettings.remindersLiveActivityEnabled
            loadedSettings.timersLiveActivityEnabled = defaults.object(forKey: "timersLiveActivityEnabled") as? Bool ?? loadedSettings.timersLiveActivityEnabled
            loadedSettings.batteryLiveActivityEnabled = defaults.object(forKey: "batteryLiveActivityEnabled") as? Bool ?? loadedSettings.batteryLiveActivityEnabled
            loadedSettings.eyeBreakLiveActivityEnabled = defaults.object(forKey: "eyeBreakLiveActivityEnabled") as? Bool ?? loadedSettings.eyeBreakLiveActivityEnabled
            loadedSettings.desktopLiveActivityEnabled = defaults.object(forKey: "desktopLiveActivityEnabled") as? Bool ?? loadedSettings.desktopLiveActivityEnabled
            loadedSettings.focusLiveActivityEnabled = defaults.object(forKey: "focusLiveActivityEnabled") as? Bool ?? loadedSettings.focusLiveActivityEnabled
            loadedSettings.fileShelfLiveActivityEnabled = defaults.object(forKey: "fileShelfLiveActivityEnabled") as? Bool ?? loadedSettings.fileShelfLiveActivityEnabled
            loadedSettings.fileProgressLiveActivityEnabled = defaults.object(forKey: "fileProgressLiveActivityEnabled") as? Bool ?? loadedSettings.fileProgressLiveActivityEnabled
            loadedSettings.swipeToDismissLiveActivity = defaults.object(forKey: "swipeToDismissLiveActivity") as? Bool ?? loadedSettings.swipeToDismissLiveActivity
            loadedSettings.hideLiveActivityInFullScreen = defaults.object(forKey: "hideLiveActivityInFullScreen") as? Bool ?? loadedSettings.hideLiveActivityInFullScreen
            loadedSettings.hideActivitiesInFullScreen = decode([String: Bool].self, forKey: "hideActivitiesInFullScreen") ?? loadedSettings.hideActivitiesInFullScreen
            loadedSettings.showPersistentBatteryLiveActivity = defaults.object(forKey: "showPersistentBatteryLiveActivity") as? Bool ?? loadedSettings.showPersistentBatteryLiveActivity
            loadedSettings.showPersistentWeatherLiveActivity = defaults.object(forKey: "showPersistentWeatherLiveActivity") as? Bool ?? loadedSettings.showPersistentWeatherLiveActivity
            loadedSettings.weatherLiveActivityInterval = defaults.object(forKey: "weatherLiveActivityInterval") as? Int ?? loadedSettings.weatherLiveActivityInterval

            if let mode = defaults.string(forKey: "focusDisplayMode"), let displayMode = FocusDisplayMode(rawValue: mode) {
                loadedSettings.focusDisplayMode = displayMode
            }

            if let source = defaults.string(forKey: "mediaSource"), let mediaSource = MediaSource(rawValue: source) { loadedSettings.mediaSource = mediaSource }
            loadedSettings.prioritizeMediaSource = defaults.object(forKey: "prioritizeMediaSource") as? Bool ?? loadedSettings.prioritizeMediaSource
            loadedSettings.hideLiveActivityWhenSourceActive = defaults.object(forKey: "hideLiveActivityWhenSourceActive") as? Bool ?? loadedSettings.hideLiveActivityWhenSourceActive
            loadedSettings.enableQuickPeekOnHover = defaults.object(forKey: "enableQuickPeekOnHover") as? Bool ?? loadedSettings.enableQuickPeekOnHover
            loadedSettings.showQuickPeekOnTrackChange = defaults.object(forKey: "showQuickPeekOnTrackChange") as? Bool ?? loadedSettings.showQuickPeekOnTrackChange
            loadedSettings.swipeToSkipMusic = defaults.object(forKey: "swipeToSkipMusic") as? Bool ?? loadedSettings.swipeToSkipMusic
            loadedSettings.swipeToRewindMusic = defaults.object(forKey: "swipeToRewindMusic") as? Bool ?? loadedSettings.swipeToRewindMusic
            loadedSettings.invertMusicGestures = defaults.object(forKey: "invertMusicGestures") as? Bool ?? loadedSettings.invertMusicGestures
            loadedSettings.twoFingerTapToPauseMusic = defaults.object(forKey: "twoFingerTapToPauseMusic") as? Bool ?? loadedSettings.twoFingerTapToPauseMusic
            loadedSettings.waveformUseGradient = defaults.object(forKey: "waveformUseGradient") as? Bool ?? loadedSettings.waveformUseGradient
            loadedSettings.useStaticWaveform = defaults.object(forKey: "useStaticWaveform") as? Bool ?? loadedSettings.useStaticWaveform
            loadedSettings.waveformBarCount = defaults.object(forKey: "waveformBarCount") as? Int ?? loadedSettings.waveformBarCount
            loadedSettings.waveformBarThickness = defaults.object(forKey: "waveformBarThickness") as? Double ?? loadedSettings.waveformBarThickness
            loadedSettings.musicWaveformIsVolumeSensitive = defaults.object(forKey: "musicWaveformIsVolumeSensitive") as? Bool ?? loadedSettings.musicWaveformIsVolumeSensitive
            loadedSettings.spotifyClientId = defaults.string(forKey: "spotifyClientId") ?? ""
            loadedSettings.spotifyClientSecret = defaults.string(forKey: "spotifyClientSecret") ?? ""
            loadedSettings.skipSpotifyAd = defaults.object(forKey: "skipSpotifyAd") as? Bool ?? loadedSettings.skipSpotifyAd
            if let player = defaults.string(forKey: "defaultMusicPlayer"), let defaultPlayer = DefaultMusicPlayer(rawValue: player) { loadedSettings.defaultMusicPlayer = defaultPlayer }
            loadedSettings.showLyricsInLiveActivity = defaults.object(forKey: "showLyricsInLiveActivity") as? Bool ?? loadedSettings.showLyricsInLiveActivity
            loadedSettings.enableLyricTranslation = defaults.object(forKey: "enableLyricTranslation") as? Bool ?? loadedSettings.enableLyricTranslation
            loadedSettings.lyricTranslationLanguage = defaults.string(forKey: "lyricTranslationLanguage") ?? "en"
            loadedSettings.musicOpenOnClick = defaults.object(forKey: "musicOpenOnClick") as? Bool ?? loadedSettings.musicOpenOnClick
            loadedSettings.musicAppStates = decode([String: Bool].self, forKey: "musicAppStates") ?? loadedSettings.musicAppStates
            loadedSettings.musicPlayerButtonOrder = decode([MusicPlayerButtonType].self, forKey: "musicPlayerButtonOrder") ?? loadedSettings.musicPlayerButtonOrder
            loadedSettings.musicLikeButtonEnabled = defaults.object(forKey: "musicLikeButtonEnabled") as? Bool ?? loadedSettings.musicLikeButtonEnabled
            loadedSettings.musicShuffleButtonEnabled = defaults.object(forKey: "musicShuffleButtonEnabled") as? Bool ?? loadedSettings.musicShuffleButtonEnabled
            loadedSettings.musicRepeatButtonEnabled = defaults.object(forKey: "musicRepeatButtonEnabled") as? Bool ?? loadedSettings.musicRepeatButtonEnabled
            loadedSettings.musicPlaylistsButtonEnabled = defaults.object(forKey: "musicPlaylistsButtonEnabled") as? Bool ?? loadedSettings.musicPlaylistsButtonEnabled
            loadedSettings.musicDevicesButtonEnabled = defaults.object(forKey: "musicDevicesButtonEnabled") as? Bool ?? loadedSettings.musicDevicesButtonEnabled
            loadedSettings.showPopularityInMusicPlayer = defaults.object(forKey: "showPopularityInMusicPlayer") as? Bool ?? loadedSettings.showPopularityInMusicPlayer
            loadedSettings.hideMusicWidgetWhenNotPlaying = defaults.object(forKey: "hideMusicWidgetWhenNotPlaying") as? Bool ?? loadedSettings.hideMusicWidgetWhenNotPlaying
            loadedSettings.preferAirPlayOverSpotify = defaults.object(forKey: "preferAirPlayOverSpotify") as? Bool ?? loadedSettings.preferAirPlayOverSpotify

            loadedSettings.hudDuration = defaults.object(forKey: "hudDuration") as? Double ?? loadedSettings.hudDuration
            loadedSettings.brightnessliderstep = defaults.object(forKey: "brightnessliderstep") as? Int ?? loadedSettings.brightnessliderstep
            loadedSettings.volumesliderstep = defaults.object(forKey: "volumesliderstep") as? Int ?? loadedSettings.volumesliderstep
            loadedSettings.hudShowPercentage = defaults.object(forKey: "hudShowPercentage") as? Bool ?? loadedSettings.hudShowPercentage
            if let style = defaults.string(forKey: "hudVisualStyle"), let visualStyle = HUDVisualStyle(rawValue: style) { loadedSettings.hudVisualStyle = visualStyle }
            loadedSettings.hudCustomColor = decode(CodableColor.self, forKey: "hudCustomColor") ?? loadedSettings.hudCustomColor
            loadedSettings.enableVolumeHUD = defaults.object(forKey: "enableVolumeHUD") as? Bool ?? loadedSettings.enableVolumeHUD
            if let style = defaults.string(forKey: "volumeHUDStyle"), let hudStyle = HUDStyle(rawValue: style) { loadedSettings.volumeHUDStyle = hudStyle }
            loadedSettings.volumeHUDSoundEnabled = defaults.object(forKey: "volumeHUDSoundEnabled") as? Bool ?? loadedSettings.volumeHUDSoundEnabled
            loadedSettings.showSpotifyVolumeHUD = defaults.object(forKey: "showSpotifyVolumeHUD") as? Bool ?? loadedSettings.showSpotifyVolumeHUD
            loadedSettings.volumeHUDShowDeviceIcon = defaults.object(forKey: "volumeHUDShowDeviceIcon") as? Bool ?? loadedSettings.volumeHUDShowDeviceIcon
            loadedSettings.excludeBuiltInSpeakersFromHUDIcon = defaults.object(forKey: "excludeBuiltInSpeakersFromHUDIcon") as? Bool ?? loadedSettings.excludeBuiltInSpeakersFromHUDIcon
            loadedSettings.enableBrightnessHUD = defaults.object(forKey: "enableBrightnessHUD") as? Bool ?? loadedSettings.enableBrightnessHUD
            if let style = defaults.string(forKey: "brightnessHUDStyle"), let hudStyle = HUDStyle(rawValue: style) { loadedSettings.brightnessHUDStyle = hudStyle }

            if let mode = defaults.string(forKey: "snapZoneViewMode"), let viewMode = SnapZoneViewMode(rawValue: mode) {
                loadedSettings.snapZoneViewMode = viewMode
            }
            loadedSettings.snapOnWindowDragEnabled = defaults.object(forKey: "snapOnWindowDragEnabled") as? Bool ?? loadedSettings.snapOnWindowDragEnabled
            loadedSettings.defaultSnapLayout = decode(SnapLayout.self, forKey: "defaultSnapLayout") ?? loadedSettings.defaultSnapLayout
            loadedSettings.appSpecificLayoutConfigurations = decode([String: AppSnapLayoutConfiguration].self, forKey: "appSpecificLayoutConfigurations") ?? loadedSettings.appSpecificLayoutConfigurations
            loadedSettings.customSnapLayouts = decode([SnapLayout].self, forKey: "customSnapLayouts") ?? loadedSettings.customSnapLayouts
            loadedSettings.snapZoneLayoutOptions = decode([UUID].self, forKey: "snapZoneLayoutOptions") ?? loadedSettings.snapZoneLayoutOptions
            loadedSettings.planes = decode([Plane].self, forKey: "planes") ?? loadedSettings.planes

            loadedSettings.batteryChargeLimit = defaults.object(forKey: "batteryChargeLimit") as? Int ?? loadedSettings.batteryChargeLimit
            loadedSettings.lowBatteryNotificationPercentage = defaults.object(forKey: "lowBatteryNotificationPercentage") as? Int ?? loadedSettings.lowBatteryNotificationPercentage
            loadedSettings.lowBatteryNotificationSoundEnabled = defaults.object(forKey: "lowBatteryNotificationSoundEnabled") as? Bool ?? loadedSettings.lowBatteryNotificationSoundEnabled
            if let style = defaults.string(forKey: "batteryNotificationStyle"), let notificationStyle = BatteryNotificationStyle(rawValue: style) { loadedSettings.batteryNotificationStyle = notificationStyle }
            loadedSettings.promptForLowPowerMode = defaults.object(forKey: "promptForLowPowerMode") as? Bool ?? loadedSettings.promptForLowPowerMode
            loadedSettings.showEstimatedBatteryTime = defaults.object(forKey: "showEstimatedBatteryTime") as? Bool ?? loadedSettings.showEstimatedBatteryTime
            loadedSettings.automaticDischargeEnabled = defaults.object(forKey: "automaticDischargeEnabled") as? Bool ?? loadedSettings.automaticDischargeEnabled
            loadedSettings.heatProtectionEnabled = defaults.object(forKey: "heatProtectionEnabled") as? Bool ?? loadedSettings.heatProtectionEnabled
            loadedSettings.heatProtectionThreshold = defaults.object(forKey: "heatProtectionThreshold") as? Double ?? loadedSettings.heatProtectionThreshold
            loadedSettings.sailingModeEnabled = defaults.object(forKey: "sailingModeEnabled") as? Bool ?? loadedSettings.sailingModeEnabled
            loadedSettings.sailingModeLowerLimit = defaults.object(forKey: "sailingModeLowerLimit") as? Int ?? loadedSettings.sailingModeLowerLimit
            loadedSettings.useHardwareBatteryPercentage = defaults.object(forKey: "useHardwareBatteryPercentage") as? Bool ?? loadedSettings.useHardwareBatteryPercentage
            loadedSettings.controlMagSafeLEDEnabled = defaults.object(forKey: "controlMagSafeLEDEnabled") as? Bool ?? loadedSettings.controlMagSafeLEDEnabled
            loadedSettings.stopChargingWhenSleeping = defaults.object(forKey: "stopChargingWhenSleeping") as? Bool ?? loadedSettings.stopChargingWhenSleeping
            loadedSettings.disableSleepUntilChargeLimit = defaults.object(forKey: "disableSleepUntilChargeLimit") as? Bool ?? loadedSettings.disableSleepUntilChargeLimit
            if let lpm = defaults.string(forKey: "lowPowerMode"), let lowPowerMode = LowPowerMode(rawValue: lpm) { loadedSettings.lowPowerMode = lowPowerMode }
            loadedSettings.scheduledTasks = decode([ScheduledTask].self, forKey: "scheduledTasks") ?? loadedSettings.scheduledTasks
            loadedSettings.stopChargingWhenAppClosed = defaults.object(forKey: "stopChargingWhenAppClosed") as? Bool ?? loadedSettings.stopChargingWhenAppClosed
            loadedSettings.magSafeLEDBlinkOnDischarge = defaults.object(forKey: "magSafeLEDBlinkOnDischarge") as? Bool ?? loadedSettings.magSafeLEDBlinkOnDischarge
            if let led = defaults.string(forKey: "magSafeLEDSetting"), let magSafeLEDSetting = MagSafeLEDSetting(rawValue: led) { loadedSettings.magSafeLEDSetting = magSafeLEDSetting }
            loadedSettings.preventSleepDuringCalibration = defaults.object(forKey: "preventSleepDuringCalibration") as? Bool ?? loadedSettings.preventSleepDuringCalibration
            loadedSettings.preventSleepDuringDischarge = defaults.object(forKey: "preventSleepDuringDischarge") as? Bool ?? loadedSettings.preventSleepDuringDischarge
            loadedSettings.enableBiweeklyCalibration = defaults.object(forKey: "enableBiweeklyCalibration") as? Bool ?? loadedSettings.enableBiweeklyCalibration
            loadedSettings.magSafeGreenAtLimit = defaults.object(forKey: "magSafeGreenAtLimit") as? Bool ?? loadedSettings.magSafeGreenAtLimit

            loadedSettings.bluetoothNotifyLowBattery = defaults.object(forKey: "bluetoothNotifyLowBattery") as? Bool ?? loadedSettings.bluetoothNotifyLowBattery
            loadedSettings.bluetoothNotifySound = defaults.object(forKey: "bluetoothNotifySound") as? Bool ?? loadedSettings.bluetoothNotifySound
            loadedSettings.showBluetoothDeviceName = defaults.object(forKey: "showBluetoothDeviceName") as? Bool ?? loadedSettings.showBluetoothDeviceName

            loadedSettings.bluetoothUnlockEnabled = defaults.bool(forKey: "bluetoothUnlockEnabled")
            loadedSettings.bluetoothUnlockDeviceID = defaults.string(forKey: "bluetoothUnlockDeviceID")
            loadedSettings.bluetoothUnlockUnlockRSSI = defaults.object(forKey: "bluetoothUnlockUnlockRSSI") as? Int ?? loadedSettings.bluetoothUnlockUnlockRSSI
            loadedSettings.bluetoothUnlockLockRSSI = defaults.object(forKey: "bluetoothUnlockLockRSSI") as? Int ?? loadedSettings.bluetoothUnlockLockRSSI
            loadedSettings.bluetoothUnlockTimeout = defaults.object(forKey: "bluetoothUnlockTimeout") as? Double ?? loadedSettings.bluetoothUnlockTimeout
            loadedSettings.bluetoothUnlockNoSignalTimeout = defaults.object(forKey: "bluetoothUnlockNoSignalTimeout") as? Double ?? loadedSettings.bluetoothUnlockNoSignalTimeout
            loadedSettings.bluetoothUnlockMinScanRSSI = defaults.object(forKey: "bluetoothUnlockMinScanRSSI") as? Int ?? loadedSettings.bluetoothUnlockMinScanRSSI
            loadedSettings.bluetoothUnlockPassiveMode = defaults.object(forKey: "bluetoothUnlockPassiveMode") as? Bool ?? loadedSettings.bluetoothUnlockPassiveMode
            loadedSettings.faceIDUnlockEnabled = defaults.bool(forKey: "faceIDUnlockEnabled")
            loadedSettings.hasRegisteredFaceID = defaults.bool(forKey: "hasRegisteredFaceID")
            loadedSettings.bluetoothUnlockWakeOnProximity = defaults.object(forKey: "bluetoothUnlockWakeOnProximity") as? Bool ?? loadedSettings.bluetoothUnlockWakeOnProximity
            loadedSettings.bluetoothUnlockWakeWithoutUnlocking = defaults.object(forKey: "bluetoothUnlockWakeWithoutUnlocking") as? Bool ?? loadedSettings.bluetoothUnlockWakeWithoutUnlocking
            loadedSettings.bluetoothUnlockPauseMusicOnLock = defaults.object(forKey: "bluetoothUnlockPauseMusicOnLock") as? Bool ?? loadedSettings.bluetoothUnlockPauseMusicOnLock
            loadedSettings.bluetoothUnlockUseScreensaver = defaults.object(forKey: "bluetoothUnlockUseScreensaver") as? Bool ?? loadedSettings.bluetoothUnlockUseScreensaver
            loadedSettings.bluetoothUnlockTurnOffScreenOnLock = defaults.object(forKey: "bluetoothUnlockTurnOffScreenOnLock") as? Bool ?? loadedSettings.bluetoothUnlockTurnOffScreenOnLock

            loadedSettings.masterNotificationsEnabled = defaults.object(forKey: "masterNotificationsEnabled") as? Bool ?? loadedSettings.masterNotificationsEnabled
            loadedSettings.iMessageNotificationsEnabled = defaults.object(forKey: "iMessageNotificationsEnabled") as? Bool ?? loadedSettings.iMessageNotificationsEnabled
            loadedSettings.airDropNotificationsEnabled = defaults.object(forKey: "airDropNotificationsEnabled") as? Bool ?? loadedSettings.airDropNotificationsEnabled
            loadedSettings.faceTimeNotificationsEnabled = defaults.object(forKey: "faceTimeNotificationsEnabled") as? Bool ?? loadedSettings.faceTimeNotificationsEnabled
            loadedSettings.systemNotificationsEnabled = defaults.object(forKey: "systemNotificationsEnabled") as? Bool ?? loadedSettings.systemNotificationsEnabled
            loadedSettings.appNotificationStates = decode([String: Bool].self, forKey: "appNotificationStates") ?? loadedSettings.appNotificationStates

            loadedSettings.onlyShowVerificationCodeNotifications = defaults.object(forKey: "onlyShowVerificationCodeNotifications") as? Bool ?? loadedSettings.onlyShowVerificationCodeNotifications
            loadedSettings.showCopyButtonForVerificationCodes = defaults.object(forKey: "showCopyButtonForVerificationCodes") as? Bool ?? loadedSettings.showCopyButtonForVerificationCodes

            loadedSettings.neardropEnabled = defaults.object(forKey: "neardropEnabled") as? Bool ?? loadedSettings.neardropEnabled
            loadedSettings.neardropDeviceDisplayName = defaults.string(forKey: "neardropDeviceDisplayName") ?? loadedSettings.neardropDeviceDisplayName
            loadedSettings.neardropDownloadLocationPath = defaults.string(forKey: "neardropDownloadLocationPath") ?? loadedSettings.neardropDownloadLocationPath
            loadedSettings.neardropOpenOnClick = defaults.object(forKey: "neardropOpenOnClick") as? Bool ?? loadedSettings.neardropOpenOnClick

            loadedSettings.clickToOpenFileShelf = defaults.object(forKey: "clickToOpenFileShelf") as? Bool ?? loadedSettings.clickToOpenFileShelf
            loadedSettings.hoverToOpenFileShelf = defaults.object(forKey: "hoverToOpenFileShelf") as? Bool ?? loadedSettings.hoverToOpenFileShelf

            loadedSettings.launchpadLayout = decode([[LaunchpadPageItem]].self, forKey: "launchpadLayout") ?? loadedSettings.launchpadLayout

            loadedSettings.weatherUseCelsius = defaults.object(forKey: "weatherUseCelsius") as? Bool ?? loadedSettings.weatherUseCelsius
            loadedSettings.weatherOpenOnClick = defaults.object(forKey: "weatherOpenOnClick") as? Bool ?? loadedSettings.weatherOpenOnClick

            loadedSettings.calendarShowAllDayEvents = defaults.object(forKey: "calendarShowAllDayEvents") as? Bool ?? loadedSettings.calendarShowAllDayEvents
            if let day = defaults.string(forKey: "calendarStartOfWeek"), let startDay = Day(rawValue: day) { loadedSettings.calendarStartOfWeek = startDay }
            loadedSettings.calendarOpenOnClick = defaults.object(forKey: "calendarOpenOnClick") as? Bool ?? loadedSettings.calendarOpenOnClick

            loadedSettings.eyeBreakWorkInterval = defaults.object(forKey: "eyeBreakWorkInterval") as? Double ?? loadedSettings.eyeBreakWorkInterval
            loadedSettings.eyeBreakBreakDuration = defaults.object(forKey: "eyeBreakBreakDuration") as? Double ?? loadedSettings.eyeBreakBreakDuration
            loadedSettings.eyeBreakSoundAlerts = defaults.object(forKey: "eyeBreakSoundAlerts") as? Bool ?? loadedSettings.eyeBreakSoundAlerts
            loadedSettings.showEyeBreakGraph = defaults.object(forKey: "showEyeBreakGraph") as? Bool ?? loadedSettings.showEyeBreakGraph

            loadedSettings.geminiApiKey = defaults.string(forKey: "geminiApiKey") ?? ""

            loadedSettings.clickToShowTimerView = defaults.object(forKey: "clickToShowTimerView") as? Bool ?? loadedSettings.clickToShowTimerView

            DispatchQueue.main.async {
                self.settings = loadedSettings
            }
        }
    }

    private func saveSettings(settings: Settings, from oldValue: Settings) {
        settingsAccessQueue.async {
            if settings.useCustomNotchConfiguration != oldValue.useCustomNotchConfiguration { self.defaults.set(settings.useCustomNotchConfiguration, forKey: "useCustomNotchConfiguration") }
            if settings.customNotchConfiguration != oldValue.customNotchConfiguration { self.encode(settings.customNotchConfiguration, forKey: "customNotchConfiguration") }
            if settings.lockScreenShowInfoWidget != oldValue.lockScreenShowInfoWidget { self.defaults.set(settings.lockScreenShowInfoWidget, forKey: "lockScreenShowInfoWidget") }
            if settings.lockScreenWidgets != oldValue.lockScreenWidgets {
                let rawValues = settings.lockScreenWidgets.map { $0.rawValue }
                self.defaults.set(rawValues, forKey: "lockScreenWidgets")
            }
            if settings.lockScreenHideInactiveInfoWidgets != oldValue.lockScreenHideInactiveInfoWidgets { self.defaults.set(settings.lockScreenHideInactiveInfoWidgets, forKey: "lockScreenHideInactiveInfoWidgets") }

            if settings.lockScreenShowMainWidget != oldValue.lockScreenShowMainWidget { self.defaults.set(settings.lockScreenShowMainWidget, forKey: "lockScreenShowMainWidget") }
            if settings.lockScreenMainWidgets != oldValue.lockScreenMainWidgets {
                let rawValues = settings.lockScreenMainWidgets.map { $0.rawValue }
                self.defaults.set(rawValues, forKey: "lockScreenMainWidgets")
                if self.defaults.object(forKey: "lockScreenMainWidget") != nil {
                    self.defaults.removeObject(forKey: "lockScreenMainWidget")
                }
            }

            if settings.lockScreenShowMiniWidgets != oldValue.lockScreenShowMiniWidgets { self.defaults.set(settings.lockScreenShowMiniWidgets, forKey: "lockScreenShowMiniWidgets") }
            if settings.lockScreenMiniWidgets != oldValue.lockScreenMiniWidgets {
                let rawValues = settings.lockScreenMiniWidgets.map { $0.rawValue }
                self.defaults.set(rawValues, forKey: "lockScreenMiniWidgets")
            }

            if settings.lockScreenWeatherInfo != oldValue.lockScreenWeatherInfo {
                let rawValues = settings.lockScreenWeatherInfo.map { $0.rawValue }
                self.defaults.set(rawValues, forKey: "lockScreenWeatherInfo")
            }

            if settings.lockScreenBatteryInfo != oldValue.lockScreenBatteryInfo {
                let rawValues = settings.lockScreenBatteryInfo.map { $0.rawValue }
                self.defaults.set(rawValues, forKey: "lockScreenBatteryInfo")
            }

            if settings.lockScreenShowNotch != oldValue.lockScreenShowNotch { self.defaults.set(settings.lockScreenShowNotch, forKey: "lockScreenShowNotch") }
            if settings.lockScreenLiveActivityEnabled != oldValue.lockScreenLiveActivityEnabled { self.defaults.set(settings.lockScreenLiveActivityEnabled, forKey: "lockScreenLiveActivityEnabled") }
            if settings.lockScreenLiquidGlassLook != oldValue.lockScreenLiquidGlassLook { self.defaults.set(settings.lockScreenLiquidGlassLook, forKey: "lockScreenLiquidGlassLook") }

            if settings.notchWidgetAppearance != oldValue.notchWidgetAppearance { self.encode(settings.notchWidgetAppearance, forKey: "notchWidgetAppearance") }
            if settings.notchLiveActivityAppearance != oldValue.notchLiveActivityAppearance { self.encode(settings.notchLiveActivityAppearance, forKey: "notchLiveActivityAppearance") }

            if settings.launchAtLogin != oldValue.launchAtLogin { self.defaults.set(settings.launchAtLogin, forKey: "launchAtLogin") }
            if settings.appLanguage != oldValue.appLanguage { self.defaults.set(settings.appLanguage, forKey: "appLanguage") }
            if settings.hapticFeedbackEnabled != oldValue.hapticFeedbackEnabled { self.defaults.set(settings.hapticFeedbackEnabled, forKey: "hapticFeedbackEnabled") }
            if settings.hideFromScreenSharing != oldValue.hideFromScreenSharing { self.defaults.set(settings.hideFromScreenSharing, forKey: "hideFromScreenSharing") }
            if settings.notchDisplayTarget != oldValue.notchDisplayTarget { self.defaults.set(settings.notchDisplayTarget.rawValue, forKey: "notchDisplayTarget") }

            if settings.expandOnHover != oldValue.expandOnHover { self.defaults.set(settings.expandOnHover, forKey: "expandOnHover") }
            if settings.launchpadEnabled != oldValue.launchpadEnabled { self.defaults.set(settings.launchpadEnabled, forKey: "launchpadEnabled") }
            if settings.caffeinateEnabled != oldValue.caffeinateEnabled { self.defaults.set(settings.caffeinateEnabled, forKey: "caffeinateEnabled") }
            if settings.fileShelfIconEnabled != oldValue.fileShelfIconEnabled { self.defaults.set(settings.fileShelfIconEnabled, forKey: "fileShelfIconEnabled") }
            if settings.batteryEstimatorEnabled != oldValue.batteryEstimatorEnabled { self.defaults.set(settings.batteryEstimatorEnabled, forKey: "batteryEstimatorEnabled") }
            if settings.geminiEnabled != oldValue.geminiEnabled { self.defaults.set(settings.geminiEnabled, forKey: "geminiEnabled") }
            if settings.pinEnabled != oldValue.pinEnabled { self.defaults.set(settings.pinEnabled, forKey: "pinEnabled") }
            if settings.hideNotchWhenInactive != oldValue.hideNotchWhenInactive { self.defaults.set(settings.hideNotchWhenInactive, forKey: "hideNotchWhenInactive") }
            if settings.notchButtonOrder != oldValue.notchButtonOrder { self.encode(settings.notchButtonOrder, forKey: "notchButtonOrder") }

            if settings.showDividersBetweenWidgets != oldValue.showDividersBetweenWidgets { self.defaults.set(settings.showDividersBetweenWidgets, forKey: "showDividersBetweenWidgets") }
            if settings.widgetOrder != oldValue.widgetOrder { self.encode(settings.widgetOrder, forKey: "widgetOrder") }
            if settings.musicWidgetEnabled != oldValue.musicWidgetEnabled { self.defaults.set(settings.musicWidgetEnabled, forKey: "musicWidgetEnabled") }
            if settings.weatherWidgetEnabled != oldValue.weatherWidgetEnabled { self.defaults.set(settings.weatherWidgetEnabled, forKey: "weatherWidgetEnabled") }
            if settings.calendarWidgetEnabled != oldValue.calendarWidgetEnabled { self.defaults.set(settings.calendarWidgetEnabled, forKey: "calendarWidgetEnabled") }
            if settings.shortcutsWidgetEnabled != oldValue.shortcutsWidgetEnabled { self.defaults.set(settings.shortcutsWidgetEnabled, forKey: "shortcutsWidgetEnabled") }
            if settings.timerWidgetEnabled != oldValue.timerWidgetEnabled { self.defaults.set(settings.timerWidgetEnabled, forKey: "timerWidgetEnabled") }
            if settings.selectedShortcuts != oldValue.selectedShortcuts { self.encode(settings.selectedShortcuts, forKey: "selectedShortcuts") }

            if settings.rememberLastMenu != oldValue.rememberLastMenu { self.defaults.set(settings.rememberLastMenu, forKey: "rememberLastMenu") }
            if settings.lastNotchNavigationStack != oldValue.lastNotchNavigationStack { self.encode(settings.lastNotchNavigationStack, forKey: "lastNotchNavigationStack") }

            if settings.liveActivityOrder != oldValue.liveActivityOrder { self.encode(settings.liveActivityOrder, forKey: "liveActivityOrder") }
            if settings.musicLiveActivityEnabled != oldValue.musicLiveActivityEnabled { self.defaults.set(settings.musicLiveActivityEnabled, forKey: "musicLiveActivityEnabled") }
            if settings.weatherLiveActivityEnabled != oldValue.weatherLiveActivityEnabled { self.defaults.set(settings.weatherLiveActivityEnabled, forKey: "weatherLiveActivityEnabled") }
            if settings.calendarLiveActivityEnabled != oldValue.calendarLiveActivityEnabled { self.defaults.set(settings.calendarLiveActivityEnabled, forKey: "calendarLiveActivityEnabled") }
            if settings.remindersLiveActivityEnabled != oldValue.remindersLiveActivityEnabled { self.defaults.set(settings.remindersLiveActivityEnabled, forKey: "remindersLiveActivityEnabled") }
            if settings.timersLiveActivityEnabled != oldValue.timersLiveActivityEnabled { self.defaults.set(settings.timersLiveActivityEnabled, forKey: "timersLiveActivityEnabled") }
            if settings.batteryLiveActivityEnabled != oldValue.batteryLiveActivityEnabled { self.defaults.set(settings.batteryLiveActivityEnabled, forKey: "batteryLiveActivityEnabled") }
            if settings.eyeBreakLiveActivityEnabled != oldValue.eyeBreakLiveActivityEnabled { self.defaults.set(settings.eyeBreakLiveActivityEnabled, forKey: "eyeBreakLiveActivityEnabled") }
            if settings.desktopLiveActivityEnabled != oldValue.desktopLiveActivityEnabled { self.defaults.set(settings.desktopLiveActivityEnabled, forKey: "desktopLiveActivityEnabled") }
            if settings.focusLiveActivityEnabled != oldValue.focusLiveActivityEnabled { self.defaults.set(settings.focusLiveActivityEnabled, forKey: "focusLiveActivityEnabled") }
            if settings.fileShelfLiveActivityEnabled != oldValue.fileShelfLiveActivityEnabled { self.defaults.set(settings.fileShelfLiveActivityEnabled, forKey: "fileShelfLiveActivityEnabled") }
            if settings.fileProgressLiveActivityEnabled != oldValue.fileProgressLiveActivityEnabled { self.defaults.set(settings.fileProgressLiveActivityEnabled, forKey: "fileProgressLiveActivityEnabled") }
            if settings.swipeToDismissLiveActivity != oldValue.swipeToDismissLiveActivity { self.defaults.set(settings.swipeToDismissLiveActivity, forKey: "swipeToDismissLiveActivity") }
            if settings.hideLiveActivityInFullScreen != oldValue.hideLiveActivityInFullScreen { self.defaults.set(settings.hideLiveActivityInFullScreen, forKey: "hideLiveActivityInFullScreen") }
            if settings.hideActivitiesInFullScreen != oldValue.hideActivitiesInFullScreen { self.encode(settings.hideActivitiesInFullScreen, forKey: "hideActivitiesInFullScreen") }
            if settings.showPersistentBatteryLiveActivity != oldValue.showPersistentBatteryLiveActivity { self.defaults.set(settings.showPersistentBatteryLiveActivity, forKey: "showPersistentBatteryLiveActivity") }
            if settings.showPersistentWeatherLiveActivity != oldValue.showPersistentWeatherLiveActivity { self.defaults.set(settings.showPersistentWeatherLiveActivity, forKey: "showPersistentWeatherLiveActivity") }
            if settings.weatherLiveActivityInterval != oldValue.weatherLiveActivityInterval { self.defaults.set(settings.weatherLiveActivityInterval, forKey: "weatherLiveActivityInterval") }

            if settings.focusDisplayMode != oldValue.focusDisplayMode { self.defaults.set(settings.focusDisplayMode.rawValue, forKey: "focusDisplayMode") }

            if settings.mediaSource != oldValue.mediaSource { self.defaults.set(settings.mediaSource.rawValue, forKey: "mediaSource") }
            if settings.prioritizeMediaSource != oldValue.prioritizeMediaSource { self.defaults.set(settings.prioritizeMediaSource, forKey: "prioritizeMediaSource") }
            if settings.hideLiveActivityWhenSourceActive != oldValue.hideLiveActivityWhenSourceActive { self.defaults.set(settings.hideLiveActivityWhenSourceActive, forKey: "hideLiveActivityWhenSourceActive") }
            if settings.enableQuickPeekOnHover != oldValue.enableQuickPeekOnHover { self.defaults.set(settings.enableQuickPeekOnHover, forKey: "enableQuickPeekOnHover") }
            if settings.showQuickPeekOnTrackChange != oldValue.showQuickPeekOnTrackChange { self.defaults.set(settings.showQuickPeekOnTrackChange, forKey: "showQuickPeekOnTrackChange") }
            if settings.swipeToSkipMusic != oldValue.swipeToSkipMusic { self.defaults.set(settings.swipeToSkipMusic, forKey: "swipeToSkipMusic") }
            if settings.swipeToRewindMusic != oldValue.swipeToRewindMusic { self.defaults.set(settings.swipeToRewindMusic, forKey: "swipeToRewindMusic") }
            if settings.invertMusicGestures != oldValue.invertMusicGestures { self.defaults.set(settings.invertMusicGestures, forKey: "invertMusicGestures") }
            if settings.twoFingerTapToPauseMusic != oldValue.twoFingerTapToPauseMusic { self.defaults.set(settings.twoFingerTapToPauseMusic, forKey: "twoFingerTapToPauseMusic") }
            if settings.waveformUseGradient != oldValue.waveformUseGradient { self.defaults.set(settings.waveformUseGradient, forKey: "waveformUseGradient") }
            if settings.useStaticWaveform != oldValue.useStaticWaveform { self.defaults.set(settings.useStaticWaveform, forKey: "useStaticWaveform") }
            if settings.waveformBarCount != oldValue.waveformBarCount { self.defaults.set(settings.waveformBarCount, forKey: "waveformBarCount") }
            if settings.waveformBarThickness != oldValue.waveformBarThickness { self.defaults.set(settings.waveformBarThickness, forKey: "waveformBarThickness") }
            if settings.musicWaveformIsVolumeSensitive != oldValue.musicWaveformIsVolumeSensitive { self.defaults.set(settings.musicWaveformIsVolumeSensitive, forKey: "musicWaveformIsVolumeSensitive") }
            if settings.spotifyClientId != oldValue.spotifyClientId { self.defaults.set(settings.spotifyClientId, forKey: "spotifyClientId") }
            if settings.spotifyClientSecret != oldValue.spotifyClientSecret { self.defaults.set(settings.spotifyClientSecret, forKey: "spotifyClientSecret") }
            if settings.skipSpotifyAd != oldValue.skipSpotifyAd { self.defaults.set(settings.skipSpotifyAd, forKey: "skipSpotifyAd") }
            if settings.defaultMusicPlayer != oldValue.defaultMusicPlayer { self.defaults.set(settings.defaultMusicPlayer.rawValue, forKey: "defaultMusicPlayer") }
            if settings.showLyricsInLiveActivity != oldValue.showLyricsInLiveActivity { self.defaults.set(settings.showLyricsInLiveActivity, forKey: "showLyricsInLiveActivity") }
            if settings.enableLyricTranslation != oldValue.enableLyricTranslation { self.defaults.set(settings.enableLyricTranslation, forKey: "enableLyricTranslation") }
            if settings.lyricTranslationLanguage != oldValue.lyricTranslationLanguage { self.defaults.set(settings.lyricTranslationLanguage, forKey: "lyricTranslationLanguage") }
            if settings.musicOpenOnClick != oldValue.musicOpenOnClick { self.defaults.set(settings.musicOpenOnClick, forKey: "musicOpenOnClick") }
            if settings.musicAppStates != oldValue.musicAppStates { self.encode(settings.musicAppStates, forKey: "musicAppStates") }
            if settings.musicPlayerButtonOrder != oldValue.musicPlayerButtonOrder { self.encode(settings.musicPlayerButtonOrder, forKey: "musicPlayerButtonOrder") }
            if settings.musicLikeButtonEnabled != oldValue.musicLikeButtonEnabled { self.defaults.set(settings.musicLikeButtonEnabled, forKey: "musicLikeButtonEnabled") }
            if settings.musicShuffleButtonEnabled != oldValue.musicShuffleButtonEnabled { self.defaults.set(settings.musicShuffleButtonEnabled, forKey: "musicShuffleButtonEnabled") }
            if settings.musicRepeatButtonEnabled != oldValue.musicRepeatButtonEnabled { self.defaults.set(settings.musicRepeatButtonEnabled, forKey: "musicRepeatButtonEnabled") }
            if settings.musicPlaylistsButtonEnabled != oldValue.musicPlaylistsButtonEnabled { self.defaults.set(settings.musicPlaylistsButtonEnabled, forKey: "musicPlaylistsButtonEnabled") }
            if settings.musicDevicesButtonEnabled != oldValue.musicDevicesButtonEnabled { self.defaults.set(settings.musicDevicesButtonEnabled, forKey: "musicDevicesButtonEnabled") }
            if settings.showPopularityInMusicPlayer != oldValue.showPopularityInMusicPlayer { self.defaults.set(settings.showPopularityInMusicPlayer, forKey: "showPopularityInMusicPlayer") }
            if settings.hideMusicWidgetWhenNotPlaying != oldValue.hideMusicWidgetWhenNotPlaying { self.defaults.set(settings.hideMusicWidgetWhenNotPlaying, forKey: "hideMusicWidgetWhenNotPlaying") }
            if settings.preferAirPlayOverSpotify != oldValue.preferAirPlayOverSpotify { self.defaults.set(settings.preferAirPlayOverSpotify, forKey: "preferAirPlayOverSpotify") }

            if settings.hudDuration != oldValue.hudDuration { self.defaults.set(settings.hudDuration, forKey: "hudDuration") }
            if settings.volumesliderstep != oldValue.volumesliderstep { self.defaults.set(settings.volumesliderstep, forKey: "volumesliderstep") }
            if settings.brightnessliderstep != oldValue.brightnessliderstep { self.defaults.set(settings.brightnessliderstep, forKey: "brightnessliderstep") }
            if settings.hudShowPercentage != oldValue.hudShowPercentage { self.defaults.set(settings.hudShowPercentage, forKey: "hudShowPercentage") }
            if settings.hudVisualStyle != oldValue.hudVisualStyle { self.defaults.set(settings.hudVisualStyle.rawValue, forKey: "hudVisualStyle") }
            if settings.hudCustomColor != oldValue.hudCustomColor { self.encode(settings.hudCustomColor, forKey: "hudCustomColor") }
            if settings.enableVolumeHUD != oldValue.enableVolumeHUD { self.defaults.set(settings.enableVolumeHUD, forKey: "enableVolumeHUD") }
            if settings.volumeHUDStyle != oldValue.volumeHUDStyle { self.defaults.set(settings.volumeHUDStyle.rawValue, forKey: "volumeHUDStyle") }
            if settings.volumeHUDSoundEnabled != oldValue.volumeHUDSoundEnabled { self.defaults.set(settings.volumeHUDSoundEnabled, forKey: "volumeHUDSoundEnabled") }
            if settings.showSpotifyVolumeHUD != oldValue.showSpotifyVolumeHUD { self.defaults.set(settings.showSpotifyVolumeHUD, forKey: "showSpotifyVolumeHUD") }
            if settings.volumeHUDShowDeviceIcon != oldValue.volumeHUDShowDeviceIcon { self.defaults.set(settings.volumeHUDShowDeviceIcon, forKey: "volumeHUDShowDeviceIcon") }
            if settings.excludeBuiltInSpeakersFromHUDIcon != oldValue.excludeBuiltInSpeakersFromHUDIcon { self.defaults.set(settings.excludeBuiltInSpeakersFromHUDIcon, forKey: "excludeBuiltInSpeakersFromHUDIcon") }
            if settings.enableBrightnessHUD != oldValue.enableBrightnessHUD { self.defaults.set(settings.enableBrightnessHUD, forKey: "enableBrightnessHUD") }
            if settings.brightnessHUDStyle != oldValue.brightnessHUDStyle { self.defaults.set(settings.brightnessHUDStyle.rawValue, forKey: "brightnessHUDStyle") }

            if settings.snapZoneViewMode != oldValue.snapZoneViewMode { self.defaults.set(settings.snapZoneViewMode.rawValue, forKey: "snapZoneViewMode") }
            if settings.snapOnWindowDragEnabled != oldValue.snapOnWindowDragEnabled { self.defaults.set(settings.snapOnWindowDragEnabled, forKey: "snapOnWindowDragEnabled") }
            if settings.defaultSnapLayout != oldValue.defaultSnapLayout { self.encode(settings.defaultSnapLayout, forKey: "defaultSnapLayout") }
            if settings.appSpecificLayoutConfigurations != oldValue.appSpecificLayoutConfigurations { self.encode(settings.appSpecificLayoutConfigurations, forKey: "appSpecificLayoutConfigurations") }
            if settings.customSnapLayouts != oldValue.customSnapLayouts { self.encode(settings.customSnapLayouts, forKey: "customSnapLayouts") }
            if settings.snapZoneLayoutOptions != oldValue.snapZoneLayoutOptions { self.encode(settings.snapZoneLayoutOptions, forKey: "snapZoneLayoutOptions") }
            if settings.planes != oldValue.planes { self.encode(settings.planes, forKey: "planes") }

            if settings.batteryChargeLimit != oldValue.batteryChargeLimit { self.defaults.set(settings.batteryChargeLimit, forKey: "batteryChargeLimit") }
            if settings.lowBatteryNotificationPercentage != oldValue.lowBatteryNotificationPercentage { self.defaults.set(settings.lowBatteryNotificationPercentage, forKey: "lowBatteryNotificationPercentage") }
            if settings.lowBatteryNotificationSoundEnabled != oldValue.lowBatteryNotificationSoundEnabled { self.defaults.set(settings.lowBatteryNotificationSoundEnabled, forKey: "lowBatteryNotificationSoundEnabled") }
            if settings.batteryNotificationStyle != oldValue.batteryNotificationStyle { self.defaults.set(settings.batteryNotificationStyle.rawValue, forKey: "batteryNotificationStyle") }
            if settings.promptForLowPowerMode != oldValue.promptForLowPowerMode { self.defaults.set(settings.promptForLowPowerMode, forKey: "promptForLowPowerMode") }
            if settings.showEstimatedBatteryTime != oldValue.showEstimatedBatteryTime { self.defaults.set(settings.showEstimatedBatteryTime, forKey: "showEstimatedBatteryTime") }
            if settings.automaticDischargeEnabled != oldValue.automaticDischargeEnabled { self.defaults.set(settings.automaticDischargeEnabled, forKey: "automaticDischargeEnabled") }
            if settings.heatProtectionEnabled != oldValue.heatProtectionEnabled { self.defaults.set(settings.heatProtectionEnabled, forKey: "heatProtectionEnabled") }
            if settings.heatProtectionThreshold != oldValue.heatProtectionThreshold { self.defaults.set(settings.heatProtectionThreshold, forKey: "heatProtectionThreshold") }
            if settings.sailingModeEnabled != oldValue.sailingModeEnabled { self.defaults.set(settings.sailingModeEnabled, forKey: "sailingModeEnabled") }
            if settings.sailingModeLowerLimit != oldValue.sailingModeLowerLimit { self.defaults.set(settings.sailingModeLowerLimit, forKey: "sailingModeLowerLimit") }
            if settings.useHardwareBatteryPercentage != oldValue.useHardwareBatteryPercentage { self.defaults.set(settings.useHardwareBatteryPercentage, forKey: "useHardwareBatteryPercentage") }
            if settings.controlMagSafeLEDEnabled != oldValue.controlMagSafeLEDEnabled { self.defaults.set(settings.controlMagSafeLEDEnabled, forKey: "controlMagSafeLEDEnabled") }
            if settings.stopChargingWhenSleeping != oldValue.stopChargingWhenSleeping { self.defaults.set(settings.stopChargingWhenSleeping, forKey: "stopChargingWhenSleeping") }
            if settings.disableSleepUntilChargeLimit != oldValue.disableSleepUntilChargeLimit { self.defaults.set(settings.disableSleepUntilChargeLimit, forKey: "disableSleepUntilChargeLimit") }
            if settings.lowPowerMode != oldValue.lowPowerMode { self.defaults.set(settings.lowPowerMode.rawValue, forKey: "lowPowerMode") }
            if settings.scheduledTasks != oldValue.scheduledTasks { self.encode(settings.scheduledTasks, forKey: "scheduledTasks") }
            if settings.stopChargingWhenAppClosed != oldValue.stopChargingWhenAppClosed { self.defaults.set(settings.stopChargingWhenAppClosed, forKey: "stopChargingWhenAppClosed") }
            if settings.magSafeLEDBlinkOnDischarge != oldValue.magSafeLEDBlinkOnDischarge { self.defaults.set(settings.magSafeLEDBlinkOnDischarge, forKey: "magSafeLEDBlinkOnDischarge") }
            if settings.magSafeLEDSetting != oldValue.magSafeLEDSetting { self.defaults.set(settings.magSafeLEDSetting.rawValue, forKey: "magSafeLEDSetting") }
            if settings.preventSleepDuringCalibration != oldValue.preventSleepDuringCalibration { self.defaults.set(settings.preventSleepDuringCalibration, forKey: "preventSleepDuringCalibration") }
            if settings.preventSleepDuringDischarge != oldValue.preventSleepDuringDischarge { self.defaults.set(settings.preventSleepDuringDischarge, forKey: "preventSleepDuringDischarge") }
            if settings.enableBiweeklyCalibration != oldValue.enableBiweeklyCalibration { self.defaults.set(settings.enableBiweeklyCalibration, forKey: "enableBiweeklyCalibration") }
            if settings.magSafeGreenAtLimit != oldValue.magSafeGreenAtLimit { self.defaults.set(settings.magSafeGreenAtLimit, forKey: "magSafeGreenAtLimit") }

            if settings.bluetoothNotifyLowBattery != oldValue.bluetoothNotifyLowBattery { self.defaults.set(settings.bluetoothNotifyLowBattery, forKey: "bluetoothNotifyLowBattery") }
            if settings.bluetoothNotifySound != oldValue.bluetoothNotifySound { self.defaults.set(settings.bluetoothNotifySound, forKey: "bluetoothNotifySound") }
            if settings.showBluetoothDeviceName != oldValue.showBluetoothDeviceName { self.defaults.set(settings.showBluetoothDeviceName, forKey: "showBluetoothDeviceName") }

            if settings.bluetoothUnlockEnabled != oldValue.bluetoothUnlockEnabled { self.defaults.set(settings.bluetoothUnlockEnabled, forKey: "bluetoothUnlockEnabled") }
            if settings.bluetoothUnlockDeviceID != oldValue.bluetoothUnlockDeviceID { self.defaults.set(settings.bluetoothUnlockDeviceID, forKey: "bluetoothUnlockDeviceID") }
            if settings.bluetoothUnlockUnlockRSSI != oldValue.bluetoothUnlockUnlockRSSI { self.defaults.set(settings.bluetoothUnlockUnlockRSSI, forKey: "bluetoothUnlockUnlockRSSI") }
            if settings.bluetoothUnlockLockRSSI != oldValue.bluetoothUnlockLockRSSI { self.defaults.set(settings.bluetoothUnlockLockRSSI, forKey: "bluetoothUnlockLockRSSI") }
            if settings.bluetoothUnlockTimeout != oldValue.bluetoothUnlockTimeout { self.defaults.set(settings.bluetoothUnlockTimeout, forKey: "bluetoothUnlockTimeout") }
            if settings.bluetoothUnlockNoSignalTimeout != oldValue.bluetoothUnlockNoSignalTimeout { self.defaults.set(settings.bluetoothUnlockNoSignalTimeout, forKey: "bluetoothUnlockNoSignalTimeout") }
            if settings.bluetoothUnlockMinScanRSSI != oldValue.bluetoothUnlockMinScanRSSI { self.defaults.set(settings.bluetoothUnlockMinScanRSSI, forKey: "bluetoothUnlockMinScanRSSI") }
            if settings.bluetoothUnlockPassiveMode != oldValue.bluetoothUnlockPassiveMode { self.defaults.set(settings.bluetoothUnlockPassiveMode, forKey: "bluetoothUnlockPassiveMode") }
            if settings.faceIDUnlockEnabled != oldValue.faceIDUnlockEnabled { self.defaults.set(settings.faceIDUnlockEnabled, forKey: "faceIDUnlockEnabled") }
            if settings.hasRegisteredFaceID != oldValue.hasRegisteredFaceID { self.defaults.set(settings.hasRegisteredFaceID, forKey: "hasRegisteredFaceID") }
            if settings.bluetoothUnlockWakeOnProximity != oldValue.bluetoothUnlockWakeOnProximity { self.defaults.set(settings.bluetoothUnlockWakeOnProximity, forKey: "bluetoothUnlockWakeOnProximity") }
            if settings.bluetoothUnlockWakeWithoutUnlocking != oldValue.bluetoothUnlockWakeWithoutUnlocking { self.defaults.set(settings.bluetoothUnlockWakeWithoutUnlocking, forKey: "bluetoothUnlockWakeWithoutUnlocking") }
            if settings.bluetoothUnlockPauseMusicOnLock != oldValue.bluetoothUnlockPauseMusicOnLock { self.defaults.set(settings.bluetoothUnlockPauseMusicOnLock, forKey: "bluetoothUnlockPauseMusicOnLock") }
            if settings.bluetoothUnlockUseScreensaver != oldValue.bluetoothUnlockUseScreensaver { self.defaults.set(settings.bluetoothUnlockUseScreensaver, forKey: "bluetoothUnlockUseScreensaver") }
            if settings.bluetoothUnlockTurnOffScreenOnLock != oldValue.bluetoothUnlockTurnOffScreenOnLock { self.defaults.set(settings.bluetoothUnlockTurnOffScreenOnLock, forKey: "bluetoothUnlockTurnOffScreenOnLock") }

            if settings.masterNotificationsEnabled != oldValue.masterNotificationsEnabled { self.defaults.set(settings.masterNotificationsEnabled, forKey: "masterNotificationsEnabled") }
            if settings.iMessageNotificationsEnabled != oldValue.iMessageNotificationsEnabled { self.defaults.set(settings.iMessageNotificationsEnabled, forKey: "iMessageNotificationsEnabled") }
            if settings.airDropNotificationsEnabled != oldValue.airDropNotificationsEnabled { self.defaults.set(settings.airDropNotificationsEnabled, forKey: "airDropNotificationsEnabled") }
            if settings.faceTimeNotificationsEnabled != oldValue.faceTimeNotificationsEnabled { self.defaults.set(settings.faceTimeNotificationsEnabled, forKey: "faceTimeNotificationsEnabled") }
            if settings.systemNotificationsEnabled != oldValue.systemNotificationsEnabled { self.defaults.set(settings.systemNotificationsEnabled, forKey: "systemNotificationsEnabled") }
            if settings.appNotificationStates != oldValue.appNotificationStates { self.encode(settings.appNotificationStates, forKey: "appNotificationStates") }

            if settings.onlyShowVerificationCodeNotifications != oldValue.onlyShowVerificationCodeNotifications { self.defaults.set(settings.onlyShowVerificationCodeNotifications, forKey: "onlyShowVerificationCodeNotifications") }
            if settings.showCopyButtonForVerificationCodes != oldValue.showCopyButtonForVerificationCodes { self.defaults.set(settings.showCopyButtonForVerificationCodes, forKey: "showCopyButtonForVerificationCodes") }

            if settings.neardropEnabled != oldValue.neardropEnabled { self.defaults.set(settings.neardropEnabled, forKey: "neardropEnabled") }
            if settings.neardropDeviceDisplayName != oldValue.neardropDeviceDisplayName { self.defaults.set(settings.neardropDeviceDisplayName, forKey: "neardropDeviceDisplayName") }
            if settings.neardropDownloadLocationPath != oldValue.neardropDownloadLocationPath { self.defaults.set(settings.neardropDownloadLocationPath, forKey: "neardropDownloadLocationPath") }
            if settings.neardropOpenOnClick != oldValue.neardropOpenOnClick { self.defaults.set(settings.neardropOpenOnClick, forKey: "neardropOpenOnClick") }

            if settings.clickToOpenFileShelf != oldValue.clickToOpenFileShelf { self.defaults.set(settings.clickToOpenFileShelf, forKey: "clickToOpenFileShelf") }
            if settings.hoverToOpenFileShelf != oldValue.hoverToOpenFileShelf { self.defaults.set(settings.hoverToOpenFileShelf, forKey: "hoverToOpenFileShelf") }

            if settings.launchpadLayout != oldValue.launchpadLayout { self.encode(settings.launchpadLayout, forKey: "launchpadLayout") }

            if settings.weatherUseCelsius != oldValue.weatherUseCelsius { self.defaults.set(settings.weatherUseCelsius, forKey: "weatherUseCelsius") }
            if settings.weatherOpenOnClick != oldValue.weatherOpenOnClick { self.defaults.set(settings.weatherOpenOnClick, forKey: "weatherOpenOnClick") }

            if settings.calendarShowAllDayEvents != oldValue.calendarShowAllDayEvents { self.defaults.set(settings.calendarShowAllDayEvents, forKey: "calendarShowAllDayEvents") }
            if settings.calendarStartOfWeek != oldValue.calendarStartOfWeek { self.defaults.set(settings.calendarStartOfWeek.rawValue, forKey: "calendarStartOfWeek") }
            if settings.calendarOpenOnClick != oldValue.calendarOpenOnClick { self.defaults.set(settings.calendarOpenOnClick, forKey: "calendarOpenOnClick") }

            if settings.eyeBreakWorkInterval != oldValue.eyeBreakWorkInterval { self.defaults.set(settings.eyeBreakWorkInterval, forKey: "eyeBreakWorkInterval") }
            if settings.eyeBreakBreakDuration != oldValue.eyeBreakBreakDuration { self.defaults.set(settings.eyeBreakBreakDuration, forKey: "eyeBreakBreakDuration") }
            if settings.eyeBreakSoundAlerts != oldValue.eyeBreakSoundAlerts { self.defaults.set(settings.eyeBreakSoundAlerts, forKey: "eyeBreakSoundAlerts") }
            if settings.showEyeBreakGraph != oldValue.showEyeBreakGraph { self.defaults.set(settings.showEyeBreakGraph, forKey: "showEyeBreakGraph") }

            if settings.geminiApiKey != oldValue.geminiApiKey { self.defaults.set(settings.geminiApiKey, forKey: "geminiApiKey") }

            if settings.clickToShowTimerView != oldValue.clickToShowTimerView { self.defaults.set(settings.clickToShowTimerView, forKey: "clickToShowTimerView") }
        }
    }
}

// MARK: - Supporting Enums and Structs (Not part of the main class)

enum MagSafeLEDSetting: String, Codable, CaseIterable, Identifiable {
    case alwaysOn, off
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .alwaysOn: "Always On"
        case .off: "Always Off"
        }
    }
}

enum LowPowerMode: String, Codable, CaseIterable, Identifiable {
    case alwaysOn, onBattery, never
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .alwaysOn: "Always On"
        case .onBattery: "On Battery"
        case .never: "Never"
        }
    }
}

enum WidgetType: String, Codable, CaseIterable, Identifiable, Equatable {
    case weather, calendar, shortcuts, music
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.prefix(1).uppercased() + self.rawValue.dropFirst() }
}

enum LiveActivityType: String, Codable, CaseIterable, Identifiable, Equatable {
    case fileShelf, eyeBreak, focus, desktop, battery, timers, calendar, reminders, weather, music, fileProgress
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .music: "Music"; case .weather: "Weather"; case .calendar: "Calendar"; case .reminders: "Reminders"; case .timers: "Timers"; case .battery: "Battery"; case .eyeBreak: "Eye Break"; case .desktop: "Desktop"; case .focus: "Focus"; case .fileShelf: "File Shelf"; case .fileProgress: "File Progress";
        }
    }
}

enum BatteryNotificationStyle: String, CaseIterable, Identifiable, Decodable, Encodable {
    case `default`
    case compact
    case persistent

    var id: String { self.rawValue.capitalized }

    static var userSelectableCases: [BatteryNotificationStyle] {
        return [.default, .compact]
    }
}

enum NotificationSource: String, CaseIterable, Identifiable {
    case iMessage, faceTime, airDrop
    var id: String { rawValue }
    var displayName: String { switch self { case .iMessage: "iMessage"; case .faceTime: "FaceTime"; case .airDrop: "AirDrop" } }
    var systemImage: String { switch self { case .iMessage: "message.fill"; case .faceTime: "video.fill"; case .airDrop: "shareplay" } }
    var iconColor: Color { switch self { case .iMessage, .faceTime: .green; case .airDrop: .blue } }
}

enum GeneralSettingType: String, CaseIterable, Identifiable, Equatable {
    case expandOnHover
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .expandOnHover: "Expand on Hover";
        }
    }
    var systemImage: String {
        switch self {
        case .expandOnHover: "cursorarrow.motionlines";
        }
    }
    var iconColor: Color {
        switch self {
        case .expandOnHover: .cyan;
        }
    }
}

enum NotchButtonType: String, Codable, CaseIterable, Identifiable, Equatable {
    case settings, fileShelf, gemini, caffeine, spacer, multiAudio, battery, pin
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .settings: "Settings"; case .fileShelf: "File Shelf"; case .gemini: "Gemini";
        case .caffeine: "Caffeinate"; case .spacer: "Spacer"; case .multiAudio: "Multi-Audio";
        case .battery: "Battery"; case .pin: "Pin"
        }
    }

    var systemImage: String {
        switch self {
        case .settings: "gearshape"; case .fileShelf: "tray.full"; case .gemini: "sparkle";
        case .caffeine: "cup.and.saucer"; case .spacer: "space"; case .multiAudio: "hifispeaker.and.homepod.mini.fill";
        case .battery: "battery.100"; case .pin: "pin"
        }
    }
}

struct SystemApp: Identifiable, Equatable {
    let id: String, name: String, icon: NSImage, isBrowser: Bool, url: URL

}

enum Day: String, Codable, CaseIterable, Identifiable {
    case sunday, monday
    var id: String { self.rawValue.capitalized }
}

enum DefaultMusicPlayer: String, Codable, CaseIterable, Identifiable {
    case appleMusic, spotify
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"; case .spotify: "Spotify"
        }
    }
}

enum HUDStyle: String, Codable, CaseIterable, Identifiable {
    case `default`, thin
    var id: String { self.rawValue.capitalized }
}

struct LaunchpadItem: Codable, Equatable, Identifiable, Hashable {
    var id: String { appBundleID }
    let appBundleID: String
}

struct LaunchpadFolder: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var items: [LaunchpadItem]
}

enum LaunchpadPageItem: Codable, Equatable, Identifiable, Hashable {
    case app(LaunchpadItem)
    case folder(LaunchpadFolder)

    var id: String {
        switch self {
        case .app(let item): return item.id
        case .folder(let folder): return folder.id.uuidString
        }
    }

    var appItem: LaunchpadItem? {
        if case .app(let item) = self { return item }
        return nil
    }
}

extension LaunchpadPageItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .launchpadItem)
    }
}

extension UTType {
    static let launchpadItem = UTType(exportedAs: "com.shariq.sapphire.launchpaditem")
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, widgets, liveActivities, lockScreen, bluetoothUnlock, shortcuts, snapZones, battery, bluetooth, hud, notifications, neardrop, fileShelf, music, weather, calendar, eyeBreak, gemini, about

    var id: String { self.rawValue }

    var requiredPermissions: [PermissionType] {
        switch self {
        case .hud: return [.accessibility]
        case .music: return [.accessibility]
        case .notifications: return [.notifications]
        case .weather: return [.location]
        case .calendar: return [.calendar, .reminders]
        case .bluetooth, .bluetoothUnlock: return [.bluetooth, .accessibility]
        case .liveActivities: return [.focusStatus]
        case .snapZones: return [.accessibility]
        default: return []
        }
    }

    var label: String {
        switch self {
        case .general: "General"; case .widgets: "Widgets"; case .liveActivities: "Live Activities"; case .lockScreen: "Lock Screen";  case .bluetoothUnlock: "Authentication"; case .shortcuts: "Shortcuts"; case .snapZones: "Snap Zones"; case .battery: "Battery"; case .bluetooth: "Bluetooth"; case .hud: "HUD"; case .notifications: "Notifications"; case .neardrop: "Nearby Share"; case .fileShelf: "File Shelf"; case .music: "Music"; case .weather: "Weather"; case .calendar: "Calendar"; case .eyeBreak: "Eye Break"; case .gemini: "Gemini"; case .about: "About"
        }
    }
    var systemImage: String {
        switch self {
        case .general: "gear"; case .widgets: "square.grid.2x2.fill"; case .liveActivities: "timer"; case .lockScreen: "lock.fill"; case .bluetoothUnlock: "lock.laptopcomputer"; case .shortcuts: "square.grid.3x1.below.line.grid.1x2"; case .snapZones: "uiwindow.split.2x1"; case .battery: "battery.100"; case .bluetooth: "macbook.and.ipad"; case .hud: "macwindow.on.rectangle"; case .notifications: "bell"; case .neardrop: "shareplay"; case .fileShelf: "tray.full.fill"; case .music: "music.note"; case .weather: "cloud.sun.fill"; case .calendar: "calendar"; case .eyeBreak: "eye.fill"; case .gemini: "sparkles"; case .about: "info.circle"
        }
    }
    var iconBackgroundColor: Color {
        switch self {
        case .general: .gray; case .widgets: .purple; case .liveActivities: .cyan; case .lockScreen: .red; case .bluetoothUnlock: .indigo; case .shortcuts: .orange; case .snapZones: .blue; case .battery: .green; case .bluetooth: .blue; case .hud: .indigo; case .notifications: .red; case .neardrop: .blue; case .fileShelf: .orange; case .music: .pink; case .weather: .blue; case .calendar: .red; case .eyeBreak: .teal; case .gemini: .purple; case .about: .blue
        }
    }
}

@MainActor
class SystemAppFetcher: ObservableObject {
    @Published private(set) var apps: [SystemApp] = []
    @Published private(set) var foundBundleIDs: Set<String> = []

    func fetchApps() {
        guard self.apps.isEmpty else { return }

        Task.detached(priority: .userInitiated) {
            var fetchedApps: [SystemApp] = []
            var seenBundleIDs = Set<String>()

            let fileManager = FileManager.default
            let searchPaths = [
                "/System/Applications",
                "/Applications"
            ] + NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true)

            for path in searchPaths.compactMap({ $0 }) {
                guard let enumerator = fileManager.enumerator(
                    at: URL(fileURLWithPath: path),
                    includingPropertiesForKeys: [.isApplicationKey, .nameKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: nil
                ) else { continue }

                for case let url as URL in enumerator {
                    if url.pathExtension == "app" {
                        guard let bundle = Bundle(url: url),
                              let bundleId = bundle.bundleIdentifier,
                              !seenBundleIDs.contains(bundleId) else { continue }

                        let name = fileManager.displayName(atPath: url.path)
                        let icon = NSWorkspace.shared.icon(forFile: url.path)

                        let isBrowser = await self.isBrowser(bundle: bundle)

                        let app = SystemApp(id: bundleId, name: name, icon: icon, isBrowser: isBrowser, url: url)

                        fetchedApps.append(app)
                        seenBundleIDs.insert(bundleId)
                    }
                }
            }

            let sortedApps = fetchedApps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            await MainActor.run {
                self.apps = sortedApps
                self.foundBundleIDs = seenBundleIDs
            }
        }
    }

    private func isBrowser(bundle: Bundle?) -> Bool {
        guard let bundle = bundle, let urlTypes = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else { return false }

        return urlTypes.contains { type in
            if let schemes = type["CFBundleURLSchemes"] as? [String] {
                return schemes.contains("http") || schemes.contains("https")
            }
            return false
        }
    }
}