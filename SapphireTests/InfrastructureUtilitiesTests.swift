//
//  InfrastructureUtilitiesTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-14

import AppKit
import Combine
import Foundation
import struct SwiftUI.Path
import struct SwiftUI.RoundedRectangle
import XCTest
@testable import Sapphire

final class InfrastructureUtilitiesTests: XCTestCase {
    @MainActor
    func testNotchDragLocationOnlyPublishesDistinctCoordinates() {
        let state = NotchDragLocationState()
        var publications = 0
        let cancellable = state.objectWillChange.sink { publications += 1 }
        defer { cancellable.cancel() }

        let location = CGPoint(x: 120, y: 42)
        state.update(location)
        state.update(location)
        state.update(nil)
        state.update(nil)

        XCTAssertEqual(publications, 2)
        XCTAssertNil(state.location)
    }

    func testSettingsSidebarCatalogContainsEveryDestinationExactlyOnce() {
        let sidebarSections = SettingsSection.sidebarGroups.flatMap(\.sections)

        XCTAssertEqual(sidebarSections.count, SettingsSection.allCases.count)
        XCTAssertEqual(Set(sidebarSections.map(\.id)), Set(SettingsSection.allCases.map(\.id)))
        XCTAssertEqual(Set(sidebarSections.map(\.id)).count, sidebarSections.count)
    }

    @MainActor
    func testSettingsMutationPublishesOneObjectInvalidation() {
        let model = SettingsModel.shared
        let original = model.settings
        var invalidations = 0
        let cancellable = model.objectWillChange.sink { invalidations += 1 }
        defer {
            cancellable.cancel()
            model.settings = original
            model.flushPendingSave()
        }

        model.settings.menuBarOpacity = original.menuBarOpacity == 0.42 ? 0.43 : 0.42

        XCTAssertEqual(invalidations, 1)
    }

    @MainActor
    func testSettingsEditingSessionCoalescesRapidDraftChanges() async {
        let model = SettingsModel.shared
        let original = model.settings
        let session = SettingsEditingSession(model: model)
        var publications = 0
        let cancellable = model.$settings.dropFirst().sink { _ in publications += 1 }
        defer {
            cancellable.cancel()
            model.settings = original
            model.flushPendingSave()
        }

        for index in 0..<40 {
            session.settings.menuBarOpacity = 0.2 + Double(index) / 100
        }
        let expectedOpacity = session.settings.menuBarOpacity

        try? await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(model.settings.menuBarOpacity, expectedOpacity)
        XCTAssertEqual(publications, 1)
    }

    @MainActor
    func testSettingsEditingSessionDoesNotPublishWhenDraftReturnsToBaseline() async {
        let model = SettingsModel.shared
        let original = model.settings
        let session = SettingsEditingSession(model: model)
        var publications = 0
        let cancellable = model.$settings.dropFirst().sink { _ in publications += 1 }
        defer {
            cancellable.cancel()
            model.settings = original
            model.flushPendingSave()
        }

        session.settings.menuBarBlur.toggle()
        session.settings.menuBarBlur = original.menuBarBlur

        try? await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(model.settings, original)
    }

    @MainActor
    func testSettingsEditingSessionPreservesNewDraftAndConcurrentRuntimeChanges() async {
        let model = SettingsModel.shared
        let original = model.settings
        defer {
            model.settings = original
            model.flushPendingSave()
        }

        let session = SettingsEditingSession(model: model)
        let editedOpacity = original.menuBarOpacity == 0.314 ? 0.315 : 0.314
        let editedBlur = !original.menuBarBlur
        let runtimeHover = !original.showOnHover

        session.settings.menuBarOpacity = editedOpacity
        session.commitNow()

        session.settings.menuBarBlur = editedBlur
        model.settings.showOnHover = runtimeHover
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(session.settings.menuBarOpacity, editedOpacity)
        XCTAssertEqual(session.settings.menuBarBlur, editedBlur)
        XCTAssertEqual(session.settings.showOnHover, runtimeHover)

        session.commitNow()
        XCTAssertEqual(model.settings.menuBarOpacity, editedOpacity)
        XCTAssertEqual(model.settings.menuBarBlur, editedBlur)
        XCTAssertEqual(model.settings.showOnHover, runtimeHover)
    }

