//
//  InfrastructureUtilitiesTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import AppKit
import Combine
import Foundation
import XCTest
@testable import Sapphire

final class InfrastructureUtilitiesTests: XCTestCase {
    func testDevActivityParticipatesInLiveActivityOrdering() {
        XCTAssertTrue(LiveActivityType.allCases.contains(.devActivity))
        XCTAssertEqual(ActivityType(from: .devActivity), .devActivity)
        XCTAssertEqual(ActivityType.devActivity.toLiveActivityType(), .devActivity)
    }

    @MainActor
    func testRuntimeBrightnessDrivesXDRWithoutInvalidatingSettingsObservers() {
        let model = SettingsModel.shared
        let manager = BrightnessManager.shared
        let originalBrightness = model.brightness
        let originalTechnique = manager.brightnessTechnique
        let changedBrightness: Float = originalBrightness == 1.234 ? 1.235 : 1.234
        let technique = BrightnessTechniqueSpy()
        var settingsInvalidations = 0

        manager.brightnessTechnique = technique
        let settingsCancellable = model.objectWillChange.sink {
            settingsInvalidations += 1
        }
        defer {
            model.brightness = originalBrightness
            manager.brightnessTechnique = originalTechnique
            withExtendedLifetime(settingsCancellable) {}
        }

        model.brightness = changedBrightness

        XCTAssertEqual(technique.adjustmentCount, 1)
        XCTAssertEqual(settingsInvalidations, 0)
    }

    @MainActor
    func testXDROverlayCanJoinFullScreenSpaces() {
        let window = OverlayWindow()
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        window.close()
    }

