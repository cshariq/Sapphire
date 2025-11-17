//
//  SMC.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23.
//

import Foundation
import IOKit
import os.log

internal enum SMCDataType: String {
    case UI8 = "ui8 "
    case UI16 = "ui16"
    case UI32 = "ui32"
    case SP1E = "sp1e"
    case SP3C = "sp3c"
    case SP4B = "sp4b"
    case SP5A = "sp5a"
    case SPA5 = "spa5"
    case SP69 = "sp69"
    case SP78 = "sp78"
    case SP87 = "sp87"
    case SP96 = "sp96"
    case SPB4 = "spb4"
    case SPF0 = "spf0"
    case FLT = "flt "
    case FPE2 = "fpe2"
    case FP2E = "fp2e"
    case FDS = "{fds"
}

internal enum SMCKeys: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
    case readPLimit = 11
    case readVers = 12
}

public enum FanMode: Int, Codable {
    case automatic = 0
    case forced = 1
}

internal struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0))
}

internal struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)

    init(_ key: String) {
        self.key = key
    }
}

extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)

        self = str.utf8.reduce(0) { sum, character in
            return sum << 8 | UInt32(character)
        }
    }

    func toString() -> String {
        return String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 8  & 0xff)!) +
               String(describing: UnicodeScalar(self       & 0xff)!)
    }
}

extension UInt16 {
    init(bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}

extension UInt32 {
    init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
    }
}

extension Int {
    init(fromFPE2 bytes: (UInt8, UInt8)) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }
}

extension Float {
    init?(_ bytes: [UInt8]) {
        self = bytes.withUnsafeBytes {
            return $0.load(fromByteOffset: 0, as: Self.self)
        }
    }

    var bytes: [UInt8] {
        withUnsafeBytes(of: self, Array.init)
    }
}

public class SMC {
    public static let shared = SMC()
    private var conn: io_connect_t = 0
    private let logger = Logger(subsystem: "com.shariq.sapphireHelper", category: "SMC")

    public init?() {
        var result: kern_return_t
        var iterator: io_iterator_t = 0
        let device: io_object_t

        let matchingDictionary: CFMutableDictionary = IOServiceMatching("AppleSMC")
        result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDictionary, &iterator)
        if result != kIOReturnSuccess {
            logger.error("Error IOServiceGetMatchingServices(): \(String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown")")
            return nil
        }

        device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        if device == 0 {
            logger.error("Error IOIteratorNext(): No matching SMC service found.")
            return nil
        }

