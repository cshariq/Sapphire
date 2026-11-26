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
import OpenDirectory

@_silgen_name("CGSessionCopyCurrentDictionary")
private func CGSessionCopyCurrentDictionary() -> CFDictionary?

enum FaceIDAuthResult: Equatable {
    case success
    case failed
    case cancelled
}

extension Notification.Name {
    static let continuityPairedPeersDidChange = Notification.Name("continuityPairedPeersDidChange")
    static let continuityPhoneLockStateDidChange = Notification.Name("continuityPhoneLockStateDidChange")
}

struct ContinuityDeviceOption: Equatable, Identifiable {
    let peerID: String
    let name: String
    let isTablet: Bool
    /// Nil until the device has connected to this Mac over Bluetooth LE, which is what proximity is measured on.
    let peripheralID: String?
    var id: String { peerID }
}

private struct BluetoothAuthenticationSettings: Equatable {
    let lockRSSI: Int
    let unlockRSSI: Int
    let proximityTimeout: Double
    let signalTimeout: Double
    let passiveMode: Bool
    let fastMode: Bool

    init(_ settings: Settings) {
        lockRSSI = settings.bluetoothUnlockLockRSSI
        unlockRSSI = settings.bluetoothUnlockUnlockRSSI
        proximityTimeout = settings.bluetoothUnlockTimeout
        signalTimeout = settings.bluetoothUnlockNoSignalTimeout
        passiveMode = settings.bluetoothUnlockPassiveMode
        fastMode = settings.bluetoothUnlockFastResponse && !settings.bluetoothUnlockPassiveMode
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
    @Published private(set) var continuityDevices: [ContinuityDeviceOption] = []

    /// The selected Continuity device, or else the most recently seen phone that can be monitored.
    var continuityPhoneSuggestion: ContinuityDeviceOption? {
        let usable = continuityDevices.filter { $0.peripheralID != nil }
        return usable.first { $0.peerID == settings.current.bluetoothUnlockContinuityPeerID }
            ?? usable.first { !$0.isTablet }
    }
    @Published private(set) var phoneLockStates: [String: Bool] = [:]
    @Published private(set) var watchFlags: TrustedWatchFlags?

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

    /// Face ID matched on the lock screen and is waiting for a key press before unlocking.
    @Published private(set) var isAwaitingUnlockConfirmation = false
    private var unlockConfirmKeyListener: UnlockConfirmKeyListener?
    private var unlockConfirmationExpiry: DispatchWorkItem?
    /// How long a match stays valid. After that Face ID scans again, so a match can't wait for someone else to press a key.
    private static let unlockConfirmationWindow: TimeInterval = 15

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
        setupContinuityPhoneObserver()
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
        if !isForAppLock { FaceIDIlluminator.shared.sessionStarted() }
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
        // A frame still in flight when the session was torn down must not unlock.
        guard isFaceIDAuthenticating else { return }
        if let completion = pendingAppLockFaceIDCompletion {
            pendingAppLockFaceIDCompletion = nil
            tearDownFaceID()
            completion(.success)
        } else if !isFaceIDSessionForAppLock {
            if settings.current.faceIDRequireKeyToUnlock {
                awaitUnlockConfirmation()
            } else {
                handleUnlock(fromFaceID: true)
            }
        }
    }

    // MARK: - Confirm Before Unlocking

