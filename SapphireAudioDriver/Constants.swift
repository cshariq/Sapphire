//
//  Constants.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-25.
//

import Foundation
import CoreAudio.AudioServerPlugIn

let kAudioServerPluginTypeUUID = CFUUIDGetConstantUUIDWithBytes(nil, 0x1A, 0x2B, 0x3C, 0x4D, 0x8E, 0x7B, 0x49, 0x1A, 0xB9, 0x85, 0xBE, 0xB9, 0x18, 0x70, 0x30, 0xDB)!

let DRIVER_BUNDLE_ID = "com.shariq.sapphire.driver"

let kDeviceManufacturer = "Shariq Charolia"
let kDeviceName = "Sapphire Audio"
let kDeviceUID = "SapphireAudioDevice_UID"

let kChannelCount: UInt32 = 2
let kSampleRate: Float64 = 44100.0

let kObjectID_PlugIn: AudioObjectID = kAudioObjectPlugInObject
let kObjectID_Device: AudioObjectID = 3
let kObjectID_Stream_Input: AudioObjectID = 4
let kObjectID_Stream_Output: AudioObjectID = 5