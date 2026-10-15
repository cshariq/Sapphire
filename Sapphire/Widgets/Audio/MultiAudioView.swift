//
//  MultiAudioView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI
import AppKit

struct MultiAudioView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @ObservedObject private var permissionsManager = PermissionsManager.shared

    private var panelSize: CGSize {
        let screen = CursorPosition.targetNotchScreen() ?? NSScreen.main
        let screenWidth = screen?.frame.width ?? 1512
        let visibleHeight = screen?.visibleFrame.height ?? 800
        return CGSize(
            width: min(850, screenWidth * 0.88),
            height: min(420, visibleHeight * 0.52)
        )
    }

    var body: some View {
        if permissionsManager.screenRecordingStatus != .granted {
            MultiAudioPermissionRequiredView(navigationStack: $navigationStack)
                .frame(width: panelSize.width, height: panelSize.height)
        } else {
            SystemAudioPanel(navigationStack: $navigationStack)
                .padding(.top, 8)
                .frame(width: panelSize.width, height: panelSize.height)
        }
    }
}

// MARK: - Screen Recording gate
struct MultiAudioPermissionRequiredView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @ObservedObject private var permissionsManager = PermissionsManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: permissionSymbolName)
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Screen Recording Required")
                .font(.title2).bold()

            Text("Multi-audio won't work without Screen Recording permission. Sapphire needs it to adjust app volumes, eqs and more.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                if permissionsManager.screenRecordingStatus == .denied {
                    SystemPreferencesPane.screenCapture.open()
                } else {
                    permissionsManager.requestPermission(.screenRecording)
                }
            } label: {
                Label(grantedTitle, systemImage: "record.circle")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Text("After enabling it, reopen this menu.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }

    private var grantedTitle: String {
        permissionsManager.screenRecordingStatus == .denied
            ? "Open System Settings"
            : "Enable Screen Recording"
    }

    private var permissionSymbolName: String {
        permissionsManager.screenRecordingStatus == .denied
            ? "lock.fill"
            : "record.circle"
    }
}

struct SystemAudioPanel: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var unified: Bool = false
    @ObservedObject private var permissionsManager = PermissionsManager.shared

    enum Tab { case devices, apps }
    @State private var selectedTab: Tab = .apps

    var body: some View {
        if permissionsManager.screenRecordingStatus != .granted {
            MultiAudioPermissionRequiredView(navigationStack: $navigationStack)
        } else if unified {
            VStack(alignment: .leading, spacing: 18) {
                Text("APPS")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                    .padding(.horizontal, 24)
                AppSectionView(navigationStack: $navigationStack, omitOuterPadding: true)
                DeviceSectionView(navigationStack: $navigationStack, omitOuterPadding: true)
            }
            .padding(.top, 4)
            .padding(.bottom, 4)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    tabButton("Apps", icon: "square.grid.2x2", tab: .apps)
                    tabButton("Devices", icon: "tv.and.hifispeaker.fill", tab: .devices)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.2)))
                .padding(.horizontal, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    if selectedTab == .apps {
                        AppSectionView(navigationStack: $navigationStack)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else {
                        DeviceSectionView(navigationStack: $navigationStack)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
        }
    }

    private func tabButton(_ title: String, icon: String, tab: Tab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(selectedTab == tab ? Color.accentColor : Color.white.opacity(0.06))
        .foregroundColor(selectedTab == tab ? .white : .primary)
        .clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab == tab)
    }
}

// MARK: - App Section

