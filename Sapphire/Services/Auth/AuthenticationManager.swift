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

private struct BluetoothAuthenticationSettings: Equatable {
    let lockRSSI: Int
    let unlockRSSI: Int
    let proximityTimeout: Double
    let signalTimeout: Double
    let passiveMode: Bool

    init(_ settings: Settings) {
        lockRSSI = settings.bluetoothUnlockLockRSSI
        unlockRSSI = settings.bluetoothUnlockUnlockRSSI
        proximityTimeout = settings.bluetoothUnlockTimeout
        signalTimeout = settings.bluetoothUnlockNoSignalTimeout
        passiveMode = settings.bluetoothUnlockPassiveMode
    }
}

private struct FaceIDLocationSettings: Equatable {
    let policy: FaceIDLocationPolicy
    let allowedWiFiNetworks: [String]

    init(_ settings: Settings) {
        policy = settings.faceIDLocationPolicy
        allowedWiFiNetworks = settings.faceIDAllowedWiFiNetworks
    }
}

@MainActor
class AuthenticationManager: NSObject, ObservableObject, BLEDelegate {
    static let shared = AuthenticationManager()

    @Published var isEnabled = false
    @Published var status: String = String(localized: "Disabled")
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
        self.selectedDeviceID = settings.current.bluetoothUnlockDeviceID
        self.isEnabled = settings.current.bluetoothUnlockEnabled
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
              isForAppLock || !isFaceIDLockedUntilPasswordUnlock,
              (isForAppLock || settings.current.faceIDUnlockEnabled),
              settings.current.hasRegisteredFaceID,
              isFaceIDAllowedAtCurrentLocation() else { return }

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
        guard settings.current.hasRegisteredFaceID else {
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

    private var isFaceIDLockedUntilPasswordUnlock = false

    private func handleFaceIDSecurityEvent(_ event: FaceIDSecurityEvent) {
        guard isFaceIDAuthenticating else { return }
        if !isFaceIDSessionForAppLock { isFaceIDLockedUntilPasswordUnlock = true }
        tearDownFaceID()
        (NSApp.delegate as? AppDelegate)?.markFaceIDRequiresPassword()
        switch event {
        case .spoofLocked:
            setStatusThrottled(String(localized: "Face ID locked — spoof detected."))
        case .mismatchTimeout:
            setStatusThrottled(String(localized: "Face ID stopped — face not recognized."))
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

    var faceIDLocationDescription: String {
        let settings = settings.settings
        guard settings.faceIDLocationPolicy == .selectedWiFiNetworks else { return String(localized: "Everywhere") }
        guard let networkName = WiFiStatusMonitor.shared.state.networkName else { return String(localized: "No Wi-Fi network") }
        return settings.faceIDAllowedWiFiNetworks.contains(networkName) ? networkName : String(localized: "\(networkName) is not allowed")
    }

    func isFaceIDAllowedAtCurrentLocation() -> Bool {
        let settings = settings.settings
        guard settings.faceIDLocationPolicy == .selectedWiFiNetworks else { return true }
        guard let networkName = WiFiStatusMonitor.shared.state.networkName else { return false }
        return settings.faceIDAllowedWiFiNetworks.contains(networkName)
    }

    func refreshFaceIDLocation(completion: (() -> Void)? = nil) {
        WiFiStatusMonitor.shared.refresh(completion: completion)
    }

    private func handleFaceIDLocationChange() {
        guard settings.current.faceIDLocationPolicy == .selectedWiFiNetworks else { return }
        if !isFaceIDAllowedAtCurrentLocation(), isFaceIDAuthenticating {
            tearDownFaceID()
            setStatusThrottled(String(localized: "Face ID unavailable at this location."))
        }
        (NSApp.delegate as? AppDelegate)?.refreshFaceIDLocationAvailability()
    }

    func handleSystemWakeFaceID() {
        guard isScreenLocked else { return }
        guard settings.current.faceIDLocationPolicy == .selectedWiFiNetworks else {
            startFaceIDAuthentication()
            return
        }
        refreshFaceIDLocation { [weak self] in
            guard let self, self.isScreenLocked else { return }
            self.startFaceIDAuthentication()
        }
    }

    func purgeFaceIDAfterUnlock() {
        isFaceIDLockedUntilPasswordUnlock = false
        if isFaceIDAuthenticating {
            tearDownFaceID()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    func stopAllAuthentication() {
        if isBluetoothAuthenticating {
            isBluetoothAuthenticating = false
            ble.monitoredUUID = nil
            setStatusThrottled(String(localized: "Disabled"))
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

        if settings.current.bluetoothUnlockWakeOnProximity || isFaceIDAuthenticating {
            (NSApp.delegate as? AppDelegate)?.wakeDisplay()
        }

        if settings.current.bluetoothUnlockWakeWithoutUnlocking && !isFaceIDAuthenticating {
            isUnlockInProgress = false
            return
        }

        if isFaceIDAuthenticating {
            tearDownFaceID()
        }

        guard hasAccessibilityPermission(promptIfNeeded: true) else {
            setStatusThrottled(String(localized: "Enable Accessibility in System Settings to allow auto-unlock."))
            isUnlockInProgress = false
            stopAllAuthentication()
            return
        }

        setStatusThrottled(String(localized: "Unlocking..."))
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
            setStatusThrottled(String(localized: "Password not set"))
            showPasswordPrompt()
            isUnlockInProgress = false
            return
        }

        var passwordData = decrypted
        defer { passwordData.resetBytes(in: 0..<passwordData.count) }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            setStatusThrottled(String(localized: "Unlock failed"))
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

            self.setStatusThrottled(String(localized: "Unlocked"))

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
        setStatusThrottled(String(localized: "Monitoring for device..."))
    }

    func startScan(includeUnnamed: Bool) {
        guard ble.centralMgr.state == .poweredOn else { setStatusThrottled(String(localized: "Bluetooth is off")); return }
        ble.thresholdRSSI = settings.current.bluetoothUnlockMinScanRSSI
        scannedDevices.removeAll()
        ble.devices.removeAll()
        isScanning = true
        setStatusThrottled(String(localized: "Scanning..."))
        ble.startScanning(includeUnnamed: includeUnnamed)
    }

    func updateScanFilter(includeUnnamed: Bool) {
        ble.includeUnnamedDevices = includeUnnamed
        if !includeUnnamed { scannedDevices.removeAll { $0.isUnnamed } }
    }

    func stopScan() {
        isScanning = false
        setStatusThrottled(isEnabled ? String(localized: "authentication.monitoring", defaultValue: "Monitoring") : String(localized: "Idle"))
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
        settings.changes(of: { $0.bluetoothUnlockEnabled })
            .prepend(settings.current.bluetoothUnlockEnabled)
            .assign(to: \.isEnabled, on: self)
            .store(in: &cancellables)
        settings.changes(of: { $0.bluetoothUnlockDeviceID })
            .prepend(settings.current.bluetoothUnlockDeviceID)
            .assign(to: \.selectedDeviceID, on: self)
            .store(in: &cancellables)
        $isEnabled.combineLatest($selectedDeviceID).sink { [weak self] (enabled, deviceID) in self?.updateMonitoringConfig(enabled: enabled, deviceID: deviceID) }.store(in: &cancellables)
    }

    private func setupSettingsObserver() {
        settings.changes(of: BluetoothAuthenticationSettings.init)
            .prepend(BluetoothAuthenticationSettings(settings.settings))
            .sink { [weak self] configuration in
                guard let self else { return }
                self.ble.lockRSSI = configuration.lockRSSI
                self.ble.unlockRSSI = configuration.unlockRSSI
                self.ble.proximityTimeout = configuration.proximityTimeout
                self.ble.signalTimeout = configuration.signalTimeout
                self.ble.setPassiveMode(configuration.passiveMode)
            }
            .store(in: &cancellables)

        settings.changes(of: FaceIDLocationSettings.init)
            .prepend(FaceIDLocationSettings(settings.settings))
            .sink { [weak self] _ in self?.handleFaceIDLocationChange() }
            .store(in: &cancellables)

        WiFiStatusMonitor.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleFaceIDLocationChange() }
            .store(in: &cancellables)
    }

    func handleDisplayWillSleep() {
        if isFaceIDAuthenticating { cameraController?.stopCameraSession() }
    }

    func handleDisplayDidWake() {
        if isFaceIDAuthenticating {
            print("[FaceID timing] display wake: resuming session")
            cameraController?.resumeAfterDisplayWake()
        }
    }

    func handleSystemDidWake() {
        guard isFaceIDAuthenticating else { return }
        print("[FaceID timing] system wake: restarting Face ID")
        tearDownFaceID()
        handleSystemWakeFaceID()
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
            guard let rssi = rssi else { self.setStatusThrottled(String(localized: "Searching...")); return }
            let unlock = self.settings.current.bluetoothUnlockUnlockRSSI
            let lock = self.settings.current.bluetoothUnlockLockRSSI
            let newStatus: String

            if rssi >= unlock { newStatus = String(localized: "Monitoring (Near)") }
            else if rssi < lock { newStatus = String(localized: "Monitoring (Far)") }
            else { newStatus = String(localized: "Monitoring (Safe Zone)") }
            self.setStatusThrottled(newStatus)
        }
        rssiUpdateWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func bluetoothPowerWarn() { setStatusThrottled(String(localized: "Bluetooth is off!")) }

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
            setStatusThrottled(String(localized: "Monitoring for device..."))
        } else {
            if isBluetoothAuthenticating {
                isBluetoothAuthenticating = false
                ble.stopMonitor()
                setStatusThrottled(String(localized: "Disabled"))
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
            AccessibilityPermission.prompt()
        }
        return trusted
    }

    private func handleLock() {
        if !isScreenLocked {
            if settings.current.bluetoothUnlockPauseMusicOnLock { Task { await MusicManager.shared.pause() } }
            settings.current.bluetoothUnlockUseScreensaver ? startScreenSaver() : (_ = SACLockScreenImmediate())
            if settings.current.bluetoothUnlockTurnOffScreenOnLock {
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