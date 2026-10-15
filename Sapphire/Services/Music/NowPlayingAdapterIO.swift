//
//  NowPlayingAdapterIO.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07
//

import AppKit
import Darwin
import Foundation
import ImageIO

// MARK: - Stream parsing

final class NowPlayingStreamParser: @unchecked Sendable {
    enum ArtworkUpdate {
        case unchanged
        case removed
        case image(digest: String, image: NSImage?)

        var isUnchanged: Bool {
            if case .unchanged = self { return true }
            return false
        }
    }

    struct Event: @unchecked Sendable {
        let metadata: [String: Any]
        let artwork: ArtworkUpdate
    }

    static let maximumLineBytes = 16 * 1024 * 1024
    static let artworkMaxPixelSize = 768

    private var framer = NewlineFramer(limit: maximumLineBytes)
    private var lastBase64: NSString?
    private var lastDigest: String?
    private var lastImage: NSImage?
    private var sawFirstPayload = false

    func consume(_ data: Data) -> [Event] {
        framer.append(data).compactMap(parse)
    }

    private func parse(_ line: Data) -> Event? {
        guard let parsed = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        var payload = (parsed["payload"] as? [String: Any]) ?? parsed
        let isFirstPayload = !sawFirstPayload
        sawFirstPayload = true

        let artwork: ArtworkUpdate
        if let raw = payload.removeValue(forKey: "artworkData") {
            if let base64 = raw as? NSString, base64.length > 0 {
                artwork = decodeArtwork(base64)
            } else {
                lastBase64 = nil
                lastDigest = nil
                lastImage = nil
                artwork = .removed
            }
        } else if isFirstPayload {
            artwork = .removed
        } else {
            artwork = .unchanged
        }
        return Event(metadata: payload, artwork: artwork)
    }

    private func decodeArtwork(_ base64: NSString) -> ArtworkUpdate {
        if let lastBase64, let lastDigest, base64.isEqual(to: lastBase64 as String) {
            return .image(digest: lastDigest, image: lastImage)
        }
        let bytes = base64.data(using: String.Encoding.utf8.rawValue) ?? Data((base64 as String).utf8)
        let digest = ArtworkDigest.of(base64Bytes: bytes)
        lastBase64 = base64
        if digest == lastDigest {
            return .image(digest: digest, image: lastImage)
        }
        let image = Data(base64Encoded: bytes, options: .ignoreUnknownCharacters).flatMap(Self.thumbnail)
        lastDigest = digest
        lastImage = image
        return .image(digest: digest, image: image)
    }

    static func thumbnail(from data: Data) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: artworkMaxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

// MARK: - Command channel

final class AdapterCommandChannel: @unchecked Sendable {
    private struct Server {
        let token: UInt64
        let process: Process
        let input: FileHandle
        let stdin: Pipe
        let stdout: Pipe
    }

    static let commandTimeout: TimeInterval = 5
    static let idleTimeout: TimeInterval = 45

    private let queue = DispatchQueue(label: "com.sapphire.mediaremote.commands", qos: .userInitiated)
    private var pending = AdapterCommandQueue()
    private var inFlight: AdapterCommand?
    private var dispatchGeneration: UInt64 = 0
    private var inFlightServerToken: UInt64?
    private var oneShot: Process?
    private var server: Server?
    private var serverToken: UInt64 = 0
    private var ackFramer = NewlineFramer(limit: 4_096)
    private var health = CommandServerHealth()
    private var deadline: DispatchWorkItem?
    private var idleClose: DispatchWorkItem?

    func submit(_ command: AdapterCommand) {
        queue.async {
            self.pending.enqueue(command)
            self.pump()
        }
    }

    func shutdown() {
        queue.async {
            self.pending.removeAll()
            self.idleClose?.cancel()
            self.idleClose = nil
            self.closeServer()
        }
    }

    // MARK: Dispatch

