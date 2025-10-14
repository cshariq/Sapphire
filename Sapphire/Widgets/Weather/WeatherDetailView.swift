//
//  WeatherDetailView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI

struct RelativeTimeView: View {
    let date: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60.0)) { context in
            if let validDate = date {
                Text(formattedString(from: validDate, to: context.date))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }

    private func formattedString(from: Date, to: Date) -> String {
        let interval = to.timeIntervalSince(from)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "Updated just now"
        } else if minutes < 60 {
            return "Updated \(minutes)m ago"
        } else {
            let hours = minutes / 60
            return "Updated \(hours)h ago"
        }
    }
}

struct WeatherPlayerView: View {
    @ObservedObject private var viewModel = WeatherViewModel.shared

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                currentWeatherAndDetailsSection
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                hourlyForecastSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
            }

            HStack(spacing: 8) {
                Spacer()
                RelativeTimeView(date: viewModel.lastUpdated)

                Button(action: {
                    viewModel.fetch()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
                .padding(6)
                .background(.black.opacity(0.2))
                .clipShape(Circle())
                .rotationEffect(.degrees(viewModel.isFetching ? 360 : 0))
                .animation(viewModel.isFetching ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isFetching)
                .disabled(viewModel.isFetching)
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .frame(width: 560, height: 240)
        .animation(.spring(response: 0.6, dampingFraction: 1, blendDuration: 0.2), value: viewModel.temperature)
        .animation(.easeInOut(duration: 0.8), value: viewModel.gradientColors.first)
    }

    private var currentWeatherAndDetailsSection: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(systemName: viewModel.iconName)
                .font(.system(size: 88, weight: .thin))
                .symbolRenderingMode(.multicolor)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .frame(width: 100, height: 100)
                .padding(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.locationName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                Text(viewModel.temperature)
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(viewModel.conditionDescription.capitalized)
                    .font(.title3).fontWeight(.medium)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(viewModel.highLowTemp)
                    }
                    .font(.callout).fontWeight(.medium)
                    .opacity(0.8)

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .font(.caption)
                            Text("Feels: \(viewModel.feelsLike)")
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "wind")
                                .font(.caption)
                            Text("Wind: \(viewModel.windInfo)")
                        }
                    }
                    .font(.subheadline).fontWeight(.regular)
                    .opacity(0.7)
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var hourlyForecastSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOURLY FORECAST")
                .font(.caption2.weight(.bold))
                .opacity(0.6)
                .kerning(0.5)
                .padding(.horizontal, 12)

            HStack(spacing: 18) {
                ForEach(viewModel.hourlyForecasts) { forecast in
                    HourlyForecastCell(forecast: forecast)
                }
            }
        }
        .frame(height: 80)
    }
}

private struct HourlyForecastCell: View {
    let forecast: HourlyForecastUIData
    @EnvironmentObject private var settings: SettingsModel

    var body: some View {
        VStack(spacing: 4) {
            Text(forecast.time)
                .font(.caption2).fontWeight(.medium)
                .opacity(0.8)
            Image(systemName: forecast.iconName)
                .font(.title2).symbolRenderingMode(.multicolor)
                .frame(height: 28)
            Text(settings.settings.weatherUseCelsius ? forecast.temperatureMetric : forecast.temperature)
                .font(.subheadline).fontWeight(.semibold)
        }
        .frame(width: 50)
    }
}