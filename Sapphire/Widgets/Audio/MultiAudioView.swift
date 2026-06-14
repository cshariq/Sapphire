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
    enum Tab { case devices, apps, none }
    @State private var selectedTab: Tab = .apps
    @Namespace private var animation

    var body: some View {
        VStack(spacing: 0) {
            // Tab Switcher
            HStack(spacing: 4) {
                tabButton("Apps", icon: "square.grid.2x2", tab: .apps)
                tabButton("Devices", icon: "tv.and.hifispeaker.fill", tab: .devices)
                tabButton("Spotify Devices", icon: "hifispeaker.and.homepod.mini.fill", tab: .none, action: { navigationStack.append(.musicDevices) })
                Spacer()
            }
            .padding(15)
            .padding(.top, 0)
            .background(Capsule().fill(.black.opacity(0.2)))

            ScrollView(.vertical, showsIndicators: false) {
                if selectedTab == .apps {
                    AppSectionView(navigationStack: $navigationStack)
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    DeviceSectionView(navigationStack: $navigationStack)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
        }
        .frame(width: 850, height: 400)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
    }

    func tabButton(_ title: String, icon: String, tab: Tab, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action = action { action() }
            else { selectedTab = tab }
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

fileprivate struct AppSectionView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @StateObject private var store = MainMenuPerAppVolumeStore()
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.runningApps) { app in
                AppControlCard(
                    app: app,
                    volume: store.volume(for: app.bundleID),
                    onVolumeChange: { store.setVolume($0, for: app.bundleID) },
                    onMute: { store.setMute(!$0, for: app.bundleID) },
                    isMuted: store.mute(for: app.bundleID),
                    onReset: { store.reset(for: app.bundleID) },
                    navigationStack: $navigationStack
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 25, height: 25).cornerRadius(5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 11, weight: .bold)).lineLimit(1)
                Text(isMuted ? "Muted" : "Active").font(.system(size: 8, weight: .semibold)).foregroundStyle(isMuted ? .red : .green)
            }.frame(width: 80, alignment: .leading)
            
            BoldPillSlider(label: "Volume", value: Binding(get: { volume * 100.0 }, set: { onVolumeChange($0/100.0) }), range: 0...100, specifier: "%.0f%%").frame(height: 30)
            
            SmallIconButton(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: isMuted) { onMute(isMuted) }
            SmallIconButton(icon: "slider.vertical.3", active: false) { navigationStack.append(.multiAudioAppEQ(bundleID: app.bundleID, appName: app.name)) }
            SmallIconButton(icon: "arrow.counterclockwise", active: false, destructive: true) { onReset() }
        }
        .padding(.vertical, 15).padding(.horizontal, 12).background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
    }
}

// MARK: - Device Section

fileprivate struct DeviceSectionView: View {
    @Binding var navigationStack: [NotchWidgetMode]
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
                            DeviceControlCard(
                                device: device, isActive: false, isExplicitlySelected: false, onSelect: {},
                                onAdjust: { navigationStack.append(.multiAudioDeviceAdjust(device)) }, onEQ: {},
                                volumeBinding: Binding(
                                    get: { Double(audioManager.getInputVolume(for: device.id)) },
                                    set: { audioManager.setInputVolume(Float($0), for: device.id) }
                                )
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 24).padding(.top, 8)
    }
}

