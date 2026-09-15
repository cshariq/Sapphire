//
//  Accessibility.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import AppKit
import ApplicationServices
import os

// MARK: - 1. Global AX messaging timeout

enum AccessibilityMessaging {

    static let defaultTimeout: Float = 0.25

    private static var didInstall = false

    static func installGlobalDefault() {
        guard !didInstall else { return }
        didInstall = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), defaultTimeout)
    }
}

// MARK: - 2. Permission

enum AccessibilityPermission {

    static var isProcessTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var isTrusted: Bool {
        AccessibilityTrustMonitor.isCurrentlyTrusted()
    }

    @discardableResult
    static func prompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSystemSettings() {
        SystemPreferencesPane.accessibility.open()
    }

    static func request() {
        if !prompt() {
            openSystemSettings()
        }
    }
}

// MARK: - 3. Runtime trust monitor (event-based)

@MainActor
final class AccessibilityTrustMonitor {
    static let shared = AccessibilityTrustMonitor()

    static let trustDidChange = Notification.Name("AccessibilityTrustMonitor.trustDidChange")

    private static let accessibilityAPIDidChange = NSNotification.Name("com.apple.accessibility.api")

    struct Registration {
        let name: String
        let teardown: () -> Void
        let reinstall: () -> Void
    }

    private let registryLock = NSLock()
    nonisolated(unsafe) private var registrations: [String: Registration] = [:]
    private var accessibilityObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var isStarted = false
    nonisolated private static let trustState = OSAllocatedUnfairLock(initialState: false)
    var isTrusted: Bool { Self.isCurrentlyTrusted() }
    private var debounceTask: Task<Void, Never>?

    private init() {
        let initial = AccessibilityPermission.isProcessTrusted
        Self.trustState.withLock { $0 = initial }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.accessibilityAPIDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDebouncedRefresh() }
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDebouncedRefresh() }
        }

        refreshTrust()
    }

    nonisolated func register(name: String, teardown: @escaping () -> Void, reinstall: @escaping () -> Void) {
        registryLock.lock()
        registrations[name] = Registration(name: name, teardown: teardown, reinstall: reinstall)
        registryLock.unlock()
    }

    nonisolated func unregister(name: String) {
        registryLock.lock()
        registrations.removeValue(forKey: name)
        registryLock.unlock()
    }

    nonisolated static func isCurrentlyTrusted() -> Bool {
        trustState.withLock { $0 }
    }

    private func scheduleDebouncedRefresh() {
        let current = AccessibilityPermission.isProcessTrusted
        if current != Self.isCurrentlyTrusted() {
            if !current {
                debounceTask?.cancel()
                refreshTrust()
                return
            }
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshTrust()
            self?.debounceTask = nil
        }
    }

    private func refreshTrust() {
        let trusted = AccessibilityPermission.isProcessTrusted
        guard trusted != Self.isCurrentlyTrusted() else { return }
        Self.trustState.withLock { $0 = trusted }

        registryLock.lock()
        let snapshot = Array(registrations.values)
        registryLock.unlock()

        if trusted {
            print("[AccessibilityTrustMonitor] Accessibility permission granted — reinstalling event taps.")
            for registration in snapshot {
                registration.reinstall()
            }
        } else {
            print("[AccessibilityTrustMonitor] Accessibility permission revoked — disabling all event taps so input is not swallowed.")
            for registration in snapshot {
                registration.teardown()
            }
        }

        NotificationCenter.default.post(
            name: Self.trustDidChange,
            object: nil,
            userInfo: ["trusted": trusted]
        )

        if !trusted {
            print("[AccessibilityTrustMonitor] Quitting: accessibility permission was revoked while the app was running.")
            NSApp.terminate(nil)
        }
    }
}

extension AccessibilityTrustMonitor {
    nonisolated func register<Owner: AnyObject>(
        name: String,
        owner: Owner,
        teardown: @escaping @MainActor (Owner) -> Void,
        reinstall: @escaping @MainActor (Owner) -> Void = { _ in }
    ) {
        register(name: name) { [weak owner] in
            MainActor.assumeIsolated {
                if let owner { teardown(owner) }
            }
        } reinstall: { [weak owner] in
            MainActor.assumeIsolated {
                if let owner { reinstall(owner) }
            }
        }
    }
}

