//
//  DevicesView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-27
//

import SwiftUI

fileprivate class Throttler {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    func throttle(action: @escaping (() -> Void)) {
        guard workItem == nil else { return }
        action()
        workItem = DispatchWorkItem { [weak self] in
            self?.workItem = nil
        }
        queue.asyncAfter(deadline: .now() + delay, execute: workItem!)
    }
}

fileprivate enum DeviceTab: Int {
    case spotify = 0
    case airplay = 1
}

struct DevicesView: View {
    @EnvironmentObject var musicManager: MusicManager
    @EnvironmentObject var settings: SettingsModel

    @Binding var navigationStack: [NotchWidgetMode]

    @State private var selectedTab: DeviceTab

    @State private var spotifyNativeDevices: [SpotifyNativeDevice] = []
    @State private var spotifyOfficialDevices: [SpotifyDevice] = []

    @State private var spotifyVolume: Double = 75

    @State private var isLoading = true

    var isLockScreenMode: Bool = false

    private let volumeThrottler = Throttler(delay: 0.1)

    private let lastSelectedTabKey = "lastSelectedDeviceTab"

    private var isAppleMusic: Bool {
        musicManager.lastKnownBundleID == "com.apple.Music"
    }

    private var isLoggedIn: Bool {
        musicManager.isPrivateAPIAuthenticated || musicManager.isOfficialAPIAuthenticated
    }

    init(navigationStack: Binding<[NotchWidgetMode]>, isLockScreenMode: Bool = false) {
        self._navigationStack = navigationStack
        let savedTab = UserDefaults.standard.integer(forKey: lastSelectedTabKey)
        self._selectedTab = State(initialValue: DeviceTab(rawValue: savedTab) ?? .spotify)
        self.isLockScreenMode = isLockScreenMode
    }

    private func sendVolumeUpdate() {
        Task {
            _ = await musicManager.setSpotifyVolume(percent: Int(spotifyVolume))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if isAppleMusic {
                Text("AirPlay Devices").font(.title2.bold())
                contentBody(for: .airplay)
            } else if !isLoggedIn {
                Text("AirPlay Devices").font(.title2.bold())
                contentBody(for: .airplay)
            } else {
                HStack {
                    if let user = musicManager.spotifyOfficialAPI.userProfile {
                        Text("Welcome, \(user.displayName)").font(.caption.bold()).foregroundColor(.secondary)
                    } else if let nativeUser = musicManager.spotifyPrivateAPI.userProfile {
                        Text("Welcome, \(nativeUser.profile.username)").font(.caption.bold()).foregroundColor(.secondary)
                    }
                    Spacer()

                    HStack(spacing: 10) {
                        TabButton(title: "Spotify", systemImage: "music.note", isSelected: selectedTab == .spotify) { selectedTab = .spotify }
                        TabButton(title: "AirPlay", systemImage: "airplayaudio", isSelected: selectedTab == .airplay) { selectedTab = .airplay }
                    }.padding(6).background(Color.black.opacity(0.2)).clipShape(Capsule())

                    if musicManager.isOfficialAPIAuthenticated {
                        Button("Log out") { musicManager.spotifyOfficialAPI.logout() }.buttonStyle(.plain).font(.caption).foregroundColor(.secondary)
                    }
                }

                ZStack {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        if selectedTab == .spotify {
                            spotifyDeviceList
                                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                        } else {
                            appleMusicDeviceList
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                .frame(minHeight: 200)
            }
        }
        .padding([.top, .horizontal], 20)
        .frame(width: 700)
        .frame(maxHeight: 350)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            Task.detached(priority: .userInitiated) {
                await fetchInitialData()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: lastSelectedTabKey)
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func contentBody(for type: DeviceTab) -> some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch type {
                case .airplay:
                    appleMusicDeviceList
                case .spotify:
                    spotifyDeviceList
                }
            }
        }
        .frame(minHeight: 200)
    }

