//
//  AudioDriverXPCProtocol.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import Foundation

@objc(AudioDriverXPCProtocol)
protocol AudioDriverXPCProtocol {
    func createAggregateDevice(with subDeviceUIDs: [String], reply: @escaping (Bool, String) -> Void)
}