@MainActor
protocol AccessibilityTrustProviding: AnyObject {
    var isTrusted: Bool { get }
    func refresh()
}

@MainActor
final class AccessibilityPermissionService: AccessibilityTrustProviding {
    private(set) var isTrustedCached: Bool

    var onTrustChanged: ((Bool) -> Void)?

    private var trustObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "AccessibilityPermissionService")

    var refreshDidFinish: (() -> Void)?

    init() {
        self.isTrustedCached = AccessibilityPermission.isProcessTrusted
    }

    var isTrusted: Bool {
        AccessibilityTrustMonitor.shared.isTrusted
    }

    func refresh() {
        let current = AccessibilityTrustMonitor.shared.isTrusted
        guard current != isTrustedCached else {
            refreshDidFinish?()
            return
        }
        isTrustedCached = current
        logger.info("Accessibility trust refreshed: \(current ? "granted" : "revoked")")
        onTrustChanged?(current)
        refreshDidFinish?()
    }

    func start() {
        guard trustObserver == nil else { return }
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleDebouncedRefresh()
            }
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let observer = trustObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            trustObserver = nil
        }
    }

    private func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.refresh()
            self.debounceTask = nil
        }
    }

    @discardableResult
    func promptForTrust() -> Bool {
        AccessibilityPermission.prompt()
    }

    func openSystemSettings() {
        AccessibilityPermission.openSystemSettings()
    }

    func requestAccess() {
        AccessibilityPermission.request()
    }
}

// MARK: - 4. Element access

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

enum AX {

    // MARK: Setup

    static func installGlobalMessagingTimeout() {
        AccessibilityMessaging.installGlobalDefault()
    }

    // MARK: Elements

    static var systemWide: AXUIElement {
        AXUIElementCreateSystemWide()
    }

