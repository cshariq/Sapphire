//
//  EarbudControlManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-29

import Foundation
import Combine
import IOBluetooth
import SwiftUI

enum EarbudVendor: String, Codable, Equatable {
    case none
    case galaxy
    case sony

    var displayName: String {
        switch self {
        case .none: String(localized: "Headphones")
        case .galaxy: "Galaxy Buds"
        case .sony: String(localized: "Sony Headphones")
        }
    }

    static func detect(name: String?) -> EarbudVendor {
        guard let name, !name.isEmpty else { return .none }
        if GalaxyBudsModel.detect(from: name) != nil { return .galaxy }
        if SonyDeviceName.matches(name) { return .sony }
        return .none
    }
}

struct EarbudControlSnapshot: Equatable {
    var vendor: EarbudVendor = .none
    var name: String = ""
    var address: String?
    var connected = false
    var ownedLocally = false
    var noiseMode = "off"
    var ancHigh = true
    var eqPreset = "off"
    var batteryLeft = 0
    var batteryRight = 0
    var batteryCase = 0
    var batteryMain = 0
    var dsee = false
    var seamless = false
    var detectConversations = false
    var ambientLevel = 2
    var supportsANC = false
    var supportsAdaptive = false
    var supportsEQ = true
    var supportsDSEE = false
    var supportsSeamless = false
    var supportsFind = false
    var supportsCustomEQ = false
    var customEQBands: [Int] = Array(repeating: 0, count: 9)
    var bassGain = 0
    var gamingMode = false
    var spatialAudio = false
    var touchpadLocked = false
    var touchLeft = GalaxyTouchOption.noiseControl
    var touchRight = GalaxyTouchOption.noiseControl
    var speakSeamlessly = false
    var ancOneEarbud = false
    var autoSwitchAudio = false
    var pauseOnOneBudRemoved = false
    var sidetone = false
    var extraHighAmbient = false
    var amplifyAmbient = false
    var inBandRingtone = false
    var callPathControl = true
    var ambientDuringCall = false
    var detectConversationsDuration = 1
    var outsideDoubleTap = false
    var muteLeft = false
    var muteRight = false
    var wearingLeft = false
    var wearingRight = false
    var fitTesting = false
    var fitLeftGood = false
    var fitRightGood = false
    var supportsGaming = false
    var supportsSpatial = false
    var supportsTouchLock = false
    var supportsFitTest = false
    var supportsAmbientExtras = false
    var supportsCallExtras = false
    var supportsDetectConversations = false
    var supportsExtraClearCall = false
    var supportsPassthrough = false
    var supportsOutsideDoubleTap = false
    var extraClearCall = false
    var passthrough = false

    var batterySummary: String {
        if batteryLeft > 0 || batteryRight > 0 {
            var parts = [String(localized: "L \(String(batteryLeft))%"), String(localized: "R \(String(batteryRight))%")]
            if batteryCase > 0 { parts.append(String(localized: "Case \(String(batteryCase))%")) }
            return parts.joined(separator: " · ")
        }
        if batteryMain > 0 { return "\(batteryMain)%" }
        return connected ? String(localized: "Connected") : String(localized: "Not connected")
    }
}

@MainActor
final class EarbudControlManager: ObservableObject {
    static let shared = EarbudControlManager()

    @Published private(set) var snapshot = EarbudControlSnapshot()
    @Published var lastError: String?

    private let galaxy = GalaxyBudsSPPClient()
    private let sony = SonyHeadphonesSPPClient()
    private var activated = false
    private var lastPublished: ContinuityEarbudStatus?
    private var suppressReconnectUntil = Date.distantPast
    private var bluetoothObservers: [NSObjectProtocol] = []
    private var seamlessReassertedThisSession = false

    private static let preferredSeamlessKey = "continuity.earbuds.preferredSeamless"

