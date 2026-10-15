//
//  MenuBarInteractionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Cocoa
import Combine
import os

@MainActor
final class MenuBarInteractionManager {
    static let shared = MenuBarInteractionManager()

    private struct Configuration: Equatable {
        let showOnClick: Bool
        let showOnHover: Bool
        let showOnScroll: Bool
    }

    // MARK: - Monitors
    private var clickToken: UUID?
    private var hoverProbe: MenuBarHoverProbe?
    private var hoverRevealTimer: Timer?
    private var scrollTapToken: GlobalEventTap.Token?

    // MARK: - State
    public var isMonitoring = false
    private var suspension = MenuBarSuspensionSources()
    private var isSuspended: Bool { suspension.isSuspended }
    private var disabledUntil: Date?
    private var lastRevealClick: (time: TimeInterval, location: CGPoint)?
    private var configuration = Configuration(showOnClick: false, showOnHover: false, showOnScroll: false)
    private var cancellables = Set<AnyCancellable>()

    private nonisolated let scrollState = OSAllocatedUnfairLock(initialState: ScrollState())

    private struct ScrollState {
        var accumulated: CGFloat = 0
        var cooldownUntil: UInt64 = 0
    }

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        MenuBarItemCatalog.shared.start()
        if cancellables.isEmpty {
            SettingsModel.shared.$settings
                .map { Configuration(showOnClick: $0.showOnClick, showOnHover: $0.showOnHover, showOnScroll: $0.showOnScroll) }
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] configuration in
                    guard let self, self.isMonitoring else { return }
                    self.updateMonitors(configuration)
                }
                .store(in: &cancellables)
        }
        let settings = SettingsModel.shared.settings
        updateMonitors(Configuration(showOnClick: settings.showOnClick, showOnHover: settings.showOnHover, showOnScroll: settings.showOnScroll))
    }

    func setSuspended(_ suspended: Bool, by source: ObjectIdentifier) {
        guard suspension.set(suspended, for: source) else { return }
        if isSuspended { cancelHoverReveal() }
        updateScrollTapEnabled()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stopClickMonitoring()
        stopHoverMonitoring()
        stopScrollMonitoring()
        cancellables.removeAll()
    }

    private func updateMonitors(_ configuration: Configuration) {
        self.configuration = configuration

        if configuration.showOnClick && clickToken == nil {
            startClickMonitoring()
        } else if !configuration.showOnClick && clickToken != nil {
            stopClickMonitoring()
        }

        let needsProbe = configuration.showOnHover || configuration.showOnScroll
        if needsProbe && hoverProbe == nil {
            startHoverMonitoring()
        } else if !needsProbe && hoverProbe != nil {
            stopHoverMonitoring()
        }
        if !configuration.showOnHover { cancelHoverReveal() }

        if configuration.showOnScroll && scrollTapToken == nil {
            startScrollMonitoring()
        } else if !configuration.showOnScroll && scrollTapToken != nil {
            stopScrollMonitoring()
        }
    }

    func temporarilyDisable(for duration: TimeInterval) {
        disabledUntil = Date().addingTimeInterval(duration)
    }

    private var revealsAllowed: Bool {
        guard isMonitoring, !isSuspended, Date() >= (disabledUntil ?? .distantPast) else { return false }
        return (NSApp.delegate as? AppDelegate)?.statusBarController?.isZenModeActive != true
    }

    // MARK: - Click Monitoring

    private func startClickMonitoring() {
        guard clickToken == nil else { return }

        clickToken = GlobalInputMonitor.shared.onLeftMouseDown { [weak self] in
            guard let self, self.revealsAllowed else { return }
            let location = NSEvent.mouseLocation
            guard self.isLocationInMenuBar(location),
                  let axPoint = AX.axPoint(fromCocoaPoint: location) else { return }
            if self.isSecondClickOfDoubleClick(at: location) {
                self.lastRevealClick = nil
                (NSApp.delegate as? AppDelegate)?.statusBarController?.showAlwaysHiddenSection()
                return
            }
            self.revealIfEmptyMenuBarSpace(at: axPoint, cocoaPoint: location)
        }
    }

    private func stopClickMonitoring() {
        if let token = clickToken {
            GlobalInputMonitor.shared.remove(token)
            clickToken = nil
        }
    }

    private func revealIfEmptyMenuBarSpace(at axPoint: CGPoint, cocoaPoint: CGPoint) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = MenuBarHitTest.classify(axPoint: axPoint)
            guard result != .item else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.revealsAllowed,
                          MenuBarHitTest.isEmptySpace(result, axPoint: axPoint, cocoaPoint: cocoaPoint) else { return }
                    self.lastRevealClick = (ProcessInfo.processInfo.systemUptime, cocoaPoint)
                    self.showHiddenItems()
                }
            }
        }
    }

    private func isSecondClickOfDoubleClick(at location: CGPoint) -> Bool {
        guard SettingsModel.shared.current.showAlwaysHiddenOnDoubleClick,
              let last = lastRevealClick else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - last.time
        return elapsed <= NSEvent.doubleClickInterval
            && abs(location.x - last.location.x) <= 6
            && abs(location.y - last.location.y) <= 6
    }

    // MARK: - Hover Monitoring

    private func startHoverMonitoring() {
        guard hoverProbe == nil else { return }
        let probe = MenuBarHoverProbe()
        hoverProbe = probe
        probe.start { [weak self] isInside in
            self?.handleMenuBarHoverChange(isInside)
        }
    }

    private func stopHoverMonitoring() {
        hoverProbe?.stop()
        hoverProbe = nil
        cancelHoverReveal()
        updateScrollTapEnabled()
    }

    private func handleMenuBarHoverChange(_ isInside: Bool) {
        updateScrollTapEnabled()
        guard configuration.showOnHover, isMonitoring, !isSuspended else { return }
        if isInside {
            scheduleHoverReveal()
        } else {
            cancelHoverReveal()
        }
    }

    private var isMouseButtonHeld: Bool { NSEvent.pressedMouseButtons != 0 }

    private func scheduleHoverReveal() {
        cancelHoverReveal()
        guard revealsAllowed, !isMouseButtonHeld else { return }

        let delay = max(0, SettingsModel.shared.current.showOnHoverDelay)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireHoverReveal() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverRevealTimer = timer
    }

    private func cancelHoverReveal() {
        hoverRevealTimer?.invalidate()
        hoverRevealTimer = nil
    }

    private func fireHoverReveal() {
        hoverRevealTimer = nil

        guard revealsAllowed, hoverProbe?.isHovering == true, !isMouseButtonHeld else { return }
        guard isLocationInMenuBar(NSEvent.mouseLocation) else { return }

        showHiddenItems()
    }

    // MARK: - Scroll / Swipe Monitoring

    private func startScrollMonitoring() {
        guard scrollTapToken == nil else { return }
        scrollTapToken = GlobalEventTap.shared.register(
            name: "MenuBarScrollReveal",
            mask: 1 << CGEventType.scrollWheel.rawValue,
            priority: EventTapPriority.observer,
            enabled: false
        ) { [weak self] type, event in
            self?.processScroll(type: type, event: event)
            return .pass
        }
        updateScrollTapEnabled()
    }

    private func stopScrollMonitoring() {
        if let scrollTapToken {
            GlobalEventTap.shared.unregister(scrollTapToken)
            self.scrollTapToken = nil
        }
    }

    private func updateScrollTapEnabled() {
        guard let scrollTapToken else { return }
        let armed = configuration.showOnScroll && isMonitoring && !isSuspended && hoverProbe?.isHovering == true
        GlobalEventTap.shared.setEnabled(scrollTapToken, armed)
        if !armed { scrollState.withLock { $0.accumulated = 0 } }
    }

    private nonisolated func processScroll(type: CGEventType, event: CGEvent) {
        guard type == .scrollWheel, let nsEvent = NSEvent(cgEvent: event) else { return }
        let delta = (nsEvent.scrollingDeltaX + nsEvent.scrollingDeltaY) / 2
        let threshold: CGFloat = nsEvent.hasPreciseScrollingDeltas ? 12 : 5
        let now = DispatchTime.now().uptimeNanoseconds

        let direction: Int = scrollState.withLock { state in
            guard now >= state.cooldownUntil else { return 0 }
            state.accumulated += delta
            guard abs(state.accumulated) >= threshold else { return 0 }
            let direction = state.accumulated > 0 ? 1 : -1
            state.accumulated = 0
            state.cooldownUntil = now + 450_000_000
            return direction
        }
        guard direction != 0 else { return }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handleScrollGesture(up: direction > 0) }
        }
    }

    private func handleScrollGesture(up: Bool) {
        let location = NSEvent.mouseLocation
        guard revealsAllowed, isLocationInMenuBar(location),
              let axPoint = AX.axPoint(fromCocoaPoint: location) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = MenuBarHitTest.classify(axPoint: axPoint)
            guard result != .item else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.revealsAllowed,
                          MenuBarHitTest.isEmptySpace(result, axPoint: axPoint, cocoaPoint: location) else { return }
                    let controller = (NSApp.delegate as? AppDelegate)?.statusBarController
                    if up { controller?.expand() } else { controller?.collapseFromGesture() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func isLocationInMenuBar(_ loc: CGPoint) -> Bool {
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) else { return false }

        let menuBarHeight = NotchDisplayMetrics.menuBarGap(frame: s.frame, visibleFrame: s.visibleFrame)
        let actualHeight = menuBarHeight > 0 ? min(menuBarHeight, 44) : 24.0

        let menuBarRect = CGRect(x: s.frame.origin.x, y: s.frame.maxY - actualHeight, width: s.frame.width, height: actualHeight)

        return menuBarRect.contains(loc)
    }

    private func showHiddenItems() {
        (NSApp.delegate as? AppDelegate)?.statusBarController?.expand()
    }
}

struct MenuBarSuspensionSources {
    private(set) var sources: Set<ObjectIdentifier> = []

    var isSuspended: Bool { !sources.isEmpty }

    @discardableResult
    mutating func set(_ suspended: Bool, for source: ObjectIdentifier) -> Bool {
        let wasSuspended = isSuspended
        if suspended {
            sources.insert(source)
        } else {
            sources.remove(source)
        }
        return wasSuspended != isSuspended
    }
}