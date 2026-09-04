//
//  SettingsModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-22

import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let sapphireSettingsBackup = UTType(exportedAs: "com.cshariq.sapphire.settings-backup")
}

public struct StatThreshold: Codable, Equatable {
    var isEnabled: Bool = false
    var value: Int = 80
}

public struct NotchSizeOverride: Codable, Equatable {
    var width: CGFloat = 0
    var height: CGFloat = 0
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

enum ReleaseChannel: String, Codable, CaseIterable {
    case stable
    case beta
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
    case music, weather, calendar, battery, focus, timer, notes, clipboard
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        default: return self.rawValue.capitalized
        }
    }

    static var selectableCases: [LockScreenMainWidgetType] {
        return [.music, .weather, .calendar, .battery, .focus, .timer, .notes, .clipboard]
    }
}

enum LockScreenWidgetType: String, Codable, CaseIterable, Identifiable {
    case none, weather, calendar, music, focus, bluetooth, battery, caffeine, timer, clock, notes, clipboard, system
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .caffeine: return "Caffeine"
        case .timer: return "Timer"
        case .clock: return "Clock"
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        case .system: return "System"
        default: return self.rawValue.capitalized
        }
    }

    static var selectableCases: [LockScreenWidgetType] {
        return [.weather, .calendar, .music, .focus, .bluetooth, .battery, .caffeine, .timer, .clock, .notes, .clipboard, .system]
    }
}

enum LockScreenMiniWidgetType: String, Codable, CaseIterable, Identifiable {
    case none, weather, calendar, music, battery, focus, caffeine, timer, bluetooth, clipboard, notes, system
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .caffeine: return "Caffeine"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .system: return "System"
        default: return self.rawValue.capitalized
        }
    }

    static var selectableCases: [LockScreenMiniWidgetType] {
        return [.weather, .calendar, .music, .battery, .focus, .caffeine, .timer, .bluetooth, .clipboard, .notes, .system]
    }
}

enum BatteryInfoType: String, Codable, CaseIterable, Identifiable {
    case percentage, statusIcon, statusText, batteryIcon, estimatedTime
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .percentage: "Percentage"
        case .statusIcon: "Status Icon"
        case .statusText: "Status Text"
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
    case sportsPlayer
    case financePlayer
    case notesPlayer
    case clipboardPlayer
    case mirrorPlayer
    case nearDrop
    case fileShelf
    case multiAudio
    case weatherPlayer
    case calendarPlayer
    case timerDetailView
    case focusSessionDetailView

    func toNotchWidgetMode() -> NotchWidgetMode {
        switch self {
        case .defaultWidgets: return .defaultWidgets
        case .musicPlayer: return .musicPlayer
        case .musicQueueAndPlaylists: return .musicQueueAndPlaylists
        case .musicDevices: return .musicDevices
        case .sportsPlayer: return .sportsPlayer
        case .financePlayer: return .financePlayer
        case .notesPlayer: return .notesPlayer
        case .clipboardPlayer: return .clipboardPlayer
        case .mirrorPlayer: return .mirrorPlayer
        case .nearDrop: return .nearDrop
        case .fileShelf: return .fileShelf
        case .multiAudio: return .multiAudio
        case .weatherPlayer: return .weatherPlayer
        case .calendarPlayer: return .calendarPlayer
        case .timerDetailView: return .timerDetailView
        case .focusSessionDetailView: return .focusSessionDetailView
        }
    }
}

enum NotchAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case `default`
    case liquidGlass
    case blur
    case custom

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .liquidGlass: return "Liquid Glass"
        case .blur: return "Blur"
        case .custom: return "Custom"
        }
    }
}

struct NotchAppearanceSettings: Codable, Equatable {
    var mode: NotchAppearanceMode = .default

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
    var liquidGlassIntensity: Double = 0.65
    var bottomFadeEnabled: Bool = false

    var usesLiquidGlass: Bool { mode == .liquidGlass || liquidGlassLook }

    mutating func normalize() {
        opacity = min(max(opacity, 0), 1)
        liquidGlassIntensity = min(max(liquidGlassIntensity, 0), 1)
        if mode != .custom {
            liquidGlassLook = mode == .liquidGlass
        }
    }
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

    var preferredBundleID: String? {
        switch self {
        case .system: return nil
        case .spotify: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        }
    }
}

extension Settings {
    /// Widgets that are switched on, in the user's order. Shared by the Widgets
    /// pane rows and per-widget settings pages so they apply the same guards.
    var enabledWidgetTypes: [WidgetType] {
        widgetOrder.filter { widget in
            switch widget {
            case .weather: return weatherWidgetEnabled
            case .calendar: return calendarWidgetEnabled
            case .shortcuts: return shortcutsWidgetEnabled
            case .music: return musicWidgetEnabled
            case .sports: return sportsWidgetEnabled
            case .finance: return financeWidgetEnabled
            case .shopify: return shopifyWidgetEnabled
            case .notes: return notesWidgetEnabled
            case .clipboard: return clipboardWidgetEnabled
            case .mirror: return mirrorWidgetEnabled
            case .battery: return batteryWidgetEnabled
            case .focusSession: return focusSessionWidgetEnabled
            case .agent: return false
            }
        }
    }
}

extension Settings {
    func isMediaAppVisible(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return true }
        let normalized = bundleID.lowercased()

        if mediaSource != .system, prioritizeMediaSource,
           let preferred = mediaSource.preferredBundleID?.lowercased() {
            if preferred == "com.spotify.client" {
                return normalized.hasPrefix("com.spotify.client")
            }
            return normalized == preferred
        }

        if let explicit = mediaAppVisibility[bundleID] ?? mediaAppVisibility[normalized] {
            return explicit
        }
        return true
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

enum MusicLongPressAction: String, Codable, CaseIterable, Identifiable, Equatable {
    case none
    case seek
    case shuffle
    case repeatMode
    case like
    case playPause
    case nextTrack
    case previousTrack
    case openQueue
    case openDevices

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None (tap only)"
        case .seek: return "Seek"
        case .shuffle: return "Shuffle"
        case .repeatMode: return "Repeat"
        case .like: return "Like"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .openQueue: return "Open Queue"
        case .openDevices: return "Open Devices"
        }
    }

    static var skipButtonOptions: [MusicLongPressAction] {
        [.none, .seek, .shuffle, .repeatMode, .like, .playPause, .nextTrack, .previousTrack, .openQueue, .openDevices]
    }

    static var accessoryButtonOptions: [MusicLongPressAction] {
        [.none, .shuffle, .repeatMode, .like, .playPause, .nextTrack, .previousTrack, .openQueue, .openDevices]
    }
}

enum MusicLongPressTarget: String, CaseIterable, Identifiable {
    case previous
    case next
    case playPause
    case playlists
    case devices
    case like
    case shuffle
    case repeatMode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .previous: return "Previous"
        case .next: return "Next"
        case .playPause: return "Play / Pause"
        case .playlists: return "Queue"
        case .devices: return "Devices"
        case .like: return "Like"
        case .shuffle: return "Shuffle"
        case .repeatMode: return "Repeat"
        }
    }

    var isTransportControl: Bool {
        switch self {
        case .previous, .next, .playPause: return true
        default: return false
        }
    }

    var isSecondaryButton: Bool { !isTransportControl }

    var pickerOptions: [MusicLongPressAction] {
        switch self {
        case .previous, .next: return MusicLongPressAction.skipButtonOptions
        default: return MusicLongPressAction.accessoryButtonOptions
        }
    }

    func defaultAction(in settings: Settings) -> MusicLongPressAction {
        switch self {
        case .previous: return settings.musicLongPressPrevious
        case .next: return settings.musicLongPressNext
        case .playPause: return settings.musicLongPressPlayPause
        case .playlists: return settings.musicLongPressPlaylists
        case .devices: return settings.musicLongPressDevices
        case .like: return settings.musicLongPressLike
        case .shuffle: return settings.musicLongPressShuffle
        case .repeatMode: return settings.musicLongPressRepeat
        }
    }

    static func from(buttonType: MusicPlayerButtonType) -> MusicLongPressTarget? {
        switch buttonType {
        case .playlists: return .playlists
        case .devices: return .devices
        case .like: return .like
        case .shuffle: return .shuffle
        case .repeat: return .repeatMode
        }
    }
}

extension Settings {
    /// BETA: resolved accent color for UI, falling back to the app's default
    /// purple when the user hasn't chosen a custom one.
    var resolvedAccentColor: Color {
        customAccentColor?.color ?? .purple
    }
}

extension Settings {
    mutating func setLongPressAction(_ action: MusicLongPressAction, for target: MusicLongPressTarget) {
        switch target {
        case .previous: musicLongPressPrevious = action
        case .next: musicLongPressNext = action
        case .playPause: musicLongPressPlayPause = action
        case .playlists: musicLongPressPlaylists = action
        case .devices: musicLongPressDevices = action
        case .like: musicLongPressLike = action
        case .shuffle: musicLongPressShuffle = action
        case .repeatMode: musicLongPressRepeat = action
        }
    }

