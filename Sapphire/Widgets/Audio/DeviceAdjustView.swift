//
//  DeviceAdjustView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI
import AppKit

struct DeviceAdjustView: View {
    let device: AudioDevice
    @StateObject private var audioManager = MultiAudioManager.shared
    @StateObject private var appStore = AdjustViewPerAppStore()
    
    // Output state
    @State private var settings: AudioDeviceSettings
    
    // Input state
    @State private var micGain: Double = 1.0
    @State private var isMicMuted: Bool = false
    @State private var sampleRate: Double = 0.0
    @State private var availableRates: [Double] = []
    @State private var streamFormat: String = ""

    init(device: AudioDevice) {
        self.device = device
        _settings = State(initialValue: MultiAudioManager.shared.deviceSettings[device.id] ?? AudioDeviceSettings())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Minimal Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.isOutput ? "MASTER ADJUSTMENTS" : "MICROPHONE CONFIGURATION")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1.2)
                    Text(device.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: device.isOutput ? "slider.horizontal.3" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if device.isOutput {
                outputControls
            } else {
                inputControls
            }
            
            Spacer(minLength: 0)
        }
        .frame(width: 750, height: 380)
        .background(Color.black)
        .onAppear {
            if device.isInput { refreshInputStats() }
        }
        .onChange(of: settings) { _, newSettings in
            if device.isOutput { audioManager.updateSettings(for: device.id, settings: newSettings) }
        }
    }
    
    private func refreshInputStats() {
        micGain = Double(audioManager.getInputVolume(for: device.id))
        isMicMuted = audioManager.isInputMuted(for: device.id)
        sampleRate = MultiAudioManager.getNominalSampleRate(for: device.id) // <--- FIXED
        availableRates = audioManager.getAvailableSampleRates(for: device.id)
        streamFormat = audioManager.getStreamFormat(for: device.id)
    }
    
    // MARK: - Output Layout
    @ViewBuilder
    private var outputControls: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Main DSP Grid
                HStack(spacing: 16) {
                    VStack(spacing: 12) {
                        ModernDarkSlider(label: "Volume", value: $settings.volume, range: 0...1.0, formatDisplay: { "\(Int($0 * 100))%" })
                        ModernDarkSlider(label: "Delay", value: $settings.delay, range: 0...0.5, formatDisplay: { "\(Int($0 * 1000))ms" })
                        ModernDarkSlider(label: "Balance", value: $settings.balance, range: 0...1.0, formatDisplay: { val in
                            if abs(val - 0.5) < 0.02 { return "Center" }
                            return val < 0.5 ? "L \(Int((0.5-val)*200))" : "R \(Int((val-0.5)*200))"
                        })
                    }
                    .padding(16)
                    .background(cardBackground)
                    
                    if !appStore.runningApps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("APP MIXER").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(1)
                            VStack(spacing: 8) {
                                ForEach(appStore.runningApps.prefix(3)) { app in
                                    AppMixRow(app: app, volume: appStore.volume(for: app.bundleID), onVolumeChange: { appStore.setVolume($0, for: app.bundleID) })
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(cardBackground)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Input Layout
    @ViewBuilder
    private var inputControls: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Column: Gain & Mute
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LEVELS").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(1)
                    ModernDarkSlider(label: "Input Gain", value: Binding(get: { micGain }, set: { micGain = $0; audioManager.setInputVolume(Float($0), for: device.id) }), range: 0...1.0, formatDisplay: { "\(Int($0 * 100))%" })
                    
                    HStack {
                        Label("Hardware Mute", systemImage: isMicMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isMicMuted ? .red : .white.opacity(0.8))
                        Spacer()
                        Toggle("", isOn: Binding(get: { isMicMuted }, set: { isMicMuted = $0; audioManager.setInputMute($0, for: device.id) }))
                            .toggleStyle(SwitchToggleStyle(tint: .red))
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(cardBackground)
                
                // Shortcut
                Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")) }) {
                    HStack {
                        Image(systemName: "dial.min.fill")
                        Text("Open Audio MIDI Setup").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right.square").opacity(0.5)
                    }
                    .padding(14)
                    .background(cardBackground)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 360)
            
            // Right Column: Technical Specs
            VStack(alignment: .leading, spacing: 12) {
                Text("SPECIFICATIONS").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4)).tracking(1)
                
                VStack(spacing: 12) {
                    specRow(label: "Stream Format", value: streamFormat)
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    HStack {
                        Text("Sample Rate").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(get: { sampleRate }, set: { sampleRate = $0; audioManager.setNominalSampleRate($0, for: device.id) })) {
                            ForEach(availableRates, id: \.self) { rate in
                                Text("\(Int(rate / 1000)) kHz").tag(rate)
                            }
                        }
                        .labelsHidden()
                        .scaleEffect(0.9)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

fileprivate struct ModernDarkSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatDisplay: (Double) -> String
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let textView = HStack {
                Text(label).font(.system(size: 12, weight: .bold))
                Spacer()
                Text(formatDisplay(value)).font(.system(size: 11, weight: .bold, design: .monospaced))
            }.padding(.horizontal, 12)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                textView.foregroundColor(.white.opacity(0.5))
                ZStack {
                    Capsule().fill(Color.accentColor)
                    textView.foregroundColor(.white)
                }.mask(Rectangle().frame(width: max(0, min(width, progress))).frame(maxWidth: .infinity, alignment: .leading))
            }.clipShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let pct = Double(v.location.x / width)
                value = min(max((range.upperBound - range.lowerBound) * pct + range.lowerBound, range.lowerBound), range.upperBound)
            })
        }.frame(height: 32)
    }
}

fileprivate struct AppMixRow: View {
    let app: AdjustAppItem
    let volume: Double
    let onVolumeChange: (Double) -> Void
    var body: some View {
        HStack(spacing: 10) {
            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 70, alignment: .leading)
            ModernDarkSlider(label: "", value: Binding(get: { volume }, set: { onVolumeChange($0) }), range: 0...1.0, formatDisplay: { "\(Int($0 * 100))%" })
        }
    }
}

// MARK: - Local Stores
fileprivate struct AdjustAppItem: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    var id: String { bundleID }
}

@MainActor
fileprivate final class AdjustViewPerAppStore: ObservableObject {
    @Published var runningApps: [AdjustAppItem] = []
    private var observer: NSObjectProtocol?

    init() {
        refreshRunningApps()
        observer = NotificationCenter.default.addObserver(
            forName: .multiAudioActiveBundlesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRunningApps()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refreshRunningApps() {
        let activeBundles = MultiAudioManager.shared.activeAudioBundleIDs()
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { activeBundles.contains($0.bundleIdentifier!) }
            .compactMap { AdjustAppItem(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? "Unknown", icon: $0.icon) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func volume(for bundleID: String) -> Double {
        PerAppAudioController.shared.volume(for: bundleID)
    }

    func setVolume(_ value: Double, for bundleID: String) {
        PerAppAudioController.shared.setVolume(value, for: bundleID)
        objectWillChange.send()
    }
}
