import XCTest
@testable import Sapphire

final class SettingsAssistantProtocolTests: XCTestCase {
    @MainActor
    func testLookupMetadataKeepsEnglishTitlePaneAndBooleanValues() throws {
        let entry = try XCTUnwrap(SettingsIndex.byKey["launchAtLogin"])
        for (isEnabled, expectedValue) in [(false, "off"), (true, "on")] {
            var settings = Settings()
            settings.launchAtLogin = isEnabled

            let output = SettingsAssistant.formatMatches([entry], settings: settings, lockedSections: [])

            XCTAssertEqual(output, "key=launchAtLogin | \"Launch at Login\" | pane: General | now: \(expectedValue) | allowed: on / off | Start Sapphire automatically when you log in to your Mac.")
        }
    }

    func testAllSectionsKeepOriginalEnglishMetadata() {
        XCTAssertEqual(Set(Self.originalPanes.map(\.section)), Set(SettingsSection.allCases))
        for pane in Self.originalPanes {
            XCTAssertEqual(pane.section.englishLabel, pane.label, pane.section.rawValue)
            XCTAssertEqual(pane.section.englishShortDescription, pane.description, pane.section.rawValue)
        }
    }

    @MainActor
    func testAssistantPaneCatalogKeepsOriginalEnglishMetadata() {
        let expected = Self.originalPanes
            .filter { $0.section != .overview && $0.section != .about }
            .map { "- \($0.label): \($0.description)" }
            .joined(separator: "\n")

        XCTAssertEqual(SettingsAssistant.paneCatalog, expected)
    }

    func testNavigationAndSettingTitlesRemainLocalized() throws {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let expected: (section: String, title: String, description: String)
        if language.hasPrefix("zh-Hans") {
            expected = ("通用", "登录时启动", "设置应用的基本行为、启动选项、动画和刘海区域控制。")
        } else if language.hasPrefix("zh-Hant") {
            expected = ("一般", "登入時啟動", "App 的核心行為、啟動選項、動畫與瀏海區域控制。")
        } else {
            expected = ("General", "Launch at Login", "Core app behavior, launch options, animations, and notch controls.")
        }
        let entry = try XCTUnwrap(SettingsIndex.byKey["launchAtLogin"])

        XCTAssertEqual(SettingsSection.general.label, expected.section)
        XCTAssertEqual(SettingsSection.general.shortDescription, expected.description)
        XCTAssertEqual(entry.displayTitle, expected.title)
    }

    @MainActor
    func testSubscriptionRequirementReflectsSuppliedAccessState() throws {
        let entry = try XCTUnwrap(SettingsIndex.entries.first { $0.section == .intelligence })
        let settings = Settings()
        let unlocked = SettingsAssistant.formatMatches([entry], settings: settings, lockedSections: [])
        let locked = SettingsAssistant.formatMatches([entry], settings: settings, lockedSections: [.intelligence])

        XCTAssertFalse(unlocked.contains(" | needs a Sapphire subscription"))
        XCTAssertTrue(locked.contains(" | needs a Sapphire subscription"))
        XCTAssertEqual(locked.replacingOccurrences(of: " | needs a Sapphire subscription", with: ""), unlocked)
    }

