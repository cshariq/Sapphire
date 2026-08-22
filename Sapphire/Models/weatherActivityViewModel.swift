//
//  weatherActivityViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-28.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class WeatherActivityViewModel: ObservableObject {
    private let source = WeatherViewModel.shared
    private var cancellables = Set<AnyCancellable>()

    var weatherData: ProcessedWeatherData? {
        source.weatherData
    }

    var hasValidWeather: Bool {
        source.hasValidWeather
    }

    init() {
        source.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func fetch() {
        source.fetch()
    }
}