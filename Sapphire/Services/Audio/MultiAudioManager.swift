//
//  MultiAudioManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import Accelerate
import Darwin

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isInput: Bool
    let isOutput: Bool
}

struct AudioDeviceSettings: Equatable {
    var volume: Double = 1.0
    var balance: Double = 0.5
    var delay: TimeInterval = 0.0
    var customEQGains: [Double] = Array(repeating: 0.0, count: 10)
}

@MainActor
class MultiAudioManager: ObservableObject {
    static let shared = MultiAudioManager()

    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var availableInputDevices: [AudioDevice] = []
    @Published var currentInputDeviceID: AudioDeviceID?
    @Published var defaultOutputDeviceID: AudioDeviceID?

    @Published var selectedOutputDeviceIDs: Set<AudioDeviceID> = [] {
        didSet {
            deviceSettings = deviceSettings.filter { selectedOutputDeviceIDs.contains($0.key) }
            reTapAllApps()
        }
    }

    @Published var deviceSettings: [AudioDeviceID: AudioDeviceSettings] = [:]
    
    // Core Engine State
    private(set) var activeTaps: [String: [String: AppTapController]] = [:] // [BundleID: [TargetDeviceUID: Tap]]
    private var isProcessMonitorStarted = false
    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var processRunningListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var monitoredProcessObjectIDs: Set<AudioObjectID> = []
    private var latestActiveBundleIDs: Set<String> = []
    private var isAuthorized = false

    private init() {
        CrashGuard.install()
        requestCapturePermissions()
        discoverDevices()
        setupDeviceListeners()
        configureProcessMonitor()
        if isAuthorized { startProcessMonitorIfNeeded() }
    }

