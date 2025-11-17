//
//  SettingsModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-07
//

import SwiftUI
import UniformTypeIdentifiers

public struct StatThreshold: Codable, Equatable {
    var isEnabled: Bool = false
    var value: Int = 80
}

public enum StatType: String, Codable, CaseIterable, Identifiable {
    case cpu, ram, gpu, disk, systemPower, batteryPower

    public var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .cpu: return "CPU Usage"
        case .ram: return "RAM Usage"
        case .gpu: return "GPU Usage"
        case .disk: return "Disk Activity"
        case .systemPower: return "System Power"
        case .batteryPower: return "Battery Draw"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .ram: return "memorychip"
        case .gpu: return "tv"
        case .disk: return "internaldrive"
        case .systemPower: return "bolt.fill"
        case .batteryPower: return "battery.75"
        }
    }
}

// MARK: - Animation Configuration
enum AnimationProfile: String, Codable, CaseIterable, Identifiable {
    case snappy, bouncy, calm, custom
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .snappy: "Snappy"
        case .bouncy: "Bouncy"
        case .calm: "Calm"
        case .custom: "Custom"
        }
    }
}

enum WidgetSwitchEffect: String, Codable, CaseIterable, Identifiable {
    case smooth, bouncy
    var id: String { self.rawValue }
    var displayName: String { self.rawValue.capitalized }
}

enum WidgetSwitchTransition: String, Codable, CaseIterable, Identifiable {
    case slide, fade, blurAndFade
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .slide: "Slide"
        case .fade: "Fade"
        case .blurAndFade: "Blur & Fade"
        }
    }
}

struct CustomizableAnimationConfiguration: Codable, Equatable {
    var expandResponse: Double = 0.45
    var expandDamping: Double = 0.68
    var swipeOpenResponse: Double = 0.5
    var swipeOpenDamping: Double = 0.85
    var collapseResponse: Double = 0.3
    var collapseDamping: Double = 0.98

    var hoverResponse: Double = 0.38
    var hoverDamping: Double = 0.96
    var autoExpandResponse: Double = 0.42
    var autoExpandDamping: Double = 0.92

    var contentTransitionResponse: Double = 0.35
    var contentTransitionDamping: Double = 0.9
    var activityToActivityResponse: Double = 0.4
    var activityToActivityDamping: Double = 0.98
    var activityMorphResponse: Double = 0.5
    var activityMorphDamping: Double = 0.88

    var bottomContentResponse: Double = 0.42
    var bottomContentDamping: Double = 0.999
    var heightIncreaseResponse: Double = 0.38
    var heightIncreaseDamping: Double = 0.995
    var heightDecreaseResponse: Double = 0.36
    var heightDecreaseDamping: Double = 0.999
    var largeMenuResponse: Double = 0.5
    var largeMenuDamping: Double = 0.97
}

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

// MARK: - Main Settings Struct
struct Settings: Codable, Equatable {
    var animationProfile: AnimationProfile = .snappy
    var customAnimationConfiguration: CustomizableAnimationConfiguration = .init()
    var widgetSwitchEffect: WidgetSwitchEffect = .smooth
    var widgetSwitchTransition: WidgetSwitchTransition = .slide
    
    var swipeToSwitchWidgets: Bool = true
    var enableWidgetSwitchFade: Bool = true
    var enableWidgetSwitchSlide: Bool = true
    var enableWidgetSwitchBounce: Bool = true
    var enableOpeningBounce: Bool = true

    var enableXDRBrightness: Bool = isDeviceSupported()
    var brightness: Float = 1.0
    var xdrBrightnessLevel: Float = 1.6
    var xdrBrightnessLock: Bool = false

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
    var expandOnHover: Bool = false
    var launchpadEnabled: Bool = false
    var caffeinateEnabled: Bool = true
    var fileShelfIconEnabled: Bool = true
    var batteryEstimatorEnabled: Bool = true
    var geminiEnabled: Bool = true
    var pinEnabled: Bool = true
    var hideNotchWhenInactive: Bool = false
    var notchButtonOrder: [NotchButtonType] = [.settings, .fileShelf, .gemini, .spacer, .battery, .multiAudio, .caffeine, .pin]
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

    var statsLiveActivityEnabled: Bool = false
    var selectedStats: [StatType] = [.cpu, .ram, .gpu, .disk]
    var selectedSensorKeys: [String] = []

