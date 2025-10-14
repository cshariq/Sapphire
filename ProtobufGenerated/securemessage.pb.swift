//
//  securemessage.pb.swift
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

enum Securemessage_SigScheme: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case hmacSha256
  case ecdsaP256Sha256

  case rsa2048Sha256

  init() {
    self = .hmacSha256
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 1: self = .hmacSha256
    case 2: self = .ecdsaP256Sha256
    case 3: self = .rsa2048Sha256
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .hmacSha256: return 1
    case .ecdsaP256Sha256: return 2
    case .rsa2048Sha256: return 3
    }
  }

}

#if swift(>=4.2)

extension Securemessage_SigScheme: CaseIterable {
}

#endif

enum Securemessage_EncScheme: SwiftProtobuf.Enum {
  typealias RawValue = Int

  case none
  case aes256Cbc

  init() {
    self = .none
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 1: self = .none
    case 2: self = .aes256Cbc
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .none: return 1
    case .aes256Cbc: return 2
    }
  }

}

#if swift(>=4.2)

extension Securemessage_EncScheme: CaseIterable {
}

#endif

enum Securemessage_PublicKeyType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case ecP256
  case rsa2048

  case dh2048Modp

  init() {
    self = .ecP256
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 1: self = .ecP256
    case 2: self = .rsa2048
    case 3: self = .dh2048Modp
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .ecP256: return 1
    case .rsa2048: return 2
    case .dh2048Modp: return 3
    }
  }

}

#if swift(>=4.2)

extension Securemessage_PublicKeyType: CaseIterable {
}

#endif

struct Securemessage_SecureMessage {

  var headerAndBody: Data {
    get {return _headerAndBody ?? Data()}
    set {_headerAndBody = newValue}
  }
  var hasHeaderAndBody: Bool {return self._headerAndBody != nil}
  mutating func clearHeaderAndBody() {self._headerAndBody = nil}

  var signature: Data {
    get {return _signature ?? Data()}
    set {_signature = newValue}
  }
  var hasSignature: Bool {return self._signature != nil}
  mutating func clearSignature() {self._signature = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _headerAndBody: Data? = nil
  fileprivate var _signature: Data? = nil
}

struct Securemessage_Header {

  var signatureScheme: Securemessage_SigScheme {
    get {return _signatureScheme ?? .hmacSha256}
    set {_signatureScheme = newValue}
  }
  var hasSignatureScheme: Bool {return self._signatureScheme != nil}
  mutating func clearSignatureScheme() {self._signatureScheme = nil}

  var encryptionScheme: Securemessage_EncScheme {
    get {return _encryptionScheme ?? .none}
    set {_encryptionScheme = newValue}
  }
  var hasEncryptionScheme: Bool {return self._encryptionScheme != nil}
  mutating func clearEncryptionScheme() {self._encryptionScheme = nil}

  var verificationKeyID: Data {
    get {return _verificationKeyID ?? Data()}
    set {_verificationKeyID = newValue}
  }
  var hasVerificationKeyID: Bool {return self._verificationKeyID != nil}
  mutating func clearVerificationKeyID() {self._verificationKeyID = nil}

  var decryptionKeyID: Data {
    get {return _decryptionKeyID ?? Data()}
    set {_decryptionKeyID = newValue}
  }
  var hasDecryptionKeyID: Bool {return self._decryptionKeyID != nil}
  mutating func clearDecryptionKeyID() {self._decryptionKeyID = nil}

  var iv: Data {
    get {return _iv ?? Data()}
    set {_iv = newValue}
  }
  var hasIv: Bool {return self._iv != nil}
  mutating func clearIv() {self._iv = nil}

  var publicMetadata: Data {
    get {return _publicMetadata ?? Data()}
    set {_publicMetadata = newValue}
  }
  var hasPublicMetadata: Bool {return self._publicMetadata != nil}
  mutating func clearPublicMetadata() {self._publicMetadata = nil}

  var associatedDataLength: UInt32 {
    get {return _associatedDataLength ?? 0}
    set {_associatedDataLength = newValue}
  }
  var hasAssociatedDataLength: Bool {return self._associatedDataLength != nil}
  mutating func clearAssociatedDataLength() {self._associatedDataLength = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _signatureScheme: Securemessage_SigScheme? = nil
  fileprivate var _encryptionScheme: Securemessage_EncScheme? = nil
  fileprivate var _verificationKeyID: Data? = nil
  fileprivate var _decryptionKeyID: Data? = nil
  fileprivate var _iv: Data? = nil
  fileprivate var _publicMetadata: Data? = nil
  fileprivate var _associatedDataLength: UInt32? = nil
}

struct Securemessage_HeaderAndBody {

  var header: Securemessage_Header {
    get {return _header ?? Securemessage_Header()}
    set {_header = newValue}
  }
  var hasHeader: Bool {return self._header != nil}
  mutating func clearHeader() {self._header = nil}