    @ViewBuilder
    private var appleMusicDeviceList: some View {
        if musicManager.airplayDevices.isEmpty {
            Text("No AirPlay devices found.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(musicManager.airplayDevices) { device in
                        AppleMusicDeviceRow(
                            device: device,
                            onSelect: {
                                Task {
                                    await musicManager.appleMusic.switchToAirPlayDevice(device)
                                    try await Task.sleep(for: .seconds(1))
                                    await musicManager.updateAirPlayDevices()
                                }
                            }
                        )
                    }
                }
                .padding(.bottom, 30)
            }
            .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
        }
    }

    @ViewBuilder
    private var spotifyDeviceList: some View {
        let sortedNativeDevices = spotifyNativeDevices.sorted { d1, d2 in
            let d1IsActive = d1.deviceId == musicManager.spotifyPrivateAPI.activePlayerDeviceID
            let d2IsActive = d2.deviceId == musicManager.spotifyPrivateAPI.activePlayerDeviceID
            if d1IsActive && !d2IsActive { return true }
            if !d1IsActive && d2IsActive { return false }
            return d1.name.localizedCompare(d2.name) == .orderedAscending
        }

        let sortedOfficialDevices = spotifyOfficialDevices.sorted { d1, d2 in
            if d1.isActive && !d2.isActive { return true }
            if !d1.isActive && d2.isActive { return false }
            return d1.name.localizedCompare(d2.name) == .orderedAscending
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if !sortedNativeDevices.isEmpty {
                    SectionHeader(title: "All Devices (Private API)")
                    ForEach(sortedNativeDevices, id: \.deviceId) { device in
                        SpotifyNativeDeviceRow(
                            device: device,
                            isActive: device.deviceId == musicManager.spotifyPrivateAPI.activePlayerDeviceID,
                            volume: $spotifyVolume,
                            onTransfer: {
                                Task.detached(priority: .userInitiated) {
                                    _ = await musicManager.transferSpotifyPlayback(to: device.deviceId)
                                    try? await Task.sleep(for: .seconds(1))
                                    await fetchInitialData()
                                }
                            },
                            onCommit: { sendVolumeUpdate() }
                        )
                    }
                } else if !sortedOfficialDevices.isEmpty {
                    SectionHeader(title: "Premium Devices (Official API)")
                    ForEach(sortedOfficialDevices) { device in
                        SpotifyDeviceRow(
                            device: device,
                            volume: $spotifyVolume,
                            onTransfer: {
                                guard let deviceId = device.id else { return }
                                Task.detached(priority: .userInitiated) {
                                    _ = await musicManager.transferSpotifyPlayback(to: deviceId)
                                    try? await Task.sleep(for: .seconds(1))
                                    await fetchInitialData()
                                }
                            },
                            onCommit: { sendVolumeUpdate() }
                        )
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
        .onChange(of: spotifyVolume) { _, _ in
            volumeThrottler.throttle { sendVolumeUpdate() }
        }
        if !musicManager.isPremiumUser && spotifyNativeDevices.isEmpty { FreeUserNoticeView() }
    }
    // MARK: - Data Fetching

    private func fetchInitialData() async {
        await MainActor.run {
            isLoading = true
        }

        await musicManager.updateAirPlayDevices()

        var fetchedNativeDevices: [SpotifyNativeDevice] = []
        var fetchedOfficialDevices: [SpotifyDevice] = []

        if isLoggedIn {
            if musicManager.isPrivateAPIAuthenticated {
                try? await musicManager.spotifyPrivateAPI.refreshPlayerAndDeviceState()
                fetchedNativeDevices = musicManager.spotifyPrivateAPI.devices
            }
            if musicManager.isOfficialAPIAuthenticated {
                 fetchedOfficialDevices = await musicManager.spotifyOfficialAPI.fetchDevices()
            }

            var newVolume: Double?
            if let activeNativeID = musicManager.spotifyPrivateAPI.activePlayerDeviceID,
               let activeNativeDevice = fetchedNativeDevices.first(where: { $0.deviceId == activeNativeID }) {
                newVolume = (Double(activeNativeDevice.volume ?? 65535) / 65535.0) * 100.0
            } else if let activeOfficial = fetchedOfficialDevices.first(where: { $0.isActive }), let currentVolume = activeOfficial.volumePercent {
                newVolume = Double(currentVolume)
            } else if let localVolume = musicManager.spotifyAppleScript.getLocalVolume() {
                newVolume = Double(localVolume)
            }

            await MainActor.run {
                self.spotifyNativeDevices = fetchedNativeDevices
                self.spotifyOfficialDevices = fetchedOfficialDevices
                if let newVolume = newVolume {
                    self.spotifyVolume = newVolume
                }
                self.isLoading = false
            }
        } else {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Row Views

fileprivate struct AppleMusicDeviceRow: View {
    let device: AirPlayDevice
    let onSelect: () -> Void
    @State private var volume: Double
    private let throttler = Throttler(delay: 0.1)
    @EnvironmentObject var musicManager: MusicManager

    init(device: AirPlayDevice, onSelect: @escaping () -> Void) {
        self.device = device
        self.onSelect = onSelect
        _volume = State(initialValue: Double(device.volume ?? 75))
    }

    private func sendVolumeUpdate() {
        Task {
            SystemControl.setVolume(to: Float(volume / 100.0))
            SystemControl.setMuted(to: false)

            await musicManager.appleMusic.setAirPlayDeviceVolume(deviceName: device.name, volume: Int(volume))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(systemName: device.iconName).font(.title2).frame(width: 30).foregroundColor(device.isSelected ? .blue : .primary)
                Text(device.name).fontWeight(.medium)
                Spacer()
                if device.isSelected { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.blue).transition(.opacity.combined(with: .scale(scale: 0.8))) }
            }
            if device.isSelected {
                BoldPillSlider(label: "Volume", value: $volume, range: 0...100, specifier: "%.0f %%", onCommit: sendVolumeUpdate)
                    .padding(.leading, 45)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16).background(.gray.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).contentShape(Rectangle())
        .onTapGesture { if !device.isSelected { onSelect() } }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: device.isSelected)
        .onChange(of: volume) { _, _ in
            throttler.throttle { sendVolumeUpdate() }
        }
    }
}

fileprivate struct SpotifyDeviceRow: View {
    let device: SpotifyDevice
    @Binding var volume: Double
    let onTransfer: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(systemName: iconName(for: device.type))
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundColor(device.isActive ? .green : .primary)
                Text(device.name).fontWeight(.medium)
                Spacer()
                if device.isActive { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green).transition(.opacity.combined(with: .scale(scale: 0.8))) }
            }
            if device.isActive && device.volumePercent != nil {
                BoldPillSlider(label: "Volume", value: $volume, range: 0...100, specifier: "%.0f %%", onCommit: onCommit)
                    .padding(.leading, 45)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16).background(.gray.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).contentShape(Rectangle())
        .onTapGesture { guard !device.isActive else { return }; onTransfer() }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: device.isActive)
    }

    private func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "desktopcomputer"
        case "speaker": return "hifispeaker.fill"
        case "smartphone": return "iphone"
        case "tv": return "tv.fill"
        case "avr", "stb", "castvideo": return "tv.inset.filled"
        case "gameconsole": return "gamecontroller.fill"
        case "automobile": return "car.fill"
        case "tablet": return "ipad"
        case "castaudio", "audiodongle": return "hifispeaker.2.fill"
        default: return "speaker.wave.2.fill"
        }
    }
}

