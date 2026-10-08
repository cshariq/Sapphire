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
import CoreServices
import Network
import dnssd

// MARK: - Permission Enums
enum PermissionType: Identifiable, CaseIterable {
    case accessibility, notifications, location, calendar, reminders, bluetooth, focusStatus, fullDiskAccess, screenRecording, localNetwork, automation
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
    @Published var screenRecordingStatus: PermissionStatus = .notRequested
    @Published var localNetworkStatus: PermissionStatus = .notRequested
    @Published var automationStatus: PermissionStatus = .notRequested

    private var locationManager: CLLocationManager?
    private lazy var bluetoothManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: 0])

    private let automationPermissionRequestedKey = "automationPermissionRequested"

    private struct AutomationTarget {
        let name: String
        let bundleIdentifier: String
    }

    private let automationTargets = [
        AutomationTarget(name: "Music", bundleIdentifier: "com.apple.Music"),
        AutomationTarget(name: "Spotify", bundleIdentifier: "com.spotify.client"),
    ]

    private var localNetworkProbe: LocalNetworkAccessProbe?
    private let localNetworkStatusKey = "localNetworkPermissionStatus.v2"
    private let localNetworkRequestedKey = "localNetworkPermissionRequested"
    private let screenRecordingRequestedAtKey = "screenRecordingRequestedAt"

    private static let automationRecheckInterval: TimeInterval = 120
    private var lastAutomationCheck = Date.distantPast
    private var automationCheckInFlight = false
    private var installedAutomationTargetIDs: Set<String>?

    private var cancellables = Set<AnyCancellable>()

    public let allPermissions: [PermissionItem] = [
        .init(type: .accessibility, title: String(localized: "Accessibility"), description: String(localized: "Needed for media key presses, window snapping, and HUDs."), iconName: "figure.wave.circle.fill", iconColor: .purple, category: .required),
        .init(type: .fullDiskAccess, title: String(localized: "Full Disk Access"), description: String(localized: "Enables File Shelf, Intelligence file access, and deeper system integrations."), iconName: "folder.badge.gearshape", iconColor: .gray, category: .recommended),
        .init(type: .screenRecording, title: String(localized: "Screen Recording"), description: String(localized: "Required for Gemini Live screen sharing, per-app audio capture, live window previews, and the hinge-driven desktop animation."), iconName: "record.circle", iconColor: .orange, category: .recommended),
        .init(type: .localNetwork, title: String(localized: "Local Network"), description: String(localized: "Needed to discover and control supported media players on your network."), iconName: "network", iconColor: .cyan, category: .recommended),
        .init(type: .automation, title: String(localized: "Automation"), description: String(localized: "Needed to control playback and get track info from Spotify and Music."), iconName: "play.display", iconColor: .green, category: .recommended),
        .init(type: .notifications, title: String(localized: "Notifications"), description: String(localized: "Needed to show custom alerts for messages and system events."), iconName: "bell.badge.fill", iconColor: .red, category: .recommended),
        .init(type: .location, title: String(localized: "Location"), description: String(localized: "Needed to provide live weather updates for your current location."), iconName: "location.fill", iconColor: .blue, category: .recommended),
        .init(type: .calendar, title: String(localized: "Calendar"), description: String(localized: "Needed to show your upcoming events."), iconName: "calendar", iconColor: .red, category: .recommended),
        .init(type: .bluetooth, title: String(localized: "Bluetooth"), description: String(localized: "Needed to detect connected devices and their battery levels."), iconName: "ipad.landscape.and.iphone", iconColor: .blue, category: .recommended),
        .init(type: .reminders, title: String(localized: "Reminders"), description: String(localized: "Needed to show your upcoming reminders."), iconName: "checklist", iconColor: .orange, category: .optional),
        .init(type: .focusStatus, title: String(localized: "Focus Status"), description: String(localized: "Needed to show when a Focus mode is active."), iconName: "moon.fill", iconColor: .indigo, category: .optional)
    ]

    var requiredPermissions: [PermissionItem] { allPermissions.filter { $0.category == .required } }
    var recommendedPermissions: [PermissionItem] { allPermissions.filter { $0.category == .recommended } }
    var optionalPermissions: [PermissionItem] { allPermissions.filter { $0.category == .optional } }

    var areAllRequiredPermissionsGranted: Bool {
        requiredPermissions.allSatisfy { status(for: $0.type) == PermissionStatus.granted }
    }

    func arePermissionsGranted(for types: [PermissionType]) -> Bool {
        types.allSatisfy { status(for: $0) == PermissionStatus.granted }
    }

    func missingPermissions(in types: [PermissionType]) -> [PermissionItem] {
        allPermissions.filter { types.contains($0.type) && status(for: $0.type) != PermissionStatus.granted }
    }

    func permissionItems(for types: [PermissionType]) -> [PermissionItem] {
        types.compactMap { type in allPermissions.first(where: { $0.type == type }) }
    }

    var areIntelligencePermissionsGranted: Bool {
        arePermissionsGranted(for: SettingsSection.intelligence.requiredPermissions)
    }

    private override init() {
        super.init()
        self.locationManager = CLLocationManager()
        self.locationManager?.delegate = self
        checkAllPermissions()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshLightweightStatuses()
                let now = Date()
                if now.timeIntervalSince(self.lastAutomationCheck) >= Self.automationRecheckInterval {
                    self.checkAutomationStatus()
                }
                if self.localNetworkProbeRequested, self.localNetworkStatus != .granted {
                    self.probeLocalNetwork(triggeredByUser: false)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AccessibilityTrustMonitor.trustDidChange)
            .sink { [weak self] _ in
                self?.checkAccessibilityStatus()
            }
            .store(in: &cancellables)
    }

    private func assign(_ keyPath: ReferenceWritableKeyPath<PermissionsManager, PermissionStatus>, _ value: PermissionStatus) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func refreshLightweightStatuses() {
        checkAccessibilityStatus()
        checkFullDiskAccessStatus()
        checkScreenRecordingStatus()
    }

    private func checkAccessibilityStatus() {
        let isTrusted = AccessibilityTrustMonitor.shared.isTrusted
        assign(\.accessibilityStatus, isTrusted ? .granted : .notRequested)
    }

    private func checkFullDiskAccessStatus() {
        if let preflight = Self.tccPreflight {
            let result = preflight(Self.serviceSystemPolicyAllFiles, nil)
            switch result {
            case 0: assign(\.fullDiskAccessStatus, .granted)
            case 1: assign(\.fullDiskAccessStatus, .denied)
            default: assign(\.fullDiskAccessStatus, .notRequested)
            }
        } else {
            let testUrl = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
            let canAccess = FileManager.default.isReadableFile(atPath: testUrl.path)
            assign(\.fullDiskAccessStatus, canAccess ? .granted : .notRequested)
        }
    }

    private func checkScreenRecordingStatus() {
        let defaults = UserDefaults.standard
        var requestedAt = defaults.object(forKey: screenRecordingRequestedAtKey) as? Date
        if requestedAt == nil, defaults.bool(forKey: "screenRecordingRequested") {
            requestedAt = .distantPast
        }
        assign(\.screenRecordingStatus, ScreenRecordingStatusPolicy.status(
            preflightGranted: CGPreflightScreenCaptureAccess(),
            requestedAt: requestedAt,
            now: Date()
        ))
    }

    func checkAllPermissions() {
        checkAccessibilityStatus()
        checkFullDiskAccessStatus()
        checkScreenRecordingStatus()
        checkLocalNetworkStatus()
        checkAutomationStatus()

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: PermissionStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = .granted
            case .denied: status = .denied
            case .notDetermined: status = .notRequested
            @unknown default: status = .notRequested
            }
            DispatchQueue.main.async {
                self.assign(\.notificationsStatus, status)
            }
        }

        updateLocationStatus(for: locationManager?.authorizationStatus ?? .notDetermined)

        let calStatus = EKEventStore.authorizationStatus(for: .event)
        switch calStatus {
        case .fullAccess, .writeOnly: assign(\.calendarStatus, .granted)
        case .denied, .restricted: assign(\.calendarStatus, .denied)
        case .notDetermined: assign(\.calendarStatus, .notRequested)
        @unknown default: assign(\.calendarStatus, .notRequested)
        }

        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        switch remStatus {
        case .fullAccess, .writeOnly: assign(\.remindersStatus, .granted)
        case .denied, .restricted: assign(\.remindersStatus, .denied)
        case .notDetermined: assign(\.remindersStatus, .notRequested)
        @unknown default: assign(\.remindersStatus, .notRequested)
        }

        updateBluetoothStatus(for: CBManager.authorization)

        let focusAuthStatus = INFocusStatusCenter.default.authorizationStatus
        switch focusAuthStatus {
        case .authorized: assign(\.focusStatusStatus, .granted)
        case .denied, .restricted: assign(\.focusStatusStatus, .denied)
        case .notDetermined: assign(\.focusStatusStatus, .notRequested)
        @unknown default: assign(\.focusStatusStatus, .notRequested)
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
        case .screenRecording: return screenRecordingStatus
        case .localNetwork: return localNetworkStatus
        case .automation: return automationStatus
        }
    }

    func requestPermission(_ type: PermissionType) {
        switch type {
        case .accessibility:
            AccessibilityPermission.request()

        case .fullDiskAccess:
            requestFullDiskAccessPrePopulation()
            openFullDiskAccessSettings()

        case .screenRecording:
            UserDefaults.standard.set(Date(), forKey: screenRecordingRequestedAtKey)
            UserDefaults.standard.set(true, forKey: "screenRecordingRequested")
            CGRequestScreenCaptureAccess()
            checkScreenRecordingStatus()

        case .automation:
            triggerAutomationPermissionRequest()

        case .localNetwork:
            probeLocalNetwork(triggeredByUser: true)

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
                SystemPreferencesPane.bluetooth.open()
            } else {
                bluetoothManager.scanForPeripherals(withServices: nil, options: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.bluetoothManager.stopScan()
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
        lastAutomationCheck = Date()
        guard UserDefaults.standard.bool(forKey: automationPermissionRequestedKey) else {
            assign(\.automationStatus, .notRequested)
            return
        }
        guard !automationCheckInFlight else { return }
        automationCheckInFlight = true

        let targets = automationTargets
        Task {
            defer { automationCheckInFlight = false }
            if installedAutomationTargetIDs == nil {
                let ids = await Task.detached(priority: .utility) {
                    Set(targets.map(\.bundleIdentifier).filter {
                        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                    })
                }.value
                installedAutomationTargetIDs = ids
            }
            let installed = targets.filter { installedAutomationTargetIDs?.contains($0.bundleIdentifier) == true }

            var statuses: [PermissionStatus] = []
            for target in installed {
                statuses.append(await getAutomationPermissionStatus(for: target))
            }

            if statuses.contains(PermissionStatus.denied) {
                assign(\.automationStatus, .denied)
            } else if !statuses.isEmpty && statuses.allSatisfy({ $0 == PermissionStatus.granted }) {
                assign(\.automationStatus, .granted)
            } else {
                assign(\.automationStatus, .notRequested)
            }
        }
    }

    private func triggerAutomationPermissionRequest() {
        Task(priority: .userInitiated) {
            var foundTarget = false

            for target in automationTargets {
                guard await launchAutomationTarget(target) else { continue }
                foundTarget = true

                print("[PermissionsManager] Requesting Automation permission for \(target.name)...")
                let status = await Self.determineAutomationPermission(
                    for: target.bundleIdentifier,
                    askUserIfNeeded: true
                )
                print("[PermissionsManager] Automation request for \(target.name) returned \(status).")
            }

            guard foundTarget else { return }
            UserDefaults.standard.set(true, forKey: automationPermissionRequestedKey)
            self.installedAutomationTargetIDs = nil

            self.checkAutomationStatus()
        }
    }

    private func launchAutomationTarget(_ target: AutomationTarget) async -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty {
            return true
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            print("[PermissionsManager] Application '\(target.name)' not found.")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { application, error in
                if let error {
                    print("[PermissionsManager] Could not launch \(target.name) for Automation permission: \(error.localizedDescription)")
                }
                continuation.resume(returning: application != nil)
            }
        }
    }

    private nonisolated static func determineAutomationPermission(
        for bundleIdentifier: String,
        askUserIfNeeded: Bool
    ) async -> OSStatus {
        await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            guard let descriptor = target.aeDesc else { return OSStatus(paramErr) }

            return AEDeterminePermissionToAutomateTarget(
                descriptor,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                askUserIfNeeded
            )
        }.value
    }

    private func getAutomationPermissionStatus(for target: AutomationTarget) async -> PermissionStatus {
        let cacheKey = "automationPermissionStatus.\(target.bundleIdentifier)"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty else {
            return UserDefaults.standard.string(forKey: cacheKey).flatMap(PermissionStatus.init(rawValue:)) ?? .notRequested
        }
        let status: PermissionStatus?
        switch await Self.determineAutomationPermission(for: target.bundleIdentifier, askUserIfNeeded: false) {
        case noErr: status = .granted
        case OSStatus(errAEEventNotPermitted): status = .denied
        case OSStatus(errAEEventWouldRequireUserConsent): status = .notRequested
        default: status = nil
        }
        if let status {
            UserDefaults.standard.set(status.rawValue, forKey: cacheKey)
            return status
        }
        return UserDefaults.standard.string(forKey: cacheKey).flatMap(PermissionStatus.init(rawValue:)) ?? .notRequested
    }

    // MARK: - Full Disk Access

    private func requestFullDiskAccessPrePopulation() {
        guard let request = Self.tccRequest else { return }
        request(Self.serviceSystemPolicyAllFiles, nil) { _ in }
    }

    private func openFullDiskAccessSettings() {
        SystemPreferencesPane.allFiles.open()
    }

    // MARK: - TCC Private SPI (dynamic loading)

    private typealias TCCPreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias TCCRequestFunc = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let tccHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    }()

    private static let tccPreflight: TCCPreflightFunc? = {
        guard let handle = tccHandle,
              let sym = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(sym, to: TCCPreflightFunc.self)
    }()

    private static let tccRequest: TCCRequestFunc? = {
        guard let handle = tccHandle,
              let sym = dlsym(handle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(sym, to: TCCRequestFunc.self)
    }()

    private static let serviceSystemPolicyAllFiles = "kTCCServiceSystemPolicyAllFiles" as CFString

    // MARK: - Local Network Logic

    private func checkLocalNetworkStatus() {
        let stored = UserDefaults.standard.string(forKey: localNetworkStatusKey).flatMap(PermissionStatus.init(rawValue:))
        assign(\.localNetworkStatus, stored ?? .notRequested)
    }

    private var localNetworkProbeRequested: Bool {
        UserDefaults.standard.bool(forKey: localNetworkRequestedKey)
    }

    private func probeLocalNetwork(triggeredByUser: Bool) {
        if triggeredByUser { UserDefaults.standard.set(true, forKey: localNetworkRequestedKey) }
        guard localNetworkProbe == nil else { return }
        let probe = LocalNetworkAccessProbe { [weak self] result in
            guard let self else { return }
            self.localNetworkProbe = nil
            switch result {
            case .granted: self.updateLocalNetworkStatus(.granted)
            case .denied: self.updateLocalNetworkStatus(.denied)
            case .undetermined: break
            }
        }
        localNetworkProbe = probe
        probe.start()
    }

    private func updateLocalNetworkStatus(_ newStatus: PermissionStatus) {
        assign(\.localNetworkStatus, newStatus)
        UserDefaults.standard.set(newStatus.rawValue, forKey: localNetworkStatusKey)
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let wasGranted = locationStatus == PermissionStatus.granted
        updateLocationStatus(for: manager.authorizationStatus)
        if locationStatus == PermissionStatus.granted && !wasGranted {
            WeatherViewModel.shared.fetch()
        }
    }

private func updateLocationStatus(for status: CLAuthorizationStatus) {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse: assign(\.locationStatus, .granted)
        case .denied, .restricted: assign(\.locationStatus, .denied)
        case .notDetermined: assign(\.locationStatus, .notRequested)
        @unknown default: assign(\.locationStatus, .notRequested)
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.updateBluetoothStatus(for: CBManager.authorization)
    }

    private func updateBluetoothStatus(for authorization: CBManagerAuthorization) {
        switch authorization {
        case .allowedAlways: assign(\.bluetoothStatus, .granted)
        case .denied, .restricted: assign(\.bluetoothStatus, .denied)
        case .notDetermined: assign(\.bluetoothStatus, .notRequested)
        @unknown default: assign(\.bluetoothStatus, .notRequested)
        }
    }
}
// MARK: - Screen Recording status

