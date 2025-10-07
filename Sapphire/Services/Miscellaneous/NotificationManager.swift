//
//  NotificationManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-07
//

import SwiftUI
import Foundation
import Combine
import AppKit
import SQLite

struct NotificationPayload: Identifiable, Equatable {
    let id: String
    let appIdentifier: String
    let title: String
    let body: String
    let date: Date
    let appIcon: NSImage?

    var hasAudioAttachment: Bool { body.contains("Audio Message") || body.contains("sent an audio message") }
    var hasImageAttachment: Bool { body.contains("sent an image") }

    var appName: String {
        switch appIdentifier {
        case "com.apple.iChat": return "Messages"
        case "com.apple.facetime": return "FaceTime"
        case "com.apple.sharingd": return "AirDrop"
        default: return appIdentifier.split(separator: ".").last.map(String.init) ?? "Notification"
        }
    }

    static func == (lhs: NotificationPayload, rhs: NotificationPayload) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - iMessage Interaction Logic

class iMessageActionManager {

    static let shared = iMessageActionManager()

    private init() {}

    // MARK: - Public API

    func replyToLastMessage() {
        if !NSWorkspace.shared.launchApplication("Messages") {
            print("iMessageActionManager: Could not launch Messages.app")
        }
    }

    func markConversationAsRead(senderName: String) {
        let sanitizedSenderName = senderName.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Messages"
            try
                set targetChat to first chat whose name is "\(sanitizedSenderName)"
                mark targetChat as read
            on error
                -- Fail silently if chat isn't found by name.
            end try
        end tell
        """
        _runAppleScript(script)
    }

    func playLatestAudioMessage() {
        guard let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            replyToLastMessage() // Fallback
            return
        }

        let attachmentsPath = libraryDir.appendingPathComponent("Messages/Attachments")

        do {
            let allFiles = try FileManager.default.contentsOfDirectory(at: attachmentsPath, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)

            let latestAudioFile = allFiles
                .filter { $0.pathExtension.lowercased() == "caf" }
                .max { (url1, url2) -> Bool in
                    do {
                        let date1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                        let date2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                        return date1 < date2
                    } catch { return false }
                }

            if let fileURL = latestAudioFile {
                print("iMessageActionManager: Found latest audio message at \(fileURL.path). Playing...")
                NSWorkspace.shared.open(fileURL)
            } else {
                print("iMessageActionManager: Could not find a recent audio message. Opening Messages.app as a fallback.")
                replyToLastMessage()
            }
        } catch {
            print("iMessageActionManager: Error searching for attachments: \(error). Opening Messages.app as fallback.")
            replyToLastMessage()
        }
    }

    // MARK: - Private Helpers

    private func _runAppleScript(_ script: String) {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let err = error {
                print("iMessageActionManager: AppleScript Error: \(err)")
            }
        }
    }
}

class NotificationManager: ObservableObject {

    @Published var latestNotification: NotificationPayload?

    private var frequency: TimeInterval = 2.0 // Set to a low interval for responsiveness
    private var isSilent: Bool = false
    private var dbPath: String?
    private var dbConnection: Connection?
    private var timer: Timer?

    private var lastNotificationId: Int64 = 0
    private var lastNotificationDate: Double = 0.0

    init(frequency: TimeInterval = 2.0, silent: Bool = true) { // Default to silent for app integration
        self.frequency = frequency
        self.isSilent = silent
        if !isSilent { print("NotificationManager: Starting up...") }
        setupDatabaseConnection()
        startScheduler()
    }

    deinit {
        timer?.invalidate()
        if !isSilent { print("NotificationManager: Scheduler stopped.") }
    }

    func dismissLatestNotification() {
        DispatchQueue.main.async { self.latestNotification = nil }
    }

    private func setupDatabaseConnection() {
        let fileManager = FileManager.default

        let homeDirectory = NSHomeDirectory()
        let sequoiaPath = "\(homeDirectory)/Library/Group Containers/group.com.apple.usernoted/db2/db"

        if fileManager.fileExists(atPath: sequoiaPath) {
            self.dbPath = sequoiaPath
        } else {
            do {
                let darwinUserDir = try subprocess(path: "/usr/bin/getconf", args: ["DARWIN_USER_DIR"]).trimmingCharacters(in: .whitespacesAndNewlines)
                let primaryLegacyPath = "\(darwinUserDir)com.apple.NotificationCenter/db2/db"
                let fallbackLegacyPath = "\(darwinUserDir)com.apple.notificationcenter/db2/db"
                if fileManager.fileExists(atPath: primaryLegacyPath) { self.dbPath = primaryLegacyPath }
                else if fileManager.fileExists(atPath: fallbackLegacyPath) { self.dbPath = fallbackLegacyPath }
            } catch {
                if !isSilent { print("Could not get DARWIN_USER_DIR for legacy paths: \(error)") }
            }
        }

        guard let validPath = self.dbPath else {
            print("Error: Could not locate the Notification Center database at any known path.")
            return
        }

        do {
            dbConnection = try Connection(validPath, readonly: true)
            if !isSilent { print("Successfully connected to notification database at: \(validPath)") }
            if let lastRecord = getLastNotificationFromDB() {
                self.lastNotificationId = lastRecord.id
                self.lastNotificationDate = lastRecord.date
            }
        } catch {
            print("Error setting up database connection to \(validPath): \(error)")
        }
    }

    private func startScheduler() {
        guard dbConnection != nil else { return }
        if !isSilent { print("Starting scheduler...") }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: frequency, repeats: true) { [weak self] _ in self?.check() }
    }

    @objc private func check() {
        do {
            guard let db = dbConnection else { return }
            let recordTable = Table("record")
            let recId = Expression<Int64>("rec_id")
            let deliveredDate = Expression<Double?>("delivered_date")
            let requestDate = Expression<Double?>("request_date")
            let data = Expression<Data>("data")
            let query = recordTable.select(recId, data, deliveredDate, requestDate)
                                  .where(recId > lastNotificationId && (deliveredDate ?? requestDate) >= lastNotificationDate)
                                  .order(recId.desc)
            var notificationsToPublish: [NotificationPayload] = []
            for row in try db.prepare(query) {
                let id = row[recId]
                let plistData = row[data]
                let dateValue = row[deliveredDate] ?? row[requestDate] ?? 0
                if let notification = parseNotification(from: plistData, id: id, dateValue: dateValue) {
                    notificationsToPublish.append(notification)
                }
            }
            if let newest = notificationsToPublish.first {
                self.lastNotificationId = Int64(newest.id) ?? self.lastNotificationId
                self.lastNotificationDate = newest.date.timeIntervalSinceReferenceDate
            }
            for notification in notificationsToPublish.reversed() {
                self.latestNotification = notification
            }
        } catch {
            print("Failed to check for notifications: \(error)")
        }
    }

    private func parseNotification(from rawPlist: Data, id: Int64, dateValue: Double) -> NotificationPayload? {
        do {
            guard let plist = try PropertyListSerialization.propertyList(from: rawPlist, options: [], format: nil) as? [String: Any],
                  let appIdentifier = plist["app"] as? String,
                  let request = plist["req"] as? [String: Any] else { return nil }

            let title = request["titl"] as? String ?? ""
            let subtitle = request["subt"] as? String ?? ""
            let body = request["body"] as? String ?? ""
            let combinedBody = subtitle.isEmpty ? body : "\(subtitle)—\(body)"
            let date = Date(timeIntervalSinceReferenceDate: dateValue)
            let appIcon = getAppIcon(for: appIdentifier)

            return NotificationPayload(
                id: String(id), appIdentifier: appIdentifier, title: title, body: combinedBody, date: date, appIcon: appIcon
            )
        } catch {
            print("Error parsing plist data: \(error)")
            return nil
        }
    }

    private func getAppIcon(for identifier: String) -> NSImage? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return nil
    }

    private func getLastNotificationFromDB() -> (id: Int64, date: Double)? {
        guard let db = dbConnection else { return nil }
        do {
            let record = Table("record")
            let recId = Expression<Int64>("rec_id")
            let deliveredDate = Expression<Double?>("delivered_date")
            let requestDate = Expression<Double?>("request_date")
            if let lastRow = try db.pluck(record.order(recId.desc)) {
                let id = try lastRow.get(recId)
                let date = try lastRow.get(deliveredDate) ?? lastRow.get(requestDate) ?? 0.0
                return (id, date)
            }
        } catch {
            print("Could not get last notification ID: \(error)")
        }
        return nil
    }

    private func subprocess(path: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}