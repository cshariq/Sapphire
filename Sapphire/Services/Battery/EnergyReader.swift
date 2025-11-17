//
//  EnergyReader.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation
import AppKit

struct TopProcess: Identifiable, Equatable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let usage: Double
}

class EnergyReader {
    private var timer: Timer?
    private let callback: ([TopProcess]) -> Void

    init(callback: @escaping ([TopProcess]) -> Void) {
        self.callback = callback
    }

    func start() {
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.read()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func read() {
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = "/usr/bin/top"
            task.arguments = ["-o", "power", "-l", "2", "-n", "5", "-stats", "pid,command,power"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do { try task.run() } catch { return }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let processes = self.parseTopOutput(output)

            DispatchQueue.main.async {
                self.callback(processes)
            }
        }
    }

    private func parseTopOutput(_ output: String) -> [TopProcess] {
        var processes: [TopProcess] = []
        let lines = output.split(separator: "\n")

        guard let sampleStartIndex = lines.firstIndex(where: { $0.contains("PID") }) else { return [] }

        for line in lines.dropFirst(Int(sampleStartIndex) + 1) {
            let components = line.split(whereSeparator: \.isWhitespace)
            guard components.count >= 3,
                  let pid = Int(components[0]),
                  let power = Double(components.last!) else { continue }

            let command = components.dropFirst().dropLast().joined(separator: " ")

            var name = command
            if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                name = app.localizedName ?? command
            }

            if power > 0 {
                processes.append(TopProcess(pid: pid, name: name, usage: power))
            }
        }

        return Array(processes.prefix(3))
    }
}