//
//  LifecycleRobustnessTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-08

import Combine
import CoreGraphics
import Foundation
import XCTest
@testable import Sapphire

final class LifecycleRobustnessTests: XCTestCase {

    // MARK: - Window registry demand

    func testWindowRegistryRunsOnlyWithAConsumerAndAccessibility() {
        var demand = SEWindowRegistryDemand()
        XCTAssertFalse(demand.shouldRun(accessibilityGranted: true))

        XCTAssertTrue(demand.acquire(.dockPreviews))
        XCTAssertFalse(demand.acquire(.dockPreviews), "acquiring twice is not a second reference")
        XCTAssertTrue(demand.shouldRun(accessibilityGranted: true))
        XCTAssertFalse(demand.shouldRun(accessibilityGranted: false))

        XCTAssertTrue(demand.acquire(.windowSwitcher))
        XCTAssertTrue(demand.release(.dockPreviews))
        XCTAssertTrue(demand.shouldRun(accessibilityGranted: true), "another consumer still holds it")

        XCTAssertTrue(demand.release(.windowSwitcher))
        XCTAssertFalse(demand.release(.windowSwitcher), "releasing an unheld consumer changes nothing")
        XCTAssertFalse(demand.shouldRun(accessibilityGranted: true))
    }

    // MARK: - System mutation journal

    func testRestoreOnlyWhenTheSystemStillShowsWhatSapphireSet() {
        let mute = SystemMutationRecord(kind: .lidAutoMute, appliedValue: true, target: "BuiltInSpeakers", recordedAt: Date())
        XCTAssertTrue(SystemMutationRestorePolicy.shouldRestore(mute, currentValue: true, currentTarget: "BuiltInSpeakers"))
        XCTAssertFalse(SystemMutationRestorePolicy.shouldRestore(mute, currentValue: false, currentTarget: "BuiltInSpeakers"),
                       "the user already unmuted")
        XCTAssertFalse(SystemMutationRestorePolicy.shouldRestore(mute, currentValue: true, currentTarget: "AirPods"),
                       "a different device is muted; that's not ours")
        XCTAssertFalse(SystemMutationRestorePolicy.shouldRestore(mute, currentValue: nil, currentTarget: "BuiltInSpeakers"))

        let lowPower = SystemMutationRecord(kind: .lowPowerMode, appliedValue: true, target: nil, recordedAt: Date())
        XCTAssertTrue(SystemMutationRestorePolicy.shouldRestore(lowPower, currentValue: true, currentTarget: nil))
        XCTAssertFalse(SystemMutationRestorePolicy.shouldRestore(lowPower, currentValue: false, currentTarget: nil))
    }

    func testJournalPersistsAcrossInstancesAndClears() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")

        let first = SystemMutationJournal(fileURL: url)
        XCTAssertTrue(first.pending.isEmpty)
        let record = SystemMutationRecord(kind: .lowPowerMode, appliedValue: true, target: nil, recordedAt: Date(timeIntervalSince1970: 100))
        first.record(record)

        let reloaded = SystemMutationJournal(fileURL: url)
        XCTAssertEqual(reloaded.pending, [record])

