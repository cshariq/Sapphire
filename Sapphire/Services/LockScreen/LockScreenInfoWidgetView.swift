//
//  LockScreenInfoWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-11.
//

import SwiftUI
import EventKit

struct TransparentEffect: ViewModifier {
    @EnvironmentObject var settings: SettingsModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if settings.settings.lockScreenLiquidGlassLook {
            content
                .opacity(0.6)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
        } else {
            content
        }
    }
}

struct LockScreenInfoWidgetView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var weatherVM: WeatherActivityViewModel
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var musicWidget: MusicManager
    @EnvironmentObject var focusModeManager: FocusModeManager
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @EnvironmentObject var batteryMonitor: BatteryMonitor
    @StateObject private var batteryEstimator = BatteryEstimator.shared

    private let fadeTransition = AnyTransition.opacity

    private var animationValue: String {
        let widgetTypes = settings.settings.lockScreenWidgets.map { $0.rawValue }.joined(separator: ",")
        let musicState = musicWidget.isPlaying ? "playing" : "stopped"
        let eventId = calendarService.upcomingEvents.first?.eventIdentifier ?? "none"
        let focusState = focusModeManager.currentStatus.isActive ? "on" : "off"
        let bluetoothId = bluetoothManager.lastEvent.map { "\($0.name)-\($0.batteryLevel ?? 0)" } ?? "none"

        return "\(widgetTypes)-\(musicState)-\(eventId)-\(focusState)-\(bluetoothId)"
    }

    var body: some View {
        HStack(spacing: LockScreenConfiguration.widgetSpacing) {
            ForEach(settings.settings.lockScreenWidgets, id: \.self) { widgetType in
                switch widgetType {
                case .weather:
                    WeatherInfoView()
                case .calendar:
                    CalendarInfoView()
                case .music:
                    MusicInfoView()
                case .focus:
                    FocusInfoView()
                case .bluetooth:
                    BluetoothInfoView()
                case .battery:
                    BatteryInfoView()
                case .none:
                    EmptyView()
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: animationValue)
        .padding(.horizontal, LockScreenConfiguration.infoWidgetContainerHorizontalPadding)
        .fixedSize()
    }

    @ViewBuilder
    private func WeatherInfoView() -> some View {
        if let weather = weatherVM.weatherData {
            HStack(spacing: LockScreenConfiguration.infoWidgetInternalHSpacing) {
                ForEach(settings.settings.lockScreenWeatherInfo, id: \.self) { infoType in
                    weatherItemView(for: infoType, with: weather)
                }
            }
            .foregroundColor(.white)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        }
    }

    @ViewBuilder
    private func weatherItemView(for type: WeatherInfoType, with data: ProcessedWeatherData) -> some View {
        let textFont = Font.system(size: LockScreenConfiguration.infoWidgetMediumFontSize, weight: .medium)

        switch type {
        case .temperature:
            Image(systemName: WeatherIconMapper.map(from: data.iconCode))
                .font(.title2)
                .symbolRenderingMode(.multicolor)
            Text("\(settings.settings.weatherUseCelsius ? data.temperatureMetric : data.temperature)°")
                .font(.system(size: LockScreenConfiguration.infoWidgetLargeFontSize, weight: .bold, design: .rounded))
        case .condition:
            Image(systemName: WeatherIconMapper.map(from: data.iconCode))
                .font(.title2)
                .symbolRenderingMode(.multicolor)
        case .wind:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "wind"); Text(data.windInfo) }.font(textFont)
        case .humidity:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "humidity.fill"); Text(data.humidity) }.font(textFont)
        case .feelsLike:
            Image(systemName: WeatherIconMapper.map(from: data.iconCode))
                .font(.title2)
                .symbolRenderingMode(.multicolor)
             Text("Feels \(settings.settings.weatherUseCelsius ? data.feelsLikeMetric : data.feelsLike)°").font(textFont)
        case .precipitation:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "drop.fill"); Text("\(data.precipChance)%") }.font(textFont)
        case .sunrise:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "sunrise.fill"); Text(data.sunriseTime) }.font(textFont)
        case .sunset:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "sunset.fill"); Text(data.sunsetTime) }.font(textFont)
        case .uvIndex:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "sun.max.fill"); Text(data.uvIndex) }.font(textFont)
        case .visibility:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "eye.fill"); Text(data.visibility) }.font(textFont)
        case .pressure:
            HStack(spacing: LockScreenConfiguration.infoWidgetSmallIconHSpacing) { Image(systemName: "gauge.medium"); Text(data.pressure) }.font(textFont)
        case .locationName:
            Text(data.locationName).fontWeight(.semibold).font(textFont)
        case .conditionDescription:
            Text(data.conditionDescription).font(textFont)
        case .highLowTemp:
            let high = settings.settings.weatherUseCelsius ? data.highTempMetric : data.highTemp
            let low = settings.settings.weatherUseCelsius ? data.lowTempMetric : data.lowTemp
            Text("H:\(high)° L:\(low)°").font(textFont)
        }
    }

    @ViewBuilder
    private func CalendarInfoView() -> some View {
        if let event = calendarService.upcomingEvents.first {
            HStack(spacing: LockScreenConfiguration.infoWidgetInternalHSpacing) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text(event.title)
                        .fontWeight(.semibold)
                    Text(event.startDate, style: .time)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.white)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetInternalHSpacing) {
                Image(systemName: "calendar")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("No More Events Today")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        }
    }

    @ViewBuilder
    private func MusicInfoView() -> some View {
        if musicWidget.isPlaying, let title = musicWidget.title {
            HStack(spacing: LockScreenConfiguration.infoWidgetInternalHSpacing) {
                Image(nsImage: musicWidget.artwork ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "Album art")!)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: LockScreenConfiguration.infoWidgetMusicArtworkSize, height: LockScreenConfiguration.infoWidgetMusicArtworkSize).cornerRadius(LockScreenConfiguration.infoWidgetMusicArtworkCornerRadius)

                VStack(alignment: .leading) {
                    Text(title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if let artist = musicWidget.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundColor(.white)
            .transition(fadeTransition)
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "music.note")
                    .font(.callout)
                Text("Nothing Playing")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        }
    }

    @ViewBuilder
    private func FocusInfoView() -> some View {
        let customImageAssetNames: Set<String> = [
            "rocket.fill",
            "apple.mindfulness",
            "person.lanyardcard.fill"
        ]

        let focusStatus = focusModeManager.currentStatus
        if focusStatus.isActive {
            let focusInfo = focusStatus.toFocusModeInfo(isActive: true)

            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                if focusStatus.identifier == "com.apple.focus.reduce-interruptions" {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))

                } else if customImageAssetNames.contains(focusStatus.symbolName) {
                    Image(focusStatus.symbolName)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: LockScreenConfiguration.infoWidgetFocusIconSize, height: LockScreenConfiguration.infoWidgetFocusIconSize)

                } else {
                    Image(systemName: focusInfo.symbolName)
                        .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                }

                Text(focusInfo.name)
                    .fontWeight(.semibold)
            }
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("Focus Off")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        }
    }

    @ViewBuilder
    private func BluetoothInfoView() -> some View {
        let device = bluetoothManager.lastEvent

        if let device = device, device.eventType == .connected, let batteryLevel = device.batteryLevel {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: device.iconName)
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))

                Text("\(batteryLevel)%")
                    .font(.system(size: LockScreenConfiguration.infoWidgetBoldFontSize, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        } else if !settings.settings.lockScreenHideInactiveInfoWidgets {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {
                Image(systemName: "headphones")
                    .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize))
                Text("No Device")
            }
            .foregroundColor(.secondary)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        }
    }

    @ViewBuilder
    private func BatteryInfoView() -> some View {
        if let state = batteryMonitor.currentState {
            HStack(spacing: LockScreenConfiguration.infoWidgetGenericHSpacing) {

                if settings.settings.lockScreenBatteryInfo.contains(.statusIcon) {
                    if state.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize - 5, weight: .bold))
                    } else if state.isPluggedIn && !state.isCharging {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: LockScreenConfiguration.infoWidgetIconFontSize, weight: .semibold))
                    }
                }

                if settings.settings.lockScreenBatteryInfo.contains(.batteryIcon) {
                    let iconSize: CGFloat = LockScreenConfiguration.infoWidgetLargeFontSize + 2

                    if state.isCharging {
                        Image(systemName: "battery.100.bolt")
                            .font(.system(size: iconSize, weight: .semibold))
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 30, height: 28)
                    } else {
                        let batterySymbol = Image(systemName: "battery.100")
                            .font(.system(size: iconSize, weight: .semibold))

                        ZStack(alignment: .leading) {
                            batterySymbol
                                .foregroundColor(.white.opacity(0.35))

                            GeometryReader { geo in
                                let insetHorizontal = geo.size.width * 0.11
                                let terminalWidth = geo.size.width * 0.05
                                let fillableWidth = geo.size.width - (insetHorizontal * 2) - terminalWidth
                                let currentFillWidth = fillableWidth * (CGFloat(state.level) / 100.0)
                                let totalMaskWidth = insetHorizontal + currentFillWidth

                                Rectangle()
                                    .frame(width: totalMaskWidth)
                                    .foregroundColor(.white)
                            }
                            .mask(batterySymbol)
                        }
                        .frame(width: 30, height: 28)
                    }
                }

                if settings.settings.lockScreenBatteryInfo.contains(.percentage) {
                    Text("\(state.level)%")
                        .font(.system(size: LockScreenConfiguration.infoWidgetBoldFontSize, weight: .bold, design: .rounded))
                }

                if settings.settings.lockScreenBatteryInfo.contains(.estimatedTime) {
                    if settings.settings.showEstimatedBatteryTime,
                       let timeRemaining = batteryEstimator.estimatedTimeRemaining,
                       !timeRemaining.isEmpty,
                       timeRemaining != "Charged" {
                        Text(timeRemaining)
                            .font(.system(size: LockScreenConfiguration.infoWidgetMediumFontSize, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .foregroundColor(.white)
            .modifier(TransparentEffect())
            .transition(fadeTransition)
        }
    }
}