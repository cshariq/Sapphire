//
//  mac_hw_info.pb.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-12
//

import Foundation
import SwiftProtobuf

fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

struct Bbhwinfo_HwInfo {

  var inner: Bbhwinfo_HwInfo.InnerHwInfo {
    get {return _storage._inner ?? Bbhwinfo_HwInfo.InnerHwInfo()}
    set {_uniqueStorage()._inner = newValue}
  }
  var hasInner: Bool {return _storage._inner != nil}
  mutating func clearInner() {_uniqueStorage()._inner = nil}

  var version: String {
    get {return _storage._version}
    set {_uniqueStorage()._version = newValue}
  }

  var protocolVersion: Int32 {
    get {return _storage._protocolVersion}
    set {_uniqueStorage()._protocolVersion = newValue}
  }

  var deviceID: String {
    get {return _storage._deviceID}
    set {_uniqueStorage()._deviceID = newValue}
  }

  var icloudUa: String {
    get {return _storage._icloudUa}
    set {_uniqueStorage()._icloudUa = newValue}
  }

  var aoskitVersion: String {
    get {return _storage._aoskitVersion}
    set {_uniqueStorage()._aoskitVersion = newValue}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  struct InnerHwInfo {

    var productName: String = String()

    var ioMacAddress: Data = Data()

    var platformSerialNumber: String = String()

    var platformUuid: String = String()

    var rootDiskUuid: String = String()

    var boardID: String = String()

    var osBuildNum: String = String()

    var platformSerialNumberEnc: Data = Data()

    var platformUuidEnc: Data = Data()

    var rootDiskUuidEnc: Data = Data()

    var rom: Data = Data()

    var romEnc: Data = Data()

    var mlb: String = String()

    var mlbEnc: Data = Data()

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}
  }

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Bbhwinfo_HwInfo: @unchecked Sendable {}
extension Bbhwinfo_HwInfo.InnerHwInfo: @unchecked Sendable {}
#endif

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "bbhwinfo"

extension Bbhwinfo_HwInfo: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".HwInfo"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "inner"),
    2: .same(proto: "version"),
    3: .standard(proto: "protocol_version"),
    4: .standard(proto: "device_id"),
    5: .standard(proto: "icloud_ua"),
    6: .standard(proto: "aoskit_version"),
  ]

  fileprivate class _StorageClass {
    var _inner: Bbhwinfo_HwInfo.InnerHwInfo? = nil
    var _version: String = String()
    var _protocolVersion: Int32 = 0
    var _deviceID: String = String()
    var _icloudUa: String = String()
    var _aoskitVersion: String = String()

    #if swift(>=5.10)
      static nonisolated(unsafe) let defaultInstance = _StorageClass()
    #else
      static let defaultInstance = _StorageClass()
    #endif

    private init() {}

    init(copying source: _StorageClass) {
      _inner = source._inner
      _version = source._version
      _protocolVersion = source._protocolVersion
      _deviceID = source._deviceID
      _icloudUa = source._icloudUa
      _aoskitVersion = source._aoskitVersion
    }
  }

  fileprivate mutating func _uniqueStorage() -> _StorageClass {
    if !isKnownUniquelyReferenced(&_storage) {
      _storage = _StorageClass(copying: _storage)
    }
    return _storage
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    _ = _uniqueStorage()
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      while let fieldNumber = try decoder.nextFieldNumber() {
        switch fieldNumber {
        case 1: try { try decoder.decodeSingularMessageField(value: &_storage._inner) }()
        case 2: try { try decoder.decodeSingularStringField(value: &_storage._version) }()
        case 3: try { try decoder.decodeSingularInt32Field(value: &_storage._protocolVersion) }()
        case 4: try { try decoder.decodeSingularStringField(value: &_storage._deviceID) }()
        case 5: try { try decoder.decodeSingularStringField(value: &_storage._icloudUa) }()
        case 6: try { try decoder.decodeSingularStringField(value: &_storage._aoskitVersion) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      try { if let v = _storage._inner {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
      } }()
      if !_storage._version.isEmpty {
        try visitor.visitSingularStringField(value: _storage._version, fieldNumber: 2)
      }
      if _storage._protocolVersion != 0 {
        try visitor.visitSingularInt32Field(value: _storage._protocolVersion, fieldNumber: 3)
      }
      if !_storage._deviceID.isEmpty {
        try visitor.visitSingularStringField(value: _storage._deviceID, fieldNumber: 4)
      }
      if !_storage._icloudUa.isEmpty {
        try visitor.visitSingularStringField(value: _storage._icloudUa, fieldNumber: 5)
      }
      if !_storage._aoskitVersion.isEmpty {
        try visitor.visitSingularStringField(value: _storage._aoskitVersion, fieldNumber: 6)
      }
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Bbhwinfo_HwInfo, rhs: Bbhwinfo_HwInfo) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._inner != rhs_storage._inner {return false}
        if _storage._version != rhs_storage._version {return false}
        if _storage._protocolVersion != rhs_storage._protocolVersion {return false}
        if _storage._deviceID != rhs_storage._deviceID {return false}
        if _storage._icloudUa != rhs_storage._icloudUa {return false}
        if _storage._aoskitVersion != rhs_storage._aoskitVersion {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Bbhwinfo_HwInfo.InnerHwInfo: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Bbhwinfo_HwInfo.protoMessageName + ".InnerHwInfo"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "product_name"),
    2: .standard(proto: "io_mac_address"),
    3: .standard(proto: "platform_serial_number"),
    4: .standard(proto: "platform_uuid"),
    5: .standard(proto: "root_disk_uuid"),
    6: .standard(proto: "board_id"),
    7: .standard(proto: "os_build_num"),
    8: .standard(proto: "platform_serial_number_enc"),
    9: .standard(proto: "platform_uuid_enc"),
    10: .standard(proto: "root_disk_uuid_enc"),
    11: .same(proto: "rom"),
    12: .standard(proto: "rom_enc"),
    13: .same(proto: "mlb"),
    14: .standard(proto: "mlb_enc"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.productName) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self.ioMacAddress) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.platformSerialNumber) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.platformUuid) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self.rootDiskUuid) }()
      case 6: try { try decoder.decodeSingularStringField(value: &self.boardID) }()
      case 7: try { try decoder.decodeSingularStringField(value: &self.osBuildNum) }()
      case 8: try { try decoder.decodeSingularBytesField(value: &self.platformSerialNumberEnc) }()
      case 9: try { try decoder.decodeSingularBytesField(value: &self.platformUuidEnc) }()
      case 10: try { try decoder.decodeSingularBytesField(value: &self.rootDiskUuidEnc) }()
      case 11: try { try decoder.decodeSingularBytesField(value: &self.rom) }()
      case 12: try { try decoder.decodeSingularBytesField(value: &self.romEnc) }()
      case 13: try { try decoder.decodeSingularStringField(value: &self.mlb) }()
      case 14: try { try decoder.decodeSingularBytesField(value: &self.mlbEnc) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.productName.isEmpty {
      try visitor.visitSingularStringField(value: self.productName, fieldNumber: 1)
    }
    if !self.ioMacAddress.isEmpty {
      try visitor.visitSingularBytesField(value: self.ioMacAddress, fieldNumber: 2)
    }
    if !self.platformSerialNumber.isEmpty {
      try visitor.visitSingularStringField(value: self.platformSerialNumber, fieldNumber: 3)
    }
    if !self.platformUuid.isEmpty {
      try visitor.visitSingularStringField(value: self.platformUuid, fieldNumber: 4)
    }
    if !self.rootDiskUuid.isEmpty {
      try visitor.visitSingularStringField(value: self.rootDiskUuid, fieldNumber: 5)
    }
    if !self.boardID.isEmpty {
      try visitor.visitSingularStringField(value: self.boardID, fieldNumber: 6)
    }
    if !self.osBuildNum.isEmpty {
      try visitor.visitSingularStringField(value: self.osBuildNum, fieldNumber: 7)
    }
    if !self.platformSerialNumberEnc.isEmpty {
      try visitor.visitSingularBytesField(value: self.platformSerialNumberEnc, fieldNumber: 8)
    }
    if !self.platformUuidEnc.isEmpty {
      try visitor.visitSingularBytesField(value: self.platformUuidEnc, fieldNumber: 9)
    }
    if !self.rootDiskUuidEnc.isEmpty {
      try visitor.visitSingularBytesField(value: self.rootDiskUuidEnc, fieldNumber: 10)
    }
    if !self.rom.isEmpty {
      try visitor.visitSingularBytesField(value: self.rom, fieldNumber: 11)
    }
    if !self.romEnc.isEmpty {
      try visitor.visitSingularBytesField(value: self.romEnc, fieldNumber: 12)
    }
    if !self.mlb.isEmpty {
      try visitor.visitSingularStringField(value: self.mlb, fieldNumber: 13)
    }
    if !self.mlbEnc.isEmpty {
      try visitor.visitSingularBytesField(value: self.mlbEnc, fieldNumber: 14)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Bbhwinfo_HwInfo.InnerHwInfo, rhs: Bbhwinfo_HwInfo.InnerHwInfo) -> Bool {
    if lhs.productName != rhs.productName {return false}
    if lhs.ioMacAddress != rhs.ioMacAddress {return false}
    if lhs.platformSerialNumber != rhs.platformSerialNumber {return false}
    if lhs.platformUuid != rhs.platformUuid {return false}
    if lhs.rootDiskUuid != rhs.rootDiskUuid {return false}
    if lhs.boardID != rhs.boardID {return false}
    if lhs.osBuildNum != rhs.osBuildNum {return false}
    if lhs.platformSerialNumberEnc != rhs.platformSerialNumberEnc {return false}
    if lhs.platformUuidEnc != rhs.platformUuidEnc {return false}
    if lhs.rootDiskUuidEnc != rhs.rootDiskUuidEnc {return false}
    if lhs.rom != rhs.rom {return false}
    if lhs.romEnc != rhs.romEnc {return false}
    if lhs.mlb != rhs.mlb {return false}
    if lhs.mlbEnc != rhs.mlbEnc {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}