    func resolvedSkipHoldAction(for target: MusicLongPressTarget) -> MusicLongPressAction {
        if !musicLongPressActionsEnabled { return .seek }
        return target.defaultAction(in: self)
    }

    func resolvedAccessoryHoldAction(for target: MusicLongPressTarget) -> MusicLongPressAction? {
        guard musicLongPressActionsEnabled else { return nil }
        let configured = target.defaultAction(in: self)
        return configured == .none ? nil : configured
    }
}

// MARK: - Swipe Action Customization

enum NotesSwipeAction: String, Codable, CaseIterable, Identifiable {
    case toggleDone, copy, delete, none
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .toggleDone: return "Toggle Done"
        case .copy: return "Copy"
        case .delete: return "Delete"
        case .none: return "None"
        }
    }
}

enum ClipboardSwipeAction: String, Codable, CaseIterable, Identifiable {
    case share, copy, delete, none
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .share: return "Share"
        case .copy: return "Copy"
        case .delete: return "Delete"
        case .none: return "None"
        }
    }
}

enum FileDropSwipeAction: String, Codable, CaseIterable, Identifiable {
    case share, delete, none
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .share: return "Share"
        case .delete: return "Delete"
        case .none: return "None"
        }
    }
}

struct SwipeActionSettings: Codable, Equatable {
    var notesLeading: NotesSwipeAction = .toggleDone
    var notesTrailing: NotesSwipeAction = .delete
    var clipboardLeading: ClipboardSwipeAction = .share
    var clipboardTrailing: ClipboardSwipeAction = .delete
    var fileDropLeading: FileDropSwipeAction = .share
    var fileDropTrailing: FileDropSwipeAction = .delete
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
    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0

    var perDisplayNotchSize: [String: NotchSizeOverride] = [:]
    var perDisplayHideNotchWhenInactive: [String: Bool] = [:]

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
    var lockScreenCustomWallpaperEnabled: Bool = false
    var lockScreenCustomWallpaperPath: String? = nil
    var lockScreenKeepWallpaperAfterUnlock: Bool = false
    var desktopWallpaperEnabled: Bool = false
    var desktopWallpaperPath: String? = nil
    var lockScreenLiveActivityEnabled: Bool = true
    var lockScreenLiquidGlassLook: Bool = true
    var lockScreenLiquidGlassIntensity: Double = 0.75
    var lockScreenFrostedOverLiquidGlass: Bool = true
    var lockScreenShowInfoWidgetBackgrounds: Bool = true
    var lockScreenShowMusicWhenPaused: Bool = true
    var lockScreenWeatherInfo: [WeatherInfoType] = [.temperature]
    var lockScreenBatteryInfo: [BatteryInfoType] = [.batteryIcon, .percentage, .statusText]
    var notchWidgetAppearance: NotchAppearanceSettings = .init()
    var notchLiveActivityAppearance: NotchAppearanceSettings = .init()
    /// BETA: overrides the app's default purple/indigo accent with a user-chosen
    /// color, applied to interactive controls in Settings and widget content.
    /// nil means "use the default app color".
    var customAccentColor: CodableColor?
    /// BETA: user-defined reusable text snippets, quick-copyable from the Clipboard widget.
    var textSnippets: [TextSnippet] = []
    /// BETA: saved Focus Session presets (duration/intensity/blocklist) for quick-start.
    var focusSessionTemplates: [FocusSessionTemplate] = []
    /// BETA: locations the user has saved for quick weather switching.
    var savedWeatherLocations: [SavedWeatherLocation] = []
    /// BETA: which saved location's weather to show. nil means "use current device location" (unchanged default behavior).
    var selectedWeatherLocationID: UUID?
    var launchAtLogin: Bool = true
    var appLanguage: String = "en"
    var hapticFeedbackEnabled: Bool = true
    var googleAnalyticsEnabled: Bool = true
    var hideFromScreenSharing: Bool = false
    var notchDisplayTarget: NotchDisplayTarget = .macbookDisplay
    var expandOnHover: Bool = false
    var expandOnHoverDelay: TimeInterval = 0.0
    var capsLockHorizontalLockEnabled: Bool = false
    var capsLockHorizontalLockAppStates: [String: Bool] = [:]
    var launchpadEnabled: Bool = false
    var caffeinateEnabled: Bool = true
    var notesIconEnabled: Bool = true
    var clipboardIconEnabled: Bool = true
    var fileShelfIconEnabled: Bool = true
    var batteryEstimatorEnabled: Bool = true
    var showMultiAudioIcon: Bool = true
    var intelligenceEnabled: Bool = true
    var intelligenceBackend: LLMBackend = .auto
    var intelligenceGeminiSpeedMode: GeminiSpeedMode = .fast
    var intelligenceGeminiModel: GeminiModelOption = .flash35Lite
    var intelligenceOpenAIModel: OpenAIModelOption = .auto
    var intelligenceAnthropicModel: AnthropicModelOption = .auto
    var intelligenceOpenRouterModel: String = OpenRouterModelPreset.auto.rawValue
    var intelligenceXAIModel: XAIModelOption = .auto
    var intelligenceNVIDIAModel: NVIDIAModelOption = .auto
    var pinEnabled: Bool = true
    var hideNotchWhenInactive: Bool = false
    var swipeToHideNotch: Bool = false
    var preventNotchExpandWhenLocked: Bool = false
    var releaseChannel: ReleaseChannel = .stable
    var notchButtonOrder: [NotchButtonType] = [.settings, .fileShelf, .notes, .clipboard, .intelligence, .focusSession, .spacer, .battery, .multiAudio, .caffeine, .pin]
    var circleToSearchEnabled: Bool = true
    var circleToSearchShortcut: KeyboardShortcut = KeyboardShortcut(key: "C", modifiers: [.control, .shift])
    var circleToSearchBrowserEngine: CircleSearchBrowserEngine = .google

    // MARK: - Per-display resolution helpers

    func resolvedNotchWidth(forDisplayID displayID: String?) -> CGFloat {
        if let displayID,
           let override = perDisplayNotchSize[displayID],
           override.width > 0 {
            return override.width
        }
        return notchWidth
    }

    func resolvedNotchHeight(forDisplayID displayID: String?) -> CGFloat {
        if let displayID,
           let override = perDisplayNotchSize[displayID],
           override.height > 0 {
            return override.height
        }
        return notchHeight
    }

    func resolvedHideNotchWhenInactive(forDisplayID displayID: String?) -> Bool {
        if let displayID, let perDisplay = perDisplayHideNotchWhenInactive[displayID] {
            return perDisplay
        }
        return hideNotchWhenInactive
    }

    // MARK: - Legacy migration shims (read-only computed, not persisted)
    var geminiEnabled: Bool { intelligenceEnabled }
    var geminiApiKey: String {
        get { APIKeyManager.shared.geminiAPIKey }
        set { APIKeyManager.shared.geminiAPIKey = newValue }
    }
    var agentSEnabled: Bool { intelligenceEnabled }
    var agentSApiKey: String {
        get { APIKeyManager.shared.geminiAPIKey }
        set { APIKeyManager.shared.geminiAPIKey = newValue }
    }
    var agentSBackend: LLMBackend {
        get { intelligenceBackend }
        set { intelligenceBackend = newValue }
    }
    var rememberLastMenu: Bool = false
    var lastNotchNavigationStack: [RestorableNotchMenu]? = nil
    var showDividersBetweenWidgets: Bool = false
    var widgetOrder: [WidgetType] = [.music, .weather, .sports, .finance, .calendar, .focusSession, .battery, .shortcuts, .notes, .clipboard, .mirror]
    var musicWidgetEnabled: Bool = true
    var weatherWidgetEnabled: Bool = true
    var sportsWidgetEnabled: Bool = false
    var financeWidgetEnabled: Bool = false
    var shopifyWidgetEnabled: Bool = false
    var calendarWidgetEnabled: Bool = true
    var shortcutsWidgetEnabled: Bool = false
    var notesWidgetEnabled: Bool = false
    var clipboardWidgetEnabled: Bool = false
    var mirrorWidgetEnabled: Bool = false
    var mirrorOpenOnClick: Bool = true
    var mirrorFlipHorizontally: Bool = true
    var mirrorRotationMode: MirrorRotationMode = .auto
    var notesOpenOnClick: Bool = true
    var clipboardOpenOnClick: Bool = true
    var clipboardHistoryLimit: Int = 0
    var clipboardMonitoringEnabled: Bool = true
    var clipboardHistoryUnlimited: Bool = true
    var clipboardIgnoreConcealedItems: Bool = true
    var timerWidgetEnabled: Bool = true
    var batteryWidgetEnabled: Bool = true
    var focusSessionWidgetEnabled: Bool = true
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
    var focusSessionLiveActivityEnabled: Bool = true
    var focusSessionLiveActivityShowTime: Bool = true
    var focusNotificationsEnabled: Bool = true
    var focusSessionDuration: TimeInterval = 90 * 60
    var focusBreakEnabled: Bool = false
    var focusBreakDuration: TimeInterval = 0
    var focusBlockingEnabled: Bool = true
    var focusBlockingDuringBreaks: Bool = false
    var focusIntensity: FocusIntensity = .standard
    var focusStrictUnblockCooldown: TimeInterval = 15 * 60
    var focusBlockingMode: FocusBlockingMode = .blocklist
    var focusBlockedApps: Set<String> = []
    var focusAllowedApps: Set<String> = []

