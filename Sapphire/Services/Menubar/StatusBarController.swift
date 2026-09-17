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

private struct StatusBarSettings: Equatable {
    let enableAlwaysHiddenSection: Bool
    let showSectionDividers: Bool
    let hideMenuBarIcon: Bool
    let controlItemIconStyle: ControlItemIconStyle
    let autoRehide: Bool
    let rehideStrategy: String
    let tempShowInterval: TimeInterval

    init(_ settings: Settings) {
        enableAlwaysHiddenSection = settings.enableAlwaysHiddenSection
        showSectionDividers = settings.showSectionDividers
        hideMenuBarIcon = settings.hideMenuBarIcon
        controlItemIconStyle = settings.controlItemIconStyle
        autoRehide = settings.autoRehide
        rehideStrategy = settings.rehideStrategy
        tempShowInterval = settings.tempShowInterval
    }
}

@MainActor
final class StatusBarController {

    static func teardown(_ controller: StatusBarController?) {
        controller?.shutdown()
    }

    // MARK: - Status Bar Items
    private let expandCollapseItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private var alwaysHiddenItem: NSStatusItem?

    // MARK: - Sub-Managers
    private var appearanceManager: MenuBarAppearanceManager?
    private var screenCornerManager: ScreenCornerManager?
    private var profileEngine: MenuBarProfileEngine?

    // MARK: - State
    private var isCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isCollapsed, forKey: "SapphireIsCollapsed")
        }
    }

    private var isAlwaysHiddenExpanded = false
    private var isEditing = false
    private var isConditionRevealed = false

    private var autoCollapseTimer: Timer?
    private var smartRehideGlobalMonitor: Any?
    private var smartRehideLocalMonitor: Any?
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
        self.profileEngine = MenuBarProfileEngine.shared
        self.profileEngine?.start()

        NotificationCenter.default.addObserver(self, selector: #selector(profilesDidChange), name: .menuBarProfilesDidChange, object: nil)
    }

    @objc private func profilesDidChange() {
        guard SettingsModel.shared.settings.menuBarProfilesEnabled else { return }
        let engine = MenuBarProfileEngine.shared
        if engine.isRevealRequested {
            if isCollapsed {
                isConditionRevealed = true
                expand()
            }
        } else if isConditionRevealed {
            isConditionRevealed = false
            if !SettingsModel.shared.settings.autoRehide, !isEditing, isCollapsed == false {
                let mouseInMenuBar = NSScreen.screens.contains { screen in
                    let menuBarHeight = max(24, screen.frame.height - screen.visibleFrame.height)
                    let rect = CGRect(x: screen.frame.origin.x, y: screen.frame.maxY - menuBarHeight, width: screen.frame.width, height: menuBarHeight)
                    return rect.contains(NSEvent.mouseLocation)
                }
                if !mouseInMenuBar {
                    collapse()
                }
            } else {
                configureAutoRehide()
            }
        }
    }

    var isRevealRequestedByProfile: Bool {
        SettingsModel.shared.settings.menuBarProfilesEnabled && MenuBarProfileEngine.shared.isRevealRequested
    }

    deinit {
    }

    func shutdown() {
        stopAutoRehide()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        profileEngine?.stop()
        profileEngine = nil
        if let item = alwaysHiddenItem {
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenItem = nil
        }
        NSStatusBar.system.removeStatusItem(expandCollapseItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
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
        updateAlwaysHiddenItem(refreshItems: false)
        updateAllItemVisuals()
        configureAutoRehide()
    }

    private func setupObservers() {
        SettingsModel.shared.changes(of: StatusBarSettings.init)
            .sink { [weak self] settings in self?.handleSettingsChange(settings) }
            .store(in: &cancellables)
    }

    private func handleSettingsChange(_ settings: StatusBarSettings) {
        if settings.enableAlwaysHiddenSection != (alwaysHiddenItem != nil) { updateAlwaysHiddenItem() }
        updateAllItemVisuals()
        configureAutoRehide()
    }

    private func updateAllItemVisuals() {
        separatorItem.menu = createAppContextMenu()
        updateItems()
    }

    private func updateAlwaysHiddenItem(refreshItems: Bool = true) {
        if SettingsModel.shared.settings.enableAlwaysHiddenSection {
            guard alwaysHiddenItem == nil else { return }
            alwaysHiddenItem = NSStatusBar.system.statusItem(withLength: Lengths.collapsed)
            alwaysHiddenItem?.autosaveName = AutosaveKeys.alwaysHidden
        } else {
            guard let item = alwaysHiddenItem else { return }
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenItem = nil
        }
        if refreshItems { updateItems() }
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

        } else if isCollapsed && !hideControlIcon {
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
            appFocusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.collapse() }
            }

        default:
            break
        }
    }

    private func startSmartRehideMonitoring() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        smartRehideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSmartRehidePointerEvent() }
        }
        smartRehideLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleSmartRehidePointerEvent() }
            return event
        }
        handleSmartRehidePointerEvent()
    }

    private func handleSmartRehidePointerEvent() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) else { return }

        let menuBarBottom = screen.visibleFrame.maxY
        let buffer: CGFloat = 50
        if mouseLocation.y < menuBarBottom - buffer {
            collapse()
        }
    }

    private func removeSmartRehideMonitors() {
        if let smartRehideGlobalMonitor {
            NSEvent.removeMonitor(smartRehideGlobalMonitor)
            self.smartRehideGlobalMonitor = nil
        }
        if let smartRehideLocalMonitor {
            NSEvent.removeMonitor(smartRehideLocalMonitor)
            self.smartRehideLocalMonitor = nil
        }
    }

    private func stopAutoRehide() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        removeSmartRehideMonitors()

        if let observer = appFocusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
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