    var statsLiveActivityThresholdEnabled: Bool = false
    var statThresholds: [StatType: StatThreshold] = [
        .cpu: StatThreshold(),
        .ram: StatThreshold(),
        .gpu: StatThreshold()
    ]

    var swipeToDismissLiveActivity: Bool = true
    var hideLiveActivityInFullScreen: Bool = false
    var hideActivitiesInFullScreen: [String: Bool] = [:]
    var showPersistentStatsLiveActivity: Bool = false
    var showPersistentBatteryLiveActivity: Bool = false
    var showPersistentWeatherLiveActivity: Bool = true
    var weatherLiveActivityInterval: Int = 10
    var focusDisplayMode: FocusDisplayMode = .full
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
    var snapZoneViewMode: SnapZoneViewMode = .multi
    var snapOnWindowDragEnabled: Bool = true
    var defaultSnapLayout: SnapLayout = LayoutTemplate.columns
    var appSpecificLayoutConfigurations: [String: AppSnapLayoutConfiguration] = [:]
    var customSnapLayouts: [SnapLayout] = []
    var snapZoneLayoutOptions: [UUID] = [LayoutTemplate.columns.id, LayoutTemplate.splitscreen.id, LayoutTemplate.focus.id]
    var planes: [Plane] = []
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
    var dischargeToLimitEnabled: Bool = false
    var oneTimeDischargeEnabled: Bool = false
    var oneTimeDischargeTarget: Int = 20
    var disableSleepUntilChargeLimit: Bool = false
    var lowPowerMode: LowPowerMode = .never
    var scheduledTasks: [ScheduledTask] = []
    var stopChargingWhenAppClosed: Bool = false
    var magSafeLEDBlinkOnDischarge: Bool = false
    var magSafeLEDSetting: MagSafeLEDSetting = .alwaysOn
    var preventSleepDuringCalibration: Bool = false
    var preventSleepDuringDischarge: Bool = true
    var enableBiweeklyCalibration: Bool = false
    var magSafeGreenAtLimit: Bool = true
    var bluetoothNotifyLowBattery: Bool = true
    var bluetoothNotifySound: Bool = true
    var showBluetoothDeviceName: Bool = false
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
    var masterNotificationsEnabled: Bool = true
    var iMessageNotificationsEnabled: Bool = true
    var airDropNotificationsEnabled: Bool = true
    var faceTimeNotificationsEnabled: Bool = true
    var systemNotificationsEnabled: Bool = true
    var appNotificationStates: [String: Bool] = [:]
    var onlyShowVerificationCodeNotifications: Bool = true
    var showCopyButtonForVerificationCodes: Bool = true
    var neardropEnabled: Bool = true
    var neardropDeviceDisplayName: String = Host.current().localizedName ?? "My Mac"
    var neardropDownloadLocationPath: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path
    var neardropOpenOnClick: Bool = true
    var clickToOpenFileShelf: Bool = true
    var hoverToOpenFileShelf: Bool = true
    var launchpadLayout: [[LaunchpadPageItem]] = []
    var weatherUseCelsius: Bool = false
    var weatherOpenOnClick: Bool = false
    var calendarShowAllDayEvents: Bool = true
    var calendarStartOfWeek: Day = .sunday
    var calendarOpenOnClick: Bool = true
    var eyeBreakWorkInterval: Double = 20
    var eyeBreakBreakDuration: Double = 20
    var eyeBreakSoundAlerts: Bool = true
    var showEyeBreakGraph: Bool = true
    var geminiApiKey: String = ""
    var clickToShowTimerView: Bool = true
    var sleepInClamshell: Bool = true

    var menuBarEnabled: Bool = false
    var showOnHover: Bool = true
    var showOnHoverDelay: TimeInterval = 0.2
    var showOnClick: Bool = true
    var showOnScroll: Bool = true
    var autoRehide: Bool = true
    var rehideStrategy: String = "smart"
    var tempShowInterval: TimeInterval = 5.0
    var hideMenuBarIcon: Bool = false
    var showSectionDividers: Bool = true
    var enableAlwaysHiddenSection: Bool = true
    var controlItemIconStyle: ControlItemIconStyle = .chevron

