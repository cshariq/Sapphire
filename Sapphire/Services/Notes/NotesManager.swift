//
//  NotesManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import AppKit

struct QuickNote: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var rtfData: Data? = nil
    var updatedAt: Date = Date()
    var isDone: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, body, rtfData, updatedAt, isDone
    }

    init(id: UUID = UUID(), title: String, body: String, rtfData: Data? = nil, updatedAt: Date = Date(), isDone: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.rtfData = rtfData
        self.updatedAt = updatedAt
        self.isDone = isDone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        rtfData = try c.decodeIfPresent(Data.self, forKey: .rtfData)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
    }

    func attributedBody() -> NSAttributedString {
        if let rtfData,
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            return attributed
        }
        return NSAttributedString(
            string: body,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    mutating func applyAttributedBody(_ attributed: NSAttributedString) {
        body = attributed.string
        let range = NSRange(location: 0, length: attributed.length)
        rtfData = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}

@MainActor
final class NotesManager: ObservableObject {
    static let shared = NotesManager()

    @Published private(set) var notes: [QuickNote] = []

    private let storageKey = "sapphire.quickNotes"

    private init() {
        load()
        if notes.isEmpty {
            notes = [QuickNote(title: "Welcome", body: "Tap to expand and edit your notes.")]
        }
    }

    var pinnedPreview: QuickNote? {
        notes.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    @discardableResult
    func addNote(title: String = "New Note", body: String = "") -> QuickNote {
        let note = QuickNote(title: title, body: body)
        notes.insert(note, at: 0)
        save()
        return note
    }

    func updateNote(_ note: QuickNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.updatedAt = Date()
        notes[index] = updated
        save()
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func setNoteDone(id: UUID, done: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isDone = done
        notes[index].updatedAt = Date()
        notes.sort { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
            return lhs.updatedAt > rhs.updatedAt
        }
        save()
    }

    func toggleNoteDone(id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        setNoteDone(id: id, done: !note.isDone)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QuickNote].self, from: data) else { return }
        notes = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}