    private func requestCapturePermissions() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        } else {
            self.isAuthorized = true
        }
    }

    // MARK: - DSP Controls (UI to Engine Bridge)
    
    func notifyAdjustmentMade(for bundleID: String) {
        reconcileRunningApps()
    }
    
    func setAppVolume(bundleID: String, volume: Float) {
        guard let taps = activeTaps[bundleID]?.values else { return }
        for tap in taps {
            tap.appVolume = volume
        }
    }

    func setAppMute(bundleID: String, isMuted: Bool) {
        guard let taps = activeTaps[bundleID]?.values else { return }
        for tap in taps {
            tap.isAppMuted = isMuted
        }
    }

    func setAppEQ(bundleID: String, gains: [Double]) {
        guard let taps = activeTaps[bundleID]?.values else { return }
        for tap in taps {
            let shouldApply = PerAppAudioController.shared.appliesEQ(for: bundleID, toDeviceUID: tap.targetDeviceUID)
            tap.updateAppEQ(gains: shouldApply ? gains : Array(repeating: 0.0, count: 10))
        }
    }

    func updateSettings(for deviceID: AudioDeviceID, settings: AudioDeviceSettings) {
        self.deviceSettings[deviceID] = settings
        guard let uid = getDeviceUID(for: deviceID) else { return }
        
        for tapMap in activeTaps.values {
            for tap in tapMap.values where tap.targetDeviceUID == uid {
                tap.deviceVolume = Float(settings.volume)
                tap.deviceBalance = Float(settings.balance)
                tap.deviceDelay = Float(settings.delay)
                tap.updateDeviceEQ(gains: settings.customEQGains)
            }
        }
        reconcileRunningApps()
    }
    
    // MARK: - Input Device Controls
    func setInputMute(_ mute: Bool, for deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muteVal: UInt32 = mute ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muteVal)
    }

    func isInputMuted(for deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muteVal: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteVal) == noErr {
            return muteVal != 0
        }
        return false
    }

    func getInputVolume(for deviceID: AudioDeviceID) -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 1
            if !AudioObjectHasProperty(deviceID, &address) { return 1.0 }
        }
        var vol: Float = 0.0
        var size = UInt32(MemoryLayout<Float>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol) == noErr {
            return vol
        }
        return 1.0
    }

    func setInputVolume(_ volume: Float, for deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) { address.mElement = 1 }
        
        var vol = volume
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
        
        if status == noErr {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Process Monitoring & Lazy Tapping
    private func configureProcessMonitor() { }

    private func startProcessMonitorIfNeeded() {
        guard !isProcessMonitorStarted else { return }
        isProcessMonitorStarted = true

        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.reconcileRunningApps()
            }
        }

        processListListenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block)
        reconcileRunningApps()
    }
    
    private func getResponsibleAppBundleID(for pid: pid_t, runningApps: [pid_t: NSRunningApplication]) -> String? {
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid") {
            let responsiblePID = unsafeBitCast(sym, to: (@convention(c) (pid_t) -> pid_t).self)(pid)
            if responsiblePID > 0 && responsiblePID != pid, let app = runningApps[responsiblePID] { return app.bundleIdentifier }
        }
        var currentPID = pid
        while currentPID > 1 {
            if let app = runningApps[currentPID], app.bundleURL?.pathExtension == "app" { return app.bundleIdentifier }
            var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.size; var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, currentPID]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let parentPID = info.kp_eproc.e_ppid
            if parentPID == currentPID { break }; currentPID = parentPID
        }
        return nil
    }
    
    private func appNeedsTap(bundleID: String, outputDeviceIDs: [AudioDeviceID]) -> Bool {
        if PerAppAudioController.shared.hasAdjustments(for: bundleID) { return true }
        if selectedOutputDeviceIDs.count > 1 { return true }
        if selectedOutputDeviceIDs.count == 1 {
            if let selectedID = selectedOutputDeviceIDs.first,
               let defaultID = defaultOutputDeviceID,
               selectedID != defaultID {
                return true
            }
        }
        for deviceID in outputDeviceIDs {
            if let settings = deviceSettings[deviceID] {
                if settings.volume != 1.0 { return true }
                if settings.balance != 0.5 { return true }
                if settings.delay > 0.0 { return true }
                if !settings.customEQGains.allSatisfy({ $0 == 0.0 }) { return true }
            }
        }
        return false
    }
    
    private func reconcileRunningApps() {
        if !isAuthorized {
            if CGPreflightScreenCaptureAccess() {
                isAuthorized = true
                startProcessMonitorIfNeeded()
            } else {
                return
            }
        }

        let outputDeviceIDs: [AudioDeviceID] = {
            if !selectedOutputDeviceIDs.isEmpty {
                return Array(selectedOutputDeviceIDs)
            }
            if let defaultID = defaultOutputDeviceID {
                return [defaultID]
            }
            return[]
        }()
        guard !outputDeviceIDs.isEmpty else { return }

        let outputUIDByDeviceID: [AudioDeviceID: String] = Dictionary(uniqueKeysWithValues: outputDeviceIDs.compactMap { deviceID -> (AudioDeviceID, String)? in
            guard let uid = getDeviceUID(for: deviceID) else { return nil }
            return (deviceID, uid)
        })
        guard !outputUIDByDeviceID.isEmpty else { return }

        var listAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &size) == noErr else { return }

        var objectIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddr, 0, nil, &size, &objectIDs)
        updateProcessRunningListeners(for: objectIDs)

        let runningAppsByPID = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { _, last in last })
        var newBundleGroups: [String: [AudioObjectID]] = [:]

        for objID in objectIDs {
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &pid) == noErr else { continue }

            var isRunning: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunning, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(objID, &runAddr, 0, nil, &runSize, &isRunning) == noErr, isRunning == 0 { continue }

            let bundleID = runningAppsByPID[pid]?.bundleIdentifier ?? getResponsibleAppBundleID(for: pid, runningApps: runningAppsByPID)
            if let bID = bundleID, !bID.hasPrefix("com.apple.audio") && bID != Bundle.main.bundleIdentifier {
                newBundleGroups[bID, default: []].append(objID)
            }
        }

        let currentBundles = Set(newBundleGroups.keys)
        if currentBundles != latestActiveBundleIDs {
            latestActiveBundleIDs = currentBundles
            NotificationCenter.default.post(name: .multiAudioActiveBundlesDidChange, object: self)
        }

        let trackedBundles = Set(activeTaps.keys)
        let activeOutputUIDs = Set(outputUIDByDeviceID.values)
        let perAppCtrl = PerAppAudioController.shared

        for bID in trackedBundles {
            guard currentBundles.contains(bID), appNeedsTap(bundleID: bID, outputDeviceIDs: outputDeviceIDs) else {
                activeTaps[bID]?.values.forEach { $0.invalidate() }
                activeTaps.removeValue(forKey: bID)
                continue
            }

            var tapMap = activeTaps[bID] ?? [:]
            for (uid, tap) in tapMap where !activeOutputUIDs.contains(uid) {
                tap.invalidate()
                tapMap.removeValue(forKey: uid)
            }
            activeTaps[bID] = tapMap.isEmpty ? nil : tapMap
        }

        for (bundleID, objIDs) in newBundleGroups {
            guard appNeedsTap(bundleID: bundleID, outputDeviceIDs: outputDeviceIDs) else { continue }
            let sortedIDs = Array(Set(objIDs)).sorted()
            var tapMap = activeTaps[bundleID] ?? [:]

            for (outputDeviceID, outputUID) in outputUIDByDeviceID {
                if let existingTap = tapMap[outputUID] {
                    if existingTap.processObjectIDs != sortedIDs {
                        existingTap.invalidate()
                        tapMap.removeValue(forKey: outputUID)
                    }
                }

                if tapMap[outputUID] == nil {
                    do {
                        // Grab actual sample rate via static helper
                        let hwSampleRate = MultiAudioManager.getNominalSampleRate(for: outputDeviceID)
                        
                        let tap = try AppTapController(bundleID: bundleID, processObjectIDs: sortedIDs, targetDeviceUID: outputUID, sampleRate: hwSampleRate)
                        
                        tap.appVolume = Float(perAppCtrl.volume(for: bundleID))
                        tap.isAppMuted = perAppCtrl.mute(for: bundleID)
                        
                        let appEQGains = perAppCtrl.eqGains(for: bundleID)
                        let shouldApplyAppEQ = perAppCtrl.appliesEQ(for: bundleID, toDeviceUID: outputUID)
                        
                        // Pass detected sample rate to EQ setup
                        tap.appEqSetup = BiquadMath.createSetup(gains: shouldApplyAppEQ ? appEQGains : Array(repeating: 0.0, count: 10), sampleRate: hwSampleRate, oldSetup: nil)
                        
                        if let devSettings = deviceSettings[outputDeviceID] {
                            tap.deviceVolume = Float(devSettings.volume)
                            tap.deviceBalance = Float(devSettings.balance)
                            tap.deviceDelay = Float(devSettings.delay)
                            tap.deviceEqSetup = BiquadMath.createSetup(gains: devSettings.customEQGains, sampleRate: hwSampleRate, oldSetup: nil)
                        }
                        
                        try tap.activate()
                        tapMap[outputUID] = tap
                    } catch {
                        print("[Engine] ❌ Failed to tap \(bundleID): \(error.localizedDescription)")
                    }
                }
            }
            activeTaps[bundleID] = tapMap.isEmpty ? nil : tapMap
        }
    }
    
    private func reTapAllApps() {
        activeTaps.values.forEach { tapMap in
            tapMap.values.forEach { $0.invalidate() }
        }
        activeTaps.removeAll()
        reconcileRunningApps()
    }
    
    // MARK: - Device Discovery & Helpers
    private func discoverDevices() {
        self.defaultOutputDeviceID = getDefaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
        
        var outputs: [AudioDevice] = []; var inputs: [AudioDevice] = []
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else { return }

        for deviceID in deviceIDs {
            guard let name = name(for: deviceID), let uid = getDeviceUID(for: deviceID), !name.hasPrefix("Sapphire-") else { continue }
            if shouldHideVirtualDevice(name: name, uid: uid) { continue }
            
            let isInput = hasChannels(for: deviceID, scope: kAudioObjectPropertyScopeInput)
            let isOutput = hasChannels(for: deviceID, scope: kAudioObjectPropertyScopeOutput)
            
            if isOutput { outputs.append(AudioDevice(id: deviceID, uid: uid, name: name, isInput: isInput, isOutput: isOutput)) }
            if isInput { inputs.append(AudioDevice(id: deviceID, uid: uid, name: name, isInput: isInput, isOutput: isOutput)) }
        }
        self.availableOutputDevices = outputs.sorted { $0.name < $1.name }; self.availableInputDevices = inputs.sorted { $0.name < $1.name }
    }

    private func setupDeviceListeners() {
        var devicesAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.discoverDevices() }
        }
        
        var defaultOutputAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.defaultOutputDeviceID = self?.getDefaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
                self?.reconcileRunningApps()
            }
        }
    }
    
    private func name(for deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size); var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name) == noErr ? name as String : nil
    }

    private func getDeviceUID(for deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size); var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid) == noErr ? uid as String : nil
    }

    private func hasChannels(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func shouldHideVirtualDevice(name: String, uid: String) -> Bool {
        let loweredName = name.lowercased()
        let loweredUID = uid.lowercased()
        let virtualMarkers = ["blackhole", "loopback", "aggregate", "multi-output", "soundflower", "background music", "airfoil", "vb-cable", "virtual"]
        return virtualMarkers.contains { loweredName.contains($0) || loweredUID.contains($0) }
    }

    private func getDefaultDevice(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var id: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size); var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr ? id : nil
    }

    private func updateProcessRunningListeners(for processObjectIDs: [AudioObjectID]) {
        let newSet = Set(processObjectIDs)
        let removed = monitoredProcessObjectIDs.subtracting(newSet)
        for objectID in removed {
            guard let block = processRunningListenerBlocks.removeValue(forKey: objectID) else { continue }
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunning, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
        }
        let added = newSet.subtracting(monitoredProcessObjectIDs)
        for objectID in added {
            var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunning, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.reconcileRunningApps() }
            }
            if AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block) == noErr { processRunningListenerBlocks[objectID] = block }
        }
        monitoredProcessObjectIDs = newSet
    }
    
    func activeAudioBundleIDs() -> Set<String> {
        if !isAuthorized {
            if CGPreflightScreenCaptureAccess() {
                isAuthorized = true
                startProcessMonitorIfNeeded()
            } else {
                return[]
            }
        }
        return latestActiveBundleIDs
    }
    
    // MARK: - Advanced Hardware Property Helpers
    
    nonisolated static func getNominalSampleRate(for deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0; var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        return (status == noErr && rate > 8000) ? rate : 48000.0
    }

    func getAvailableSampleRates(for deviceID: AudioDeviceID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges)
        return ranges.map { $0.mMinimum }.sorted()
    }

    func setNominalSampleRate(_ rate: Double, for deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newRate = rate
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Double>.size), &newRate)
    }

    func getStreamFormat(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format) == noErr else { return "Unknown" }
        
        let bitDepth = format.mBitsPerChannel
        let channels = format.mChannelsPerFrame
        return "\(channels) Ch / \(bitDepth)-bit"
    }
}