struct AppSectionView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var omitOuterPadding: Bool = false
    @StateObject private var store = MainMenuPerAppVolumeStore()
    @ObservedObject private var audioManager = MultiAudioManager.shared

    private var arrangedApps: [MainMenuRunningAppItem] {
        let byID = Dictionary(store.runningApps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        return audioManager.appOrdering.arrange(store.runningApps.map(\.bundleID)).compactMap { byID[$0] }
    }

    var body: some View {
        let apps = arrangedApps
        let visibleIDs = apps.map(\.bundleID)
        VStack(spacing: 8) {
            ForEach(apps) { app in
                AppControlCard(
                    app: app,
                    volume: store.volume(for: app.bundleID),
                    onVolumeChange: { store.setVolume($0, for: app.bundleID) },
                    onMute: { store.setMute(!$0, for: app.bundleID) },
                    isMuted: store.mute(for: app.bundleID),
                    onReset: { store.reset(for: app.bundleID) },
                    navigationStack: $navigationStack,
                    isRecentlyActive: app.isRecentlyActive,
                    isCurrentlyOutputting: app.isCurrentlyOutputting,
                    isEightDAudioEnabled: audioManager.eightDAudioSettings(for: app.bundleID).enabled,
                    isSurroundAudioEnabled: audioManager.surroundAudioSettings(for: app.bundleID).enabled,
                    route: audioManager.route(for: app.bundleID),
                    outputs: audioManager.availableOutputDevices,
                    onRoute: { audioManager.setRoute($0, for: app.bundleID) },
                    isPinned: audioManager.appOrdering.isPinned(app.bundleID),
                    onPin: { audioManager.togglePin(app.bundleID) },
                    onMove: { audioManager.move(app.bundleID, offset: $0, visible: visibleIDs) },
                    onHide: { audioManager.hideApp(app.bundleID) }
                )
            }
            if !audioManager.appOrdering.hidden.isEmpty {
                HiddenAppsMenu(hidden: audioManager.appOrdering.hidden, names: store.namesByBundleID)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, omitOuterPadding ? 4 : 20)
        .padding(.top, omitOuterPadding ? 0 : 10)
        .onAppear { store.refreshRunningApps() }
    }
}

fileprivate struct AppControlCard: View {
    let app: MainMenuRunningAppItem
    let volume: Double
    let onVolumeChange: (Double) -> Void
    let onMute: (Bool) -> Void
    let isMuted: Bool
    let onReset: () -> Void
    @Binding var navigationStack: [NotchWidgetMode]
    var isRecentlyActive: Bool = false
    var isCurrentlyOutputting: Bool = false
    var isEightDAudioEnabled: Bool = false
    var isSurroundAudioEnabled: Bool = false
    var route: String? = nil
    var outputs: [AudioDevice] = []
    var onRoute: (String?) -> Void = { _ in }
    var isPinned: Bool = false
    var onPin: () -> Void = {}
    var onMove: (Int) -> Void = { _ in }
    var onHide: () -> Void = {}

    private var statusText: String {
        if isMuted { return "Muted" }
        if isCurrentlyOutputting { return "Playing" }
        if isRecentlyActive { return "Recent" }
        return "Idle"
    }

    private var statusColor: Color {
        if isMuted { return .red }
        if isCurrentlyOutputting { return .green }
        if isRecentlyActive { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 25, height: 25).cornerRadius(5)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    if isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                    }
                    Text(app.name).font(.system(size: 11, weight: .bold)).lineLimit(1)
                }
                Text(statusText).font(.system(size: 8, weight: .semibold)).foregroundStyle(statusColor)
            }.frame(width: 80, alignment: .leading)

            AppVolumeSlider(volume: volume, onVolumeChange: onVolumeChange)
                .frame(height: 30)

            AppRouteMenu(route: route, outputs: outputs, onRoute: onRoute)

            SmallIconButton(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: isMuted) { onMute(isMuted) }
            SmallIconButton(icon: "slider.vertical.3", active: false) { navigationStack.append(.multiAudioAppEQ(bundleID: app.bundleID, appName: app.name)) }
            SmallIconButton(icon: "rotate.3d", active: isEightDAudioEnabled) {
                guard SubscriptionAccess.hasAccess(to: .audio8D) else {
                    _ = FeatureGate.shared.require(.audio8D, message: premiumDefaultMessage(for: .audio8D))
                    return
                }
                navigationStack.append(.multiAudioApp8D(bundleID: app.bundleID, appName: app.name))
            }
            SmallIconButton(icon: "hifispeaker.2.fill", active: isSurroundAudioEnabled) {
                guard SubscriptionAccess.hasAccess(to: .surroundSound) else {
                    _ = FeatureGate.shared.require(.surroundSound, message: premiumDefaultMessage(for: .surroundSound))
                    return
                }
                navigationStack.append(.multiAudioAppSurround(bundleID: app.bundleID, appName: app.name))
            }
            SmallIconButton(icon: "arrow.counterclockwise", active: false, destructive: true) { onReset() }
        }
        .padding(.vertical, 15).padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isCurrentlyOutputting || isRecentlyActive ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrentlyOutputting ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin to Top", action: onPin)
            Button("Move Up") { onMove(-1) }
            Button("Move Down") { onMove(1) }
            Divider()
            Button("Hide from Mixer", action: onHide)
        }
    }
}

