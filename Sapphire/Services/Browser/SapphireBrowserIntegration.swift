//
//  SapphireBrowserIntegration.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30.
//

import Foundation
import AppKit
import UserNotifications

@MainActor
final class SapphireBrowserIntegration {

    static let shared = SapphireBrowserIntegration()

    enum BridgeNotification {
        static let downloadedFile = "com.cshariq.sapphire.browserDownloadedFile"
        static let link = "com.cshariq.sapphire.browserLink"
        static let nowPlaying = "com.cshariq.sapphire.browserNowPlaying"
        static let nowPlayingStopped = "com.cshariq.sapphire.browserNowPlayingStopped"
        static let openURL = "com.cshariq.sapphire.browserOpenURL"
    }

    static let linkNotificationCategory = "SAPPHIRE_BROWSER_LINK"
    static let browserBundleID = "com.cshariq.sapphirebrowser"

    private var observers: [NSObjectProtocol] = []
    private var hasStarted = false

    private(set) var browserMedia: (title: String, isPlaying: Bool, url: URL?)?

    var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "SapphireBrowserIntegrationEnabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "SapphireBrowserIntegrationEnabled")
        }
    }

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        registerNotificationCategory()
        requestNotificationAuthorizationIfNeeded()

        let center = DistributedNotificationCenter.default()

        observers.append(center.addObserver(
            forName: Notification.Name(BridgeNotification.downloadedFile),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleDownloadedFile(notification)
        })

        observers.append(center.addObserver(
            forName: Notification.Name(BridgeNotification.link),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleLink(notification)
        })

        observers.append(center.addObserver(
            forName: Notification.Name(BridgeNotification.nowPlaying),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNowPlaying(notification)
        })

        observers.append(center.addObserver(
            forName: Notification.Name(BridgeNotification.nowPlayingStopped),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.browserMedia = nil
        })
    }

    // MARK: - Browser → Sapphire

    private func handleDownloadedFile(_ notification: Notification) {
        guard isEnabled else { return }
        let userInfo = notification.userInfo
        guard let path = userInfo?["path"] as? String,
              FileManager.default.fileExists(atPath: path) else { return }

        let url = URL(fileURLWithPath: path)
        MainActor.assumeIsolated {
            FileShelfManager.shared.addFiles(from: [url])
            postLocalNotification(
                title: "Saved to File Shelf",
                body: "\(url.lastPathComponent) from Sapphire Browser",
                category: nil,
                userInfo: nil
            )
        }
    }

    private func handleLink(_ notification: Notification) {
        guard isEnabled else { return }
        let userInfo = notification.userInfo
        guard let urlString = userInfo?["url"] as? String,
              let url = URL(string: urlString) else { return }

        let title = (userInfo?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.host ?? urlString
        let toShelf = (userInfo?["shelf"] as? Bool) ?? false

        MainActor.assumeIsolated {
            if toShelf {
                let safeName = title
                    .replacingOccurrences(of: "/", with: "-")
                    .prefix(60)
                FileShelfManager.shared.addText(url.absoluteString, named: String(safeName))
                postLocalNotification(
                    title: "Saved to File Shelf",
                    body: title,
                    category: nil,
                    userInfo: nil
                )
            } else {
                postLocalNotification(
                    title: "Link from Sapphire Browser",
                    body: title,
                    category: Self.linkNotificationCategory,
                    userInfo: ["url": url.absoluteString]
                )
            }
        }
    }

    private func handleNowPlaying(_ notification: Notification) {
        guard isEnabled else { return }
        let userInfo = notification.userInfo
        browserMedia = (
            title: userInfo?["title"] as? String ?? "",
            isPlaying: (userInfo?["playing"] as? Bool) ?? false,
            url: (userInfo?["url"] as? String).flatMap(URL.init(string:))
        )
    }

    // MARK: - Sapphire → Browser

    func openInBrowser(url: URL) {
        guard var components = URLComponents(string: "sapphirebrowser://open") else { return }
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let deepLink = components.url else { return }

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.browserBundleID) != nil {
            NSWorkspace.shared.open(deepLink)
        } else {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(BridgeNotification.openURL),
                object: nil,
                userInfo: ["url": url.absoluteString],
                options: [.deliverImmediately]
            )
            postLocalNotification(
                title: "Sapphire Browser isn't installed",
                body: "Install it to open \(url.host ?? "this link").",
                category: nil,
                userInfo: nil
            )
        }
    }

    // MARK: - Local notifications

    private func registerNotificationCategory() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_IN_BROWSER",
            title: "Open in Browser",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.linkNotificationCategory,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            case .denied:
                break
            default:
                break
            }
        }
    }

    private func postLocalNotification(title: String, body: String, category: String?, userInfo: [AnyHashable: Any]?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category {
            content.categoryIdentifier = category
        }
        if let userInfo {
            content.userInfo = userInfo
        }
        let request = UNNotificationRequest(
            identifier: "sapphire-browser-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Notification action handling

extension SapphireBrowserIntegration {
    func handleLinkNotificationResponse(_ response: UNNotificationResponse) {
        let action = response.actionIdentifier
        guard action == UNNotificationDefaultActionIdentifier || action == "OPEN_IN_BROWSER" else { return }
        guard let urlString = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: urlString) else { return }
        openInBrowser(url: url)
    }
}