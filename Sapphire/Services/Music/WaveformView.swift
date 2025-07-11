//
//  WaveformView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI
import Combine

struct MusicWaveformView: View {
    @EnvironmentObject var musicWidget: MusicWidget
    @EnvironmentObject var settingsModel: SettingsModel

    @State private var transientIcon: TransientIcon?

    enum TransientIcon: Equatable {
        case paused, skippedForward, skippedBackward
        
        var systemName: String {
            switch self {
            case .paused: return "pause.fill"
            case .skippedForward: return "forward.end.fill"
            case .skippedBackward: return "backward.end.fill"
            }
        }
    }

    private let iconDisplayDuration: TimeInterval = 2.5
    private let barCount = 3
    private let minHeight: CGFloat = 3.0
    private let maxHeight: CGFloat = 22.0

    var body: some View {
        ZStack {
            if let icon = transientIcon {
                iconBody(systemName: icon.systemName)
            } else if musicWidget.isPlaying {
                animatedWaveformBody
            } else {
                staticWaveformBody
            }
        }
        .frame(width: 22, height: 22, alignment: .center)
        .onReceive(musicWidget.playerActionPublisher) { action in
            handle(playerAction: action)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: musicWidget.isPlaying)  
    }
    
    private func handle(playerAction: PlayerAction) {
        var iconToShow: TransientIcon?
        switch playerAction {
        case .paused: iconToShow = .paused
        case .skippedForward: iconToShow = .skippedForward
        case .skippedBackward: iconToShow = .skippedBackward
        case .played, .trackChanged:
            transientIcon = nil
            return
        }
        if let icon = iconToShow {
            showTransientIcon(icon)
        }
    }
    
    private func showTransientIcon(_ icon: TransientIcon) {
        self.transientIcon = icon
        Task {
            setTransientState(true)
            try? await Task.sleep(for: .seconds(iconDisplayDuration))
            if self.transientIcon == icon {
                self.transientIcon = nil
            }
            setTransientState(false)
        }
    }
    
    private func setTransientState(_ isDisplaying: Bool) {
        if musicWidget.isDisplayingTransientIcon != isDisplaying {
            DispatchQueue.main.async {
                musicWidget.isDisplayingTransientIcon = isDisplaying
            }
        }
    }

    
    private var animatedWaveformBody: some View {
        TimelineView(.animation(minimumInterval: 0.03)) { context in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(musicWidget.accentColor)
                        .shadow(color: musicWidget.accentColor.opacity(0.6), radius: 4, y: 2)
                        .frame(width: 3, height: calculateBarHeight(for: index, at: context.date))
                        .animation(.easeInOut(duration: 0.2), value: context.date) 
                }
            }
        }
        .frame(width: 18, height: 22)
        .transition(.opacity) 
    }
    
    
    private var staticWaveformBody: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule().fill(musicWidget.accentColor).frame(width: 3, height: minHeight)
            }
        }
        .frame(width: 18, height: 22)
        .transition(.opacity) 
    }

    private func iconBody(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(musicWidget.accentColor)
            .transition(.opacity.animation(.easeOut(duration: 0.2)))
    }

    
    private func calculateBarHeight(for index: Int, at date: Date) -> CGFloat {
        let scale = settingsModel.settings.musicWaveformIsVolumeSensitive ? musicWidget.systemVolume : 0.7
        let amplitude = (maxHeight - minHeight) * CGFloat(scale)
        let time = date.timeIntervalSinceReferenceDate
        
        let speed1 = 2.5
        let speed2 = 1.8
        let phaseOffset = Double(index) * 2.0
        
        let sine1 = sin((time * speed1) + phaseOffset)
        let sine2 = sin((time * speed2) + phaseOffset * 0.5)
        
        let combinedSine = (sine1 + sine2) / 2.0
        
        let basePulseLevel: CGFloat = 0.15
        let normalizedHeight = basePulseLevel + (1.0 - basePulseLevel) * ((CGFloat(combinedSine) + 1.0) / 2.0)
        
        return minHeight + (amplitude * normalizedHeight)
    }
}
