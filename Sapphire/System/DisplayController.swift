//
//  DisplayController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation
import AppKit
import Combine

class DisplayController: ObservableObject {
    static let shared = DisplayController()

    @Published var displays: [Display] = []

    private var screenUpdateCancellable: AnyCancellable?

    private init() {
        discoverDisplays()
        screenUpdateCancellable = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                print("[DisplayController] Screen parameters changed. Re-discovering displays.")
                self?.discoverDisplays()
            }
    }

    func discoverDisplays() {
        var newDisplays: [Display] = []
        var activeDisplayIDs = [CGDirectDisplayID]()

        var result = CGGetActiveDisplayList(0, nil, &activeDisplayIDs)
        guard result == .success else {
            print("[DisplayController] Failed to get active display list.")
            return
        }

        for displayID in activeDisplayIDs {
            let display = Display(id: displayID)
            display.refreshControl()
            newDisplays.append(display)
        }

        self.displays = newDisplays
        print("[DisplayController] Discovered \(newDisplays.count) displays.")
    }

    func getDisplay(for screen: NSScreen) -> Display? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return displays.first { $0.id == id }
    }

    func getCursorDisplay() -> Display? {
        guard let screen = NSScreen.main else { return nil }
        return getDisplay(for: screen)
    }

    func adjustBrightness(by amount: Int) {
        guard let display = getCursorDisplay() else { return }

        let oldValue = display.brightness
        let newValue = max(0, min(100, oldValue + Float(amount)))

        if display.control?.setBrightness(newValue, oldValue: oldValue) == true {
            display.brightness = newValue
        }
    }
}