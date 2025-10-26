//
//  SapphireDriver.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-25.
//

import Foundation
import CoreAudio.AudioServerPlugIn
import Atomics

// MARK: - Global Driver State

var gPlugInHost: AudioServerPlugInHostRef?
var gIsRunning = false
var gRingBuffer: [Float] = Array(repeating: 0.0, count: 4096 * 2)
var gRingBufferIndex = ManagedAtomic<Int>(0)
var gHostTicksPerFrame: Float64 = 0
var gAnchorHostTime: UInt64 = 0

// MARK: - Driver Entry Point & Lifetime Management

@_cdecl("SapphireDriver_Create")
public func SapphireDriver_Create(allocator: CFAllocator!, requestedTypeUUID: CFUUID!) -> UnsafeMutableRawPointer? {
    if !CFEqual(requestedTypeUUID, kAudioServerPluginTypeUUID) { return nil }
    return UnsafeMutableRawPointer(gDriverInterfaceRef)
}

// MARK: - Driver Interface C-style implementation in Swift

var gDriverInterface = AudioServerPlugInDriverInterface(
    _reserved: nil,
    QueryInterface: QueryInterface, AddRef: AddRef, Release: Release,
    Initialize: Initialize,
    CreateDevice: { _, _, _, _ in kAudioHardwareUnsupportedOperationError },
    DestroyDevice: { _, _ in kAudioHardwareUnsupportedOperationError },
    AddDeviceClient: { _, _, _ in noErr },
    RemoveDeviceClient: { _, _, _ in noErr },
    PerformDeviceConfigurationChange: { _, _, _, _ in noErr },
    AbortDeviceConfigurationChange: { _, _, _, _ in noErr },
    HasProperty: HasProperty,
    IsPropertySettable: IsPropertySettable,
    GetPropertyDataSize: GetPropertyDataSize,
    GetPropertyData: GetPropertyData,
    SetPropertyData: { _, _, _, _, _, _, _, _ in kAudioHardwareUnsupportedOperationError },
    StartIO: StartIO,
    StopIO: StopIO,
    GetZeroTimeStamp: GetZeroTimeStamp,
    WillDoIOOperation: WillDoIOOperation,
    BeginIOOperation: { _, _, _, _, _, _ in noErr },
    DoIOOperation: DoIOOperation,
    EndIOOperation: { _, _, _, _, _, _ in noErr }
)

var gDriverInterfacePtr = withUnsafeMutablePointer(to: &gDriverInterface) { $0 }
var gDriverInterfaceRef: AudioServerPlugInDriverRef? = withUnsafeMutablePointer(to: &gDriverInterfacePtr) { $0 }

// MARK: - Core Functions

func Initialize(inDriver: AudioServerPlugInDriverRef, inHost: AudioServerPlugInHostRef) -> OSStatus {
    gPlugInHost = inHost
    var timebaseInfo = mach_timebase_info()
    mach_timebase_info(&timebaseInfo)
    let hostClockFrequency = (Float64(timebaseInfo.denom) / Float64(timebaseInfo.numer)) * 1_000_000_000.0
    gHostTicksPerFrame = hostClockFrequency / kSampleRate
    return noErr
}

func HasProperty(inDriver: AudioServerPlugInDriverRef, inObjectID: AudioObjectID, inClientProcessID: pid_t, inAddress: UnsafePointer<AudioObjectPropertyAddress>) -> DarwinBoolean {
    let address = inAddress.pointee
    switch inObjectID {
    case kObjectID_PlugIn:
        return DarwinBoolean(address.mSelector == kAudioObjectPropertyOwnedObjects || address.mSelector == kAudioPlugInPropertyDeviceList)
    case kObjectID_Device:
        let selectors: [AudioObjectPropertySelector] = [
            kAudioObjectPropertyName, kAudioDevicePropertyDeviceUID,
            kAudioObjectPropertyManufacturer, kAudioObjectPropertyOwnedObjects,
            kAudioDevicePropertyStreams, kAudioDevicePropertyNominalSampleRate,
            kAudioDevicePropertyDeviceIsRunning
        ]
        return DarwinBoolean(selectors.contains(address.mSelector))
    case kObjectID_Stream_Input, kObjectID_Stream_Output:
        let selectors: [AudioObjectPropertySelector] = [
            kAudioStreamPropertyDirection, kAudioStreamPropertyVirtualFormat, kAudioStreamPropertyIsActive
        ]
        return DarwinBoolean(selectors.contains(address.mSelector))
    default: return false
    }
}