  var body: Data {
    get {return _body ?? Data()}
    set {_body = newValue}
  }
  var hasBody: Bool {return self._body != nil}
  mutating func clearBody() {self._body = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _header: Securemessage_Header? = nil
  fileprivate var _body: Data? = nil
}

struct Securemessage_HeaderAndBodyInternal {

  var header: Data {
    get {return _header ?? Data()}
    set {_header = newValue}
  }
  var hasHeader: Bool {return self._header != nil}
  mutating func clearHeader() {self._header = nil}

  var body: Data {
    get {return _body ?? Data()}
    set {_body = newValue}
  }
  var hasBody: Bool {return self._body != nil}
  mutating func clearBody() {self._body = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _header: Data? = nil
  fileprivate var _body: Data? = nil
}

struct Securemessage_EcP256PublicKey {

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

  fileprivate var _x: Data? = nil
  fileprivate var _y: Data? = nil
}

struct Securemessage_SimpleRsaPublicKey {

  var n: Data {
    get {return _n ?? Data()}
    set {_n = newValue}
  }
  var hasN: Bool {return self._n != nil}
  mutating func clearN() {self._n = nil}

  var e: Int32 {
    get {return _e ?? 65537}
    set {_e = newValue}
  }
  var hasE: Bool {return self._e != nil}
  mutating func clearE() {self._e = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _n: Data? = nil
  fileprivate var _e: Int32? = nil
}

struct Securemessage_DhPublicKey {

  var y: Data {
    get {return _y ?? Data()}
    set {_y = newValue}
  }
  var hasY: Bool {return self._y != nil}
  mutating func clearY() {self._y = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _y: Data? = nil
}

struct Securemessage_GenericPublicKey {

  var type: Securemessage_PublicKeyType {
    get {return _type ?? .ecP256}
    set {_type = newValue}
  }
  var hasType: Bool {return self._type != nil}
  mutating func clearType() {self._type = nil}

  var ecP256PublicKey: Securemessage_EcP256PublicKey {
    get {return _ecP256PublicKey ?? Securemessage_EcP256PublicKey()}
    set {_ecP256PublicKey = newValue}
  }
  var hasEcP256PublicKey: Bool {return self._ecP256PublicKey != nil}
  mutating func clearEcP256PublicKey() {self._ecP256PublicKey = nil}

  var rsa2048PublicKey: Securemessage_SimpleRsaPublicKey {
    get {return _rsa2048PublicKey ?? Securemessage_SimpleRsaPublicKey()}
    set {_rsa2048PublicKey = newValue}
  }
  var hasRsa2048PublicKey: Bool {return self._rsa2048PublicKey != nil}
  mutating func clearRsa2048PublicKey() {self._rsa2048PublicKey = nil}

  var dh2048PublicKey: Securemessage_DhPublicKey {
    get {return _dh2048PublicKey ?? Securemessage_DhPublicKey()}
    set {_dh2048PublicKey = newValue}
  }
  var hasDh2048PublicKey: Bool {return self._dh2048PublicKey != nil}
  mutating func clearDh2048PublicKey() {self._dh2048PublicKey = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _type: Securemessage_PublicKeyType? = nil
  fileprivate var _ecP256PublicKey: Securemessage_EcP256PublicKey? = nil
  fileprivate var _rsa2048PublicKey: Securemessage_SimpleRsaPublicKey? = nil
  fileprivate var _dh2048PublicKey: Securemessage_DhPublicKey? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Securemessage_SigScheme: @unchecked Sendable {}
extension Securemessage_EncScheme: @unchecked Sendable {}
extension Securemessage_PublicKeyType: @unchecked Sendable {}
extension Securemessage_SecureMessage: @unchecked Sendable {}
extension Securemessage_Header: @unchecked Sendable {}
extension Securemessage_HeaderAndBody: @unchecked Sendable {}
extension Securemessage_HeaderAndBodyInternal: @unchecked Sendable {}
extension Securemessage_EcP256PublicKey: @unchecked Sendable {}
extension Securemessage_SimpleRsaPublicKey: @unchecked Sendable {}
extension Securemessage_DhPublicKey: @unchecked Sendable {}
extension Securemessage_GenericPublicKey: @unchecked Sendable {}
#endif

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "securemessage"

extension Securemessage_SigScheme: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "HMAC_SHA256"),
    2: .same(proto: "ECDSA_P256_SHA256"),
    3: .same(proto: "RSA2048_SHA256"),
  ]
}

extension Securemessage_EncScheme: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "NONE"),
    2: .same(proto: "AES_256_CBC"),
  ]
}

extension Securemessage_PublicKeyType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "EC_P256"),
    2: .same(proto: "RSA2048"),
    3: .same(proto: "DH2048_MODP"),
  ]
}

