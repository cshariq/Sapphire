//
//  DDCService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

#if !APP_STORE

import Foundation
import IOKit
import os

// MARK: - IOAVService Dynamic Loading

enum IOAVServiceLoader {
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias ReadI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
    typealias WriteI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafePointer<UInt8>, UInt32) -> IOReturn

    private static var createFn: CreateWithServiceFn?
    private static var readFn: ReadI2CFn?
    private static var writeFn: WriteI2CFn?
    private static var didLoad = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "DDCService")

    static func ensureLoaded() -> Bool {
        guard !didLoad else { return createFn != nil }
        didLoad = true

        let path = "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer"
        guard let handle = dlopen(path, RTLD_NOW) else {
            logger.error("Failed to dlopen IOMobileFramebuffer: \(String(cString: dlerror()))")
            return false
        }

        guard let c = dlsym(handle, "IOAVServiceCreateWithService"),
              let r = dlsym(handle, "IOAVServiceReadI2C"),
              let w = dlsym(handle, "IOAVServiceWriteI2C") else {
            logger.error("Failed to resolve IOAVService symbols")
            return false
        }

        createFn = unsafeBitCast(c, to: CreateWithServiceFn.self)
        readFn = unsafeBitCast(r, to: ReadI2CFn.self)
        writeFn = unsafeBitCast(w, to: WriteI2CFn.self)
        logger.info("IOAVService APIs loaded successfully")
        return true
    }

    static func createService(for entry: io_service_t) -> CFTypeRef? {
        guard ensureLoaded(), let fn = createFn else { return nil }
        return fn(kCFAllocatorDefault, entry)?.takeRetainedValue()
    }

    static func readI2C(service: CFTypeRef, chipAddress: UInt32, dataAddress: UInt32,
                        buffer: UnsafeMutablePointer<UInt8>, size: UInt32) -> IOReturn {
        guard let fn = readFn else { return kIOReturnNotReady }
        return fn(service, chipAddress, dataAddress, buffer, size)
    }

    static func writeI2C(service: CFTypeRef, chipAddress: UInt32, dataAddress: UInt32,
                         buffer: UnsafePointer<UInt8>, size: UInt32) -> IOReturn {
        guard let fn = writeFn else { return kIOReturnNotReady }
        return fn(service, chipAddress, dataAddress, buffer, size)
    }
}

// MARK: - DDC Error

enum DDCError: Error {
    case apiNotAvailable
    case serviceCreationFailed
    case writeFailed(IOReturn)
    case readFailed(IOReturn)
    case checksumMismatch
    case invalidResponse
    case unsupportedVCP
}

// MARK: - DDC Service

final class DDCService: @unchecked Sendable {
    private let service: CFTypeRef

    private let chipAddress: UInt32 = 0x37
    private let writeAddress: UInt32 = 0x51

    private let writeSleepTime: UInt32 = 10_000
    private let numWriteCycles = 2
    private let readSleepTime: UInt32 = 50_000
    private let retryCount = 5
    private let retrySleepTime: UInt32 = 100_000

    init(service: CFTypeRef) {
        self.service = service
    }

    // MARK: - I2C Write/Read Primitives

    private func i2cWriteRead(packet: [UInt8]) throws -> [UInt8] {
        var writeSuccess = false
        for _ in 0..<numWriteCycles {
            usleep(writeSleepTime)
            let result = packet.withUnsafeBufferPointer { buf in
                IOAVServiceLoader.writeI2C(service: service, chipAddress: chipAddress,
                                           dataAddress: writeAddress, buffer: buf.baseAddress!, size: UInt32(buf.count))
            }
            if result == kIOReturnSuccess { writeSuccess = true }
        }
        guard writeSuccess else { throw DDCError.writeFailed(kIOReturnError) }

        usleep(readSleepTime)

        var reply = [UInt8](repeating: 0, count: 11)
        let readResult = reply.withUnsafeMutableBufferPointer { buf in
            IOAVServiceLoader.readI2C(service: service, chipAddress: chipAddress,
                                      dataAddress: 0, buffer: buf.baseAddress!, size: UInt32(buf.count))
        }
        guard readResult == kIOReturnSuccess else { throw DDCError.readFailed(readResult) }

        return reply
    }

    private func i2cWrite(packet: [UInt8]) throws {
        for _ in 0..<numWriteCycles {
            usleep(writeSleepTime)
            let result = packet.withUnsafeBufferPointer { buf in
                IOAVServiceLoader.writeI2C(service: service, chipAddress: chipAddress,
                                           dataAddress: writeAddress, buffer: buf.baseAddress!, size: UInt32(buf.count))
            }
            if result == kIOReturnSuccess { return }
        }
        throw DDCError.writeFailed(kIOReturnError)
    }

    // MARK: - VCP Commands

