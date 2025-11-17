//
//  ShortcutsFetcher.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import Foundation
import AppKit

@MainActor
class ShortcutsFetcher: ObservableObject {
    @Published var allShortcuts: [ShortcutInfo] = []
    @Published var isLoading: Bool = false
    @Published var accessError: String?

    func fetchAllShortcuts() {
        guard !isLoading else { return }

        isLoading = true
        accessError = nil

        Task {
            do {
                let shortcuts = try await self.loadShortcuts()
                self.allShortcuts = shortcuts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } catch {
                self.accessError = "Could not fetch shortcuts. Error: \(error.localizedDescription)"
                self.allShortcuts = []
            }
            self.isLoading = false
        }
    }

    private func loadShortcuts() async throws -> [ShortcutInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list", "--show-identifiers"]

        let pipe = Pipe()
        process.standardOutput = pipe

        return try await withTaskCancellationHandler {
            try process.run()

            var shortcuts: [ShortcutInfo] = []

            for try await line in pipe.fileHandleForReading.bytes.lines {
                guard let match = line.wholeMatch(of: /(.*) \(([A-Z0-9-]*)\)/) else { continue }
                let (_, name, id) = match.output
                shortcuts.append(ShortcutInfo(id: String(id), name: String(name)))
            }
            return shortcuts

        } onCancel: {
            process.terminate()
        }
    }
}