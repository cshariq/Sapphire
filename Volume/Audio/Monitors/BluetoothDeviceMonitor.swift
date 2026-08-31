//
//  BluetoothDeviceMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AppKit
import IOBluetooth
import os

@Observable
@MainActor
final class BluetoothDeviceMonitor {

    // MARK: - Published State

    private(set) var isBluetoothOn: Bool = false

    private(set) var pairedDevices: [PairedBluetoothDevice] = []

    private(set) var connectingIDs: Set<String> = []

    private(set) var connectionErrors: [String: String] = [:]

    // MARK: - Private

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire",
        category: "BluetoothDeviceMonitor"
    )

    private static let btQueue = DispatchQueue(label: "com.cshariq.sapphire.bluetooth")

    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    private var errorClearTasks: [String: Task<Void, Never>] = [:]

    private var refreshTask: Task<Void, Never>?

    private let connectTimeoutSeconds: Double = 12

    // MARK: - A2DP / HFP SDP UUIDs

    private static let a2dpSinkUUID = IOBluetoothSDPUUID(uuid16: 0x110B)!
    private static let hfpUUID = IOBluetoothSDPUUID(uuid16: 0x111E)!

    private nonisolated(unsafe) var powerOnObserver: NSObjectProtocol?
    private nonisolated(unsafe) var powerOffObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    deinit {
        if let powerOnObserver { NotificationCenter.default.removeObserver(powerOnObserver) }
        if let powerOffObserver { NotificationCenter.default.removeObserver(powerOffObserver) }
    }

    func start() {
        powerOnObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("IOBluetoothHostControllerPoweredOnNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        powerOffObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("IOBluetoothHostControllerPoweredOffNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            let powered = await Self.runOnBTQueue {
                IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
            }
            guard !Task.isCancelled else { return }

            isBluetoothOn = powered

            guard powered else {
                pairedDevices = []
                return
            }

            let connectingSnapshot = connectingIDs
            let rawDevices = await Self.runOnBTQueue {
                Self.fetchPairedAudioDevices(excludingConnectingIDs: connectingSnapshot)
            }
            guard !Task.isCancelled else { return }

            let devices = rawDevices.map { raw in
                PairedBluetoothDevice(
                    id: raw.mac,
                    name: raw.name,
                    icon: NSImage(
                        systemSymbolName: raw.iconName,
                        accessibilityDescription: raw.name
                    )
                )
            }
            pairedDevices = devices
            logger.debug("Paired BT audio devices: \(devices.count)")
        }
    }

    // MARK: - Connect

    func connect(device: PairedBluetoothDevice) {
        let mac = device.id
        guard !connectingIDs.contains(mac) else { return }

        logger.info("Connecting to \(device.name) (\(mac))")

        connectingIDs.insert(mac)
        connectionErrors.removeValue(forKey: mac)

        Task {
            let result = await Self.runOnBTQueue {
                guard let btDevice = IOBluetoothDevice(addressString: mac) else {
                    return kIOReturnNotFound
                }
                return btDevice.openConnection()
            }

            if result != kIOReturnSuccess {
                logger.error("\(device.name): openConnection failed (IOReturn \(result))")
                finishConnecting(mac: mac, error: "Couldn't connect")
                return
            }

            startConnectTimeout(mac: mac, name: device.name)
        }
    }

    func notifyDeviceAppearedInCoreAudio() {
        if !connectingIDs.isEmpty {
            Task {
                let stillDisconnected = await Self.runOnBTQueue {
                    let allPaired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
                    return Set(allPaired.filter { !$0.isConnected() }.compactMap { $0.addressString })
                }

                for mac in connectingIDs {
                    if !stillDisconnected.contains(mac) {
                        logger.debug("Device \(mac) connected; clearing in-flight state")
                        timeoutTasks[mac]?.cancel()
                        timeoutTasks.removeValue(forKey: mac)
                        connectingIDs.remove(mac)
                        pairedDevices.removeAll { $0.id == mac }
                    }
                }

                refresh()
            }
        } else {
            refresh()
        }
    }

    // MARK: - IOBluetooth Queue Helper

    private nonisolated static func runOnBTQueue<T: Sendable>(
        _ work: @Sendable @escaping () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            btQueue.async {
                autoreleasepool {
                    continuation.resume(returning: work())
                }
            }
        }
    }

    // MARK: - Background IOBluetooth Work

    private struct RawPairedDevice: Sendable {
        let mac: String
        let name: String
        let iconName: String
    }

    private nonisolated static func fetchPairedAudioDevices(
        excludingConnectingIDs connectingIDs: Set<String>
    ) -> [RawPairedDevice] {
        guard let all = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        var result: [RawPairedDevice] = []

        for device in all {
            guard !device.isConnected() else { continue }

            let mac = device.addressString ?? ""
            guard !mac.isEmpty else { continue }
            guard !connectingIDs.contains(mac) else { continue }

            let hasA2DP = device.getServiceRecord(for: a2dpSinkUUID) != nil
            let hasHFP = device.getServiceRecord(for: hfpUUID) != nil
            guard hasA2DP || hasHFP else { continue }

            let name = device.name ?? mac
            result.append(RawPairedDevice(mac: mac, name: name, iconName: suggestedIconName(for: name)))
        }

        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }

    private nonisolated static func suggestedIconName(for name: String) -> String {
        if name.contains("AirPods Pro") { return "airpodspro" }
        if name.contains("AirPods Max") { return "airpodsmax" }
        if name.contains("AirPods") { return "airpods.gen3" }
        if name.contains("HomePod mini") { return "homepodmini" }
        if name.contains("HomePod") { return "homepod" }
        if name.contains("Beats") { return "beats.headphones" }
        return "headphones"
    }

    // MARK: - Private Helpers

    private func startConnectTimeout(mac: String, name: String) {
        timeoutTasks[mac]?.cancel()
        timeoutTasks[mac] = Task { [weak self, connectTimeoutSeconds] in
            try? await Task.sleep(for: .seconds(connectTimeoutSeconds))
            guard !Task.isCancelled else { return }
            self?.logger.warning("\(name) connect timeout after \(connectTimeoutSeconds)s")
            self?.finishConnecting(mac: mac, error: "Connection timed out")
        }
    }

    private func finishConnecting(mac: String, error: String?) {
        timeoutTasks[mac]?.cancel()
        timeoutTasks.removeValue(forKey: mac)
        connectingIDs.remove(mac)

        if let error {
            connectionErrors[mac] = error
            scheduleErrorClear(mac: mac)
        }

        refresh()
    }

    private func scheduleErrorClear(mac: String) {
        errorClearTasks[mac]?.cancel()
        errorClearTasks[mac] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.connectionErrors.removeValue(forKey: mac)
        }
    }

}