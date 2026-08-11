//
//  OpenMeteoService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import CoreLocation

// MARK: - Response Models

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather?
    let hourly: HourlyWeather?
    let daily: DailyWeather?

    struct CurrentWeather: Decodable {
        let time: String?
        let temperature2m: Double?
        let apparentTemperature: Double?
        let relativeHumidity2m: Int?
        let windspeed10m: Double?
        let weathercode: Int?
        let isDay: Int?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m         = "temperature_2m"
            case apparentTemperature   = "apparent_temperature"
            case relativeHumidity2m    = "relative_humidity_2m"
            case windspeed10m          = "windspeed_10m"
            case weathercode
            case isDay                 = "is_day"
        }
    }

    struct HourlyWeather: Decodable {
        let time: [String]?
        let temperature2m: [Double?]?
        let weathercode: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m  = "temperature_2m"
            case weathercode
        }
    }

    struct DailyWeather: Decodable {
        let time: [String]?
        let weathercode: [Int?]?
        let temperature2mMax: [Double?]?
        let temperature2mMin: [Double?]?
        let precipitationProbabilityMax: [Int?]?
        let sunrise: [String]?
        let sunset: [String]?
        let uvIndexMax: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weathercode
            case temperature2mMax              = "temperature_2m_max"
            case temperature2mMin              = "temperature_2m_min"
            case precipitationProbabilityMax   = "precipitation_probability_max"
            case sunrise
            case sunset
            case uvIndexMax                    = "uv_index_max"
        }
    }
}

// MARK: - WMO Weather Code Mapping

private func wmcCodeToTWCIcon(_ wmo: Int, isDay: Bool) -> Int {
    switch wmo {
    case 0:          return isDay ? 32 : 31
    case 1:          return isDay ? 34 : 33
    case 2:          return isDay ? 30 : 29
    case 3:          return 26
    case 45, 48:     return 20
    case 51, 53:     return 9
    case 55:         return 9
    case 56, 57:     return 8
    case 61:         return 11
    case 63:         return 12
    case 65:         return 40
    case 66, 67:     return 6
    case 71:         return 13
    case 73:         return 14
    case 75:         return 16
    case 77:         return 16
    case 80:         return 39
    case 81:         return 11
    case 82:         return 12
    case 85, 86:     return 42
    case 95:         return isDay ? 37 : 47
    case 96, 99:     return 3
    default:         return 44
    }
}

private func wmcDescription(_ wmo: Int) -> String {
    switch wmo {
    case 0:      return "Clear"
    case 1:      return "Mostly Clear"
    case 2:      return "Partly Cloudy"
    case 3:      return "Overcast"
    case 45:     return "Foggy"
    case 48:     return "Icy Fog"
    case 51:     return "Light Drizzle"
    case 53:     return "Drizzle"
    case 55:     return "Heavy Drizzle"
    case 56, 57: return "Freezing Drizzle"
    case 61:     return "Light Rain"
    case 63:     return "Rain"
    case 65:     return "Heavy Rain"
    case 66, 67: return "Freezing Rain"
    case 71:     return "Light Snow"
    case 73:     return "Snow"
    case 75:     return "Heavy Snow"
    case 77:     return "Snow Grains"
    case 80:     return "Light Showers"
    case 81:     return "Showers"
    case 82:     return "Heavy Showers"
    case 85, 86: return "Snow Showers"
    case 95:     return "Thunderstorm"
    case 96, 99: return "Thunderstorm w/ Hail"
    default:     return "Unknown"
    }
}

// MARK: - Service

enum OpenMeteoServiceError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "Invalid Open-Meteo URL."
        case .networkError(let e):     return e.localizedDescription
        case .decodingError(let e):    return "Failed to parse Open-Meteo response: \(e.localizedDescription)"
        case .noData:                  return "No data from Open-Meteo."
        }
    }
}

final class OpenMeteoService {

    static let shared = OpenMeteoService()
    private init() {}

