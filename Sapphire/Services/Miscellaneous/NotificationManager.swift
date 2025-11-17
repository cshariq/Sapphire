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
import Contacts
import AVFoundation

struct NotificationPayload: Identifiable, Equatable {
    let id: String
    let appIdentifier: String
    let title: String
    let body: String
    let date: Date
    let appIcon: NSImage?

    var hasAudioAttachment: Bool {
        let lowerBody = body.lowercased()
        return lowerBody.contains("audio message") || lowerBody.contains("sent an audio message") || lowerBody.contains("audio file")
    }
    var hasImageAttachment: Bool {
        let lowerBody = body.lowercased()
        return lowerBody.contains("sent an image") || lowerBody.contains("image file")
    }

    var verificationCode: String? {
        let textToSearch = "\(title) \(body)"

        let patterns = [
            "G-(\\d{6})",
            "(\\d{3}-\\d{3})",
            "(?:code|pin|token|password|otp|verification|auth|security|passcode)(?: is | is: |: | be )?([a-zA-Z0-9]{4,8})",
            "([a-zA-Z0-9]{4,8}) is your",
            "\\b(\\d{6})\\b"
        ]

        for pattern in patterns {
            if let code = findCode(in: textToSearch, with: pattern) {
                return code.uppercased()
            }
        }

        return nil
    }

    var appName: String {
        switch appIdentifier {
        case "com.apple.iChat", "com.apple.MobileSMS": return "Messages"
        case "com.apple.facetime": return "FaceTime"
        case "com.apple.sharingd": return "AirDrop"
        default: return appIdentifier.split(separator: ".").last.map(String.init) ?? "Notification"
        }
    }

    private func findCode(in text: String, with pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: text) { return String(text[captureRange]) }
            }
        } catch { print("Verification code regex error: \(error)") }
        return nil
    }

    static func == (lhs: NotificationPayload, rhs: NotificationPayload) -> Bool {
        return lhs.id == rhs.id
    }
}

struct MessageAttachment {
    enum AttachmentType { case image, audio, other }
    let localURL: URL
    let originalMimeType: String
    var type: AttachmentType {
        if originalMimeType.starts(with: "image/") { return .image }
        if originalMimeType.starts(with: "audio/") { return .audio }
        let pathExtension = localURL.pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "tiff"]
        let audioExtensions = ["m4a", "mp3", "caf", "wav", "aiff"]
        if imageExtensions.contains(pathExtension) { return .image }
        if audioExtensions.contains(pathExtension) { return .audio }
        return .other
    }
}

enum TapbackType: String, CaseIterable {
    case love, like, dislike, laugh, emphasize, question
    var systemImage: String {
        switch self {
        case .love: return "heart.fill"; case .like: return "hand.thumbsup.fill"; case .dislike: return "hand.thumbsdown.fill"; case .laugh: return "face.smiling.inverse"; case .emphasize: return "exclamationmark.2"; case .question: return "questionmark"
        }
    }
}

