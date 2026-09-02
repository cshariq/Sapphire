//
//  MenuBarInteractionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Cocoa
import Combine

@MainActor
final class MenuBarInteractionManager {
    static let shared = MenuBarInteractionManager()

    // MARK: - Monitors
    private var clickToken: UUID?
    private var hoverProbe: MenuBarHoverProbe?
    private var hoverRevealTimer: Timer?

    // MARK: - State
    public var isMonitoring = false
    private var isSuspended = false
    private var disabledUntil: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        isSuspended = false
        if cancellables.isEmpty {
            SettingsModel.shared.$settings.receive(on: DispatchQueue.main).sink { [weak self] settings in
                guard let self = self, self.isMonitoring else { return }
                self.updateMonitors(for: settings)
            }.store(in: &cancellables)
        }
        updateMonitors(for: SettingsModel.shared.settings)
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended { cancelHoverReveal() }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        isSuspended = false
        stopClickMonitoring()
        stopHoverMonitoring()
        cancellables.removeAll()
    }

    private func updateMonitors(for settings: Settings) {
        if settings.showOnClick && clickToken == nil {
            startClickMonitoring()
        } else if !settings.showOnClick && clickToken != nil {
            stopClickMonitoring()
        }

        if settings.showOnHover && hoverProbe == nil {
            startHoverMonitoring()
        } else if !settings.showOnHover && hoverProbe != nil {
            stopHoverMonitoring()
        }
    }

    func temporarilyDisable(for duration: TimeInterval) {
        disabledUntil = Date().addingTimeInterval(duration)
    }

    // MARK: - Click Monitoring

    private func startClickMonitoring() {
        guard clickToken == nil else { return }

        clickToken = GlobalInputMonitor.shared.onLeftMouseDown { [weak self] in
            guard let self = self, !self.isSuspended else { return }
            guard Date() >= (self.disabledUntil ?? .distantPast) else { return }

            let location = NSEvent.mouseLocation

            if self.isLocationInMenuBar(location) {
                if self.isClickInEmptyMenuBarArea(location) {
                    self.showHiddenItems()
                }
            }
        }
    }

    private func stopClickMonitoring() {
        if let token = clickToken {
            GlobalInputMonitor.shared.remove(token)
            clickToken = nil
        }
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
    }

    private func handleMenuBarHoverChange(_ isInside: Bool) {
        guard isMonitoring, !isSuspended else { return }
        if isInside {
            scheduleHoverReveal()
        } else {
            cancelHoverReveal()
        }
    }

    private func scheduleHoverReveal() {
        cancelHoverReveal()
        guard Date() >= (disabledUntil ?? .distantPast) else { return }

        let delay = max(0, SettingsModel.shared.settings.showOnHoverDelay)
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

        guard isMonitoring, !isSuspended, hoverProbe?.isHovering == true else { return }
        guard Date() >= (disabledUntil ?? .distantPast) else { return }
        guard isLocationInMenuBar(NSEvent.mouseLocation) else { return }

        showHiddenItems()
    }

    // MARK: - Helpers

    private func isLocationInMenuBar(_ loc: CGPoint) -> Bool {
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) else { return false }

        let menuBarHeight = s.frame.height - s.visibleFrame.height
        let actualHeight = menuBarHeight > 0 ? menuBarHeight : 24.0

        let menuBarRect = CGRect(x: s.frame.origin.x, y: s.frame.maxY - actualHeight, width: s.frame.width, height: actualHeight)

        return menuBarRect.contains(loc)
    }

    private func isClickInEmptyMenuBarArea(_ loc: CGPoint) -> Bool {
        let items = MenuBarItemDetector.detectItems()
        return !items.contains { $0.frame.contains(loc) }
    }

    private func showHiddenItems() {
        (NSApp.delegate as? AppDelegate)?.statusBarController?.expand()
    }
}