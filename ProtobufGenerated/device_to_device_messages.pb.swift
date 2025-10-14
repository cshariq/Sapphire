//
//  device_to_device_messages.pb.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-29
//

import Foundation
import SwiftProtobuf

fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

enum Securegcm_Curve: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case ed25519

  init() {
    self = .ed25519
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 1: self = .ed25519
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .ed25519: return 1
    }
  }

}

#if swift(>=4.2)

extension Securegcm_Curve: CaseIterable {
}

#endif

struct Securegcm_DeviceToDeviceMessage {

  var message: Data {
    get {return _message ?? Data()}
    set {_message = newValue}
  }
  var hasMessage: Bool {return self._message != nil}
  mutating func clearMessage() {self._message = nil}

  var sequenceNumber: Int32 {
    get {return _sequenceNumber ?? 0}
    set {_sequenceNumber = newValue}
  }
  var hasSequenceNumber: Bool {return self._sequenceNumber != nil}
  mutating func clearSequenceNumber() {self._sequenceNumber = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _message: Data? = nil
  fileprivate var _sequenceNumber: Int32? = nil
}

struct Securegcm_InitiatorHello {

  var publicDhKey: Securemessage_GenericPublicKey {
    get {return _publicDhKey ?? Securemessage_GenericPublicKey()}
    set {_publicDhKey = newValue}
  }
  var hasPublicDhKey: Bool {return self._publicDhKey != nil}
  mutating func clearPublicDhKey() {self._publicDhKey = nil}

  var protocolVersion: Int32 {
    get {return _protocolVersion ?? 0}
    set {_protocolVersion = newValue}
  }
  var hasProtocolVersion: Bool {return self._protocolVersion != nil}
  mutating func clearProtocolVersion() {self._protocolVersion = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _publicDhKey: Securemessage_GenericPublicKey? = nil
  fileprivate var _protocolVersion: Int32? = nil
}

struct Securegcm_ResponderHello {

  var publicDhKey: Securemessage_GenericPublicKey {
    get {return _publicDhKey ?? Securemessage_GenericPublicKey()}
    set {_publicDhKey = newValue}
  }
  var hasPublicDhKey: Bool {return self._publicDhKey != nil}
  mutating func clearPublicDhKey() {self._publicDhKey = nil}

  var protocolVersion: Int32 {
    get {return _protocolVersion ?? 0}
    set {_protocolVersion = newValue}
  }
  var hasProtocolVersion: Bool {return self._protocolVersion != nil}
  mutating func clearProtocolVersion() {self._protocolVersion = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _publicDhKey: Securemessage_GenericPublicKey? = nil
  fileprivate var _protocolVersion: Int32? = nil
}

struct Securegcm_EcPoint {

  var curve: Securegcm_Curve {
    get {return _curve ?? .ed25519}
    set {_curve = newValue}
  }
  var hasCurve: Bool {return self._curve != nil}
  mutating func clearCurve() {self._curve = nil}

  var x: Data {
    get {return _x ?? Data()}
    set {_x = newValue}
  }
  var hasX: Bool {return self._x != nil}
  mutating func clearX() {self._x = nil}

  var y: Data {
    get {return _y ?? Data()}
    set {_y = newValue}
  }
  var hasY: Bool {return self._y != nil}
  mutating func clearY() {self._y = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _curve: Securegcm_Curve? = nil
  fileprivate var _x: Data? = nil
  fileprivate var _y: Data? = nil
}

struct Securegcm_SpakeHandshakeMessage {

  var flowNumber: Int32 {
    get {return _flowNumber ?? 0}
    set {_flowNumber = newValue}
  }
  var hasFlowNumber: Bool {return self._flowNumber != nil}
  mutating func clearFlowNumber() {self._flowNumber = nil}

  var ecPoint: Securegcm_EcPoint {
    get {return _ecPoint ?? Securegcm_EcPoint()}
    set {_ecPoint = newValue}
  }
  var hasEcPoint: Bool {return self._ecPoint != nil}
  mutating func clearEcPoint() {self._ecPoint = nil}

  var hashValue_p: Data {
    get {return _hashValue_p ?? Data()}
    set {_hashValue_p = newValue}
  }
  var hasHashValue_p: Bool {return self._hashValue_p != nil}
  mutating func clearHashValue_p() {self._hashValue_p = nil}

