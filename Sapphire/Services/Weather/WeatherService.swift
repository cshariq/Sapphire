//
//  WeatherService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import Foundation
import CoreLocation
import SwiftUI

@MainActor
final class WeatherService: NSObject, @MainActor CLLocationManagerDelegate {
    static let shared = WeatherService()

    private let locationManager = CLLocationManager()
    private var pendingCompletions: [(Result<ProcessedWeatherData, Error>) -> Void] = []

    private var cachedWeatherData: ProcessedWeatherData?
    private var lastFetchDate: Date?
    private let cacheDuration: TimeInterval = 10 * 60

    private var lastKnownLocation: CLLocation?
    private var lastLocationDate: Date?
    private let locationCacheDuration: TimeInterval = 60 * 60
    private var lastLocationFailureDate: Date?
    private let locationFailureBackoff: TimeInterval = 3 * 60

    private var isFetchingLocation = false
    private var locationTimeoutWorkItem: DispatchWorkItem?

    private var lastAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    private var weatherAPIKey: String {
        if let envKey = ProcessInfo.processInfo.environment["WEATHER_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        let homeConfig = (NSHomeDirectory() as NSString).appendingPathComponent(".sapphire/WeatherConfig.plist")
        if let dict = NSDictionary(contentsOfFile: homeConfig),
           let key = dict["APIKey"] as? String, !key.isEmpty {
            return key
        }
        return WeatherAPIKey.value
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let displayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let hourlyTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 500
    }

    public func fetchWeather(completion: @escaping (Result<ProcessedWeatherData, Error>) -> Void) {
        pendingCompletions.append(completion)

        if let lastFetch = lastFetchDate,
           let cachedData = cachedWeatherData,
           cachedData.isValid,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            finishPending(with: .success(cachedData))
            return
        }

        if !CLLocationManager.locationServicesEnabled() {
            finishPending(with: .failure(WeatherServiceError.locationDisabled))
            return
        }

        if let location = cachedLocationIfValid() {
            fetchAPIs(for: location)
            return
        }

        if let failureDate = lastLocationFailureDate,
           Date().timeIntervalSince(failureDate) < locationFailureBackoff {
            finishPending(with: .failure(WeatherServiceError.locationUnavailable))
            return
        }

        requestLocationIfAuthorized()
    }

    private func cachedLocationIfValid() -> CLLocation? {
        if let cached = lastKnownLocation,
           let date = lastLocationDate,
           cached.horizontalAccuracy >= 0,
           Date().timeIntervalSince(date) < locationCacheDuration {
            return cached
        }

        if let last = locationManager.location,
           last.horizontalAccuracy >= 0,
           Date().timeIntervalSince(last.timestamp) < locationCacheDuration {
            lastKnownLocation = last
            lastLocationDate = last.timestamp
            return last
        }

        return nil
    }

