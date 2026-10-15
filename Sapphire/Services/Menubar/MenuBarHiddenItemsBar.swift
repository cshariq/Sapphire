//
//  MenuBarHiddenItemsBar.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12
//

import AppKit
import SwiftUI

@MainActor
final class MenuBarHiddenItemsBar: ObservableObject {
    static let shared = MenuBarHiddenItemsBar()

    struct Entry: Identifiable, Equatable {
        let id: String
        let title: String
        let icon: NSImage?
        let symbolName: String?
        let sectionKey: String?
        let isAlwaysHidden: Bool
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isLoading = false

    private var panel: NSPanel?
    private var mouseDownTokens: [NSEvent.EventType: UUID] = [:]
    private var keyMonitor: Any?
    private var isVisible = false
    private var anchor: CGRect?
    private var rehideTimer: Timer?
    private var openedAt = Date.distantPast

    private static let height: CGFloat = 40

    private init() {}

    // MARK: - Presentation

    func toggle(below anchor: CGRect?) {
        isVisible ? close() : show(below: anchor)
    }

    func show(below anchor: CGRect?) {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted() else {
            AccessibilityPermission.request()
            return
        }
        self.anchor = anchor
        isLoading = entries.isEmpty
        ensurePanel()
        isVisible = true
        reposition()
        panel?.orderFrontRegardless()
        refreshMonitors()
        reload()
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
        refreshMonitors()
    }

    private func reload() {
        MenuBarItemCatalog.shared.start()
        MenuBarItemCatalog.shared.items(maxAge: 0.3) { [weak self] items in
            guard let self else { return }
            let store = MenuBarSectionStore.shared
            let agentPID = MenuBarAgentHost.agentPID
            var apps: [pid_t: NSRunningApplication] = [:]

            self.entries = items.filter { !$0.isOnScreen }.compactMap { item in
                if item.pid == agentPID {
                    guard let identifier = AX.string("AXIdentifier", of: item.element),
                          let system = MenuBarSystemItem(menuExtraIdentifier: identifier) else { return nil }
                    return Entry(
                        id: item.id, title: item.name ?? system.title, icon: nil, symbolName: system.symbolName,
                        sectionKey: system.key, isAlwaysHidden: store.section(for: system.key) == .alwaysHidden
                    )
                }
                let app = apps[item.pid] ?? NSRunningApplication(processIdentifier: item.pid)
                apps[item.pid] = app
                let key = MenuBarSectionStore.key(for: app)
                let appName = app?.localizedName ?? "PID \(item.pid)"
                return Entry(
                    id: item.id,
                    title: item.name.map { $0 == appName ? appName : "\(appName) — \($0)" } ?? appName,
                    icon: app?.icon,
                    symbolName: nil,
                    sectionKey: key,
                    isAlwaysHidden: key.map { store.section(for: $0) == .alwaysHidden } ?? false
                )
            }
            .sorted { lhs, rhs in
                lhs.isAlwaysHidden != rhs.isAlwaysHidden ? !lhs.isAlwaysHidden : false
            }
            self.isLoading = false
            self.reposition()
        }
    }

    // MARK: - Opening an item

    func activate(_ entry: Entry) {
        close()
        let restrictor = MenuBarVisibilityRestrictor.shared
        if let key = entry.sectionKey { restrictor.allowTemporarily(key) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MenuBarItemCatalog.shared.items(maxAge: 0) { items in
                guard let item = items.first(where: { $0.id == entry.id }) else { return }
                let element = item.element
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = AX.perform(kAXPressAction as String, on: element)
                }
            }
        }
        openedAt = Date()
        startRehideTimer()
    }

    private func startRehideTimer() {
        rehideTimer?.invalidate()
        var quietSince: Date?
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let now = Date()
                guard now.timeIntervalSince(self.openedAt) > 1.5 else { return }
                if StatusBarController.isAnyMenuOpen() {
                    quietSince = nil
                    return
                }
                if quietSince == nil { quietSince = now }
                let keepOpen = max(1, SettingsModel.shared.current.menuBarKeepOpenedItemsDelay)
                guard let since = quietSince, now.timeIntervalSince(since) >= keepOpen else { return }
                timer.invalidate()
                self.rehideTimer = nil
                MenuBarVisibilityRestrictor.shared.endTemporaryAllowances()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        rehideTimer = timer
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureAsSapphireOverlay()
        panel.level = .popUpMenu

        let backdrop = NSVisualEffectView()
        backdrop.material = .menu
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 12
        backdrop.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: MenuBarHiddenItemsBarView(bar: self))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        backdrop.addSubview(hosting)
        panel.contentView = backdrop
        self.panel = panel
    }

    private func reposition() {
        guard let panel, isVisible else { return }
        let itemCount = max(entries.count, 1)
        let width = min(CGFloat(itemCount) * 34 + CGFloat(entries.contains(where: \.isAlwaysHidden) ? 12 : 0) + 16, 900)

        let anchorRect = anchor.map { AX.cocoaRect(fromAXRect: $0) }
        let screen = anchorRect.flatMap { rect in NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } }
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let menuBarBottom = screen.visibleFrame.maxY
        let rightEdge = min((anchorRect?.maxX ?? screen.frame.maxX - 12) + 8, screen.frame.maxX - 8)
        let x = max(screen.frame.minX + 8, rightEdge - width)
        let frame = NSRect(x: x, y: menuBarBottom - 6 - Self.height, width: width, height: Self.height)
        panel.setFrame(frame, display: true)
        panel.contentView?.subviews.first?.frame = panel.contentView?.bounds ?? .zero
    }

    private func refreshMonitors() {
        EventMonitorHub.shared.setRegistered(
            isVisible,
            tokens: &mouseDownTokens,
            for: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible, let frame = self.panel?.frame else { return }
            if !frame.contains(NSEvent.mouseLocation) { self.close() }
        }
        if isVisible, keyMonitor == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { MenuBarHiddenItemsBar.shared.close() } }
            }
        } else if !isVisible, let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - View

private struct MenuBarHiddenItemsBarView: View {
    @ObservedObject var bar: MenuBarHiddenItemsBar

    var body: some View {
        HStack(spacing: 2) {
            if bar.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if bar.entries.isEmpty {
                Text("No hidden items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(bar.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0, entry.isAlwaysHidden, !bar.entries[index - 1].isAlwaysHidden {
                        Divider().frame(height: 18).padding(.horizontal, 4)
                    }
                    HiddenItemButton(entry: entry) { bar.activate(entry) }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HiddenItemButton: View {
    let entry: MenuBarHiddenItemsBar.Entry
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if let icon = entry.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: entry.symbolName ?? "menubar.rectangle")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .frame(width: 20, height: 20)
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.title)
        .onHover { isHovered = $0 }
    }
}