    private func pump() {
        guard inFlight == nil, let command = pending.dequeue() else { return }
        idleClose?.cancel()
        idleClose = nil
        inFlight = command
        dispatchGeneration &+= 1
        let generation = dispatchGeneration

        if !health.prefersOneShot(at: Date()), let token = sendThroughServer(command) {
            inFlightServerToken = token
        } else {
            inFlightServerToken = nil
            guard runOneShot(command, generation: generation) else {
                finishInFlight()
                return
            }
        }
        armDeadline(generation: generation)
    }

    private func finishInFlight() {
        deadline?.cancel()
        deadline = nil
        inFlight = nil
        inFlightServerToken = nil
        oneShot = nil
        if pending.isEmpty { scheduleIdleClose() }
        pump()
    }

    private func armDeadline(generation: UInt64) {
        deadline?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.inFlight != nil, self.dispatchGeneration == generation else { return }
            print("[NativeMediaController] Media command timed out; resetting the command channel.")
            if self.inFlightServerToken != nil {
                self.health.recordCrash(at: Date())
                self.closeServer(force: true)
            }
            if let oneShot = self.oneShot, oneShot.isRunning { oneShot.terminate() }
            self.finishInFlight()
        }
        deadline = item
        queue.asyncAfter(deadline: .now() + Self.commandTimeout, execute: item)
    }

    private func scheduleIdleClose() {
        guard server != nil else { return }
        idleClose?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.inFlight == nil, self.pending.isEmpty else { return }
            self.closeServer()
        }
        idleClose = item
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: item)
    }

    // MARK: Server

    private func sendThroughServer(_ command: AdapterCommand) -> UInt64? {
        guard let server = ensureServer() else { return nil }
        let line = Data((command.serveLine + "\n").utf8)
        guard Self.writeAll(line, to: server.input.fileDescriptor) else {
            health.recordCrash(at: Date())
            closeServer(force: true)
            return nil
        }
        return server.token
    }

    private func ensureServer() -> Server? {
        if let server, server.process.isRunning { return server }
        closeServer(force: true)
        guard let paths = NativeMediaController.cachedPaths else { return nil }

        serverToken &+= 1
        let token = serverToken
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.adapter, "serve"]
        var env = ProcessInfo.processInfo.environment
        env["PERLIO"] = ":unix"
        process.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { self?.handleServerOutput(data, token: token) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            let reason = process.terminationReason
            self?.queue.async { self?.serverDidExit(token: token, status: status, reason: reason) }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            try? stdin.fileHandleForWriting.close()
            health.recordCrash(at: Date())
            return nil
        }
        ackFramer.reset()
        let launched = Server(token: token, process: process, input: stdin.fileHandleForWriting, stdin: stdin, stdout: stdout)
        server = launched
        return launched
    }

    private func closeServer(force: Bool = false) {
        guard let server else { return }
        self.server = nil
        try? server.input.close()
        if force, server.process.isRunning { server.process.terminate() }
    }

    private func handleServerOutput(_ data: Data, token: UInt64) {
        guard server?.token == token else { return }
        let lines = ackFramer.append(data)
        guard inFlightServerToken == token, inFlight != nil, !lines.isEmpty else { return }
        finishInFlight()
    }

    private func serverDidExit(token: UInt64, status: Int32, reason: Process.TerminationReason) {
        if server?.token == token {
            server = nil
        }
        guard inFlightServerToken == token, inFlight != nil else { return }
        if reason == .uncaughtSignal || (status != 0 && status != 1) {
            health.recordCrash(at: Date())
        }
        finishInFlight()
    }

    // MARK: One-shot fallback

    private func runOneShot(_ command: AdapterCommand, generation: UInt64) -> Bool {
        guard let paths = NativeMediaController.cachedPaths else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.script, paths.adapter] + command.oneShotArguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] _ in
            self?.queue.async {
                guard let self, self.dispatchGeneration == generation, self.inFlight != nil else { return }
                self.finishInFlight()
            }
        }
        do {
            try task.run()
        } catch {
            return false
        }
        oneShot = task
        return true
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, base + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }
}