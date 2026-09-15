//
//  SettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI

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
                    AccountSettingsView()
                        .id("account-pane")
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    SettingsDetailView(selectedSection: selectedSection)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(settings)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: NotchConfiguration.settingsWindowCornerRadius, style: .continuous))
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .sapphireOpenAccountPane)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                showAccountPane = true
                selectedSection = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sapphireSettingsWillClose)) { _ in
            settings.flushPendingSave()
            SystemAppFetcher.shared.releaseCachedApps()
            AppIconLoader.releaseCache()
        }
        .onDisappear {
            SystemAppFetcher.shared.releaseCachedApps()
            AppIconLoader.releaseCache()
        }
    }
}