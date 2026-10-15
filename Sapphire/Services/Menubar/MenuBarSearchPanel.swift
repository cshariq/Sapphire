//
//  MenuBarSearchPanel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27
//

@preconcurrency import ApplicationServices
import AppKit
import SwiftUI

@MainActor
final class MenuBarSearchPanelController: ObservableObject {
    static let shared = MenuBarSearchPanelController()

    struct Entry: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let icon: NSImage?
        let isHidden: Bool
        let recentKey: String
    }

    @Published var query = "" {
        didSet { selectedIndex = 0 }
    }
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isLoading = false
    @Published var selectedIndex = 0

    private var panel: KeyableNonMainPanel?
    private var mouseDownTokens: [NSEvent.EventType: UUID] = [:]
    private var isVisible = false

    private static let panelSize = NSSize(width: 460, height: 380)
    private static let recentsKey = "SapphireMenuBarSearchRecents"
    private static let recentsLimit = 8

    private var recentKeys: [String] = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []

    private init() {}

    var filteredEntries: [Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entriesWithRecentsFirst }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || $0.subtitle.localizedCaseInsensitiveContains(needle)
        }
    }

    private var entriesWithRecentsFirst: [Entry] {
        guard !recentKeys.isEmpty else { return entries }
        let rank = Dictionary(recentKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = entries.filter { rank[$0.recentKey] != nil }
            .sorted { rank[$0.recentKey]! < rank[$1.recentKey]! }
        return recent + entries.filter { rank[$0.recentKey] == nil }
    }

    func isRecent(_ entry: Entry) -> Bool {
        query.isEmpty && recentKeys.contains(entry.recentKey)
    }

    private func noteRecent(_ entry: Entry) {
        recentKeys.removeAll { $0 == entry.recentKey }
        recentKeys.insert(entry.recentKey, at: 0)
        if recentKeys.count > Self.recentsLimit { recentKeys.removeLast(recentKeys.count - Self.recentsLimit) }
        UserDefaults.standard.set(recentKeys, forKey: Self.recentsKey)
    }

    // MARK: - Presentation

    func toggle() {
        isVisible ? close() : open()
    }

    func open() {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            AccessibilityPermission.request()
            return
        }
        query = ""
        selectedIndex = 0
        isLoading = entries.isEmpty
        ensurePanel()
        guard let panel else { return }

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let origin = CGPoint(
                x: screen.frame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.maxY - 80
            )
            panel.setFrameTopLeftPoint(origin)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        refreshMouseMonitor()
        reload()
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
        refreshMouseMonitor()
    }

    private func reload() {
        MenuBarItemCatalog.shared.start()
        MenuBarItemCatalog.shared.items(maxAge: 0.5) { [weak self] items in
            guard let self else { return }
            var apps: [pid_t: NSRunningApplication] = [:]
            self.entries = Array(items.map { item in
                let app = apps[item.pid] ?? NSRunningApplication(processIdentifier: item.pid)
                apps[item.pid] = app
                let appName = app?.localizedName ?? "PID \(item.pid)"
                let title = item.name ?? appName
                return Entry(
                    id: item.id,
                    title: title,
                    subtitle: appName,
                    icon: app?.icon,
                    isHidden: !item.isOnScreen,
                    recentKey: "\(app?.bundleIdentifier ?? appName)|\(title)"
                )
            }
            .reversed())
            self.isLoading = false
        }
    }

    // MARK: - Keyboard

    func moveSelection(by delta: Int) {
        let count = filteredEntries.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func activateSelection() {
        let list = filteredEntries
        guard list.indices.contains(selectedIndex) else { return }
        activate(list[selectedIndex])
    }

    func activate(_ entry: Entry) {
        close()
        noteRecent(entry)
        let controller = (NSApp.delegate as? AppDelegate)?.statusBarController
        let press = {
            MenuBarItemCatalog.shared.items(maxAge: 0) { items in
                guard let item = items.first(where: { $0.id == entry.id }) else { return }
                let element = item.element
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = AX.perform(kAXPressAction as String, on: element)
                }
            }
        }
        if entry.isHidden, let controller {
            controller.revealAllSections { press() }
        } else {
            press()
        }
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = KeyableNonMainPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureAsSapphireOverlay()
        panel.level = .popUpMenu

        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 22
        backdrop.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: MenuBarSearchView(controller: self))
        hosting.sizingOptions = []
        hosting.frame = backdrop.bounds
        hosting.autoresizingMask = [.width, .height]
        backdrop.addSubview(hosting)

        panel.contentView = backdrop
        panel.setContentSize(Self.panelSize)
        self.panel = panel
    }

    private func refreshMouseMonitor() {
        EventMonitorHub.shared.setRegistered(
            isVisible,
            tokens: &mouseDownTokens,
            for: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible, let frame = self.panel?.frame else { return }
            if !frame.contains(NSEvent.mouseLocation) { self.close() }
        }
    }
}

// MARK: - View

private struct MenuBarSearchView: View {
    @ObservedObject var controller: MenuBarSearchPanelController
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search menu bar items", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isQueryFocused)
                    .onSubmit { controller.activateSelection() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            results
        }
        .onAppear { isQueryFocused = true }
        .onKeyPress(.downArrow) { controller.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { controller.moveSelection(by: -1); return .handled }
        .onKeyPress(.escape) { controller.close(); return .handled }
    }

    @ViewBuilder
    private var results: some View {
        let entries = controller.filteredEntries
        if controller.isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            Text(controller.query.isEmpty ? "No menu bar items found" : "No items match “\(controller.query)”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            row(entry, isSelected: index == controller.selectedIndex)
                                .id(entry.id)
                                .onTapGesture { controller.activate(entry) }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: controller.selectedIndex) { _, index in
                    guard entries.indices.contains(index) else { return }
                    proxy.scrollTo(entries[index].id)
                }
            }
        }
    }

    private func row(_ entry: MenuBarSearchPanelController.Entry, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = entry.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "menubar.rectangle").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if entry.subtitle != entry.title {
                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if controller.isRecent(entry) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Recently opened")
            }
            if entry.isHidden {
                Text("Hidden")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}