        reloaded.clear(.lowPowerMode)
        XCTAssertTrue(reloaded.pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "an empty journal leaves no file")
        XCTAssertTrue(SystemMutationJournal(fileURL: url).pending.isEmpty)
    }

    // MARK: - Startup marker

    func testStartupMarkerFlagsALaunchThatNeverGotHealthy() throws {
        let suite = "LifecycleRobustnessTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = StartupHealthMarker(defaults: defaults)
        XCTAssertEqual(first.beginLaunch(), .normal)

        let second = StartupHealthMarker(defaults: defaults)
        XCTAssertEqual(second.beginLaunch(), .recovery)
        XCTAssertEqual(second.consecutiveIncompleteLaunches, 1)

        let third = StartupHealthMarker(defaults: defaults)
        XCTAssertEqual(third.beginLaunch(), .recovery)
        XCTAssertEqual(third.consecutiveIncompleteLaunches, 2)
        third.markHealthy()

        let fourth = StartupHealthMarker(defaults: defaults)
        XCTAssertEqual(fourth.beginLaunch(), .normal)
        XCTAssertEqual(fourth.consecutiveIncompleteLaunches, 0)
        fourth.markCleanExit()

        XCTAssertEqual(StartupHealthMarker(defaults: defaults).beginLaunch(), .normal, "a clean quit is not a failed launch")
    }

    // MARK: - Event tap dispatch

    private func entry(
        _ id: UInt64,
        priority: Int,
        mask: CGEventMask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue),
        log: @escaping (UInt64) -> Void,
        decision: @escaping (CGEvent) -> EventTapDecision = { _ in .pass }
    ) -> EventTapDispatchEntry {
        EventTapDispatchEntry(id: id, name: "h\(id)", mask: mask, priority: priority) { _, event in
            log(id)
            return decision(event)
        }
    }

    func testDispatchRunsByPriorityThenRegistrationAndStopsAtFirstDecision() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        var calls: [UInt64] = []
        let entries = EventTapDispatchPlan.ordered([
            entry(3, priority: EventTapPriority.observer, log: { calls.append($0) }),
            entry(2, priority: EventTapPriority.shortcut, log: { calls.append($0) }),
            entry(1, priority: EventTapPriority.shortcut, log: { calls.append($0) }),
            entry(0, priority: EventTapPriority.filter, log: { calls.append($0) }),
        ])
        XCTAssertEqual(entries.map(\.id), [0, 1, 2, 3])

        guard case .pass = EventTapDispatchPlan.run(entries, type: .keyDown, event: event) else {
            return XCTFail("all handlers passed")
        }
        XCTAssertEqual(calls, [0, 1, 2, 3])

        calls.removeAll()
        let swallowing = EventTapDispatchPlan.ordered([
            entry(1, priority: EventTapPriority.shortcut, log: { calls.append($0) }, decision: { _ in .swallow }),
            entry(2, priority: EventTapPriority.observer, log: { calls.append($0) }),
        ])
        guard case .swallow = EventTapDispatchPlan.run(swallowing, type: .keyDown, event: event) else {
            return XCTFail("expected the shortcut to swallow")
        }
        XCTAssertEqual(calls, [1], "nothing after the deciding handler runs")
    }

    func testDispatchSkipsHandlersWhoseMaskExcludesTheEvent() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        var calls: [UInt64] = []
        let mouseMask = CGEventMask(1) << CGEventMask(CGEventType.leftMouseDown.rawValue)
        let entries = EventTapDispatchPlan.ordered([
            entry(1, priority: 100, mask: mouseMask, log: { calls.append($0) }, decision: { _ in .swallow }),
            entry(2, priority: 200, log: { calls.append($0) }),
        ])
        _ = EventTapDispatchPlan.run(entries, type: .keyDown, event: event)
        XCTAssertEqual(calls, [2])
        XCTAssertEqual(EventTapDispatchPlan.combinedMask(entries), mouseMask | (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)))
    }

    // MARK: - Accessibility trust transitions

    func testRevocationNeedsAConfirmingRead() {
        XCTAssertEqual(AccessibilityTrustTransition.onObservation(cached: true, observed: true), .none)
        XCTAssertEqual(AccessibilityTrustTransition.onObservation(cached: false, observed: true), .apply)
        XCTAssertEqual(AccessibilityTrustTransition.onObservation(cached: true, observed: false), .confirmRevocation)
        XCTAssertTrue(AccessibilityTrustTransition.onConfirmation(cached: true, observed: false))
        XCTAssertFalse(AccessibilityTrustTransition.onConfirmation(cached: true, observed: true), "the false read was spurious")
    }

    // MARK: - Permissions

    func testScreenRecordingIsNotDeniedWhileTheUserCanStillAnswer() {
        let now = Date()
        XCTAssertEqual(ScreenRecordingStatusPolicy.status(preflightGranted: true, requestedAt: nil, now: now), .granted)
        XCTAssertEqual(ScreenRecordingStatusPolicy.status(preflightGranted: false, requestedAt: nil, now: now), .notRequested)
        XCTAssertEqual(ScreenRecordingStatusPolicy.status(preflightGranted: false, requestedAt: now.addingTimeInterval(-5), now: now), .notRequested)
        XCTAssertEqual(ScreenRecordingStatusPolicy.status(preflightGranted: false, requestedAt: .distantPast, now: now), .denied)
    }

    @MainActor
    func testRepeatedPermissionChecksDoNotRepublishUnchangedStatuses() {
        let manager = PermissionsManager.shared
        manager.refreshLightweightStatuses()
        var publications = 0
        let cancellable = manager.objectWillChange.sink { publications += 1 }
        defer { cancellable.cancel() }
        manager.refreshLightweightStatuses()
        manager.refreshLightweightStatuses()
        XCTAssertEqual(publications, 0)
    }

    // MARK: - Launch at login

    func testLaunchAtLoginAdoptsSystemSettingsChangesInsteadOfReRegistering() {
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(wanted: true, state: .notRegistered, lastApplied: true, isUserChange: false, onboardingComplete: true),
            .adoptSystemState(false)
        )
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(wanted: false, state: .enabled, lastApplied: false, isUserChange: false, onboardingComplete: true),
            .adoptSystemState(true)
        )
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(wanted: true, state: .notRegistered, lastApplied: true, isUserChange: true, onboardingComplete: true),
            .register
        )
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(wanted: false, state: .enabled, lastApplied: true, isUserChange: false, onboardingComplete: true),
            .unregister
        )
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(wanted: true, state: .requiresApproval, lastApplied: nil, isUserChange: false, onboardingComplete: true),
            .none
        )
        XCTAssertEqual(
            LaunchAtLoginPolicy.action(wanted: true, state: .notRegistered, lastApplied: nil, isUserChange: true, onboardingComplete: false),
            .none
        )
    }

    // MARK: - Fan commands

    func testFanCommandSlotsClearOnlyTheirOwnCommand() {
        var slots = FanCommandSlots()
        let first = slots.reserve(0)
        let second = slots.reserve(0)
        slots.finish(0, commandID: first)
        XCTAssertTrue(slots.isRunning(0), "a superseded command must not clear its replacement's slot")
        slots.finish(0, commandID: second)
        XCTAssertFalse(slots.isRunning(0))

        _ = slots.reserve(1)
        _ = slots.reserve(2)
        XCTAssertFalse(slots.isEmpty)
        slots.cancelAll()
        XCTAssertTrue(slots.isEmpty, "cancelled commands don't linger")
    }

    // MARK: - Services registration

    func testServicesAreReRegisteredOnlyWhenTheyChange() {
        let services: [[String: Any]] = [["NSMessage": "takePhoto", "NSMenuItem": ["default": "Take Photo"]]]
        let a = ServicesRegistrationFingerprint.make(services: services, bundlePath: "/Applications/Sapphire.app")
        let b = ServicesRegistrationFingerprint.make(services: services, bundlePath: "/Applications/Sapphire.app")
        let moved = ServicesRegistrationFingerprint.make(services: services, bundlePath: "/Users/me/Sapphire.app")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, moved)
        XCTAssertFalse(ServicesRegistrationFingerprint.needsUpdate(stored: a, current: b))
        XCTAssertTrue(ServicesRegistrationFingerprint.needsUpdate(stored: nil, current: a))
        XCTAssertTrue(ServicesRegistrationFingerprint.needsUpdate(stored: a, current: nil))
    }
}