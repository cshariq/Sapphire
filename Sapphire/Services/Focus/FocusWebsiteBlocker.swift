//
//  FocusWebsiteBlocker.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation
import AppKit
import Network

@MainActor
final class FocusWebsiteBlocker {
    static let shared = FocusWebsiteBlocker()

    private(set) var isActive = false
    private(set) var blockedDomains: Set<String> = []
    private let pageServer = FocusBlockPageServer()
    private var productiveAccessValidator: ((String) -> Bool)?

    private static let hostsMarkerStart = "# >>> Sapphire Focus Block >>>"
    private static let hostsMarkerEnd = "# <<< Sapphire Focus Block <<<"

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeHostsEntriesAndFlush()
        }
    }

    func setEnabled(_ enabled: Bool, domains: Set<String>, productiveAccessValidator: ((String) -> Bool)? = nil) {
        let normalized = Self.normalize(domains)
        guard enabled != isActive || normalized != blockedDomains else {
            if enabled { self.productiveAccessValidator = productiveAccessValidator }
            return
        }
        isActive = enabled
        blockedDomains = normalized
        self.productiveAccessValidator = productiveAccessValidator
        pageServer.productiveAccessHandler = { [weak self] domain in
            self?.productiveAccessValidator?(domain) ?? false
        }

        if enabled {
            pageServer.start()
            writeHosts(entries: hostsEntries)
        } else {
            pageServer.stop()
            self.productiveAccessValidator = nil
            removeHostsEntriesAndFlush()
        }
    }

    private var hostsEntries: [String] {
        var entries = [Self.hostsMarkerStart]
        for domain in blockedDomains.sorted() {
            for host in Self.hostVariants(for: domain) {
                entries.append("127.0.0.1 \(host)")
                entries.append("::1 \(host)")
            }
        }
        entries.append(Self.hostsMarkerEnd)
        return entries
    }

    static func hostVariants(for domain: String) -> [String] {
        [domain, "www.\(domain)", "m.\(domain)", "mobile.\(domain)"]
    }

    static func normalize(_ domains: Set<String>) -> Set<String> {
        var result: Set<String> = []
        for domain in domains {
            var d = domain
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
            if let slash = d.firstIndex(of: "/") { d = String(d[..<slash]) }
            guard !d.isEmpty, d.contains("."), !d.contains(" "),
                  d.unicodeScalars.allSatisfy({ CharacterSet.urlHostAllowed.contains($0) }) else { continue }
            result.insert(d)
        }
        return result
    }

    nonisolated static func rewriting(_ hosts: String, with entries: [String]) -> String {
        var lines = hosts.components(separatedBy: "\n")
        if let start = lines.firstIndex(of: hostsMarkerStart),
           let end = lines[start...].firstIndex(of: hostsMarkerEnd) {
            lines.removeSubrange(start...end)
        }
        if entries.count > 2 { lines.append(contentsOf: entries) }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    private func writeHosts(entries: [String]) {
        guard HelperManager.shared.status == .enabled else { return }
        XPCClient.shared.helper?.writeHostsEntries(entries) { success in
            if !success { print("[FocusWebsiteBlocker] Helper failed to update /etc/hosts.") }
        }
    }

    private func removeHostsEntriesAndFlush() {
        guard HelperManager.shared.status == .enabled else { return }
        XPCClient.shared.helper?.removeHostsEntries { success in
            if !success { print("[FocusWebsiteBlocker] Helper failed to remove /etc/hosts entries.") }
        }
    }
}

private final class FocusBlockPageServer {
    var productiveAccessHandler: ((String) -> Bool)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.cshariq.sapphire.focus-block-redirect")

    func start() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: 80),
              let newListener = try? NWListener(using: .tcp, on: port) else { return }
        listener = newListener
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        newListener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8),
                  let host = Self.host(from: request) else {
                connection.cancel()
                return
            }
            let normalizedHost = host.split(separator: ":").first.map(String.init) ?? host
            let requestParameter = self.productiveAccessHandler?(normalizedHost) == true
                ? "&request=productive"
                : ""
            let location = "https://sapphire-app.tech/blocked?site=\(Self.urlEncode(normalizedHost))&source=focus\(requestParameter)"
            let response = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func host(from request: String) -> String? {
        for line in request.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("host:") {
            return line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}