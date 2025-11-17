//
//  StatusBarController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import AppKit
import Combine

extension Notification.Name {
    static let menuBarHidingStateDidChange = Notification.Name("com.sapphire.menuBarHidingStateDidChange")
}

@MainActor
final class StatusBarController {

    // MARK: - Status Bar Items
    private let expandCollapseItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private var alwaysHiddenItem: NSStatusItem?

    // MARK: - Sub-Managers
    private var appearanceManager: MenuBarAppearanceManager?
    private var screenCornerManager: ScreenCornerManager?

    // MARK: - State
    private var isCollapsed = true
    private var isEditing = false

    private var autoCollapseTimer: Timer?
    private var smartRehideTimer: Timer?
    private var smartRehideMonitor: Any?
    private var appFocusObserver: NSObjectProtocol?

    private var cancellables = Set<AnyCancellable>()

    private var isUsingLTRLanguage: Bool { NSApp.userInterfaceLayoutDirection == .leftToRight }

    // MARK: - Constants
    private enum Lengths { static let standard: CGFloat = 24; static let separator: CGFloat = 8; static let collapsed: CGFloat = 10_000 }
    private enum AutosaveKeys { static let expandCollapse = "SapphireExpandCollapseItem"; static let separator = "SapphireSeparatorItem"; static let alwaysHidden = "SapphireAlwaysHiddenItem" }

    init() {
        StatusBarController.seedItemPositionsIfNeeded()

        expandCollapseItem = NSStatusBar.system.statusItem(withLength: Lengths.standard)
        expandCollapseItem.autosaveName = AutosaveKeys.expandCollapse

        separatorItem = NSStatusBar.system.statusItem(withLength: Lengths.collapsed)
        separatorItem.autosaveName = AutosaveKeys.separator

        setupItems()
        setupObservers()

        print("[StatusBarController] Initializing sub-managers.")
        self.appearanceManager = MenuBarAppearanceManager()
        self.screenCornerManager = ScreenCornerManager()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(expandCollapseItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        if let alwaysHiddenItem = alwaysHiddenItem { NSStatusBar.system.removeStatusItem(alwaysHiddenItem) }
        appearanceManager = nil
        screenCornerManager = nil
        print("[StatusBarController] Deinitialized and items removed.")
    }

    private static func preferredPositionKey(for autosaveName: String) -> String { "NSStatusItem Preferred Position \(autosaveName)" }

    private static func seedItemPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        let alwaysHiddenKey = preferredPositionKey(for: AutosaveKeys.alwaysHidden)
        if defaults.object(forKey: alwaysHiddenKey) == nil {
            defaults.set(0, forKey: alwaysHiddenKey)
        }
        let separatorKey = preferredPositionKey(for: AutosaveKeys.separator)
        if defaults.object(forKey: separatorKey) == nil {
            defaults.set(1, forKey: separatorKey)
        }
        let expandCollapseKey = preferredPositionKey(for: AutosaveKeys.expandCollapse)
        if defaults.object(forKey: expandCollapseKey) == nil {
            defaults.set(1_000_000, forKey: expandCollapseKey)
        }
        print("[StatusBarController] Item positions seeded successfully.")
    }

    // MARK: - Setup

    private func setupItems() {
        if let button = expandCollapseItem.button {
            button.target = self
            button.action = #selector(statusBarButtonAction(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        separatorItem.menu = createAppContextMenu()
        updateAlwaysHiddenItem()
        updateAllItemVisuals()
    }

    private func setupObservers() {
        SettingsModel.shared.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in self?.handleSettingsChange(settings) }
            .store(in: &cancellables)
    }

    private func handleSettingsChange(_ settings: Settings) {
        if settings.enableAlwaysHiddenSection != (alwaysHiddenItem != nil) { updateAlwaysHiddenItem() }
        updateAllItemVisuals()
        configureAutoRehide()
    }

    private func updateAllItemVisuals() {
        separatorItem.menu = createAppContextMenu()
        updateItems()
    }

    private func updateAlwaysHiddenItem() {
        if SettingsModel.shared.settings.enableAlwaysHiddenSection {
            guard alwaysHiddenItem == nil else { return }
            alwaysHiddenItem = NSStatusBar.system.statusItem(withLength: Lengths.collapsed)
            alwaysHiddenItem?.autosaveName = AutosaveKeys.alwaysHidden
            print("[StatusBarController] Always Hidden item created.")
        } else {
            guard let item = alwaysHiddenItem else { return }
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenItem = nil
            print("[StatusBarController] Always Hidden item removed.")
        }
        updateItems()
    }

    // MARK: - Core Logic