    private static let localISOFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static let displayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let hourlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f
    }()

    private static let dayOfWeekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    func fetchWeather(
        for location: CLLocation,
        locationName: String
    ) async throws -> ProcessedWeatherData {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude",              value: String(format: "%.4f", lat)),
            .init(name: "longitude",             value: String(format: "%.4f", lon)),
            .init(name: "current",               value: "temperature_2m,apparent_temperature,relative_humidity_2m,windspeed_10m,weathercode,is_day"),
            .init(name: "hourly",                value: "temperature_2m,weathercode"),
            .init(name: "daily",                 value: "weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"),
            .init(name: "temperature_unit",      value: "celsius"),
            .init(name: "windspeed_unit",        value: "mph"),
            .init(name: "precipitation_unit",    value: "mm"),
            .init(name: "timezone",              value: "auto"),
            .init(name: "forecast_days",         value: "7"),
            .init(name: "hourly_steps",          value: "1"),
            .init(name: "forecast_hours",        value: "8"),
        ]

        guard let url = components.url else { throw OpenMeteoServiceError.invalidURL }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 10
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)

        let data: Data
        do {
            let (d, _) = try await session.data(from: url)
            data = d
        } catch {
            throw OpenMeteoServiceError.networkError(error)
        }

        let response: OpenMeteoResponse
        do {
            response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw OpenMeteoServiceError.decodingError(error)
        }

        return try process(response: response, locationName: locationName)
    }

    // MARK: - Processing

    private func process(
        response: OpenMeteoResponse,
        locationName: String
    ) throws -> ProcessedWeatherData {
        guard let current = response.current,
              let tempC = current.temperature2m else {
            throw OpenMeteoServiceError.noData
        }

        let isDay      = (current.isDay ?? 1) == 1
        let wmoCode    = current.weathercode ?? 0
        let twcIcon    = wmcCodeToTWCIcon(wmoCode, isDay: isDay)
        let feelsC     = current.apparentTemperature ?? tempC
        let humidity   = current.relativeHumidity2m ?? 0
        let windMph    = Int((current.windspeed10m ?? 0).rounded())

        let tempF    = celsiusToFahrenheit(tempC)
        let feelsF   = celsiusToFahrenheit(feelsC)

        let daily      = response.daily
        let todayMaxC  = daily?.temperature2mMax?.first.flatMap { $0 } ?? tempC
        let todayMinC  = daily?.temperature2mMin?.first.flatMap { $0 } ?? tempC
        let todayMaxF  = celsiusToFahrenheit(todayMaxC)
        let todayMinF  = celsiusToFahrenheit(todayMinC)
        let precipPct  = daily?.precipitationProbabilityMax?.first.flatMap { $0 } ?? 0
        let uvRaw      = daily?.uvIndexMax?.first.flatMap { $0 } ?? 0
        let uvDesc     = uvDescription(uvRaw)

        let sunriseStr = formatISOTime(daily?.sunrise?.first ?? "")
        let sunsetStr  = formatISOTime(daily?.sunset?.first ?? "")

        let dailyForecasts: [DailyForecastUIData] = buildDailyForecasts(from: daily)

        let hourlyForecasts: [HourlyForecastUIData] = buildHourlyForecasts(from: response.hourly, isDay: isDay)

        return ProcessedWeatherData(
            locationName:       locationName,
            temperature:        tempF,
            temperatureMetric:  Int(tempC.rounded()),
            highTemp:           todayMaxF,
            highTempMetric:     Int(todayMaxC.rounded()),
            lowTemp:            todayMinF,
            lowTempMetric:      Int(todayMinC.rounded()),
            conditionDescription: wmcDescription(wmoCode),
            iconCode:           twcIcon,
            feelsLike:          feelsF,
            feelsLikeMetric:    Int(feelsC.rounded()),
            windInfo:           "\(windMph) mph",
            humidity:           "\(humidity)%",
            precipChance:       precipPct,
            uvIndex:            "\(Int(uvRaw.rounded())) (\(uvDesc))",
            sunriseTime:        sunriseStr,
            sunsetTime:         sunsetStr,
            visibility:         "-- mi",
            pressure:           "-- in",
            dailyForecasts:     dailyForecasts,
            hourlyForecasts:    hourlyForecasts,
            isAvailable:        true
        )
    }

    // MARK: - Helpers

    private func celsiusToFahrenheit(_ c: Double) -> Int {
        Int((c * 9.0 / 5.0 + 32).rounded())
    }

    private func uvDescription(_ uv: Double) -> String {
        switch uv {
        case ..<3:   return "Low"
        case ..<6:   return "Moderate"
        case ..<8:   return "High"
        case ..<11:  return "Very High"
        default:     return "Extreme"
        }
    }

    private func formatISOTime(_ iso: String) -> String {
        guard !iso.isEmpty else { return "--:--" }
        let normalized = iso.count >= 16 ? String(iso.prefix(16)) : iso
        if let date = Self.localISOFormatter.date(from: normalized) {
            return Self.displayTimeFormatter.string(from: date)
        }
        return "--:--"
    }

    private func buildDailyForecasts(
        from daily: OpenMeteoResponse.DailyWeather?
    ) -> [DailyForecastUIData] {
        guard let daily, let times = daily.time else { return [] }
        var results: [DailyForecastUIData] = []
        for i in 1..<min(times.count, 7) {
            let maxC = daily.temperature2mMax?[i].flatMap { $0 } ?? 0
            let minC = daily.temperature2mMin?[i].flatMap { $0 } ?? 0
            let wmo  = daily.weathercode?[i].flatMap { $0 } ?? 0
            let dow  = dowAbbreviation(from: times[i])
            results.append(DailyForecastUIData(
                dayOfWeek:      dow,
                iconName:       WeatherIconMapper.map(from: wmcCodeToTWCIcon(wmo, isDay: true)),
                highTemp:       celsiusToFahrenheit(maxC),
                lowTemp:        celsiusToFahrenheit(minC),
                highTempMetric: Int(maxC.rounded()),
                lowTempMetric:  Int(minC.rounded())
            ))
        }
        return results
    }

    private func buildHourlyForecasts(
        from hourly: OpenMeteoResponse.HourlyWeather?,
        isDay: Bool
    ) -> [HourlyForecastUIData] {
        guard let hourly, let times = hourly.time else { return [] }
        let startOfCurrentHour = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
        var results: [HourlyForecastUIData] = []

        for i in 0..<times.count {
            let timeStr = times[i].count >= 16 ? String(times[i].prefix(16)) : times[i]
            guard let date = Self.localISOFormatter.date(from: timeStr), date >= startOfCurrentHour else { continue }
            let tempC = hourly.temperature2m?[i].flatMap { $0 } ?? 0
            let wmo   = hourly.weathercode?[i].flatMap { $0 } ?? 0
            results.append(HourlyForecastUIData(
                time:             Self.hourlyFormatter.string(from: date).uppercased(),
                iconName:         WeatherIconMapper.map(from: wmcCodeToTWCIcon(wmo, isDay: isDay)),
                temperature:      "\(celsiusToFahrenheit(tempC))°",
                temperatureMetric: "\(Int(tempC.rounded()))°"
            ))
            if results.count == 8 { break }
        }
        return results
    }

    private func dowAbbreviation(from isoDate: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: isoDate) else { return "---" }
        return Self.dayOfWeekFormatter.string(from: date).uppercased()
    }
}