    var menuBarTintStyle: String = "none"
    var menuBarSolidColor: CodableColor = CodableColor(color: .blue)
    var menuBarGradientColors: [CodableColor] = [
        CodableColor(color: .blue, location: 0.0),
        CodableColor(color: .purple, location: 1.0)
    ]
    var menuBarGradientAngle: Double = 90.0
    var menuBarOpacity: Double = 1.0
    var menuBarBlur: Bool = false
    var menuBarLiquidGlass: Bool = false

    var menuBarBorderWidth: CGFloat = 0.0
    var menuBarBorderColor: CodableColor = CodableColor(color: .black)
    var menuBarShadowEnabled: Bool = false

    var menuBarShapeStyle: String = "none"
    var menuBarCornerRadius: CGFloat = 16.0

    var roundedCornersTop: Bool = false
    var roundedCornersBelowMenu: Bool = false
    var roundedCornersBottom: Bool = false
    var screenCornerRadius: CGFloat = 16.0
    var menuBarVerticalPadding: CGFloat = 0.0
    var menuBarSpacing: Int = 1
    var menuBarSelectionPadding: Int = 1

}

enum ControlItemIconStyle: String, Codable, CaseIterable, Identifiable {
    case chevron = "chevron"
    case arrow = "arrow"
    case dot = "dot"
    case line = "line"
    case bracket = "bracket"
    case circle = "circle"
    case triangle = "triangle"
    case diamond = "diamond"
    case squareFilled = "squareFilled"
    case ellipsis = "ellipsis"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chevron: return "Chevron"
        case .arrow: return "Arrow"
        case .dot: return "Dot"
        case .line: return "Line"
        case .bracket: return "Bracket"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .diamond: return "Diamond"
        case .squareFilled: return "Square"
        case .ellipsis: return "ellipsis"
        }
    }

    func symbolName(isHidden: Bool) -> String {
        switch self {
        case .chevron:
            return isHidden ? "chevron.compact.right" : "chevron.compact.left"

        case .arrow:
            return isHidden ? "arrow.right" : "arrow.left"

        case .dot:
            return isHidden ? "circle" : "circle.fill"

        case .line:
            return isHidden ? "line.diagonal" : "line.diagonal.arrow"

        case .bracket:
            return "curlybraces"

        case .circle:
            return isHidden ? "circle" : "circle.fill"

        case .triangle:
            return isHidden ? "arrowtriangle.right" : "arrowtriangle.right.fill"

        case .diamond:
            return isHidden ? "diamond" : "diamond.fill"

        case .squareFilled:
            return isHidden ? "square" : "square.fill"

        case .ellipsis:
            return "ellipsis"
        }
    }

    var previewSymbol: String {
        return symbolName(isHidden: false)
    }
}
// MARK: - SettingsModel Class
class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    @Published var settings: Settings = Settings() {
        didSet {
            saveSettings()
        }
    }

    private let defaults = UserDefaults.standard
    private let settingsKey = "com.shariq.sapphire.appSettings"
    private let settingsAccessQueue = DispatchQueue(label: "com.shariq.sapphire.settings.sync.queue")

    private init() {
        loadSettings()
    }

    private func loadSettings() {
        settingsAccessQueue.sync {
            guard let data = defaults.data(forKey: settingsKey) else {
                return
            }

            do {
                let decoder = PropertyListDecoder()
                let loadedSettings = try decoder.decode(Settings.self, from: data)
                DispatchQueue.main.async {
                    self.settings = loadedSettings
                }
            } catch {
                print("Error: Failed to decode settings from UserDefaults. \(error)")
            }
        }
    }

    private func saveSettings() {
        settingsAccessQueue.async {
            do {
                let encoder = PropertyListEncoder()
                let data = try encoder.encode(self.settings)
                self.defaults.set(data, forKey: self.settingsKey)
            } catch {
                print("Error: Failed to encode settings for UserDefaults. \(error)")
            }
        }
    }
}