    var focusDimInactiveApps: Bool = true
    var focusDimInactiveOpacity: Double = 0.45
    var focusDisableDimInMissionControl: Bool = false
    var focusHideWallpaper: Bool = false
    var focusAppLimitEnabled: Bool = false
    var focusAppLimit: Int = 2
    var focusAmbientSoundEnabled: Bool = false
    var focusAmbientSoundType: FocusAmbientSoundType = .rain
    var focusAmbientSoundVolume: Double = 0.4
    var focusStartShortcutName: String = ""
    var focusEndShortcutName: String = ""
    var focusBlockedWebsites: Set<String> = []
    var focusStartShortcut: KeyboardShortcut = KeyboardShortcut(key: "F", modifiers: [.command, .shift])
    var clickToShowFocusSessionView: Bool = true
    var focusShortcutsEnabled: Bool = false
    var focusShortcutSyncMode: FocusShortcutSyncMode = .none
    var scheduledFocusSessions: [ScheduledFocusSession] = []

    var appLockEnabled: Bool = false
    var appLockProtectedApps: Set<String> = []
    var appLockFaceIDEnabled: Bool = true
    var appLockTouchIDEnabled: Bool = true
    var appLockPasswordFallbackEnabled: Bool = true
    var appLockPreventOpenUntilAuth: Bool = true
    var appLockCloseAppOnAuthFailures: Bool = true
    var appLockAutoLockIdleEnabled: Bool = false
    var appLockAutoLockIdleMinutes: Int = 3
    var appLockAutoCloseOnLock: Bool = false
    var appLockLockOnLeave: Bool = false
    var appLockLockOnSleep: Bool = true
    var appLockPanicKeyEnabled: Bool = true
    var fileShelfLiveActivityEnabled: Bool = true
    var fileProgressLiveActivityEnabled: Bool = false

    var microphoneLiveActivityEnabled: Bool = true
    var microphoneLiveActivityBehavior: MicrophoneLiveActivityBehavior = .iconAndGesture

    var statsLiveActivityEnabled: Bool = false
    var selectedStats: [StatType] = [.cpu, .ram, .gpu, .disk]
    var selectedSensorKeys: [String] = []

    var statsLiveActivityThresholdEnabled: Bool = false
    var statThresholds: [StatType: StatThreshold] = [
        .cpu: StatThreshold(),
        .ram: StatThreshold(),
        .gpu: StatThreshold()
    ]

    var sportsLiveActivityEnabled: Bool = false
    var sportsCommentaryInLiveActivity: Bool = false
    var sportsLiveActivityWhenLiveOnly: Bool = false
    var financeLiveActivityEnabled: Bool = false
    var financeLiveActivityActiveHoursOnly: Bool = false
    var sportsOpenOnClick: Bool = true
    var financeOpenOnClick: Bool = true
    var sportsPreferLogo: Bool = true
    var sportsFavoriteTeams: [String] = ["Kansas City Chiefs"]
    var financeFavoriteSymbols: [String] = ["AAPL", "MSFT", "NVDA"]
    var financeShares: [String: Double] = [:]
    var financeInvested: [String: Double] = [:]
    var financeInvestmentStartDates: [String: Date] = [:]
    var sportsFavoriteTeamIndex: Int = 0
    var financeFavoriteSymbolIndex: Int = 0

    mutating func normalizedSportsFavoriteTeamIndex() {
        guard !sportsFavoriteTeams.isEmpty else { sportsFavoriteTeamIndex = 0; return }
        sportsFavoriteTeamIndex = max(0, min(sportsFavoriteTeamIndex, sportsFavoriteTeams.count - 1))
    }

    mutating func normalizedFinanceFavoriteSymbolIndex() {
        guard !financeFavoriteSymbols.isEmpty else { financeFavoriteSymbolIndex = 0; return }
        financeFavoriteSymbolIndex = max(0, min(financeFavoriteSymbolIndex, financeFavoriteSymbols.count - 1))
    }

    mutating func disableUnavailablePremiumFeatures() {
        if !SubscriptionAccess.hasAccess(to: .sportsWidget) {
            sportsWidgetEnabled = false
        }
        if !SubscriptionAccess.hasAccess(to: .financeWidget) {
            financeWidgetEnabled = false
        }
        if !SubscriptionAccess.hasAccess(to: .liveSports) {
            sportsLiveActivityEnabled = false
        }
        if !SubscriptionAccess.hasAccess(to: .financeLiveActivity) {
            financeLiveActivityEnabled = false
        }
    }

    mutating func normalizeCollectionOrders() {
        let allActivities = LiveActivityType.allCases
        liveActivityOrder = liveActivityOrder.filter { allActivities.contains($0) }.deduplicated()
        let missingActivities = allActivities.filter { !liveActivityOrder.contains($0) }
        if !missingActivities.isEmpty {
            liveActivityOrder.append(contentsOf: missingActivities)
        }

        let allWidgets = WidgetType.allCases
        widgetOrder = widgetOrder.filter { allWidgets.contains($0) }.deduplicated()
        let missingWidgets = allWidgets.filter { !widgetOrder.contains($0) }
        if !missingWidgets.isEmpty {
            widgetOrder.append(contentsOf: missingWidgets)
        }

        let allNotchButtons = NotchButtonType.allCases
        notchButtonOrder = notchButtonOrder.filter { allNotchButtons.contains($0) }.deduplicated()
        let missingNotchButtons = allNotchButtons.filter { !notchButtonOrder.contains($0) }
        if !missingNotchButtons.isEmpty {
            if let spacerIndex = notchButtonOrder.firstIndex(of: .spacer) {
                notchButtonOrder.insert(contentsOf: missingNotchButtons, at: spacerIndex)
            } else {
                notchButtonOrder.append(contentsOf: missingNotchButtons)
            }
        }
    }

    func currentSportsFavoriteTeam() -> String? {
        guard !sportsFavoriteTeams.isEmpty else { return nil }
        let index = max(0, min(sportsFavoriteTeamIndex, sportsFavoriteTeams.count - 1))
        return sportsFavoriteTeams[index]
    }

    func currentFinanceFavoriteSymbol() -> String? {
        guard !financeFavoriteSymbols.isEmpty else { return nil }
        let index = max(0, min(financeFavoriteSymbolIndex, financeFavoriteSymbols.count - 1))
        return financeFavoriteSymbols[index]
    }

    func currentSportsTeam() -> String? {
        currentSportsFavoriteTeam()
    }

    func currentFinanceSymbol() -> String? {
        currentFinanceFavoriteSymbol()
    }

    var swipeActionSettings: SwipeActionSettings = .init()
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
    var mediaAppVisibility: [String: Bool] = [:]
    var hideLiveActivityWhenSourceActive: Bool = true
    var enableQuickPeekOnHover: Bool = true
    var showQuickPeekOnTrackChange: Bool = true
    var swipeToSkipMusic: Bool = true
    var swipeToRewindMusic: Bool = true
    var invertMusicGestures: Bool = false
    var twoFingerTapToPauseMusic: Bool = true
    var musicHoldSkipForSecondaryActions: Bool = true
    var musicLongPressActionsEnabled: Bool = true
    var musicLongPressPrevious: MusicLongPressAction = .none
    var musicLongPressNext: MusicLongPressAction = .none
    var musicLongPressPlayPause: MusicLongPressAction = .none
    var musicLongPressPlaylists: MusicLongPressAction = .openDevices
    var musicLongPressDevices: MusicLongPressAction = .openQueue
    var musicLongPressLike: MusicLongPressAction = .shuffle
    var musicLongPressShuffle: MusicLongPressAction = .repeatMode
    var musicLongPressRepeat: MusicLongPressAction = .like
    var waveformUseGradient: Bool = true
    var useStaticWaveform: Bool = false
    var waveformBarCount: Int = 3
    var waveformBarThickness: Double = 4.0
    var musicWaveformIsVolumeSensitive: Bool = true
    var spotifyClientId: String {
        get { APIKeyManager.shared.spotifyClientId }
        set { APIKeyManager.shared.spotifyClientId = newValue }
    }
    var spotifyClientSecret: String {
        get { APIKeyManager.shared.spotifyClientSecret }
        set { APIKeyManager.shared.spotifyClientSecret = newValue }
    }
    var skipSpotifyAd: Bool = false
    var defaultMusicPlayer: DefaultMusicPlayer = .appleMusic
    var showLyricsInLiveActivity: Bool = false
    var enableLyricTranslation: Bool = true
    var lyricTranslationLanguage: String = "en"
    var lyricOffset: Double = 0.0
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
    var persistMusicWidgetWhenPaused: Bool = true
    var preferAirPlayOverSpotify: Bool = true
    var spotifyCanvasLiveVideo: Bool = true
    var showSpotifySourceTab: Bool = true
    var spotifyShowArtistProfile: Bool = true
    var spotifyShowSuggestedSongs: Bool = true
    var spotifyShowNextSong: Bool = true
    var spotifyShowNextSongAlbumArt: Bool = true
    var spotifyShowConcertTickets: Bool = false
    var spotifyShowAccountBadge: Bool = true