        result = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        if result != kIOReturnSuccess {
            logger.error("Error IOServiceOpen(): \(String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown")")
            return nil
        }
    }

    deinit {
        let result = self.close()
        if result != kIOReturnSuccess {
            logger.error("Error closing SMC connection: \(String(cString: mach_error_string(result), encoding: .ascii) ?? "unknown")")
        }
    }

    public func close() -> kern_return_t {
        return IOServiceClose(conn)
    }

    public func getValue(_ key: String) -> Double? {
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess, val.dataSize > 0 else { return nil }

        if val.bytes.first(where: { $0 != 0 }) == nil && !["FS! ", "F0Md", "F1Md"].contains(val.key) {
            return nil
        }

        let data = Data(bytes: val.bytes, count: Int(val.dataSize))
        return val.dataType.parse(data: data)
    }

    public func getStringValue(_ key: String) -> String? {
        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess, val.dataSize > 0 else { return nil }

        if val.bytes.first(where: { $0 != 0 }) == nil { return nil }

        if val.dataType == SMCDataType.FDS.rawValue {
            let str = val.bytes[4..<16].compactMap { UnicodeScalar($0) }.map(Character.init)
            return String(str).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    public func getAllKeys() -> [String] {
        var list: [String] = []
        guard let keysNum = self.getValue("#KEY") else {
            logger.error("Could not read #KEY to get the number of SMC keys.")
            return list
        }

        for i in 0...Int(keysNum) {
            var input = SMCKeyData_t()
            var output = SMCKeyData_t()
            input.data8 = SMCKeys.readIndex.rawValue
            input.data32 = UInt32(i)

            if call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output) == kIOReturnSuccess {
                list.append(output.key.toString())
            }
        }
        return list
    }

    // MARK: - Fan Control

    public func setFanMode(_ id: Int, mode: FanMode) -> kern_return_t {
        logger.log("Setting Fan \(id) to mode '\(String(describing: mode))'.")

        let fsResult = setForceFanMode(for: id, enabled: mode == .forced)
        if fsResult != kIOReturnSuccess {
            logger.error("Failed to write to FS! key for fan \(id). Error: \(fsResult)")
        }

        let key = "F\(id)Md"
        let data = Data([UInt8(mode.rawValue)])
        logger.log("Writing to individual fan mode key '\(key)' with value \(mode.rawValue)...")
        let mdResult = writeData(key, data: data)
        if mdResult != kIOReturnSuccess {
            logger.error("Failed to write to individual fan mode key '\(key)'. Error: \(mdResult)")
        }

        return mdResult
    }

    private func setForceFanMode(for fanIndex: Int, enabled: Bool) -> kern_return_t {
        guard let currentMask = readFanForceMask() else {
            logger.warning("Could not read the 'FS! ' key. This Mac might not support it. Skipping this step.")
            return kIOReturnSuccess
        }

        let fanBit: UInt16 = 1 << fanIndex
        let newMask: UInt16 = enabled ? (currentMask | fanBit) : (currentMask & ~fanBit)

        if newMask == currentMask {
            logger.log("'FS! ' mask is already set correctly (\(String(format: "0x%04x", newMask))). No write needed.")
            return kIOReturnSuccess
        }

        logger.log("Writing new 'FS! ' mask. From \(String(format: "0x%04x", currentMask)) to \(String(format: "0x%04x", newMask)).")
        return writeFanForceMask(mask: newMask)
    }

    private func readFanForceMask() -> UInt16? {
        var val = SMCVal_t("FS! ")
        guard read(&val) == kIOReturnSuccess, val.dataSize >= 2 else { return nil }
        return UInt16(bytes: (val.bytes[0], val.bytes[1]))
    }

    private func writeFanForceMask(mask: UInt16) -> kern_return_t {
        var val = SMCVal_t("FS! ")
        val.dataSize = 2
        val.dataType = "ui16"
        val.bytes[0] = UInt8(mask >> 8)
        val.bytes[1] = UInt8(mask & 0xFF)
        return write(val)
    }

    public func setFanSpeed(_ id: Int, speed: Int) -> kern_return_t {
        let key = "F\(id)Tg"
        logger.log("Attempting to set fan \(id) speed to \(speed) RPM for key '\(key)'")

        var val = SMCVal_t(key)
        guard read(&val) == kIOReturnSuccess else {
            logger.error("Could not read info for key '\(key)'.")
            return kIOReturnNotFound
        }

        logger.log("Detected data type for key '\(key)' is '\(val.dataType)' with size \(val.dataSize).")

        if val.dataType == SMCDataType.FLT.rawValue {
            let bytes = Float(speed).bytes
            for i in 0..<bytes.count { val.bytes[i] = bytes[i] }
        } else if val.dataType == SMCDataType.FPE2.rawValue {
            let encodedSpeed = UInt16(clamping: speed) << 2
            val.bytes[0] = UInt8(encodedSpeed >> 8)
            val.bytes[1] = UInt8(encodedSpeed & 0xFF)
        } else {
            logger.error("Unsupported data type '\(val.dataType)' for fan speed key '\(key)'.")
            return kIOReturnUnsupported
        }

        return write(val)
    }

    // MARK: - Internal I/O Functions

    private func read(_ value: UnsafeMutablePointer<SMCVal_t>) -> kern_return_t {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = FourCharCode(fromString: value.pointee.key)
        input.data8 = SMCKeys.readKeyInfo.rawValue

        var result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        if result != kIOReturnSuccess { return result }

        value.pointee.dataSize = UInt32(output.keyInfo.dataSize)
        value.pointee.dataType = output.keyInfo.dataType.toString()
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCKeys.readBytes.rawValue

        result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        if result != kIOReturnSuccess { return result }

        memcpy(&value.pointee.bytes, &output.bytes, Int(value.pointee.dataSize))

        return kIOReturnSuccess
    }

    public func writeData(_ key: String, data: Data) -> kern_return_t {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = FourCharCode(fromString: key)
        input.keyInfo.dataSize = IOByteCount32(data.count)
        input.data8 = SMCKeys.writeBytes.rawValue

        withUnsafeMutableBytes(of: &input.bytes) { $0.copyBytes(from: data[0..<min(data.count, 32)]) }

        return call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
    }

    private func write(_ value: SMCVal_t) -> kern_return_t {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = FourCharCode(fromString: value.key)
        input.data8 = SMCKeys.writeBytes.rawValue
        input.keyInfo.dataSize = IOByteCount32(value.dataSize)

        withUnsafeMutablePointer(to: &input.bytes) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 32) {
                let buffer = UnsafeMutableBufferPointer(start: $0, count: 32)
                for i in 0..<Int(value.dataSize) { buffer[i] = value.bytes[i] }
            }
        }

        return self.call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
    }

    private func call(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        return IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
    }
}

extension String {
    func parse(data: Data) -> Double {
        let type = self
        switch type {
        case "fp1f": return Double(UInt16(data[0]) << 8 + UInt16(data[1])) / 32768.0
        case "fp4c": return Double(UInt16(data[0]) << 8 + UInt16(data[1])) / 4096.0
        case "fp6a": return Double(UInt16(data[0]) << 8 + UInt16(data[1])) / 1024.0
        case "fp88": return Double(UInt16(data[0]) << 8 + UInt16(data[1])) / 256.0
        case "fpa4": return Double(UInt16(data[0]) << 8 + UInt16(data[1])) / 16.0
        case "fpc2": return Double(UInt16(data[0]) << 8 + UInt16(data[1])) / 4.0
        case "fpe2": return Double(Int(fromFPE2: (data[0], data[1])))
        case "flt ":
            guard data.count >= 4 else { return 0 }
            let floatValue: Float = data.withUnsafeBytes { $0.load(as: Float.self) }
            return Double(floatValue)
        case "si8 ": return Double(Int8(bitPattern: data[0]))
        case "ui8 ": return Double(data[0])
        case "si16": return Double(Int16(bigEndian: data.withUnsafeBytes { $0.load(as: Int16.self) }))
        case "ui16": return Double(UInt16(bigEndian: data.withUnsafeBytes { $0.load(as: UInt16.self) }))
        case "ui32": return Double(UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) }))
        case "ui64": return Double(UInt64(bigEndian: data.withUnsafeBytes { $0.load(as: UInt64.self) }))
        default: return 0
        }
    }
}