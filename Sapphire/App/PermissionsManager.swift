//
//  PermissionsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import Combine
import CoreLocation
import EventKit
import AVFoundation
import UserNotifications
import ScreenCaptureKit
import CoreBluetooth
import Intents
import ApplicationServices
import AppKit
import Network

// MARK: - Permission Enums
enum PermissionType: Identifiable, CaseIterable {
    case accessibility, notifications, location, calendar, reminders, bluetooth, focusStatus, fullDiskAccess, localNetwork, automation
    var id: Self { self }
}

enum PermissionStatus: String, CaseIterable {
    case granted, denied, notRequested
}

enum PermissionCategory: String, CaseIterable {
    case required = "Required"
    case recommended = "Recommended"
    case optional = "Optional"
}

struct PermissionItem: Identifiable {
    let id = UUID()
    let type: PermissionType, title: String, description: String, iconName: String
    let iconColor: Color
    let category: PermissionCategory
}

// MARK: - PermissionsManager
@MainActor
class PermissionsManager: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate, @MainActor CBCentralManagerDelegate {
    static let shared = PermissionsManager()

    @Published var accessibilityStatus: PermissionStatus = .notRequested
    @Published var notificationsStatus: PermissionStatus = .notRequested
    @Published var locationStatus: PermissionStatus = .notRequested
    @Published var calendarStatus: PermissionStatus = .notRequested
    @Published var remindersStatus: PermissionStatus = .notRequested
    @Published var bluetoothStatus: PermissionStatus = .notRequested
    @Published var focusStatusStatus: PermissionStatus = .notRequested
    @Published var fullDiskAccessStatus: PermissionStatus = .notRequested
    @Published var localNetworkStatus: PermissionStatus = .notRequested
    @Published var automationStatus: PermissionStatus = .notRequested

    private var locationManager: CLLocationManager?
    private var bluetoothManager: CBCentralManager?

    private var localNetworkListener: NWListener?
    private var dummyNetService: NetService?
    private let localNetworkStatusKey = "localNetworkPermissionStatus"

    private var cancellables = Set<AnyCancellable>()

    public let allPermissions: [PermissionItem] = [
        .init(type: .accessibility, title: "Accessibility", description: "Needed for media key presses, window snapping, and HUDs.", iconName: "figure.wave.circle.fill", iconColor: .purple, category: .required),
        .init(type: .fullDiskAccess, title: "Full Disk Access", description: "Required for features like File Shelf and advanced integrations.", iconName: "folder.badge.gearshape", iconColor: .gray, category: .required),
        .init(type: .localNetwork, title: "Local Network", description: "Needed to discover and control supported media players on your network.", iconName: "network", iconColor: .cyan, category: .recommended),
        .init(type: .automation, title: "Automation", description: "Needed to control playback and get track info from Spotify and Music.", iconName: "play.display", iconColor: .green, category: .recommended),
        .init(type: .notifications, title: "Notifications", description: "Needed to show custom alerts for messages and system events.", iconName: "bell.badge.fill", iconColor: .red, category: .recommended),
        .init(type: .location, title: "Location", description: "Needed to provide live weather updates for your current location.", iconName: "location.fill", iconColor: .blue, category: .recommended),
        .init(type: .calendar, title: "Calendar", description: "Needed to show your upcoming events.", iconName: "calendar", iconColor: .red, category: .recommended),
        .init(type: .bluetooth, title: "Bluetooth", description: "Needed to detect connected devices and their battery levels.", iconName: "ipad.landscape.and.iphone", iconColor: .blue, category: .recommended),
        .init(type: .reminders, title: "Reminders", description: "Needed to show your upcoming reminders.", iconName: "checklist", iconColor: .orange, category: .optional),
        .init(type: .focusStatus, title: "Focus Status", description: "Needed to show when a Focus mode is active.", iconName: "moon.fill", iconColor: .indigo, category: .optional)
    ]

    var requiredPermissions: [PermissionItem] { allPermissions.filter { $0.category == .required } }
    var recommendedPermissions: [PermissionItem] { allPermissions.filter { $0.category == .recommended } }
    var optionalPermissions: [PermissionItem] { allPermissions.filter { $0.category == .optional } }

    var areAllRequiredPermissionsGranted: Bool {
        requiredPermissions.allSatisfy { status(for: $0.type) == .granted }
    }