    var hudDuration: Double = 2.5
    var hudShowPercentage: Bool = true
    var hudShowFunctionName: Bool = false
    var hudVisualStyle: HUDVisualStyle = .adaptive
    var hudCustomColor: CodableColor? = CodableColor(color: .accentColor)
    var enableVolumeHUD: Bool = true
    var volumeHUDStyle: HUDStyle = .default
    var volumeHUDShowDots: Bool = false
    var volumeHUDSoundEnabled: Bool = true
    var showSpotifyVolumeHUD: Bool = true
    var showAppVolumeHUD: Bool = true
    var showAppVolumeInNormalHUD: Bool = false
    var perAppVolumeSystemDependent: Bool = true
    var volumeHUDShowDeviceIcon: Bool = true
    var excludeBuiltInSpeakersFromHUDIcon: Bool = true
    var enableBrightnessHUD: Bool = true
    var brightnessHUDStyle: HUDStyle = .default
    var brightnessHUDShowDots: Bool = false
    var hudPillPosition: PillHUDPosition = .right
    var hudPillStyle: PillHUDStyle = .contained
    var hudPillLength: Double = 340
    var hudPillThickness: Double = 64
    var volumesliderstep: Int = 6
    var volumesliderstepByDevice: [String: Int] = [:]
    var brightnessliderstep: Int = 6

    var effectiveVolumeHUDStyle: HUDStyle { volumeHUDShowDots ? .dots : volumeHUDStyle }
    var effectiveBrightnessHUDStyle: HUDStyle { brightnessHUDShowDots ? .dots : brightnessHUDStyle }
    var snapZoneViewMode: SnapZoneViewMode = .multi
    var snapDragEnabled: Bool = true
    var snapOnWindowDragEnabled: Bool = true
    var snapActivationDelay: Double = 0.45
    var defaultSnapLayout: SnapLayout = LayoutTemplate.columns
    var appSpecificLayoutConfigurations: [String: AppSnapLayoutConfiguration] = [:]
    var customSnapLayouts: [SnapLayout] = []
    var snapZoneShortcuts: [SnapZoneShortcut] = []
    var snapZoneLayoutOptions: [UUID] = [LayoutTemplate.fancy.id, LayoutTemplate.quarters.id, LayoutTemplate.splitscreen.id, LayoutTemplate.focus.id, LayoutTemplate.fullscreen.id]
    var planes: [Plane] = []
    var batteryChargeLimit: Int = 100
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
    var logBatteryDuringSleep: Bool = false
    var sleepLoggingIntervalMinutes: Int = 30
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
    var preventSleepDuringDischarge: Bool = false
    var fanControlModes: [String: StoredFanControlMode] = [:]
    var enableBiweeklyCalibration: Bool = false
    var magSafeGreenAtLimit: Bool = true
    var bluetoothNotifyLowBattery: Bool = true
    var bluetoothNotifySound: Bool = true
    var showBluetoothDeviceName: Bool = false
    var bluetoothLiveActivityEnabled: Bool = true
    var showBluetoothContinuityDevices: Bool = true
    var bluetoothUnlockEnabled: Bool = false
    var bluetoothUnlockDeviceID: String? = nil
    var bluetoothUnlockUnlockRSSI: Int = -65
    var bluetoothUnlockLockRSSI: Int = -75
    var bluetoothUnlockTimeout: Double = 5.0
    var bluetoothUnlockNoSignalTimeout: Double = 60.0
    var bluetoothUnlockMinScanRSSI: Int = -80
    var bluetoothUnlockPassiveMode: Bool = false
    var faceIDUnlockEnabled: Bool = false
    var faceIDAntiSpoofEnabled: Bool = true
    var hasRegisteredFaceID: Bool = false
    var faceIDSpoofLockDuration: Double = 3.0
    var faceIDAntiSpoofAcceptThreshold: Double = 0.50
    var faceIDMismatchTimeout: Double = 30.0
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
    var smartInboxEnabled: Bool = true
    var mailOTPDetectionEnabled: Bool = true
    var autoCopyVerificationCodes: Bool = false
    var parcelTrackingEnabled: Bool = true
    var parcelLiveActivityEnabled: Bool = true
    var otpLiveActivityEnabled: Bool = true
    var neardropEnabled: Bool = true
    var neardropDeviceDisplayName: String = Host.current().localizedName ?? "My Mac"
    var neardropDownloadLocationPath: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path
    var neardropOpenOnClick: Bool = true
    var clickToOpenFileShelf: Bool = true
    var hoverToOpenFileShelf: Bool = true
    var removeFileFromShelfAfterDrag: Bool = false
    var launchpadLayout: [[LaunchpadPageItem]] = []
    var weatherUseCelsius: Bool = false
    var weatherUseMetricSystem: Bool = false
    var weatherOpenOnClick: Bool = false
    var calendarShowAllDayEvents: Bool = true
    var calendarStartOfWeek: Day = .sunday
    var calendarOpenOnClick: Bool = true
    var eyeBreakWorkInterval: Double = 20
    var eyeBreakBreakDuration: Double = 20
    var eyeBreakSoundAlerts: Bool = true
    var showEyeBreakGraph: Bool = true
    var clickToShowTimerView: Bool = true
    var sleepInClamshell: Bool = true
    var persistentCaffeinateAfterClamshell: Bool = false
    var caffeinateTimeoutMinutes: Double = 0
    var caffeinateTurnOffScreenUsingLidAngle: Bool = false
    var caffeinateLidAngleTrigger: Double = 15.0
    var lidAnglePauseMediaEnabled: Bool = false
    var lidAnglePauseMediaTrigger: Double = 18.0
    var lidAngleMuteAudioEnabled: Bool = false
    var lidAngleMuteAudioTrigger: Double = 14.0
    var lidAngleSleepDisplayEnabled: Bool = false
    var lidAngleSleepDisplayTrigger: Double = 12.0
    var lidAngleLowPowerModeEnabled: Bool = false
    var lidAngleLowPowerModeTrigger: Double = 35.0

    var menuBarEnabled: Bool = false
    var showOnClick: Bool = true
    var showOnHover: Bool = true
    var showOnHoverDelay: TimeInterval = 0.4
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
    var menuBarLiquidGlassIntensity: Double = 0.65

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

struct SettingsBackupPayload: Codable {
    let appName: String
    let schemaVersion: Int
    let exportedAt: Date
    let settings: Settings

    init(settings: Settings, exportedAt: Date = .now) {
        self.appName = "Sapphire"
        self.schemaVersion = 1
        self.exportedAt = exportedAt
        self.settings = settings
    }
}

struct SettingsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sapphireSettingsBackup, .json] }

    var payload: SettingsBackupPayload

    init(settings: Settings) {
        self.payload = SettingsBackupPayload(settings: settings)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.payload = try Self.decodePayload(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return FileWrapper(regularFileWithContents: try encoder.encode(payload))
    }

    static func decodePayload(from data: Data) throws -> SettingsBackupPayload {
        let decoder = JSONDecoder()

        if let payload = try? decoder.decode(SettingsBackupPayload.self, from: data) {
            return payload
        }

        if let settings = SettingsPersistence.decodeFromPayload(data) {
            return SettingsBackupPayload(settings: settings)
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "The file could not be read as a Sapphire settings backup."
            )
        )
    }
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

// MARK: - Settings Persistence Helpers

private enum SettingsPersistence {
    static let payloadKey = "sapphire.settings.payload"
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    static let decoder = JSONDecoder()

    static let legacyAPIKeyUserDefaultsKeys: Set<String> = [
        "geminiAPIKey",
        "intelligenceApiKey",
        "hackClubAPIKey",
        "openAIAPIKey",
        "anthropicAPIKey",
        "openRouterAPIKey",
        "xaiAPIKey",
        "nvidiaAPIKey",
        "spotifyClientId",
        "spotifyClientSecret",
        "geminiApiKey",
        "agentSApiKey",
    ]