func GetPropertyDataSize(inDriver: AudioServerPlugInDriverRef, inObjectID: AudioObjectID, inClientProcessID: pid_t, inAddress: UnsafePointer<AudioObjectPropertyAddress>, inQualifierDataSize: UInt32, inQualifierData: UnsafeRawPointer?, outDataSize: UnsafeMutablePointer<UInt32>) -> OSStatus {
    switch inAddress.pointee.mSelector {
    case kAudioObjectPropertyOwnedObjects, kAudioPlugInPropertyDeviceList, kAudioDevicePropertyStreams:
        outDataSize.pointee = UInt32(MemoryLayout<AudioObjectID>.size)
    case kAudioObjectPropertyName, kAudioDevicePropertyDeviceUID, kAudioObjectPropertyManufacturer:
        outDataSize.pointee = UInt32(MemoryLayout<CFString>.size)
    case kAudioDevicePropertyNominalSampleRate:
        outDataSize.pointee = UInt32(MemoryLayout<Float64>.size)
    case kAudioDevicePropertyDeviceIsRunning, kAudioStreamPropertyDirection, kAudioStreamPropertyIsActive:
        outDataSize.pointee = UInt32(MemoryLayout<UInt32>.size)
    case kAudioStreamPropertyVirtualFormat:
        outDataSize.pointee = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    default: return kAudioHardwareUnknownPropertyError
    }
    return noErr
}

func GetPropertyData(inDriver: AudioServerPlugInDriverRef, inObjectID: AudioObjectID, inClientProcessID: pid_t, inAddress: UnsafePointer<AudioObjectPropertyAddress>, inQualifierDataSize: UInt32, inQualifierData: UnsafeRawPointer?, inDataSize: UInt32, outDataSize: UnsafeMutablePointer<UInt32>, outData: UnsafeMutableRawPointer) -> OSStatus {
    let address = inAddress.pointee
    outDataSize.pointee = inDataSize

    switch address.mSelector {
    case kAudioObjectPropertyOwnedObjects, kAudioPlugInPropertyDeviceList:
        outData.bindMemory(to: AudioObjectID.self, capacity: 1).pointee = kObjectID_Device
    case kAudioDevicePropertyStreams:
         outData.bindMemory(to: AudioObjectID.self, capacity: 1).pointee = (address.mScope == kAudioObjectPropertyScopeInput) ? kObjectID_Stream_Input : kObjectID_Stream_Output
    case kAudioObjectPropertyName:
        outData.bindMemory(to: CFString.self, capacity: 1).pointee = kDeviceName as CFString
    case kAudioObjectPropertyManufacturer:
        outData.bindMemory(to: CFString.self, capacity: 1).pointee = kDeviceManufacturer as CFString
    case kAudioDevicePropertyDeviceUID:
        outData.bindMemory(to: CFString.self, capacity: 1).pointee = kDeviceUID as CFString
    case kAudioDevicePropertyNominalSampleRate:
        outData.bindMemory(to: Float64.self, capacity: 1).pointee = kSampleRate
    case kAudioDevicePropertyDeviceIsRunning:
        outData.bindMemory(to: UInt32.self, capacity: 1).pointee = gIsRunning ? 1 : 0
    case kAudioStreamPropertyIsActive:
        outData.bindMemory(to: UInt32.self, capacity: 1).pointee = 1
    case kAudioStreamPropertyDirection:
        outData.bindMemory(to: UInt32.self, capacity: 1).pointee = (inObjectID == kObjectID_Stream_Input) ? 1 : 0
    case kAudioStreamPropertyVirtualFormat:
        let asbd = AudioStreamBasicDescription(mSampleRate: kSampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: kChannelCount * 4, mFramesPerPacket: 1, mBytesPerFrame: kChannelCount * 4, mChannelsPerFrame: kChannelCount, mBitsPerChannel: 32, mReserved: 0)
        outData.bindMemory(to: AudioStreamBasicDescription.self, capacity: 1).pointee = asbd
    default: return kAudioHardwareUnknownPropertyError
    }
    return noErr
}

