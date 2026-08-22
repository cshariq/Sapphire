//
//  AudioScope.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import AudioToolbox

enum AudioScope: Sendable {
    case global
    case input
    case output

    var propertyScope: AudioObjectPropertyScope {
        switch self {
        case .global: return kAudioObjectPropertyScopeGlobal
        case .input:  return kAudioObjectPropertyScopeInput
        case .output: return kAudioObjectPropertyScopeOutput
        }
    }
}