    var preferredSeamless: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.preferredSeamlessKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: Self.preferredSeamlessKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.preferredSeamlessKey) }
    }

    var canUseSeamless: Bool {
        snapshot.supportsSeamless
            && snapshot.vendor == .galaxy
            && preferredSeamless
    }

    private init() {
        galaxy.onStatus = { [weak self] status in
            Task { @MainActor in self?.applyGalaxy(status) }
        }
        galaxy.onConnectionChange = { [weak self] open in
            Task { @MainActor in
                guard let self else { return }
                if self.snapshot.vendor == .galaxy {
                    self.snapshot.connected = open
                    self.snapshot.ownedLocally = open
                    if open {
                        self.seamlessReassertedThisSession = false
                    }
                    self.publishIfNeeded()
                }
            }
        }
        sony.onChange = { [weak self] in
            Task { @MainActor in self?.applySony() }
        }
        sony.onConnectionChange = { [weak self] open in
            Task { @MainActor in
                guard let self else { return }
                if self.snapshot.vendor == .sony {
                    self.snapshot.connected = open
                    self.snapshot.ownedLocally = open
                    self.publishIfNeeded()
                }
            }
        }
    }

    func activate() {
        guard !activated else { return }
        activated = true
        installBluetoothObservers()
        if let connected = preferredPaired(), connected.isConnected() {
            attemptPreferredReconnect(device: connected)
        }
    }

    private func installBluetoothObservers() {
        guard bluetoothObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let connected = center.addObserver(
            forName: NSNotification.Name(rawValue: "IOBluetoothDeviceConnectedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleBluetoothConnect(note.object as? IOBluetoothDevice) }
        }
        let disconnected = center.addObserver(
            forName: NSNotification.Name(rawValue: "IOBluetoothDeviceDisconnectedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleBluetoothDisconnect(note.object as? IOBluetoothDevice) }
        }
        bluetoothObservers = [connected, disconnected]
    }

    private func handleBluetoothConnect(_ device: IOBluetoothDevice?) {
        guard let device else {
            attemptPreferredReconnect()
            return
        }
        let vendor = EarbudVendor.detect(name: device.name)
        guard vendor != .none else { return }
        attemptPreferredReconnect(device: device, vendor: vendor)
    }

    private func handleBluetoothDisconnect(_ device: IOBluetoothDevice?) {
        guard let device else { return }
        let addr = ContinuityBluetoothAddress.normalize(device.addressString)
        guard ContinuityBluetoothAddress.matches(addr, snapshot.address) else { return }
        if galaxy.isOpen { galaxy.dropLocalChannel() }
        if sony.isOpen { sony.dropLocalChannel() }
        snapshot.connected = false
        snapshot.ownedLocally = false
        publishIfNeeded()
    }

    private func attemptPreferredReconnect(device: IOBluetoothDevice? = nil, vendor: EarbudVendor? = nil) {
        guard Date() >= suppressReconnectUntil else { return }
        guard !galaxy.isOpen, !sony.isOpen else { return }
        guard !galaxy.handedOffToPhone, !sony.handedOffToPhone else { return }
        let preferred = device ?? preferredPaired()
        guard let preferred else { return }
        let resolved = vendor ?? EarbudVendor.detect(name: preferred.name)
        guard resolved != .none else { return }
        snapshot.vendor = resolved
        snapshot.name = preferred.name ?? snapshot.name
        snapshot.address = ContinuityBluetoothAddress.normalize(preferred.addressString)
        connectPreferred(address: snapshot.address, name: snapshot.name, vendor: resolved)
    }

    func supports(_ device: AudioDevice) -> Bool {
        EarbudVendor.detect(name: device.name) != .none
    }

    func present(for device: AudioDevice) {
        activate()
        let vendor = EarbudVendor.detect(name: device.name)
        snapshot.vendor = vendor
        snapshot.name = device.name
        snapshot.address = ContinuityBluetoothAddress.normalize(device.uid)
        connectPreferred(address: snapshot.address, name: device.name, vendor: vendor)
    }

    func presentCurrent() {
        activate()
        if let device = preferredPaired() {
            snapshot.vendor = EarbudVendor.detect(name: device.name)
            snapshot.name = device.name ?? snapshot.name
            snapshot.address = ContinuityBluetoothAddress.normalize(device.addressString)
            connectPreferred(address: snapshot.address, name: snapshot.name, vendor: snapshot.vendor)
        }
    }

    func handOffToPhone(address: String?) {
        suppressReconnectUntil = Date().addingTimeInterval(1.2)
        let seamless = canUseSeamless && galaxy.isOpen
        if seamless {
            galaxy.yieldAudioStream()
            snapshot.ownedLocally = false
            publishIfNeeded()
        } else {
            galaxy.closeControlChannel()
            sony.close()
            snapshot.connected = false
            snapshot.ownedLocally = false
            publishIfNeeded()
        }
        _ = address
    }

    func reclaim(address: String?, name: String?) {
        suppressReconnectUntil = .distantPast
        galaxy.reclaimFromPhone()
        sony.reclaimFromPhone()
        let vendor = EarbudVendor.detect(name: name)
        snapshot.vendor = vendor == .none ? snapshot.vendor : vendor
        snapshot.address = ContinuityBluetoothAddress.normalize(address) ?? snapshot.address
        if let name { snapshot.name = name }
        if snapshot.vendor == .galaxy, galaxy.isOpen {
            galaxy.resumeAudioStream()
            if canUseSeamless {
                galaxy.sendSeamless(true)
                snapshot.seamless = true
            }
            snapshot.ownedLocally = true
            snapshot.connected = true
            publishIfNeeded()
            return
        }
        connectPreferred(address: snapshot.address, name: snapshot.name, vendor: snapshot.vendor)
    }

    func apply(_ command: ContinuityEarbudCommand) {
        if snapshot.ownedLocally || galaxy.isOpen || sony.isOpen {
            executeLocally(command)
        } else {
            ContinuityManager.shared.connectedPeer?.send(.earbudCommand, command)
        }
    }

    func applyRemote(_ command: ContinuityEarbudCommand) {
        executeLocally(command)
    }

    func applyRemoteStatus(_ status: ContinuityEarbudStatus) {
        guard !snapshot.ownedLocally else { return }
        snapshot = status.snapshot
        snapshot.ownedLocally = false
    }

    func setNoise(_ wire: String) {
        apply(ContinuityEarbudCommand(action: "noise", stringValue: wire))
    }

    func setEQ(_ wire: String) {
        apply(ContinuityEarbudCommand(action: "eq", stringValue: wire))
    }

    func setAncHigh(_ high: Bool) {
        apply(ContinuityEarbudCommand(action: "ancHigh", boolValue: high))
    }

    func setDsee(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "dsee", boolValue: enabled))
    }

    func setSeamless(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "seamless", boolValue: enabled))
    }

    func setDetectConversations(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "detectConversations", boolValue: enabled))
    }

    func setAmbientLevel(_ level: Int) {
        apply(ContinuityEarbudCommand(action: "ambientLevel", intValue: level))
    }

    func setCustomEQ(_ bands: [Int]) {
        apply(ContinuityEarbudCommand(action: "customEq", stringValue: bands.map(String.init).joined(separator: ",")))
    }

    func setBass(_ value: Int) {
        apply(ContinuityEarbudCommand(action: "bass", intValue: value))
    }

    func find(_ start: Bool) {
        apply(ContinuityEarbudCommand(action: "find", boolValue: start))
    }

    func setGamingMode(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "gamingMode", boolValue: enabled))
    }

    func setSpatialAudio(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "spatialAudio", boolValue: enabled))
    }

    func setTouchpadLock(_ locked: Bool) {
        apply(ContinuityEarbudCommand(action: "touchpadLock", boolValue: locked))
    }

    func setOutsideDoubleTap(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "outsideDoubleTap", boolValue: enabled))
    }

    func setExtraClearCall(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "extraClearCall", boolValue: enabled))
    }

    func setPassthrough(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "passthrough", boolValue: enabled))
    }

    func setSidetone(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "sidetone", boolValue: enabled))
    }

    func setExtraHighAmbient(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "extraHighAmbient", boolValue: enabled))
    }

    func setAmplifyAmbient(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "amplifyAmbient", boolValue: enabled))
    }

    func setSpeakSeamlessly(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "speakSeamlessly", boolValue: enabled))
    }

    func setAncOneEarbud(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "ancOneEarbud", boolValue: enabled))
    }

    func setAutoSwitchAudio(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "autoSwitchAudio", boolValue: enabled))
    }

    func setPauseOnOneBud(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "pauseOnOneBud", boolValue: enabled))
    }

    func setInBandRingtone(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "inBandRingtone", boolValue: enabled))
    }

    func setCallPathControl(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "callPathControl", boolValue: enabled))
    }

    func setAmbientDuringCall(_ enabled: Bool) {
        apply(ContinuityEarbudCommand(action: "ambientDuringCall", boolValue: enabled))
    }

    func setDetectConversationsDuration(_ index: Int) {
        apply(ContinuityEarbudCommand(action: "detectConversationsDuration", intValue: index))
    }

    func setTouchLeft(_ option: GalaxyTouchOption) {
        apply(ContinuityEarbudCommand(action: "touchLeft", intValue: option.rawValue))
    }

    func setTouchRight(_ option: GalaxyTouchOption) {
        apply(ContinuityEarbudCommand(action: "touchRight", intValue: option.rawValue))
    }

    func setMute(left: Bool, right: Bool) {
        apply(ContinuityEarbudCommand(action: "mute", stringValue: "\(left ? 1 : 0),\(right ? 1 : 0)"))
    }

    func startFitTest() {
        apply(ContinuityEarbudCommand(action: "fitTest", boolValue: true))
    }

    func enterPairingMode() {
        apply(ContinuityEarbudCommand(action: "pairingMode"))
    }

    private func executeLocally(_ command: ContinuityEarbudCommand) {
        switch command.action {
        case "noise":
            let wire = command.stringValue ?? "off"
            if snapshot.vendor == .galaxy {
                galaxy.sendNoise(GalaxyNoiseControlMode.from(wire: wire))
            } else {
                sony.setNoise(SonyNoiseMode.from(wire: wire), ambientLevel: snapshot.ambientLevel)
            }
            snapshot.noiseMode = wire
        case "eq":
            let wire = command.stringValue ?? "off"
            if snapshot.vendor == .galaxy, let preset = GalaxyEqualizerPreset.from(wire: wire) {
                galaxy.sendEqualizer(preset)
            } else if let preset = SonyEqualizerPreset.from(wire: wire) {
                sony.setEqualizer(preset)
            }
            snapshot.eqPreset = wire
        case "ancHigh":
            galaxy.sendAncHigh(command.boolValue ?? true)
            snapshot.ancHigh = command.boolValue ?? true
        case "dsee":
            sony.setDsee(command.boolValue ?? false)
            snapshot.dsee = command.boolValue ?? false
        case "seamless":
            let enabled = command.boolValue ?? true
            preferredSeamless = enabled
            if snapshot.supportsSeamless {
                galaxy.sendSeamless(enabled)
                snapshot.seamless = enabled
            }
        case "detectConversations":
            galaxy.sendDetectConversations(command.boolValue ?? false)
            snapshot.detectConversations = command.boolValue ?? false
        case "ambientLevel":
            let level = command.intValue ?? 2
            if snapshot.vendor == .galaxy {
                galaxy.sendAmbientVolume(level)
            } else {
                sony.setNoise(SonyNoiseMode.from(wire: snapshot.noiseMode), ambientLevel: level)
            }
            snapshot.ambientLevel = level
        case "customEq":
            let bands = (command.stringValue ?? "")
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if snapshot.vendor == .sony {
                sony.setCustomEqualizer(clearBass: snapshot.bassGain, bands: bands)
            } else {
                galaxy.sendCustomEqualizer(bands)
            }
            snapshot.customEQBands = bands
            snapshot.eqPreset = "custom"
        case "bass":
            let value = command.intValue ?? 0
            snapshot.bassGain = value
            if snapshot.vendor == .sony {
                sony.setCustomEqualizer(clearBass: value, bands: snapshot.customEQBands)
                snapshot.eqPreset = "custom"
            }
        case "find":
            galaxy.findBuds(start: command.boolValue ?? true)
        case "gamingMode":
            galaxy.sendGamingMode(command.boolValue ?? false)
            snapshot.gamingMode = command.boolValue ?? false
        case "spatialAudio":
            galaxy.sendSpatialAudio(command.boolValue ?? false)
            snapshot.spatialAudio = command.boolValue ?? false
        case "touchpadLock":
            galaxy.sendTouchpadLock(command.boolValue ?? false)
            snapshot.touchpadLocked = command.boolValue ?? false
        case "touchLeft":
            if let opt = GalaxyTouchOption(rawValue: command.intValue ?? 2) {
                galaxy.sendTouchOptions(left: opt, right: snapshot.touchRight)
                snapshot.touchLeft = opt
            }
        case "touchRight":
            if let opt = GalaxyTouchOption(rawValue: command.intValue ?? 2) {
                galaxy.sendTouchOptions(left: snapshot.touchLeft, right: opt)
                snapshot.touchRight = opt
            }
        case "outsideDoubleTap":
            galaxy.sendOutsideDoubleTap(command.boolValue ?? false)
            snapshot.outsideDoubleTap = command.boolValue ?? false
        case "extraClearCall":
            galaxy.sendExtraClearCall(command.boolValue ?? false)
            snapshot.extraClearCall = command.boolValue ?? false
        case "passthrough":
            galaxy.sendPassthrough(command.boolValue ?? false)
            snapshot.passthrough = command.boolValue ?? false
        case "mute":
            let left = command.boolValue ?? false
            let right = (command.intValue ?? 0) != 0
            if let parts = command.stringValue?.split(separator: ",") {
                let l = parts.first.map { $0 == "1" || $0.lowercased() == "true" } ?? left
                let r = parts.dropFirst().first.map { $0 == "1" || $0.lowercased() == "true" } ?? right
                galaxy.sendMute(left: l, right: r)
                snapshot.muteLeft = l
                snapshot.muteRight = r
            } else {
                galaxy.sendMute(left: left, right: right)
                snapshot.muteLeft = left
                snapshot.muteRight = right
            }
        case "fitTest":
            galaxy.sendFitTest(command.boolValue ?? true)
            snapshot.fitTesting = command.boolValue ?? true
        case "sidetone":
            galaxy.sendSidetone(command.boolValue ?? false)
            snapshot.sidetone = command.boolValue ?? false
        case "extraHighAmbient":
            galaxy.sendExtraHighAmbient(command.boolValue ?? false)
            snapshot.extraHighAmbient = command.boolValue ?? false
        case "amplifyAmbient":
            galaxy.sendAmplifyAmbient(command.boolValue ?? false)
            snapshot.amplifyAmbient = command.boolValue ?? false
        case "speakSeamlessly":
            galaxy.sendSpeakSeamlessly(command.boolValue ?? false)
            snapshot.speakSeamlessly = command.boolValue ?? false
        case "ancOneEarbud":
            galaxy.sendAncOneEarbud(command.boolValue ?? false)
            snapshot.ancOneEarbud = command.boolValue ?? false
        case "autoSwitchAudio":
            galaxy.sendAutoSwitchAudio(command.boolValue ?? false)
            snapshot.autoSwitchAudio = command.boolValue ?? false
        case "pauseOnOneBud":
            galaxy.sendPauseOnOneBud(command.boolValue ?? false)
            snapshot.pauseOnOneBudRemoved = command.boolValue ?? false
        case "detectConversationsDuration":
            galaxy.sendDetectConversationsDuration(command.intValue ?? 1)
            snapshot.detectConversationsDuration = command.intValue ?? 1
        case "inBandRingtone":
            galaxy.sendInBandRingtone(command.boolValue ?? false)
            snapshot.inBandRingtone = command.boolValue ?? false
        case "callPathControl":
            galaxy.sendCallPathControl(command.boolValue ?? true)
            snapshot.callPathControl = command.boolValue ?? true
        case "ambientDuringCall":
            galaxy.sendAmbientDuringCall(command.boolValue ?? false)
            snapshot.ambientDuringCall = command.boolValue ?? false
        case "pairingMode":
            galaxy.sendPairingMode()
        case "requestStatus":
            galaxy.requestStatus()
            sony.requestStatus()
        default:
            break
        }
        publishIfNeeded()
    }

    private func preferredPaired() -> IOBluetoothDevice? {
        guard let all = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let matching = all.filter { EarbudVendor.detect(name: $0.name) != .none }
        return matching.first(where: { $0.isConnected() }) ?? matching.first
    }

    private func connectPreferred(address: String?, name: String, vendor: EarbudVendor) {
        switch vendor {
        case .galaxy:
            applyGalaxyCapabilities(name: name)
            let enableSeamless = snapshot.supportsSeamless && preferredSeamless
            if !galaxy.isOpen {
                seamlessReassertedThisSession = false
                galaxy.connect(address: address, name: name, enableSeamless: enableSeamless)
            }
            if enableSeamless { snapshot.seamless = true }
        case .sony:
            if !sony.isOpen { sony.connect(address: address) }
            snapshot.supportsANC = true
            snapshot.supportsEQ = true
            snapshot.supportsDSEE = sony.isV2
            snapshot.supportsFind = false
            snapshot.supportsSeamless = false
            snapshot.supportsCustomEQ = true
        case .none:
            break
        }
    }

    private func applyGalaxyCapabilities(name: String) {
        let model = GalaxyBudsModel.detect(from: name) ?? .buds4Pro
        snapshot.supportsANC = model.supportsANC
        snapshot.supportsAdaptive = model.supportsAdaptiveANC
        snapshot.supportsEQ = true
        snapshot.supportsCustomEQ = model.supportsCustomEqualizer
        snapshot.supportsSeamless = model.supportsSeamlessConnection
        snapshot.supportsFind = true
        snapshot.supportsDSEE = false
        snapshot.supportsGaming = model.supportsGamingMode
        snapshot.supportsSpatial = model.supportsSpatialAudio
        snapshot.supportsTouchLock = model.supportsTouchLock
        snapshot.supportsFitTest = model.supportsFitTest
        snapshot.supportsAmbientExtras = model.supportsAmbientExtras
        snapshot.supportsCallExtras = model.supportsCallExtras
        snapshot.supportsDetectConversations = model.supportsDetectConversations
        snapshot.supportsExtraClearCall = model.supportsExtraClearCall
        snapshot.supportsPassthrough = model.supportsPassthrough
        snapshot.supportsOutsideDoubleTap = model.supportsOutsideDoubleTap
        snapshot.vendor = .galaxy
    }

    private func applyGalaxy(_ status: GalaxyBudsStatus) {
        snapshot.vendor = .galaxy
        snapshot.connected = galaxy.isOpen
        snapshot.ownedLocally = galaxy.isOpen
        snapshot.noiseMode = status.noiseControlMode.wireName
        snapshot.ancHigh = status.ancLevelHigh
        snapshot.eqPreset = status.equalizerPreset.wireName
        snapshot.batteryLeft = status.batteryLeft
        snapshot.batteryRight = status.batteryRight
        snapshot.batteryCase = status.batteryCase
        snapshot.detectConversations = status.detectConversations
        snapshot.ambientLevel = status.ambientSoundVolume
        snapshot.customEQBands = status.customEqualizerBands
        snapshot.gamingMode = status.gamingMode
        snapshot.spatialAudio = status.spatialAudio
        snapshot.touchpadLocked = status.touchpadLocked
        snapshot.touchLeft = status.touchLeft
        snapshot.touchRight = status.touchRight
        snapshot.speakSeamlessly = status.speakSeamlessly
        snapshot.ancOneEarbud = status.ancWithOneEarbud
        snapshot.autoSwitchAudio = status.autoSwitchAudio
        snapshot.pauseOnOneBudRemoved = status.pauseOnOneBud
        snapshot.sidetone = status.sidetone
        snapshot.extraHighAmbient = status.extraHighAmbient
        snapshot.amplifyAmbient = status.amplifyAmbient
        snapshot.extraClearCall = status.extraClearCall
        snapshot.passthrough = status.passthrough
        snapshot.inBandRingtone = status.inBandRingtone
        snapshot.callPathControl = status.callPathControl
        snapshot.ambientDuringCall = status.ambientDuringCall
        snapshot.detectConversationsDuration = status.detectConversationsDuration
        snapshot.outsideDoubleTap = status.outsideDoubleTap
        snapshot.muteLeft = status.muteLeft
        snapshot.muteRight = status.muteRight
        snapshot.wearingLeft = status.isLeftWearing
        snapshot.wearingRight = status.isRightWearing
        snapshot.fitTesting = status.fitTesting
        snapshot.fitLeftGood = status.fitLeftGood
        snapshot.fitRightGood = status.fitRightGood
        applyGalaxyCapabilities(name: snapshot.name)

        if snapshot.supportsSeamless {
            if preferredSeamless {
                if !status.seamlessConnectionEnabled, !seamlessReassertedThisSession {
                    seamlessReassertedThisSession = true
                    galaxy.sendSeamless(true)
                }
                snapshot.seamless = true
            } else {
                snapshot.seamless = status.seamlessConnectionEnabled
            }
        } else {
            snapshot.seamless = false
        }
        publishIfNeeded()
    }

    private func applySony() {
        snapshot.vendor = .sony
        snapshot.connected = sony.isOpen
        snapshot.ownedLocally = sony.isOpen
        snapshot.noiseMode = sony.noiseMode.rawValue
        snapshot.eqPreset = sony.eqPreset.wireName
        snapshot.dsee = sony.dsee
        snapshot.ambientLevel = sony.ambientLevel
        snapshot.batteryMain = sony.batteryMain
        snapshot.batteryLeft = sony.batteryLeft
        snapshot.batteryRight = sony.batteryRight
        snapshot.supportsANC = true
        snapshot.supportsEQ = true
        snapshot.supportsDSEE = sony.isV2
        snapshot.supportsCustomEQ = true
        snapshot.customEQBands = sony.customBands
        snapshot.bassGain = sony.clearBass
        publishIfNeeded()
    }

    private func publishIfNeeded() {
        let payload = ContinuityEarbudStatus(snapshot: snapshot)
        guard payload != lastPublished else { return }
        lastPublished = payload
        ContinuityManager.shared.connectedPeer?.send(.earbudStatus, payload)
    }
}