    @MainActor
    func testSettingsEditingSessionDiscardsQueuedExternalStateOlderThanCommit() async {
        let model = SettingsModel.shared
        let original = model.settings
        defer {
            model.settings = original
            model.flushPendingSave()
        }

        let session = SettingsEditingSession(model: model)
        let editedBlur = !original.menuBarBlur
        let runtimeHover = !original.showOnHover

        session.settings.menuBarBlur = editedBlur
        model.settings.showOnHover = runtimeHover
        session.commitNow()
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(session.settings.menuBarBlur, editedBlur)
        XCTAssertEqual(session.settings.showOnHover, runtimeHover)
        XCTAssertEqual(session.settings.value, model.settings)
    }

    @MainActor
    func testSettingsEditingSessionDoesNotMistakeEqualExternalRollbackForEcho() async {
        let model = SettingsModel.shared
        let original = model.settings
        defer {
            model.settings = original
            model.flushPendingSave()
        }

        let session = SettingsEditingSession(model: model)
        session.settings.menuBarBlur.toggle()
        session.commitNow()
        let firstCommit = model.settings

        session.settings.showOnHover.toggle()
        session.commitNow()
        XCTAssertNotEqual(model.settings, firstCommit)

        model.settings = firstCommit
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(session.settings.value, firstCommit)
        XCTAssertEqual(session.settings.value, model.settings)
    }

    func testHardwareNotchDetectionRequiresSafeAreaAndCentralCutout() {
        let leftArea = CGRect(x: 0, y: 0, width: 700, height: 32)
        let rightArea = CGRect(x: 900, y: 0, width: 700, height: 32)

        XCTAssertTrue(NotchConfiguration.hasHardwareNotch(
            safeAreaTop: 32,
            leftArea: leftArea,
            rightArea: rightArea
        ))
        XCTAssertFalse(NotchConfiguration.hasHardwareNotch(
            safeAreaTop: 0,
            leftArea: leftArea,
            rightArea: rightArea
        ))
        XCTAssertFalse(NotchConfiguration.hasHardwareNotch(
            safeAreaTop: 32,
            leftArea: nil,
            rightArea: nil
        ))
        XCTAssertFalse(NotchConfiguration.hasHardwareNotch(
            safeAreaTop: 32,
            leftArea: leftArea,
            rightArea: CGRect(x: leftArea.maxX, y: 0, width: 700, height: 32)
        ))
    }

    func testDevActivityParticipatesInLiveActivityOrdering() {
        XCTAssertTrue(LiveActivityType.allCases.contains(.devActivity))
        XCTAssertEqual(ActivityType(from: .devActivity), .devActivity)
        XCTAssertEqual(ActivityType.devActivity.toLiveActivityType(), .devActivity)
    }

    func testCapsLockLiveActivityParticipatesInOrderingAndIsEnabledByDefault() {
        XCTAssertTrue(Settings().capsLockLiveActivityEnabled)
        XCTAssertTrue(LiveActivityType.allCases.contains(.capsLock))
        XCTAssertEqual(ActivityType(from: .capsLock), .capsLock)
        XCTAssertEqual(ActivityType.capsLock.toLiveActivityType(), .capsLock)
    }

    func testExpandedContentSizeHonorsCustomNotchMinimums() {
        XCTAssertEqual(
            NotchSizing.expandedContentSize(
                contentSize: CGSize(width: 180, height: 40),
                minimumSize: CGSize(width: 260, height: 72)
            ),
            CGSize(width: 260, height: 72)
        )
        XCTAssertEqual(
            NotchSizing.expandedContentSize(
                contentSize: CGSize(width: 180, height: 40),
                minimumSize: CGSize(width: 120, height: 20),
                scale: 1.5
            ),
            CGSize(width: 270, height: 60)
        )
    }

