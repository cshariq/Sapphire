//
//  PlaneEditorView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import SwiftUI

struct PlaneEditorView: View {
    @Binding var plane: Plane
    let allLayouts: [SnapLayout]
    let allApps: [SystemApp]
    let onSave: (Plane) -> Void
    @Environment(\.dismiss) var dismiss

    @StateObject private var shortcutRecorder = GlobalShortcutRecorder.shared
    @State private var selectedLayout: SnapLayout?

    private let noAppSelectedID = "none"

    init(plane: Binding<Plane>, allLayouts: [SnapLayout], allApps: [SystemApp], onSave: @escaping (Plane) -> Void) {
        self._plane = plane
        self.allLayouts = allLayouts
        self.allApps = allApps
        self.onSave = onSave
        self._selectedLayout = State(initialValue: allLayouts.first { $0.id == plane.wrappedValue.layoutID })
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Plane")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 15) {
                TextField("Plane Name", text: $plane.name)

                Picker("Layout:", selection: $plane.layoutID) {
                    ForEach(allLayouts) { layout in
                        Text(layout.name).tag(layout.id)
                    }
                }

                HStack {
                    Text("Keyboard Shortcut")
                    Spacer()
                    Button(action: {
                        if shortcutRecorder.isRecording {
                            shortcutRecorder.stopRecording()
                        } else {
                            shortcutRecorder.startRecording { key, flags in
                                self.plane.shortcut = .init(key: key, modifiers: flags)
                            }
                        }
                    }) {
                        if shortcutRecorder.isRecording {
                            Text("Recording... (Esc to cancel)")
                                .foregroundColor(.accentColor)
                        } else if let shortcut = plane.shortcut {
                            Text("\(KeyboardShortcutHelper.description(for: shortcut.modifiers)) \(shortcut.key)")
                        } else {
                            Text("Record Shortcut")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .textFieldStyle(.roundedBorder)
            .pickerStyle(.menu)

            Divider()

            Text("App Assignments")
                .font(.headline)

            if let layout = selectedLayout {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                            HStack {
                                Text("Zone \(index + 1)")
                                Spacer()
                                Picker("App", selection: appBinding(for: zone.id)) {
                                    Text("None").tag(noAppSelectedID)
                                    Divider()
                                    ForEach(allApps) { app in
                                        Text(app.name).tag(app.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 200)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Select a valid layout to assign apps.")
                    .foregroundColor(.secondary)
                    .frame(maxHeight: .infinity)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(plane)
                    dismiss()
                }
                .disabled(plane.name.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(minWidth: 450, minHeight: 500)
        .background(.ultraThinMaterial)
        .onChange(of: plane.layoutID) { _, newID in
            selectedLayout = allLayouts.first { $0.id == newID }
        }
        .onDisappear {
            shortcutRecorder.stopRecording()
        }
    }

    private func appBinding(for zoneID: UUID) -> Binding<String> {
        return Binding(
            get: { self.plane.assignments[zoneID] ?? noAppSelectedID },
            set: { newAppID in
                if newAppID == noAppSelectedID {
                    self.plane.assignments.removeValue(forKey: zoneID)
                } else {
                    self.plane.assignments[zoneID] = newAppID
                }
            }
        )
    }
}