    private func awaitUnlockConfirmation() {
        guard isScreenLocked, !isUnlockInProgress else { return }
        tearDownFaceID(result: .success)

        let listener = UnlockConfirmKeyListener { [weak self] in
            Task { @MainActor in self?.confirmUnlock() }
        }
        guard listener.start() else {
            // Without Input Monitoring no key can confirm, so leave the Mac locked rather than unlock unasked.
            setStatusThrottled(String(localized: "Allow Input Monitoring for Sapphire to confirm Face ID with a key press."))
            (NSApp.delegate as? AppDelegate)?.markFaceIDRequiresPassword()
            return
        }
        unlockConfirmKeyListener = listener
        isAwaitingUnlockConfirmation = true
        (NSApp.delegate as? AppDelegate)?.setFaceIDAwaitingConfirmation(true)
        setStatusThrottled(String(localized: "Face recognized. Press Return or any key to unlock."))

        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.isAwaitingUnlockConfirmation else { return }
            self.endUnlockConfirmation()
            if self.isScreenLocked { self.startFaceIDAuthentication() }
        }
        unlockConfirmationExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.unlockConfirmationWindow, execute: expiry)
    }

    private func confirmUnlock() {
        guard isAwaitingUnlockConfirmation, isScreenLocked else { return }
        endUnlockConfirmation()
        // Space typed a character into the password field, so clear it before the password goes in.
        handleUnlock(fromFaceID: true, clearPasswordField: true)
    }

    private func endUnlockConfirmation() {
        unlockConfirmationExpiry?.cancel()
        unlockConfirmationExpiry = nil
        unlockConfirmKeyListener?.stop()
        unlockConfirmKeyListener = nil
        guard isAwaitingUnlockConfirmation else { return }
        isAwaitingUnlockConfirmation = false
        (NSApp.delegate as? AppDelegate)?.setFaceIDAwaitingConfirmation(false)
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
        FaceIDIlluminator.shared.end()
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
        endUnlockConfirmation()
        if isFaceIDAuthenticating {
            tearDownFaceID()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    private func stopUnlockAttemptAuthentication() {
        endUnlockConfirmation()
        if isFaceIDAuthenticating {
            tearDownFaceID()
        }
    }

    // MARK: - Auto-Unlock Pipeline

    func handleUnlock(fromFaceID: Bool = false, clearPasswordField: Bool = false) {
        guard !isUnlockInProgress else { return }
        isUnlockInProgress = true

        guard self.isScreenLocked else {
            print("[AuthManager] Screen already unlocked. Sequence aborted.")
            isUnlockInProgress = false
            stopUnlockAttemptAuthentication()
            return
        }

        if settings.current.bluetoothUnlockWakeOnProximity || fromFaceID {
            (NSApp.delegate as? AppDelegate)?.wakeDisplay()
        }

        if settings.current.bluetoothUnlockWakeWithoutUnlocking && !fromFaceID {
            isUnlockInProgress = false
            return
        }

        if !fromFaceID && !isPhoneUnlockRequirementMet {
            setStatusThrottled(String(localized: "Unlock your phone to unlock this Mac."))
            isUnlockInProgress = false
            return
        }

        if !fromFaceID && !isWatchUnlockRequirementMet {
            setStatusThrottled(String(localized: "Wear your watch and unlock it to unlock this Mac."))
            isUnlockInProgress = false
            return
        }

        if isFaceIDAuthenticating {
            tearDownFaceID()
        }

        guard hasAccessibilityPermission(promptIfNeeded: true) else {
            setStatusThrottled(String(localized: "Enable Accessibility in System Settings to allow auto-unlock."))
            isUnlockInProgress = false
            stopUnlockAttemptAuthentication()
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
            self.unlockWithPassword(attempt: 1, attemptID: attemptID, clearPasswordField: clearPasswordField)
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
        stopUnlockAttemptAuthentication()
    }

    // MARK: - Password & HID Injection

    private func unlockWithPassword(attempt: Int = 1, attemptID: UUID, clearPasswordField: Bool = false) {
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

            // Key events posted at the HID tap go to whatever has focus when they are delivered, not to
            // the lock screen in particular. Re-check before every step that the Mac is still locked and
            // loginwindow's lock screen is in front, and stop for good the moment either check fails, so
            // the password can never be typed (and sent with Return) into an app after unlock.
            @MainActor func lockScreenStillTargeted() -> Bool {
                self.unlockAttemptID == attemptID && self.isUnlockInProgress && self.isScreenLocked
                    && Self.isScreenActuallyLocked() && Self.isLockScreenFrontmost()
            }
            @MainActor func abortInjection() {
                print("[AuthManager] Lock screen no longer in front — password entry aborted.")
                self.didCompleteUnlock()
            }

            guard lockScreenStillTargeted() else { return abortInjection() }

            if clearPasswordField {
                // Delete is harmless on an empty field. Keys other than Return confirm ~0.5 s late,
                // so a few more characters may have landed by now; clear generously.
                for _ in 0..<16 {
                    guard lockScreenStillTargeted() else { return abortInjection() }
                    CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)?.post(tap: tapLocation)
                    CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)?.post(tap: tapLocation)
                }
            }

            for start in stride(from: 0, to: utf16chars.count, by: 20) {
                guard lockScreenStillTargeted() else { return abortInjection() }
                var chunk = Array(utf16chars[start..<min(start + 20, utf16chars.count)])
                defer { for i in chunk.indices { chunk[i] = 0 } }
                if let pwDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                    pwDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                    pwDown.post(tap: tapLocation)
                }
                if let pwUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    pwUp.post(tap: tapLocation)
                }
            }

            guard lockScreenStillTargeted() else { return abortInjection() }
            let retDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
            let retUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
            retDown?.post(tap: tapLocation)
            retUp?.post(tap: tapLocation)

            // No automatic retry: loginwindow keeps reporting "locked" while it verifies the password,
            // so a timed retry can pass every check and then land in the app that comes forward. Hold the
            // attempt open briefly (blocking a second injection), then release it. If the Mac is still
            // locked, the user can try Face ID again or type the password.
            self.setStatusThrottled(String(localized: "Unlocking..."))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, self.unlockAttemptID == attemptID else { return }
                if self.isScreenLocked {
                    self.setStatusThrottled(String(localized: "Unlock failed"))
                    (NSApp.delegate as? AppDelegate)?.markFaceIDRequiresPassword()
                }
                self.didCompleteUnlock()
            }
        }
    }

    /// True only when a loginwindow-owned window is on screen above the screen-saver level, i.e. the
    /// lock screen is what keyboard input will reach. Fails closed if the window list is unavailable.
    private static func isLockScreenFrontmost() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let minLayer = Int(CGWindowLevelForKey(.screenSaverWindow))
        return windows.contains { info in
            (info[kCGWindowOwnerName as String] as? String) == "loginwindow"
                && ((info[kCGWindowLayer as String] as? Int) ?? Int.min) >= minLayer
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
        let match = continuityDevices.first { $0.peripheralID == uuid.uuidString }
        settings.settings.bluetoothUnlockContinuityPeerID = match?.peerID
        settings.settings.bluetoothUnlockDeviceID = uuid.uuidString
        stopScan()
    }

    func useContinuityDevice(peerID: String) {
        guard let device = continuityDevices.first(where: { $0.peerID == peerID }),
              let peripheralID = device.peripheralID else { return }
        settings.settings.bluetoothUnlockContinuityPeerID = device.peerID
        settings.settings.bluetoothUnlockDeviceID = peripheralID
        if isScanning { stopScan() }
    }

    func forgetDevice() {
        if settings.current.bluetoothUnlockContinuityPeerID != nil {
            settings.settings.bluetoothUnlockUseContinuityPhone = false
        }
        settings.settings.bluetoothUnlockContinuityPeerID = nil
        settings.settings.bluetoothUnlockDeviceID = nil
    }

    // MARK: - Continuity Phone

    private func setupContinuityPhoneObserver() {
        NotificationCenter.default.publisher(for: .continuityPairedPeersDidChange)
            .map { _ in () }
            .merge(with: settings.changes(of: { $0.bluetoothUnlockUseContinuityPhone }).map { _ in () })
            .prepend(())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshContinuityPhone() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .continuityPhoneLockStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let peerID = note.userInfo?["peerID"] as? String else { return }
                let isLocked = note.userInfo?["isLocked"] as? Bool
                guard self.phoneLockStates[peerID] != isLocked else { return }
                self.phoneLockStates[peerID] = isLocked
                self.handlePhoneLockStateChange(peerID: peerID)
            }
            .store(in: &cancellables)
    }

    /// True unless the trusted device is the Continuity phone, the option is on, and the phone hasn't reported being unlocked.
    var isPhoneUnlockRequirementMet: Bool {
        let current = settings.current
        guard current.bluetoothUnlockRequirePhoneUnlocked,
              let peerID = current.bluetoothUnlockContinuityPeerID else { return true }
        return phoneLockStates[peerID] == false
    }

    var selectedWatch: TrustedWatch? {
        settings.current.bluetoothUnlockDeviceID.flatMap { TrustedWatchStore.shared.watch(id: $0) }
    }

    /// A trusted watch unlocks the Mac only while it is on the wrist and unlocked.
    var isWatchUnlockRequirementMet: Bool {
        guard selectedWatch != nil else { return true }
        return watchFlags?.isSuperset(of: [.onWrist, .unlocked]) == true
    }

    func useWatch(id: String) {
        settings.settings.bluetoothUnlockContinuityPeerID = nil
        settings.settings.bluetoothUnlockDeviceID = id
        if isScanning { stopScan() }
    }

    func forgetWatch(id: String) {
        if settings.current.bluetoothUnlockDeviceID == id { forgetDevice() }
        TrustedWatchStore.shared.remove(id: id)
    }

    func updateWatchFlags(_ flags: TrustedWatchFlags) {
        let wasMet = isWatchUnlockRequirementMet
        if watchFlags != flags { watchFlags = flags }
        guard !wasMet, isWatchUnlockRequirementMet, isBluetoothAuthenticating,
              wasPreviouslyPresent, isScreenLocked, !isUnlockInProgress else { return }
        handleUnlock()
    }

    private func handlePhoneLockStateChange(peerID: String) {
        guard peerID == settings.current.bluetoothUnlockContinuityPeerID,
              isPhoneUnlockRequirementMet, isBluetoothAuthenticating,
              wasPreviouslyPresent, isScreenLocked, !isUnlockInProgress else { return }
        handleUnlock()
    }

    private func refreshContinuityPhone() {
        let current = settings.current
        let devices = ContinuityKeystore.shared.pairedPeers
            .filter { $0.deviceType == .phone || $0.deviceType == .tablet }
            .sorted { ($0.lastSeenAt ?? .distantPast) > ($1.lastSeenAt ?? .distantPast) }
            .map { ContinuityDeviceOption(peerID: $0.id, name: $0.name, isTablet: $0.deviceType == .tablet, peripheralID: $0.blePeripheralID) }
        if continuityDevices != devices { continuityDevices = devices }

        guard current.bluetoothUnlockUseContinuityPhone, let suggestion = continuityPhoneSuggestion,
              let peripheralID = suggestion.peripheralID,
              current.bluetoothUnlockDeviceID == nil || current.bluetoothUnlockContinuityPeerID != nil,
              current.bluetoothUnlockDeviceID != peripheralID
                || current.bluetoothUnlockContinuityPeerID != suggestion.peerID else { return }
        settings.settings.bluetoothUnlockContinuityPeerID = suggestion.peerID
        settings.settings.bluetoothUnlockDeviceID = peripheralID
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
        $isEnabled.combineLatest($selectedDeviceID, $isPasswordSet.removeDuplicates())
            .sink { [weak self] (enabled, deviceID, _) in self?.updateMonitoringConfig(enabled: enabled, deviceID: deviceID) }
            .store(in: &cancellables)
        TrustedWatchStore.shared.$watches.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateMonitoringConfig(enabled: self.isEnabled, deviceID: self.selectedDeviceID)
            }
            .store(in: &cancellables)
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
                self.ble.setFastMode(configuration.fastMode)
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
        FaceIDIlluminator.shared.end()
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

    func bluetoothPowerWarn() { setStatusThrottled(String(localized: "Bluetooth is off")) }

    func updatePresence(presence: Bool, reason: String) {
        if isEnabled && isBluetoothAuthenticating {
            if presence {
                if !wasPreviouslyPresent, !isUnlockInProgress, isScreenLocked { handleUnlock() }
            } else {
                handleLock()
            }
            wasPreviouslyPresent = presence
        }
    }

    // MARK: - Utilities

    private func updateMonitoringConfig(enabled: Bool, deviceID: String?) {
        let watchKey = deviceID.flatMap { TrustedWatchStore.shared.watch(id: $0)?.keyBase64 }
        ble.watchVerifier = watchKey.map { key in { data in TrustedWatchStore.verify(serviceData: data, keyBase64: key) } }
        if watchKey == nil { watchFlags = nil }
        if enabled, self.isPasswordSet, let id = deviceID, let uuid = UUID(uuidString: id) {
            if isBluetoothAuthenticating && ble.monitoredUUID == uuid { return }
            isBluetoothAuthenticating = true
            wasPreviouslyPresent = false
            lastRSSI = nil
            ble.startMonitor(uuid: uuid)
            setStatusThrottled(String(localized: "Monitoring for device..."))
        } else {
            if isBluetoothAuthenticating {
                isBluetoothAuthenticating = false
                ble.stopMonitor()
                setStatusThrottled(String(localized: "Disabled"))
                self.monitoredPeripheralState = .disconnected
                self.lastRSSI = nil
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

        // Same local-node check as `dscl . -authonly`, without putting the password in an argument list other processes can read.
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: userName, attributes: nil)
            try record.verifyPassword(password)
            return true
        } catch {
            print("[AuthManager] Password check failed: \(error.localizedDescription)")
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