// MARK: - FineTune Process Tap Controller
class AppTapController {
    let bundleID: String, processObjectIDs: [AudioObjectID], targetDeviceUID: String
    var tapID: AudioObjectID = 0, aggregateDeviceID: AudioObjectID = 0, procID: AudioDeviceIOProcID?
    
    nonisolated(unsafe) var appVolume: Float = 1.0, isAppMuted: Bool = false, appEqSetup: vDSP_biquad_Setup?
    nonisolated(unsafe) var deviceVolume: Float = 1.0, deviceBalance: Float = 0.5, deviceDelay: Float = 0.0, deviceEqSetup: vDSP_biquad_Setup?
    
    private let appBufferL, appBufferR, devBufferL, devBufferR: UnsafeMutablePointer<Float>
    private let bufferSize = 22
    private let maxDelaySamples = 96000
    private var delayBufferL, delayBufferR: UnsafeMutablePointer<Float>
    private var delayWriteIndex = 0
    private var fadeInSamplesRemaining = 2048
    private var isInvalidated = false
    private var currentSampleRate: Double
    
    init(bundleID: String, processObjectIDs: [AudioObjectID], targetDeviceUID: String, sampleRate: Double) throws {
        self.bundleID = bundleID; self.processObjectIDs = processObjectIDs; self.targetDeviceUID = targetDeviceUID
        self.currentSampleRate = sampleRate
        
        appBufferL = .allocate(capacity: bufferSize); appBufferR = .allocate(capacity: bufferSize)
        devBufferL = .allocate(capacity: bufferSize); devBufferR = .allocate(capacity: bufferSize)
        
        // Zero all memory cleanly
        appBufferL.initialize(repeating: 0, count: bufferSize)
        appBufferR.initialize(repeating: 0, count: bufferSize)
        devBufferL.initialize(repeating: 0, count: bufferSize)
        devBufferR.initialize(repeating: 0, count: bufferSize)
        
        delayBufferL = .allocate(capacity: maxDelaySamples); delayBufferR = .allocate(capacity: maxDelaySamples)
        delayBufferL.initialize(repeating: 0, count: maxDelaySamples); delayBufferR.initialize(repeating: 0, count: maxDelaySamples)
        
        let objectIDNumbers = processObjectIDs.map { NSNumber(value: $0) }
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: objectIDNumbers as! [AudioObjectID])
        tapDesc.uuid = UUID(); tapDesc.muteBehavior = .mutedWhenTapped; tapDesc.isPrivate = true
        
