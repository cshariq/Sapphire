//
//  MultiAudioView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI

struct MultiAudioView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        DeviceListView(navigationStack: $navigationStack)
    }
}

fileprivate struct DeviceListView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @StateObject private var audioManager = MultiAudioManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if !audioManager.availableOutputDevices.isEmpty {
                        VStack(alignment: .leading) {
                            Text("OUTPUT")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                ForEach(audioManager.availableOutputDevices) { device in
                                    DeviceOutputRow(device: device, navigationStack: $navigationStack)
                                }
                            }
                        }
                    }

                    if !audioManager.availableInputDevices.isEmpty {
                        VStack(alignment: .leading) {
                            Text("INPUT")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                ForEach(audioManager.availableInputDevices) { device in
                                    DeviceInputRow(device: device)
                                }
                            }.padding(.bottom, 20)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 600)
        .padding(.top, 10)
    }
}

// MARK: - Row and Helper Views

fileprivate struct EmptySectionView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
    }
}

fileprivate struct DeviceOutputRow: View {
    let device: AudioDevice
    @Binding var navigationStack: [NotchWidgetMode]

    @StateObject private var audioManager = MultiAudioManager.shared

    private var isSelected: Bool {
        audioManager.selectedOutputDeviceIDs.contains(device.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(systemName: IconMapper.icon(for: device))
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundColor(isSelected ? .green : .primary)

                Text(device.name)
                    .fontWeight(.medium)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .green : .secondary)
            }

            if isSelected {
                HStack(spacing: 10) {
                    ModernControlButton(title: "Adjust", systemImage: "slider.horizontal.3") {
                        navigationStack.append(.multiAudioDeviceAdjust(device))
                    }

                    ModernControlButton(title: "EQ", systemImage: "dial.medium") {
                        navigationStack.append(.multiAudioEQ(device))
                    }
                }
                .padding(.leading, 45)
                .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.gray.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                audioManager.selectedOutputDeviceIDs.remove(device.id)
            } else {
                audioManager.selectedOutputDeviceIDs.insert(device.id)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

fileprivate struct DeviceInputRow: View {
    let device: AudioDevice
    @StateObject private var audioManager = MultiAudioManager.shared

    private var isSelected: Bool {
        audioManager.currentInputDeviceID == device.id
    }

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: IconMapper.icon(for: device))
                .font(.title2)
                .frame(width: 30)
                .foregroundColor(isSelected ? .accentColor : .primary)

            Text(device.name)
                .fontWeight(.medium)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(.gray.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            audioManager.setDefaultInputDevice(to: device.id)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

fileprivate struct ModernControlButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }
}