//
//  GammaControl.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation
import AppKit

final class GammaControl: Control {
    weak var display: Display?
    var isSoftware: Bool { true }
    var isDDC: Bool { false }

    private var originalGammaRed: [CGGammaValue] = []
    private var originalGammaGreen: [CGGammaValue] = []
    private var originalGammaBlue: [CGGammaValue] = []
    private var tableSize: UInt32 = 256
    private var hasStoredOriginalGamma = false

    init(display: Display) {
        self.display = display
        storeOriginalGamma()
    }

    func isAvailable() -> Bool {
        return true
    }

    private func storeOriginalGamma() {
        guard let displayID = display?.id, !hasStoredOriginalGamma else { return }
        var redTable = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var greenTable = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var blueTable = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var sampleCount: UInt32 = 0

        if CGGetDisplayTransferByTable(displayID, tableSize, &redTable, &greenTable, &blueTable, &sampleCount) == .success {
            self.originalGammaRed = redTable
            self.originalGammaGreen = greenTable
            self.originalGammaBlue = blueTable
            self.hasStoredOriginalGamma = true
        }
    }

    func setBrightness(_ brightness: Float, oldValue: Float?) -> Bool {
        guard let displayID = display?.id else { return false }

        if !hasStoredOriginalGamma { storeOriginalGamma() }
        guard hasStoredOriginalGamma else { return false }

        let level = brightness / 100.0

        if level >= 1.0 {
            CGDisplayRestoreColorSyncSettings()
            return true
        }

        let factor = level.map(from: (0.0, 1.0), to: (0.08, 1.0))

        var newRedTable = originalGammaRed.map { $0 * factor }
        var newGreenTable = originalGammaGreen.map { $0 * factor }
        var newBlueTable = originalGammaBlue.map { $0 * factor }

        let result = CGSetDisplayTransferByTable(displayID, tableSize, &newRedTable, &newGreenTable, &newBlueTable)

        if result != .success {
             print("[GammaControl] Failed to set gamma for display \(displayID)")
        }
        return result == .success
    }

    func getBrightness() -> Float? {
        return nil
    }

    func setContrast(_ contrast: Float, oldValue: Float?) -> Bool { return false }
    func getContrast() -> Float? { return nil }
    func setPower(_ power: PowerState) -> Bool { return false }
}

extension FloatingPoint {
    func map(from: (Self, Self), to: (Self, Self)) -> Self {
        let result = (self - from.0) / (from.1 - from.0) * (to.1 - to.0) + to.0
        return result
    }
}