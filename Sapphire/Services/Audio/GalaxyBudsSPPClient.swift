//
//  GalaxyBudsSPPClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-21

import Foundation
import IOBluetooth

final class GalaxyBudsSPPClient: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private(set) var model: GalaxyBudsModel = .buds4Pro
    private(set) var isOpen = false
    private(set) var status = GalaxyBudsStatus()
    private(set) var address: String?
    private(set) var handedOffToPhone = false

    var onStatus: ((GalaxyBudsStatus) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private var device: IOBluetoothDevice?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.shariq.sapphire.galaxy-buds-spp")
    private var pendingEnableSeamless = true

    func connect(address: String?, name: String?, enableSeamless: Bool = true) {
        handedOffToPhone = false
        let model = GalaxyBudsModel.detect(from: name ?? "") ?? .buds4Pro
        self.model = model
        self.address = ContinuityBluetoothAddress.normalize(address)
        self.pendingEnableSeamless = enableSeamless && model.supportsSeamlessConnection
        queue.async { [weak self] in
            self?.openOnQueue(address: address, model: model)
        }
    }

    func reclaimFromPhone() {
        handedOffToPhone = false
    }

    func closeControlChannel() {
        handedOffToPhone = true
        dropLocalChannel()
    }

    func dropLocalChannel() {
        runOnMainSync {
            self.rfcommChannel?.close()
            self.rfcommChannel = nil
            self.isOpen = false
        }
        onConnectionChange?(false)
    }

    func handOffToPhone() {
        closeControlChannel()
    }

    func closeSPPOnly() {
        closeControlChannel()
    }

    func sendNoise(_ mode: GalaxyNoiseControlMode) {
        send(.init(id: .noiseControls, payload: Data([UInt8(mode.rawValue)])))
        status.noiseControlMode = mode
        notifyStatus()
    }

    func sendAncHigh(_ high: Bool) {
        send(.init(id: .noiseReductionLevel, payload: Data([high ? 1 : 0])))
        status.ancLevelHigh = high
        notifyStatus()
    }

    func sendEqualizer(_ preset: GalaxyEqualizerPreset) {
        if preset == .custom {
            sendCustomEqualizer(status.customEqualizerBands)
            return
        }
        send(.init(id: .equalizer, payload: Data([preset.wireValue])))
        status.equalizerPreset = preset
        notifyStatus()
    }

    func sendCustomEqualizer(_ bands: [Int]) {
        let clamped = (0..<9).map { i in
            Int8(clamping: bands.indices.contains(i) ? bands[i] : 0)
        }
        var payload = Data([9])
        for band in clamped { payload.append(UInt8(bitPattern: band)) }
        send(.init(id: .customEqualize, payload: payload))
        send(.init(id: .equalizer, payload: Data([7])))
        status.customEqualizerBands = clamped.map { Int($0) }
        status.equalizerPreset = .custom
        notifyStatus()
    }

    func sendSeamless(_ enabled: Bool) {
        send(.init(id: .setSeamlessConnection, payload: GalaxyBudsHandshake.seamlessPayload(enabled: enabled)))
        status.seamlessConnectionEnabled = enabled
        notifyStatus()
    }

    func yieldAudioStream() {
        send(.init(id: .logSessionOpen))
        ContinuityLog.f("galaxy buds: yielded A2DP (log session open)")
    }

    func resumeAudioStream() {
        send(.init(id: .logSessionClose))
        ContinuityLog.f("galaxy buds: resumed A2DP (log session close)")
    }

    func sendDetectConversations(_ enabled: Bool) {
        send(.init(id: .setDetectConversations, payload: Data([enabled ? 1 : 0])))
        status.detectConversations = enabled
        notifyStatus()
    }

    func sendAmbientVolume(_ volume: Int) {
        let value = UInt8(clamping: volume)
        send(.init(id: .ambientVolume, payload: Data([value])))
        status.ambientSoundVolume = Int(value)
        notifyStatus()
    }

    func findBuds(start: Bool) {
        let id: GalaxyMessageId
        if start {
            let worn = status.isLeftWearing || status.isRightWearing
            id = worn ? .findMyEarbudsOnWearingStart : .findMyEarbudsStart
        } else {
            id = .findMyEarbudsStop
        }
        send(.init(id: id))
    }

    func sendGamingMode(_ enabled: Bool) {
        send(.init(id: .gameMode, payload: Data([enabled ? 1 : 0])))
        status.gamingMode = enabled
        notifyStatus()
    }

    func sendSpatialAudio(_ enabled: Bool) {
        if enabled {
            send(.init(id: .setSpatialAudio, payload: Data([1])))
            send(.init(id: .spatialAudioControl, payload: Data([0])))
        } else {
            send(.init(id: .spatialAudioControl, payload: Data([1])))
            send(.init(id: .setSpatialAudio, payload: Data([0])))
        }
        status.spatialAudio = enabled
        notifyStatus()
    }

    func sendTouchpadLock(_ locked: Bool) {
        let payload: Data
        if model.supportsAdvancedTouchLock {
            var bytes: [UInt8] = [
                locked ? 0 : 1,
                status.singleTapOn ? 1 : 0,
                status.doubleTapOn ? 1 : 0,
                status.tripleTapOn ? 1 : 0,
                status.touchHoldOn ? 1 : 0,
            ]
            if model.supportsAdvancedTouchLockForCalls {
                bytes.append(status.doubleTapForCallOn ? 1 : 0)
                bytes.append(status.touchHoldForCallOn ? 1 : 0)
            }
            payload = Data(bytes)
        } else {
            payload = Data([locked ? 1 : 0])
        }
        send(.init(id: .lockTouchpad, payload: payload))
        status.touchpadLocked = locked
        notifyStatus()
    }

    func sendTouchOptions(left: GalaxyTouchOption, right: GalaxyTouchOption) {
        send(.init(id: .setTouchpadOption, payload: Data([UInt8(left.rawValue), UInt8(right.rawValue)])))
        status.touchLeft = left
        status.touchRight = right
        notifyStatus()
    }

    func sendTouchHoldNoise(_ options: GalaxyTouchHoldNoiseOptions) {
        send(.init(id: .setTouchAndHoldNoiseControls, payload: options.wire))
    }

    func sendOutsideDoubleTap(_ enabled: Bool) {
        send(.init(id: .outsideDoubleTap, payload: Data([enabled ? 1 : 0])))
        status.outsideDoubleTap = enabled
        notifyStatus()
    }

    func sendMute(left: Bool, right: Bool) {
        send(.init(id: .muteEarbud, payload: Data([left ? 1 : 0, right ? 1 : 0])))
        status.muteLeft = left
        status.muteRight = right
        notifyStatus()
    }

    func sendFitTest(_ start: Bool) {
        send(.init(id: .checkFitOfEarbuds, payload: Data([start ? 1 : 0])))
        status.fitTesting = start
        notifyStatus()
    }

    func sendSidetone(_ enabled: Bool) {
        send(.init(id: .setSidetone, payload: Data([enabled ? 1 : 0])))
        status.sidetone = enabled
        notifyStatus()
    }

    func sendExtraHighAmbient(_ enabled: Bool) {
        send(.init(id: .extraHighAmbient, payload: Data([enabled ? 1 : 0])))
        status.extraHighAmbient = enabled
        notifyStatus()
    }

    func sendAmplifyAmbient(_ enabled: Bool) {
        send(.init(id: .setAmplifyAmbientSound, payload: Data([enabled ? 1 : 0])))
        status.amplifyAmbient = enabled
        notifyStatus()
    }

    func sendSpeakSeamlessly(_ enabled: Bool) {
        send(.init(id: .setSpeakSeamlessly, payload: Data([enabled ? 1 : 0])))
        status.speakSeamlessly = enabled
        notifyStatus()
    }

    func sendAncOneEarbud(_ enabled: Bool) {
        send(.init(id: .setAncWithOneEarbud, payload: Data([enabled ? 1 : 0])))
        status.ancWithOneEarbud = enabled
        notifyStatus()
    }

    func sendAutoSwitchAudio(_ enabled: Bool) {
        send(.init(id: .autoSwitchAudioOutput, payload: Data([enabled ? 1 : 0])))
        status.autoSwitchAudio = enabled
        notifyStatus()
    }

    func sendPauseOnOneBud(_ enabled: Bool) {
        send(.init(id: .pauseMediaWhenOneBudRemoved, payload: Data([enabled ? 1 : 0])))
        status.pauseOnOneBud = enabled
        notifyStatus()
    }

    func sendDetectConversationsDuration(_ index: Int) {
        let value = UInt8(clamping: max(0, min(2, index)))
        send(.init(id: .setDetectConversationsDuration, payload: Data([value])))
        status.detectConversationsDuration = Int(value)
        notifyStatus()
    }

    func sendInBandRingtone(_ enabled: Bool) {
        send(.init(id: .setInBandRingtone, payload: Data([enabled ? 1 : 0])))
        status.inBandRingtone = enabled
        notifyStatus()
    }

    func sendCallPathControl(_ budsHandleCalls: Bool) {
        send(.init(id: .setCallPathControl, payload: Data([budsHandleCalls ? 0 : 1])))
        status.callPathControl = budsHandleCalls
        notifyStatus()
    }

    func sendAmbientDuringCall(_ enabled: Bool) {
        send(.init(id: .ambientDuringCallNoti, payload: Data([enabled ? 1 : 0])))
        status.ambientDuringCall = enabled
        notifyStatus()
    }

    func sendPairingMode() {
        send(.init(id: .pairingMode))
    }

    func sendPassthrough(_ enabled: Bool) {
        send(.init(id: .passThrough, payload: Data([enabled ? 1 : 0])))
        status.passthrough = enabled
        notifyStatus()
    }

    func sendExtraClearCall(_ enabled: Bool) {
        send(.init(id: .extraClearSoundCall, payload: Data([enabled ? 1 : 0])))
        status.extraClearCall = enabled
        notifyStatus()
    }

    func requestStatus() {
        send(.init(id: .extendedStatusUpdated))
    }

    private func send(_ message: GalaxySppMessage) {
        var encoded = message.encode(legacy: model.usesLegacyProtocol)
        runOnMain {
            guard let channel = self.rfcommChannel, channel.isOpen() else { return }
            let length = UInt16(encoded.count)
            encoded.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                channel.writeSync(base.assumingMemoryBound(to: UInt8.self), length: length)
            }
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func runOnMainSync(_ work: () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }

    private func openOnQueue(address: String?, model: GalaxyBudsModel) {
        guard let device = Self.pairedDevice(matching: address) else { return }
        self.device = device
        if !device.isConnected() {
            _ = device.openConnection()
            for _ in 0..<20 where !device.isConnected() {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        let uuids = [
            model.serviceUUID,
            "2e73a4ad-332d-41fc-90e2-16bef06523f2",
            "00001101-0000-1000-8000-00805f9b34fb",
            "00001102-0000-1000-8000-00805f9b34fd",
        ]
        var resolved: BluetoothRFCOMMChannelID?
        for uuid in uuids {
            if let channelId = Self.resolveChannel(device: device, uuidString: uuid) {
                ContinuityLog.f("galaxy buds: SPP channel via \(uuid)")
                resolved = channelId
                break
            }
        }
        guard let channelId = resolved else {
            ContinuityLog.fErr("galaxy buds: no SPP channel for \(address ?? "?") after UUID fallbacks")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var channel: IOBluetoothRFCOMMChannel?
            let status = device.openRFCOMMChannelAsync(&channel, withChannelID: channelId, delegate: self)
            ContinuityLog.f("galaxy buds: openRFCOMMChannelAsync → \(status)")
            self.rfcommChannel = channel
            self.pollOpen()
        }
    }

    private func pollOpen() {
        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                if self.isOpen { return }
                if self.rfcommChannel?.isOpen() == true {
                    self.markOpen()
                    return
                }
            }
        }
    }

    private func markOpen() {
        guard !isOpen else { return }
        isOpen = true
        sendInitialHandshake()
        onConnectionChange?(true)
    }

    private func sendInitialHandshake() {
        send(.init(id: .resp, payload: Data([0])))
        send(.init(id: .managerInfo, payload: GalaxyBudsHandshake.managerInfoPayload))
        send(.init(id: .updateTime, payload: GalaxyBudsHandshake.updateTimePayload()))
        if pendingEnableSeamless, model.supportsSeamlessConnection {
            sendSeamless(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.requestStatus()
            }
        }
        requestStatus()
    }

    private func notifyStatus() {
        let snapshot = status
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(snapshot)
        }
    }

    private static func pairedDevice(matching address: String?) -> IOBluetoothDevice? {
        let dashed = ContinuityBluetoothAddress.dashed(address)?.uppercased()
        if let all = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
           let match = all.first(where: { ContinuityBluetoothAddress.matches($0.addressString, address) }) {
            return match
        }
        if let dashed { return IOBluetoothDevice(addressString: dashed) }
        return nil
    }

    private static func resolveChannel(device: IOBluetoothDevice, uuidString: String) -> BluetoothRFCOMMChannelID? {
        let uuidBytes = uuidStringToBytes(uuidString)
        let uuid = IOBluetoothSDPUUID(bytes: uuidBytes, length: uuidBytes.count)
        if let channel = rfcommChannel(on: device, uuid: uuid) { return channel }
        _ = device.performSDPQuery(nil)
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.2)
            if let channel = rfcommChannel(on: device, uuid: uuid) { return channel }
        }
        return nil
    }

    private static func rfcommChannel(on device: IOBluetoothDevice, uuid: IOBluetoothSDPUUID?) -> BluetoothRFCOMMChannelID? {
        guard let uuid, let record = device.getServiceRecord(for: uuid) else { return nil }
        var channelId: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelId) == kIOReturnSuccess else { return nil }
        return channelId
    }

    private static func uuidStringToBytes(_ uuidString: String) -> [UInt8] {
        let hex = uuidString.replacingOccurrences(of: "-", with: "")
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(String(hex[index..<next]), radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        return bytes
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if error == kIOReturnSuccess || rfcommChannel?.isOpen() == true {
                self.rfcommChannel = rfcommChannel
                self.markOpen()
            }
        }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let received = Data(bytes: dataPointer, count: dataLength)
        DispatchQueue.main.async { [weak self] in
            self?.handleReceived(received)
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isOpen = false
            self.rfcommChannel = nil
            self.onConnectionChange?(false)
        }
    }

    private func handleReceived(_ data: Data) {
        receiveBuffer.append(data)
        while let message = GalaxySppMessage.extract(from: &receiveBuffer) {
            handle(message)
        }
    }

    private func handle(_ message: GalaxySppMessage) {
        guard let id = message.knownId else { return }
        switch id {
        case .extendedStatusUpdated, .statusUpdated:
            status.applyExtendedStatus(message.payload, model: model)
            notifyStatus()
        case .noiseControls, .noiseControlsUpdate:
            if let first = message.payload.first,
               let mode = GalaxyNoiseControlMode(rawValue: Int(first)) {
                status.noiseControlMode = mode
                notifyStatus()
            }
        case .checkFitResult:
            if message.payload.count >= 2 {
                status.fitLeftGood = message.payload[0] == 1
                status.fitRightGood = message.payload[1] == 1
                status.fitTesting = false
                send(.init(id: .checkFitOfEarbuds, payload: Data([0])))
                notifyStatus()
            }
        case .customEqualizeRecv:
            if message.payload.count >= 10 {
                status.customEqualizerBands = (1...9).map { Int(Int8(bitPattern: message.payload[$0])) }
                status.equalizerPreset = .custom
                notifyStatus()
            }
        default:
            break
        }
    }
}