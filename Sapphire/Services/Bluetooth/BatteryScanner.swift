//
//  BatteryScanner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-25.
//

import Foundation
import IOBluetooth

@MainActor
class BatteryScanner {

    static func getBattery(for device: IOBluetoothDevice) async -> Int? {
        guard let name = device.name else {
            print("[BatteryScanner] Could not get name for device.")
            return nil
        }

        print("[BatteryScanner] Starting on-demand battery scan for '\(name)'...")

        let batteryLevel: Int? = await withCheckedContinuation { continuation in
            SPBluetoothDataModel.shared.refeshData { _ in
                print("[BatteryScanner] -> System Profiler data refreshed.")

                MagicBattery.shared.getIOBTBattery()

                if let batteryDevice = AirBatteryModel.getByName(name), batteryDevice.batteryLevel > 0 {
                    print("[BatteryScanner] Found battery via Direct Query after refresh: \(batteryDevice.batteryLevel)%")
                    continuation.resume(returning: batteryDevice.batteryLevel)
                    return
                }

                print("[BatteryScanner] No battery level found for '\(name)' after all checks.")
                continuation.resume(returning: nil)
            }
        }

        if let level = batteryLevel, let address = device.addressString {
            updateModel(address: address, name: name, level: level)
        }

        return batteryLevel
    }

    // MARK: - Private Helper Methods

    private static func updateModel(address: String, name: String, level: Int) {
        let batteryDevice = BatteryDevice(
            deviceID: address,
            deviceType: "general_bt",
            deviceName: name,
            batteryLevel: level,
            isCharging: 0,
            lastUpdate: Date().timeIntervalSince1970
        )
        AirBatteryModel.updateDevice(batteryDevice)
    }
}