class iMessageActionManager {
    static let shared = iMessageActionManager()
    private var audioPlayer: AVPlayer?
    private var chatDbConnection: Connection?
    private init() { setupChatDatabaseConnection() }
    private func setupChatDatabaseConnection() {
        let chatDbPath = ("~/Library/Messages/chat.db" as NSString).expandingTildeInPath
        do { chatDbConnection = try Connection(chatDbPath, readonly: true) } catch { print("iMessageActionManager: ERROR: Could not connect to chat.db: \(error)") }
    }
    func sendMessage(_ message: String, to recipientName: String) {
        Task(priority: .userInitiated) {
            let contactIdentifiers = await _getContactIdentifiers(forName: recipientName)
            guard !contactIdentifiers.isEmpty else { return }
            let identifiersString = contactIdentifiers.map { "\"\($0)\"" }.joined(separator: ", ")
            let sanitizedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
            let scriptTemplate = """
            tell application "Messages"
                set identifierList to {%@}
                set messageSent to false
                repeat with anIdentifier in identifierList
                    if not messageSent then
                        try
                            send "%@" to participant anIdentifier
                            set messageSent to true
                            exit repeat
                        on error
                        end try
                    end if
                end repeat
            end tell
            """
            let finalScript = String(format: scriptTemplate, identifiersString, sanitizedMessage)
            _runAppleScript(finalScript)
        }
    }
    func sendTapback(type tapbackType: TapbackType, to recipientName: String) {
        Task(priority: .userInitiated) {
            let contactIdentifiers = await _getContactIdentifiers(forName: recipientName)
            guard let primaryIdentifier = contactIdentifiers.first else { return }
            let sanitizedIdentifier = primaryIdentifier.replacingOccurrences(of: "\"", with: "\\\"")
            let tapbackValue = tapbackType.rawValue
            let script = """
            tell application "Messages"
                try
                    set targetChat to 1st chat whose participants's handle contains "\(sanitizedIdentifier)"
                    set lastMessage to last message of targetChat
                    tapback "\(tapbackValue)" to lastMessage
                on error errMsg
                end try
            end tell
            """
            _runAppleScript(script)
        }
    }
    func fetchContactImage(forName name: String) async -> NSImage? {
        let store = CNContactStore()
        let keysToFetch = [CNContactImageDataKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            if let contact = contacts.first, let imageData = contact.imageData { return NSImage(data: imageData) }
        } catch { print("iMessageActionManager: Failed to fetch contact image for \(name): \(error)") }
        return nil
    }
    func replyToLastMessage() { if !NSWorkspace.shared.launchApplication("Messages") { print("iMessageActionManager: Could not launch Messages.app") } }
    func markConversationAsRead(senderName: String) {
        let sanitizedSenderName = senderName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Messages"
            try
                set targetChat to first chat whose name is "\(sanitizedSenderName)"
                mark targetChat as read
            on error
            end try
        end tell
        """
        _runAppleScript(script)
    }
    func fetchAndCopyLatestAttachment(for senderName: String) async -> MessageAttachment? {
        guard let db = chatDbConnection else { return nil }
        do {
            let chat = Table("chat"), msg = Table("message"), att = Table("attachment"), c_m_j = Table("chat_message_join"), m_a_j = Table("message_attachment_join")
            let cId = Expression<Int64>("ROWID"), mId = Expression<Int64>("ROWID"), aId = Expression<Int64>("ROWID"), dName = Expression<String?>("display_name"), date = Expression<Int64>("date"), fName = Expression<String?>("filename"), mType = Expression<String?>("mime_type")
            let query = chat.join(c_m_j, on: chat[cId] == c_m_j[Expression<Int64>("chat_id")]).join(msg, on: c_m_j[Expression<Int64>("message_id")] == msg[mId]).join(m_a_j, on: msg[mId] == m_a_j[Expression<Int64>("message_id")]).join(att, on: m_a_j[Expression<Int64>("attachment_id")] == att[aId]).filter(dName == senderName && fName != nil && mType != nil).order(date.desc).limit(1).select(fName, mType)
            if let row = try db.pluck(query), let path = row[fName], let mimeType = row[mType] {
                let fullPath = (path as NSString).expandingTildeInPath, originalURL = URL(fileURLWithPath: fullPath), tempDir = FileManager.default.temporaryDirectory, tempURL = tempDir.appendingPathComponent(originalURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: tempURL.path) { try? FileManager.default.removeItem(at: tempURL) }
                try FileManager.default.copyItem(at: originalURL, to: tempURL)
                return MessageAttachment(localURL: tempURL, originalMimeType: mimeType)
            }
        } catch { print("iMessageActionManager: ERROR: Database query for attachment failed: \(error).") }
        return nil
    }
    func playAudio(at url: URL) { self.audioPlayer = AVPlayer(url: url); self.audioPlayer?.play() }
    private func _getContactIdentifiers(forName name: String) async -> [String] {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        var isAuthorized = false
        switch status { case .authorized: isAuthorized = true; case .denied, .restricted: return []; case .notDetermined: do { isAuthorized = try await store.requestAccess(for: .contacts) } catch { return [] }; @unknown default: return [] }
        guard isAuthorized else { return [] }
        var identifiers: [String] = []
        let keysToFetch = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            guard let contact = contacts.first else { return [] }
            contact.phoneNumbers.forEach { identifiers.append($0.value.stringValue.filter("0123456789+".contains)) }
            contact.emailAddresses.forEach { identifiers.append(String($0.value)) }
            return identifiers.filter { !$0.isEmpty }
        } catch { return [] }
    }
    private func _runAppleScript(_ script: String) {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) { _ = scriptObject.executeAndReturnError(&error); if let err = error { print("iMessageActionManager: AppleScript Error: \(err)") } }
    }
}

class NotificationManager: ObservableObject {
    @Published var latestNotification: NotificationPayload?
    private var frequency: TimeInterval = 2.0
    private var isSilent: Bool = true
    private var dbPath: String?
    private var dbConnection: Connection?
    private var timer: Timer?
    private var lastNotificationId: Int64 = 0
    private var lastNotificationDate: Double = 0.0
    private let settingsModel = SettingsModel.shared
    init(frequency: TimeInterval = 2.0, silent: Bool = true) { self.frequency = frequency; self.isSilent = silent; setupDatabaseConnection(); startScheduler() }
    deinit { timer?.invalidate() }
    func dismissLatestNotification() { DispatchQueue.main.async { self.latestNotification = nil } }
    private func setupDatabaseConnection() {
        let fileManager = FileManager.default, homeDirectory = NSHomeDirectory(), sequoiaPath = "\(homeDirectory)/Library/Group Containers/group.com.apple.usernoted/db2/db"
        if fileManager.fileExists(atPath: sequoiaPath) { self.dbPath = sequoiaPath } else {
            do {
                let darwinUserDir = try subprocess(path: "/usr/bin/getconf", args: ["DARWIN_USER_DIR"]).trimmingCharacters(in: .whitespacesAndNewlines)
                let primaryLegacyPath = "\(darwinUserDir)com.apple.NotificationCenter/db2/db", fallbackLegacyPath = "\(darwinUserDir)com.apple.notificationcenter/db2/db"
                if fileManager.fileExists(atPath: primaryLegacyPath) { self.dbPath = primaryLegacyPath } else if fileManager.fileExists(atPath: fallbackLegacyPath) { self.dbPath = fallbackLegacyPath }
            } catch {}
        }
        guard let validPath = self.dbPath else { return }
        do { dbConnection = try Connection(validPath, readonly: true); if let lastRecord = getLastNotificationFromDB() { self.lastNotificationId = lastRecord.id; self.lastNotificationDate = lastRecord.date } } catch { print("Error setting up database connection to \(validPath): \(error)") }
    }
    private func startScheduler() { guard dbConnection != nil else { return }; check(); timer = Timer.scheduledTimer(withTimeInterval: frequency, repeats: true) { [weak self] _ in self?.check() } }
    @objc private func check() {
        do {
            guard let db = dbConnection else { return }
            let recordTable = Table("record"), recId = Expression<Int64>("rec_id"), deliveredDate = Expression<Double?>("delivered_date"), requestDate = Expression<Double?>("request_date"), data = Expression<Data>("data")
            let query = recordTable.select(recId, data, deliveredDate, requestDate).where(recId > lastNotificationId && (deliveredDate ?? requestDate) >= lastNotificationDate).order(recId.desc)
            var notificationsToPublish: [NotificationPayload] = []
            for row in try db.prepare(query) {
                if let notification = parseNotification(from: row[data], id: row[recId], dateValue: row[deliveredDate] ?? row[requestDate] ?? 0) {
                    if _shouldShowNotification(for: notification) { notificationsToPublish.append(notification) }
                }
            }
            if let newest = notificationsToPublish.first { self.lastNotificationId = Int64(newest.id) ?? self.lastNotificationId; self.lastNotificationDate = newest.date.timeIntervalSinceReferenceDate }
            for notification in notificationsToPublish.reversed() { self.latestNotification = notification }
        } catch { print("Failed to check for notifications: \(error)") }
    }
    private func _shouldShowNotification(for payload: NotificationPayload) -> Bool {
        let settings = settingsModel.settings
        var isInitiallyAllowed: Bool
        if !settings.masterNotificationsEnabled { isInitiallyAllowed = false } else {
            switch payload.appIdentifier {
            case "com.apple.MobileSMS", "com.apple.iChat": isInitiallyAllowed = settings.iMessageNotificationsEnabled
            case "com.apple.sharingd": isInitiallyAllowed = settings.airDropNotificationsEnabled
            case "com.apple.facetime": isInitiallyAllowed = settings.faceTimeNotificationsEnabled
            default:
                if let isEnabled = settings.appNotificationStates[payload.appIdentifier] { isInitiallyAllowed = isEnabled }
                else if payload.appIdentifier.starts(with: "com.apple.") { isInitiallyAllowed = settings.systemNotificationsEnabled }
                else { isInitiallyAllowed = true }
            }
        }
        if !isInitiallyAllowed { return false }
        if settings.onlyShowVerificationCodeNotifications { return payload.verificationCode != nil }
        return true
    }
    private func parseNotification(from rawPlist: Data, id: Int64, dateValue: Double) -> NotificationPayload? {
        do {
            guard let plist = try PropertyListSerialization.propertyList(from: rawPlist, options: [], format: nil) as? [String: Any],
                  let appIdentifier = plist["app"] as? String,
                  let request = plist["req"] as? [String: Any] else { return nil }
            let title = request["titl"] as? String ?? "", subtitle = request["subt"] as? String ?? "", body = request["body"] as? String ?? ""
            let combinedBody = subtitle.isEmpty ? body : "\(subtitle)—\(body)", date = Date(timeIntervalSinceReferenceDate: dateValue), appIcon = getAppIcon(for: appIdentifier)
            return NotificationPayload(id: String(id), appIdentifier: appIdentifier, title: title, body: combinedBody, date: date, appIcon: appIcon)
        } catch { return nil }
    }
    private func getAppIcon(for identifier: String) -> NSImage? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier).map { NSWorkspace.shared.icon(forFile: $0.path) } }
    private func getLastNotificationFromDB() -> (id: Int64, date: Double)? {
        guard let db = dbConnection else { return nil }
        do {
            let record = Table("record"), recId = Expression<Int64>("rec_id"), deliveredDate = Expression<Double?>("delivered_date"), requestDate = Expression<Double?>("request_date")
            if let lastRow = try db.pluck(record.order(recId.desc)) { return (try lastRow.get(recId), try lastRow.get(deliveredDate) ?? lastRow.get(requestDate) ?? 0.0) }
        } catch {}
        return nil
    }
    private func subprocess(path: String, args: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = args; let pipe = Pipe(); process.standardOutput = pipe; try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); return String(data: data, encoding: .utf8) ?? ""
    }
}