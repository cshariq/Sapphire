//
//  WeatherViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import CoreLocation
import Combine

private struct WeatherViewState {
    var weatherData: ProcessedWeatherData?
    var locationName = "Loading..."
    var temperature = "—°"
    var conditionDescription = "Fetching..."
    var highLowTemp = "H: —° L: —°"
    var feelsLike = "—°"
    var windInfo = "— mph"
    var humidity = "—%"
    var uvIndex = "—"
    var visibility = "—"
    var pressure = "—"
    var precipChance = "—%"
    var iconName = "icloud"
    var gradientColors: [Color] = [.blue.opacity(0.8), .purple.opacity(0.8)]
    var hourlyForecasts: [HourlyForecastUIData] = []
    var lastUpdated: Date?
    var isFetching = false
}

private struct AutomaticWeatherRefreshSettings: Equatable {
    let isEnabled: Bool

    init(_ settings: Settings) {
        isEnabled = settings.weatherWidgetEnabled || settings.weatherLiveActivityEnabled
    }
}

@MainActor
class WeatherViewModel: ObservableObject {
    static let shared = WeatherViewModel()

    private let weatherService = WeatherService.shared
    private let settingsModel = SettingsModel.shared
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var automaticRefreshEnabled = false

    @Published private var state = WeatherViewState()

    var weatherData: ProcessedWeatherData? { state.weatherData }
    var locationName: String { state.locationName }
    var temperature: String { state.temperature }
    var conditionDescription: String { state.conditionDescription }
    var highLowTemp: String { state.highLowTemp }
    var feelsLike: String { state.feelsLike }
    var windInfo: String { state.windInfo }
    var humidity: String { state.humidity }
    var uvIndex: String { state.uvIndex }
    var visibility: String { state.visibility }
    var pressure: String { state.pressure }
    var precipChance: String { state.precipChance }
    var iconName: String { state.iconName }
    var gradientColors: [Color] { state.gradientColors }
    var hourlyForecasts: [HourlyForecastUIData] { state.hourlyForecasts }
    var lastUpdated: Date? { state.lastUpdated }
    var isFetching: Bool { state.isFetching }

    var hasValidWeather: Bool { weatherData?.isValid == true }

    var weatherDataPublisher: AnyPublisher<ProcessedWeatherData?, Never> {
        $state
            .map(\.weatherData)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private init() {
        setAutomaticRefreshEnabled(
            AutomaticWeatherRefreshSettings(settingsModel.settings).isEnabled
        )

        settingsModel.changes(of: AutomaticWeatherRefreshSettings.init)
            .sink { [weak self] settings in
                self?.setAutomaticRefreshEnabled(settings.isEnabled)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .weatherLocationAuthorizationGranted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.automaticRefreshEnabled == true else { return }
                self?.fetch()
            }
            .store(in: &cancellables)
    }

    func fetch() {
        guard !isFetching else { return }
        var fetchingState = state
        fetchingState.isFetching = true
        if fetchingState.weatherData == nil {
            fetchingState.locationName = "Loading..."
            fetchingState.conditionDescription = "Locating…"
        }
        state = fetchingState

        weatherService.fetchWeather { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let data):
                    guard data.isValid else {
                        self.handleError(WeatherServiceError.unavailableData)
                        return
                    }
                    self.updateUI(with: data)
                case .failure(let error):
                    self.handleError(error)
                }
            }
        }
    }

    private func updateUI(with data: ProcessedWeatherData) {
        let useCelsius = settingsModel.settings.weatherUseCelsius
        let useMetricSystem = settingsModel.settings.weatherUseMetricSystem

        state = WeatherViewState(
            weatherData: data,
            locationName: data.locationName,
            temperature: useCelsius ? "\(data.temperatureMetric)°" : "\(data.temperature)°",
            conditionDescription: data.conditionDescription,
            highLowTemp: useCelsius
                ? "H: \(data.highTempMetric)° L: \(data.lowTempMetric)°"
                : "H: \(data.highTemp)° L: \(data.lowTemp)°",
            feelsLike: useCelsius ? "\(data.feelsLikeMetric)°" : "\(data.feelsLike)°",
            windInfo: useMetricSystem ? data.windInfoMetric : data.windInfo,
            humidity: data.humidity,
            uvIndex: data.uvIndex,
            visibility: useMetricSystem ? data.visibilityMetric : data.visibility,
            pressure: useMetricSystem ? data.pressureMetric : data.pressure,
            precipChance: "\(data.precipChance)%",
            iconName: WeatherIconMapper.map(from: data.iconCode),
            gradientColors: gradientColors(for: data.iconCode),
            hourlyForecasts: data.hourlyForecasts,
            lastUpdated: Date(),
            isFetching: false
        )
    }

    private func handleError(_ error: Error) {
        if let weatherData, weatherData.isValid {
            var current = state
            current.isFetching = false
            state = current
            return
        }

        let useMetricSystem = settingsModel.settings.weatherUseMetricSystem
        let message: String
        if let weatherError = error as? WeatherServiceError {
            message = weatherError.localizedDescription
        } else if (error as NSError).domain == CLError.errorDomain {
            message = "Could not determine your location."
        } else {
            message = error.localizedDescription
        }

        state = WeatherViewState(
            weatherData: nil,
            locationName: "Unavailable",
            temperature: "—°",
            conditionDescription: message,
            highLowTemp: "H: —° L: —°",
            feelsLike: "—°",
            windInfo: useMetricSystem ? "— km/h" : "— mph",
            humidity: "—%",
            uvIndex: "—",
            visibility: "—",
            pressure: "—",
            precipChance: "—%",
            iconName: "icloud",
            gradientColors: [.gray.opacity(0.6), .black.opacity(0.8)],
            hourlyForecasts: [],
            lastUpdated: nil,
            isFetching: false
        )
    }

    private func setAutomaticRefreshEnabled(_ isEnabled: Bool) {
        guard automaticRefreshEnabled != isEnabled else { return }
        automaticRefreshEnabled = isEnabled

        if isEnabled {
            if weatherData == nil { fetch() }
            refreshTimer = Timer.scheduledCoalescing(withTimeInterval: 60 * 10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.fetch() }
            }
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func gradientColors(for iconCode: Int) -> [Color] {
        switch iconCode {
        case 31, 32, 33, 34, 36: return [Color("#4A90E2"), Color("#81C7F4")]
        case 27, 28, 29, 30: return [Color("#5D7A98"), Color("#8E9EAE")]
        case 26: return [Color("#8E9EAE"), Color("#B4C1CC")]
        case 3, 4, 37, 38, 47: return [Color("#2c3e50"), Color("#465868")]
        case 5, 6, 7, 8, 9, 10, 11, 12, 17, 18, 35, 39, 40, 45: return [Color("#5A7D9A"), Color("#829AB1")]
        case 13, 14, 15, 16, 41, 42, 43, 46: return [Color("#B4C1CC"), Color("#E0E6EB")]
        case 19, 20, 21, 22: return [Color("#95A5A6"), Color("#BDC3C7")]
        default: return [Color("#4A90E2"), Color("#81C7F4")]
        }
    }
}