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
    private var pollingTimer: Timer?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?

    // MARK: - State
    private var hoverTriggerTimer: Timer?
    private var isMonitoring = false
    private var disabledUntil: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        SettingsModel.shared.$settings.receive(on: DispatchQueue.main).sink { [weak self] settings in
            guard let self = self, self.isMonitoring else { return }
            self.updateMonitors(for: settings)
        }.store(in: &cancellables)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        updateMonitors(for: SettingsModel.shared.settings)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stopHoverMonitoring()
        stopClickMonitoring()
        stopScrollMonitoring()
        cancellables.removeAll()
    }

    private func updateMonitors(for settings: Settings) {
        if settings.showOnHover && pollingTimer == nil {
            startHoverMonitoring()
        } else if !settings.showOnHover && pollingTimer != nil {
            stopHoverMonitoring()
        }

        if settings.showOnClick && clickMonitor == nil {
            startClickMonitoring()
        } else if !settings.showOnClick && clickMonitor != nil {
            stopClickMonitoring()
        }

        if settings.showOnScroll && scrollMonitor == nil {
            startScrollMonitoring()
        } else if !settings.showOnScroll && scrollMonitor != nil {
            stopScrollMonitoring()
        }
    }

    func temporarilyDisable(for duration: TimeInterval) {
        disabledUntil = Date().addingTimeInterval(duration)
    }

    // MARK: - Hover Monitoring (Polling Implementation)

    private func startHoverMonitoring() {
        guard pollingTimer == nil else { return }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func stopHoverMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        hoverTriggerTimer?.invalidate()
        hoverTriggerTimer = nil
    }

    private func checkMousePosition() {
        guard Date() >= (self.disabledUntil ?? .distantPast) else { return }

        let location = NSEvent.mouseLocation

        let isNearTop = NSScreen.screens.contains { screen in
            return location.y >= (screen.frame.maxY - 30)
        }

        if isNearTop && isLocationInMenuBar(location) {
            if hoverTriggerTimer == nil {
                let delay = SettingsModel.shared.settings.showOnHoverDelay
                hoverTriggerTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    self?.showHiddenItems()
                }
            }
        } else {
            hoverTriggerTimer?.invalidate()
            hoverTriggerTimer = nil
        }
    }

    // MARK: - Click Monitoring

    private func startClickMonitoring() {
        guard clickMonitor == nil else { return }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, Date() >= (self.disabledUntil ?? .distantPast) else { return }

            let location = NSEvent.mouseLocation

            if self.isLocationInMenuBar(location) {
                if self.isClickInEmptyMenuBarArea(location) {
                    DispatchQueue.main.async {
                        self.showHiddenItems()
                    }
                }
            }
        }
    }

    private func stopClickMonitoring() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    // MARK: - Scroll Monitoring

    private func startScrollMonitoring() {
        guard scrollMonitor == nil else { return }

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, Date() >= (self.disabledUntil ?? .distantPast) else { return }

            guard abs(event.scrollingDeltaY) > 2 || abs(event.scrollingDeltaX) > 2 else { return }

            let location = NSEvent.mouseLocation

            if self.isLocationInMenuBar(location) {
                DispatchQueue.main.async {
                    self.showHiddenItems()
                }
            }
        }
    }

    private func stopScrollMonitoring() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
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