        var err = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard err == noErr else { throw NSError(domain: "TapError", code: Int(err)) }
        
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sapphire-\(bundleID.split(separator: ".").last ?? "App")",
            kAudioAggregateDeviceUIDKey: UUID().uuidString, kAudioAggregateDeviceMainSubDeviceKey: targetDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: targetDeviceUID, kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: targetDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: false, kAudioSubTapUIDKey: tapDesc.uuid.uuidString]]
        ]
        
        err = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateDeviceID)
        guard err == noErr else { invalidate(); throw NSError(domain: "AggregateError", code: Int(err)) }
        CrashGuard.trackDevice(aggregateDeviceID)
    }
    
    deinit { invalidate() }
    
    func activate() throws {
        let queue = DispatchQueue(label: "com.sapphire.audiotap.\(bundleID)", qos: .userInteractive)
        var err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, queue) { [weak self] _, inData, _, outData, _ in self?.process(inData, outData) }
        guard err == noErr else { throw NSError(domain: "IOProcError", code: Int(err)) }
        err = AudioDeviceStart(aggregateDeviceID, procID!)
        guard err == noErr else { throw NSError(domain: "DeviceStartError", code: Int(err)) }
    }
    
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        if let pID = procID { AudioDeviceStop(aggregateDeviceID, pID); AudioDeviceDestroyIOProcID(aggregateDeviceID, pID) }
        if aggregateDeviceID != 0 { CrashGuard.untrackDevice(aggregateDeviceID); AudioHardwareDestroyAggregateDevice(aggregateDeviceID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        if let setup = appEqSetup { vDSP_biquad_DestroySetup(setup) }
        if let setup = deviceEqSetup { vDSP_biquad_DestroySetup(setup) }
        appBufferL.deallocate(); appBufferR.deallocate(); devBufferL.deallocate(); devBufferR.deallocate()
        delayBufferL.deallocate(); delayBufferR.deallocate()
    }
    
    func updateAppEQ(gains: [Double]) { appEqSetup = BiquadMath.createSetup(gains: gains, sampleRate: currentSampleRate, oldSetup: appEqSetup) }
    func updateDeviceEQ(gains: [Double]) { deviceEqSetup = BiquadMath.createSetup(gains: gains, sampleRate: currentSampleRate, oldSetup: deviceEqSetup) }
    
    private func process(_ inData: UnsafePointer<AudioBufferList>, _ outData: UnsafeMutablePointer<AudioBufferList>) {
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outBuffers = UnsafeMutableAudioBufferListPointer(outData)
        let finalVol = isAppMuted ? 0.0 : (appVolume * deviceVolume)
        let needsProcessing = finalVol != 1.0 || appEqSetup != nil || deviceEqSetup != nil || deviceBalance != 0.5 || deviceDelay > 0.0 || fadeInSamplesRemaining > 0
        
        for i in 0..<outBuffers.count {
            guard let outBytes = outBuffers[i].mData, let inBytes = inBuffers[i].mData else { continue }
            let totalSamples = Int(outBuffers[i].mDataByteSize) / MemoryLayout<Float>.size
            let channels = Int(outBuffers[i].mNumberChannels)
            let outPtr = outBytes.assumingMemoryBound(to: Float.self); let inPtr = inBytes.assumingMemoryBound(to: Float.self)
            
            if !needsProcessing {
                if inBytes != outBytes { memcpy(outBytes, inBytes, totalSamples * MemoryLayout<Float>.size) }
                continue
            }
            
            if finalVol == 0 { vDSP_vclr(outPtr, 1, vDSP_Length(totalSamples)) }
            else { var v = finalVol; vDSP_vsmul(inPtr, 1, &v, outPtr, 1, vDSP_Length(totalSamples)) }
            
            let frameCount = totalSamples / channels
            if let eq = appEqSetup, channels == 2 { vDSP_biquad(eq, appBufferL, outPtr, 2, outPtr, 2, vDSP_Length(frameCount)); vDSP_biquad(eq, appBufferR, outPtr.advanced(by: 1), 2, outPtr.advanced(by: 1), 2, vDSP_Length(frameCount)) }
            if let eq = deviceEqSetup, channels == 2 { vDSP_biquad(eq, devBufferL, outPtr, 2, outPtr, 2, vDSP_Length(frameCount)); vDSP_biquad(eq, devBufferR, outPtr.advanced(by: 1), 2, outPtr.advanced(by: 1), 2, vDSP_Length(frameCount)) }

            if (deviceBalance != 0.5 || deviceDelay > 0.0) && channels == 2 {
                let leftG = min(1.0, (1.0 - deviceBalance) * 2.0); let rightG = min(1.0, deviceBalance * 2.0)
                let delayFrames = min(Int(deviceDelay * Float(currentSampleRate)), maxDelaySamples - 1)
                var ptr = outPtr
                for _ in 0..<frameCount {
                    var l = ptr[0] * leftG, r = ptr[1] * rightG
                    if deviceDelay > 0.0 {
                        delayBufferL[delayWriteIndex] = l; delayBufferR[delayWriteIndex] = r
                        let readIdx = (delayWriteIndex - delayFrames + maxDelaySamples) % maxDelaySamples
                        l = delayBufferL[readIdx]; r = delayBufferR[readIdx]
                        delayWriteIndex = (delayWriteIndex + 1) % maxDelaySamples
                    }
                    ptr[0] = l; ptr[1] = r; ptr += 2
                }
            }
            if fadeInSamplesRemaining > 0 {
                let fadeCount = min(totalSamples, fadeInSamplesRemaining)
                for s in 0..<fadeCount { outPtr[s] *= Float(2048 - fadeInSamplesRemaining + s) / 2048.0 }
                fadeInSamplesRemaining -= fadeCount
            }
            SoftLimiter.processBuffer(outPtr, sampleCount: totalSamples)
        }
    }
}