    static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func frontmostApplicationElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return application(pid: app.processIdentifier)
    }

    static func setMessagingTimeout(_ seconds: Float, on element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    static func identity(of element: AXUIElement) -> String {
        String(format: "ax:%lx", CFHash(element))
    }

    // MARK: Receive — raw

    static func rawValue(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func attributeStatus(_ attribute: String, of element: AXUIElement) -> AXError {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    }

    static func isAlive(_ element: AXUIElement) -> Bool {
        attributeStatus(kAXPositionAttribute as String, of: element) == .success
    }

    static func isSettable(_ attribute: String, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return status == .success && settable.boolValue
    }

    // MARK: Receive — typed

    static func string(_ attribute: String, of element: AXUIElement) -> String? {
        rawValue(attribute, of: element) as? String
    }

    static func bool(_ attribute: String, of element: AXUIElement) -> Bool? {
        (rawValue(attribute, of: element) as? NSNumber)?.boolValue
    }

    static func int(_ attribute: String, of element: AXUIElement) -> Int? {
        (rawValue(attribute, of: element) as? NSNumber)?.intValue
    }

    static func url(_ attribute: String, of element: AXUIElement) -> URL? {
        guard let value = rawValue(attribute, of: element),
              CFGetTypeID(value) == CFURLGetTypeID() else {
            return nil
        }
        return (value as! CFURL) as URL
    }

    static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = rawValue(attribute, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func elements(_ attribute: String, of element: AXUIElement) -> [AXUIElement] {
        rawValue(attribute, of: element) as? [AXUIElement] ?? []
    }

    static func elements(_ attribute: String, of element: AXUIElement, limit: Int) -> [AXUIElement] {
        var raw: CFArray?
        guard AXUIElementCopyAttributeValues(element, attribute as CFString, 0, CFIndex(limit), &raw) == .success,
              let values = raw as? [AXUIElement] else {
            return []
        }
        return values
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        elements(kAXChildrenAttribute as String, of: element)
    }

    static func selectedChildren(of element: AXUIElement) -> [AXUIElement] {
        elements(kAXSelectedChildrenAttribute as String, of: element)
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        self.element(kAXParentAttribute as String, of: element)
    }

    static func role(of element: AXUIElement) -> String? {
        string(kAXRoleAttribute as String, of: element)
    }

    static func subrole(of element: AXUIElement) -> String? {
        string(kAXSubroleAttribute as String, of: element)
    }

    static func title(of element: AXUIElement) -> String? {
        string(kAXTitleAttribute as String, of: element)
    }

    // MARK: Receive — geometry

    static func point(_ attribute: String, of element: AXUIElement) -> CGPoint? {
        guard let value = rawValue(attribute, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ attribute: String, of element: AXUIElement) -> CGSize? {
        guard let value = rawValue(attribute, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    static func rect(_ attribute: String, of element: AXUIElement) -> CGRect? {
        guard let value = rawValue(attribute, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func range(_ attribute: String, of element: AXUIElement) -> CFRange? {
        guard let value = rawValue(attribute, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        rect("AXFrame", of: element)
    }

    static func windowFrame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(kAXPositionAttribute as String, of: element),
              let size = size(kAXSizeAttribute as String, of: element) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    static func rect(_ attribute: String, of element: AXUIElement, range: CFRange) -> CGRect? {
        var mutableRange = range
        guard let parameter = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    // MARK: Receive — focus & hit-testing

    static func focusedUIElement() -> AXUIElement? {
        if let systemFocused = element(kAXFocusedUIElementAttribute as String, of: systemWide) {
            return systemFocused
        }
        guard let appElement = frontmostApplicationElement() else { return nil }
        return element(kAXFocusedUIElementAttribute as String, of: appElement)
    }

    static func focusedUIElement(ofApplication appElement: AXUIElement) -> AXUIElement? {
        element(kAXFocusedUIElementAttribute as String, of: appElement)
    }

    static func focusedWindow(ofApplication appElement: AXUIElement) -> AXUIElement? {
        element(kAXFocusedWindowAttribute as String, of: appElement)
    }

    static func mainWindow(ofApplication appElement: AXUIElement) -> AXUIElement? {
        element(kAXMainWindowAttribute as String, of: appElement)
    }

    static func element(atAXPoint axPoint: CGPoint, timeout: Float? = nil) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(axPoint.x),
            Float(axPoint.y),
            &hit
        ) == .success, let hit else {
            return nil
        }
        if let timeout { setMessagingTimeout(timeout, on: hit) }
        return hit
    }

    static func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        while let node = current {
            if role(of: node) == (kAXWindowRole as String) { return node }
            current = parent(of: node)
        }
        return nil
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func frontmostAppHasSecureTextFieldFocused() -> Bool {
        guard AccessibilityTrustMonitor.isCurrentlyTrusted(),
              let appElement = frontmostApplicationElement(),
              let focused = focusedUIElement(ofApplication: appElement) else {
            return false
        }
        return subrole(of: focused) == (kAXSecureTextFieldSubrole as String)
    }

    // MARK: Send — actions & attributes

    @discardableResult
    static func perform(_ action: String, on element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    @discardableResult
    static func set(_ attribute: String, to value: CFTypeRef, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func set(_ attribute: String, to flag: Bool, on element: AXUIElement) -> Bool {
        set(attribute, to: flag ? kCFBooleanTrue : kCFBooleanFalse, on: element)
    }

    @discardableResult
    static func set(_ attribute: String, toPoint point: CGPoint, on element: AXUIElement) -> Bool {
        var value = point
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return false }
        return set(attribute, to: axValue, on: element)
    }

    @discardableResult
    static func set(_ attribute: String, toSize size: CGSize, on element: AXUIElement) -> Bool {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return false }
        return set(attribute, to: axValue, on: element)
    }

    @discardableResult
    static func raise(_ window: AXUIElement) -> Bool {
        perform(kAXRaiseAction as String, on: window)
    }

    @discardableResult
    static func makeMainWindow(_ window: AXUIElement) -> Bool {
        set(kAXMainWindowAttribute as String, to: true, on: window)
    }

    @discardableResult
    static func setMinimized(_ minimized: Bool, on window: AXUIElement) -> Bool {
        set(kAXMinimizedAttribute as String, to: minimized, on: window)
    }

    @discardableResult
    static func close(_ window: AXUIElement) -> Bool {
        if perform("AXClose", on: window) { return true }
        guard let closeButton = element(kAXCloseButtonAttribute as String, of: window) else { return false }
        return perform(kAXPressAction as String, on: closeButton)
    }

    static func canSetFrame(on window: AXUIElement) -> Bool {
        isSettable(kAXPositionAttribute as String, of: window)
            && isSettable(kAXSizeAttribute as String, of: window)
    }

    @discardableResult
    static func setAXFrame(_ frame: CGRect, on window: AXUIElement) -> Bool {
        guard set(kAXPositionAttribute as String, toPoint: frame.origin, on: window) else { return false }
        return set(kAXSizeAttribute as String, toSize: frame.size, on: window)
    }

    @discardableResult
    static func setCocoaFrame(_ frame: CGRect, on window: AXUIElement) -> Bool {
        guard let axFrame = axRect(fromCocoaRect: frame) else { return false }
        return setAXFrame(axFrame, on: window)
    }

    // MARK: Coordinates — AX (top-left) ⇄ Cocoa (bottom-left)

    private static let displayHeightLock = NSLock()
    nonisolated(unsafe) private static var cachedPrimaryDisplayHeight: CGFloat = 0

    static func refreshPrimaryDisplayHeight() {
        let height: CGFloat
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            height = primary.frame.height
        } else {
            height = NSScreen.main?.frame.height ?? 0
        }
        displayHeightLock.lock()
        cachedPrimaryDisplayHeight = height
        displayHeightLock.unlock()
    }

    static var primaryDisplayHeight: CGFloat {
        displayHeightLock.lock()
        let cached = cachedPrimaryDisplayHeight
        displayHeightLock.unlock()
        if cached > 0 { return cached }

        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return NSScreen.main?.frame.height ?? 0
    }

    static func cocoaRect(fromAXRect rect: CGRect) -> CGRect {
        let height = primaryDisplayHeight
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axRect(fromCocoaRect rect: CGRect) -> CGRect? {
        let height = primaryDisplayHeight
        guard height > 0 else { return nil }
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axPoint(fromCocoaPoint point: CGPoint) -> CGPoint? {
        let height = primaryDisplayHeight
        guard height > 0 else { return nil }
        return CGPoint(x: point.x, y: height - point.y)
    }

    static func windowCocoaFrame(of window: AXUIElement) -> CGRect? {
        guard let axFrame = frame(of: window) else { return nil }
        return cocoaRect(fromAXRect: axFrame)
    }
}

// MARK: - 5. AX notification observers

final class AXObserverHandle {

    typealias Handler = (AXUIElement, String) -> Void

    private let observer: AXObserver
    private let handler: Handler
    private var attachedRunLoop: CFRunLoop?
    private var attachedMode: CFRunLoopMode?

    let pid: pid_t

    init?(pid: pid_t, handler: @escaping Handler) {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverTrampoline, &observer) == .success,
              let observer else {
            return nil
        }
        self.observer = observer
        self.handler = handler
        self.pid = pid
    }

    deinit {
        detach()
    }

    @discardableResult
    func observe(_ notification: String, on element: AXUIElement) -> Bool {
        let context = Unmanaged.passUnretained(self).toOpaque()
        return AXObserverAddNotification(observer, element, notification as CFString, context) == .success
    }

    @discardableResult
    func observe(_ notifications: [String], on element: AXUIElement) -> Int {
        notifications.reduce(into: 0) { count, name in
            if observe(name, on: element) { count += 1 }
        }
    }

    func attach(to runLoop: CFRunLoop = CFRunLoopGetMain(), mode: CFRunLoopMode = .commonModes) {
        guard attachedRunLoop == nil else { return }
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(observer), mode)
        attachedRunLoop = runLoop
        attachedMode = mode
    }

    func detach() {
        guard let runLoop = attachedRunLoop, let mode = attachedMode else { return }
        CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), mode)
        attachedRunLoop = nil
        attachedMode = nil
    }

    fileprivate func dispatch(element: AXUIElement, notification: String) {
        handler(element, notification)
    }
}

private func axObserverTrampoline(
    observer _: AXObserver,
    element: AXUIElement,
    notification: CFString,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let handle = Unmanaged<AXObserverHandle>.fromOpaque(context).takeUnretainedValue()
    handle.dispatch(element: element, notification: notification as String)
}