extension ContinuityEarbudStatus {
    init(snapshot: EarbudControlSnapshot) {
        self.init(
            vendor: snapshot.vendor.rawValue,
            name: snapshot.name,
            address: snapshot.address,
            connected: snapshot.connected,
            ownedLocally: snapshot.ownedLocally,
            noiseMode: snapshot.noiseMode,
            ancHigh: snapshot.ancHigh,
            eqPreset: snapshot.eqPreset,
            batteryLeft: snapshot.batteryLeft,
            batteryRight: snapshot.batteryRight,
            batteryCase: snapshot.batteryCase,
            batteryMain: snapshot.batteryMain,
            dsee: snapshot.dsee,
            seamless: snapshot.seamless,
            detectConversations: snapshot.detectConversations,
            ambientLevel: snapshot.ambientLevel,
            supportsANC: snapshot.supportsANC,
            supportsAdaptive: snapshot.supportsAdaptive,
            supportsEQ: snapshot.supportsEQ,
            supportsDSEE: snapshot.supportsDSEE,
            supportsSeamless: snapshot.supportsSeamless,
            supportsFind: snapshot.supportsFind,
            supportsCustomEQ: snapshot.supportsCustomEQ,
            customEQBands: snapshot.customEQBands,
            gamingMode: snapshot.gamingMode,
            spatialAudio: snapshot.spatialAudio,
            touchpadLocked: snapshot.touchpadLocked,
            touchLeft: snapshot.touchLeft.rawValue,
            touchRight: snapshot.touchRight.rawValue,
            speakSeamlessly: snapshot.speakSeamlessly,
            ancOneEarbud: snapshot.ancOneEarbud,
            autoSwitchAudio: snapshot.autoSwitchAudio,
            pauseOnOneBudRemoved: snapshot.pauseOnOneBudRemoved,
            sidetone: snapshot.sidetone,
            extraHighAmbient: snapshot.extraHighAmbient,
            amplifyAmbient: snapshot.amplifyAmbient,
            inBandRingtone: snapshot.inBandRingtone,
            callPathControl: snapshot.callPathControl,
            ambientDuringCall: snapshot.ambientDuringCall,
            detectConversationsDuration: snapshot.detectConversationsDuration,
            outsideDoubleTap: snapshot.outsideDoubleTap,
            muteLeft: snapshot.muteLeft,
            muteRight: snapshot.muteRight,
            wearingLeft: snapshot.wearingLeft,
            wearingRight: snapshot.wearingRight,
            fitTesting: snapshot.fitTesting,
            fitLeftGood: snapshot.fitLeftGood,
            fitRightGood: snapshot.fitRightGood,
            supportsGaming: snapshot.supportsGaming,
            supportsSpatial: snapshot.supportsSpatial,
            supportsTouchLock: snapshot.supportsTouchLock,
            supportsFitTest: snapshot.supportsFitTest,
            supportsAmbientExtras: snapshot.supportsAmbientExtras,
            supportsCallExtras: snapshot.supportsCallExtras,
            supportsDetectConversations: snapshot.supportsDetectConversations,
            supportsExtraClearCall: snapshot.supportsExtraClearCall,
            supportsPassthrough: snapshot.supportsPassthrough,
            supportsOutsideDoubleTap: snapshot.supportsOutsideDoubleTap,
            extraClearCall: snapshot.extraClearCall,
            passthrough: snapshot.passthrough
        )
    }

