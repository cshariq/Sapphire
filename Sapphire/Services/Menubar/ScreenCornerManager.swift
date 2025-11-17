//
//  ScreenCornerManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import SwiftUI
import Combine

@MainActor
final class ScreenCornerManager {
    private var cornerOverlays = [NSScreen: [Corner: NSPanel]]()
    private var cancellables = Set<AnyCancellable>()

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    init() {
        print("[ScreenCornerManager] Initializing.")
        setupObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit {
        print("[ScreenCornerManager] Deinitializing.")

        let panelsToClose = cornerOverlays.values.flatMap { $0.values }
        cornerOverlays.removeAll()

        DispatchQueue.main.async {
            print("[ScreenCornerManager] Executing async cleanup: closing \(panelsToClose.count) panels.")
            for panel in panelsToClose {
                panel.close()
            }
        }

        NotificationCenter.default.removeObserver(self)
    }

    private func setupObservers() {
        SettingsModel.shared.$settings
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.applyCornerSettings(from: settings)
            }
            .store(in: &cancellables)
    }

    @objc private func screenParametersChanged() {
        applyCornerSettings(from: SettingsModel.shared.settings)
    }

    private func applyCornerSettings(from settings: Settings) {
        let radius = settings.screenCornerRadius
        let shouldShowTop = settings.roundedCornersTop || settings.roundedCornersBelowMenu
        let shouldShowBottom = settings.roundedCornersBottom

        guard shouldShowTop || shouldShowBottom else {
            removeAllOverlays(); return
        }

        for screen in NSScreen.screens {
            var screenOverlays = cornerOverlays[screen] ?? [:]

            if shouldShowTop {
                let yOffset = settings.roundedCornersBelowMenu ? (screen.frame.height - screen.visibleFrame.height) : 0
                screenOverlays[.topLeft] = createOrUpdatePanel(for: .topLeft, on: screen, radius: radius, yOffset: yOffset, existingPanel: screenOverlays[.topLeft])
                screenOverlays[.topRight] = createOrUpdatePanel(for: .topRight, on: screen, radius: radius, yOffset: yOffset, existingPanel: screenOverlays[.topRight])
            } else {
                screenOverlays[.topLeft]?.close(); screenOverlays.removeValue(forKey: .topLeft)
                screenOverlays[.topRight]?.close(); screenOverlays.removeValue(forKey: .topRight)
            }

            if shouldShowBottom {
                screenOverlays[.bottomLeft] = createOrUpdatePanel(for: .bottomLeft, on: screen, radius: radius, existingPanel: screenOverlays[.bottomLeft])
                screenOverlays[.bottomRight] = createOrUpdatePanel(for: .bottomRight, on: screen, radius: radius, existingPanel: screenOverlays[.bottomRight])
            } else {
                screenOverlays[.bottomLeft]?.close(); screenOverlays.removeValue(forKey: .bottomLeft)
                screenOverlays[.bottomRight]?.close(); screenOverlays.removeValue(forKey: .bottomRight)
            }

            cornerOverlays[screen] = screenOverlays
        }
    }

    private func createOrUpdatePanel(for corner: Corner, on screen: NSScreen, radius: CGFloat, yOffset: CGFloat = 0, existingPanel: NSPanel?) -> NSPanel {
        let frame = frameFor(corner: corner, on: screen, radius: radius, yOffset: yOffset)

        if let panel = existingPanel {
            panel.setFrame(frame, display: true)
            (panel.contentView as? NSHostingView<CornerView>)?.rootView.corner = corner
            return panel
        } else {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: CornerView(corner: corner))
            panel.orderFrontRegardless()
            return panel
        }
    }

    private func frameFor(corner: Corner, on screen: NSScreen, radius: CGFloat, yOffset: CGFloat = 0) -> CGRect {
        let screenFrame = screen.frame
        switch corner {
        case .topLeft: return CGRect(x: screenFrame.minX, y: screenFrame.maxY - radius - yOffset, width: radius, height: radius)
        case .topRight: return CGRect(x: screenFrame.maxX - radius, y: screenFrame.maxY - radius - yOffset, width: radius, height: radius)
        case .bottomLeft: return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: radius, height: radius)
        case .bottomRight: return CGRect(x: screenFrame.maxX - radius, y: screenFrame.minY, width: radius, height: radius)
        }
    }

    private func removeAllOverlays() {
        for screenDict in cornerOverlays.values {
            for panel in screenDict.values {
                panel.close()
            }
        }
        cornerOverlays.removeAll()
    }
}

fileprivate struct CornerView: View {
    var corner: ScreenCornerManager.Corner
    var body: some View {
        QuarterCircle(corner: corner).fill(Color.black)
    }
}

fileprivate struct QuarterCircle: Shape {
    var corner: ScreenCornerManager.Corner
    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: 0, y: rect.height))
            path.addArc(center: CGPoint(x: rect.width, y: rect.height), radius: rect.width, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: 0))
        case .topRight:
            path.move(to: CGPoint(x: rect.width, y: 0))
            path.addArc(center: .zero, radius: rect.width, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: rect.height))
        case .bottomLeft:
            path.move(to: CGPoint(x: rect.width, y: 0))
            path.addArc(center: CGPoint(x: rect.width, y: rect.height), radius: rect.width, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: 0))
        case .bottomRight:
            path.move(to: CGPoint(x: 0, y: rect.height))
            path.addArc(center: .zero, radius: rect.width, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.width, y: 0))
        }
        path.closeSubpath()
        return path
    }
}