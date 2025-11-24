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
    private var isCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isCollapsed, forKey: "SapphireIsCollapsed")
        }
    }

    private var isAlwaysHiddenExpanded = false
    private var isEditing = false

    private var autoCollapseTimer: Timer?
    private var smartRehideTimer: Timer?
    private var appFocusObserver: NSObjectProtocol?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Constants
    private enum Lengths { static let standard: CGFloat = 24; static let separator: CGFloat = 8; static let collapsed: CGFloat = 10_000 }
    private enum AutosaveKeys { static let expandCollapse = "SapphireExpandCollapseItem"; static let separator = "SapphireSeparatorItem"; static let alwaysHidden = "SapphireAlwaysHiddenItem" }

    init() {
        self.isCollapsed = UserDefaults.standard.object(forKey: "SapphireIsCollapsed") as? Bool ?? false

        self.isAlwaysHiddenExpanded = false
        self.isEditing = false

        expandCollapseItem = NSStatusBar.system.statusItem(withLength: Lengths.standard)
        expandCollapseItem.autosaveName = AutosaveKeys.expandCollapse

        separatorItem = NSStatusBar.system.statusItem(withLength: Lengths.collapsed)
        separatorItem.autosaveName = AutosaveKeys.separator

        setupItems()
        setupObservers()
        self.appearanceManager = MenuBarAppearanceManager()
        self.screenCornerManager = ScreenCornerManager()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(expandCollapseItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        if let alwaysHiddenItem = alwaysHiddenItem { NSStatusBar.system.removeStatusItem(alwaysHiddenItem) }
        appearanceManager = nil
        screenCornerManager = nil
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
        } else {
            guard let item = alwaysHiddenItem else { return }
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenItem = nil
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

                if event.modifierFlags.contains(.option) {
                    enterEditMode()
                } else if event.modifierFlags.contains(.command) {
                    toggleAlwaysHidden()
                } else {
                    isCollapsed ? expand() : collapse()
                }
            }
        }
    }

    func expand() {
        guard isCollapsed else { return }
        isCollapsed = false
        isEditing = false

        isAlwaysHiddenExpanded = false

        updateItems()
        configureAutoRehide()
    }

    private func collapse() {
        isCollapsed = true
        isAlwaysHiddenExpanded = false
        isEditing = false
        updateItems()
        stopAutoRehide()
    }

    private func toggleAlwaysHidden() {
        isAlwaysHiddenExpanded.toggle()
        updateItems()
    }

    @objc private func enterEditMode() {
        isEditing = true
        isCollapsed = false
        isAlwaysHiddenExpanded = true
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

            if isAlwaysHiddenExpanded {
                alwaysHiddenItem?.length = showDividers ? Lengths.separator : 0
                alwaysHiddenItem?.button?.image = showDividers ? image : nil
            } else {
                alwaysHiddenItem?.length = Lengths.collapsed
                alwaysHiddenItem?.button?.image = nil
            }
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
            autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.collapse()
            }

        case "smart":
            startSmartRehideMonitoring()

        case "focusedApp":
            appFocusObserver = NotificationCenter.default.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.collapse()
            }

        default:
            break
        }
    }

    private func startSmartRehideMonitoring() {
        smartRehideTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let mouseLoc = NSEvent.mouseLocation

            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) else {
                return
            }

            let menuBarBottom = screen.visibleFrame.maxY
            let buffer: CGFloat = 50.0

            if mouseLoc.y < (menuBarBottom - buffer) {
                self.collapse()
            }
        }
    }

    private func stopAutoRehide() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        smartRehideTimer?.invalidate()
        smartRehideTimer = nil

        if let observer = appFocusObserver {
            NotificationCenter.default.removeObserver(observer)
            appFocusObserver = nil
        }
    }

    // MARK: - Context Menus

    private func createChevronContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Edit Menu Bar Items", action: #selector(enterEditMode), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Sapphire Setting", action: #selector(openPreferences), keyEquivalent: ",").target = self
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
        menu.addItem(withTitle: "Preferences", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sapphire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openPreferences() {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}