    private func requestLocationIfAuthorized() {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            startLocationUpdates()
        case .denied, .restricted:
            finishPending(with: .failure(WeatherServiceError.locationDenied))
        case .notDetermined:
            finishPending(with: .failure(WeatherServiceError.locationNotDetermined))
        @unknown default:
            finishPending(with: .failure(WeatherServiceError.unknownAuthorization))
        }
    }

    private func startLocationUpdates() {
        if isFetchingLocation { return }
        isFetchingLocation = true

        if let location = cachedLocationIfValid() {
            finishLocationSearch(with: location)
            return
        }

        locationManager.requestLocation()

        locationTimeoutWorkItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.locationManager.stopUpdatingLocation()
            self.isFetchingLocation = false
            if let location = self.cachedLocationIfValid() ?? self.locationManager.location,
               location.horizontalAccuracy >= 0 {
                self.rememberLocation(location)
                self.fetchAPIs(for: location)
            } else {
                self.lastLocationFailureDate = Date()
                self.finishPending(with: .failure(WeatherServiceError.locationUnavailable))
            }
        }
        locationTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    private func rememberLocation(_ location: CLLocation) {
        lastKnownLocation = location
        lastLocationDate = Date()
        lastLocationFailureDate = nil
    }

    private func finishLocationSearch(with location: CLLocation) {
        locationTimeoutWorkItem?.cancel()
        locationTimeoutWorkItem = nil
        locationManager.stopUpdatingLocation()
        isFetchingLocation = false
        rememberLocation(location)
        fetchAPIs(for: location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let wasAuthorized = Self.isAuthorized(status: lastAuthorizationStatus)
        lastAuthorizationStatus = status

        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            if wasAuthorized {
                break
            }
            if pendingCompletions.isEmpty {
                NotificationCenter.default.post(name: .weatherLocationAuthorizationGranted, object: nil)
            } else {
                requestLocationIfAuthorized()
            }
        case .denied, .restricted:
            guard !pendingCompletions.isEmpty else { return }
            finishPending(with: .failure(WeatherServiceError.locationDenied))
        case .notDetermined:
            break
        @unknown default:
            guard !pendingCompletions.isEmpty else { return }
            finishPending(with: .failure(WeatherServiceError.unknownAuthorization))
        }
    }

    private static func isAuthorized(status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        finishLocationSearch(with: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if Self.isLocationUnknown(error) { return }

        locationTimeoutWorkItem?.cancel()
        locationTimeoutWorkItem = nil
        locationManager.stopUpdatingLocation()
        isFetchingLocation = false

        if let last = cachedLocationIfValid() ?? manager.location, last.horizontalAccuracy >= 0 {
            rememberLocation(last)
            fetchAPIs(for: last)
            return
        }
        lastLocationFailureDate = Date()
        finishPending(with: .failure(error))
    }

    private static func isLocationUnknown(_ error: Error) -> Bool {
        if let clError = error as? CLError { return clError.code == .locationUnknown }
        let nsError = error as NSError
        return nsError.domain == kCLErrorDomain && nsError.code == 0
    }

    private func fetchAPIs(for location: CLLocation) {
        Task { @MainActor in
            let placemarks   = try? await CLGeocoder().reverseGeocodeLocation(location)
            let locationName = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Unknown Location"

            if !weatherAPIKey.isEmpty,
               let primaryData = await fetchPrimary(for: location, locationName: locationName) {
                self.cachedWeatherData = primaryData
                self.lastFetchDate     = Date()
                finishPending(with: .success(primaryData))
                return
            }

            do {
                let fallbackData = try await OpenMeteoService.shared.fetchWeather(
                    for: location,
                    locationName: locationName
                )
                self.cachedWeatherData = fallbackData
                self.lastFetchDate     = Date()
                finishPending(with: .success(fallbackData))
            } catch {
                finishPending(with: .failure(error))
            }
        }
    }

    private func fetchPrimary(
        for location: CLLocation,
        locationName: String
    ) async -> ProcessedWeatherData? {
        let lat       = location.coordinate.latitude
        let lon       = location.coordinate.longitude
        let urlString = "https://api.weather.com/v1/geocode/\(lat)/\(lon)/aggregate.json?apiKey=\(weatherAPIKey)&products=conditionsshort,fcstdaily10short,fcsthourly24short,nowlinks"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest  = 10
            config.timeoutIntervalForResource = 15
            let (data, response) = try await URLSession(configuration: config).data(from: url)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }

            let apiResponse = try JSONDecoder().decode(WeatherApiResponse.self, from: data)
            return self.process(response: apiResponse, locationName: locationName)
        } catch {
            return nil
        }
    }

    private func finishPending(with result: Result<ProcessedWeatherData, Error>) {
        locationTimeoutWorkItem?.cancel()
        locationTimeoutWorkItem = nil
        locationManager.stopUpdatingLocation()
        isFetchingLocation = false
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        completions.forEach { $0(result) }
    }

    private func process(response: WeatherApiResponse, locationName: String) -> ProcessedWeatherData? {
        let observation = response.conditionsshort?.observation
        let todayForecast = response.fcstdaily10short?.forecasts?.first

        guard observation?.imperial?.temp != nil || observation?.metric?.temp != nil else {
            return nil
        }

        let uiDailyForecasts: [DailyForecastUIData] = response.fcstdaily10short?.forecasts?.prefix(7).compactMap { forecast in
            guard let dow = forecast.dow,
                  let maxTemp = forecast.imperial?.max_temp, let minTemp = forecast.imperial?.min_temp,
                  let maxTempMetric = forecast.metric?.max_temp, let minTempMetric = forecast.metric?.min_temp else {
                return nil
            }
            return DailyForecastUIData(
                dayOfWeek: String(dow.prefix(3)).uppercased(),
                iconName: WeatherIconMapper.map(from: forecast.day?.icon_cd ?? 44),
                highTemp: maxTemp,
                lowTemp: minTemp,
                highTempMetric: maxTempMetric,
                lowTempMetric: minTempMetric
            )
        } ?? []

        let uiHourlyForecasts: [HourlyForecastUIData] = response.fcsthourly24short?.forecasts?.prefix(8).compactMap { forecast in
            guard let gmt = forecast.fcst_valid, let icon = forecast.icon_cd,
                  let tempImperial = forecast.imperial?.temp,
                  let tempMetric = forecast.metric?.temp else {
                return nil
            }
            let date = Date(timeIntervalSince1970: TimeInterval(gmt))
            return HourlyForecastUIData(
                time: Self.hourlyTimeFormatter.string(from: date).uppercased(),
                iconName: WeatherIconMapper.map(from: icon),
                temperature: "\(tempImperial)°",
                temperatureMetric: "\(tempMetric)°"
            )
        } ?? []

        return ProcessedWeatherData(
            locationName: locationName,
            temperature: observation?.imperial?.temp ?? observation?.metric?.temp ?? 0,
            temperatureMetric: observation?.metric?.temp ?? observation?.imperial?.temp ?? 0,
            highTemp: todayForecast?.imperial?.max_temp ?? observation?.imperial?.temp ?? 0,
            highTempMetric: todayForecast?.metric?.max_temp ?? observation?.metric?.temp ?? 0,
            lowTemp: todayForecast?.imperial?.min_temp ?? observation?.imperial?.temp ?? 0,
            lowTempMetric: todayForecast?.metric?.min_temp ?? observation?.metric?.temp ?? 0,
            conditionDescription: observation?.wx_phrase ?? "Unavailable",
            iconCode: observation?.wx_icon ?? 44,
            feelsLike: observation?.imperial?.feels_like ?? observation?.imperial?.temp ?? 0,
            feelsLikeMetric: observation?.metric?.feels_like ?? observation?.metric?.temp ?? 0,
            windInfo: "\(observation?.imperial?.wspd ?? 0) mph",
            windInfoMetric: "\(observation?.metric?.wspd ?? 0) km/h",
            humidity: "\(observation?.rh ?? 0)%",
            precipChance: todayForecast?.day?.pop ?? 0,
            uvIndex: "\(observation?.uv_index ?? 0) (\(observation?.uv_desc ?? "N/A"))",
            sunriseTime: formatTime(from: todayForecast?.sunrise),
            sunsetTime: formatTime(from: todayForecast?.sunset),
            visibility: observation?.vis != nil ? "\(Int(observation!.vis!)) mi" : "-- mi",
            visibilityMetric: observation?.vis != nil ? "\(Int((observation!.vis! * 1.609344).rounded())) km" : "-- km",
            pressure: observation?.pressure != nil ? "\(String(format: "%.2f", observation!.pressure! * 0.02953)) in" : "-- in",
            pressureMetric: observation?.pressure != nil ? "\(Int(observation!.pressure!)) hPa" : "-- hPa",
            dailyForecasts: uiDailyForecasts,
            hourlyForecasts: uiHourlyForecasts,
            isAvailable: true
        )
    }

    private func formatTime(from dateString: String?) -> String {
        guard let dateString = dateString, let date = Self.apiDateFormatter.date(from: dateString) else { return "--:--" }
        return Self.displayTimeFormatter.string(from: date)
    }
}

extension Notification.Name {
    static let weatherLocationAuthorizationGranted = Notification.Name("weatherLocationAuthorizationGranted")
}

enum WeatherServiceError: LocalizedError {
    case missingAPIKey
    case locationDisabled
    case locationDenied
    case locationNotDetermined
    case locationUnavailable
    case unknownAuthorization
    case invalidURL
    case unavailableData

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Weather API key is not configured."
        case .locationDisabled: return "Location services are disabled system-wide."
        case .locationDenied: return "Location access was denied. Please enable it in System Settings."
        case .locationNotDetermined: return "Grant Location access in Sapphire's Permissions settings to show weather."
        case .locationUnavailable: return "Could not determine your location."
        case .unknownAuthorization: return "Unknown location authorization status."
        case .invalidURL: return "Invalid weather API URL."
        case .unavailableData: return "Weather data is temporarily unavailable."
        }
    }
}