    private override init() {
        super.init()
        self.locationManager = CLLocationManager()
        self.locationManager?.delegate = self
        self.bluetoothManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: 0])
        checkAllPermissions()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkAccessibilityStatus()
                self?.checkFullDiskAccessStatus()
                self?.checkAutomationStatus()
            }
            .store(in: &cancellables)
    }

    private func checkAccessibilityStatus() {
        let isTrusted = AXIsProcessTrusted()
        accessibilityStatus = isTrusted ? .granted : .notRequested
    }

    private func checkFullDiskAccessStatus() {
        let testUrl = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        let canAccess = FileManager.default.isReadableFile(atPath: testUrl.path)
        fullDiskAccessStatus = canAccess ? .granted : .notRequested
    }

    func checkAllPermissions() {
        checkAccessibilityStatus()
        checkFullDiskAccessStatus()
        checkLocalNetworkStatus()
        checkAutomationStatus()

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional: self.notificationsStatus = .granted
                case .denied: self.notificationsStatus = .denied
                case .notDetermined: self.notificationsStatus = .notRequested
                @unknown default: self.notificationsStatus = .notRequested
                }
            }
        }

        updateLocationStatus(for: locationManager?.authorizationStatus ?? .notDetermined)

        let calStatus = EKEventStore.authorizationStatus(for: .event)
        switch calStatus {
        case .fullAccess, .writeOnly: calendarStatus = .granted
        case .denied, .restricted: calendarStatus = .denied
        case .notDetermined: calendarStatus = .notRequested
        @unknown default: calendarStatus = .notRequested
        }

        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        switch remStatus {
        case .fullAccess: remindersStatus = .granted
        case .denied, .restricted: remindersStatus = .denied
        case .notDetermined: remindersStatus = .notRequested
        @unknown default: remindersStatus = .notRequested
        }

        updateBluetoothStatus(for: CBManager.authorization)

        let focusAuthStatus = INFocusStatusCenter.default.authorizationStatus
        switch focusAuthStatus {
        case .authorized: focusStatusStatus = .granted
        case .denied, .restricted: focusStatusStatus = .denied
        case .notDetermined: focusStatusStatus = .notRequested
        @unknown default: focusStatusStatus = .notRequested
        }
    }

    func status(for type: PermissionType) -> PermissionStatus {
        switch type {
        case .accessibility: return accessibilityStatus
        case .notifications: return notificationsStatus
        case .location: return locationStatus
        case .calendar: return calendarStatus
        case .reminders: return remindersStatus
        case .bluetooth: return bluetoothStatus
        case .focusStatus: return focusStatusStatus
        case .fullDiskAccess: return fullDiskAccessStatus
        case .localNetwork: return localNetworkStatus
        case .automation: return automationStatus
        }
    }

    func requestPermission(_ type: PermissionType) {
        switch type {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            if !isTrusted {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }

        case .fullDiskAccess:
            triggerFullDiskAccessPrePopulation()
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess")!
            NSWorkspace.shared.open(url)

        case .automation:
            triggerAutomationPermissionRequest()

        case .localNetwork:
            triggerLocalNetworkPrivacyAlert()

        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                DispatchQueue.main.async { self.checkAllPermissions() }
            }

        case .location:
            locationManager?.requestWhenInUseAuthorization()

        case .calendar:
            Task {
                do { _ = try await EKEventStore().requestFullAccessToEvents() } catch {}
                await MainActor.run { self.checkAllPermissions() }
            }

        case .reminders:
            Task {
                do { _ = try await EKEventStore().requestFullAccessToReminders() } catch {}
                await MainActor.run { self.checkAllPermissions() }
            }

        case .bluetooth:
            if CBManager.authorization == .denied {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
                NSWorkspace.shared.open(url)
            } else {
                bluetoothManager?.scanForPeripherals(withServices: nil, options: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.bluetoothManager?.stopScan()
                }
            }

        case .focusStatus:
            INFocusStatusCenter.default.requestAuthorization { _ in
                DispatchQueue.main.async { self.checkAllPermissions() }
            }
        }
    }

    // MARK: - Automation Logic

    private func checkAutomationStatus() {
        Task {
            let spotifyStatus = await getAutomationPermissionStatus(for: "Spotify")
            let musicStatus = await getAutomationPermissionStatus(for: "Music")

            if spotifyStatus == .denied || musicStatus == .denied {
                automationStatus = .denied
            } else if spotifyStatus == .granted && musicStatus == .granted {
                automationStatus = .granted
            } else {
                automationStatus = .notRequested
            }
        }
    }

    private func triggerAutomationPermissionRequest() {
        Task(priority: .userInitiated) {
            print("[PermissionsManager] Triggering Automation permission for Spotify...")
            _ = await executeAppleScript(command: #"tell application "Spotify" to activate"#, for: "Spotify")

            try? await Task.sleep(for: .seconds(1))

            print("[PermissionsManager] Triggering Automation permission for Music...")
            _ = await executeAppleScript(command: #"tell application "Music" to activate"#, for: "Music")
        }
    }

    private func getAutomationPermissionStatus(for appName: String) async -> PermissionStatus {
        let command = #"tell application "\#(appName)" to get its name"#

        let errorInfo = await executeAppleScript(command: command, for: appName)

        if errorInfo == nil {
            return .granted
        } else if let errorNumber = errorInfo?[NSAppleScript.errorNumber] as? NSNumber,
                  errorNumber.intValue == -1743 {
            return .denied
        } else {
            return .notRequested
        }
    }

    private func executeAppleScript(command: String, for appName: String) async -> NSDictionary? {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName.lowercased() == "spotify" ? "com.spotify.client" : "com.apple.Music") != nil else {
            print("[PermissionsManager] Application '\(appName)' not found.")
            return ["error": "\(appName) not found"]
        }

        guard let script = NSAppleScript(source: command) else {
            return ["error": "Failed to create AppleScript object"]
        }

        var errorInfo: NSDictionary?
        return await Task.detached {
            script.executeAndReturnError(&errorInfo)
            return errorInfo
        }.value
    }

    // MARK: - Full Disk Access Trigger

    private func triggerFullDiskAccessPrePopulation() {
        let safariBookmarksPath = "~/Library/Safari/Bookmarks.plist"
        _ = try? String(contentsOfFile: (safariBookmarksPath as NSString).expandingTildeInPath, encoding: .utf8)
    }

    // MARK: - Local Network Logic

    private func checkLocalNetworkStatus() {
        if let storedStatusRawValue = UserDefaults.standard.string(forKey: localNetworkStatusKey),
           let storedStatus = PermissionStatus(rawValue: storedStatusRawValue) {
            localNetworkStatus = storedStatus
        } else {
            localNetworkStatus = .notRequested
        }
    }

    private func triggerLocalNetworkPrivacyAlert() {
        guard localNetworkListener == nil else { return }

        do {
            let listener = try NWListener(using: .tcp)
            self.localNetworkListener = listener

            listener.stateUpdateHandler = { [weak self] newState in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch newState {
                    case .ready:
                        if let port = listener.port {
                            print("[PermissionsManager] Local network listener ready on port \(port). Advertising dummy service.")
                            let service = NetService(domain: "local.", type: "_dummy-service._tcp.", name: "PermissionCheck", port: Int32(port.rawValue))
                            self.dummyNetService = service
                            service.publish()
                            self.updateLocalNetworkStatus(.granted)
                        }
                        self.scheduleStopLocalNetworkCheck()

                    case .failed(let error):
                        print("[PermissionsManager] Local network listener failed: \(error)")
                        self.updateLocalNetworkStatus(.denied)
                        self.stopLocalNetworkCheck()

                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { newConnection in
                newConnection.cancel()
            }

            listener.start(queue: DispatchQueue(label: "LocalNetworkPermissionTrigger"))

        } catch {
            print("[PermissionsManager] Failed to create NWListener for permission check: \(error)")
            self.updateLocalNetworkStatus(.denied)
        }
    }

    private func scheduleStopLocalNetworkCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopLocalNetworkCheck()
        }
    }

    private func stopLocalNetworkCheck() {
        if localNetworkListener != nil {
            print("[PermissionsManager] Stopping local network permission check.")
            dummyNetService?.stop()
            dummyNetService = nil
            localNetworkListener?.cancel()
            localNetworkListener = nil
        }
    }

    private func updateLocalNetworkStatus(_ newStatus: PermissionStatus) {
        localNetworkStatus = newStatus
        UserDefaults.standard.set(newStatus.rawValue, forKey: localNetworkStatusKey)
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationStatus(for: manager.authorizationStatus)
    }

private func updateLocationStatus(for status: CLAuthorizationStatus) {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse: locationStatus = .granted
        case .denied, .restricted: locationStatus = .denied
        case .notDetermined: locationStatus = .notRequested
        @unknown default: locationStatus = .notRequested
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.updateBluetoothStatus(for: CBManager.authorization)
    }

    private func updateBluetoothStatus(for authorization: CBManagerAuthorization) {
        switch authorization {
        case .allowedAlways: bluetoothStatus = .granted
        case .denied, .restricted: bluetoothStatus = .denied
        case .notDetermined: bluetoothStatus = .notRequested
        @unknown default: bluetoothStatus = .notRequested
        }
    }
}