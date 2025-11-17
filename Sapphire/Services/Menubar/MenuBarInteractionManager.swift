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
    private var hoverMonitor: Any?; private var clickMonitor: Any?; private var scrollMonitor: Any?
    private var hoverTimer: Timer?; private var isMonitoring = false; private var disabledUntil: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        SettingsModel.shared.$settings.receive(on: DispatchQueue.main).sink { [weak self] settings in
            guard let self = self, self.isMonitoring else { return }; self.updateMonitors(for: settings)
        }.store(in: &cancellables)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }; isMonitoring = true; updateMonitors(for: SettingsModel.shared.settings)
    }
    func stopMonitoring() {
        guard isMonitoring else { return }; isMonitoring = false
        stopHoverMonitoring(); stopClickMonitoring(); stopScrollMonitoring(); cancellables.removeAll()
    }

    private func updateMonitors(for settings: Settings) {
        if settings.showOnHover && hoverMonitor == nil { startHoverMonitoring() } else if !settings.showOnHover && hoverMonitor != nil { stopHoverMonitoring() }
        if settings.showOnClick && clickMonitor == nil { startClickMonitoring() } else if !settings.showOnClick && clickMonitor != nil { stopClickMonitoring() }
        if settings.showOnScroll && scrollMonitor == nil { startScrollMonitoring() } else if !settings.showOnScroll && scrollMonitor != nil { stopScrollMonitoring() }
    }

    func temporarilyDisable(for duration: TimeInterval) { disabledUntil = Date().addingTimeInterval(duration) }
    private func startHoverMonitoring() {
        guard hoverMonitor == nil else { return }
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self, Date() >= (self.disabledUntil ?? .distantPast) else { return }
            if self.isLocationInMenuBar(NSEvent.mouseLocation) {
                self.hoverTimer?.invalidate()
                self.hoverTimer = Timer.scheduledTimer(withTimeInterval: SettingsModel.shared.settings.showOnHoverDelay, repeats: false) { _ in self.showHiddenItems() }
            } else { self.hoverTimer?.invalidate() }
        }
    }
    private func stopHoverMonitoring() { if let m = hoverMonitor { NSEvent.removeMonitor(m); hoverMonitor = nil }; hoverTimer?.invalidate(); hoverTimer = nil }
    private func startClickMonitoring() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, Date() >= (self.disabledUntil ?? .distantPast) else { return }
            if self.isLocationInMenuBar(NSEvent.mouseLocation) && self.isClickInEmptyMenuBarArea(NSEvent.mouseLocation) { self.showHiddenItems() }
        }
    }
    private func stopClickMonitoring() { if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil } }
    private func startScrollMonitoring() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, Date() >= (self.disabledUntil ?? .distantPast) else { return }
            if self.isLocationInMenuBar(NSEvent.mouseLocation) && (abs(event.scrollingDeltaY) > 2 || abs(event.scrollingDeltaX) > 2) { self.showHiddenItems() }
        }
    }
    private func stopScrollMonitoring() { if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil } }
    private func isLocationInMenuBar(_ loc: CGPoint) -> Bool {
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) else { return false }
        return CGRect(x: s.frame.origin.x, y: s.frame.maxY - 24.0, width: s.frame.width, height: 24.0).contains(loc)
    }
    private func isClickInEmptyMenuBarArea(_ loc: CGPoint) -> Bool { !MenuBarItemDetector.detectItems().contains { $0.frame.contains(loc) } }
    private func showHiddenItems() { (NSApp.delegate as? AppDelegate)?.statusBarController?.expand() }
}