fileprivate struct SpotifyNativeDeviceRow: View {
    let device: SpotifyNativeDevice
    let isActive: Bool
    @Binding var volume: Double
    let onTransfer: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(systemName: iconName(for: device.deviceType)).font(.title2).frame(width: 30).foregroundColor(isActive ? .green : .primary)
                Text(device.name).fontWeight(.medium)
                Spacer()
                if isActive { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green).transition(.opacity.combined(with: .scale(scale: 0.8))) }
            }
            if isActive && (device.capabilities.volumeSteps ?? 0) > 0 {
                BoldPillSlider(label: "Volume", value: $volume, range: 0...100, specifier: "%.0f %%", onCommit: onCommit)
                    .padding(.leading, 45)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16).background(.gray.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)).contentShape(Rectangle())
        .onTapGesture { if !isActive { onTransfer() } }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }

    private func iconName(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "macbook.gen2"
        case "speaker": return "hifispeaker.2.fill"
        case "smartphone": return "iphone"
        case "avr", "stb": return "tv.inset.filled"
        default: return "questionmark.circle"
        }
    }
}

fileprivate struct FreeUserNoticeView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.lock.fill").font(.title3).foregroundColor(.yellow)
            Text("Switching devices requires a Spotify Premium account or a private api login.").font(.subheadline).foregroundColor(.secondary)
        }.padding().background(Color.yellow.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

fileprivate struct BoldPillSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let specifier: String
    var onCommit: (() -> Void)? = nil

    private var displayValue: String { String(format: specifier, value) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let progressWidth = width * progress
            let textView = HStack { Text(label).fontWeight(.bold); Spacer(); Text(displayValue).font(.system(.body, design: .monospaced)).fontWeight(.bold) }.font(.system(size: 16)).padding(.horizontal, 20)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                textView.foregroundColor(.primary.opacity(0.8))
                ZStack { Capsule().fill(Color.accentColor); textView.foregroundColor(.white) }.mask(Rectangle().frame(width: progressWidth).frame(maxWidth: .infinity, alignment: .leading))
            }
            .clipShape(Capsule()).contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let percentage = (gesture.location.x / width).clamped(to: 0...1)
                    let newValue = (range.upperBound - range.lowerBound) * percentage + range.lowerBound
                    self.value = newValue.clamped(to: range)
                }
                .onEnded { _ in onCommit?() }
            )
        }.frame(height: 44)
    }
}