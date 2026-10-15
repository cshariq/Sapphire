//
//  SapphirePerformance.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-20

import FirebaseCore
import FirebaseInstallations
import Foundation
import GoogleDataTransport
import Network
import os.log

private let sapphirePerformanceLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Sapphire",
    category: "FirebasePerformance"
)

@MainActor
final class SapphirePerformanceTrace {
    private let name: String
    private let startDate = Date()
    private let startUptime = ProcessInfo.processInfo.systemUptime
    private var counters: [String: Int64] = [:]
    private var attributes: [String: String]
    private var isStopped = false

    fileprivate init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    @discardableResult
    func setMetric(_ value: Int64, named metricName: String) -> Self {
        guard let metricName = SapphirePerformance.validatedName(metricName) else { return self }
        counters[metricName] = value
        return self
    }

    @discardableResult
    func incrementMetric(_ metricName: String, by value: Int64 = 1) -> Self {
        guard let metricName = SapphirePerformance.validatedName(metricName) else { return self }
        counters[metricName, default: 0] += value
        return self
    }

    @discardableResult
    func setAttribute(_ value: String, named attributeName: String) -> Self {
        guard let pair = SapphirePerformance.validatedAttribute(name: attributeName, value: value) else {
            return self
        }
        guard attributes[pair.name] != nil || attributes.count < 5 else { return self }
        attributes[pair.name] = pair.value
        return self
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        SapphirePerformance.recordTrace(
            name: name,
            startTime: startDate,
            duration: ProcessInfo.processInfo.systemUptime - startUptime,
            counters: counters,
            attributes: attributes
        )
    }
}

@MainActor
enum SapphirePerformance {
    private static let logSource = "462"
    private static var isCollectionEnabled = false
    private static var networkMonitor: NWPathMonitor?

    private static let transport = GDTCORTransport(
        mappingID: logSource,
        transformers: nil,
        target: .FLL
    )

    static func setCollectionEnabled(_ enabled: Bool) {
        let hasUsableFirebaseProject = FirebaseApp.app().map {
            isUsableFirebaseProject(appID: $0.options.googleAppID, projectID: $0.options.projectID)
        } ?? false
        isCollectionEnabled = enabled && hasUsableFirebaseProject

        if isCollectionEnabled, networkMonitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { _ in }
            monitor.start(queue: DispatchQueue(label: "com.cshariq.sapphire.firebase-performance-network"))
            networkMonitor = monitor
        } else if !isCollectionEnabled {
            networkMonitor?.cancel()
            networkMonitor = nil
        }
    }

    static func startTrace(
        name: String,
        attributes: [String: String] = [:]
    ) -> SapphirePerformanceTrace? {
        guard isCollectionEnabled, let name = validatedName(name) else { return nil }
        return SapphirePerformanceTrace(name: name, attributes: validatedAttributes(attributes))
    }

    static func recordTrace(
        name: String,
        startTime: Date,
        duration: TimeInterval,
        counters: [String: Int64] = [:],
        attributes: [String: String] = [:]
    ) {
        guard isCollectionEnabled,
              FirebaseBootstrap.isConfigured,
              let name = validatedName(name),
              duration > 0,
              duration.isFinite else {
            return
        }

        let networkType = currentNetworkType
        let cleanCounters = validatedCounters(counters)
        let cleanAttributes = validatedAttributes(attributes)

        Task { @MainActor in
            do {
                let installationID = try await Installations.installations().installationID()
                guard isCollectionEnabled,
                      let options = FirebaseApp.app()?.options,
                      isUsableFirebaseProject(appID: options.googleAppID, projectID: options.projectID) else {
                    return
                }

                let metric = PerformanceMetricEncoder.encodeTrace(
                    appID: options.googleAppID,
                    installationID: installationID,
                    firebaseVersion: FirebaseVersion(),
                    bundleShortVersion: Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? "0",
                    networkType: networkType,
                    name: name,
                    startTime: startTime,
                    duration: duration,
                    counters: cleanCounters,
                    attributes: cleanAttributes
                )

                guard let transport else {
                    sapphirePerformanceLog.error("Firebase Performance transport is unavailable")
                    return
                }

                let event = transport.eventForTransport()
                event.dataObject = PerformanceEventData(metric)
                try await transport.sendDataEvent(event)
                sapphirePerformanceLog.debug("Queued Firebase Performance trace: \(name, privacy: .public)")
            } catch {
                sapphirePerformanceLog.error(
                    "Could not queue Firebase Performance trace: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    static func validatedName(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("_"), name.utf16.count <= 100 else { return nil }
        return name
    }

    static func validatedAttribute(name: String, value: String) -> (name: String, value: String)? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let reservedPrefixes = ["firebase_", "google_", "ga_"]
        let allowedCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
        )
        let isAllowedName = name.unicodeScalars.allSatisfy {
            allowedCharacters.contains($0)
        }

        guard !name.isEmpty,
              isAllowedName,
              !reservedPrefixes.contains(where: name.hasPrefix),
              name.utf16.count <= 40,
              !value.isEmpty,
              value.utf16.count <= 100 else {
            return nil
        }
        return (name, value)
    }

    static func validatedCounters(_ counters: [String: Int64]) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for (rawName, value) in counters.sorted(by: { $0.key < $1.key }) {
            guard let name = validatedName(rawName) else { continue }
            result[name] = value
        }
        return result
    }

    static func validatedAttributes(_ attributes: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (rawName, value) in attributes.sorted(by: { $0.key < $1.key }) {
            guard let pair = validatedAttribute(name: rawName, value: value) else { continue }
            guard result[pair.name] != nil || result.count < 5 else { continue }
            result[pair.name] = pair.value
        }
        return result
    }

    static func isUsableFirebaseProject(appID: String, projectID: String?) -> Bool {
        projectID != "sapphire-stub"
            && appID != "1:000000000000:ios:0000000000000000"
    }

    private static var currentNetworkType: Int64 {
        guard let path = networkMonitor?.currentPath, path.status == .satisfied else { return -1 }
        if path.usesInterfaceType(.wifi) { return 1 }
        if path.usesInterfaceType(.cellular) { return 0 }
        if path.usesInterfaceType(.wiredEthernet) { return 9 }
        return -1
    }
}