extension Securemessage_SecureMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SecureMessage"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "header_and_body"),
    2: .same(proto: "signature"),
  ]

  public var isInitialized: Bool {
    if self._headerAndBody == nil {return false}
    if self._signature == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._headerAndBody) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._signature) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._headerAndBody {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._signature {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_SecureMessage, rhs: Securemessage_SecureMessage) -> Bool {
    if lhs._headerAndBody != rhs._headerAndBody {return false}
    if lhs._signature != rhs._signature {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securemessage_Header: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Header"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "signature_scheme"),
    2: .standard(proto: "encryption_scheme"),
    3: .standard(proto: "verification_key_id"),
    4: .standard(proto: "decryption_key_id"),
    5: .same(proto: "iv"),
    6: .standard(proto: "public_metadata"),
    7: .standard(proto: "associated_data_length"),
  ]

  public var isInitialized: Bool {
    if self._signatureScheme == nil {return false}
    if self._encryptionScheme == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._signatureScheme) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._encryptionScheme) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._verificationKeyID) }()
      case 4: try { try decoder.decodeSingularBytesField(value: &self._decryptionKeyID) }()
      case 5: try { try decoder.decodeSingularBytesField(value: &self._iv) }()
      case 6: try { try decoder.decodeSingularBytesField(value: &self._publicMetadata) }()
      case 7: try { try decoder.decodeSingularUInt32Field(value: &self._associatedDataLength) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._signatureScheme {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._encryptionScheme {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._verificationKeyID {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._decryptionKeyID {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._iv {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._publicMetadata {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._associatedDataLength {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 7)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_Header, rhs: Securemessage_Header) -> Bool {
    if lhs._signatureScheme != rhs._signatureScheme {return false}
    if lhs._encryptionScheme != rhs._encryptionScheme {return false}
    if lhs._verificationKeyID != rhs._verificationKeyID {return false}
    if lhs._decryptionKeyID != rhs._decryptionKeyID {return false}
    if lhs._iv != rhs._iv {return false}
    if lhs._publicMetadata != rhs._publicMetadata {return false}
    if lhs._associatedDataLength != rhs._associatedDataLength {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securemessage_HeaderAndBody: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".HeaderAndBody"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "header"),
    2: .same(proto: "body"),
  ]

  public var isInitialized: Bool {
    if self._header == nil {return false}
    if self._body == nil {return false}
    if let v = self._header, !v.isInitialized {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._header) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._body) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._header {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._body {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_HeaderAndBody, rhs: Securemessage_HeaderAndBody) -> Bool {
    if lhs._header != rhs._header {return false}
    if lhs._body != rhs._body {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securemessage_HeaderAndBodyInternal: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".HeaderAndBodyInternal"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "header"),
    2: .same(proto: "body"),
  ]

  public var isInitialized: Bool {
    if self._header == nil {return false}
    if self._body == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._header) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._body) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._header {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._body {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_HeaderAndBodyInternal, rhs: Securemessage_HeaderAndBodyInternal) -> Bool {
    if lhs._header != rhs._header {return false}
    if lhs._body != rhs._body {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securemessage_EcP256PublicKey: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".EcP256PublicKey"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "x"),
    2: .same(proto: "y"),
  ]

  public var isInitialized: Bool {
    if self._x == nil {return false}
    if self._y == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._x) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._y) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._x {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._y {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_EcP256PublicKey, rhs: Securemessage_EcP256PublicKey) -> Bool {
    if lhs._x != rhs._x {return false}
    if lhs._y != rhs._y {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securemessage_SimpleRsaPublicKey: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".SimpleRsaPublicKey"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "n"),
    2: .same(proto: "e"),
  ]

  public var isInitialized: Bool {
    if self._n == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._n) }()
      case 2: try { try decoder.decodeSingularInt32Field(value: &self._e) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._n {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._e {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_SimpleRsaPublicKey, rhs: Securemessage_SimpleRsaPublicKey) -> Bool {
    if lhs._n != rhs._n {return false}
    if lhs._e != rhs._e {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securemessage_DhPublicKey: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DhPublicKey"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "y"),
  ]

  public var isInitialized: Bool {
    if self._y == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._y) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._y {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_DhPublicKey, rhs: Securemessage_DhPublicKey) -> Bool {
    if lhs._y != rhs._y {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securemessage_GenericPublicKey: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GenericPublicKey"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "type"),
    2: .standard(proto: "ec_p256_public_key"),
    3: .standard(proto: "rsa2048_public_key"),
    4: .standard(proto: "dh2048_public_key"),
  ]

  public var isInitialized: Bool {
    if self._type == nil {return false}
    if let v = self._ecP256PublicKey, !v.isInitialized {return false}
    if let v = self._rsa2048PublicKey, !v.isInitialized {return false}
    if let v = self._dh2048PublicKey, !v.isInitialized {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._type) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._ecP256PublicKey) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._rsa2048PublicKey) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._dh2048PublicKey) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._type {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._ecP256PublicKey {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._rsa2048PublicKey {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._dh2048PublicKey {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securemessage_GenericPublicKey, rhs: Securemessage_GenericPublicKey) -> Bool {
    if lhs._type != rhs._type {return false}
    if lhs._ecP256PublicKey != rhs._ecP256PublicKey {return false}
    if lhs._rsa2048PublicKey != rhs._rsa2048PublicKey {return false}
    if lhs._dh2048PublicKey != rhs._dh2048PublicKey {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}