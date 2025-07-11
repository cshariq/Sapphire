//
//  SystemAudioMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-01.
//

import Foundation
import AVFoundation
import Combine
import CoreAudio
import Accelerate 

class SystemAudioMonitor: ObservableObject {
    @Published var audioLevel: Float = 0.0

    private let engine = AVAudioEngine()
    private var isMonitoring = false
    
    init() {}

    func start() {
        guard !isMonitoring else { return }
        setupAndStartEngine()
    }

    func stop() {
        guard isMonitoring else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isMonitoring = false
    }
    
    private func setupAndStartEngine() {
        let inputNode = engine.inputNode
        
        guard let blackHoleDeviceID = findBlackHoleDeviceID() else {
            return
        }

        do {
            var deviceID = blackHoleDeviceID
            guard let audioUnit = inputNode.audioUnit else {
                print("[SystemAudioMonitor] ❌ Could not get AudioUnit for input node."); return
            }
            let error = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            if error != noErr {
                print("[SystemAudioMonitor] ❌ Failed to set input device. Error: \(error)"); return
            }
            try engine.start()
        } catch {
            print("[SystemAudioMonitor] ❌ Failed to start audio engine: \(error.localizedDescription)"); return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            let level = self?.calculateRMS(from: buffer) ?? 0.0
            DispatchQueue.main.async { self?.audioLevel = level }
        }
        
        isMonitoring = true
    }

    private func findBlackHoleDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize) == noErr else { return nil }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceIDs) == noErr else { return nil }
        
        for deviceID in deviceIDs {
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameQuery = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(deviceID, &nameQuery, 0, nil, &nameSize, &name) == noErr {
                if let deviceName = name as String?, deviceName.contains("BlackHole") {
                    return deviceID
                }
            }
        }
        return nil
    }
    
    
    private func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = vDSP_Length(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        
        var totalSquareSum: Float = 0.0
        
        for channel in 0..<Int(buffer.format.channelCount) {
            
            
            let samples = channelData[channel]
            var channelSquareSum: Float = 0.0
            
            
            vDSP_svesq(samples, 1, &channelSquareSum, frameLength)
            totalSquareSum += channelSquareSum
        }
        
        let mean = totalSquareSum / Float(frameLength * vDSP_Length(buffer.format.channelCount))
        let rawRms = sqrt(mean)
        
        
        let amplifier: Float = 5.0
        let processedRms = min(1.0, rawRms * amplifier)
        
        return processedRms
    }
}
