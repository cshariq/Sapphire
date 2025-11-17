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

    @Published var registeredFaceProfiles: [String] = []
    @Published var faceRegistrationController: CameraController?
    private(set) var profileNameToRegister: String = ""

    private var cameraController: CameraController?
    public let ble = BLE()
    private let settings = SettingsModel.shared
    private var cancellables = Set<AnyCancellable>()
    private var isBluetoothAuthenticating = false
    private var isFaceIDAuthenticating = false
    private var isUnlockInProgress = false
    private let passwordAccount = "SapphireUserPassword"

    private override init() {
        super.init()
        self.ble.delegate = self
        self.selectedDeviceID = settings.settings.bluetoothUnlockDeviceID
        self.isEnabled = settings.settings.bluetoothUnlockEnabled
        self.isPasswordSet = KeychainManager.shared.load(for: passwordAccount) != nil
        setupBindings()
        setupSettingsObserver()
        fetchRegisteredFaces()
    }

    func fetchRegisteredFaces() {
        self.registeredFaceProfiles = FaceDataStore.shared.getRegisteredProfileNames()
    }

    func beginFaceRegistration(profileName: String) {
        self.profileNameToRegister = profileName
        self.faceRegistrationController = CameraController()
    }

    func completeFaceRegistration() {
        self.faceRegistrationController = nil
        self.fetchRegisteredFaces()
        MLModelManager.shared.unloadModels()
    }

    func deleteFaceProfile(name: String) {
        FaceDataStore.shared.deleteProfile(name: name)
        fetchRegisteredFaces()
    }

    func startFaceIDAuthentication() {
        guard !isUnlockInProgress, !isFaceIDAuthenticating, settings.settings.faceIDUnlockEnabled, settings.settings.hasRegisteredFaceID, self.cameraController == nil else { return }
        print("LOG (FaceID): Creating new CameraController instance for authentication.")
        isFaceIDAuthenticating = true
        self.cameraController = CameraController()
        self.cameraController?.startAuthentication()
    }

    private func tearDownFaceID() {
        guard isFaceIDAuthenticating else { return }
        print("LOG (FaceID): Tearing down Face ID engine.")
        isFaceIDAuthenticating = false
        cameraController?.teardown()
        cameraController = nil
        DispatchQueue.global(qos: .utility).async {
            MLModelManager.shared.unloadModels()
        }
    }

    func stopAllAuthentication() {
        if isBluetoothAuthenticating {
            isBluetoothAuthenticating = false; ble.monitoredUUID = nil; status = "Disabled"; self.monitoredPeripheralState = .disconnected
        }
        if isFaceIDAuthenticating {
            tearDownFaceID()
        }
    }

    func handleUnlock() {
        guard !isUnlockInProgress else { return }
        isUnlockInProgress = true

        guard self.isScreenLocked else {
            print("[AuthManager] Unlock sequence aborted: Screen was unlocked manually just before auto-unlock.")
            isUnlockInProgress = false
            stopAllAuthentication()
            return
        }

        if settings.settings.bluetoothUnlockWakeOnProximity { (NSApp.delegate as? AppDelegate)?.wakeDisplay() }
        if settings.settings.bluetoothUnlockWakeWithoutUnlocking {
            isUnlockInProgress = false
            return
        }

        if isFaceIDAuthenticating {
            cameraController?.stopCameraSession()
        }

        self.unlockWithPassword()

        if isFaceIDAuthenticating {
            DispatchQueue.main.async {
                self.tearDownFaceID()
            }
        }
    }

    func didCompleteUnlock() {
        isUnlockInProgress = false
    }

    private func setupBindings() {
        settings.$settings.map(\.bluetoothUnlockEnabled).removeDuplicates().assign(to: \.isEnabled, on: self).store(in: &cancellables)
        settings.$settings.map(\.bluetoothUnlockDeviceID).removeDuplicates().assign(to: \.selectedDeviceID, on: self).store(in: &cancellables)
        $isEnabled.combineLatest($selectedDeviceID).sink { [weak self] (enabled, deviceID) in self?.updateMonitoringConfig(enabled: enabled, deviceID: deviceID) }.store(in: &cancellables)
    }

    private func setupSettingsObserver() {
        settings.$settings.receive(on: DispatchQueue.main).sink { [weak self] newSettings in
            guard let self = self else { return }
            self.ble.lockRSSI = newSettings.bluetoothUnlockLockRSSI; self.ble.unlockRSSI = newSettings.bluetoothUnlockUnlockRSSI
            self.ble.proximityTimeout = newSettings.bluetoothUnlockTimeout; self.ble.signalTimeout = newSettings.bluetoothUnlockNoSignalTimeout
            self.ble.setPassiveMode(newSettings.bluetoothUnlockPassiveMode)
        }.store(in: &cancellables)
    }

    func handleDisplayWillSleep() {
        cameraController?.stopCameraSession()
    }

    func handleDisplayDidWake() {
        if isFaceIDAuthenticating {
            cameraController?.startAuthentication()
        }
    }

    func startBluetoothAuthentication() {
        guard !isBluetoothAuthenticating, isEnabled, isPasswordSet, let deviceID = selectedDeviceID, let uuid = UUID(uuidString: deviceID) else { return }
        isBluetoothAuthenticating = true; ble.startMonitor(uuid: uuid); status = "Monitoring for device..."
    }

    func startScan(includeUnnamed: Bool) {
        guard ble.centralMgr.state == .poweredOn else { status = "Bluetooth is off"; return }
        ble.thresholdRSSI = settings.settings.bluetoothUnlockMinScanRSSI; scannedDevices.removeAll(); ble.devices.removeAll()
        isScanning = true; status = "Scanning..."; ble.startScanning(includeUnnamed: includeUnnamed)
    }

    func updateScanFilter(includeUnnamed: Bool) {
        ble.includeUnnamedDevices = includeUnnamed; if !includeUnnamed { scannedDevices.removeAll { $0.displayName == "Unnamed Device" } }
    }

    func stopScan() {
        isScanning = false; status = isEnabled ? "Monitoring" : "Idle"; ble.stopScanning()
    }

    func selectDevice(uuid: UUID) {
        settings.settings.bluetoothUnlockDeviceID = uuid.uuidString; stopScan()
    }

    func forgetDevice() {
        settings.settings.bluetoothUnlockDeviceID = nil; ble.monitoredUUID = nil; self.monitoredPeripheralState = .disconnected
    }

    func manualLock() {
        handleLock()
    }

    func removePassword() {
        _ = KeychainManager.shared.delete(for: passwordAccount); self.isPasswordSet = false
    }

    func verifyAndSavePassword(_ password: String) -> Bool {
        let process = Process(); process.launchPath = "/usr/bin/sudo"; process.arguments = ["-S", "-v"]; let pipe = Pipe(); process.standardInput = pipe; process.launch()
        if let data = (password + "\n").data(using: .utf8) { try? pipe.fileHandleForWriting.write(contentsOf: data); try? pipe.fileHandleForWriting.close() }
        process.waitUntilExit(); let success = process.terminationStatus == 0
        if success { _ = savePasswordToKeychain(password); self.isPasswordSet = true }; return success
    }

    private func updateMonitoringConfig(enabled: Bool, deviceID: String?) {
        if enabled, self.isPasswordSet, let id = deviceID, let uuid = UUID(uuidString: id) {
            if isBluetoothAuthenticating && ble.monitoredUUID == uuid {
                print("[AuthManager] Already monitoring \(id). No change needed.")
                return
            }
            print("[AuthManager] Starting/updating proximity monitoring for device \(id).")
            isBluetoothAuthenticating = true
            ble.startMonitor(uuid: uuid)
            status = "Monitoring for device..."
        } else {
            if isBluetoothAuthenticating {
                isBluetoothAuthenticating = false
                ble.stopMonitor()
                status = "Disabled"
                self.monitoredPeripheralState = .disconnected
                print("[AuthManager] Proximity monitoring stopped because it was disabled or device was forgotten.")
            }
        }
    }

    var isScreenLocked: Bool {
        (NSApp.delegate as? AppDelegate)?.isScreenLocked ?? false
    }

    private func unlockWithPassword() {
        guard let encrypted = KeychainManager.shared.load(for: passwordAccount), let decrypted = CryptoManager.shared.decrypt(data: encrypted), let password = String(data: decrypted, encoding: .utf8) else {
            showPasswordPrompt(); return
        }
        status = "Unlocking..."; guard let source = CGEventSource(stateID: .hidSystemState) else { status = "Unlock failed"; return }; let tapLocation = CGEventTapLocation.cghidEventTap
        let utf16chars = Array(password.utf16); var offset = 0
        while offset < utf16chars.count {
            var chunk = Array(utf16chars[offset..<min(offset + 20, utf16chars.count)])
            let pwEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            pwEvent?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk); pwEvent?.post(tap: tapLocation); offset += 20
        }
        let retDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true); let retUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        retDown?.post(tap: tapLocation); retUp?.post(tap: tapLocation); status = "Unlocked"
    }

    func newDevice(device: Device) {
        updateDevice(device: device)
    }

    func updateDevice(device: Device) {
        if let index = scannedDevices.firstIndex(where: { $0.id == device.id }) {
            scannedDevices[index] = device
        } else {
            scannedDevices.append(device)
        }
        scannedDevices.sort { $0.displayName < $1.displayName }
    }

    func removeDevice(device: Device) {
        scannedDevices.removeAll { $0.id == device.id }
    }

    func updateRSSI(rssi: Int?, active: Bool) {
        self.lastRSSI = rssi; guard let rssi = rssi else { status = "Searching..."; return }; let unlock = settings.settings.bluetoothUnlockUnlockRSSI, lock = settings.settings.bluetoothUnlockLockRSSI
        if rssi >= unlock {
            status = "Monitoring (Near)"
        } else if rssi < lock {
            status = "Monitoring (Far)"
        } else {
            status = "Monitoring (Safe Zone)"
        }
    }

    func bluetoothPowerWarn() {
        status = "Bluetooth is off!"
    }

    func updatePresence(presence: Bool, reason: String) {
        if isEnabled && isBluetoothAuthenticating {
            presence ? handleUnlock() : handleLock()
        }
    }

    private func handleLock() {
        if !isScreenLocked {
            if settings.settings.bluetoothUnlockPauseMusicOnLock { MusicManager.shared.pause() }
            settings.settings.bluetoothUnlockUseScreensaver ? startScreenSaver() : (_ = SACLockScreenImmediate())
            if settings.settings.bluetoothUnlockTurnOffScreenOnLock {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { (NSApp.delegate as? AppDelegate)?.sleepDisplay() }
            }
        }
    }

    private func startScreenSaver() {
        let p = Process(); p.launchPath = "/usr-bin/open"; p.arguments = ["-a", "ScreenSaverEngine"]; try? p.run()
    }

    private func savePasswordToKeychain(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8), let encrypted = CryptoManager.shared.encrypt(data: data) else { return false }
        return KeychainManager.shared.save(key: encrypted, for: passwordAccount)
    }

    private func showPasswordPrompt() {
        NotificationCenter.default.post(name: .init("SapphireShowPasswordPrompt"), object: nil)
    }
}