    static let settingsFileName = "settings.json"
    static let settingsBackupFileName = "settings.backup.json"

    static var directoryURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sapphire", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var fileURL: URL { directoryURL.appendingPathComponent(settingsFileName) }
    static var backupURL: URL { directoryURL.appendingPathComponent(settingsBackupFileName) }

    static func purgeLegacyAPIKeyUserDefaults() {
        let defaults = UserDefaults.standard
        for key in legacyAPIKeyUserDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
    }

    static func encodeToDictionary(_ settings: Settings) -> [String: Any]? {
        guard let data = try? encoder.encode(settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func decodeFromDictionary(_ dictionary: [String: Any]) -> Settings? {
        decodeDictionaryTolerantly(dictionary)
    }

    static func decodeFromPayload(_ data: Data) -> Settings? {
        if var settings = try? decoder.decode(Settings.self, from: data) {
            settings.normalizeCollectionOrders()
            return settings
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let settingsDictionary: [String: Any]
        if let wrapped = object["settings"] as? [String: Any] {
            settingsDictionary = wrapped
        } else {
            settingsDictionary = object
        }
        return decodeFromDictionary(settingsDictionary)
    }

    // MARK: - Tolerant decoding

    private static func decodeDictionaryTolerantly(_ dictionary: [String: Any]) -> Settings? {
        if let settings = decodeFromJSONDictionary(dictionary) {
            return settings
        }
        guard let defaults = encodeToDictionary(Settings()) else { return nil }

        var merged = deepMergedDictionary(defaults: defaults, incoming: dictionary)
        if let settings = decodeFromJSONDictionary(merged) {
            return settings
        }

        var droppedKeys: [String] = []
        while decodeFromJSONDictionary(merged) == nil {
            var repaired = false
            for key in dictionary.keys {
                var candidate = merged
                if let defaultValue = defaults[key] {
                    candidate[key] = defaultValue
                } else {
                    candidate.removeValue(forKey: key)
                }
                if decodeFromJSONDictionary(candidate) != nil {
                    merged = candidate
                    droppedKeys.append(key)
                    repaired = true
                    break
                }
            }
            if !repaired { return nil }
        }
        if !droppedKeys.isEmpty {
            print("[SettingsModel] Settings import: reverted incompatible keys to defaults: \(droppedKeys.sorted())")
        }
        return decodeFromJSONDictionary(merged)
    }

    private static func decodeFromJSONDictionary(_ dictionary: [String: Any]) -> Settings? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary),
              var settings = try? decoder.decode(Settings.self, from: data) else {
            return nil
        }
        settings.normalizeCollectionOrders()
        return settings
    }

    private static func deepMergedDictionary(defaults: [String: Any], incoming: [String: Any]) -> [String: Any] {
        var result = defaults
        for (key, incomingValue) in incoming {
            if let incomingDict = incomingValue as? [String: Any],
               let defaultDict = result[key] as? [String: Any] {
                result[key] = deepMergedDictionary(defaults: defaultDict, incoming: incomingDict)
            } else {
                result[key] = incomingValue
            }
        }
        return result
    }

    static func isJSONCompatible(_ value: Any) -> Bool {
        if value is String || value is Bool || value is NSNull { return true }
        if value is Int || value is Double || value is Float { return true }
        if let number = value as? NSNumber { return true }
        if let array = value as? [Any] { return array.allSatisfy(isJSONCompatible) }
        if let dictionary = value as? [String: Any] { return dictionary.values.allSatisfy(isJSONCompatible) }
        if let array = value as? NSArray { return array.allSatisfy { isJSONCompatible($0) } }
        if let dictionary = value as? NSDictionary {
            return dictionary.allKeys.allSatisfy { $0 is String } && dictionary.allValues.allSatisfy { isJSONCompatible($0) }
        }
        return false
    }

    static func loadImportedSettingsSnapshot() -> Settings? {
        for url in [fileURL, backupURL] {
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let settings = decodeFromPayload(data) else {
                continue
            }
            return settings
        }
        return nil
    }

    static func removeImportedSettingsSnapshots() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: backupURL)
    }
}

// MARK: - SettingsModel Class
class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    @Published var settings: Settings = Settings() {
        didSet {
            guard !isApplyingLoadedSettings else { return }
            if settings.volumeHUDSoundEnabled != oldValue.volumeHUDSoundEnabled {
                SystemSoundFeedback.isVolumeChangeFeedbackEnabled = settings.volumeHUDSoundEnabled
            }
            var sanitized = settings
            sanitized.normalizeCollectionOrders()
            if sanitized != settings {
                isApplyingLoadedSettings = true
                settings = sanitized
                isApplyingLoadedSettings = false
                scheduleSaveSettings()
                return
            }
            scheduleSaveSettings()
        }
    }

    private let defaults = UserDefaults.standard
    private let settingsAccessQueue = DispatchQueue(label: "com.cshariq.sapphire.settings.sync.queue")
    private var isApplyingLoadedSettings = false
    private var pendingSaveWorkItem: DispatchWorkItem?

    private var lastPersistedSettings: Settings?
    private var isPersisting = false

    private init() {
        _ = APIKeyManager.shared
        let loaded = Self.readSettingsFromStorage()
        isApplyingLoadedSettings = true
        settings = loaded
        isApplyingLoadedSettings = false

        settings.volumeHUDSoundEnabled = SystemSoundFeedback.isVolumeChangeFeedbackEnabled

        applyIntelligenceRuntimePreferences(from: loaded)
        lastPersistedSettings = settings
        persistSettingsUnlocked(settings)
        SettingsPersistence.removeImportedSettingsSnapshots()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushPendingSave()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushPendingSave()
        }
    }

    private static func readSettingsFromStorage() -> Settings {
        SettingsPersistence.purgeLegacyAPIKeyUserDefaults()
        let defaults = UserDefaults.standard

        var loaded: Settings
        if let payload = defaults.data(forKey: SettingsPersistence.payloadKey),
           let decoded = SettingsPersistence.decodeFromPayload(payload) {
            loaded = decoded
        } else if let snapshot = SettingsPersistence.loadImportedSettingsSnapshot() {
            loaded = snapshot
        } else if let merged = decodeSettingsFromUserDefaults(defaults) {
            loaded = merged
        } else {
            loaded = Settings()
        }

        if defaults.object(forKey: "musicLongPressActionsMigratedV2") == nil {
            loaded.musicLongPressPrevious = .none
            loaded.musicLongPressNext = .none
            loaded.musicLongPressPlayPause = .none
            if loaded.musicLongPressPlaylists == .none {
                loaded.musicLongPressPlaylists = .openDevices
            }
            if loaded.musicLongPressDevices == .none {
                loaded.musicLongPressDevices = .openQueue
            }
            defaults.set(true, forKey: "musicLongPressActionsMigratedV2")
        } else if defaults.object(forKey: "musicLongPressPrevious") == nil {
            if loaded.musicHoldSkipForSecondaryActions {
                loaded.musicLongPressActionsEnabled = true
            } else {
                loaded.musicLongPressActionsEnabled = false
            }
            loaded.musicLongPressPrevious = .none
            loaded.musicLongPressNext = .none
        }

        if defaults.object(forKey: "focusDefaultsAppliedV1") == nil {
            loaded.focusSessionDuration = 90 * 60
            loaded.focusBreakEnabled = false
            loaded.focusBreakDuration = 0
            defaults.set(true, forKey: "focusDefaultsAppliedV1")
        }

        loaded.disableUnavailablePremiumFeatures()
        return loaded
    }

    private static func decodeSettingsFromUserDefaults(_ defaults: UserDefaults) -> Settings? {
        let fallback = Settings()
        guard var dictionary = SettingsPersistence.encodeToDictionary(fallback) else {
            return nil
        }

        for key in dictionary.keys {
            guard !SettingsPersistence.legacyAPIKeyUserDefaultsKeys.contains(key),
                  let savedValue = defaults.object(forKey: key),
                  SettingsPersistence.isJSONCompatible(savedValue) else {
                continue
            }

            var candidate = dictionary
            candidate[key] = savedValue
            if SettingsPersistence.decodeFromDictionary(candidate) != nil {
                dictionary[key] = savedValue
            }
        }

        return SettingsPersistence.decodeFromDictionary(dictionary)
    }

    private func applyIntelligenceRuntimePreferences(from loadedSettings: Settings) {
        UserDefaults.standard.set(loadedSettings.intelligenceGeminiModel.rawValue, forKey: "geminiModelID")
        UserDefaults.standard.set(loadedSettings.intelligenceGeminiSpeedMode.rawValue, forKey: "geminiSpeedMode")
        UserDefaults.standard.set(loadedSettings.intelligenceBackend.rawValue, forKey: "llmBackend")
        BlipModelPreferences.openAIModel = loadedSettings.intelligenceOpenAIModel.rawValue
        BlipModelPreferences.anthropicModel = loadedSettings.intelligenceAnthropicModel.rawValue
        BlipModelPreferences.openRouterModelStored = loadedSettings.intelligenceOpenRouterModel
        BlipModelPreferences.xaiModel = loadedSettings.intelligenceXAIModel.rawValue
        BlipModelPreferences.nvidiaModel = loadedSettings.intelligenceNVIDIAModel.rawValue
    }

    private func scheduleSaveSettings() {
        guard settings != lastPersistedSettings || pendingSaveWorkItem != nil else { return }
        pendingSaveWorkItem?.cancel()
        var snapshot = settings
        snapshot.normalizeCollectionOrders()
        let work = DispatchWorkItem { [weak self] in
            self?.persistSettingsUnlocked(snapshot)
        }
        pendingSaveWorkItem = work
        settingsAccessQueue.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
    }

    func flushPendingSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        guard settings != lastPersistedSettings else { return }
        persistSettingsUnlocked(settings)
    }

    private func persistSettingsUnlocked(_ settingsToPersist: Settings? = nil) {
        var settingsToSave = settingsToPersist ?? settings
        if Thread.isMainThread {
            settingsToSave.normalizeCollectionOrders()
        }
        applyIntelligenceRuntimePreferences(from: settingsToSave)

        guard let payload = try? SettingsPersistence.encoder.encode(settingsToSave) else {
            print("[SettingsModel] Failed to encode settings payload.")
            return
        }
        defaults.set(payload, forKey: SettingsPersistence.payloadKey)

        if let dictionary = SettingsPersistence.encodeToDictionary(settingsToSave) {
            for (key, value) in dictionary {
                defaults.set(value, forKey: key)
            }
        }

        lastPersistedSettings = settingsToSave
    }

    func makeBackupDocument() -> SettingsBackupDocument {
        SettingsBackupDocument(settings: settings)
    }

    func volumeSliderStep(forDeviceUID uid: String?) -> Int {
        guard let uid = uid else { return settings.volumesliderstep }
        return settings.volumesliderstepByDevice[uid] ?? settings.volumesliderstep
    }

    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let importedPayload = try SettingsBackupDocument.decodePayload(from: data)
        var importedSettings = importedPayload.settings
        importedSettings.normalizeCollectionOrders()
        importedSettings.disableUnavailablePremiumFeatures()
        settings = importedSettings
    }

    func resetAllSettings() {
        settings = Settings()
    }

    func sanitizePremiumFeatureSettings() {
        var sanitized = settings
        sanitized.disableUnavailablePremiumFeatures()
        ReleaseChannelPolicy.reconcileStoredPreference(&sanitized)
        if sanitized != settings {
            settings = sanitized
        }
    }
}