    func testTransientLiveActivitiesCanSuppressHoverExpansion() {
        XCTAssertFalse(LiveActivityHoverExpansionPolicy.shouldSuppress(activity: .music))
        XCTAssertFalse(LiveActivityHoverExpansionPolicy.shouldSuppress(activity: .persistentBattery))
        XCTAssertFalse(LiveActivityHoverExpansionPolicy.shouldSuppress(activity: .weather))
        XCTAssertFalse(LiveActivityHoverExpansionPolicy.shouldSuppress(activity: .stats))
        XCTAssertFalse(LiveActivityHoverExpansionPolicy.shouldSuppress(activity: .devActivity))
        XCTAssertTrue(LiveActivityHoverExpansionPolicy.shouldSuppress(activity: .notification))
        XCTAssertTrue(LiveActivityHoverExpansionPolicy.shouldSuppress(activity: .audioSwitch))
    }

    func testSpotifyWidgetVisibilityCanHideClosedLoggedInSpotifySource() {
        XCTAssertFalse(MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: true,
            hideWhenNotPlaying: false,
            isPlaying: false,
            hidePausedSpotifyWhenIdle: false,
            isSpotifyPausedWithNoOtherPlayback: false,
            hideSpotifyWhenAppClosed: true,
            isLoggedIntoSpotify: true,
            isSpotifyOnlySource: true,
            isSpotifyAppRunning: false
        ))
        XCTAssertTrue(MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: true,
            hideWhenNotPlaying: false,
            isPlaying: false,
            hidePausedSpotifyWhenIdle: false,
            isSpotifyPausedWithNoOtherPlayback: false,
            hideSpotifyWhenAppClosed: true,
            isLoggedIntoSpotify: true,
            isSpotifyOnlySource: true,
            isSpotifyAppRunning: true
        ))
        XCTAssertTrue(MusicWidgetVisibilityPolicy.shouldShow(
            isEnabled: true,
            hideWhenNotPlaying: false,
            isPlaying: false,
            hidePausedSpotifyWhenIdle: false,
            isSpotifyPausedWithNoOtherPlayback: false,
            hideSpotifyWhenAppClosed: true,
            isLoggedIntoSpotify: true,
            isSpotifyOnlySource: false,
            isSpotifyAppRunning: false
        ))
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

    func testFullScreenHideAllIncludesTheHUD() {
        let behavior = FullScreenBehavior(activityVisibility: .hideAll)
        XCTAssertTrue(FullScreenActivityVisibilityPolicy.hides(.systemHUD, behavior: behavior, selectedActivityTypes: [:]))
        XCTAssertTrue(FullScreenActivityVisibilityPolicy.hides(.music, behavior: behavior, selectedActivityTypes: [:]))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.hides(.lockScreen, behavior: behavior, selectedActivityTypes: [:]))
    }

    func testFullScreenHidePersistentKeepsEvents() {
        let behavior = FullScreenBehavior(activityVisibility: .hidePersistent)
        XCTAssertTrue(FullScreenActivityVisibilityPolicy.hides(.music, behavior: behavior, selectedActivityTypes: [:]))
        XCTAssertTrue(FullScreenActivityVisibilityPolicy.hides(.persistentStats, behavior: behavior, selectedActivityTypes: [:]))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.hides(.systemHUD, behavior: behavior, selectedActivityTypes: [:]))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.hides(.capsLock, behavior: behavior, selectedActivityTypes: [:]))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.hides(.timer, behavior: behavior, selectedActivityTypes: [:], isAlerting: true))
    }

    func testFullScreenHideSelectedUsesActivityType() {
        let behavior = FullScreenBehavior(activityVisibility: .hideSelected)
        let selected = [LiveActivityType.music.rawValue: true]
        XCTAssertTrue(FullScreenActivityVisibilityPolicy.hides(.music, behavior: behavior, selectedActivityTypes: selected))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.hides(.weather, behavior: behavior, selectedActivityTypes: selected))
        XCTAssertFalse(FullScreenActivityVisibilityPolicy.hides(.music, behavior: FullScreenBehavior(), selectedActivityTypes: selected))
    }

    func testPerDisplayFullScreenBehaviorOverridesTheDefault() {
        var settings = Settings()
        settings.fullScreenActivityVisibility = .hidePersistent
        settings.perDisplayFullScreenBehavior["external"] = FullScreenBehavior(activityVisibility: .showAll, hideNotch: true)
        XCTAssertEqual(settings.resolvedFullScreenBehavior(forDisplayID: "built-in").activityVisibility, .hidePersistent)
        XCTAssertEqual(settings.resolvedFullScreenBehavior(forDisplayID: "external"), FullScreenBehavior(activityVisibility: .showAll, hideNotch: true))
    }

    func testFullScreenBehaviorWithoutHideLyricsKeepsHidingLyrics() throws {
        let saved = Data(#"{"activityVisibility":"showAll","hideNotch":true}"#.utf8)
        let behavior = try JSONDecoder().decode(FullScreenBehavior.self, from: saved)
        XCTAssertTrue(behavior.hideNotch)
        XCTAssertTrue(behavior.hideLyrics)
        XCTAssertTrue(Settings().hideLyricsInFullScreen)
    }

    func testApplyDisplaySettingsToAllDisplaysCopiesOneDisplay() {
        var settings = Settings()
        settings.perDisplayNotchSize["a"] = NotchSizeOverride(width: 220, height: 40)
        settings.perDisplayHideNotchWhenInactive["a"] = true
        settings.perDisplayFullScreenBehavior["a"] = FullScreenBehavior(activityVisibility: .hideAll, hideNotch: true, hideLyrics: false)
        settings.perDisplayFullScreenBehavior["b"] = FullScreenBehavior(activityVisibility: .showAll)

        settings.applyDisplaySettingsToAllDisplays(from: "a")

        for display in ["a", "b", "new"] {
            XCTAssertEqual(settings.resolvedNotchWidth(forDisplayID: display), 220)
            XCTAssertEqual(settings.resolvedNotchHeight(forDisplayID: display), 40)
            XCTAssertTrue(settings.resolvedHideNotchWhenInactive(forDisplayID: display))
            XCTAssertEqual(settings.resolvedFullScreenBehavior(forDisplayID: display), FullScreenBehavior(activityVisibility: .hideAll, hideNotch: true, hideLyrics: false))
        }
    }

    func testFloatingIslandIsAPillWhenShortAndRoundedWhenOpen() {
        let collapsed = CGRect(x: 0, y: 0, width: 180, height: 32)
        let pill = CustomNotchShape(cornerRadius: 16, bottomCornerRadius: 16, isFloatingIsland: true)
        XCTAssertEqual(pill.path(in: collapsed).description,
                       RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: collapsed).description)

        let open = CGRect(x: 0, y: 0, width: 640, height: 300)
        let card = CustomNotchShape(cornerRadius: 32, bottomCornerRadius: 32, isFloatingIsland: true)
        XCTAssertEqual(card.path(in: open).description,
                       RoundedRectangle(cornerRadius: 52, style: .continuous).path(in: open).description)
        let short = CGRect(x: 0, y: 0, width: 640, height: 120)
        XCTAssertEqual(card.path(in: short).description,
                       RoundedRectangle(cornerRadius: 32, style: .continuous).path(in: short).description)

        let preview = CustomNotchShape(cornerRadius: 0, bottomCornerRadius: 0, isFloatingIsland: true)
        XCTAssertEqual(preview.path(in: short).description,
                       RoundedRectangle(cornerRadius: CustomNotchShape.floatingIslandExpandedCornerRadius, style: .continuous).path(in: short).description)
    }

    func testIslandBarDropsOutOfTheCardOnlyOnceItHasGrown() {
        var shape = CustomNotchShape(cornerRadius: 32, bottomCornerRadius: 32, isFloatingIsland: true)
        shape.islandBarSize = CGSize(width: 300, height: NotchIslandBar.height)
        shape.islandBarGap = NotchIslandBar.gap
        shape.islandCollapsedHeight = 25
        XCTAssertEqual(shape.islandBarPresence(height: 25), 0)
        XCTAssertEqual(shape.islandBarPresence(height: 40), 0)
        XCTAssertEqual(shape.islandBarPresence(height: 200), 1)

        let open = CGRect(x: 0, y: 0, width: 500, height: 200)
        let path = shape.path(in: open)
        let barTop = open.maxY - NotchIslandBar.height
        XCTAssertTrue(path.contains(CGPoint(x: 250, y: barTop - NotchIslandBar.gap - 2)))
        XCTAssertFalse(path.contains(CGPoint(x: 250, y: barTop - NotchIslandBar.gap / 2)))
        XCTAssertTrue(path.contains(CGPoint(x: 250, y: barTop + NotchIslandBar.height / 2)))
        XCTAssertFalse(path.contains(CGPoint(x: 60, y: barTop + NotchIslandBar.height / 2)))

        let closed = CGRect(x: 0, y: 0, width: 140, height: 25)
        XCTAssertEqual(shape.path(in: closed).description,
                       RoundedRectangle(cornerRadius: 12.5, style: .continuous).path(in: closed).description)
    }

    func testSecondIslandRestyleReplacesOnlyEarlierDefaults() {
        var previous = Settings()
        previous.floatingIslandStyle = FloatingIslandStyle.previousDefaults[1]
        SettingsModel.adoptCurrentFloatingIslandStyle(&previous)
        XCTAssertEqual(previous.floatingIslandStyle, FloatingIslandStyle())

        var custom = Settings()
        var style = FloatingIslandStyle.previousDefaults[1]
        style.openPadding = 22
        custom.floatingIslandStyle = style
        SettingsModel.adoptCurrentFloatingIslandStyle(&custom)
        XCTAssertEqual(custom.floatingIslandStyle, style)
    }

    func testSatelliteBubbleBudsOffTheNotchEnd() {
        let layout = NotchSatelliteLayout(diameter: 32, gap: 6, centerY: 15)
        let outline = CGRect(x: 100, y: 0, width: 110, height: 30)
        let trailing = NotchSatelliteSlot(index: 0)
        let leading = NotchSatelliteSlot(index: 1)
        let tucked = layout.rect(slot: trailing, presence: 0, outline: outline)
        XCTAssertEqual(tucked.midX, outline.maxX - 16, accuracy: 0.001)
        XCTAssertEqual(tucked.width, 16, accuracy: 0.001)
        let apart = layout.rect(slot: trailing, presence: 1, outline: outline)
        XCTAssertEqual(apart.minX, outline.maxX + 6, accuracy: 0.001)
        XCTAssertEqual(apart.width, 32, accuracy: 0.001)
        XCTAssertEqual(layout.rect(slot: leading, presence: 1, outline: outline).maxX, outline.minX - 6, accuracy: 0.001)
        XCTAssertNil(layout.neck(slot: trailing, bubble: apart, anchor: outline))

        var shape = CustomNotchShape(cornerRadius: 15, bottomCornerRadius: 15, isFloatingIsland: true)
        shape.satelliteLayout = layout
        XCTAssertFalse(shape.path(in: outline).contains(CGPoint(x: apart.midX, y: apart.midY)))
        shape.satellites[trailing] = 1
        XCTAssertTrue(shape.path(in: outline).contains(CGPoint(x: apart.midX, y: apart.midY)))
        XCTAssertFalse(shape.path(in: outline).contains(CGPoint(x: outline.maxX + 3, y: 15)))
    }

    func testOuterSatellitesLineUpBeyondTheInnerOnes() {
        let layout = NotchSatelliteLayout(diameter: 32, gap: 6, centerY: 15)
        let outline = CGRect(x: 100, y: 0, width: 110, height: 30)
        XCTAssertEqual(NotchSatelliteSlot.allCases.map(\.isTrailing), [true, false, true, false, true])
        XCTAssertEqual(NotchSatelliteSlot.allCases.map(\.ring), [0, 0, 1, 1, 2])
        let inner = layout.restingRect(slot: NotchSatelliteSlot(index: 0), outline: outline)
        let outer = layout.restingRect(slot: NotchSatelliteSlot(index: 2), outline: outline)
        XCTAssertEqual(outer.minX, inner.maxX + 6, accuracy: 0.001)
        let budding = layout.rect(slot: NotchSatelliteSlot(index: 2), presence: 0, outline: outline)
        XCTAssertEqual(budding.midX, inner.maxX - 16, accuracy: 0.001)
        let farLeading = layout.restingRect(slot: NotchSatelliteSlot(index: 3), outline: outline)
        XCTAssertEqual(farLeading.maxX, outline.minX - 2 * 6 - 32, accuracy: 0.001)
        XCTAssertEqual(layout.reach(count: 1), 38, accuracy: 0.001)
        XCTAssertEqual(layout.reach(count: 5), 3 * 38, accuracy: 0.001)

        var shape = CustomNotchShape(cornerRadius: 15, bottomCornerRadius: 15, isFloatingIsland: true)
        shape.satelliteLayout = layout
        shape.satellites = .showing(5)
        let path = shape.path(in: outline)
        for slot in NotchSatelliteSlot.allCases {
            let rect = layout.restingRect(slot: slot, outline: outline)
            XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: rect.midY)), "slot \(slot.index)")
        }
        XCTAssertEqual(NotchSatellitePresence.showing(3).count, 3)
    }

    func testPathsWithDifferentElementsDoNotInterpolate() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 30)
        let a = Path(roundedRect: rect, cornerRadius: 10).cgPath
        let b = Path(roundedRect: rect.insetBy(dx: 5, dy: 0), cornerRadius: 10).cgPath
        XCTAssertTrue(NotchMorphGeometry.pathsInterpolate([a, b]))
        XCTAssertFalse(NotchMorphGeometry.pathsInterpolate([a, Path(rect).cgPath]))
    }

    func testNotchAppearanceCanDifferPerDisplay() {
        var settings = Settings()
        var external = settings.notchWidgetAppearance
        external.opacity = 0.4
        settings.perDisplayNotchWidgetAppearance["external"] = external

        XCTAssertEqual(settings.resolvedNotchWidgetAppearance(forDisplayID: "external").opacity, 0.4)
        XCTAssertEqual(settings.resolvedNotchWidgetAppearance(forDisplayID: "built-in"), settings.notchWidgetAppearance)
        XCTAssertEqual(settings.resolvedNotchLiveActivityAppearance(forDisplayID: "external"), settings.notchLiveActivityAppearance)
        XCTAssertTrue(settings.hasAppearanceOverride(forDisplayID: "external"))
        XCTAssertFalse(settings.hasAppearanceOverride(forDisplayID: "built-in"))

        settings.applyAppearanceToAllDisplays(from: "external")
        XCTAssertEqual(settings.notchWidgetAppearance.opacity, 0.4)
        XCTAssertTrue(settings.perDisplayNotchWidgetAppearance.isEmpty)
        XCTAssertEqual(settings.resolvedNotchWidgetAppearance(forDisplayID: "built-in").opacity, 0.4)
    }

    func testIslandBarKeepsHomeAndDropsTogglesFirst() {
        var settings = Settings()
        settings.notchButtonOrder = [.settings, .fileShelf, .notes, .spacer, .battery, .caffeine, .pin]
        settings.fileShelfIconEnabled = true
        settings.notesIconEnabled = true
        settings.batteryEstimatorEnabled = true
        settings.caffeinateEnabled = true
        settings.pinEnabled = true

        let roomy = NotchIslandBar.items(settings: settings, navigationDepth: 1, maxWidth: 1000)
        XCTAssertEqual(roomy, [.home, .separator, .button(.settings), .button(.fileShelf), .button(.notes),
                               .separator, .button(.battery), .button(.caffeine), .button(.pin)])
        XCTAssertEqual(NotchIslandBar.width(of: roomy), NotchIslandBar.padding * 2 + 7 * NotchIslandBar.itemWidth + 2 * NotchIslandBar.separatorWidth)

        let tight = NotchIslandBar.items(settings: settings, navigationDepth: 3, maxWidth: 200)
        XCTAssertEqual(tight.prefix(2), [.back, .home])
        XCTAssertFalse(tight.contains(.button(.pin)))
        XCTAssertLessThanOrEqual(NotchIslandBar.width(of: tight), 200)
        XCTAssertNotEqual(tight.last, .separator)
    }

    func testIslandBarSelectsTheTabForWhereThePanelIs() {
        XCTAssertEqual(NotchIslandBar.selection(for: [.defaultWidgets]), .home)
        XCTAssertEqual(NotchIslandBar.selection(for: [.defaultWidgets, .musicPlayer]), .home)
        XCTAssertEqual(NotchIslandBar.selection(for: [.defaultWidgets, .fileShelf]), .button(.fileShelf))
        XCTAssertEqual(NotchIslandBar.selection(for: [.defaultWidgets, .multiAudio, .musicDevices]), .button(.multiAudio))
        XCTAssertFalse(NotchIslandBar.showsBar(for: .dragActivated))
    }

    func testNotchlessNotchHasSmallRoundShouldersAndContinuousCorners() {
        let closed = CGRect(x: 0, y: 0, width: 180, height: 28)
        let path = CustomNotchShape(cornerRadius: 10, bottomCornerRadius: 10, isNotchless: true).path(in: closed)
        XCTAssertEqual(path.boundingRect.minX, closed.minX, accuracy: 0.001)
        XCTAssertEqual(path.boundingRect.maxX, closed.maxX, accuracy: 0.001)
        XCTAssertEqual(path.boundingRect.maxY, closed.maxY, accuracy: 0.001)
        XCTAssertTrue(path.contains(CGPoint(x: 3, y: 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 3, y: 3)))
        XCTAssertFalse(path.contains(CGPoint(x: 5, y: 14)))
        XCTAssertTrue(path.contains(CGPoint(x: 7, y: 14)))
        XCTAssertFalse(path.contains(CGPoint(x: 7, y: 27.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 22, y: 27.5)))

        let open = CGRect(x: 0, y: 0, width: 600, height: 150)
        let notchless = CustomNotchShape(cornerRadius: 40, bottomCornerRadius: 26, isNotchless: true).path(in: open)
        XCTAssertFalse(notchless.contains(CGPoint(x: 11, y: 40)))
        XCTAssertTrue(notchless.contains(CGPoint(x: 13, y: 40)))
        let hardware = CustomNotchShape(cornerRadius: 40, bottomCornerRadius: 40).path(in: open)
        XCTAssertFalse(hardware.contains(CGPoint(x: 13, y: 40)))
    }

    func testRedesignedFloatingIslandReplacesOnlyUntouchedDefaults() {
        var untouched = Settings()
        untouched.floatingIslandOnNotchlessDisplays = false
        untouched.floatingIslandTopOffset = FloatingIslandStyle.legacyTopOffset
        untouched.floatingIslandStyle = .legacyDefault
        SettingsModel.adoptRedesignedFloatingIsland(&untouched)
        XCTAssertTrue(untouched.floatingIslandOnNotchlessDisplays)
        XCTAssertEqual(untouched.floatingIslandTopOffset, Settings().floatingIslandTopOffset)
        XCTAssertEqual(untouched.floatingIslandStyle, FloatingIslandStyle())

        var movedIsland = Settings()
        movedIsland.floatingIslandOnNotchlessDisplays = false
        movedIsland.floatingIslandTopOffset = 12
        SettingsModel.adoptRedesignedFloatingIsland(&movedIsland)
        XCTAssertFalse(movedIsland.floatingIslandOnNotchlessDisplays)
        XCTAssertEqual(movedIsland.floatingIslandTopOffset, 12)

        var chosePerDisplay = Settings()
        chosePerDisplay.floatingIslandOnNotchlessDisplays = false
        chosePerDisplay.floatingIslandTopOffset = FloatingIslandStyle.legacyTopOffset
        chosePerDisplay.perDisplayFloatingIsland["external"] = false
        var customStyle = FloatingIslandStyle.legacyDefault
        customStyle.openPadding = 20
        chosePerDisplay.floatingIslandStyle = customStyle
        SettingsModel.adoptRedesignedFloatingIsland(&chosePerDisplay)
        XCTAssertFalse(chosePerDisplay.floatingIslandOnNotchlessDisplays)
        XCTAssertFalse(chosePerDisplay.resolvedFloatingIsland(forDisplayID: "external"))
        XCTAssertEqual(chosePerDisplay.floatingIslandStyle, customStyle)
    }

    func testApplyToAllCopiesFloatingIslandOnlyFromNotchlessDisplays() {
        var settings = Settings()
        settings.perDisplayFloatingIsland["external"] = true
        settings.perDisplayFloatingIslandTopOffset["external"] = 12

        var fromNotched = settings
        fromNotched.applyDisplaySettingsToAllDisplays(from: "built-in", includeFloatingIsland: false)
        XCTAssertTrue(fromNotched.resolvedFloatingIsland(forDisplayID: "external"))

        settings.applyDisplaySettingsToAllDisplays(from: "external", includeFloatingIsland: true)
        XCTAssertTrue(settings.resolvedFloatingIsland(forDisplayID: "another"))
        XCTAssertEqual(settings.resolvedFloatingIslandTopOffset(forDisplayID: "another"), 12)
    }

    func testFloatingIslandStyleDefaultsAndPerDisplayOverride() throws {
        let partial = try JSONDecoder().decode(FloatingIslandStyle.self, from: Data(#"{"sidePadding":14}"#.utf8))
        XCTAssertEqual(partial.sidePadding, 14)
        XCTAssertEqual(partial.centerGap, FloatingIslandStyle().centerGap)

        var settings = Settings()
        var custom = FloatingIslandStyle()
        custom.openCornerRadius = 50
        settings.perDisplayFloatingIslandStyle["external"] = custom
        XCTAssertEqual(settings.resolvedFloatingIslandStyle(forDisplayID: "external").openCornerRadius, 50)
        XCTAssertEqual(settings.resolvedFloatingIslandStyle(forDisplayID: "other"), FloatingIslandStyle())

        settings.applyDisplaySettingsToAllDisplays(from: "external", includeFloatingIsland: true)
        XCTAssertEqual(settings.resolvedFloatingIslandStyle(forDisplayID: "other").openCornerRadius, 50)
    }

    func testLegacyFullScreenSettingsMigrate() throws {
        func migrated(_ legacy: [String: Any]) throws -> FullScreenActivityVisibility {
            var dictionary = try XCTUnwrap(SettingsPersistence.encodeToDictionary(Settings()))
            dictionary.removeValue(forKey: "fullScreenActivityVisibility")
            dictionary.merge(legacy) { $1 }
            return try XCTUnwrap(SettingsPersistence.decodeFromDictionary(dictionary)).fullScreenActivityVisibility
        }
        XCTAssertEqual(try migrated(["hideLiveActivityInFullScreen": true]), .hideAll)
        XCTAssertEqual(try migrated(["hideLiveActivityInFullScreen": false, "hideActivitiesInFullScreen": ["music": true]]), .hideSelected)
        XCTAssertEqual(try migrated(["hideLiveActivityInFullScreen": false]), .showAll)
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

    func testFocusNotchBarItemPreferenceIsIndependentFromFocusWidget() throws {
        var settings = Settings()
        settings.focusSessionIconEnabled = false
        settings.focusSessionWidgetEnabled = true

        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

        XCTAssertFalse(decoded.focusSessionIconEnabled)
        XCTAssertTrue(decoded.focusSessionWidgetEnabled)
    }

    func testNewFeaturesAreDisabledByDefault() {
        let settings = Settings()

        XCTAssertFalse(settings.systemEnhanceDockPreviewsEnabled)
        XCTAssertFalse(settings.systemEnhanceWindowSwitcherEnabled)
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
        XCTAssertTrue(settings.automaticUpdateChecksEnabled)
        XCTAssertTrue(settings.automaticallyDownloadSapphireUpdates)
        XCTAssertTrue(settings.updateAvailableNotificationsEnabled)
        XCTAssertTrue(settings.showUpdateAvailableLiveActivity)
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
        XCTAssertTrue(settings.fileShelfDeviceDestinationsEnabled)
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
    func testNotchRuntimeStateOnlyBacksOffWhenEveryWindowIsIdle() {
        let state = NotchRuntimeState()
        let firstWindow = NSObject()
        let secondWindow = NSObject()
        let first = ObjectIdentifier(firstWindow)
        let second = ObjectIdentifier(secondWindow)

        XCTAssertFalse(state.shouldReduceBackgroundWork)

        state.register(source: first)
        XCTAssertTrue(state.shouldReduceBackgroundWork)

        state.register(source: second, isUserNear: true)
        XCTAssertFalse(state.shouldReduceBackgroundWork)

        state.update(source: second, isUserNear: false)
        XCTAssertTrue(state.shouldReduceBackgroundWork)

        state.update(source: first, isExpanded: true)
        XCTAssertFalse(state.shouldReduceBackgroundWork)

        state.update(source: first, isExpanded: false)
        XCTAssertTrue(state.shouldReduceBackgroundWork)

        state.unregister(source: first)
        state.unregister(source: second)
        XCTAssertFalse(state.shouldReduceBackgroundWork)
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