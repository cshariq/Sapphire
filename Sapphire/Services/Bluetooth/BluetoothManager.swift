//
//  BluetoothManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-07.
//

import Foundation
import Combine
import IOBluetooth
import AppKit

struct BluetoothDeviceState: Hashable {
    enum EventType: Hashable {
        case connected, disconnected, batteryLow
    }
    let eventUUID = UUID()
    let id: String, name: String, iconName: String, eventType: EventType
    var batteryLevel: Int? = nil
    let isContinuityDevice: Bool
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.eventUUID == rhs.eventUUID }
    func hash(into hasher: inout Hasher) { hasher.combine(eventUUID) }
}

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var lastEvent: BluetoothDeviceState?

    var isBluetoothPoweredOn: Bool {
        IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }

    private var connectionNotification: IOBluetoothUserNotification?
    private var disconnectionNotifications: [String: IOBluetoothUserNotification] = [:]
    private var recentlyConnectedDebounceSet: Set<String> = []
    private var initialConnectionsUntil = Date().addingTimeInterval(2)

    private let magicBattery = MagicBattery.shared
    private let batteryReader = BluetoothBatteryReader.shared

    private var cancellables = Set<AnyCancellable>()
    private var isProximityScanActive = false

    override init() {
        super.init()
        ud.register(defaults: ["readBTDevice": true, "readBTHID": true, "readIDevice": true, "updateInterval": 1])

        SPBluetoothDataModel.shared.refeshData { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForInitiallyConnectedDevices()
            }
        }

        Task { [batteryReader] in
            await batteryReader.refreshAllBatteries()
        }

        initialConnectionsUntil = Date().addingTimeInterval(2)
        self.connectionNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )

        AuthenticationManager.shared.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isScanning in
                self?.isProximityScanActive = isScanning
            }
            .store(in: &cancellables)
    }

    deinit {
        connectionNotification?.unregister()
        disconnectionNotifications.values.forEach { $0.unregister() }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            self?.handleDeviceConnected(device: device)
        }
    }

    @MainActor
    private func handleDeviceConnected(device: IOBluetoothDevice, isInitialState: Bool = false) {
        guard !isProximityScanActive else {
            registerForDisconnect(device: device)
            return
        }

        guard let address = device.addressString, let name = device.name else { return }

        if recentlyConnectedDebounceSet.contains(address) { return }
        recentlyConnectedDebounceSet.insert(address)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.recentlyConnectedDebounceSet.remove(address)
        }

        let alreadyConnected = isInitialState || Date() < initialConnectionsUntil
        if SettingsModel.shared.current.bluetoothNotifySound, !alreadyConnected {
            if let soundURL = Bundle.main.url(forResource: "head_gestures_double_nod", withExtension: "caf") {
                NSSound(contentsOf: soundURL, byReference: true)?.play()
            } else {
                NSSound(named: "Tink")?.play()
            }
        }

        let lowercasedName = name.lowercased()
        if lowercasedName.contains("airpods") || lowercasedName.contains("beats") {
            registerForDisconnect(device: device)
            return
        }

        let batteryStatus = IconMapper.getBatteryStatus(for: device)
        let iconName = IconMapper.icon(for: device)

        switch batteryStatus {
        case .noBattery:
            let deviceState = BluetoothDeviceState(
                id: address, name: name, iconName: iconName,
                eventType: .connected, batteryLevel: nil,
                isContinuityDevice: isContinuityDevice(name: name)
            )
            self.lastEvent = deviceState

        case .hasBattery:
            Task {
                let batteryLevel = await findBatteryLevel(for: device)
                let deviceState = BluetoothDeviceState(
                    id: address, name: name, iconName: iconName,
                    eventType: .connected, batteryLevel: batteryLevel,
                    isContinuityDevice: isContinuityDevice(name: name)
                )
                self.lastEvent = deviceState
            }

        case .unknown:
            let immediateState = BluetoothDeviceState(
                id: address, name: name, iconName: iconName,
                eventType: .connected, batteryLevel: nil,
                isContinuityDevice: isContinuityDevice(name: name)
            )
            self.lastEvent = immediateState

            Task {
                let batteryLevel = await findBatteryLevel(for: device)

                IconMapper.learnDeviceBatteryStatus(address: address, hasBattery: batteryLevel != nil)

                if let level = batteryLevel {
                    let updatedState = BluetoothDeviceState(
                        id: address, name: name, iconName: iconName,
                        eventType: .connected, batteryLevel: level,
                        isContinuityDevice: isContinuityDevice(name: name)
                    )
                    self.lastEvent = updatedState
                }
            }
        }

        registerForDisconnect(device: device)
    }

    private func findBatteryLevel(for device: IOBluetoothDevice) async -> Int? {
        guard let name = device.name else { return nil }
        let address = device.addressString

        if let level = Self.validLevel(fromDeviceProperties: device) { return level }

        if let address {
            let level = await Task.detached(priority: .utility) {
                BluetoothBatteryReader.ioRegistryBatteryLevel(forAddress: address)
            }.value
            if let level { return level }
        }

        if let cached = Self.validCachedLevel(named: name) { return cached }

        await batteryReader.refreshAllBatteries(maxAge: 30)

        if let cached = Self.validCachedLevel(named: name) { return cached }
        let normalized = address.map(BluetoothBatteryReader.normalizedAddress)
        if let match = batteryReader.systemProfilerBatteries.first(where: {
            $0.name == name || (normalized != nil && $0.address == normalized && $0.name == $0.baseName)
        }) {
            return match.level
        }
        return nil
    }

    private static func validLevel(fromDeviceProperties device: IOBluetoothDevice) -> Int? {
        if device.isMultiBatteryDevice {
            let valid = [device.batteryPercentLeft, device.batteryPercentRight].filter { $0 > 0 && $0 <= 100 }
            return valid.isEmpty ? nil : valid.reduce(0, +) / valid.count
        }
        let single = device.batteryPercentSingle
        return single > 0 && single <= 100 ? single : nil
    }

    private static func validCachedLevel(named name: String) -> Int? {
        guard let cached = AccessoryBatteryStore.getByName(name),
              cached.batteryLevel > 0, cached.batteryLevel <= 100 else { return nil }
        return cached.batteryLevel
    }

    private func registerForDisconnect(device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        if self.disconnectionNotifications[address] == nil {
            self.disconnectionNotifications[address] = device.register(
                forDisconnectNotification: self,
                selector: #selector(self.deviceDisconnected(_:device:))
            )
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            self?.handleDeviceDisconnected(device: device)
        }
    }

    @MainActor
    private func handleDeviceDisconnected(device: IOBluetoothDevice) {
        guard !isProximityScanActive else {
            if let address = device.addressString, let notificationToRemove = disconnectionNotifications.removeValue(forKey: address) {
                notificationToRemove.unregister()
            }
            return
        }

        guard let address = device.addressString, let name = device.name else { return }

        if SettingsModel.shared.current.bluetoothNotifySound {
            if let soundURL = Bundle.main.url(forResource: "jbl_cancel", withExtension: "caf") {
                NSSound(contentsOf: soundURL, byReference: true)?.play()
            } else {
                NSSound(named: "Tink")?.play()
            }
        }

        let iconName = IconMapper.icon(for: device)

        let deviceState = BluetoothDeviceState(
            id: address, name: name, iconName: iconName,
            eventType: .disconnected, isContinuityDevice: isContinuityDevice(name: name)
        )
        self.lastEvent = deviceState

        if let notificationToRemove = disconnectionNotifications.removeValue(forKey: address) {
            notificationToRemove.unregister()
        }
    }

    private func checkForInitiallyConnectedDevices() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in pairedDevices where device.isConnected() {
            handleDeviceConnected(device: device, isInitialState: true)
        }
    }

    private func isContinuityDevice(name: String) -> Bool {
        let lowercasedName = name.lowercased()
        let keywords = ["macbook", "imac", "mac mini", "mac studio", "mac pro", "iphone", "ipad", "apple watch", "vision pro"]
        return keywords.contains { lowercasedName.contains($0) }
    }
}