// MARK: - Supporting Enums and Structs

private extension Array where Element: Equatable {
    func deduplicated() -> [Element] {
        var seen: [Element] = []
        return filter { element in
            if seen.contains(element) {
                return false
            }
            seen.append(element)
            return true
        }
    }
}

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
    case weather, calendar, shortcuts, music, sports, finance, shopify, notes, clipboard, mirror, battery, focusSession, agent
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .weather: return "Weather"
        case .calendar: return "Calendar"
        case .shortcuts: return "Shortcuts"
        case .music: return "Music"
        case .sports: return "Sports"
        case .finance: return "Finance"
        case .shopify: return "Shopify Orders"
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        case .mirror: return "Mirror"
        case .battery: return "Battery"
        case .focusSession: return "Focus"
        case .agent: return "Agent"
        }
    }
}

enum LiveActivityType: String, Codable, CaseIterable, Identifiable, Equatable {
    case fileShelf, eyeBreak, focus, desktop, battery, timers, calendar, reminders, weather, music, fileProgress, stats, microphone, sports, finance
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .music: "Music"; case .weather: "Weather"; case .calendar: "Calendar"; case .reminders: "Reminders"; case .timers: "Timers"; case .battery: "Battery"; case .eyeBreak: "Eye Break"; case .desktop: "Desktop"; case .focus: "Focus"; case .fileShelf: "File Shelf"; case .fileProgress: "File Progress"; case .stats: "Stats"; case .microphone: "Microphone"; case .sports: "Sports"; case .finance: "Finance"
        }
    }
}

enum FocusIntensity: String, Codable, CaseIterable, Identifiable {
    case minimal
    case gentle
    case standard
    case strict

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .gentle: return "Gentle"
        case .standard: return "Standard"
        case .strict: return "Strict"
        }
    }

    var systemImage: String {
        switch self {
        case .minimal: return "hand.raised"
        case .gentle: return "hand.raised.fill"
        case .standard: return "lock.shield"
        case .strict: return "shield.lefthalf.filled"
        }
    }

    var blurb: String {
        switch self {
        case .minimal:
            return "App is blurred while blocked. Notifications stay visible, and you can unblock an app instantly with a button, the app stays open."
        case .gentle:
            return "App is blurred while blocked. Notifications stay visible and the app stays open, but there is no unblock button, although you can end the session anytime."
        case .standard:
            return "Blocked apps are force-closed the moment they open and notifications are hidden. No unblocking, but you can end the session anytime."
        case .strict:
            return "Blocked apps are force-closed and notifications are hidden. Unblock requests wait 10 minutes (or until the session ends), and the session itself can't be stopped early."
        }
    }

    var suppressesNotifications: Bool {
        switch self {
        case .minimal, .gentle: return false
        case .standard, .strict: return true
        }
    }

    var forceClosesBlockedApps: Bool {
        switch self {
        case .minimal, .gentle: return false
        case .standard, .strict: return true
        }
    }

    var canEndSessionEarly: Bool {
        switch self {
        case .minimal, .gentle, .standard: return true
        case .strict: return false
        }
    }
}

enum MirrorRotationMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case angle90
    case angle180
    case angle270

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .angle90: return "90°"
        case .angle180: return "180°"
        case .angle270: return "270°"
        }
    }

    var systemImage: String {
        switch self {
        case .auto: return "rotate.right"
        case .angle90: return "90.rotation"
        case .angle180: return "180.rotation"
        case .angle270: return "270.rotation"
        }
    }

    var angle: CGFloat? {
        switch self {
        case .auto: return nil
        case .angle90: return 90
        case .angle180: return 180
        case .angle270: return 270
        }
    }

    var next: MirrorRotationMode {
        switch self {
        case .auto: return .angle90
        case .angle90: return .angle180
        case .angle180: return .angle270
        case .angle270: return .auto
        }
    }
}

enum FocusShortcutSyncMode: String, Codable, CaseIterable, Identifiable {
    case none
    case timer
    case stopwatch

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .timer: return "Sync Timer"
        case .stopwatch: return "Sync Stopwatch"
        }
    }
}

enum FocusBlockingMode: String, Codable, CaseIterable, Identifiable {
    case blocklist
    case allowlist

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .blocklist: return "Block selected apps"
        case .allowlist: return "Allow only selected apps"
        }
    }

    var blurb: String {
        switch self {
        case .blocklist:
            return "Blocks only the apps (and websites) you add to the list. Everything else stays accessible."
        case .allowlist:
            return "Blocks every app except the ones you allow. Ideal for deep-work sessions where only a few tools should exist."
        }
    }
}

enum FocusAmbientSoundType: String, Codable, CaseIterable, Identifiable {
    case whiteNoise
    case pinkNoise
    case brownNoise
    case rain

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .whiteNoise: return "White Noise"
        case .pinkNoise: return "Pink Noise"
        case .brownNoise: return "Brown Noise"
        case .rain: return "Rain"
        }
    }

    var systemImage: String {
        switch self {
        case .whiteNoise: return "waveform"
        case .pinkNoise: return "waveform.circle"
        case .brownNoise: return "water.waves"
        case .rain: return "cloud.rain.fill"
        }
    }
}

enum MicrophoneLiveActivityBehavior: String, Codable, CaseIterable, Identifiable {
    case iconOnly
    case iconAndGesture

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .iconOnly: return "Icon Only"
        case .iconAndGesture: return "Icon + Gesture"
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
    case expandOnHover, swipeToSwitchWidgets, enableOpeningBounce, capsLockHorizontalLock
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .expandOnHover: "Expand on Hover"
        case .swipeToSwitchWidgets: "Swipe to Switch Widgets"
        case .enableOpeningBounce: "Bounce when Opening Widgets"
        case .capsLockHorizontalLock: "Lock Cursor Horizontally with Caps Lock"
        }
    }
    var systemImage: String {
        switch self {
        case .expandOnHover: "cursorarrow.motionlines"
        case .swipeToSwitchWidgets: "hand.draw.fill"
        case .enableOpeningBounce: "arrowshape.bounce.forward.fill"
        case .capsLockHorizontalLock: "capslock"
        }
    }
    var iconColor: Color {
        switch self {
        case .expandOnHover: .cyan
        case .swipeToSwitchWidgets: .orange
        case .enableOpeningBounce: .blue
        case .capsLockHorizontalLock: .green
        }
    }
}

