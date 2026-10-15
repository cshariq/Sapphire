//
//  StatusBarController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import AppKit
import Combine
import os

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
    let keepOpenedItemsDelay: TimeInterval

    init(_ settings: Settings) {
        enableAlwaysHiddenSection = settings.enableAlwaysHiddenSection
        showSectionDividers = settings.showSectionDividers
        hideMenuBarIcon = settings.hideMenuBarIcon
        controlItemIconStyle = settings.controlItemIconStyle
        autoRehide = settings.autoRehide
        rehideStrategy = settings.rehideStrategy
        tempShowInterval = settings.tempShowInterval
        keepOpenedItemsDelay = settings.menuBarKeepOpenedItemsDelay
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

    private(set) var isZenModeActive = false
    private var isZenModeAutomatic = false
    private var presentationMonitor: MenuBarPresentationMonitor?

    private var autoCollapseTimer: Timer?
    private var rehideGraceUntil = Date.distantPast
    private var lastMenuOpenSeen = Date.distantPast
    private var smartRehideTimer: Timer?
    private var appFocusObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    private var appWithHiddenMenus: NSRunningApplication?
    private var appMenuHidingGeneration = 0

    private var controlItemRecoveryAttempts = 0
    private var controlItemRecoveryWindowStart = Date.distantPast

    private var cancellables = Set<AnyCancellable>()
    private var statusSettings: StatusBarSettings

    private var learnGeneration = 0
    private var lastDrawnItems: [MenuBarAgentHost.DrawnItem] = [] {
        didSet { lastDrawnItemsAt = Date() }
    }
    private var lastDrawnItemsAt = Date.distantPast
    private var controlItemPlacementCheckPending = false
    private static let drawnItemsFreshness: TimeInterval = 30
    private var secondaryClickToken: GlobalEventTap.Token?
    private var sectionsObserver: NSObjectProtocol?

    // MARK: - Constants
    private enum Lengths { static let standard: CGFloat = 24; static let separator: CGFloat = 8; static let collapsed: CGFloat = 10_000 }
    private enum AutosaveKeys { static let expandCollapse = "SapphireExpandCollapseItem"; static let separator = "SapphireSeparatorItem"; static let alwaysHidden = "SapphireAlwaysHiddenItem" }

    init() {
        self.isCollapsed = UserDefaults.standard.object(forKey: "SapphireIsCollapsed") as? Bool ?? false
        self.statusSettings = StatusBarSettings(SettingsModel.shared.current)

        self.isAlwaysHiddenExpanded = false
        self.isEditing = false

        expandCollapseItem = NSStatusBar.system.statusItem(withLength: Lengths.standard)
        expandCollapseItem.autosaveName = AutosaveKeys.expandCollapse

        separatorItem = NSStatusBar.system.statusItem(withLength: Self.detectAgentHost() && MenuBarVisibilityRestrictor.isUsable ? 0 : Lengths.collapsed)
        separatorItem.autosaveName = AutosaveKeys.separator

        setupItems()
        setupObservers()
        self.appearanceManager = MenuBarAppearanceManager()
        self.screenCornerManager = ScreenCornerManager()
        self.profileEngine = MenuBarProfileEngine.shared
        self.profileEngine?.start()
        let presentationMonitor = MenuBarPresentationMonitor { [weak self] engaged in
            self?.setAutomaticZenMode(engaged)
        }
        self.presentationMonitor = presentationMonitor
        presentationMonitor.start()

        NotificationCenter.default.addObserver(self, selector: #selector(profilesDidChange), name: .menuBarProfilesDidChange, object: nil)
        scheduleControlItemPlacementCheck()
        observeAgentHost()
        if isAgentHosted { startAgentHosting() }
    }

    @objc private func profilesDidChange() {
        guard SettingsModel.shared.current.menuBarProfilesEnabled, !isZenModeActive else { return }
        let engine = MenuBarProfileEngine.shared
        if engine.isRevealRequested {
            if isCollapsed {
                isConditionRevealed = true
                expand()
            }
        } else if isConditionRevealed {
            isConditionRevealed = false
            if !statusSettings.autoRehide, !isEditing, isCollapsed == false {
                if !isPointerInMenuBar() {
                    collapse()
                }
            } else {
                configureAutoRehide()
            }
        }
    }

    var isRevealRequestedByProfile: Bool {
        SettingsModel.shared.current.menuBarProfilesEnabled && MenuBarProfileEngine.shared.isRevealRequested
    }

    deinit {
    }

    func shutdown() {
        stopAutoRehide()
        restoreApplicationMenus()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        stopAgentHosting()
        MenuBarHiddenItemsBar.shared.close()
        agentHostObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        agentHostObservers.removeAll()
        profileEngine?.stop()
        profileEngine = nil
        presentationMonitor?.stop()
        presentationMonitor = nil
        if let item = alwaysHiddenItem {
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenItem = nil
        }
        NSStatusBar.system.removeStatusItem(expandCollapseItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        appearanceManager = nil
        screenCornerManager = nil
        MenuBarWallpaperTint.shared.stop()
        MenuBarSearchPanelController.shared.close()
    }

    // MARK: - Setup

    private func setupItems() {
        if let button = expandCollapseItem.button {
            button.setAccessibilityIdentifier(AutosaveKeys.expandCollapse)
            if isAgentHosted, MenuBarAgentHost.attachPrimaryAction(to: button, target: self, action: #selector(primaryAction)) {
                usesForwardedPrimaryAction = true
            } else {
                button.target = self
                button.action = #selector(statusBarButtonAction(sender:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
        }
        separatorItem.button?.setAccessibilityIdentifier(AutosaveKeys.separator)
        updateAlwaysHiddenItem(refreshItems: false)
        updateAllItemVisuals()
        configureAutoRehide()
    }

    private func setupObservers() {
        SettingsModel.shared.changes(of: StatusBarSettings.init)
            .sink { [weak self] settings in self?.handleSettingsChange(settings) }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controlItemRecoveryAttempts = 0
                self?.scheduleControlItemPlacementCheck()
            }
        }
    }

    private func handleSettingsChange(_ settings: StatusBarSettings) {
        statusSettings = settings
        if settings.enableAlwaysHiddenSection != (alwaysHiddenItem != nil) { updateAlwaysHiddenItem() }
        updateAllItemVisuals()
        configureAutoRehide()
    }

    private func updateAllItemVisuals() {
        separatorItem.menu = createAppContextMenu()
        updateItems()
    }

    private func updateAlwaysHiddenItem(refreshItems: Bool = true) {
        if statusSettings.enableAlwaysHiddenSection {
            guard alwaysHiddenItem == nil else { return }
            alwaysHiddenItem = NSStatusBar.system.statusItem(withLength: usesRestriction ? 0 : Lengths.collapsed)
            alwaysHiddenItem?.autosaveName = AutosaveKeys.alwaysHidden
            alwaysHiddenItem?.button?.setAccessibilityIdentifier(AutosaveKeys.alwaysHidden)
        } else {
            guard let item = alwaysHiddenItem else { return }
            fittedDivider.forget(item)
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenItem = nil
        }
        if refreshItems { updateItems() }
    }

    // MARK: - Core Logic

    @objc private func statusBarButtonAction(sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showChevronContextMenu()
        } else {
            handlePrimaryClick(modifiers: event.modifierFlags)
        }
    }

    @objc private func primaryAction() {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.control) {
            showChevronContextMenu()
        } else {
            handlePrimaryClick(modifiers: modifiers)
        }
    }

    private func handlePrimaryClick(modifiers: NSEvent.ModifierFlags) {
        (NSApp.delegate as? AppDelegate)?.interactionManager?.temporarilyDisable(for: 0.5)

        if isZenModeActive {
            setZenMode(false)
            expand()
        } else if modifiers.contains(.option) {
            isEditing ? collapse() : enterEditMode()
        } else if modifiers.contains(.command) {
            toggleAlwaysHidden()
        } else if usesHiddenItemsBar {
            MenuBarHiddenItemsBar.shared.toggle(below: chevronFrame)
        } else {
            isCollapsed ? expand() : collapse()
        }
    }

    private func showChevronContextMenu() {
        let menu = createChevronContextMenu()
        if usesForwardedPrimaryAction, let frame = chevronFrame {
            let cocoa = AX.cocoaRect(fromAXRect: frame)
            menu.popUp(positioning: nil, at: CGPoint(x: cocoa.minX, y: cocoa.minY - 4), in: nil)
        } else {
            expandCollapseItem.popUpMenu(menu)
        }
    }

    func expand(inline: Bool = false) {
        guard isCollapsed, !isZenModeActive else { return }
        if usesHiddenItemsBar, !inline {
            MenuBarHiddenItemsBar.shared.show(below: chevronFrame)
            return
        }
        isCollapsed = false
        isEditing = false
        isAlwaysHiddenExpanded = false
        lastMenuOpenSeen = .distantPast

        updateItems()
        configureAutoRehide()
        hideApplicationMenusIfCrowded()
    }

    private func collapse() {
        MenuBarHiddenItemsBar.shared.close()
        isCollapsed = true
        isAlwaysHiddenExpanded = false
        isEditing = false
        updateItems()
        stopAutoRehide()
        restoreApplicationMenus()
    }

    func collapseFromGesture() {
        guard !isCollapsed, !isEditing else { return }
        collapse()
    }

    private func toggleAlwaysHidden() {
        isAlwaysHiddenExpanded.toggle()
        updateItems()
    }

    @objc private func enterEditMode() {
        if isZenModeActive { setZenMode(false) }
        isEditing = true
        isCollapsed = false
        isAlwaysHiddenExpanded = true
        updateItems()
        stopAutoRehide()
    }

    // MARK: - Public Toggles (hotkeys, search, menus)

    @objc func toggleHiddenSection() {
        if isZenModeActive { setZenMode(false) }
        isCollapsed ? expand() : collapse()
    }

    @objc func toggleAlwaysHiddenSection() {
        guard alwaysHiddenItem != nil else {
            toggleHiddenSection()
            return
        }
        if isZenModeActive { setZenMode(false) }
        if isCollapsed {
            expand()
            isAlwaysHiddenExpanded = true
            updateItems()
        } else {
            toggleAlwaysHidden()
        }
    }

    @objc func toggleZenMode() {
        setZenMode(!isZenModeActive)
    }

    func setZenMode(_ enabled: Bool) {
        isZenModeAutomatic = false
        applyZenMode(enabled)
    }

    func setAutomaticZenMode(_ engaged: Bool) {
        if engaged {
            guard !isZenModeActive else { return }
            applyZenMode(true)
            isZenModeAutomatic = true
        } else {
            guard isZenModeAutomatic else { return }
            isZenModeAutomatic = false
            applyZenMode(false)
        }
    }

    private func applyZenMode(_ enabled: Bool) {
        guard isZenModeActive != enabled else { return }
        isZenModeActive = enabled
        if enabled {
            isConditionRevealed = false
            collapse()
        }
        updateAllItemVisuals()
    }

    func showAlwaysHiddenSection() {
        guard !isZenModeActive, alwaysHiddenItem != nil else { return }
        if isCollapsed { expand() }
        guard !isAlwaysHiddenExpanded else { return }
        isAlwaysHiddenExpanded = true
        updateItems()
    }

    func revealAllSections(then completion: @escaping @MainActor () -> Void) {
        if isZenModeActive { setZenMode(false) }
        rehideGraceUntil = Date().addingTimeInterval(2)
        let wasFullyShown = !isCollapsed && (isAlwaysHiddenExpanded || alwaysHiddenItem == nil)
        if isCollapsed { expand(inline: true) }
        if alwaysHiddenItem != nil, !isAlwaysHiddenExpanded {
            isAlwaysHiddenExpanded = true
            updateItems()
        }
        guard !wasFullyShown else {
            completion()
            return
        }
        MenuBarItemCatalog.shared.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainActor.assumeIsolated { completion() }
        }
    }

    // MARK: - UI Updates

    private var dividerImage: NSImage? {
        NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Separator")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 5, weight: .light))
    }

    private func updateItems() {
        guard usesRestriction else {
            updateDividerItems()
            finishItemsUpdate()
            return
        }

        learnGeneration += 1
        let generation = learnGeneration
        guard separatorItem.length > 0 || (alwaysHiddenItem?.length ?? 0) > 0 else {
            updateAgentHostedItems()
            finishItemsUpdate()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let drawn = MenuBarAgentHost.drawnItems()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.learnGeneration else { return }
                    if let drawn, !self.isLearningLayout { self.learnSections(from: drawn) }
                    self.updateAgentHostedItems()
                    self.finishItemsUpdate()
                }
            }
        }
    }

    private func finishItemsUpdate() {
        updateExpandCollapseIcon()
        MenuBarItemCatalog.shared.invalidate()
        NotificationCenter.default.post(name: .menuBarHidingStateDidChange, object: nil)
    }

    private func updateDividerItems() {
        let showDividers = statusSettings.showSectionDividers
        let hideControlIcon = statusSettings.hideMenuBarIcon
        let image = dividerImage

        expandCollapseItem.length = hideControlIcon ? 0 : Lengths.standard
        separatorItem.isVisible = true
        alwaysHiddenItem?.isVisible = true

        if isEditing {
            setLength(Lengths.separator, on: separatorItem)
            separatorItem.button?.image = image
            setLength(Lengths.separator, on: alwaysHiddenItem)
            alwaysHiddenItem?.button?.image = image
        } else if isCollapsed && !hideControlIcon {
            setLength(collapsedLength(for: separatorItem), on: separatorItem)
            separatorItem.button?.image = showDividers ? image : nil
            if let alwaysHiddenItem { setLength(collapsedLength(for: alwaysHiddenItem), on: alwaysHiddenItem) }
            alwaysHiddenItem?.button?.image = nil
        } else {
            setLength(showDividers ? Lengths.separator : 0, on: separatorItem)
            separatorItem.button?.image = showDividers ? image : nil
            if isAlwaysHiddenExpanded {
                setLength(showDividers ? Lengths.separator : 0, on: alwaysHiddenItem)
                alwaysHiddenItem?.button?.image = showDividers ? image : nil
            } else {
                if let alwaysHiddenItem { setLength(collapsedLength(for: alwaysHiddenItem), on: alwaysHiddenItem) }
                alwaysHiddenItem?.button?.image = nil
            }
        }
        if isAgentHosted { fittedDivider.scheduleFit() }
    }

    private func collapsedLength(for item: NSStatusItem) -> CGFloat {
        isAgentHosted ? fittedDivider.collapsedLength(for: item) : Lengths.collapsed
    }

    private func setLength(_ length: CGFloat, on item: NSStatusItem?) {
        guard let item, item.length != length else { return }
        item.length = length
    }

    private lazy var fittedDivider = MenuBarFittedDivider(
        minimumLength: Lengths.separator,
        target: { [unowned self] in
            guard !self.isEditing else { return nil }
            if self.isCollapsed && !self.statusSettings.hideMenuBarIcon { return self.separatorItem }
            return self.isAlwaysHiddenExpanded ? nil : self.alwaysHiddenItem
        }
    )

    // MARK: - MenuBarAgent Hosting (macOS 27)

    private nonisolated static let menuBarAgentBundleID = MenuBarAgentHost.bundleIdentifier

    private var isAgentHosted = StatusBarController.detectAgentHost()
    private var agentHostObservers: [NSObjectProtocol] = []
    private var usesForwardedPrimaryAction = false
    private var isLearningLayout = false
    private nonisolated let secondaryClickState = OSAllocatedUnfairLock(initialState: SecondaryClickState())

    private struct SecondaryClickState {
        var chevronFrame: CGRect?
        var swallowingUp = false
    }

    private var restrictionFailed = false

    private var usesRestriction: Bool {
        isAgentHosted && MenuBarVisibilityRestrictor.isUsable && !restrictionFailed
    }

    private var usesHiddenItemsBar: Bool {
        usesRestriction && SettingsModel.shared.current.menuBarUseHiddenItemsBar
    }

    private var chevronFrame: CGRect? {
        lastDrawnItems.first { $0.ownIdentifier == AutosaveKeys.expandCollapse }?.frame
    }

    private nonisolated static func detectAgentHost() -> Bool {
        MenuBarAgentHost.isActive
    }

    private func observeAgentHost() {
        guard agentHostObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            agentHostObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == StatusBarController.menuBarAgentBundleID else { return }
                MainActor.assumeIsolated { self?.refreshAgentHost() }
            })
        }
    }

    private func refreshAgentHost() {
        let hosted = Self.detectAgentHost()
        guard hosted != isAgentHosted else {
            if hosted { updateItems() }
            return
        }
        isAgentHosted = hosted
        hosted ? startAgentHosting() : stopAgentHosting()
        updateItems()
    }

    private func startAgentHosting() {
        if usesForwardedPrimaryAction, secondaryClickToken == nil {
            let mask = (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue)
            secondaryClickToken = GlobalEventTap.shared.register(
                name: "MenuBarChevronSecondaryClick",
                mask: CGEventMask(mask),
                priority: EventTapPriority.filter
            ) { [weak self] type, event in
                self?.handleSecondaryClick(type: type, event: event) ?? .pass
            }
        }
        refreshDrawnItems(after: 0.5)

        guard usesRestriction else {
            fittedDivider.start()
            updateItems()
            return
        }
        if sectionsObserver == nil {
            sectionsObserver = NotificationCenter.default.addObserver(forName: .menuBarSectionsDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyRestriction() }
            }
        }
        guard !MenuBarSectionStore.shared.hasLearnedLayout else {
            updateItems()
            return
        }
        isLearningLayout = true
        updateItems()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isLearningLayout else { return }
                self.isLearningLayout = false
                self.updateItems()
            }
        }
    }

    private func stopAgentHosting() {
        fittedDivider.stop()
        learnGeneration += 1
        isLearningLayout = false
        if let sectionsObserver {
            NotificationCenter.default.removeObserver(sectionsObserver)
            self.sectionsObserver = nil
        }
        if let secondaryClickToken {
            GlobalEventTap.shared.unregister(secondaryClickToken)
            self.secondaryClickToken = nil
        }
        MenuBarVisibilityRestrictor.shared.releaseAll()
    }

    private var concealedSections: Set<MenuBarSectionKind> {
        guard !isEditing, !isLearningLayout else { return [] }
        if isCollapsed && !statusSettings.hideMenuBarIcon { return [.hidden, .alwaysHidden] }
        return alwaysHiddenItem != nil && !isAlwaysHiddenExpanded ? [.alwaysHidden] : []
    }

    private func updateAgentHostedItems() {
        let showDividers = statusSettings.showSectionDividers || isEditing || isLearningLayout
        let concealed = concealedSections
        let image = dividerImage

        expandCollapseItem.length = statusSettings.hideMenuBarIcon ? 0 : Lengths.standard
        separatorItem.isVisible = true
        alwaysHiddenItem?.isVisible = true

        let separatorShown = showDividers && !concealed.contains(.hidden)
        setLength(separatorShown ? Lengths.separator : 0, on: separatorItem)
        separatorItem.button?.image = separatorShown ? image : nil

        let alwaysHiddenShown = showDividers && !concealed.contains(.alwaysHidden)
        setLength(alwaysHiddenShown ? Lengths.separator : 0, on: alwaysHiddenItem)
        alwaysHiddenItem?.button?.image = alwaysHiddenShown ? image : nil

        applyRestriction()
        refreshDrawnItems(after: 0.5)
        if MenuBarVisibilityRestrictor.shared.isRestricting { scheduleControlItemPlacementCheck() }
    }

    private func applyRestriction() {
        guard isAgentHosted else { return }
        let store = MenuBarSectionStore.shared
        let keys = concealedSections.reduce(into: Set<String>()) { $0.formUnion(store.keys(in: $1)) }
        MenuBarVisibilityRestrictor.shared.conceal(keys)
    }

    private func learnSections(from drawn: [MenuBarAgentHost.DrawnItem]) {
        let items = labelOwnItems(drawn)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let agentPID = MenuBarAgentHost.agentPID
        guard let separator = items.first(where: { $0.ownIdentifier == AutosaveKeys.separator }) else { return }
        let alwaysHidden = alwaysHiddenItem == nil ? nil : items.first { $0.ownIdentifier == AutosaveKeys.alwaysHidden }

        var names: [String: String] = [:]
        let placements: [MenuBarSectionClassifier.Placement] = items.compactMap { item in
            guard item.ownerPID != ownPID else { return nil }
            let key: String
            if item.ownerPID == agentPID {
                guard let system = item.systemIdentifier.flatMap(MenuBarSystemItem.init(menuExtraIdentifier:)) else { return nil }
                key = system.key
            } else {
                let app = NSRunningApplication(processIdentifier: item.ownerPID)
                guard let bundleID = MenuBarSectionStore.key(for: app) else { return nil }
                key = bundleID
                names[bundleID] = app?.localizedName
            }
            return .init(key: key, midX: item.frame.midX)
        }

        let learned = MenuBarSectionClassifier.classify(
            placements,
            hiddenDividerMidX: separator.frame.midX,
            alwaysHiddenDividerMidX: alwaysHidden?.frame.midX
        )
        MenuBarSectionStore.shared.merge(learned, names: names)
    }

    private func labelOwnItems(_ drawn: [MenuBarAgentHost.DrawnItem]) -> [MenuBarAgentHost.DrawnItem] {
        let expected = [
            (alwaysHiddenItem, AutosaveKeys.alwaysHidden),
            (separatorItem, AutosaveKeys.separator),
            (expandCollapseItem, AutosaveKeys.expandCollapse),
        ].compactMap { item, identifier in (item?.length ?? 0) > 0 ? identifier : nil }
        return MenuBarAgentHost.labellingOwnItems(drawn, expected: expected)
    }

    private func refreshDrawnItems(after delay: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let drawn = MenuBarAgentHost.drawnItems() else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastDrawnItems = self.labelOwnItems(drawn)
                    let frame = self.chevronFrame
                    self.secondaryClickState.withLock { $0.chevronFrame = frame }
                }
            }
        }
    }

    private nonisolated func handleSecondaryClick(type: CGEventType, event: CGEvent) -> EventTapDecision {
        let location = event.location
        let isDown = type == .rightMouseDown
        let swallow: Bool = secondaryClickState.withLock { state in
            if isDown {
                guard let frame = state.chevronFrame, frame.contains(location) else { return false }
                state.swallowingUp = true
                return true
            }
            defer { state.swallowingUp = false }
            return state.swallowingUp
        }
        guard swallow else { return .pass }
        if isDown {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.showChevronContextMenu() }
            }
        }
        return .swallow
    }

    private func updateExpandCollapseIcon() {
        guard let button = expandCollapseItem.button else { return }
        if isZenModeActive {
            button.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Zen Mode")
            return
        }
        let style = statusSettings.controlItemIconStyle
        let symbolName = style.symbolName(isHidden: isCollapsed && !isEditing)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Toggle Hidden Items")
    }

    // MARK: - Control Item Recovery

    private func scheduleControlItemPlacementCheck() {
        guard !controlItemPlacementCheckPending else { return }
        controlItemPlacementCheckPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.controlItemPlacementCheckPending = false
                self.recoverControlItemIfParked()
            }
        }
    }

    private func recoverControlItemIfParked() {
        guard !statusSettings.hideMenuBarIcon else { return }
        guard !isAgentHosted else {
            recoverUndrawnControlItem()
            return
        }
        guard let window = expandCollapseItem.button?.window,
              window.frame.width > 0,
              Self.isParked(window.frame) else { return }

        if Date().timeIntervalSince(controlItemRecoveryWindowStart) > 60 {
            controlItemRecoveryWindowStart = Date()
            controlItemRecoveryAttempts = 0
        }
        guard controlItemRecoveryAttempts < 3 else { return }
        controlItemRecoveryAttempts += 1

        let reseed = controlItemRecoveryAttempts > 1
        print("[StatusBarController] Control item parked at \(window.frame); re-publishing (attempt \(controlItemRecoveryAttempts)\(reseed ? ", moved to the right end" : "")).")
        Self.republish(expandCollapseItem, position: reseed ? 0 : nil) { [weak self] in
            self?.scheduleControlItemPlacementCheck()
        }
    }

    private func recoverUndrawnControlItem() {
        if controlItemRecoveryAttempts == 0, chevronFrame != nil,
           Date().timeIntervalSince(lastDrawnItemsAt) < Self.drawnItemsFreshness {
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let drawn = MenuBarAgentHost.drawnItems() else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isAgentHosted, !self.statusSettings.hideMenuBarIcon else { return }
                    self.lastDrawnItems = self.labelOwnItems(drawn)
                    let frame = self.chevronFrame
                    self.secondaryClickState.withLock { $0.chevronFrame = frame }
                    guard frame == nil else {
                        self.controlItemRecoveryAttempts = 0
                        return
                    }
                    if MenuBarVisibilityRestrictor.shared.isRestricting {
                        self.fallBackToFittedDivider()
                        return
                    }

                    if Date().timeIntervalSince(self.controlItemRecoveryWindowStart) > 60 {
                        self.controlItemRecoveryWindowStart = Date()
                        self.controlItemRecoveryAttempts = 0
                    }
                    guard self.controlItemRecoveryAttempts < 3 else { return }
                    self.controlItemRecoveryAttempts += 1

                    let attempt = self.controlItemRecoveryAttempts
                    print("[StatusBarController] MenuBarAgent is not drawing the control item; recovery attempt \(attempt).")
                    if attempt == 1 {
                        MenuBarAgentHost.nudgeLayout(of: self.expandCollapseItem)
                        self.scheduleControlItemPlacementCheck()
                    } else {
                        Self.republish(self.expandCollapseItem, position: attempt > 2 ? 0 : nil) { [weak self] in
                            self?.scheduleControlItemPlacementCheck()
                        }
                    }
                }
            }
        }
    }

    private func fallBackToFittedDivider() {
        guard usesRestriction else { return }
        print("[StatusBarController] The visibility restriction hid Sapphire's control item; falling back to fitted dividers.")
        restrictionFailed = true
        learnGeneration += 1
        MenuBarVisibilityRestrictor.shared.releaseAll()
        MenuBarHiddenItemsBar.shared.close()
        fittedDivider.start()
        updateItems()
    }

    private static func isParked(_ frame: CGRect) -> Bool {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { screen in
            CGRect(x: screen.frame.minX, y: screen.frame.maxY - 50, width: screen.frame.width, height: 50).contains(center)
        }) else { return true }
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return false }
        let notchMinX = screen.frame.minX + left.maxX
        let notchMaxX = screen.frame.minX + right.minX
        return frame.maxX > notchMinX + 2 && frame.minX < notchMaxX - 2
    }

    private static func republish(_ item: NSStatusItem, position: Double?, then completion: @escaping @MainActor () -> Void) {
        let key = "NSStatusItem Preferred Position \(item.autosaveName as String)"
        let saved = position ?? (UserDefaults.standard.object(forKey: key) as? Double)
        item.isVisible = false
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                item.isVisible = true
                completion()
            }
        }
    }

    // MARK: - Application Menu Hiding

    private func hideApplicationMenusIfCrowded() {
        guard SettingsModel.shared.current.hideAppMenusWhenShowingItems,
              appWithHiddenMenus == nil,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main,
              !ActiveAppMonitor.shared.isScreenFullScreen(screen) else { return }

        appMenuHidingGeneration += 1
        let generation = appMenuHidingGeneration
        let pid = frontmost.processIdentifier
        let notch = Self.notchRectInAXSpace(of: screen)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MenuBarItemCatalog.shared.items(maxAge: 0) { items in
                guard let self, generation == self.appMenuHidingGeneration, !self.isCollapsed else { return }
                let leftmost = items.filter(\.isOnScreen).map(\.frame.minX).min() ?? .greatestFiniteMagnitude
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let menuFrame = MenuBarHitTest.applicationMenuFrame(pid: pid) else { return }
                    let crowdsMenus = leftmost - menuFrame.maxX < 40
                    let blockedByNotch = notch.map { leftmost >= $0.maxX - 1 && menuFrame.maxX > $0.minX - 60 } ?? false
                    guard crowdsMenus || blockedByNotch else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard generation == self.appMenuHidingGeneration, !self.isCollapsed else { return }
                            self.appWithHiddenMenus = frontmost
                            NSApp.activate()
                        }
                    }
                }
            }
        }
    }

    private func restoreApplicationMenus() {
        appMenuHidingGeneration += 1
        guard let app = appWithHiddenMenus else { return }
        appWithHiddenMenus = nil
        guard !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
        app.activate()
    }

    private static func notchRectInAXSpace(of screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return CGRect(x: screen.frame.minX + left.maxX, y: 0, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    // MARK: - Auto-Rehide Logic

    private func configureAutoRehide() {
        stopAutoRehide()

        guard statusSettings.autoRehide, !isCollapsed, !isEditing else { return }

        let strategy = statusSettings.rehideStrategy

        switch strategy {
        case "timed":
            let interval = statusSettings.tempShowInterval
            scheduleTimedRehide(after: interval)

        case "smart":
            startSmartRehideMonitoring()

        case "focusedApp":
            appFocusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                    self?.collapse()
                }
            }

        default:
            break
        }
    }

    private func scheduleTimedRehide(after interval: TimeInterval) {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isCollapsed else { return }
                if !self.collapseUnlessMenuOpen() { self.scheduleTimedRehide(after: 1) }
            }
        }
    }

    private func startSmartRehideMonitoring() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleSmartRehideTick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        smartRehideTimer = timer
    }

    private func handleSmartRehideTick() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) else { return }

        let menuBarBottom = screen.visibleFrame.maxY
        let buffer: CGFloat = 50
        if mouseLocation.y < menuBarBottom - buffer {
            collapseUnlessMenuOpen()
        }
    }

    @discardableResult
    private func collapseUnlessMenuOpen() -> Bool {
        let now = Date()
        guard now >= rehideGraceUntil else { return false }
        if Self.isAnyMenuOpen() {
            lastMenuOpenSeen = now
            return false
        }
        let keepOpen = statusSettings.keepOpenedItemsDelay
        guard keepOpen <= 0 || now.timeIntervalSince(lastMenuOpenSeen) >= keepOpen else { return false }
        collapse()
        return true
    }

    static func isAnyMenuOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let displays = activeDisplayBounds()
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == menuLevel,
                  (info[kCGWindowOwnerPID as String] as? Int) != ownPID else { return false }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return true }
            return bounds.height > 8 && displays.contains {
                $0.intersects(bounds) && bounds.minY >= $0.minY - 1 && bounds.minY <= $0.minY + 56
            }
        }
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    private func stopAutoRehide() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil

        smartRehideTimer?.invalidate()
        smartRehideTimer = nil

        if let observer = appFocusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appFocusObserver = nil
        }
    }

    private func isPointerInMenuBar() -> Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = CursorPosition.screen(containing: mouse) else { return false }
        let metrics = NotchDisplayMetrics.current(for: screen)
        return mouse.y >= screen.frame.maxY - metrics.menuBarHeight - NotchDisplayMetrics.menuBarSeparator
    }

    // MARK: - Context Menus

    private func createChevronContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Edit Menu Bar Items", action: #selector(enterEditMode), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Search Menu Bar Items…", action: #selector(openItemSearch), keyEquivalent: "").target = self
        let zenItem = NSMenuItem(title: "Zen Mode", action: #selector(toggleZenMode), keyEquivalent: "")
        zenItem.target = self
        zenItem.state = isZenModeActive ? .on : .off
        menu.addItem(zenItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Sapphire Setting", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sapphire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func createAppContextMenu() -> NSMenu {
        let menu = NSMenu()
        if statusSettings.hideMenuBarIcon {
            menu.addItem(withTitle: "Edit Menu Bar Items", action: #selector(enterEditMode), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Search Menu Bar Items…", action: #selector(openItemSearch), keyEquivalent: "").target = self
            let zenItem = NSMenuItem(title: "Zen Mode", action: #selector(toggleZenMode), keyEquivalent: "")
            zenItem.target = self
            zenItem.state = isZenModeActive ? .on : .off
            menu.addItem(zenItem)
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Preferences", action: #selector(openPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sapphire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openItemSearch() {
        MenuBarSearchPanelController.shared.toggle()
    }

    @objc private func openPreferences() {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}