    func readVCP(_ code: UInt8) throws -> (current: UInt16, max: UInt16) {
        let logger = Self.logger
        var packet: [UInt8] = [0x82, 0x01, code]
        packet.append(writeChecksum(packet))

        var lastError: DDCError = .readFailed(kIOReturnError)

        for attempt in 0..<retryCount {
            do {
                let reply = try i2cWriteRead(packet: packet)

                if reply.allSatisfy({ $0 == 0 }) {
                    logger.debug("readVCP(0x\(String(code, radix: 16))): all-zero response (no DDC)")
                    throw DDCError.invalidResponse
                }

                if reply[0] == 0x6E && reply[1] == 0x80 {
                    logger.debug("readVCP(0x\(String(code, radix: 16))): null response, attempt \(attempt + 1)/\(self.retryCount)")
                    lastError = .invalidResponse
                    if attempt < retryCount - 1 { usleep(retrySleepTime) }
                    continue
                }

                let hex = reply.map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.debug("readVCP(0x\(String(code, radix: 16))): reply: \(hex)")

                return try parseVCPResponse(reply, expectedCode: code)
            } catch let error as DDCError {
                lastError = error
                if attempt < retryCount - 1 { usleep(retrySleepTime) }
            }
        }

        throw lastError
    }

    func writeVCP(_ code: UInt8, value: UInt16) throws {
        var packet: [UInt8] = [0x84, 0x03, code, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        packet.append(writeChecksum(packet))

        var lastError: DDCError = .writeFailed(kIOReturnError)

        for attempt in 0..<retryCount {
            do {
                try i2cWrite(packet: packet)
                return
            } catch let error as DDCError {
                lastError = error
                if attempt < retryCount - 1 { usleep(retrySleepTime) }
            }
        }

        throw lastError
    }

    // MARK: - EDID

    func readEDID() -> (vendorID: UInt32, productID: UInt32, serialNumber: UInt32)? {
        let edidAddress: UInt32 = 0x50
        var edidData = [UInt8](repeating: 0, count: 128)
        let result = edidData.withUnsafeMutableBufferPointer { buf in
            IOAVServiceLoader.readI2C(service: service, chipAddress: edidAddress,
                                      dataAddress: 0, buffer: buf.baseAddress!, size: 128)
        }
        guard result == kIOReturnSuccess else { return nil }

        let expectedHeader: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        guard Array(edidData[0..<8]) == expectedHeader else { return nil }

        let checksum: UInt8 = edidData.reduce(0, &+)
        guard checksum == 0 else { return nil }

        let vendorID = UInt32(edidData[8]) << 8 | UInt32(edidData[9])

        let productID = UInt32(edidData[10]) | UInt32(edidData[11]) << 8

        let serialNumber = UInt32(edidData[12]) | UInt32(edidData[13]) << 8
            | UInt32(edidData[14]) << 16 | UInt32(edidData[15]) << 24

        return (vendorID: vendorID, productID: productID, serialNumber: serialNumber)
    }

    // MARK: - Convenience

    func supportsAudioVolume() -> Bool {
        (try? readVCP(0x62)) != nil
    }

    func getAudioVolume() throws -> (current: Int, max: Int) {
        let result = try readVCP(0x62)
        return (current: Int(result.current), max: Int(result.max))
    }

    func setAudioVolume(_ volume: Int) throws {
        try writeVCP(0x62, value: UInt16(max(0, min(100, volume))))
    }

    // MARK: - Packet Helpers

    private func writeChecksum(_ data: [UInt8]) -> UInt8 {
        var checksum = UInt8(truncatingIfNeeded: (chipAddress << 1) ^ writeAddress)
        for byte in data { checksum ^= byte }
        return checksum
    }

    private func responseChecksum(_ data: [UInt8]) -> UInt8 {
        var checksum: UInt8 = 0x50
        for byte in data { checksum ^= byte }
        return checksum
    }

    private func parseVCPResponse(_ reply: [UInt8], expectedCode: UInt8) throws -> (current: UInt16, max: UInt16) {
        guard reply.count >= 11 else { throw DDCError.invalidResponse }

        let expected = responseChecksum(Array(reply[0..<10]))
        guard reply[10] == expected else { throw DDCError.checksumMismatch }
        guard reply[3] == 0 else { throw DDCError.unsupportedVCP }
        guard reply[4] == expectedCode else { throw DDCError.invalidResponse }

        let maxValue = (UInt16(reply[6]) << 8) | UInt16(reply[7])
        let currentValue = (UInt16(reply[8]) << 8) | UInt16(reply[9])
        return (current: currentValue, max: maxValue)
    }
}

// MARK: - IOAVService Discovery

extension DDCService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", category: "DDCService")

    static func discoverServices() -> [(entry: io_service_t, service: DDCService)] {
        guard IOAVServiceLoader.ensureLoaded() else {
            logger.error("discoverServices: IOAVService APIs not available")
            return []
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        )
        guard result == kIOReturnSuccess else {
            logger.error("discoverServices: IOServiceGetMatchingServices failed: \(result)")
            return []
        }
        defer { IOObjectRelease(iterator) }

        var services: [(entry: io_service_t, service: DDCService)] = []
        var entryCount = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            entryCount += 1

            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if location == "Embedded" {
                logger.debug("discoverServices: skipping embedded display (entry \(entryCount))")
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
                continue
            }

            if let avService = IOAVServiceLoader.createService(for: entry) {
                services.append((entry: entry, service: DDCService(service: avService)))
                logger.debug("discoverServices: created IOAVService for entry \(entryCount) (location: \(location ?? "unknown"))")
            } else {
                logger.debug("discoverServices: IOAVServiceCreateWithService failed for entry \(entryCount)")
                IOObjectRelease(entry)
            }
            entry = IOIteratorNext(iterator)
        }

        logger.info("discoverServices: \(entryCount) DCPAVServiceProxy entries, \(services.count) IOAVService(s) created")
        return services
    }
}

#endif