enum NotchButtonType: String, Codable, Identifiable, Equatable {
    case settings, fileShelf, notes, clipboard, intelligence, intelligenceLive, focusSession, caffeine, spacer, multiAudio, battery, pin
    var id: String { self.rawValue }

    static let allCases: [NotchButtonType] = [
        .settings, .fileShelf, .notes, .clipboard, .intelligence,
        .focusSession, .caffeine, .spacer, .multiAudio, .battery, .pin,
    ]

    var displayName: String {
        switch self {
        case .settings: "Settings"; case .fileShelf: "File Shelf"; case .notes: "Notes"; case .clipboard: "Clipboard"
        case .intelligence: "Blip"; case .intelligenceLive: "Gemini";
        case .focusSession: "Focus";
        case .caffeine: "Caffeinate"; case .spacer: "Spacer";
        case .multiAudio: "Multi-Audio (Beta)"; case .battery: "Battery"; case .pin: "Pin"
        }
    }

    var systemImage: String {
        switch self {
        case .settings: "gearshape"; case .fileShelf: "tray.full"; case .notes: "note.text"; case .clipboard: "list.clipboard"
        case .intelligence: "sparkle"; case .intelligenceLive: "waveform";
        case .focusSession: "moon.fill";
        case .caffeine: "cup.and.saucer"; case .spacer: "space";
        case .multiAudio: "hifispeaker.and.homepod.mini.fill"; case .battery: "battery.100"; case .pin: "pin"
        }
    }
}

struct SystemApp: Identifiable, Equatable {
    let id: String, name: String, isBrowser: Bool, url: URL
}

enum AppIconLoader {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()

    static func icon(for url: URL, maxDimension: CGFloat = 32) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let image = downsample(NSWorkspace.shared.icon(forFile: url.path), maxDimension: maxDimension)
        cache.setObject(image, forKey: key, cost: Int(maxDimension * maxDimension * 4))
        return image
    }

    static func releaseCache() {
        cache.removeAllObjects()
    }

    nonisolated static func downsample(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

enum Day: String, Codable, CaseIterable, Identifiable {
    case sunday, monday
    var id: String { self.rawValue.capitalized }

    var firstWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        }
    }

    var configuredCalendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = self.firstWeekday
        return cal
    }

    var weekdayHeaders: [String] {
        let symbols = configuredCalendar.shortWeekdaySymbols
        let offset = self.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

enum DefaultMusicPlayer: String, Codable, CaseIterable, Identifiable {
    case appleMusic, spotify, tidal, youtubeMusic
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .tidal: "Tidal"
        case .youtubeMusic: "YouTube Music"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .tidal: "com.tidal.desktop"
        case .youtubeMusic: nil
        }
    }

    var webURL: URL? {
        switch self {
        case .appleMusic: nil
        case .spotify: nil
        case .tidal: URL(string: "https://tidal.com")
        case .youtubeMusic: URL(string: "https://music.youtube.com")
        }
    }

    var isAppInstalled: Bool {
        guard let bundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func open() {
        if let bundleIdentifier,
           NSWorkspace.shared.launchApplication(
               withBundleIdentifier: bundleIdentifier,
               options: [],
               additionalEventParamDescriptor: nil,
               launchIdentifier: nil
           ) {
            return
        }
        if let webURL {
            NSWorkspace.shared.open(webURL)
        }
    }
}

enum HUDStyle: String, Codable, CaseIterable, Identifiable {
    case `default`, thin, dots, pill
    var id: String { self.rawValue.capitalized }
}

enum PillHUDPosition: String, Codable, CaseIterable, Identifiable {
    case left, right, bottom
    var id: String { self.rawValue.capitalized }
}

enum PillHUDStyle: String, Codable, CaseIterable, Identifiable {
    case contained, bare
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
    static let launchpadItem = UTType(exportedAs: "com.cshariq.sapphire.launchpaditem")
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, apps, storage, widgets, liveActivities, appearance, lockScreen, bluetoothUnlock, shortcuts, snapZones, audio, battery, bluetooth, hud, notifications, neardrop, fileShelf, notes, clipboard, mirror, caffeine, music, weather, calendar, eyeBreak, focusSession, appLock, intelligence, sports, finance, about

    var id: String { self.rawValue }

    var requiredPremiumFeature: AppFeature? {
        switch self {
        case .intelligence:
            return .geminiLive
        case .sports:
            return .liveSports
        case .finance:
            return .financeWidget
        case .appLock:
            return .appLock
        default:
            return nil
        }
    }

    var minimumRequiredTier: SubscriptionTier? {
        guard let requiredPremiumFeature else { return nil }
        return SubscriptionFeatureCatalog.minimumTier(for: requiredPremiumFeature)
    }

    var isPremiumLocked: Bool {
        guard let requiredPremiumFeature else { return false }
        return !SubscriptionAccess.hasAccess(to: requiredPremiumFeature)
    }

    func isPremiumLocked(for tier: SubscriptionTier, features: Set<AppFeature>) -> Bool {
        guard let requiredPremiumFeature else { return false }
        if features.contains(requiredPremiumFeature) { return false }
        return !SubscriptionFeatureCatalog.features(for: tier).contains(requiredPremiumFeature)
    }

    var shortDescription: String {
        switch self {
        case .general: "Core app behavior, launch options, animations, and notch controls."
        case .apps: "Review installed applications, inspect bundle details, and safely move unwanted apps to Trash."
        case .storage: "Find large folders and reclaim space with transparent, user-approved cleanup."
        case .widgets: "Choose which widgets appear in the notch and how they are ordered."
        case .liveActivities: "Control which live activities can surface and auto-expand in the notch."
        case .appearance: "Tune the notch look, materials, colors, and layout styling."
        case .lockScreen: "Configure Sapphire content and behavior while your Mac is locked."
        case .bluetoothUnlock: "Set up proximity-based authentication and trusted device behavior."
        case .shortcuts: "Manage quick actions and shortcut surfaces shown in Sapphire."
        case .snapZones: "Configure window snapping behavior, layouts, and zone actions."
        case .audio: "Audio adjustments, EQ, and per-app volume adjustments."
        case .battery: "Battery widgets, history, charging preferences, and power-related controls."
        case .bluetooth: "Bluetooth device integrations, visibility, and connection behavior."
        case .hud: "Heads-up display overlays for volume, brightness, keyboard, and media feedback."
        case .notifications: "Choose which system notifications Sapphire mirrors or enhances."
        case .neardrop: "Nearby sharing preferences, transfers, and device discovery options."
        case .fileShelf: "Manage temporary file storage, drag targets, and shelf behavior."
        case .notes: "Quick notes widget, click-to-expand behavior, and notch bar access."
        case .clipboard: "Clipboard history, monitoring, and notch clipboard shortcuts."
        case .mirror: "Mirror widget showing live camera feed, with expandable fullscreen view."
        case .caffeine: "Keep your Mac awake, clamshell sleep behavior, and lid-angle display controls."
        case .music: "Music widget sources, playback controls, and media integrations."
        case .weather: "Weather widget data sources, units, and location-based behavior."
        case .calendar: "Calendar and reminder integrations shown in widgets and live activities."
        case .eyeBreak: "Break reminders, timing, and focus nudges for healthier screen habits."
        case .focusSession: "Session-style focus mode with timers, app/website blocking, and session history."
        case .appLock: "Lock apps behind Touch ID or password — blur overlays, idle/sleep auto-lock, and auto-close."
        case .intelligence: "Sapphire Blip — Mac agent with memory, skills, tools, and computer use."
        case .sports: "Sports widget settings, favorite teams selection, and scoreboard configurations."
        case .finance: "Stock market ticker configurations, favorite stocks, and trendline visualizations."
        case .about: "App version details, credits, links, and project information."
        }
    }

