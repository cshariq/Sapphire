//
//  XDRGamma.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-13
//

import Foundation
import Cocoa

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

class GammaTable {
    static let tableSize: UInt32 = 256

    var redTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var greenTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var blueTable: [CGGammaValue] = [CGGammaValue](repeating: 0, count: Int(tableSize))

    private init() {}

    static func createFromCurrentGammaTable(displayId: CGDirectDisplayID) -> GammaTable? {
        let table = GammaTable()
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(displayId, tableSize, &table.redTable, &table.greenTable, &table.blueTable, &sampleCount)
        guard result == .success else { return nil }
        return table
    }

    func setTableForScreen(displayId: CGDirectDisplayID, factor: Float) {
        var newRedTable = redTable.map { $0 * factor }
        var newGreenTable = greenTable.map { $0 * factor }
        var newBlueTable = blueTable.map { $0 * factor }

        CGSetDisplayTransferByTable(displayId, GammaTable.tableSize, &newRedTable, &newGreenTable, &newBlueTable)
    }
}

class GammaTechnique: BrightnessTechnique {
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var gammaTables: [CGDirectDisplayID: GammaTable] = [:]

    override func enable() {
        getXDRDisplays().forEach { enableScreen(screen: $0) }
        isEnabled = true
        adjustBrightness()
    }

    override func enableScreen(screen: NSScreen) {
        guard let displayId = screen.displayId else { return }

        if overlayWindowControllers[displayId] != nil {
            print("[GammaTechnique] Overlay for display \(displayId) already exists. Skipping creation.")
            return
        }

        if !gammaTables.keys.contains(displayId) {
            gammaTables[displayId] = GammaTable.createFromCurrentGammaTable(displayId: displayId)
        }

        print("[GammaTechnique] Creating new overlay for display \(displayId).")
        let overlayWindowController = OverlayWindowController(screen: screen)
        overlayWindowControllers[displayId] = overlayWindowController
        let rect = NSRect(x: screen.frame.origin.x, y: screen.frame.origin.y, width: 1, height: 1)
        overlayWindowController.open(rect: rect)
    }

    override func disable() {
        isEnabled = false
        overlayWindowControllers.values.forEach { $0.window?.close() }
        overlayWindowControllers.removeAll()
        gammaTables.removeAll()
        resetGammaTable()
        print("[GammaTechnique] Disabled and closed all overlay windows.")
    }

    override func adjustBrightness() {
        super.adjustBrightness()

        if isEnabled {
            let gamma = SettingsModel.shared.settings.brightness
            overlayWindowControllers.values.forEach { controller in
                if let displayId = controller.screen.displayId, let gammaTable = gammaTables[displayId] {
                    gammaTable.setTableForScreen(displayId: displayId, factor: gamma)
                }
            }
        }
    }

    private func resetGammaTable() {
        CGDisplayRestoreColorSyncSettings()
        print("[GammaTechnique] Reset gamma table for all displays")
    }

    override func screenUpdate(screens: [NSScreen]) {
        let allDisplayIds = screens.compactMap { $0.displayId }
        let toBeDeactivated = overlayWindowControllers.keys.filter { !allDisplayIds.contains($0) }

        toBeDeactivated.forEach { displayId in
            overlayWindowControllers[displayId]?.window?.close()
            gammaTables[displayId]?.setTableForScreen(displayId: displayId, factor: 1.0)
            gammaTables.removeValue(forKey: displayId)
            overlayWindowControllers.removeValue(forKey: displayId)
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