    var snapshot: EarbudControlSnapshot {
        var snap = EarbudControlSnapshot(
            vendor: EarbudVendor(rawValue: vendor) ?? .none,
            name: name,
            address: address,
            connected: connected,
            ownedLocally: ownedLocally,
            noiseMode: noiseMode,
            ancHigh: ancHigh,
            eqPreset: eqPreset,
            batteryLeft: batteryLeft,
            batteryRight: batteryRight,
            batteryCase: batteryCase,
            batteryMain: batteryMain,
            dsee: dsee,
            seamless: seamless,
            detectConversations: detectConversations,
            ambientLevel: ambientLevel,
            supportsANC: supportsANC,
            supportsAdaptive: supportsAdaptive,
            supportsEQ: supportsEQ,
            supportsDSEE: supportsDSEE,
            supportsSeamless: supportsSeamless,
            supportsFind: supportsFind,
            supportsCustomEQ: supportsCustomEQ,
            customEQBands: customEQBands
        )
        snap.gamingMode = gamingMode
        snap.spatialAudio = spatialAudio
        snap.touchpadLocked = touchpadLocked
        snap.touchLeft = GalaxyTouchOption(rawValue: touchLeft) ?? .noiseControl
        snap.touchRight = GalaxyTouchOption(rawValue: touchRight) ?? .noiseControl
        snap.speakSeamlessly = speakSeamlessly
        snap.ancOneEarbud = ancOneEarbud
        snap.autoSwitchAudio = autoSwitchAudio
        snap.pauseOnOneBudRemoved = pauseOnOneBudRemoved
        snap.sidetone = sidetone
        snap.extraHighAmbient = extraHighAmbient
        snap.amplifyAmbient = amplifyAmbient
        snap.inBandRingtone = inBandRingtone
        snap.callPathControl = callPathControl
        snap.ambientDuringCall = ambientDuringCall
        snap.detectConversationsDuration = detectConversationsDuration
        snap.outsideDoubleTap = outsideDoubleTap
        snap.muteLeft = muteLeft
        snap.muteRight = muteRight
        snap.wearingLeft = wearingLeft
        snap.wearingRight = wearingRight
        snap.fitTesting = fitTesting
        snap.fitLeftGood = fitLeftGood
        snap.fitRightGood = fitRightGood
        snap.supportsGaming = supportsGaming
        snap.supportsSpatial = supportsSpatial
        snap.supportsTouchLock = supportsTouchLock
        snap.supportsFitTest = supportsFitTest
        snap.supportsAmbientExtras = supportsAmbientExtras
        snap.supportsCallExtras = supportsCallExtras
        snap.supportsDetectConversations = supportsDetectConversations
        snap.supportsExtraClearCall = supportsExtraClearCall
        snap.supportsPassthrough = supportsPassthrough
        snap.supportsOutsideDoubleTap = supportsOutsideDoubleTap
        snap.extraClearCall = extraClearCall
        snap.passthrough = passthrough
        return snap
    }
}