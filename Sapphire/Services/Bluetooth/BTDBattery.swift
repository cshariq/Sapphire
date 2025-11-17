//
//  BTDBattery.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2024/6/23.
//

import SwiftUI
import Foundation
import IOBluetooth

class BTDBattery {
    var scanTimer: Timer?
    static var allDevices = [String]()
    @AppStorage("readBTHID") var readBTHID = true
    static func getConnected(mac: Bool = false) -> [String]{
        guard var bluetoothDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        bluetoothDevices = bluetoothDevices.filter({ $0.isConnected() })
        if mac {
            let devices = bluetoothDevices.map({ ($0.addressString ?? "").uppercased().replacingOccurrences(of: "-", with: ":") })
            return devices.filter({ $0 != "" })
        }
        return bluetoothDevices.map({ $0.name ?? "" }).filter({ $0 != "" })
    }
}