  var payload: Data {
    get {return _payload ?? Data()}
    set {_payload = newValue}
  }
  var hasPayload: Bool {return self._payload != nil}
  mutating func clearPayload() {self._payload = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _flowNumber: Int32? = nil
  fileprivate var _ecPoint: Securegcm_EcPoint? = nil
  fileprivate var _hashValue_p: Data? = nil
  fileprivate var _payload: Data? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Securegcm_Curve: @unchecked Sendable {}
extension Securegcm_DeviceToDeviceMessage: @unchecked Sendable {}
extension Securegcm_InitiatorHello: @unchecked Sendable {}
extension Securegcm_ResponderHello: @unchecked Sendable {}
extension Securegcm_EcPoint: @unchecked Sendable {}
extension Securegcm_SpakeHandshakeMessage: @unchecked Sendable {}
#endif

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "securegcm"

extension Securegcm_Curve: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "ED_25519"),
  ]
}

extension Securegcm_DeviceToDeviceMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DeviceToDeviceMessage"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "message"),
    2: .standard(proto: "sequence_number"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._message) }()
      case 2: try { try decoder.decodeSingularInt32Field(value: &self._sequenceNumber) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._message {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._sequenceNumber {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_DeviceToDeviceMessage, rhs: Securegcm_DeviceToDeviceMessage) -> Bool {
    if lhs._message != rhs._message {return false}
    if lhs._sequenceNumber != rhs._sequenceNumber {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securegcm_InitiatorHello: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".InitiatorHello"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "public_dh_key"),
    2: .standard(proto: "protocol_version"),
  ]

  public var isInitialized: Bool {
    if let v = self._publicDhKey, !v.isInitialized {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._publicDhKey) }()
      case 2: try { try decoder.decodeSingularInt32Field(value: &self._protocolVersion) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._publicDhKey {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._protocolVersion {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_InitiatorHello, rhs: Securegcm_InitiatorHello) -> Bool {
    if lhs._publicDhKey != rhs._publicDhKey {return false}
    if lhs._protocolVersion != rhs._protocolVersion {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securegcm_ResponderHello: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ResponderHello"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "public_dh_key"),
    2: .standard(proto: "protocol_version"),
  ]

  public var isInitialized: Bool {
    if let v = self._publicDhKey, !v.isInitialized {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._publicDhKey) }()
      case 2: try { try decoder.decodeSingularInt32Field(value: &self._protocolVersion) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._publicDhKey {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._protocolVersion {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_ResponderHello, rhs: Securegcm_ResponderHello) -> Bool {
    if lhs._publicDhKey != rhs._publicDhKey {return false}
    if lhs._protocolVersion != rhs._protocolVersion {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securegcm_EcPoint: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".EcPoint"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "curve"),
    2: .same(proto: "x"),
    3: .same(proto: "y"),
  ]

  public var isInitialized: Bool {
    if self._curve == nil {return false}
    if self._x == nil {return false}
    if self._y == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._curve) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._x) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._y) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._curve {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._x {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._y {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_EcPoint, rhs: Securegcm_EcPoint) -> Bool {
    if lhs._curve != rhs._curve {return false}
    if lhs._x != rhs._x {return false}
    if lhs._y != rhs._y {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securegcm_SpakeHandshakeMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SpakeHandshakeMessage"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "flow_number"),
    2: .standard(proto: "ec_point"),
    3: .standard(proto: "hash_value"),
    4: .same(proto: "payload"),
  ]

  public var isInitialized: Bool {
    if let v = self._ecPoint, !v.isInitialized {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt32Field(value: &self._flowNumber) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._ecPoint) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._hashValue_p) }()
      case 4: try { try decoder.decodeSingularBytesField(value: &self._payload) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._flowNumber {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._ecPoint {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._hashValue_p {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._payload {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_SpakeHandshakeMessage, rhs: Securegcm_SpakeHandshakeMessage) -> Bool {
    if lhs._flowNumber != rhs._flowNumber {return false}
    if lhs._ecPoint != rhs._ecPoint {return false}
    if lhs._hashValue_p != rhs._hashValue_p {return false}
    if lhs._payload != rhs._payload {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}