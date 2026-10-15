//
//  MenuBarVisibilityRestrictor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import AppKit
import os

@objc private protocol MBAssessmentModeConfigurationFactory {
    init(allowedSystemItems: NSArray, allowedBundleIdentifiers: NSArray)
}

@objc private protocol MBAssessmentModeAssertionMethods {
    func activate(withConfiguration configuration: AnyObject, completionHandler: @escaping (Error?) -> Void)
    func invalidate()
}

@MainActor
final class MenuBarVisibilityRestrictor {
    static let shared = MenuBarVisibilityRestrictor()

    private nonisolated static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private nonisolated static let syntheticClickTag: Int64 = 0x5341_5050_4D42
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "MenuBarRestriction")

    nonisolated static let isAvailable: Bool = {
        guard dlopen(frameworkPath, RTLD_NOW) != nil else { return false }
        return NSClassFromString("MBAssessmentModeAssertion") != nil
            && NSClassFromString("MBAssessmentModeConfiguration") != nil
    }()

    nonisolated static var canKeepOwnItemsVisible: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/")
    }

    nonisolated static var isUsable: Bool { isAvailable && canKeepOwnItemsVisible }

    private var assertion: NSObject?
    private var concealedKeys: Set<String> = []
    private var temporarilyAllowed: Set<String> = []
    private var bridgeSuspended = false
    private var appliedSignature: [String]?
    private var launchObserver: NSObjectProtocol?
    private var reapplyWorkItem: DispatchWorkItem?

    private var clockTapToken: GlobalEventTap.Token?
    private nonisolated let clockState = OSAllocatedUnfairLock(initialState: ClockState())
    private var bridgeGeneration = 0

    private struct ClockState {
        var frame: CGRect?
        var swallowingUp = false
    }

    private(set) var isRestricting = false

    private init() {}

    // MARK: - Public

    func conceal(_ keys: Set<String>) {
        concealedKeys = keys
        apply()
    }

    func allowTemporarily(_ key: String) {
        guard temporarilyAllowed.insert(key).inserted else { return }
        apply()
    }

    func endTemporaryAllowances() {
        guard !temporarilyAllowed.isEmpty else { return }
        temporarilyAllowed.removeAll()
        apply()
    }

    func releaseAll() {
        concealedKeys.removeAll()
        temporarilyAllowed.removeAll()
        apply()
    }

    // MARK: - Applying

    private func apply() {
        reapplyWorkItem?.cancel()
        reapplyWorkItem = nil

        let ownBundleID = Bundle.main.bundleIdentifier
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let concealed = concealedKeys.subtracting(temporarilyAllowed).subtracting([ownBundleID].compactMap { $0 })
        let concealedSystem = MenuBarSystemItem.allCases.filter { concealed.contains($0.key) }
        let concealsRunningApp = !running.isDisjoint(with: concealed)

        guard Self.isAvailable, !bridgeSuspended, concealsRunningApp || !concealedSystem.isEmpty else {
            invalidate()
            return
        }

        let systemItems = MenuBarSystemItem.allCases.filter { !concealed.contains($0.key) }.map(\.rawValue)
        let bundleIDs = running.subtracting(concealed).union([ownBundleID].compactMap { $0 }).sorted()
        let signature = systemItems.map(String.init) + ["|"] + bundleIDs
        guard signature != appliedSignature || assertion == nil else { return }

        guard let configurationClass = NSClassFromString("MBAssessmentModeConfiguration"),
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type else {
            invalidate()
            return
        }
        let factory = unsafeBitCast(configurationClass, to: MBAssessmentModeConfigurationFactory.Type.self)
        let configuration = factory.init(
            allowedSystemItems: systemItems.map { NSNumber(value: $0) } as NSArray,
            allowedBundleIdentifiers: bundleIDs as NSArray
        )

        let target = assertion ?? assertionClass.init()
        assertion = target
        appliedSignature = signature
        isRestricting = true
        unsafeBitCast(target, to: MBAssessmentModeAssertionMethods.self)
            .activate(withConfiguration: configuration) { error in
                guard let error else { return }
                Self.log.error("Visibility restriction failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let restrictor = MenuBarVisibilityRestrictor.shared
                        guard restrictor.assertion === target else { return }
                        restrictor.invalidate()
                    }
                }
            }

        startObservingLaunches()
        setClockBridgeArmed(true)
        refreshClockFrame(after: 0.6)
        didChange()
    }

    private func invalidate() {
        if let assertion {
            unsafeBitCast(assertion, to: MBAssessmentModeAssertionMethods.self).invalidate()
        }
        let changed = isRestricting
        assertion = nil
        appliedSignature = nil
        isRestricting = false
        stopObservingLaunches()
        setClockBridgeArmed(false)
        if changed { didChange() }
    }

    private func didChange() {
        MenuBarItemCatalog.shared.invalidate()
        NotificationCenter.default.post(name: .menuBarHidingStateDidChange, object: nil)
    }

    // MARK: - Newly launched apps

    private func startObservingLaunches() {
        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { MenuBarVisibilityRestrictor.shared.scheduleReapply() }
        }
    }

    private func stopObservingLaunches() {
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        reapplyWorkItem?.cancel()
        reapplyWorkItem = nil
    }

    private func scheduleReapply() {
        reapplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.apply() }
        }
        reapplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    // MARK: - Clock bridge

    private func setClockBridgeArmed(_ armed: Bool) {
        if armed, clockTapToken == nil {
            let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            clockTapToken = GlobalEventTap.shared.register(
                name: "MenuBarClockBridge",
                mask: CGEventMask(mask),
                priority: EventTapPriority.filter
            ) { [weak self] type, event in
                self?.handleClockTap(type: type, event: event) ?? .pass
            }
        } else if !armed, let clockTapToken {
            GlobalEventTap.shared.unregister(clockTapToken)
            self.clockTapToken = nil
            clockState.withLock { $0 = ClockState() }
        }
    }

    private nonisolated func handleClockTap(type: CGEventType, event: CGEvent) -> EventTapDecision {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticClickTag else { return .pass }
        let location = event.location
        let decision: EventTapDecision = clockState.withLock { state in
            switch type {
            case .leftMouseDown:
                guard let frame = state.frame, frame.contains(location) else { return .pass }
                state.swallowingUp = true
                return .swallow
            case .leftMouseUp where state.swallowingUp:
                state.swallowingUp = false
                return .swallow
            default:
                return .pass
            }
        }
        if type == .leftMouseDown, case .swallow = decision {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MenuBarVisibilityRestrictor.shared.bridgeClockClick(at: location) }
            }
        }
        return decision
    }

    private func bridgeClockClick(at location: CGPoint) {
        bridgeGeneration += 1
        let generation = bridgeGeneration
        bridgeSuspended = true
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Self.postClick(at: location)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.bridgeGeneration else { return }
                self.bridgeSuspended = false
                self.apply()
            }
        }
    }

    private nonisolated static func postClick(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: syntheticClickTag)
            event.post(tap: .cghidEventTap)
        }
    }

    private func refreshClockFrame(after delay: TimeInterval) {
        let state = clockState
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            guard let drawn = MenuBarAgentHost.drawnItems() else { return }
            let clock = drawn.first { $0.systemIdentifier.flatMap(MenuBarSystemItem.init(menuExtraIdentifier:)) == .clock }
            state.withLock { $0.frame = clock?.frame }
        }
    }
}