    private static let originalPanes: [(section: SettingsSection, label: String, description: String)] = [
        (.overview, "Overview", "Ask about any setting, get suggestions, and change the most-used settings."),
        (.general, "General", "Core app behavior, launch options, animations, and notch controls."),
        (.systemEnhance, "System Enhance", "Window previews, app switching, dock controls, and display behavior."),
        (.apps, "Apps", "Review installed applications, inspect bundle details, and safely move unwanted apps to Trash."),
        (.storage, "Storage", "Find large folders and reclaim space with transparent, user-approved cleanup."),
        (.widgets, "Widgets", "Choose which widgets appear in the notch and how they are ordered."),
        (.liveActivities, "Live Activities", "Control which live activities can surface and auto-expand in the notch."),
        (.appActivities, "App Activities", "Live activities and controls for Zoom, Google Meet, Teams, Slack, Discord, FaceTime, recorders and more."),
        (.fileProgress, "File Progress", "Download, copy and AirDrop progress per app — Safari, Chrome, Edge, Firefox, Finder and others."),
        (.appearance, "Appearance", "Tune the notch look, materials, colors, and layout styling."),
        (.lockScreen, "Lock Screen", "Configure Sapphire content and behavior while your Mac is locked."),
        (.bluetoothUnlock, "Authentication", "Set up proximity-based authentication and trusted device behavior."),
        (.shortcuts, "Shortcuts", "Manage quick actions and shortcut surfaces shown in Sapphire."),
        (.keyboardShortcuts, "Keyboard Shortcuts", "Reference page listing every keyboard shortcut in Sapphire — global hotkeys, snap zones, and in-app shortcuts."),
        (.snapZones, "Snap Zones", "Configure window snapping behavior, layouts, and zone actions."),
        (.audio, "Audio", "Audio adjustments, EQ, and per-app volume adjustments."),
        (.battery, "Battery", "Battery widgets, history, charging preferences, and power-related controls."),
        (.bluetooth, "Bluetooth", "Bluetooth device integrations, visibility, and connection behavior."),
        (.hud, "HUD", "Heads-up display overlays for volume, brightness, keyboard, and media feedback."),
        (.notifications, "Notifications", "Choose which system notifications Sapphire mirrors or enhances."),
        (.nearbyShare, "Nearby Share", "Nearby sharing preferences, transfers, and device discovery options."),
        (.continuity, "Continuity", "Pair an Android phone for clipboard, notifications, media, battery, and Instant Hotspot."),
        (.fileShelf, "File Shelf", "Manage temporary file storage, drag targets, and shelf behavior."),
        (.notes, "Notes", "Quick notes widget, click-to-expand behavior, and notch bar access."),
        (.clipboard, "Clipboard", "Clipboard history, monitoring, and notch clipboard shortcuts."),
        (.emoji, "Emoji", "Slack-style emoji typing with :shortcode: suggestions and a full search picker."),
        (.mouse, "Mouse", "Mouse and trackpad scroll, acceleration, and button customization."),
        (.monitoring, "Monitoring", "Menu bar readouts and notifications for CPU, memory, disk, and network."),
        (.devActivity, "Dev Activity", "Track AI agents, builds, and terminal commands, and keep the Mac awake while they run."),
        (.archives, "Archives & DMG", "Extract ZIP, RAR, 7-Zip, TAR, and other archives — or auto-mount and install disk images (DMGs) — from anywhere."),
        (.mirror, "Mirror", "Mirror widget showing live camera feed, with expandable fullscreen view."),
        (.caffeine, "Caffeinate", "Keep your Mac awake, clamshell sleep behavior, and lid-angle display controls."),
        (.music, "Music", "Music widget sources, playback controls, and media integrations."),
        (.weather, "Weather", "Weather widget data sources, units, and location-based behavior."),
        (.calendar, "Calendar", "Calendar and reminder integrations shown in widgets and live activities."),
        (.eyeBreak, "Eye Break", "Break reminders, timing, and focus nudges for healthier screen habits."),
        (.focusSession, "Focus Sessions", "Session-style Focus Profiles with timers, app/website blocking, social filters, triggers, and cross-device sync."),
        (.appLock, "App Lock", "Lock apps behind Touch ID or password — blur overlays, idle/sleep auto-lock, and auto-close."),
        (.intelligence, "Blip", "Sapphire Blip — Mac agent with memory, skills, tools, and computer use."),
        (.sports, "Sports", "Sports widget settings, favorite teams selection, and scoreboard configurations."),
        (.finance, "Finance", "Stock market ticker configurations, favorite stocks, and trendline visualizations."),
        (.dockLayouts, "Dock", "Save Dock layouts as presets and switch between them with a click or hotkey."),
        (.mediaOptimizer, "Media Optimizer", "Automatically shrink images, compress media, and extract text with OCR."),
        (.about, "About", "App version details, Sapphire updates, release channels, credits, links, and project information."),
    ]
}