// MARK: - IO Functions

func StartIO(inDriver: AudioServerPlugInDriverRef, inDeviceObjectID: AudioObjectID, inClientID: UInt32) -> OSStatus {
    if !gIsRunning {
        gIsRunning = true
        gAnchorHostTime = mach_absolute_time()
        gRingBufferIndex.store(0, ordering: .relaxed)
    }
    return noErr
}

func StopIO(inDriver: AudioServerPlugInDriverRef, inDeviceObjectID: AudioObjectID, inClientID: UInt32) -> OSStatus {
    gIsRunning = false
    return noErr
}

func GetZeroTimeStamp(inDriver: AudioServerPlugInDriverRef, inDeviceObjectID: AudioObjectID, inClientID: UInt32, outSampleTime: UnsafeMutablePointer<Float64>, outHostTime: UnsafeMutablePointer<UInt64>, outSeed: UnsafeMutablePointer<UInt64>) -> OSStatus {
    let now = mach_absolute_time()
    let hostTicks = now - gAnchorHostTime
    let sampleTime = Float64(hostTicks) / gHostTicksPerFrame

    outSampleTime.pointee = sampleTime
    outHostTime.pointee = now
    outSeed.pointee = 1
    return noErr
}

func WillDoIOOperation(inDriver: AudioServerPlugInDriverRef, inDeviceObjectID: AudioObjectID, inClientID: UInt32, inOperationID: UInt32, outWillDo: UnsafeMutablePointer<DarwinBoolean>, outWillDoInPlace: UnsafeMutablePointer<DarwinBoolean>) -> DarwinBoolean {
    outWillDo.pointee = true
    outWillDoInPlace.pointee = true
    return true
}

func DoIOOperation(inDriver: AudioServerPlugInDriverRef, inDeviceObjectID: AudioObjectID, inStreamObjectID: AudioObjectID, inClientID: UInt32, inOperationID: UInt32, inIOBufferFrameSize: UInt32, inIOCycleInfo: UnsafePointer<AudioServerPlugInIOCycleInfo>, ioMainBuffer: UnsafeMutableRawPointer?, ioSecondaryBuffer: UnsafeMutableRawPointer?) -> OSStatus {
    let bufferSize = gRingBuffer.count
    let frameCount = Int(inIOBufferFrameSize)
    let channelCount = Int(kChannelCount)

    if inStreamObjectID == kObjectID_Stream_Output {
        let inputBuffer = UnsafeBufferPointer(start: ioMainBuffer?.assumingMemoryBound(to: Float.self), count: frameCount * channelCount)
        let startIndex = gRingBufferIndex.load(ordering: .relaxed)
        for i in 0..<inputBuffer.count {
            gRingBuffer[(startIndex + i) % bufferSize] = inputBuffer[i]
        }
    } else if inStreamObjectID == kObjectID_Stream_Input {
        let outputBuffer = UnsafeMutableBufferPointer(start: ioMainBuffer?.assumingMemoryBound(to: Float.self), count: frameCount * channelCount)
        let startIndex = gRingBufferIndex.load(ordering: .relaxed)
        for i in 0..<outputBuffer.count {
            outputBuffer[i] = gRingBuffer[(startIndex + i) % bufferSize]
        }
        gRingBufferIndex.store((startIndex + outputBuffer.count) % bufferSize, ordering: .relaxed)
    }

    return noErr
}

// MARK: - Unused Stubs (Required by the interface)
func QueryInterface(inDriver: UnsafeMutableRawPointer?, inUUID: REFIID, outInterface: UnsafeMutablePointer<LPVOID?>?) -> HRESULT { outInterface?.pointee = gDriverInterfaceRef; return noErr }
func AddRef(inDriver: UnsafeMutableRawPointer?) -> ULONG { return 1 }
func Release(inDriver: UnsafeMutableRawPointer?) -> ULONG { return 1 }
func IsPropertySettable(inDriver: AudioServerPlugInDriverRef, inObjectID: AudioObjectID, inClientProcessID: pid_t, inAddress: UnsafePointer<AudioObjectPropertyAddress>, outIsSettable: UnsafeMutablePointer<DarwinBoolean>) -> OSStatus { outIsSettable.pointee = false; return noErr }