enum ScreenRecordingStatusPolicy {
    static let answerGracePeriod: TimeInterval = 120

    static func status(preflightGranted: Bool, requestedAt: Date?, now: Date) -> PermissionStatus {
        if preflightGranted { return .granted }
        guard let requestedAt else { return .notRequested }
        return now.timeIntervalSince(requestedAt) < answerGracePeriod ? .notRequested : .denied
    }
}

// MARK: - Local Network probe

@MainActor
final class LocalNetworkAccessProbe {
    enum Result { case granted, denied, undetermined }

    private static let serviceType = "_sapphire-lnp._tcp"
    private static let timeout: TimeInterval = 8

    private let completion: @MainActor (Result) -> Void
    private let serviceName = "Sapphire-\(UUID().uuidString.prefix(8))"
    private let queue = DispatchQueue(label: "com.sapphire.local-network-probe", qos: .utility)
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var timeoutWork: DispatchWorkItem?
    private var isFinished = false

    init(completion: @escaping @MainActor (Result) -> Void) {
        self.completion = completion
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            listener.newConnectionHandler = { $0.cancel() }
            listener.stateUpdateHandler = { [weak self] state in
                guard case .failed = state else { return }
                DispatchQueue.main.async { self?.finish(.undetermined) }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            finish(.undetermined)
            return
        }

        let name = serviceName
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: NWParameters())
        browser.stateUpdateHandler = { [weak self] state in
            let result: Result?
            switch state {
            case .waiting(let error): result = Self.isPolicyDenied(error) ? .denied : nil
            case .failed(let error): result = Self.isPolicyDenied(error) ? .denied : .undetermined
            default: result = nil
            }
            guard let result else { return }
            DispatchQueue.main.async { self?.finish(result) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let sawSelf = results.contains { result in
                if case .service(let found, _, _, _) = result.endpoint { return found == name }
                return false
            }
            guard sawSelf else { return }
            DispatchQueue.main.async { self?.finish(.granted) }
        }
        self.browser = browser
        browser.start(queue: queue)

        let work = DispatchWorkItem { [weak self] in self?.finish(.undetermined) }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: work)
    }

    private nonisolated static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
        return false
    }

    private func finish(_ result: Result) {
        guard !isFinished else { return }
        isFinished = true
        timeoutWork?.cancel()
        timeoutWork = nil
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        completion(result)
    }
}