    @objc private func statusBarButtonAction(sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseUp {
                expandCollapseItem.popUpMenu(createChevronContextMenu())
            } else {
                (NSApp.delegate as? AppDelegate)?.interactionManager?.temporarilyDisable(for: 0.5)
                if event.modifierFlags.contains(.option) { enterEditMode() } else { isCollapsed ? expand() : collapse() }
            }
        }
    }

    func expand() {
        guard isCollapsed else { return }
        print("[StatusBarController] Expanding Hidden section.")
        isCollapsed = false
        isEditing = false
        updateItems()
        configureAutoRehide()
    }

    private func collapse() {
        print("[StatusBarController] Collapsing all sections.")
        isCollapsed = true
        isEditing = false
        updateItems()
        stopAutoRehide()
    }

    @objc private func enterEditMode() {
        print("[StatusBarController] Entering Edit Mode.")
        isEditing = true
        isCollapsed = false
        updateItems()
        stopAutoRehide()
    }

    // MARK: - UI Updates

    private func updateItems() {
        let settings = SettingsModel.shared.settings
        let showDividers = settings.showSectionDividers
        let hideControlIcon = settings.hideMenuBarIcon
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Separator")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 5, weight: .light))

        expandCollapseItem.length = hideControlIcon ? 0 : Lengths.standard

        separatorItem.isVisible = true
        if let alwaysHiddenItem = alwaysHiddenItem {
            alwaysHiddenItem.isVisible = true
        }

        if isEditing {
            separatorItem.length = Lengths.separator
            separatorItem.button?.image = image
            alwaysHiddenItem?.length = Lengths.separator
            alwaysHiddenItem?.button?.image = image
        } else if isCollapsed {
            separatorItem.length = Lengths.collapsed
            separatorItem.button?.image = showDividers ? image : nil
            alwaysHiddenItem?.length = Lengths.collapsed
            alwaysHiddenItem?.button?.image = nil
        } else {
            separatorItem.length = showDividers ? Lengths.separator : 0
            separatorItem.button?.image = showDividers ? image : nil
            alwaysHiddenItem?.length = Lengths.collapsed
            alwaysHiddenItem?.button?.image = nil
        }

        updateExpandCollapseIcon()
        NotificationCenter.default.post(name: .menuBarHidingStateDidChange, object: nil)
    }

    private func updateExpandCollapseIcon() {
        guard let button = expandCollapseItem.button else { return }
        let style = SettingsModel.shared.settings.controlItemIconStyle
        let symbolName = style.symbolName(isHidden: isCollapsed && !isEditing)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Toggle Hidden Items")
    }

    // MARK: - Auto-Rehide Logic

    private func configureAutoRehide() {
        stopAutoRehide()

        guard SettingsModel.shared.settings.autoRehide, !isCollapsed, !isEditing else { return }

        let strategy = SettingsModel.shared.settings.rehideStrategy

        switch strategy {
        case "timed":
            let interval = SettingsModel.shared.settings.tempShowInterval
            print("[StatusBarController] Starting timed rehide: \(interval)s")
            autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.collapse()
            }

        case "smart":
            print("[StatusBarController] Starting smart rehide monitoring")
            smartRehideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.handleSmartRehideMouseMove()
            }

        case "focusedApp":
            print("[StatusBarController] Starting focused app rehide monitoring")
            appFocusObserver = NotificationCenter.default.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.collapse()
            }

        default:
            break
        }
    }

    private func stopAutoRehide() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        if let monitor = smartRehideMonitor {
            NSEvent.removeMonitor(monitor)
            smartRehideMonitor = nil
        }

        smartRehideTimer?.invalidate()
        smartRehideTimer = nil

        if let observer = appFocusObserver {
            NotificationCenter.default.removeObserver(observer)
            appFocusObserver = nil
        }
    }

    private func handleSmartRehideMouseMove() {
        if isMouseInMenuBar() {
            if smartRehideTimer != nil {
                print("[StatusBarController] Mouse re-entered, cancelling rehide")
                smartRehideTimer?.invalidate()
                smartRehideTimer = nil
            }
        } else {
            if smartRehideTimer == nil {
                smartRehideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    print("[StatusBarController] Smart rehide triggered")
                    self?.collapse()
                }
            }
        }
    }

    private func isMouseInMenuBar() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else { return false }

        let boundary = screen.visibleFrame.maxY - 10

        return mouseLocation.y > boundary
    }

    // MARK: - Context Menus

    private func createChevronContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Edit Menu Bar Items", action: #selector(enterEditMode), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Sapphire Settings…", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sapphire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func createAppContextMenu() -> NSMenu {
        let menu = NSMenu()
        if SettingsModel.shared.settings.hideMenuBarIcon {
            menu.addItem(withTitle: "Edit Menu Bar Items", action: #selector(enterEditMode), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sapphire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openPreferences() {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}