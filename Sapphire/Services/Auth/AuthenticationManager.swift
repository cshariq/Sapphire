//
//  AuthenticationManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-07.
//

import Foundation
import Combine
import AppKit
import CoreBluetooth
import Security
import os.log

@MainActor
class AuthenticationManager: NSObject, ObservableObject, BLEDelegate {
    static let shared = AuthenticationManager()

    @Published var isEnabled = false
    @Published var status: String = "Disabled"
    @Published var scannedDevices: [Device] = []
    @Published var isScanning = false
    @Published var selectedDeviceID: String?
    @Published var lastRSSI: Int?
    @Published var isPasswordSet: Bool = false
    @Published var monitoredPeripheralState: CBPeripheralState = .disconnected

    public lazy var cameraController = CameraController()

    public let ble = BLE()

    private let settings = SettingsModel.shared
    private var cancellables = Set<AnyCancellable>()

    private var isBluetoothAuthenticating = false
    private var isFaceIDAuthenticating = false

    private let passwordAccount = "SapphireUserPassword"

    private override init() {
        super.init()
        self.ble.delegate = self

        self.selectedDeviceID = settings.settings.bluetoothUnlockDeviceID
        self.isEnabled = settings.settings.bluetoothUnlockEnabled
        self.isPasswordSet = KeychainManager.shared.load(for: passwordAccount) != nil

        setupBindings()
        setupSettingsObserver()
    }

    private func setupBindings() {
        settings.$settings.map(\.bluetoothUnlockEnabled).removeDuplicates().assign(to: \.isEnabled, on: self).store(in: &cancellables)
        settings.$settings.map(\.bluetoothUnlockDeviceID).removeDuplicates().assign(to: \.selectedDeviceID, on: self).store(in: &cancellables)

        $isEnabled.combineLatest($selectedDeviceID)
            .sink { [weak self] (enabled, deviceID) in
                self?.updateMonitoringConfig(enabled: enabled, deviceID: deviceID)
            }
            .store(in: &cancellables)
    }

