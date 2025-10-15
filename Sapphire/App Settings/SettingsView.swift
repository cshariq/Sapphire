//
//  SettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI

private struct WindowKey: EnvironmentKey {
    static let defaultValue: NSWindow? = nil
}

extension EnvironmentValues {
    var window: NSWindow? {
        get { self[WindowKey.self] }
        set { self[WindowKey.self] = newValue }
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsModel.shared
    @State private var selectedSection: SettingsSection? = .widgets
    @State private var nsWindow: NSWindow? = nil

    var body: some View {

        ZStack {
            HStack(spacing: 0) {
                SettingsSidebarView(selectedSection: $selectedSection)
                    .frame(width: 190, height: 880)

                SettingsDetailView(selectedSection: selectedSection)
            }

            WindowDragHandle()

            CustomTrafficLightButtons()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowFinder { window in
            self.nsWindow = window
            if let w = window {
                w.isReleasedWhenClosed = true
                w.titleVisibility = .hidden
                w.titlebarAppearsTransparent = true
                w.isOpaque = false
                w.backgroundColor = .clear
                w.standardWindowButton(.closeButton)?.isHidden = true
                w.standardWindowButton(.miniaturizeButton)?.isHidden = true
                w.standardWindowButton(.zoomButton)?.isHidden = true
            }
        })
        .environmentObject(settings)
        .environment(\.window, nsWindow)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: nil)) { notification in
            guard let closingWindow = notification.object as? NSWindow else { return }
            if closingWindow == nsWindow {
                closingWindow.orderOut(nil)
                nsWindow = nil
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct WindowDragHandle: View {
    @Environment(\.window) private var window

    var body: some View {
        VStack {
            Color.clear
                .frame(height: 50)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if let window = window {
                                let startPoint = window.frame.origin
                                let newPoint = NSPoint(
                                    x: startPoint.x + value.translation.width,
                                    y: startPoint.y - value.translation.height
                                )
                                window.setFrameOrigin(newPoint)
                            }
                        }
                )
            Spacer()
        }
        .zIndex(1)
    }
}

private struct WindowFinder: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            callback(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            callback(nsView?.window)
        }
    }
}