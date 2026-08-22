//
//  BiquadProcessable.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

protocol BiquadProcessable: AnyObject {
    var isEnabled: Bool { get }

    func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frameCount: Int)

    func updateSampleRate(_ newRate: Double)
}