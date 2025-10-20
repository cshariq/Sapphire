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
    var screens: [NSScreen] = []
    var xdrScreens: [NSScreen] = []
    var enabled: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setBrightnessTechnique()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParameters(notification:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensWake(notification:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        SettingsModel.shared.$settings
            .map(\.brightness)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.brightnessTechnique?.adjustBrightness()
            }
            .store(in: &cancellables)

        screens = getXDRDisplays()
    }

    func activate() {
        if !enabled {
            self.enabled = true
            self.enableExtraBrightness()
            print("[BrightnessManager] XDR Brightness Activated")
        }
    }

    func deactivate() {
        if enabled {
            self.enabled = false
            self.brightnessTechnique?.disable()
            print("[BrightnessManager] XDR Brightness Deactivated")
        }
    }

    func setBrightnessTechnique() {
        brightnessTechnique?.disable()
        brightnessTechnique = GammaTechnique()
    }

    @objc func handleScreenParameters(notification: Notification) {
        handlePotentialScreenUpdate()
    }

    @objc func screensWake(notification: Notification) {
        if let brightnessTechnique = brightnessTechnique, brightnessTechnique.isEnabled {
            brightnessTechnique.adjustBrightness()
        }
    }

    func handlePotentialScreenUpdate() {
        let newScreens = NSScreen.screens
        let newXdrDisplays = getXDRDisplays()
        var changedScreens = newScreens.count != screens.count || newXdrDisplays.count != xdrScreens.count
        if !changedScreens {
            for screen in screens {
                let sameScreen = newScreens.filter({$0.displayId == screen.displayId }).first
                if sameScreen?.frame.origin != screen.frame.origin {
                    changedScreens = true;
                    break
                }
            }
        }

        if changedScreens {
            print("[BrightnessManager] Screen setup changed")
            screens = newScreens
            xdrScreens = newXdrDisplays
        }

        guard enabled else { return }

        if !newScreens.isEmpty {
            if let brightnessTechnique = brightnessTechnique {
                if !brightnessTechnique.isEnabled {
                    self.enableExtraBrightness()
                } else if changedScreens {
                    brightnessTechnique.screenUpdate(screens: xdrScreens)
                } else {
                    brightnessTechnique.adjustBrightness()
                }
            }
        } else {
            self.brightnessTechnique?.disable()
        }
    }

    private func enableExtraBrightness() {
        let maxBrightness = SettingsModel.shared.settings.xdrBrightnessLevel
        let safeBrightness = max(1.0, min(maxBrightness, SettingsModel.shared.settings.brightness))

        if safeBrightness != SettingsModel.shared.settings.brightness {
            SettingsModel.shared.settings.brightness = safeBrightness
        }
        self.brightnessTechnique?.enable()
    }
}