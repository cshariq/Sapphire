//
//  WeatherViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import CoreLocation
import Combine

@MainActor
class WeatherViewModel: ObservableObject {
    static let shared = WeatherViewModel()

    private let weatherService = WeatherService.shared
    private let settingsModel = SettingsModel.shared
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var weatherData: ProcessedWeatherData?
    @Published var locationName: String = "Loading..."
    @Published var temperature: String = "—°"
    @Published var conditionDescription: String = "Fetching..."
    @Published var highLowTemp: String = "H: —° L: —°"
    @Published var feelsLike: String = "—°"
    @Published var windInfo: String = "— mph"
    @Published var humidity: String = "—%"
    @Published var uvIndex: String = "—"
    @Published var visibility: String = "—"
    @Published var pressure: String = "—"
    @Published var precipChance: String = "—%"
    @Published var iconName: String = "icloud"
    @Published var gradientColors: [Color] = [.blue.opacity(0.8), .purple.opacity(0.8)]
    @Published var hourlyForecasts: [HourlyForecastUIData] = []
    @Published var lastUpdated: Date? = nil

    @Published var isFetching = false

    var hasValidWeather: Bool { weatherData?.isValid == true }

    // MARK: - Saved Locations (BETA)

    private var selectedSavedLocation: SavedWeatherLocation? {
        guard let id = settingsModel.settings.selectedWeatherLocationID else { return nil }
        return settingsModel.settings.savedWeatherLocations.first { $0.id == id }
    }

    /// Switches which location's weather is shown. Pass nil to go back to the
    /// device's current location (the pre-existing default behavior).
    func selectLocation(id: UUID?) {
        guard settingsModel.settings.selectedWeatherLocationID != id else { return }
        settingsModel.settings.selectedWeatherLocationID = id
        weatherData = nil
        fetch()
    }

    /// Geocodes `query` and saves it as a quick-switch location. Throws if the
    /// address couldn't be resolved.
    func addSavedLocation(query: String) async throws {
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let placemark = placemarks.first, let coordinate = placemark.location?.coordinate else {
            throw WeatherServiceError.locationUnavailable
        }
        let name = [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
        let location = SavedWeatherLocation(
            name: name.isEmpty ? query : name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        settingsModel.settings.savedWeatherLocations.append(location)
    }

    func removeSavedLocation(id: UUID) {
        settingsModel.settings.savedWeatherLocations.removeAll { $0.id == id }
        if settingsModel.settings.selectedWeatherLocationID == id {
            selectLocation(id: nil)
        }
    }

    private init() {
        fetch()
        Timer.scheduledTimer(withTimeInterval: 60 * 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }

        NotificationCenter.default.publisher(for: .weatherLocationAuthorizationGranted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetch()
            }
            .store(in: &cancellables)
    }

    func fetch() {
        guard !isFetching else { return }
        isFetching = true
        if weatherData == nil {
            locationName = "Loading..."
            conditionDescription = "Locating…"
        }

        // BETA: a saved (non-current) location is selected — fetch for its
        // fixed coordinates instead of the device's live location.
        if let location = selectedSavedLocation {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let data = try await OpenMeteoService.shared.fetchWeather(for: location.clLocation, locationName: location.name)
                    self.isFetching = false
                    guard data.isValid else {
                        self.handleError(WeatherServiceError.unavailableData)
                        return
                    }
                    self.weatherData = data
                    self.updateUI(with: data)
                } catch {
                    self.isFetching = false
                    self.handleError(error)
                }
            }
            return
        }

        weatherService.fetchWeather { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isFetching = false
                switch result {
                case .success(let data):
                    guard data.isValid else {
                        self.handleError(WeatherServiceError.unavailableData)
                        return
                    }
                    self.weatherData = data
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

        self.locationName = data.locationName
        self.temperature = useCelsius ? "\(data.temperatureMetric)°" : "\(data.temperature)°"
        self.conditionDescription = data.conditionDescription
        self.highLowTemp = useCelsius ? "H: \(data.highTempMetric)° L: \(data.lowTempMetric)°" : "H: \(data.highTemp)° L: \(data.lowTemp)°"
        self.feelsLike = useCelsius ? "\(data.feelsLikeMetric)°" : "\(data.feelsLike)°"
        self.windInfo = useMetricSystem ? data.windInfoMetric : data.windInfo
        self.humidity = data.humidity
        self.uvIndex = data.uvIndex
        self.visibility = useMetricSystem ? data.visibilityMetric : data.visibility
        self.pressure = useMetricSystem ? data.pressureMetric : data.pressure
        self.precipChance = "\(data.precipChance)%"
        self.iconName = WeatherIconMapper.map(from: data.iconCode)
        self.hourlyForecasts = data.hourlyForecasts
        self.gradientColors = gradientColors(for: data.iconCode)
        self.lastUpdated = Date()
    }

    private func handleError(_ error: Error) {
        if let weatherData, weatherData.isValid {
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

        self.locationName = "Unavailable"
        self.temperature = "—°"
        self.conditionDescription = message
        self.highLowTemp = "H: —° L: —°"
        self.feelsLike = "—°"
        self.windInfo = useMetricSystem ? "— km/h" : "— mph"
        self.humidity = "—%"
        self.uvIndex = "—"
        self.visibility = "—"
        self.pressure = "—"
        self.precipChance = "—%"
        self.iconName = "icloud"
        self.gradientColors = [.gray.opacity(0.6), .black.opacity(0.8)]
        self.hourlyForecasts = []
        self.lastUpdated = nil
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