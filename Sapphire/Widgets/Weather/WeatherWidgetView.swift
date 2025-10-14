//
//  WeatherWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-05
//

import SwiftUI

struct WeatherWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @ObservedObject private var viewModel = WeatherViewModel.shared

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 10) {
                primaryInfo.layoutPriority(1)
                secondaryInfo
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 0)
        .frame(minWidth: 200, minHeight: 90)
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                navigationStack.wrappedValue.append(.weatherPlayer)
            }
        }
    }

    private var primaryInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.iconName)
                .font(.system(size: 44))
                .symbolRenderingMode(.multicolor)
                .shadow(radius: 2)
                .minimumScaleFactor(0.8)
                .id(viewModel.iconName)
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.temperature)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .id(viewModel.temperature)
                    .transition(.opacity)

                Text(viewModel.locationName)
                    .font(.headline).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.7)
                    .id(viewModel.locationName)
                    .transition(.opacity)

                Text(viewModel.conditionDescription)
                    .font(.subheadline).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
                    .id(viewModel.conditionDescription)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.4), value: viewModel.locationName)
        }
    }

    private var secondaryInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            CompactInfoRow(iconName: "wind", value: viewModel.windInfo)
            CompactInfoRow(iconName: "drop.fill", value: viewModel.precipChance)
            CompactInfoRow(iconName: "humidity.fill", value: viewModel.humidity)
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.windInfo)
    }
}

struct CompactInfoRow: View {
    let iconName: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.callout)
                .frame(width: 20)
                .symbolRenderingMode(.hierarchical)
                .opacity(0.8)

            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .id(value)
        .transition(.opacity)
    }
}