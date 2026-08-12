//
//  NotesWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

struct NotesWidgetView: View {
    @ObservedObject private var notesManager = NotesManager.shared

    private let maxHeight: CGFloat = 96

    private var suggestions: [QuickNote] {
        Array(notesManager.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.35), Color.orange.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
                Text("Notes")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text("\(notesManager.notes.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(MaterialChartPalette.surfaceVariant)
                    .clipShape(Capsule())
            }

            if suggestions.isEmpty {
                Text("No notes yet")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions) { note in
                        suggestionRow(note)
                    }
                }
            }
        }
        .frame(width: 176, height: maxHeight, alignment: .topLeading)
        .clipped()
    }

    private func suggestionRow(_ note: QuickNote) -> some View {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = title.isEmpty ? (body.isEmpty ? "Untitled" : body) : title

        return HStack(spacing: 6) {
            Capsule()
                .fill(Color.yellow.opacity(0.75))
                .frame(width: 3, height: 14)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(MaterialChartPalette.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct NotesPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @ObservedObject private var notesManager = NotesManager.shared
    @StateObject private var editorGate = NoteEditorGate()
    @State private var searchText = ""
    @State private var showSearch = false

    private var filteredNotes: [QuickNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notesManager.notes }
        return notesManager.notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    private var editingNote: QuickNote? {
        guard let id = editorGate.editingNoteID else { return nil }
        return notesManager.notes.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let note = editingNote {
                InNotchNoteEditor(
                    note: note,
                    onBack: { editorGate.editingNoteID = nil },
                    onSave: { updated in
                        notesManager.updateNote(updated)
                    },
                    onDelete: {
                        notesManager.deleteNote(id: note.id)
                        editorGate.editingNoteID = nil
                    }
                )
            } else {
                listView
            }
        }
        .onAppear {
            NotchBackRouter.shared.intercept = { [weak editorGate] in
                editorGate?.dismissIfEditing() ?? false
            }
        }
        .onDisappear {
            NotchBackRouter.shared.intercept = nil
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            topBar

            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    NotchSearchField(placeholder: "Search notes", text: $searchText, autofocus: true)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MaterialChartPalette.surfaceContainer)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MaterialChartPalette.cardGradient(for: .yellow))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.yellow.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if filteredNotes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredNotes) { note in
                            NotchSwipeRow(
                                leading: NotchSwipeAction(
                                    systemImage: note.isDone ? "arrow.uturn.backward" : "checkmark",
                                    tint: note.isDone ? .orange : .green
                                ) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        notesManager.toggleNoteDone(id: note.id)
                                    }
                                },
                                trailing: NotchSwipeAction(
                                    systemImage: "trash.fill",
                                    tint: .red
                                ) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        if editorGate.editingNoteID == note.id { editorGate.editingNoteID = nil }
                                        notesManager.deleteNote(id: note.id)
                                    }
                                }
                            ) {
                                noteRow(note)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 10)
        .frame(width: 460, height: 270)
        .clipped()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Notes")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("\(notesManager.notes.count) saved")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            toolbarButton("magnifyingglass", active: showSearch) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSearch.toggle()
                    if !showSearch { searchText = "" }
                }
            }
            toolbarButton("square.and.pencil") {
                let note = notesManager.addNote()
                editorGate.editingNoteID = note.id
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func toolbarButton(_ systemName: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        NotchCapsuleIconButton(
            systemName: systemName,
            isActive: active,
            activeTint: .yellow,
            action: action
        )
    }

    private func noteRow(_ note: QuickNote) -> some View {
        Button {
            editorGate.editingNoteID = note.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: note.isDone
                                ? [Color.green.opacity(0.75), Color.mint.opacity(0.45)]
                                : [Color.yellow.opacity(0.9), Color.orange.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(note.isDone ? .secondary : .primary)
                            .strikethrough(note.isDone, color: .secondary)
                            .lineLimit(1)
                        if note.isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green.opacity(0.9))
                        }
                    }
                    Text(note.body.isEmpty ? "Empty note" : note.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .opacity(note.isDone ? 0.65 : 1)
                }
                Spacer(minLength: 0)
                RelativeMinuteText(date: note.updatedAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.surface)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MaterialChartPalette.cardGradient(for: note.isDone ? .green : .yellow))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MaterialChartPalette.outline, lineWidth: 1)
            )
            .opacity(note.isDone ? 0.82 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.isDone ? "Mark Undone" : "Mark Done") {
                notesManager.toggleNoteDone(id: note.id)
            }
            Button("Edit") { editorGate.editingNoteID = note.id }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(note.title)\n\(note.body)", forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) {
                notesManager.deleteNote(id: note.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.yellow.opacity(0.8))
            Text(searchText.isEmpty ? "No notes yet" : "No matching notes")
                .font(.headline)
            Text(searchText.isEmpty ? "Tap the pencil to create your first note." : "Try a different search.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 20)
    }
}

@MainActor
private final class NoteEditorGate: ObservableObject {
    @Published var editingNoteID: UUID?

    func dismissIfEditing() -> Bool {
        guard editingNoteID != nil else { return false }
        editingNoteID = nil
        return true
    }
}

private struct InNotchNoteEditor: View {
    @State private var draft: QuickNote
    @State private var attributedBody: NSAttributedString
    @StateObject private var textViewBox = RichTextViewBox()

    let onBack: () -> Void
    let onSave: (QuickNote) -> Void
    let onDelete: () -> Void

    init(
        note: QuickNote,
        onBack: @escaping () -> Void,
        onSave: @escaping (QuickNote) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: note)
        _attributedBody = State(initialValue: note.attributedBody())
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NotchSearchField(placeholder: "Title", text: $draft.title, autofocus: draft.title == "New Note" || draft.title.isEmpty)
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer(minLength: 8)

                NotchCapsuleIconButton(
                    systemName: "trash",
                    isActive: true,
                    activeTint: .red,
                    help: "Delete note",
                    action: onDelete
                )

                Button(action: saveAndBack) {
                    Text("Done")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.yellow.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            RichTextToolbar(textViewBox: textViewBox, attributedText: $attributedBody)
                .padding(.horizontal, 12)
                .background(MaterialChartPalette.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            RichTextEditor(attributedText: $attributedBody, textViewBox: textViewBox)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MaterialChartPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MaterialChartPalette.outline, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: 520, height: 310)
        .clipped()
        .onDisappear {
            persistDraft()
        }
    }

    private func persistDraft() {
        draft.applyAttributedBody(attributedBody)
        onSave(draft)
    }

    private func saveAndBack() {
        persistDraft()
        onBack()
    }
}