//
//  UserWindowSupport.swift
//  Sapphire
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let sapphireHelperConnectionLost = Notification.Name("sapphireHelperConnectionLost")
}

enum SapphireStandardMenu {
    static func installIfNeeded() {
        guard NSApp.mainMenu == nil || !hasEditMenu else { return }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Quit Sapphire",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector("redo:"), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private static var hasEditMenu: Bool {
        NSApp.mainMenu?.items.contains { $0.title == "Edit" } == true
    }
}

enum UtilityWindowPresenter {
    /// Normal window level so other apps can appear above when focused.
    private static let elevatedWindowLevel = NSWindow.Level.normal

    /// Standard settings / lyrics windows behave like a normal app window.
    static func presentSettingsWindow(_ window: NSWindow) {
        activateAsRegularApp()
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .normal
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.center()

        // Defer ALL ordering to the next run loop so the
        // accessory → regular activation policy transition completes first.
        DispatchQueue.main.async {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func present(_ window: NSWindow) {
        activateAsRegularApp()
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.level = elevatedWindowLevel
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.center()

        // Defer ALL ordering to the next run loop so the
        // accessory → regular activation policy transition completes first.
        DispatchQueue.main.async {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func activateAsRegularApp() {
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
enum HelperAlertPresenter {
    private static var hostWindow: AlertHostWindow?
    private static var activeModalCount = 0

    static func showHelperConnectionLost(onDismiss: (() -> Void)? = nil) {
        presentModal(
            messageText: "Sapphire Helper Needs Attention",
            informativeText: """
            Sapphire lost connection to its system helper.

            1. Open System Settings → General → Login Items & Extensions
            2. Turn Background App Activity for Sapphire off, then on again
            3. Quit Sapphire completely (Sapphire → Quit Sapphire, or press ⌘Q)
            4. Reopen Sapphire
            """,
            alertStyle: .warning,
            buttonTitles: ["OK"]
        ) { _ in
            onDismiss?()
        }
    }

    static func presentModal(
        messageText: String,
        informativeText: String,
        alertStyle: NSAlert.Style = .warning,
        buttonTitles: [String],
        completion: @escaping (Int) -> Void
    ) {
        UtilityWindowPresenter.activateAsRegularApp()

        let host = acquireHostWindow()
        host.orderFrontRegardless()
        host.makeKeyAndOrderFront(nil)

        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = alertStyle
        for title in buttonTitles {
            alert.addButton(withTitle: title)
        }

        activeModalCount += 1

        DispatchQueue.main.async {
            alert.beginSheetModal(for: host) { response in
                releaseHostWindowIfIdle()
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                completion(index)
            }
        }
    }

    private static func acquireHostWindow() -> AlertHostWindow {
        if let hostWindow {
            return hostWindow
        }

        let window = AlertHostWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Sapphire"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.001
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.center()
        hostWindow = window
        return window
    }

    private static func releaseHostWindowIfIdle() {
        activeModalCount = max(0, activeModalCount - 1)
        guard activeModalCount == 0 else { return }
        hostWindow?.orderOut(nil)
        hostWindow = nil
    }
}

private final class AlertHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FocusableHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleStandardEditShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handleStandardEditShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else {
            return false
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let selector: Selector?
        switch key {
        case "c":
            selector = #selector(NSText.copy(_:))
        case "v":
            selector = #selector(NSText.paste(_:))
        case "x":
            selector = #selector(NSText.cut(_:))
        case "a":
            selector = #selector(NSText.selectAll(_:))
        case "z":
            selector = event.modifierFlags.contains(.shift) ? Selector("redo:") : Selector("undo:")
        default:
            selector = nil
        }

        guard let selector else { return false }
        return NSApp.sendAction(selector, to: nil, from: self)
    }
}
