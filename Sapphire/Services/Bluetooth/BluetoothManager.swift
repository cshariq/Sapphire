//
//  BluetoothManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-07.
//
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

    private var connectionNotification: IOBluetoothUserNotification?
    private var disconnectionNotifications: [String: IOBluetoothUserNotification] = [:]
    private var recentlyConnectedDebounceSet: Set<String> = []

    private let iDeviceBattery = IDeviceBattery.shared
    private let bleBattery = BLEBattery()
    private let magicBattery = MagicBattery.shared
    private let btdBattery = BTDBattery()
    private var periodicPollingTimer: Timer?

    // MARK: - New properties for scan suppression
    private var cancellables = Set<AnyCancellable>()
    private var isProximityScanActive = false

    override init() {
        super.init()
        ud.register(defaults: ["readBTDevice": true, "readBTHID": true, "readIDevice": true, "updateInterval": 1])

        SPBluetoothDataModel.shared.refeshData { [weak self] _ in
            guard let self = self else { return }
            self.bleBattery.startScan()

            self.checkForInitiallyConnectedDevices()
        }

        self.connectionNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAirPodsUpdate(_:)),
            name: .didUpdateAirPodsBattery,
            object: nil
        )

        AuthenticationManager.shared.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isScanning in
                self?.isProximityScanActive = isScanning
                if isScanning {
                    print("[BluetoothManager] Suppressing connection notifications: Proximity scan started.")
                } else {
                    print("[BluetoothManager] Resuming connection notifications: Proximity scan stopped.")
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        connectionNotification?.unregister()
        disconnectionNotifications.values.forEach { $0.unregister() }
        NotificationCenter.default.removeObserver(self)
    }

    func forceBatteryUpdateScan() {
        print("[BluetoothManager] Forcing a full battery update scan on lock.")
        Task.detached(priority: .userInitiated) {
            SPBluetoothDataModel.shared.refeshData { _ in
                self.btdBattery.scanDevices(longScan: true)
                self.bleBattery.scan(longScan: true)
                self.iDeviceBattery.scanDevices()

                self.magicBattery.scanDevices()
            }
        }
    }

    @objc private func handleAirPodsUpdate(_ notification: Notification) {
        guard !isProximityScanActive else {
            print("[BluetoothManager] Suppressing AirPods update because proximity scan is active.")
            return
        }

        guard let userInfo = notification.userInfo,
              let bleName = userInfo["name"] as? String,
              let level = userInfo["level"] as? Int else {
            return
        }

        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let classicDevice = pairedDevices.first(where: {
                  guard let classicName = $0.name else { return false }
                  let cleanClassic = classicName.replacingOccurrences(of: "(ANC)", with: "").replacingOccurrences(of: " ", with: "").lowercased()
                  let cleanBLE = bleName.replacingOccurrences(of: "- Find My", with: "").replacingOccurrences(of: "’s", with: "").replacingOccurrences(of: " ", with: "").lowercased()
                  return cleanBLE.contains(cleanClassic) || cleanClassic.contains(cleanBLE)
              }) else {
            return
        }

        let iconName = IconMapper.icon(for: classicDevice)
        let deviceState = BluetoothDeviceState(
            id: classicDevice.addressString,
            name: classicDevice.name ?? bleName,
            iconName: iconName,
            eventType: .connected,
            batteryLevel: level,
            isContinuityDevice: isContinuityDevice(name: classicDevice.name ?? bleName)
        )
        self.lastEvent = deviceState
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard !isProximityScanActive else {
            print("[BluetoothManager] Suppressing connection event for '\(device.name ?? "??")' because proximity scan is active.")
            registerForDisconnect(device: device)
            return
        }

        guard let address = device.addressString, let name = device.name else { return }

        if recentlyConnectedDebounceSet.contains(address) { return }
        recentlyConnectedDebounceSet.insert(address)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.recentlyConnectedDebounceSet.remove(address)
        }

        if let soundURL = Bundle.main.url(forResource: "head_gestures_double_nod", withExtension: "caf") {
            NSSound(contentsOf: soundURL, byReference: true)?.play()
        } else {
            NSSound(named: "Tink")?.play()
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
            print("[BluetoothManager] Unknown device '\(name)'. Entering learn mode.")
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
        let timeout = 5.0
        let interval: UInt64 = 300_000_000
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if let batteryLevel = await BatteryScanner.getBattery(for: device) {
                print("[BluetoothManager] Found battery level for [\(device.name ?? "??")] after scanning: \(batteryLevel)%")
                return batteryLevel
            }
            try? await Task.sleep(nanoseconds: interval)
        }

        print("[BluetoothManager] Final battery level for [\(device.name ?? "??")]: nil (timeout)")
        return nil
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
        guard !isProximityScanActive else {
            print("[BluetoothManager] Suppressing disconnection event for '\(device.name ?? "??")' because proximity scan is active.")
            if let address = device.addressString, let notificationToRemove = disconnectionNotifications.removeValue(forKey: address) {
                notificationToRemove.unregister()
            }
            return
        }

        guard let address = device.addressString, let name = device.name else { return }

        if let soundURL = Bundle.main.url(forResource: "jbl_cancel", withExtension: "caf") {
            NSSound(contentsOf: soundURL, byReference: true)?.play()
        } else {
            NSSound(named: "Tink")?.play()
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
            deviceConnected(IOBluetoothUserNotification(), device: device)
        }
    }

    private func startPollingServices() {
        let interval = TimeInterval(ud.integer(forKey: "updateInterval") * 60)
        let effectiveInterval = interval > 0 ? interval : 300.0

        periodicPollingTimer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            self?.pollForIDeviceUpdates()
        }
    }

    private func pollForIDeviceUpdates() {
        print("[BluetoothManager] Performing periodic poll for iDevices...")
        iDeviceBattery.scanDevices()
    }

    private func isContinuityDevice(name: String) -> Bool {
        let lowercasedName = name.lowercased()
        let keywords = ["macbook", "imac", "mac mini", "mac studio", "mac pro", "iphone", "ipad", "apple watch", "vision pro"]
        return keywords.contains { lowercasedName.contains($0) }
    }
}