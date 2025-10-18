//
//  Display.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation
import Cocoa
import CoreGraphics
import Combine

class Display: NSObject, ObservableObject, Identifiable {
    @Published var id: CGDirectDisplayID
    @Published var serial: String
    @Published var name: String
    @Published var adaptive: Bool = true

    @Published var brightness: Float = 50.0

    @Published var softwareBrightness: Float = 1.0 {
        didSet {
            if let control = self.control as? GammaControl {
                control.setBrightness(softwareBrightness * 100, oldValue: nil)
            } else if let appleControl = self.control as? AppleNativeControl, isBuiltin, softwareBrightness < 1.0 {
                let gamma = GammaControl(display: self)
                gamma.setBrightness(softwareBrightness * 100, oldValue: nil)
            }
        }
    }

    @Published var contrast: Float = 75.0
    @Published var volume: Float = 20.0

    @Published var minBrightness: Float = 0.0
    @Published var maxBrightness: Float = 100.0
    @Published var minContrast: Float = 0.0
    @Published var maxContrast: Float = 100.0

    var control: Control?

    var isBuiltin: Bool {
        return CGDisplayIsBuiltin(id) != 0
    }

    var hasDDC: Bool = false
    var hasNetworkControl: Bool = false
    var isNative: Bool = false

    init(id: CGDirectDisplayID, serial: String? = nil, name: String? = nil) {
        self.id = id
        self.serial = serial ?? Display.getSerial(for: id)
        self.name = name ?? Display.getDisplayName(for: id)
        super.init()
    }

    static func getSerial(for id: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id) {
            let uuidValue = uuid.takeRetainedValue()
            return CFUUIDCreateString(kCFAllocatorDefault, uuidValue) as String
        }
        return String(id)
    }

    static func getDisplayName(for id: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == id }) {
            return screen.localizedName
        }
        return "Unknown Display"
    }

    func getBestControl() -> Control {
        if self.isBuiltin || AppleNativeControl.isAvailable(for: self) {
            self.isNative = true
            return AppleNativeControl(display: self)
        }
        if DDC.isAvailable(for: self) {
            self.hasDDC = true
            return DDCControl(display: self)
        }
        return GammaControl(display: self)
    }

    func refreshControl() {
        self.control = getBestControl()
    }
}