// MARK: - Supporting Enums and Structs

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
    case fileShelf, eyeBreak, focus, desktop, battery, timers, calendar, reminders, weather, music, fileProgress, stats
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .music: "Music"; case .weather: "Weather"; case .calendar: "Calendar"; case .reminders: "Reminders"; case .timers: "Timers"; case .battery: "Battery"; case .eyeBreak: "Eye Break"; case .desktop: "Desktop"; case .focus: "Focus"; case .fileShelf: "File Shelf"; case .fileProgress: "File Progress"; case .stats: "Stats"
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
    case expandOnHover, swipeToSwitchWidgets, enableOpeningBounce
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .expandOnHover: "Expand on Hover"
        case .swipeToSwitchWidgets: "Swipe to Switch Widgets"
        case .enableOpeningBounce: "Bounce when Opening Widgets"
        }
    }
    var systemImage: String {
        switch self {
        case .expandOnHover: "cursorarrow.motionlines"
        case .swipeToSwitchWidgets: "hand.draw.fill"
        case .enableOpeningBounce: "arrowshape.bounce.forward.fill"
        }
    }
    var iconColor: Color {
        switch self {
        case .expandOnHover: .cyan
        case .swipeToSwitchWidgets: .orange
        case .enableOpeningBounce: .green
        }
    }
}

enum NotchButtonType: String, Codable, CaseIterable, Identifiable, Equatable {
    case settings, fileShelf, gemini, caffeine, spacer, multiAudio, battery, pin
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .settings: "Settings"; case .fileShelf: "File Shelf"; case .gemini: "Gemini";
        case .caffeine: "Caffeinate"; case .spacer: "Spacer"; case .multiAudio: "Multi-Audio (Beta)";
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
    case general, widgets, liveActivities, appearance, lockScreen, bluetoothUnlock, shortcuts, snapZones, battery, bluetooth, hud, notifications, neardrop, fileShelf, music, weather, calendar, eyeBreak, gemini, about

    var id: String { self.rawValue }

    var requiredPermissions: [PermissionType] {
        switch self {
        case .hud, .music, .snapZones, .appearance: return [.accessibility]
        case .notifications: return [.notifications]
        case .weather: return [.location]
        case .calendar: return [.calendar, .reminders]
        case .bluetooth, .bluetoothUnlock: return [.bluetooth, .accessibility]
        case .liveActivities: return [.focusStatus]
        default: return []
        }
    }

    var label: String {
        switch self {
        case .general: "General"; case .widgets: "Widgets"; case .liveActivities: "Live Activities"; case .appearance: "Appearance"; case .lockScreen: "Lock Screen"; case .bluetoothUnlock: "Authentication"; case .shortcuts: "Shortcuts"; case .snapZones: "Snap Zones"; case .battery: "Battery"; case .bluetooth: "Bluetooth"; case .hud: "HUD"; case .notifications: "Notifications"; case .neardrop: "Nearby Share"; case .fileShelf: "File Shelf"; case .music: "Music"; case .weather: "Weather"; case .calendar: "Calendar"; case .eyeBreak: "Eye Break"; case .gemini: "Gemini"; case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"; case .widgets: "square.grid.2x2.fill"; case .liveActivities: "timer"; case .appearance: "paintpalette"; case .lockScreen: "lock.fill"; case .bluetoothUnlock: "lock.laptopcomputer"; case .shortcuts: "square.grid.3x1.below.line.grid.1x2"; case .snapZones: "uiwindow.split.2x1"; case .battery: "battery.100"; case .bluetooth: "macbook.and.ipad"; case .hud: "macwindow.on.rectangle"; case .notifications: "bell"; case .neardrop: "shareplay"; case .fileShelf: "tray.full.fill"; case .music: "music.note"; case .weather: "cloud.sun.fill"; case .calendar: "calendar"; case .eyeBreak: "eye.fill"; case .gemini: "sparkles"; case .about: "info.circle"
        }
    }

    var iconBackgroundColor: Color {
        switch self {
        case .general: .black; case .widgets: .gray; case .liveActivities: .cyan; case .appearance: .indigo; case .lockScreen: .red; case .bluetoothUnlock: .indigo; case .shortcuts: .orange; case .snapZones: .blue; case .battery: .green; case .bluetooth: .blue; case .hud: .indigo; case .notifications: .red; case .neardrop: .blue; case .fileShelf: .orange; case .music: .pink; case .weather: .blue; case .calendar: .red; case .eyeBreak: .teal; case .gemini: .purple; case .about: .blue
        }
    }
}

@MainActor
class SystemAppFetcher: ObservableObject {
    static let shared = SystemAppFetcher()

    @Published private(set) var apps: [SystemApp] = []
    @Published private(set) var foundBundleIDs: Set<String> = []

    private init() {}

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