private final class PerformanceEventData: NSObject, GDTCOREventDataObject {
    private let data: Data

    init(_ data: Data) {
        self.data = data
    }

    func transportBytes() -> Data {
        data
    }
}

enum PerformanceMetricEncoder {
    static func encodeTrace(
        appID: String,
        installationID: String,
        firebaseVersion: String,
        bundleShortVersion: String,
        networkType: Int64,
        name: String,
        startTime: Date,
        duration: TimeInterval,
        counters: [String: Int64],
        attributes: [String: String]
    ) -> Data {
        var iosInfo = ProtobufWriter()
        iosInfo.appendString(field: 2, firebaseVersion)
        iosInfo.appendString(field: 3, bundleShortVersion)
        iosInfo.appendMessage(field: 5) { networkInfo in
            networkInfo.appendInt64(field: 1, networkType)
        }

        var applicationInfo = ProtobufWriter()
        applicationInfo.appendString(field: 1, appID)
        applicationInfo.appendString(field: 2, installationID)
        applicationInfo.appendMessage(field: 4, data: iosInfo.data)
        applicationInfo.appendInt64(field: 5, 1)

        var trace = ProtobufWriter()
        trace.appendString(field: 1, name)
        trace.appendBool(field: 2, false)
        trace.appendInt64(field: 4, Int64(startTime.timeIntervalSince1970 * 1_000_000))
        trace.appendInt64(field: 5, Int64(duration * 1_000_000))
        for (key, value) in counters.sorted(by: { $0.key < $1.key }) {
            trace.appendMessage(field: 6) { entry in
                entry.appendString(field: 1, key)
                entry.appendInt64(field: 2, value)
            }
        }
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            trace.appendMessage(field: 8) { entry in
                entry.appendString(field: 1, key)
                entry.appendString(field: 2, value)
            }
        }

        var metric = ProtobufWriter()
        metric.appendMessage(field: 1, data: applicationInfo.data)
        metric.appendMessage(field: 2, data: trace.data)
        return metric.data
    }
}

private struct ProtobufWriter {
    fileprivate var data = Data()

    mutating func appendBool(field: Int, _ value: Bool) {
        appendKey(field: field, wireType: 0)
        appendVarint(value ? 1 : 0)
    }

    mutating func appendInt64(field: Int, _ value: Int64) {
        appendKey(field: field, wireType: 0)
        appendVarint(UInt64(bitPattern: value))
    }

    mutating func appendString(field: Int, _ value: String) {
        appendMessage(field: field, data: Data(value.utf8))
    }

    mutating func appendMessage(field: Int, _ body: (inout ProtobufWriter) -> Void) {
        var message = ProtobufWriter()
        body(&message)
        appendMessage(field: field, data: message.data)
    }

    mutating func appendMessage(field: Int, data message: Data) {
        appendKey(field: field, wireType: 2)
        appendVarint(UInt64(message.count))
        data.append(message)
    }

    private mutating func appendKey(field: Int, wireType: UInt64) {
        appendVarint((UInt64(field) << 3) | wireType)
    }

    private mutating func appendVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }
}