    private func setupSettingsObserver() {
        settings.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                guard let self = self else { return }

                self.ble.lockRSSI = newSettings.bluetoothUnlockLockRSSI
                self.ble.unlockRSSI = newSettings.bluetoothUnlockUnlockRSSI
                self.ble.proximityTimeout = newSettings.bluetoothUnlockTimeout
                self.ble.signalTimeout = newSettings.bluetoothUnlockNoSignalTimeout
                self.ble.setPassiveMode(newSettings.bluetoothUnlockPassiveMode)
            }
            .store(in: &cancellables)
    }

    func handleDisplayWillSleep() {
        if isFaceIDAuthenticating {
            cameraController.stopSession()
        }
    }

    func handleDisplayDidWake() {
        if isFaceIDAuthenticating {
            cameraController.startSession()
        }
    }

    func startBluetoothAuthentication() {
        guard !isBluetoothAuthenticating, isEnabled, isPasswordSet, let deviceID = selectedDeviceID, let uuid = UUID(uuidString: deviceID) else { return }
        isBluetoothAuthenticating = true
        ble.startMonitor(uuid: uuid)
        status = "Monitoring for device..."
    }

    func startFaceIDAuthentication() {
        guard !isFaceIDAuthenticating, settings.settings.faceIDUnlockEnabled, settings.settings.hasRegisteredFaceID else { return }
        isFaceIDAuthenticating = true
        cameraController.startAuthentication()
    }

    func stopAllAuthentication() {
        if isBluetoothAuthenticating {
            isBluetoothAuthenticating = false
            ble.monitoredUUID = nil
            status = "Disabled"
            self.monitoredPeripheralState = .disconnected
        }
        if isFaceIDAuthenticating {
            isFaceIDAuthenticating = false
            cameraController.stopSession()
            cameraController.handleManualUnlock()
        }
    }

    func startScan(includeUnnamed: Bool) {
        guard ble.centralMgr.state == .poweredOn else { status = "Bluetooth is off"; return }
        ble.thresholdRSSI = settings.settings.bluetoothUnlockMinScanRSSI

        scannedDevices.removeAll()
        // It's also good practice to clear the BLE manager's device cache on a fresh scan
        ble.devices.removeAll()

        isScanning = true
        status = "Scanning..."
        ble.startScanning(includeUnnamed: includeUnnamed)
    }

    func updateScanFilter(includeUnnamed: Bool) {
        ble.includeUnnamedDevices = includeUnnamed
        
        if !includeUnnamed {
            scannedDevices.removeAll { $0.displayName == "Unnamed Device" }
        }
    }

    func stopScan() {
        isScanning = false
        status = isEnabled ? "Monitoring" : "Idle"
        ble.stopScanning()
    }

    func selectDevice(uuid: UUID) {
        settings.settings.bluetoothUnlockDeviceID = uuid.uuidString; stopScan()
    }

    func forgetDevice() {
        settings.settings.bluetoothUnlockDeviceID = nil
        ble.monitoredUUID = nil
        self.monitoredPeripheralState = .disconnected
    }

    func manualLock() { handleLock() }

    func removePassword() {
        _ = KeychainManager.shared.delete(for: passwordAccount)
        self.isPasswordSet = false
    }

    func verifyAndSavePassword(_ password: String) -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/sudo"; process.arguments = ["-S", "-v"]
        let pipe = Pipe(); process.standardInput = pipe
        process.launch()
        if let data = (password + "\n").data(using: .utf8) {
            try? pipe.fileHandleForWriting.write(contentsOf: data)
            try? pipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        let success = process.terminationStatus == 0
        if success { _ = savePasswordToKeychain(password); self.isPasswordSet = true }
        return success
    }

    private func updateMonitoringConfig(enabled: Bool, deviceID: String?) {
        if enabled, self.isPasswordSet, deviceID != nil {
            if !isBluetoothAuthenticating { status = "Ready to monitor" }
        } else {
            status = "Disabled"
            self.monitoredPeripheralState = .disconnected
        }
    }

    var isScreenLocked: Bool {
        (NSApp.delegate as? AppDelegate)?.isScreenLocked ?? false
    }

    func handleUnlock() {
        if settings.settings.bluetoothUnlockWakeOnProximity, let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.wakeDisplay()
        }
        if settings.settings.bluetoothUnlockWakeWithoutUnlocking { return }
        if cameraController.captureSession.isRunning { cameraController.stopSession() }
        self.unlockWithPassword()
    }

    private func unlockWithPassword() {
        guard let encrypted = KeychainManager.shared.load(for: passwordAccount) else { showPasswordPrompt(); return }
        guard let decrypted = CryptoManager.shared.decrypt(data: encrypted), let password = String(data: decrypted, encoding: .utf8) else { showPasswordPrompt(); return }

        status = "Unlocking..."
        guard let source = CGEventSource(stateID: .hidSystemState) else { status = "Unlock failed"; return }
        let tapLocation = CGEventTapLocation.cghidEventTap

        let chunkSize = 20
        let utf16chars = Array(password.utf16)
        let totalChars = utf16chars.count
        var offset = 0

        while offset < totalChars {
            let chunkLength = min(chunkSize, totalChars - offset)
            var chunk = Array(utf16chars[offset..<(offset + chunkLength)])
            
            let passwordEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            passwordEvent?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            passwordEvent?.post(tap: tapLocation)
            
            offset += chunkLength
        }

        let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        returnDown?.post(tap: tapLocation)
        returnUp?.post(tap: tapLocation)

        status = "Unlocked"
    }

    // MARK: - BLEDelegate Methods (Corrected)

    func newDevice(device: Device) {
        // This method now forwards to the more robust updateDevice method.
        updateDevice(device: device)
    }

    func updateDevice(device: Device) {
        // This is the key fix. It now handles both updates and inserts.
        if let index = scannedDevices.firstIndex(where: { $0.id == device.id }) {
            // Device is already in the list, so update its data.
            scannedDevices[index] = device
        } else {
            // Device is NOT in the list (e.g., after a rescan), so add it.
            scannedDevices.append(device)
        }
        // Always re-sort the list after any modification to keep it alphabetical.
        scannedDevices.sort { $0.displayName < $1.displayName }
    }

    func removeDevice(device: Device) {
        scannedDevices.removeAll { $0.id == device.id }
    }

    func updateRSSI(rssi: Int?, active: Bool) {
        self.lastRSSI = rssi
        guard let currentRSSI = rssi else { status = "Searching for device..."; return }
        let unlockThreshold = settings.settings.bluetoothUnlockUnlockRSSI
        let lockThreshold = settings.settings.bluetoothUnlockLockRSSI
        if currentRSSI >= unlockThreshold { status = "Monitoring (Device is Near)" }
        else if currentRSSI < lockThreshold { status = "Monitoring (Device is Far)" }
        else { status = "Monitoring (In Safe Zone)" }
    }

    func bluetoothPowerWarn() { status = "Bluetooth is powered off!" }

    func updatePresence(presence: Bool, reason: String) {
        guard isEnabled && isBluetoothAuthenticating else { return }
        presence ? handleUnlock() : handleLock()
    }

    private func handleLock() {
        if !isScreenLocked {
            if settings.settings.bluetoothUnlockPauseMusicOnLock { MusicManager.shared.pause() }
            settings.settings.bluetoothUnlockUseScreensaver ? startScreenSaver() : (_ = SACLockScreenImmediate())
            if settings.settings.bluetoothUnlockTurnOffScreenOnLock {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    (NSApp.delegate as? AppDelegate)?.sleepDisplay()
                }
            }
        }
    }

    private func startScreenSaver() {
        let process = Process()
        process.launchPath = "/usr/bin/open"; process.arguments = ["-a", "ScreenSaverEngine"]
        try? process.run()
    }

    private func savePasswordToKeychain(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8), let encrypted = CryptoManager.shared.encrypt(data: data) else { return false }
        return KeychainManager.shared.save(key: encrypted, for: passwordAccount)
    }

    private func showPasswordPrompt() {
        NotificationCenter.default.post(name: .init("SapphireShowPasswordPrompt"), object: nil)
    }
}
