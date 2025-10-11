//
//  PermissionsManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//
//
//
//
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

// MARK: - Permission Enums

enum PermissionType: Identifiable, CaseIterable {
    case accessibility, notifications, location, calendar, reminders, bluetooth, focusStatus, fullDiskAccess
    var id: Self { self }
}

enum PermissionStatus: CaseIterable {
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

    private var locationManager: CLLocationManager?
    private var bluetoothManager: CBCentralManager?
    private var cancellables = Set<AnyCancellable>()

    public let allPermissions: [PermissionItem] = [
        .init(type: .accessibility, title: "Accessibility", description: "Needed for media key presses, window snapping, and HUDs.", iconName: "figure.wave.circle.fill", iconColor: .purple, category: .required),
        .init(type: .fullDiskAccess, title: "Full Disk Access", description: "Required for features like File Shelf and advanced integrations.", iconName: "folder.badge.gearshape", iconColor: .gray, category: .required),
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
            }
            .store(in: &cancellables)
    }

    private func checkAccessibilityStatus() {
        let isTrusted = AXIsProcessTrusted()
        let newStatus: PermissionStatus = isTrusted ? .granted : .notRequested
        if accessibilityStatus != newStatus {
            accessibilityStatus = newStatus
        }
    }

    private func checkFullDiskAccessStatus() {
        let testUrl = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        let canAccess = FileManager.default.isReadableFile(atPath: testUrl.path)
        let newStatus: PermissionStatus = canAccess ? .granted : .notRequested
        if fullDiskAccessStatus != newStatus {
            fullDiskAccessStatus = newStatus
        }
    }

    func checkAllPermissions() {
        checkAccessibilityStatus()
        checkFullDiskAccessStatus() // MODIFICATION: Check it here as well

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
        }
    }

    func requestPermission(_ type: PermissionType) {
        switch type {
        case .accessibility:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)

        case .fullDiskAccess:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess")!
            NSWorkspace.shared.open(url)

        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                DispatchQueue.main.async { self.checkAllPermissions() }
            }

        case .location:
            locationManager?.requestWhenInUseAuthorization()

        case .calendar:
            Task {
                _ = try? await EKEventStore().requestFullAccessToEvents()
                self.checkAllPermissions()
            }

        case .reminders:
            Task {
                _ = try? await EKEventStore().requestFullAccessToReminders()
                self.checkAllPermissions()
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