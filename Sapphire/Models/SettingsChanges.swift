//
//  SettingsChanges.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import Combine
import Foundation

extension SettingsModel {
    func changes<Value: Equatable>(of value: @escaping (Settings) -> Value) -> AnyPublisher<Value, Never> {
        $settings
            .map(value)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}