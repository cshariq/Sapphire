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

    func scaledTable(factor: Float) -> (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
        return (
            red: redTable.map { $0 * factor },
            green: greenTable.map { $0 * factor },
            blue: blueTable.map { $0 * factor }
        )
    }

    func matches(red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue], tolerance: Float) -> Bool {
        let sampleCount = min(red.count, green.count, blue.count, redTable.count)
        guard sampleCount > 0 else { return false }

        for index in 0..<sampleCount {
            if abs(red[index] - redTable[index]) > tolerance
                || abs(green[index] - greenTable[index]) > tolerance
                || abs(blue[index] - blueTable[index]) > tolerance {
                return false
            }
        }
        return true
    }
}

@MainActor
class GammaTechnique: BrightnessTechnique {
    private var overlayWindowControllers: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var gammaTables: [CGDirectDisplayID: GammaTable] = [:]

    private var gammaEnforcerTimer: Timer?
    private var fullScreenStateCancellable: AnyCancellable?
    private let gammaEnforcerInterval: TimeInterval = 30.0
    private let gammaEnforcerTolerance: Float = 0.005

    override func enable() {
        getXDRDisplays().forEach { enableScreen(screen: $0) }
        isEnabled = true
        adjustBrightness()
        registerFullScreenObserver()
        updateGammaEnforcer()
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
        stopGammaEnforcer()
        unregisterFullScreenObserver()
        isEnabled = false
        overlayWindowControllers.values.forEach { controller in
            RemoteViewCrashGuardRunBlock { controller.window?.close() }
        }
        overlayWindowControllers.removeAll()
        gammaTables.removeAll()
        resetGammaTable()
        print("[GammaTechnique] Disabled and closed all overlay windows.")
    }

    private func startGammaEnforcer() {
        guard gammaEnforcerTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: gammaEnforcerInterval, repeats: true) { [weak self] _ in
            self?.enforceGamma()
        }
        RunLoop.main.add(timer, forMode: .common)
        gammaEnforcerTimer = timer
    }

    private func stopGammaEnforcer() {
        gammaEnforcerTimer?.invalidate()
        gammaEnforcerTimer = nil
    }

    private func updateGammaEnforcer() {
        guard isEnabled else { return }
        if !ActiveAppMonitor.shared.isFullScreen {
            stopGammaEnforcer()
        } else {
            startGammaEnforcer()
            enforceGamma()
        }
    }

    private func registerFullScreenObserver() {
        guard fullScreenStateCancellable == nil else { return }
        fullScreenStateCancellable = ActiveAppMonitor.shared.$isFullScreen
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateGammaEnforcer()
            }
    }

    private func unregisterFullScreenObserver() {
        fullScreenStateCancellable?.cancel()
        fullScreenStateCancellable = nil
    }

    private func enforceGamma() {
        guard isEnabled else { return }
        let factor = SettingsModel.shared.settings.brightness

        for (displayId, gammaTable) in gammaTables {
            guard ActiveAppMonitor.shared.isFullScreen else {
                continue
            }
            guard let currentTable = GammaTable.createFromCurrentGammaTable(displayId: displayId) else { continue }
            let expected = gammaTable.scaledTable(factor: factor)
            let drifted = !currentTable.matches(red: expected.red, green: expected.green, blue: expected.blue, tolerance: gammaEnforcerTolerance)

            if drifted {
                gammaTable.setTableForScreen(displayId: displayId, factor: factor)
                print("[GammaEnforcer] Re-applied gamma table for display \(displayId) — compensation had been reset by the system.")
            }
        }
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
            RemoteViewCrashGuardRunBlock {
                self.overlayWindowControllers[displayId]?.window?.close()
            }
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