    var searchTokens: [String] {
        switch self {
        case .general: ["startup", "login", "animation", "notch", "system", "behavior", "analytics", "google", "privacy", "tracking", "telemetry", "swipe", "hide", "lock"]
        case .apps: ["apps", "applications", "uninstall", "cleaner", "appcleaner", "bundle", "extensions", "startup"]
        case .storage: ["storage", "disk", "space", "large files", "cache", "cleanup", "daisy disk", "scanner"]
        case .widgets: ["widget", "widgets", "reorder", "layout"]
        case .liveActivities: ["live", "activity", "activities", "dynamic", "focus"]
        case .appearance: ["theme", "appearance", "style", "glass", "color", "material"]
        case .lockScreen: ["lock", "screen", "locked"]
        case .bluetoothUnlock: ["authentication", "unlock", "proximity", "trusted", "device"]
        case .shortcuts: ["shortcut", "action", "launcher"]
        case .snapZones: ["snap", "zones", "window", "tiling", "layout"]
        case .audio: ["audio", "EQ", "volume", "app", "devices"]
        case .battery: ["battery", "charging", "power", "history"]
        case .bluetooth: ["bluetooth", "devices", "connections"]
        case .hud: ["hud", "overlay", "volume", "brightness", "media", "pill", "position", "edge", "side"]
        case .notifications: ["notifications", "alerts", "imessage", "facetime", "airdrop"]
        case .neardrop: ["nearby", "share", "drop", "transfer"]
        case .fileShelf: ["file", "shelf", "drag", "drop", "storage", "remove"]
        case .notes: ["notes", "note", "memo", "quick note"]
        case .clipboard: ["clipboard", "pasteboard", "history", "copy", "paste"]
        case .mirror: ["mirror", "camera", "camera feed", "selfie", "webcam"]
        case .caffeine: ["caffeinate", "caffeine", "sleep", "awake", "clamshell", "lid", "timeout", "timer"]
        case .music: ["music", "media", "spotify", "playback"]
        case .weather: ["weather", "forecast", "temperature", "location"]
        case .calendar: ["calendar", "reminders", "events", "schedule"]
        case .eyeBreak: ["eye", "break", "rest", "wellness", "focus"]
        case .focusSession: ["focus", "session", "timer", "pomodoro", "block", "distraction", "website", "app", "blocking", "shortcut", "history", "stopwatch", "streak"]
        case .appLock: ["lock", "app lock", "protect", "touch id", "password", "privacy", "overlay", "idle", "sleep", "panic", "auto-close", "secure"]
        case .intelligence: ["intelligence", "blip", "facet", "nova", "octo", "claw", "connected", "accounts", "gmail", "github", "outlook", "findmy", "gemini", "ai", "assistant", "agent", "automation", "task", "voice", "live", "computer", "control", "accessibility", "memory", "skills", "personalization", "profiling", "monitoring", "privacy", "learning", "behavior", "screenshots", "calendar", "notes", "spotify", "clipboard", "settings", "data", "tracking", "circle", "search", "lasso"]
        case .sports: ["sports", "score", "game", "nfl", "nba", "mlb", "nhl", "team"]
        case .finance: ["finance", "stocks", "market", "ticker", "portfolio", "aapl"]
        case .about: ["about", "version", "credits", "support"]
        }
    }

    var requiredPermissions: [PermissionType] {
        switch self {
        case .hud, .music, .snapZones, .appearance: return [.accessibility]
        case .notifications: return [.notifications]
        case .weather: return [.location]
        case .calendar: return [.calendar, .reminders]
        case .bluetooth, .bluetoothUnlock: return [.bluetooth, .accessibility]
        case .liveActivities: return [.focusStatus]
        case .audio: return [.screenRecording]
        case .intelligence: return [.accessibility, .fullDiskAccess, .screenRecording]
        default: return []
        }
    }

    var label: String {
        switch self {
        case .general: "General"; case .apps: "Apps"; case .storage: "Storage"; case .widgets: "Widgets"; case .liveActivities: "Live Activities"; case .appearance: "Appearance"; case .lockScreen: "Lock Screen"; case .bluetoothUnlock: "Authentication"; case .shortcuts: "Shortcuts"; case .snapZones: "Snap Zones"; case .audio: "Audio"; case .battery: "Battery"; case .bluetooth: "Bluetooth"; case .hud: "HUD"; case .notifications: "Notifications"; case .neardrop: "Nearby Share"; case .fileShelf: "File Shelf"; case .notes: "Notes"; case .clipboard: "Clipboard"; case .mirror: "Mirror"; case .caffeine: "Caffeinate"; case .music: "Music"; case .weather: "Weather";        case .calendar: "Calendar"; case .eyeBreak: "Eye Break"; case .focusSession: "Focus Sessions"; case .appLock: "App Lock"; case .intelligence: "Blip"; case .sports: "Sports"; case .finance: "Finance"; case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"; case .apps: "square.stack.3d.up.fill"; case .storage: "internaldrive.fill"; case .widgets: "square.grid.2x2.fill"; case .liveActivities: "timer"; case .appearance: "paintpalette"; case .lockScreen: "lock.fill"; case .bluetoothUnlock: "lock.laptopcomputer"; case .shortcuts: "square.grid.3x1.below.line.grid.1x2"; case .snapZones: "uiwindow.split.2x1"; case .audio: "speaker.circle.fill"; case .battery: "battery.100"; case .bluetooth: "macbook.and.ipad"; case .hud: "macwindow.on.rectangle"; case .notifications: "bell"; case .neardrop: "shareplay"; case .fileShelf: "tray.full.fill"; case .notes: "note.text"; case .clipboard: "list.clipboard"; case .mirror: "camera.fill"; case .caffeine: "cup.and.saucer.fill"; case .music: "music.note"; case .weather: "cloud.sun.fill";        case .calendar: "calendar"; case .eyeBreak: "eye.fill"; case .focusSession: "moon.fill"; case .appLock: "lock.shield.fill"; case .intelligence: "sparkle"; case .sports: "sportscourt"; case .finance: "chart.line.uptrend.xyaxis"; case .about: "info.circle"
        }
    }

    var iconBackgroundColor: Color {
        switch self {
        case .general: .black; case .apps: .purple; case .storage: .orange; case .widgets: .gray; case .liveActivities: .cyan; case .appearance: .indigo; case .lockScreen: .red; case .bluetoothUnlock: .indigo; case .shortcuts: .orange; case .snapZones: .blue; case .audio: .red; case .battery: .green; case .bluetooth: .blue; case .hud: .indigo; case .notifications: .red; case .neardrop: .blue; case .fileShelf: .orange; case .notes: .yellow; case .clipboard: .mint; case .mirror: .indigo; case .caffeine: .brown; case .music: .pink; case .weather: .blue;        case .calendar: .red; case .eyeBreak: .teal; case .focusSession: .purple; case .appLock: .red; case .intelligence: .mint; case .sports: .green; case .finance: .green; case .about: .blue
        }
    }

    var iconGradientColors: [Color]? {
        switch self {
        case .focusSession: return [.purple, .indigo]
        case .appLock: return [.red, .orange]
        default: return nil
        }
    }
}

extension SettingsSection {
    static func features(requiring permission: PermissionType) -> [SettingsSection] {
        allCases.filter { $0.requiredPermissions.contains(permission) }
    }
}

@MainActor
class SystemAppFetcher: ObservableObject {
    static let shared = SystemAppFetcher()

    @Published private(set) var apps: [SystemApp] = []
    @Published private(set) var foundBundleIDs: Set<String> = []
    private var shouldDiscardFetch = false
    private var fetchTask: Task<Void, Never>?

    private init() {}

    func fetchApps() {
        guard apps.isEmpty, fetchTask == nil else { return }
        shouldDiscardFetch = false

        fetchTask = Task(priority: .utility) {
            var fetchedApps: [SystemApp] = []
            var seenBundleIDs = Set<String>()

            let fileManager = FileManager.default
            let searchPaths = [
                "/System/Applications",
                "/Applications"
            ] + NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true)

            for path in searchPaths.compactMap({ $0 }) {
                guard !Task.isCancelled else { return }
                guard let enumerator = fileManager.enumerator(
                    at: URL(fileURLWithPath: path),
                    includingPropertiesForKeys: [.isApplicationKey, .nameKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: nil
                ) else { continue }

                for case let url as URL in enumerator {
                    if Task.isCancelled { return }
                    guard url.pathExtension == "app",
                          let bundle = Bundle(url: url),
                          let bundleId = bundle.bundleIdentifier,
                          !seenBundleIDs.contains(bundleId) else { continue }

                    let name = fileManager.displayName(atPath: url.path)
                    let isBrowser = Self.isBrowser(bundle: bundle)
                    let app = SystemApp(id: bundleId, name: name, isBrowser: isBrowser, url: url)

                    fetchedApps.append(app)
                    seenBundleIDs.insert(bundleId)
                }
            }

            let sortedApps = fetchedApps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            await MainActor.run {
                defer { self.fetchTask = nil }
                guard !self.shouldDiscardFetch, !Task.isCancelled else { return }
                self.apps = sortedApps
                self.foundBundleIDs = seenBundleIDs
            }
        }
    }

    func releaseCachedApps() {
        shouldDiscardFetch = true
        fetchTask?.cancel()
        fetchTask = nil
        apps.removeAll(keepingCapacity: false)
        foundBundleIDs.removeAll(keepingCapacity: false)
        AppIconLoader.releaseCache()
    }

    nonisolated private static func isBrowser(bundle: Bundle?) -> Bool {
        guard let bundle = bundle, let urlTypes = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else { return false }

        return urlTypes.contains { type in
            if let schemes = type["CFBundleURLSchemes"] as? [String] {
                return schemes.contains("http") || schemes.contains("https")
            }
            return false
        }
    }
}