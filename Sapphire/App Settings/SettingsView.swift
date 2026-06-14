//
//  SettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI

private final class WeakWindowBox {
    weak var window: NSWindow?
    init(_ window: NSWindow) { self.window = window }
}

private struct WindowKey: EnvironmentKey {
    static let defaultValue: WeakWindowBox? = nil
}

extension EnvironmentValues {
    var window: NSWindow? {
        get { self[WindowKey.self]?.window }
        set {
            if let newValue {
                self[WindowKey.self] = WeakWindowBox(newValue)
            } else {
                self[WindowKey.self] = nil
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsModel.shared
    @State private var selectedSection: SettingsSection? = .general
    @State private var showAccountPane = true // Track Account pane visibility (Enabled by default like System Settings)

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Pass showAccountPane and selectedSection bindings to handle mutual exclusion
                SettingsSidebarView(selectedSection: $selectedSection, showAccountPane: $showAccountPane)
                    .frame(width: 250, height: 1000)

                if showAccountPane {
                    AccountSettingsView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    SettingsDetailView(selectedSection: selectedSection)
                }
            }

            WindowDragHandle()

            CustomTrafficLightButtons()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(settings)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .sapphireOpenAccountPane)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                showAccountPane = true
                selectedSection = nil
            }
        }
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
    }
}