// MARK: - Sharp DSP Utilities
enum BiquadMath {
    static func createSetup(gains: [Double], sampleRate: Double, oldSetup: vDSP_biquad_Setup?) -> vDSP_biquad_Setup? {
        if let old = oldSetup { DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { vDSP_biquad_DestroySetup(old) } }
        if gains.allSatisfy({ $0 == 0.0 }) { return nil }
        
        let freqs: [Double] = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        let Q = 1.5
        var coeffs: [Double] = []
        
        // REPLACED: Instead of reducing volume by the absolute MAX boost (which kills volume),
        // we use a more moderate gain compensation of only 60% of the max boost.
        // This keeps the sound "sharp" but prevents the 50% volume drop.
        let maxBoost = gains.max() ?? 0.0
        let compensation = maxBoost > 0 ? pow(10.0, -(maxBoost * 0.6) / 20.0) : 1.0
        
        for i in 0..<10 {
            let gain = gains[i]
            let A = pow(10.0, gain / 40.0)
            let omega = 2.0 * .pi * freqs[i] / sampleRate
            let sn = sin(omega)
            let cs = cos(omega)
            let alpha = sn / (2.0 * Q)
            
            var b0 = 1.0 + alpha * A
            var b1 = -2.0 * cs
            var b2 = 1.0 - alpha * A
            let a0 = 1.0 + alpha / A
            let a1 = -2.0 * cs
            let a2 = 1.0 - alpha / A
            
            // Apply compensation to the first filter block
            if i == 0 {
                b0 *= compensation
                b1 *= compensation
                b2 *= compensation
            }
            
            coeffs.append(contentsOf:[b0/a0, b1/a0, b2/a0, a1/a0, a2/a0])
        }
        return coeffs.withUnsafeBufferPointer { vDSP_biquad_CreateSetup($0.baseAddress!, vDSP_Length(10)) }
    }
}

