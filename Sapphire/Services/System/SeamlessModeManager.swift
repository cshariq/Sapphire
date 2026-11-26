//
//  SeamlessModeManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-29
//
//  Seamless mode makes Sapphire present itself to *other apps* as a quiet background system process
//  instead of a separate app with visible windows — closer to how the notch UI would feel if it were
//  drawn by the system itself. It never hides Sapphire from the user or from the OS: the user still sees
//  every window, and the system still accounts for the process normally. It only changes what other
//  user-space apps observe through the standard enumeration/capture APIs.
//
//  All of the mechanisms here are ordinary macOS window/app presentation settings, plus one well-known
//  private LaunchServices call to set the app's display name. By design this does NOT forge an Apple
//  bundle identifier or code signature, inject into other processes, or try to defeat security tooling —
//  none of that is needed for the goal, and the user is fine with the system seeing Sapphire as itself.
//
//  It is gated twice: the setting is only shown while Debug Mode is on, and only takes effect while both
//  Debug Mode and the setting are enabled.

import AppKit
import Combine
import Foundation

@MainActor
final class SeamlessModeManager: ObservableObject {
    static let shared = SeamlessModeManager()

    /// The neutral name other apps will show for Sapphire while seamless mode is on. Intentionally generic
    /// and descriptive — never an Apple or third-party app's name/identifier.
    static let presentedName = "Notch"

    @Published private(set) var isActive = false

    private weak var settingsModel: SettingsModel?
    private var sweepTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// Windows already decorated this activation, by window number, so the sweep is cheap.
    private var decorated: [ObjectIdentifier: WindowState] = [:]
    private var started = false

    private struct WindowState {
        let sharingType: NSWindow.SharingType
        let collectionBehavior: NSWindow.CollectionBehavior
        let isExcludedFromWindowsMenu: Bool
    }

    private init() {}

    // MARK: Lifecycle

    func start(settingsModel: SettingsModel) {
        guard !started else { return }
        started = true
        self.settingsModel = settingsModel

        settingsModel.$settings
            .map(\.seamlessModeEnabled)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        DebugMode.shared.$isEnabled
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    /// Whether both gates are satisfied.
    private var shouldBeActive: Bool {
        if let forcedActiveOverride { return forcedActiveOverride }
        return DebugMode.shared.isEnabled && (settingsModel?.current.seamlessModeEnabled ?? false)
    }

    /// A testing override driven only by the debug notch hook — which is itself only enabled in DEBUG
    /// builds or behind an env var, so this is unreachable in a normal release. `true`/`false` force the
    /// state; `nil` returns to the settings-driven behaviour.
    private var forcedActiveOverride: Bool?
    func setForcedActive(_ on: Bool?) {
        forcedActiveOverride = on
        NSLog("[SeamlessMode] setForcedActive(%@)", on.map(String.init(describing:)) ?? "auto")
        refresh()
    }

    private func refresh() {
        let target = shouldBeActive
        guard target != isActive else {
            if isActive { sweepWindows() }
            return
        }
        isActive = target
        if target { apply() } else { remove() }
    }

    /// The sharing type a window should use right now, given the user's own screen-sharing preference.
    /// Seamless mode forces exclusion from capture; otherwise the user's choice stands.
    func sharingType(whenNotSeamless userHidesFromSharing: Bool) -> NSWindow.SharingType {
        if isActive { return .none }
        return userHidesFromSharing ? .none : .readOnly
    }

    /// Apply the treatment to one window as it's created, so new windows are correct immediately rather
    /// than waiting for the next sweep.
    func decorateIfActive(_ window: NSWindow) {
        guard isActive else { return }
        decorate(window)
    }

    // MARK: Apply / remove

    private func apply() {
        setPresentedName(Self.presentedName)
        sweepWindows()
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweepWindows() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
        NSLog("[SeamlessMode] Active — presenting to other apps as \"%@\".", Self.presentedName)
    }

    private func remove() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        restorePresentedName()
        let hidesFromSharing = settingsModel?.current.hideFromScreenSharing ?? false
        for window in NSApp.windows {
            guard let state = decorated[ObjectIdentifier(window)] else { continue }
            // Screen-sharing visibility should follow the user's current preference, not the pre-seamless snapshot.
            window.sharingType = hidesFromSharing ? .none : .readOnly
            window.collectionBehavior = state.collectionBehavior
            window.isExcludedFromWindowsMenu = state.isExcludedFromWindowsMenu
        }
        decorated.removeAll()
        NSLog("[SeamlessMode] Inactive — restored normal app presentation.")
    }

    private func sweepWindows() {
        for window in NSApp.windows where decorated[ObjectIdentifier(window)] == nil {
            decorate(window)
        }
    }

    private func decorate(_ window: NSWindow) {
        if decorated[ObjectIdentifier(window)] == nil {
            decorated[ObjectIdentifier(window)] = WindowState(
                sharingType: window.sharingType,
                collectionBehavior: window.collectionBehavior,
                isExcludedFromWindowsMenu: window.isExcludedFromWindowsMenu
            )
        }
        // Excluded from other apps' screen capture / window-image queries.
        window.sharingType = .none
        // Not part of Mission Control, window cycling, or the Windows menu — it behaves like chrome, not a doc window.
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary])
        window.isExcludedFromWindowsMenu = true
    }

    // MARK: LaunchServices display name

    /// The name `NSWorkspace.runningApplications` reports to other apps. Changing it is a long-standing
    /// private LaunchServices call (the same one menu-bar apps use to rename themselves); resolved at
    /// runtime so there's no bridging-header surface.
    private typealias GetASN = @convention(c) () -> UnsafeRawPointer
    private typealias SetInfoItem = @convention(c) (Int32, UnsafeRawPointer, CFString, CFString, UnsafeMutableRawPointer?) -> OSStatus

    private struct LaunchServicesName {
        let getASN: GetASN
        let setItem: SetInfoItem
        let displayKey: CFString
    }

    private static let launchServices: LaunchServicesName? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let asnSym = dlsym(handle, "_LSGetCurrentApplicationASN"),
              let setSym = dlsym(handle, "_LSSetApplicationInformationItem"),
              let keySym = dlsym(handle, "_kLSDisplayNameKey") else { return nil }
        let key = keySym.assumingMemoryBound(to: Unmanaged<CFString>.self).pointee.takeUnretainedValue()
        return LaunchServicesName(
            getASN: unsafeBitCast(asnSym, to: GetASN.self),
            setItem: unsafeBitCast(setSym, to: SetInfoItem.self),
            displayKey: key
        )
    }()

    /// -2 == kLSDefaultSessionID (a compile-time constant, not an exported symbol).
    private static let defaultSessionID: Int32 = -2

    private func setPresentedName(_ name: String) {
        guard let ls = Self.launchServices else { return }
        _ = ls.setItem(Self.defaultSessionID, ls.getASN(), ls.displayKey, name as CFString, nil)
    }

    private func restorePresentedName() {
        let bundle = Bundle.main
        let real = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Sapphire"
        setPresentedName(real)
    }
}
