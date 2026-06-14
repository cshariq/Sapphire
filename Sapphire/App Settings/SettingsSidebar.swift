//
//  SettingsSidebar.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection?
    @Binding var showAccountPane: Bool
    @State private var searchText = ""

    private var filteredSections: [SettingsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsSection.allCases }

        return SettingsSection.allCases.filter { section in
            let haystacks = [section.label, section.shortDescription] + section.searchTokens
            return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 45)

            // MARK: 1. Search Settings (Top of Sidebar)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search settings", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12) // Spacing below search bar

            // MARK: 2. Apple ID Style Account Sidebar Card (Below Search Bar)
            SidebarAccountCardView(isSelected: showAccountPane) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showAccountPane = true
                    selectedSection = nil // Deselect standard list rows
                }
            }

            // MARK: 3. Settings Sections list
            List(selection: Binding(
                get: { selectedSection },
                set: { value in
                    selectedSection = value
                    if value != nil {
                        showAccountPane = false
                    }
                }
            )) {
                Section {
                    ForEach(filteredSections) { section in
                        SidebarRowView(section: section).tag(section)
                    }
                }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SapphireSelectSection"))) { notification in
                if let sectionName = notification.object as? String,
                   let section = SettingsSection(rawValue: sectionName) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.selectedSection = section
                        self.showAccountPane = false
                    }
                }
            }
            
            if !searchText.isEmpty && filteredSections.isEmpty {
                Text("No settings matched \"\(searchText)\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Button(action: {
                NSApp.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Quit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 3)
                .padding(.leading, 12)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 15)
        }
    }
}

// MARK: - Sidebar Profile Card
struct SidebarAccountCardView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Avatar: gradient only when signed in; plain icon when logged out
                Group {
                    if subscriptionManager.isSignedIn {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: subscriptionManager.tierGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            Text(subscriptionManager.userInitials)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 38, height: 38)

                // User details stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionManager.userDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(subscriptionManager.tierLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

struct CustomTrafficLightButtons: View {
    @Environment(\.window) private var settingsWindow: NSWindow?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                settingsWindow?.close()
            }) {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold, design: .rounded))
            }.buttonStyle(TrafficLightButtonStyle(color: .red, isHovering: isHovering))

            Button(action: { settingsWindow?.miniaturize(nil) }) {
                Image(systemName: "minus").font(.system(size: 7, weight: .bold, design: .rounded))
            }.buttonStyle(TrafficLightButtonStyle(color: .yellow, isHovering: isHovering))

            Button(action: { settingsWindow?.zoom(nil) }) {
                Image(systemName: "plus").font(.system(size: 7, weight: .bold, design: .rounded))
            }.buttonStyle(TrafficLightButtonStyle(color: .green, isHovering: isHovering))
        }.onHover { hovering in withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering } }
    }
}

struct TrafficLightButtonStyle: ButtonStyle {
    let color: Color; let isHovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        ZStack { Circle().fill(color); configuration.label.foregroundStyle(.black.opacity(0.6)).opacity(isHovering ? 1 : 0) }.frame(width: 12, height: 12)
    }
}

fileprivate struct SidebarRowView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    let section: SettingsSection

    private var isPremiumLocked: Bool {
        section.isPremiumLocked(
            for: subscriptionManager.activeTier,
            features: subscriptionManager.entitlements.features
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(section.iconBackgroundColor.opacity(0.8).gradient).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(section.label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Spacer()
            if isPremiumLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}