fileprivate struct DeviceControlCard: View {
    let device: AudioDevice
    let isActive: Bool
    let isExplicitlySelected: Bool
    let onSelect: () -> Void
    let onAdjust: () -> Void
    let onEQ: () -> Void
    let volumeBinding: Binding<Double>
    
    @State private var isMicMuted: Bool = false
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
            
            SmallIconButton(icon: "slider.vertical.3", active: false, action: onAdjust)
            if device.isOutput { SmallIconButton(icon: "waveform.path.ecg", active: false, action: onEQ) }
        }
        .padding(.vertical, 15).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(getBg()))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(getBorder(), lineWidth: isExplicitlySelected ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if device.isOutput { onSelect() }
            else { isMicMuted.toggle(); MultiAudioManager.shared.setInputMute(isMicMuted, for: device.id) }
        }
        .onAppear { sync() }
        .onReceive(MultiAudioManager.shared.objectWillChange) { _ in sync() }
    }

    private func sync() {
        if device.isInput { isMicMuted = MultiAudioManager.shared.isInputMuted(for: device.id) }
        let hw = volumeBinding.wrappedValue * 100.0
        if abs(internalGain - hw) > 1.0 { internalGain = hw }
    }
    
    private func getIcon() -> String { device.isOutput ? "hifispeaker.2.fill" : (isMicMuted ? "mic.slash.fill" : "mic.fill") }
    private func getColor() -> Color { device.isOutput ? (isActive ? .accentColor : .primary.opacity(0.8)) : (isMicMuted ? .red : .primary.opacity(0.8)) }
    private func getSubtitle() -> String { device.isOutput ? (isActive ? "Active Channel" : "Standby") : (isMicMuted ? "Muted" : "Microphone") }
    private func getSubtitleColor() -> Color { device.isOutput ? (isActive ? .accentColor.opacity(0.8) : .secondary) : (isMicMuted ? .red.opacity(0.8) : .secondary) }
    private func getBg() -> Color { device.isOutput ? (isActive ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.05)) : (isMicMuted ? Color.red.opacity(0.08) : Color.white.opacity(0.05)) }
    private func getBorder() -> Color { device.isOutput ? (isExplicitlySelected ? .accentColor : (isActive ? .accentColor.opacity(0.4) : .clear)) : (isMicMuted ? .red.opacity(0.4) : .clear) }
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

fileprivate struct BoldPillSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let specifier: String
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let textView = HStack {
                Text(label).fontWeight(.bold)
                Spacer()
                Text(String(format: specifier, value)).font(.system(.body, design: .monospaced)).fontWeight(.bold)
            }.font(.system(size: 13)).padding(.horizontal, 16)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                textView.foregroundColor(.primary.opacity(0.85))
                ZStack {
                    Capsule().fill(Color.accentColor)
                    textView.foregroundColor(.white)
                }.mask(Rectangle().frame(width: width * min(max(progress, 0), 1)).frame(maxWidth: .infinity, alignment: .leading))
            }.clipShape(Capsule()).contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let percentage = Double(v.location.x / width)
                value = min(max((range.upperBound - range.lowerBound) * percentage + range.lowerBound, range.lowerBound), range.upperBound)
            })
        }
    }
}

// MARK: - Data Stores

fileprivate struct MainMenuRunningAppItem: Identifiable {
    let bundleID: String, name: String, icon: NSImage?
    var id: String { bundleID }
}

@MainActor
fileprivate final class MainMenuPerAppVolumeStore: ObservableObject {
    @Published var runningApps: [MainMenuRunningAppItem] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        refreshRunningApps()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshRunningApps() })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshRunningApps() })
        observers.append(NotificationCenter.default.addObserver(forName: .multiAudioActiveBundlesDidChange, object: nil, queue: .main) { [weak self] _ in self?.refreshRunningApps() })
        observers.append(NotificationCenter.default.addObserver(forName: .perAppAudioSettingsDidChange, object: nil, queue: .main) { [weak self] _ in self?.objectWillChange.send() })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func refreshRunningApps() {
        let activeAudio = MultiAudioManager.shared.activeAudioBundleIDs()
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { MainMenuRunningAppItem(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? "Unknown App", icon: $0.icon) }
            .sorted {
                let lhsActive = activeAudio.contains($0.bundleID)
                let rhsActive = activeAudio.contains($1.bundleID)
                if lhsActive != rhsActive { return lhsActive && !rhsActive }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
    
    func volume(for bID: String) -> Double { PerAppAudioController.shared.volume(for: bID) }
    func mute(for bID: String) -> Bool { PerAppAudioController.shared.mute(for: bID) }
    func setVolume(_ v: Double, for bID: String) { PerAppAudioController.shared.setVolume(v, for: bID) }
    func setMute(_ m: Bool, for bID: String) { PerAppAudioController.shared.setMute(m, for: bID) }
    func reset(for bID: String) { PerAppAudioController.shared.reset(for: bID); objectWillChange.send() }
}