    func testFullScreenActivityVisibilityIsScopedToOneDisplay() {
        let fullScreenDisplays: Set<CGDirectDisplayID> = [101]

        XCTAssertTrue(FullScreenActivityVisibilityPolicy.shouldHide(
            activity: .music,
            on: 101,
            fullScreenDisplayIDs: fullScreenDisplays,
            hideAll: true,
            hiddenActivityTypes: [:]
        ))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.shouldHide(
            activity: .music,
            on: 202,
            fullScreenDisplayIDs: fullScreenDisplays,
            hideAll: true,
            hiddenActivityTypes: [:]
        ))
    }

    func testSpecificFullScreenActivityVisibilityUsesActivityType() {
        let hiddenTypes = [LiveActivityType.music.rawValue: true]

        XCTAssertTrue(FullScreenActivityVisibilityPolicy.shouldHide(
            activity: .music,
            on: 101,
            fullScreenDisplayIDs: [101],
            hideAll: false,
            hiddenActivityTypes: hiddenTypes
        ))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.shouldHide(
            activity: .weather,
            on: 101,
            fullScreenDisplayIDs: [101],
            hideAll: false,
            hiddenActivityTypes: hiddenTypes
        ))
    }

    @MainActor
    func testDynamicFocusWindowMouseEventHandlingIsDirect() {
        let window = makeDynamicFocusWindow(displayID: 101)
        defer { window.close() }

        window.setMouseEventHandlingEnabled(true)
        XCTAssertFalse(window.ignoresMouseEvents)

        window.setMouseEventHandlingEnabled()
        XCTAssertTrue(window.ignoresMouseEvents)
    }

    @MainActor
    func testNotchHoverMonitorOnlyRegistersMouseEventsWhilePointerIsInside() {
        let window = makeDynamicFocusWindow(displayID: 101)
        let monitor = NotchHoverMonitor()
        monitor.start(
            window: window,
            handlers: NotchHoverMonitorHandlers(
                onPointerEvent: {},
                onMouseDrag: { _, _ in },
                onMouseDragEnded: { _ in },
                onFileDrag: { _, _ in },
                onFileDragEnded: { _, _ in },
                onFileDrop: { _, _ in false }
            )
        )
        defer {
            monitor.stop()
            window.close()
        }

        XCTAssertFalse(monitor.hasActiveMouseEventMonitors)
        XCTAssertFalse(monitor.isHoverProbeListeningForPointer)

        monitor.update(hoverRect: CGRect(x: 0, y: 0, width: 100, height: 40), pointerIsInside: false)
        XCTAssertFalse(monitor.hasActiveMouseEventMonitors)
        XCTAssertTrue(monitor.isHoverProbeListeningForPointer)

        monitor.update(hoverRect: CGRect(x: 0, y: 0, width: 100, height: 40), pointerIsInside: true)
        XCTAssertTrue(monitor.hasActiveMouseEventMonitors)
        XCTAssertFalse(monitor.isHoverProbeListeningForPointer)

        monitor.update(hoverRect: CGRect(x: 0, y: 0, width: 100, height: 40), pointerIsInside: false)
        XCTAssertFalse(monitor.hasActiveMouseEventMonitors)
        XCTAssertTrue(monitor.isHoverProbeListeningForPointer)
    }

    @MainActor
    private func makeDynamicFocusWindow(displayID: CGDirectDisplayID) -> DynamicFocusWindow {
        let window = DynamicFocusWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.displayID = displayID
        return window
    }

    func testDebouncerFlushExecutesPendingActionExactlyOnce() {
        let queue = DispatchQueue(label: "InfrastructureUtilitiesTests.debouncer")
        let debouncer = Debouncer(delay: 0.05, queue: queue)
        let counter = LockedCounter()

        debouncer.debounce {
            counter.increment()
        }
        debouncer.flush()

        let settled = expectation(description: "scheduled work had time to drain")
        queue.asyncAfter(deadline: .now() + 0.15) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)

        XCTAssertEqual(counter.value, 1)
    }

    func testDebouncerOnlyExecutesNewestAction() {
        let queue = DispatchQueue(label: "InfrastructureUtilitiesTests.latest")
        let debouncer = Debouncer(delay: 0.03, queue: queue)
        let values = LockedValues<Int>()

        debouncer.debounce { values.append(1) }
        debouncer.debounce { values.append(2) }

        let settled = expectation(description: "debounce interval elapsed")
        queue.asyncAfter(deadline: .now() + 0.12) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)

        XCTAssertEqual(values.value, [2])
    }

    func testOlderSettingsPayloadKeepsCompatibleValuesAndDropsOnlyInvalidOnes() throws {
        let encoded = try JSONEncoder().encode(Settings())
        var dictionary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        dictionary.removeValue(forKey: "hapticFeedbackEnabled")
        dictionary["showOnHover"] = false
        dictionary["volumesliderstep"] = "not-an-integer"

        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let recovered = try SettingsBackupDocument.decodePayload(from: data).settings

        XCTAssertFalse(recovered.showOnHover)
        XCTAssertEqual(recovered.volumesliderstep, Settings().volumesliderstep)
        XCTAssertEqual(recovered.hapticFeedbackEnabled, Settings().hapticFeedbackEnabled)
    }

    func testNewFeaturesAreDisabledByDefault() {
        let settings = Settings()

        XCTAssertFalse(settings.systemEnhanceDockPreviewsEnabled)
        XCTAssertFalse(settings.systemEnhanceAltTabEnabled)
        XCTAssertFalse(settings.systemEnhanceCalendarIntegrationEnabled)
        XCTAssertFalse(settings.systemEnhanceCompactPreviewEnabled)
        XCTAssertFalse(settings.systemEnhanceEnhancedPreviewsEnabled)
        XCTAssertFalse(settings.systemEnhancePasteAsPlainTextEnabled)
        XCTAssertFalse(settings.systemEnhanceHingeAnimationEnabled)
        XCTAssertFalse(settings.systemEnhanceDockClicksEnabled)
        XCTAssertFalse(settings.systemEnhanceAutoQuitEnabled)
        XCTAssertFalse(settings.systemEnhanceQuitProtectionEnabled)
        XCTAssertFalse(settings.systemEnhanceGreenMaximizeEnabled)
        XCTAssertFalse(settings.dockLayoutsEnabled)
        XCTAssertFalse(settings.mediaToolsAutoOptimizeClipboard)
        XCTAssertFalse(settings.mediaToolsShowShelfActions)
        XCTAssertFalse(settings.mediaToolsOCRShortcutEnabled)
        XCTAssertFalse(settings.automaticUpdateChecksEnabled)
        XCTAssertFalse(settings.automaticallyDownloadSapphireUpdates)
        XCTAssertFalse(settings.updateAvailableNotificationsEnabled)
        XCTAssertFalse(settings.showUpdateAvailableLiveActivity)
        XCTAssertFalse(settings.installedAppUpdatesEnabled)
        XCTAssertFalse(settings.installedAppUpdateNotificationsEnabled)
        XCTAssertFalse(settings.clipboardPickerEnabled)
        XCTAssertFalse(settings.clipboardAutoClearEnabled)
        XCTAssertFalse(settings.clipboardCleanURLEnabled)
        XCTAssertFalse(settings.clipboardFinderCutPasteEnabled)
        XCTAssertFalse(settings.clipboardFinderF2RenameEnabled)
        XCTAssertFalse(settings.snippetsEnabled)
        XCTAssertFalse(settings.emojiEnabled)
        XCTAssertFalse(settings.mouseControlEnabled)
        XCTAssertFalse(settings.monitoringMenuBarReadoutsEnabled)
        XCTAssertFalse(settings.monitoringAlertsEnabled)
        XCTAssertFalse(settings.archiveExtractorEnabled)
        XCTAssertFalse(settings.dmgInstallerEnabled)
        XCTAssertFalse(settings.timerWidgetEnabled)
        XCTAssertFalse(settings.storageWidgetEnabled)
        XCTAssertFalse(settings.continuityEnabled)
        XCTAssertFalse(settings.fileShelfAirDropDestinationEnabled)
        XCTAssertFalse(settings.fileShelfDeviceDestinationsEnabled)
        XCTAssertFalse(settings.caffeinateAutoDuringTasks)
        XCTAssertFalse(settings.devActivityEnabled)
        XCTAssertFalse(settings.menuBarEnabled)
        XCTAssertFalse(settings.menuBarProfilesEnabled)
        XCTAssertFalse(settings.showOnlyRunningAppsInDock)
    }

    func testEventHandlingSnapshotPreservesHotPathPreferences() {
        var settings = Settings()
        settings.clipboardFinderCutPasteEnabled = true
        settings.snippetsEnabled = true
        settings.snippetsList = [SnippetEntry(trigger: ":ship", replacement: "")]
        settings.mouseControlEnabled = true
        settings.mouseScrollSpeed = 1.75
        settings.mouseExcludedAppBundleIDs = ["com.example.Game"]
        settings.systemEnhanceDockClicksEnabled = true
        settings.systemEnhanceDockClicksAllAppsEnabled = false
        settings.systemEnhanceDockClicksSelectedApps = ["com.apple.Safari"]
        settings.systemEnhanceDockClickAction = .cycle
        settings.systemEnhanceQuitProtectionMode = .doublePress

        let snapshot = EventHandlingSettingsSnapshot(settings: settings)

        XCTAssertTrue(snapshot.clipboardFinderCutPasteEnabled)
        XCTAssertEqual(snapshot.snippetByTrigger[":ship"]?.replacement, "")
        XCTAssertEqual(snapshot.mouseScrollSpeed, 1.75)
        XCTAssertEqual(snapshot.mouseExcludedAppBundleIDs, ["com.example.Game"])
        XCTAssertFalse(snapshot.systemEnhanceDockClicksAllAppsEnabled)
        XCTAssertEqual(snapshot.systemEnhanceDockClicksSelectedApps, ["com.apple.Safari"])
        XCTAssertTrue(snapshot.isDockClickEnabled(for: "com.apple.Safari"))
        XCTAssertFalse(snapshot.isDockClickEnabled(for: "com.apple.TextEdit"))
        XCTAssertEqual(snapshot.systemEnhanceDockClickAction, .cycle)
        XCTAssertEqual(snapshot.systemEnhanceQuitProtectionMode, .doublePress)
        XCTAssertLessThan(
            MemoryLayout<EventHandlingSettingsSnapshot>.size * 5,
            MemoryLayout<Settings>.size
        )
    }

    func testDockClicksEnableAllAppsByDefault() {
        var settings = Settings()
        let snapshot = EventHandlingSettingsSnapshot(settings: settings)

        XCTAssertTrue(settings.systemEnhanceDockClicksAllAppsEnabled)
        XCTAssertTrue(snapshot.isDockClickEnabled(for: "com.example.NewlyInstalledApp"))

        settings.systemEnhanceDockClicksExcludedApps = ["com.example.ExcludedApp"]
        let snapshotWithExclusion = EventHandlingSettingsSnapshot(settings: settings)
        XCTAssertFalse(snapshotWithExclusion.isDockClickEnabled(for: "com.example.ExcludedApp"))
        XCTAssertTrue(snapshotWithExclusion.isDockClickEnabled(for: "com.example.NewlyInstalledApp"))
    }

    func testLegacyDockClickAllowlistRemainsAnAllowlist() throws {
        let encoded = try JSONEncoder().encode(Settings())
        var dictionary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        dictionary.removeValue(forKey: "systemEnhanceDockClicksAllAppsEnabled")
        dictionary["systemEnhanceDockClicksSelectedApps"] = ["com.apple.Safari"]

        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let recovered = try SettingsBackupDocument.decodePayload(from: data).settings

        XCTAssertFalse(recovered.systemEnhanceDockClicksAllAppsEnabled)
        XCTAssertEqual(recovered.systemEnhanceDockClicksSelectedApps, ["com.apple.Safari"])
    }

    func testEventHandlingSnapshotOnlyRebuildsForRelevantSettings() {
        let original = Settings()
        var visualChange = original
        visualChange.menuBarOpacity = 0.42
        XCTAssertTrue(EventHandlingSettingsSnapshot.hasSameInputs(original, visualChange))

        var mouseChange = original
        mouseChange.mouseScrollSpeed += 0.25
        XCTAssertFalse(EventHandlingSettingsSnapshot.hasSameInputs(original, mouseChange))

        var snippetChange = original
        snippetChange.snippetsList.append(SnippetEntry(trigger: ":fast", replacement: "Done"))
        XCTAssertFalse(EventHandlingSettingsSnapshot.hasSameInputs(original, snippetChange))

        var dockClickScopeChange = original
        dockClickScopeChange.systemEnhanceDockClicksAllAppsEnabled = false
        XCTAssertFalse(EventHandlingSettingsSnapshot.hasSameInputs(original, dockClickScopeChange))
    }

    @MainActor
    func testAppIconCacheKeepsRequestedSizesIndependent() {
        AppIconLoader.releaseCache()
        defer { AppIconLoader.releaseCache() }

        let appURL = Bundle.main.bundleURL
        let small = AppIconLoader.icon(for: appURL, maxDimension: 8)
        let larger = AppIconLoader.icon(for: appURL, maxDimension: 128)

        XCTAssertLessThanOrEqual(small.size.width, 8)
        XCTAssertGreaterThan(larger.size.width, small.size.width)
    }
}

@MainActor
private final class BrightnessTechniqueSpy: BrightnessTechnique {
    private(set) var adjustmentCount = 0

    override func adjustBrightness() {
        adjustmentCount += 1
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedValues<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    var value: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }
}