enum SoftLimiter {
    @inline(__always) static func processBuffer(_ buffer: UnsafeMutablePointer<Float>, sampleCount: Int) {
        // Fast, Native Hard Clip that doesn't apply "fuzz" distortion curves.
        var low: Float = -1.0
        var high: Float = 1.0
        vDSP_vclip(buffer, 1, &low, &high, buffer, 1, vDSP_Length(sampleCount))
    }
}

extension Notification.Name {
    static let multiAudioActiveBundlesDidChange = Notification.Name("multiAudioActiveBundlesDidChange")
    static let perAppAudioSettingsDidChange = Notification.Name("perAppAudioSettingsDidChange")
}

enum CrashGuard {
    private static var devices: [AudioObjectID] = []
    private static let lock = NSLock()
    static func install() { signal(SIGABRT, { CrashGuard.handleSignal($0) }); signal(SIGSEGV, { CrashGuard.handleSignal($0) }) }
    static func handleSignal(_ sig: Int32) { devices.forEach { AudioHardwareDestroyAggregateDevice($0) }; signal(sig, SIG_DFL); raise(sig) }
    static func trackDevice(_ id: AudioObjectID) { lock.lock(); devices.append(id); lock.unlock() }
    static func untrackDevice(_ id: AudioObjectID) { lock.lock(); devices.removeAll { $0 == id }; lock.unlock() }
}
