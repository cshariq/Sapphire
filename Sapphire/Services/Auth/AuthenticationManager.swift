//
//  AuthenticationManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Foundation
import Combine
import AppKit
import CoreBluetooth
import Security
import ApplicationServices
import os.log
import Darwin

@_silgen_name("CGSessionCopyCurrentDictionary")
private func CGSessionCopyCurrentDictionary() -> CFDictionary?

enum FaceIDAuthResult: Equatable {
    case success
    case failed
    case cancelled
}

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

    private var pendingAppLockFaceIDCompletion: ((FaceIDAuthResult) -> Void)?

    private var isFaceIDSessionForAppLock = false

    private var unlockAttemptID = UUID()
    private let passwordAccount = "SapphireUserPassword"

    private var rssiUpdateWorkItem: DispatchWorkItem?
    private var wasPreviouslyPresent = false
    private var pendingStatus: String?
    private var statusUpdateWorkItem: DispatchWorkItem?
    private let statusUpdateQueue = DispatchQueue(label: "auth.status.update", qos: .utility)

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

    // MARK: - Face ID Profile Management

    func fetchRegisteredFaces() {
        self.registeredFaceProfiles = FaceIDDataStore.shared.getRegisteredProfileNames()
    }

    func beginFaceRegistration(profileName: String) {
        self.profileNameToRegister = profileName
        if isFaceIDAuthenticating { tearDownFaceID() }
        if let old = faceRegistrationController { old.cancelCurrentOperation() }
        self.faceRegistrationController = CameraController()
    }

    func completeFaceRegistration() {
        faceRegistrationController?.cancelCurrentOperation()
        self.faceRegistrationController = nil
        self.fetchRegisteredFaces()
    }

    func deleteFaceProfile(name: String) {
        FaceIDDataStore.shared.deleteProfile(name: name)
        fetchRegisteredFaces()
    }

    // MARK: - Face ID Authentication

    func startFaceIDAuthentication() {
        let isForAppLock = pendingAppLockFaceIDCompletion != nil
        guard !isUnlockInProgress, !isFaceIDAuthenticating,
              (isForAppLock || settings.settings.faceIDUnlockEnabled),
              settings.settings.hasRegisteredFaceID else { return }

        isFaceIDSessionForAppLock = isForAppLock

        if let reg = faceRegistrationController {
            reg.cancelCurrentOperation()
            faceRegistrationController = nil
        }
        if let old = cameraController {
            old.cancelCurrentOperation()
        }
        isFaceIDAuthenticating = true
        let controller = CameraController()
        controller.onSecurityEvent = { [weak self] event in
            Task { @MainActor in self?.handleFaceIDSecurityEvent(event) }
        }
        self.cameraController = controller
        cameraController?.startAuthentication()
    }

    func startFaceIDAuthenticationForAppLock(completion: @escaping (FaceIDAuthResult) -> Void) {
        guard settings.settings.hasRegisteredFaceID else {
            completion(.failed)
            return
        }
        if isFaceIDAuthenticating { tearDownFaceID() }
        pendingAppLockFaceIDCompletion = completion
        startFaceIDAuthentication()
        if !isFaceIDAuthenticating {
            pendingAppLockFaceIDCompletion = nil
            completion(.failed)
        }
    }

    func handleFaceIDAuthenticated() {
        if let completion = pendingAppLockFaceIDCompletion {
            pendingAppLockFaceIDCompletion = nil
            tearDownFaceID()
            completion(.success)
        } else if !isFaceIDSessionForAppLock {
            handleUnlock()
        }
    }

    private func handleFaceIDSecurityEvent(_ event: FaceIDSecurityEvent) {
        guard isFaceIDAuthenticating else { return }
        tearDownFaceID()
        (NSApp.delegate as? AppDelegate)?.markFaceIDRequiresPassword()
        switch event {
        case .spoofLocked:
            setStatusThrottled("Face ID locked — spoof detected.")
        case .mismatchTimeout:
            setStatusThrottled("Face ID stopped — face not recognized.")
        }
    }

    private func tearDownFaceID(result: FaceIDAuthResult = .failed) {
        guard isFaceIDAuthenticating else { return }
        isFaceIDAuthenticating = false
        cameraController?.cancelCurrentOperation()
        cameraController = nil
        if let completion = pendingAppLockFaceIDCompletion {
            pendingAppLockFaceIDCompletion = nil
            completion(result)
        }
    }

    func cancelFaceIDAuthentication() {
        if isFaceIDAuthenticating { tearDownFaceID(result: .cancelled) }
    }

    func timeoutFaceIDAuthentication() {
        if isFaceIDAuthenticating { tearDownFaceID(result: .failed) }
    }

    var isFaceIDSessionActive: Bool { isFaceIDAuthenticating || cameraController != nil }

    func purgeFaceIDAfterUnlock() {
        if isFaceIDAuthenticating {
            tearDownFaceID()
        }
        malloc_zone_pressure_relief(nil, 0)
    }

    func stopAllAuthentication() {
        if isBluetoothAuthenticating {
            isBluetoothAuthenticating = false
            ble.monitoredUUID = nil
            setStatusThrottled("Disabled")
            self.monitoredPeripheralState = .disconnected
        }
        if isFaceIDAuthenticating {
            tearDownFaceID()
        }
    }

    // MARK: - Auto-Unlock Pipeline

    func handleUnlock() {
        guard !isUnlockInProgress else { return }
        isUnlockInProgress = true

        guard self.isScreenLocked else {
            print("[AuthManager] Screen already unlocked. Sequence aborted.")
            isUnlockInProgress = false
            stopAllAuthentication()
            return
        }

        if settings.settings.bluetoothUnlockWakeOnProximity || isFaceIDAuthenticating {
            (NSApp.delegate as? AppDelegate)?.wakeDisplay()
        }

        if settings.settings.bluetoothUnlockWakeWithoutUnlocking && !isFaceIDAuthenticating {
            isUnlockInProgress = false
            return
        }

        if isFaceIDAuthenticating {
            tearDownFaceID()
        }

        guard hasAccessibilityPermission(promptIfNeeded: true) else {
            setStatusThrottled("Enable Accessibility in System Settings to allow auto-unlock.")
            isUnlockInProgress = false
            stopAllAuthentication()
            return
        }

        setStatusThrottled("Unlocking...")
        let attemptID = UUID()
        unlockAttemptID = attemptID

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            guard self.unlockAttemptID == attemptID, self.isUnlockInProgress, self.isScreenLocked else {
                self.isUnlockInProgress = false
                return
            }
            self.unlockWithPassword(attempt: 1, attemptID: attemptID)
        }
    }

    func didCompleteUnlock() {
        unlockAttemptID = UUID()
        isUnlockInProgress = false
    }

    func cancelPendingPasswordInjection(reason: String) {
        print("[AuthManager] Cancelling pending password injection: \(reason)")
        unlockAttemptID = UUID()
        isUnlockInProgress = false
        stopAllAuthentication()
    }

    // MARK: - Password & HID Injection

    private func unlockWithPassword(attempt: Int = 1, attemptID: UUID) {
        guard unlockAttemptID == attemptID, isUnlockInProgress, isScreenLocked else {
            isUnlockInProgress = false
            return
        }

        guard let encrypted = KeychainManager.shared.load(for: passwordAccount),
              let decrypted = CryptoManager.shared.decrypt(data: encrypted),
              let password = String(data: decrypted, encoding: .utf8) else {
            setStatusThrottled("Password not set")
            showPasswordPrompt()
            isUnlockInProgress = false
            return
        }

        var passwordData = decrypted
        defer { passwordData.resetBytes(in: 0..<passwordData.count) }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            setStatusThrottled("Unlock failed")
            isUnlockInProgress = false
            return
        }

        let tapLocation = CGEventTapLocation.cghidEventTap
        (NSApp.delegate as? AppDelegate)?.wakeDisplay()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            guard self.unlockAttemptID == attemptID, self.isUnlockInProgress,
                  self.isScreenLocked, Self.isScreenActuallyLocked() else {
                self.isUnlockInProgress = false
                return
            }

            var utf16chars = Array(password.utf16)
            defer { for i in utf16chars.indices { utf16chars[i] = 0 } }

            if let pwDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                pwDown.keyboardSetUnicodeString(stringLength: utf16chars.count, unicodeString: &utf16chars)
                pwDown.post(tap: tapLocation)
            }
            if let pwUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                pwUp.post(tap: tapLocation)
            }

            let retDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
            let retUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
            retDown?.post(tap: tapLocation)
            retUp?.post(tap: tapLocation)

            self.setStatusThrottled("Unlocked")

            if attempt < 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    if self.unlockAttemptID == attemptID && self.isScreenLocked {
                        print("[AuthManager] Screen still locked — retrying password entry.")
                        self.unlockWithPassword(attempt: attempt + 1, attemptID: attemptID)
                    } else {
                        self.didCompleteUnlock()
                    }
                }
            } else {
                self.didCompleteUnlock()
            }
        }
    }

    // MARK: - Bluetooth Auth Control

    func startBluetoothAuthentication() {
        guard !isBluetoothAuthenticating, isEnabled, isPasswordSet,
              let deviceID = selectedDeviceID, let uuid = UUID(uuidString: deviceID) else { return }

        isBluetoothAuthenticating = true
        ble.startMonitor(uuid: uuid)
        setStatusThrottled("Monitoring for device...")
    }

    func startScan(includeUnnamed: Bool) {
        guard ble.centralMgr.state == .poweredOn else { setStatusThrottled("Bluetooth is off"); return }
        ble.thresholdRSSI = settings.settings.bluetoothUnlockMinScanRSSI
        scannedDevices.removeAll()
        ble.devices.removeAll()
        isScanning = true
        setStatusThrottled("Scanning...")
        ble.startScanning(includeUnnamed: includeUnnamed)
    }

    func updateScanFilter(includeUnnamed: Bool) {
        ble.includeUnnamedDevices = includeUnnamed
        if !includeUnnamed { scannedDevices.removeAll { $0.displayName == "Unnamed Device" } }
    }

    func stopScan() {
        isScanning = false
        setStatusThrottled(isEnabled ? "Monitoring" : "Idle")
        ble.stopScanning()
    }

    func selectDevice(uuid: UUID) {
        settings.settings.bluetoothUnlockDeviceID = uuid.uuidString
        stopScan()
    }

    func forgetDevice() {
        settings.settings.bluetoothUnlockDeviceID = nil
        ble.monitoredUUID = nil
        self.monitoredPeripheralState = .disconnected
    }

    // MARK: - Passwords & Lifecycle

    func manualLock() { handleLock() }

    func removePassword() {
        _ = KeychainManager.shared.delete(for: passwordAccount)
        self.isPasswordSet = false
    }

    func verifyAndSavePassword(_ password: String) -> Bool {
        guard verifyMacLoginPassword(password) else { return false }
        if savePasswordToKeychain(password) {
            self.isPasswordSet = true
            return true
        }
        return false
    }

    func verifyMacLoginPassword(_ password: String) -> Bool { verifyLoginPassword(password) }

    func verifyPassword(_ password: String) -> Bool {
        guard let encrypted = KeychainManager.shared.load(for: passwordAccount),
              let decrypted = CryptoManager.shared.decrypt(data: encrypted),
              let stored = String(data: decrypted, encoding: .utf8) else { return false }
        return stored.utf8.elementsEqual(password.utf8)
    }

    // MARK: - System Observers & Delegates

    private func setupBindings() {
        settings.$settings.map(\.bluetoothUnlockEnabled).removeDuplicates().assign(to: \.isEnabled, on: self).store(in: &cancellables)
        settings.$settings.map(\.bluetoothUnlockDeviceID).removeDuplicates().assign(to: \.selectedDeviceID, on: self).store(in: &cancellables)
        $isEnabled.combineLatest($selectedDeviceID).sink { [weak self] (enabled, deviceID) in self?.updateMonitoringConfig(enabled: enabled, deviceID: deviceID) }.store(in: &cancellables)
    }

    private func setupSettingsObserver() {
        settings.$settings.receive(on: DispatchQueue.main).sink { [weak self] newSettings in
            guard let self = self else { return }
            self.ble.lockRSSI = newSettings.bluetoothUnlockLockRSSI
            self.ble.unlockRSSI = newSettings.bluetoothUnlockUnlockRSSI
            self.ble.proximityTimeout = newSettings.bluetoothUnlockTimeout
            self.ble.signalTimeout = newSettings.bluetoothUnlockNoSignalTimeout
            self.ble.setPassiveMode(newSettings.bluetoothUnlockPassiveMode)
        }.store(in: &cancellables)
    }

    func handleDisplayWillSleep() {
        if isFaceIDAuthenticating { cameraController?.stopCameraSession() }
    }

    func handleDisplayDidWake() {
        if isFaceIDAuthenticating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.cameraController?.startAuthentication()
            }
        }
    }

    func handleSystemDidWake() {
        guard isFaceIDAuthenticating else { return }
        tearDownFaceID()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isScreenLocked else { return }
            self.startFaceIDAuthentication()
        }
    }

    func newDevice(device: Device) { updateDevice(device: device) }

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
        self.lastRSSI = rssi
        rssiUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let rssi = rssi else { self.setStatusThrottled("Searching..."); return }
            let unlock = self.settings.settings.bluetoothUnlockUnlockRSSI
            let lock = self.settings.settings.bluetoothUnlockLockRSSI
            let newStatus: String

            if rssi >= unlock { newStatus = "Monitoring (Near)" }
            else if rssi < lock { newStatus = "Monitoring (Far)" }
            else { newStatus = "Monitoring (Safe Zone)" }
            self.setStatusThrottled(newStatus)
        }
        rssiUpdateWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func bluetoothPowerWarn() { setStatusThrottled("Bluetooth is off!") }

    func updatePresence(presence: Bool, reason: String) {
        if isEnabled && isBluetoothAuthenticating {
            if presence {
                if !wasPreviouslyPresent, !isUnlockInProgress { handleUnlock() }
            } else {
                handleLock()
            }
            wasPreviouslyPresent = presence
        }
    }

    // MARK: - Utilities

    private func updateMonitoringConfig(enabled: Bool, deviceID: String?) {
        if enabled, self.isPasswordSet, let id = deviceID, let uuid = UUID(uuidString: id) {
            if isBluetoothAuthenticating && ble.monitoredUUID == uuid { return }
            isBluetoothAuthenticating = true
            ble.startMonitor(uuid: uuid)
            setStatusThrottled("Monitoring for device...")
        } else {
            if isBluetoothAuthenticating {
                isBluetoothAuthenticating = false
                ble.stopMonitor()
                setStatusThrottled("Disabled")
                self.monitoredPeripheralState = .disconnected
            }
        }
    }

    var isScreenLocked: Bool { (NSApp.delegate as? AppDelegate)?.isScreenLocked ?? false }

    var isBluetoothMonitoringActive: Bool {
        isBluetoothAuthenticating
    }

    private static func isScreenActuallyLocked() -> Bool {
        guard let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return (sessionDict["CGSSessionScreenIsLocked"] as? Bool) ?? true
    }

    private func hasAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        let trusted = AccessibilityTrustMonitor.shared.isTrusted
        if !trusted && promptIfNeeded {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return trusted
    }

    private func handleLock() {
        if !isScreenLocked {
            if settings.settings.bluetoothUnlockPauseMusicOnLock { Task { await MusicManager.shared.pause() } }
            settings.settings.bluetoothUnlockUseScreensaver ? startScreenSaver() : (_ = SACLockScreenImmediate())
            if settings.settings.bluetoothUnlockTurnOffScreenOnLock {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { (NSApp.delegate as? AppDelegate)?.sleepDisplay() }
            }
        }
    }

    private func startScreenSaver() {
        let p = Process(); p.launchPath = "/usr/bin/open"; p.arguments = ["-a", "ScreenSaverEngine"]; try? p.run()
    }

    private func savePasswordToKeychain(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8), let encrypted = CryptoManager.shared.encrypt(data: data) else { return false }
        return KeychainManager.shared.save(key: encrypted, for: passwordAccount)
    }

    private func verifyLoginPassword(_ password: String) -> Bool {
        guard !password.isEmpty else { return false }
        let userName = currentLoginUserName()
        guard !userName.isEmpty else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-authonly", userName, password]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("[AuthManager] dscl authonly failed: \(error)")
            return false
        }
    }

    private func currentLoginUserName() -> String {
        if let passwd = getpwuid(getuid()) { return String(cString: passwd.pointee.pw_name) }
        return NSUserName()
    }

    private func showPasswordPrompt() {
        NotificationCenter.default.post(name: .init("SapphireShowPasswordPrompt"), object: nil)
    }

    private func setStatusThrottled(_ newStatus: String, throttle: TimeInterval = 0.2) {
        if status == newStatus { return }
        pendingStatus = newStatus
        statusUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let pending = self.pendingStatus else { return }
            DispatchQueue.main.async { if self.status != pending { self.status = pending } }
        }
        statusUpdateWorkItem = work
        statusUpdateQueue.asyncAfter(deadline: .now() + throttle, execute: work)
    }
}