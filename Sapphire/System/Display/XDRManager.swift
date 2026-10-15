//
//  XDRManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-13
//

import Foundation
import Cocoa
import Combine

@MainActor
class BrightnessManager {
    static let shared = BrightnessManager()

    var brightnessTechnique: BrightnessTechnique?
    private(set) var xdrScreens: [NSScreen] = []
    private(set) var enabled: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var screenUpdateWorkItem: DispatchWorkItem?

    private init() {
        setBrightnessTechnique()

        SettingsModel.shared.brightnessPublisher
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.brightnessTechnique?.adjustBrightness()
            }
            .store(in: &cancellables)
    }

    func activate() {
        guard !enabled else { return }
        enabled = true
        xdrScreens = getXDRDisplays()
        installObservers()
        enableExtraBrightness()
        print("[BrightnessManager] XDR Brightness Activated")
    }

    func deactivate() {
        guard enabled else { return }
        enabled = false
        removeObservers()
        brightnessTechnique?.disable()
        xdrScreens = []
        print("[BrightnessManager] XDR Brightness Deactivated")
    }

    func setBrightnessTechnique() {
        brightnessTechnique?.disable()
        brightnessTechnique = GammaTechnique()
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((center, center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScreenUpdate() }
        }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let technique = self?.brightnessTechnique, technique.isEnabled else { return }
                technique.adjustBrightness()
            }
        }))
    }

    private func removeObservers() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        screenUpdateWorkItem?.cancel()
        screenUpdateWorkItem = nil
    }

    private func scheduleScreenUpdate() {
        screenUpdateWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.screenUpdateWorkItem = nil
                self?.handlePotentialScreenUpdate()
            }
        }
        screenUpdateWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func handlePotentialScreenUpdate() {
        guard enabled else { return }
        let newXdrScreens = getXDRDisplays()
        let changedScreens = Self.layoutKey(newXdrScreens) != Self.layoutKey(xdrScreens)
        xdrScreens = newXdrScreens

        guard let brightnessTechnique else { return }
        if newXdrScreens.isEmpty {
            brightnessTechnique.screenUpdate(screens: [])
        } else if !brightnessTechnique.isEnabled {
            enableExtraBrightness()
        } else if changedScreens {
            print("[BrightnessManager] XDR screen setup changed")
            brightnessTechnique.screenUpdate(screens: newXdrScreens)
        } else {
            brightnessTechnique.adjustBrightness()
        }
    }

    private static func layoutKey(_ screens: [NSScreen]) -> [String] {
        screens.map { "\($0.displayId ?? 0)@\($0.frame.origin.x),\($0.frame.origin.y)" }
    }

    private func enableExtraBrightness() {
        let maxBrightness = SettingsModel.shared.current.xdrBrightnessLevel
        let safeBrightness = max(1.0, min(maxBrightness, SettingsModel.shared.brightness))

        if safeBrightness != SettingsModel.shared.brightness {
            SettingsModel.shared.brightness = safeBrightness
        }
        self.brightnessTechnique?.enable()
    }
}