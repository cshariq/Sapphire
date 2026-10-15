//
//  XDRGamma.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-13
//

import Foundation
import Cocoa
import Combine

@MainActor
class BrightnessTechnique {
    fileprivate(set) var isEnabled: Bool = false

    func enable() {
        fatalError("Subclasses need to implement the `enable()` method.")
    }

    func enableScreen(screen: NSScreen) {
        fatalError("Subclasses need to implement the `enableScreen()` method.")
    }

    func disable() {
        fatalError("Subclasses need to implement the `disable()` method.")
    }

    func adjustBrightness() {}

    func screenUpdate(screens: [NSScreen]) {}
}

@MainActor
class GammaTechnique: BrightnessTechnique {
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]

    private var gammaEnforcerTimer: Timer?
    private var fullScreenStateCancellable: AnyCancellable?
    private let gammaEnforcerInterval: TimeInterval = 30.0

    private var gamma: DisplayGammaController { DisplayGammaController.shared }

    override func enable() {
        getXDRDisplays().forEach { enableScreen(screen: $0) }
        isEnabled = true
        adjustBrightness()
        registerFullScreenObserver()
        updateGammaEnforcer(isFullScreen: ActiveAppMonitor.shared.isFullScreen)
    }

    override func enableScreen(screen: NSScreen) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.enableScreen(screen: screen)
            }
            return
        }
        guard let displayId = screen.displayId else { return }

        if overlayWindowControllers[displayId] != nil {
            return
        }

        let overlayWindowController = OverlayWindowController(screen: screen)
        overlayWindowControllers[displayId] = overlayWindowController
        let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
        overlayWindowController.open(rect: rect)
    }

    override func disable() {
        stopGammaEnforcer()
        unregisterFullScreenObserver()
        isEnabled = false
        for (displayId, controller) in overlayWindowControllers {
            RemoteViewCrashGuardRunBlock { controller.window?.close() }
            gamma.removeFactor(for: displayId, source: .xdr)
        }
        overlayWindowControllers.removeAll()
    }

    private func startGammaEnforcer() {
        guard gammaEnforcerTimer == nil else { return }
        let timer = Timer.scheduledCoalescing(withTimeInterval: gammaEnforcerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.enforceGamma(isFullScreen: ActiveAppMonitor.shared.isFullScreen)
            }
        }
        gammaEnforcerTimer = timer
    }

    private func stopGammaEnforcer() {
        gammaEnforcerTimer?.invalidate()
        gammaEnforcerTimer = nil
    }

    private func updateGammaEnforcer(isFullScreen: Bool) {
        guard isEnabled else { return }
        if !isFullScreen {
            stopGammaEnforcer()
        } else {
            startGammaEnforcer()
            enforceGamma(isFullScreen: true)
        }
    }

    private func registerFullScreenObserver() {
        guard fullScreenStateCancellable == nil else { return }
        fullScreenStateCancellable = ActiveAppMonitor.shared.$isFullScreen
            .removeDuplicates()
            .sink { [weak self] isFullScreen in
                self?.updateGammaEnforcer(isFullScreen: isFullScreen)
            }
    }

    private func unregisterFullScreenObserver() {
        fullScreenStateCancellable?.cancel()
        fullScreenStateCancellable = nil
    }

    private func enforceGamma(isFullScreen: Bool) {
        guard isEnabled, isFullScreen else { return }
        gamma.reapplyIfReset()
    }

    override func adjustBrightness() {
        super.adjustBrightness()
        guard isEnabled else { return }
        let factor = SettingsModel.shared.brightness
        for displayId in overlayWindowControllers.keys {
            gamma.setFactor(factor, for: displayId, source: .xdr)
        }
    }

    override func screenUpdate(screens: [NSScreen]) {
        let allDisplayIds = screens.compactMap { $0.displayId }
        let toBeDeactivated = overlayWindowControllers.keys.filter { !allDisplayIds.contains($0) }

        toBeDeactivated.forEach { displayId in
            if let controller = overlayWindowControllers.removeValue(forKey: displayId) {
                RemoteViewCrashGuardRunBlock { controller.window?.close() }
            }
            gamma.removeFactor(for: displayId, source: .xdr)
        }

        screens.forEach { screen in
            guard let displayId = screen.displayId else { return }
            if let controller = overlayWindowControllers[displayId] {
                controller.reposition(screen: screen)
            } else {
                enableScreen(screen: screen)
            }
        }

        adjustBrightness()
    }
}