fileprivate struct AppRouteMenu: View {
    let route: String?
    let outputs: [AudioDevice]
    let onRoute: (String?) -> Void

    private var routeIsConnected: Bool {
        guard let route else { return false }
        return outputs.contains { $0.uid == route }
    }

    var body: some View {
        Menu {
            Button {
                onRoute(nil)
            } label: {
                if route == nil { Label("Mixer Output", systemImage: "checkmark") } else { Text("Mixer Output") }
            }
            Divider()
            ForEach(outputs) { device in
                Button {
                    onRoute(device.uid)
                } label: {
                    if route == device.uid { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
            if route != nil, !routeIsConnected {
                Divider()
                Text("Saved device is disconnected")
            }
        } label: {
            Image(systemName: route == nil ? "hifispeaker" : (routeIsConnected ? "arrow.triangle.branch" : "exclamationmark.triangle"))
                .font(.system(size: 11, weight: .bold))
                .frame(width: 32, height: 32)
                .background(route == nil ? Color.white.opacity(0.08) : Color.accentColor)
                .foregroundColor(route == nil ? .primary : .white)
                .clipShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Output device for this app")
    }
}

fileprivate struct HiddenAppsMenu: View {
    let hidden: Set<String>
    let names: [String: String]
    @ObservedObject private var audioManager = MultiAudioManager.shared

    var body: some View {
        Menu {
            ForEach(hidden.sorted(), id: \.self) { bundleID in
                Button("Show \(names[bundleID] ?? bundleID)") { audioManager.unhideApp(bundleID) }
            }
            Divider()
            Button("Show All") { audioManager.unhideAllApps() }
        } label: {
            Label(hidden.count == 1 ? "1 hidden app" : "\(hidden.count) hidden apps", systemImage: "eye.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

fileprivate struct AppVolumeSlider: View {
    let volume: Double
    let onVolumeChange: (Double) -> Void
    @State private var localValue: Double

    init(volume: Double, onVolumeChange: @escaping (Double) -> Void) {
        self.volume = volume
        self.onVolumeChange = onVolumeChange
        _localValue = State(initialValue: volume * 100.0)
    }

    var body: some View {
        BoldPillSlider(
            label: localValue > 100.5 ? "Boost" : "Volume",
            value: $localValue,
            range: 0...Double(PerAppAudioController.maxVolume * 100),
            specifier: "%.0f%%",
            tint: localValue > 100.5 ? .orange : .accentColor
        )
        .onChange(of: localValue) { _, newValue in
            onVolumeChange(newValue / 100.0)
        }
        .onChange(of: volume) { _, newValue in
            let percentage = newValue * 100.0
            if abs(localValue - percentage) > 0.01 {
                localValue = percentage
            }
        }
    }
}

// MARK: - Device Section

struct DeviceSectionView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var omitOuterPadding: Bool = false
    @StateObject private var audioManager = MultiAudioManager.shared

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("OUTPUTS").font(.system(size: 11, weight: .black)).foregroundStyle(.secondary).tracking(1.2).padding(.horizontal, 4)
                VStack(spacing: 8) {
                    ForEach(audioManager.availableOutputDevices) { device in
                        let isSel = audioManager.selectedOutputDeviceIDs.contains(device.id)
                        let isActive = isSel || (audioManager.selectedOutputDeviceIDs.isEmpty && device.id == audioManager.defaultOutputDeviceID)
                        DeviceControlCard(
                            device: device, isActive: isActive, isExplicitlySelected: isSel,
                            onSelect: {
                                if isSel { audioManager.selectedOutputDeviceIDs.remove(device.id) }
                                else { audioManager.selectedOutputDeviceIDs.insert(device.id) }
                            },
                            onAdjust: { navigationStack.append(.multiAudioDeviceAdjust(device)) },
                            onEQ: { navigationStack.append(.multiAudioEQ(device)) },
                            onEarbuds: EarbudControlManager.shared.supports(device)
                                ? { navigationStack.append(.earbudControls(device)) }
                                : nil,
                            volumeBinding: Binding(
                                get: { audioManager.deviceSettings[device.id]?.volume ?? 1.0 },
                                set: { var s = audioManager.deviceSettings[device.id] ?? AudioDeviceSettings(); s.volume = $0; audioManager.updateSettings(for: device.id, settings: s) }
                            )
                        )
                    }
                }
            }

            if !audioManager.availableInputDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("INPUTS").font(.system(size: 11, weight: .black)).foregroundStyle(.secondary).tracking(1.2).padding(.horizontal, 4)
                    VStack(spacing: 8) {
                        ForEach(audioManager.availableInputDevices) { device in
                            let isDefault = device.id == audioManager.currentInputDeviceID
                            DeviceControlCard(
                                device: device,
                                isActive: isDefault,
                                isExplicitlySelected: isDefault && audioManager.preferredInputUID == device.uid,
                                onSelect: { audioManager.selectInputDevice(device) },
                                onAdjust: { navigationStack.append(.multiAudioDeviceAdjust(device)) }, onEQ: {},
                                volumeBinding: Binding(
                                    get: { Double(audioManager.inputVolumes[device.id] ?? 1.0) },
                                    set: { audioManager.setInputVolume(Float($0), for: device.id) }
                                ),
                                isMicMuted: audioManager.areAllInputsMuted || audioManager.isInputMuted(for: device.id),
                                isInputRow: true
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, omitOuterPadding ? 8 : 24)
        .padding(.top, omitOuterPadding ? 0 : 8)
    }
}

fileprivate struct DeviceControlCard: View {
    let device: AudioDevice
    let isActive: Bool
    let isExplicitlySelected: Bool
    let onSelect: () -> Void
    let onAdjust: () -> Void
    let onEQ: () -> Void
    var onEarbuds: (() -> Void)? = nil
    let volumeBinding: Binding<Double>
    var isMicMuted: Bool = false
    var isInputRow: Bool = false

    @State private var internalGain: Double = 0.0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: getIcon()).font(.system(size: 16)).foregroundColor(getColor()).frame(width: 25)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if isActive { Circle().fill(Color.accentColor).frame(width: 6).shadow(color: .accentColor.opacity(0.6), radius: 3) }
                    Text(device.name).font(.system(size: 11, weight: isActive ? .bold : .semibold)).lineLimit(1)
                }
                Text(getSubtitle()).font(.system(size: 8, weight: .semibold)).foregroundStyle(getSubtitleColor())
            }
            .frame(width: 85, alignment: .leading)

            BoldPillSlider(label: device.isOutput ? "Volume" : "Gain", value: $internalGain, range: 0...100, specifier: "%.0f%%")
                .frame(height: 30)
                .onChange(of: internalGain) { _, nv in
                    if abs(nv/100.0 - volumeBinding.wrappedValue) > 0.01 { volumeBinding.wrappedValue = nv/100.0 }
                }

            if isInputRow {
                SmallIconButton(icon: isMicMuted ? "mic.slash.fill" : "mic.fill", active: isMicMuted, destructive: isMicMuted) {
                    MultiAudioManager.shared.setAllInputMutes(!isMicMuted)
                }
            }
            SmallIconButton(icon: "slider.vertical.3", active: false, action: onAdjust)
            if device.isOutput { SmallIconButton(icon: "waveform.path.ecg", active: false, action: onEQ) }
            if device.isOutput, let onEarbuds {
                SmallIconButton(icon: "headphones", active: false, action: onEarbuds)
            }
        }
        .padding(.vertical, 15).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(getBg()))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(getBorder(), lineWidth: isExplicitlySelected ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onSelect() }
        .onAppear { sync() }
        .onChange(of: volumeBinding.wrappedValue) { _, _ in sync() }
    }

    private func sync() {
        let hw = volumeBinding.wrappedValue * 100.0
        if abs(internalGain - hw) > 1.0 { internalGain = hw }
    }

    private func getIcon() -> String { device.isOutput ? "hifispeaker.2.fill" : (isMicMuted ? "mic.slash.fill" : "mic.fill") }
    private func getColor() -> Color { device.isOutput ? (isActive ? .accentColor : .primary.opacity(0.8)) : (isMicMuted ? .red : (isActive ? .accentColor : .primary.opacity(0.8))) }
    private func getSubtitle() -> String { device.isOutput ? (isActive ? "Active Channel" : "Standby") : (isMicMuted ? "Muted" : (isActive ? "System Input" : "Microphone")) }
    private func getSubtitleColor() -> Color { device.isOutput ? (isActive ? .accentColor.opacity(0.8) : .secondary) : (isMicMuted ? .red.opacity(0.8) : .secondary) }
    private func getBg() -> Color { device.isOutput ? (isActive ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.05)) : (isMicMuted ? Color.red.opacity(0.08) : (isActive ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.05))) }
    private func getBorder() -> Color { device.isOutput ? (isExplicitlySelected ? .accentColor : (isActive ? .accentColor.opacity(0.4) : .clear)) : (isMicMuted ? .red.opacity(0.4) : (isExplicitlySelected ? .accentColor : (isActive ? .accentColor.opacity(0.4) : .clear))) }
}

