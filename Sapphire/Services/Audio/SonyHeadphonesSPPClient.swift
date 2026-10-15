//
//  SonyHeadphonesSPPClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-20

import Foundation
import IOBluetooth

final class SonyHeadphonesSPPClient: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private(set) var isOpen = false
    private(set) var isV2 = false
    private(set) var address: String?
    private(set) var noiseMode: SonyNoiseMode = .off
    private(set) var eqPreset: SonyEqualizerPreset = .off
    private(set) var dsee = false
    private(set) var ambientLevel = 20
    private(set) var handedOffToPhone = false
    private(set) var customBands: [Int] = Array(repeating: 0, count: 5)
    private(set) var clearBass = 0
    private(set) var batteryMain = 0
    private(set) var batteryLeft = 0
    private(set) var batteryRight = 0

    var onChange: (() -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private var device: IOBluetoothDevice?
    private var receiveBuffer = Data()
    private var sequence: UInt8 = 0
    private let queue = DispatchQueue(label: "com.shariq.sapphire.sony-mdr-spp")

    func connect(address: String?) {
        handedOffToPhone = false
        self.address = ContinuityBluetoothAddress.normalize(address)
        queue.async { [weak self] in
            self?.openOnQueue(address: address)
        }
    }

    func close() {
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

    func reclaimFromPhone() {
        handedOffToPhone = false
    }

    func setNoise(_ mode: SonyNoiseMode, ambientLevel: Int = 20) {
        self.noiseMode = mode
        self.ambientLevel = ambientLevel
        let payload = isV2
            ? SonyMdrCommands.setNoiseV2(mode: mode, ambientLevel: ambientLevel, focusOnVoice: false)
            : SonyMdrCommands.setNoiseV1(mode: mode, ambientLevel: ambientLevel, focusOnVoice: false)
        sendPayload(payload)
        notify()
    }

    func setEqualizer(_ preset: SonyEqualizerPreset) {
        eqPreset = preset
        let payload = isV2
            ? SonyMdrCommands.setEqualizerPresetV2(preset)
            : SonyMdrCommands.setEqualizerPresetV1(preset)
        sendPayload(payload)
        notify()
    }

    func setCustomEqualizer(clearBass: Int, bands: [Int]) {
        self.clearBass = max(-10, min(10, clearBass))
        customBands = (0..<5).map { i in max(-10, min(10, bands.indices.contains(i) ? bands[i] : 0)) }
        eqPreset = .manual
        sendPayload(SonyMdrCommands.setEqualizerCustom(isV2: isV2, clearBass: self.clearBass, bands: customBands))
        notify()
    }

    func setDsee(_ enabled: Bool) {
        guard isV2 else { return }
        dsee = enabled
        sendPayload(SonyMdrCommands.setDsee(enabled))
        notify()
    }

    func requestStatus() {
        if isV2 {
            sendPayload(SonyMdrCommands.getNoiseV2())
            sendPayload(SonyMdrCommands.getEqualizerV2())
            sendPayload(SonyMdrCommands.getDsee())
            sendPayload(SonyMdrCommands.getBatteryV2Main())
            sendPayload(SonyMdrCommands.getBatteryV2Dual())
        } else {
            sendPayload(SonyMdrCommands.getBatteryV1())
        }
    }

    private func sendPayload(_ payload: Data) {
        runOnMain { [weak self] in
            guard let self, let channel = self.rfcommChannel, channel.isOpen() else { return }
            let frame = SonyMdrFrame(type: SonyMdrDataType.dataMdr.rawValue, sequence: self.sequence, payload: payload)
            self.sequence &+= 1
            var encoded = frame.encode()
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

    private func notify() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    private func openOnQueue(address: String?) {
        guard let device = Self.pairedDevice(matching: address) else { return }
        self.device = device
        if !device.isConnected() {
            _ = device.openConnection()
        }
        let v1 = Self.resolveChannel(device: device, uuidString: SonyMdrFrame.uuidV1)
        let v2 = v1 == nil ? Self.resolveChannel(device: device, uuidString: SonyMdrFrame.uuidV2) : nil
        guard let channelId = v1 ?? v2 else {
            ContinuityLog.fErr("sony headphones: no MDR channel for \(address ?? "?")")
            return
        }
        isV2 = v1 == nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var channel: IOBluetoothRFCOMMChannel?
            _ = device.openRFCOMMChannelAsync(&channel, withChannelID: channelId, delegate: self)
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
        requestStatus()
        onConnectionChange?(true)
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
        let hex = uuidString.replacingOccurrences(of: "-", with: "")
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(String(hex[index..<next]), radix: 16) { bytes.append(byte) }
            index = next
        }
        let uuid = IOBluetoothSDPUUID(bytes: bytes, length: bytes.count)
        if let record = device.getServiceRecord(for: uuid) {
            var channelId: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channelId) == kIOReturnSuccess { return channelId }
        }
        _ = device.performSDPQuery(nil)
        for _ in 0..<25 {
            Thread.sleep(forTimeInterval: 0.2)
            if let record = device.getServiceRecord(for: uuid) {
                var channelId: BluetoothRFCOMMChannelID = 0
                if record.getRFCOMMChannelID(&channelId) == kIOReturnSuccess { return channelId }
            }
        }
        return nil
    }

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
        while let frame = SonyMdrFrame.extract(from: &receiveBuffer) {
            handle(frame)
        }
    }

    private func handle(_ frame: SonyMdrFrame) {
        guard frame.type == SonyMdrDataType.dataMdr.rawValue, let opcode = frame.payload.first else { return }
        let payload = frame.payload
        switch opcode {
        case 0x67 where payload.count >= 7 && payload[1] == 0x17:
            let effect = payload[3]
            let setting = payload.count > 4 ? payload[4] : 0
            if effect == 0 { noiseMode = .off }
            else if setting == 1 { noiseMode = .ambient }
            else { noiseMode = .anc }
            notify()
        case 0x57 where payload.count >= 3:
            eqPreset = SonyEqualizerPreset(rawValue: Int(payload[2])) ?? (payload[2] == 0xA0 ? .manual : .off)
            if payload.count >= 10 {
                clearBass = Int(payload[4]) - 10
                customBands = (0..<5).map { Int(payload[5 + $0]) - 10 }
            }
            notify()
        case 0xE7 where payload.count >= 3:
            dsee = payload[2] != 0
            notify()
        case 0x23 where isV2 && payload.count >= 4:
            if payload[1] == 0x00 {
                batteryMain = Int(payload[2])
            } else if payload[1] == 0x09, payload.count >= 6 {
                batteryLeft = Int(payload[2])
                batteryRight = Int(payload[4])
            }
            notify()
        case 0x11 where !isV2 && payload.count >= 4:
            batteryMain = Int(payload[2])
            notify()
        default:
            break
        }
    }
}