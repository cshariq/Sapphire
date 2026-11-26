//
//  BluetoothUnlockCalibrationTests.swift
//  Sapphire
//

import Testing
@testable import Sapphire

struct BluetoothUnlockCalibrationTests {
    // Unlock fires at or above its threshold and lock below its own, so the measured spots must fall on the right side.
    @Test func suggestionsUnlockAtTheNearSpotAndLockAtTheFarSpot() {
        let (unlock, lock) = BLE.suggestedThresholds(near: -55, far: -80)
        #expect(-55 >= unlock)
        #expect(-80 < lock)
        #expect(unlock > lock)
    }

    @Test func closeMeasurementsStillLeaveAGapBetweenUnlockAndLock() {
        let (unlock, lock) = BLE.suggestedThresholds(near: -70, far: -72)
        #expect(unlock > lock)
    }
}