// MARK: - Reusable UI

fileprivate struct SmallIconButton: View {
    let icon: String
    let active: Bool
    var destructive: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).frame(width: 32, height: 32)
                .background(active ? (destructive ? Color.red : Color.accentColor) : (destructive ? Color.red.opacity(0.1) : Color.white.opacity(0.08)))
                .foregroundColor(active ? .white : (destructive ? .red : .primary)).clipShape(Circle())
        }.buttonStyle(.plain).scaleEffect(active ? 1.05 : 1.0)
    }
}

// MARK: - Data Stores

fileprivate struct MainMenuRunningAppItem: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let isRecentlyActive: Bool
    let isCurrentlyOutputting: Bool
    let lastActivityDate: Date?
    var id: String { bundleID }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleID == rhs.bundleID
            && lhs.name == rhs.name
            && lhs.icon === rhs.icon
            && lhs.isRecentlyActive == rhs.isRecentlyActive
            && lhs.isCurrentlyOutputting == rhs.isCurrentlyOutputting
            && lhs.lastActivityDate == rhs.lastActivityDate
    }
}

@MainActor
fileprivate final class MainMenuPerAppVolumeStore: ObservableObject {
    @Published var runningApps: [MainMenuRunningAppItem] = []
    var namesByBundleID: [String: String] {
        Dictionary(runningApps.map { ($0.bundleID, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var recentExpiryWorkItem: DispatchWorkItem?
    private let recentWindow: TimeInterval = 180

    init() {
        refreshRunningApps()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshRunningApps() }
        })
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshRunningApps() }
        })

        let appCenter = NotificationCenter.default
        appObservers.append(appCenter.addObserver(forName: .multiAudioActiveBundlesDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRunningApps() }
        })
        appObservers.append(appCenter.addObserver(forName: .perAppAudioSettingsDidChange, object: nil, queue: .main) { [weak self] notification in
            let kind = notification.userInfo?[PerAppAudioController.changeKindUserInfoKey] as? String
            guard kind == nil || kind == PerAppAudioController.ChangeKind.mute.rawValue || kind == PerAppAudioController.ChangeKind.reset.rawValue else {
                return
            }
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        })
    }

    deinit {
        recentExpiryWorkItem?.cancel()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        let appCenter = NotificationCenter.default
        appObservers.forEach(appCenter.removeObserver)
    }

    private static var iconCache: [String: NSImage] = [:]

    private static func icon(for bundleID: String, pid: pid_t) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        if let icon { iconCache[bundleID] = icon }
        return icon
    }

    func refreshRunningApps() {
        let audio = MultiAudioManager.shared
        let activeAudio = audio.activeAudioBundleIDs()
        let now = Date()
        let refreshedApps = RunningApps.shared.infoByPID()
            .filter { $0.value.isRegular }
            .compactMap { pid, info -> MainMenuRunningAppItem? in
                guard let bundleID = info.bundleID,
                      bundleID != Bundle.main.bundleIdentifier else { return nil }
                let lastActivityDate = audio.lastAudioActivityDate(for: bundleID)
                let isRecentlyActive = lastActivityDate.map {
                    now.timeIntervalSince($0) <= self.recentWindow
                } ?? false
                return MainMenuRunningAppItem(
                    bundleID: bundleID,
                    name: info.name ?? "Unknown App",
                    icon: Self.icon(for: bundleID, pid: pid),
                    isRecentlyActive: isRecentlyActive,
                    isCurrentlyOutputting: activeAudio.contains(bundleID),
                    lastActivityDate: lastActivityDate
                )
            }
            .sorted { lhs, rhs in
                if lhs.isCurrentlyOutputting != rhs.isCurrentlyOutputting {
                    return lhs.isCurrentlyOutputting && !rhs.isCurrentlyOutputting
                }
                if lhs.isRecentlyActive != rhs.isRecentlyActive {
                    return lhs.isRecentlyActive && !rhs.isRecentlyActive
                }
                if lhs.isRecentlyActive,
                   rhs.isRecentlyActive,
                   let ld = lhs.lastActivityDate,
                   let rd = rhs.lastActivityDate,
                   ld != rd {
                    return ld > rd
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        if runningApps != refreshedApps {
            runningApps = refreshedApps
        }
        scheduleNextRecentExpiry(from: refreshedApps)
    }

    private func scheduleNextRecentExpiry(from apps: [MainMenuRunningAppItem]) {
        recentExpiryWorkItem?.cancel()
        recentExpiryWorkItem = nil

        guard let expiry = apps.lazy
            .filter({ $0.isRecentlyActive && !$0.isCurrentlyOutputting })
            .compactMap({ $0.lastActivityDate?.addingTimeInterval(self.recentWindow) })
            .min()
        else { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.recentExpiryWorkItem = nil
                self?.refreshRunningApps()
            }
        }
        recentExpiryWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.05, expiry.timeIntervalSinceNow),
            execute: work
        )
    }

    func volume(for bID: String) -> Double { PerAppAudioController.shared.volume(for: bID) }
    func mute(for bID: String) -> Bool { PerAppAudioController.shared.mute(for: bID) }
    func setVolume(_ v: Double, for bID: String) { PerAppAudioController.shared.setVolume(v, for: bID) }
    func setMute(_ m: Bool, for bID: String) { PerAppAudioController.shared.setMute(m, for: bID) }
    func reset(for bID: String) {
        PerAppAudioController.shared.reset(for: bID)
        MultiAudioManager.shared.resetEightDAudio(for: bID)
        MultiAudioManager.shared.resetSurroundAudio(for: bID)
    }
}