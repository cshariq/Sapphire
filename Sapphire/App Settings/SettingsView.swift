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
    private let settings = SettingsModel.shared
    @State private var selectedSection: SettingsSection? = .general
    @State private var showAccountPane = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SettingsSidebarView(selectedSection: $selectedSection, showAccountPane: $showAccountPane)
                    .frame(width: 250)

                if showAccountPane {
                    AccountPaneWithRefresh()
                        .id("account-pane")
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
        .onReceive(NotificationCenter.default.publisher(for: .sapphireSettingsWillClose)) { _ in
            settings.flushPendingSave()
            MemoryTrimSupport.releaseSettingsPaneCaches()
        }
        .onDisappear {
            MemoryTrimSupport.releaseSettingsPaneCaches()
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

// MARK: - Account Pane with Refresh

private struct AccountPaneWithRefresh: View {
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            // Refresh button bar
            HStack {
                Spacer()
                Button(action: {
                    isRefreshing = true
                    Task {
                        await SubscriptionManager.shared.validateSubscriptionStatus()
                        // Brief delay so the spinner is visible
                        try? await Task.sleep(for: .milliseconds(600))
                        await MainActor.run { isRefreshing = false }
                    }
                }) {
                    HStack(spacing: 6) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        }
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                        Text("Refresh")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .padding(.trailing, 16)
                .padding(.top, 56)
            }

            AccountSettingsView()
        }
    }
}