//
//  wire_format.pb.swift
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

struct Sharing_Nearby_FileMetadata {

  var name: String {
    get {return _name ?? String()}
    set {_name = newValue}
  }
  var hasName: Bool {return self._name != nil}
  mutating func clearName() {self._name = nil}

  var type: Sharing_Nearby_FileMetadata.TypeEnum {
    get {return _type ?? .unknown}
    set {_type = newValue}
  }
  var hasType: Bool {return self._type != nil}
  mutating func clearType() {self._type = nil}

  var payloadID: Int64 {
    get {return _payloadID ?? 0}
    set {_payloadID = newValue}
  }
  var hasPayloadID: Bool {return self._payloadID != nil}
  mutating func clearPayloadID() {self._payloadID = nil}

  var size: Int64 {
    get {return _size ?? 0}
    set {_size = newValue}
  }
  var hasSize: Bool {return self._size != nil}
  mutating func clearSize() {self._size = nil}

  var mimeType: String {
    get {return _mimeType ?? "application/octet-stream"}
    set {_mimeType = newValue}
  }
  var hasMimeType: Bool {return self._mimeType != nil}
  mutating func clearMimeType() {self._mimeType = nil}

  var id: Int64 {
    get {return _id ?? 0}
    set {_id = newValue}
  }
  var hasID: Bool {return self._id != nil}
  mutating func clearID() {self._id = nil}

  var parentFolder: String {
    get {return _parentFolder ?? String()}
    set {_parentFolder = newValue}
  }
  var hasParentFolder: Bool {return self._parentFolder != nil}
  mutating func clearParentFolder() {self._parentFolder = nil}

  var attachmentHash: Int64 {
    get {return _attachmentHash ?? 0}
    set {_attachmentHash = newValue}
  }
  var hasAttachmentHash: Bool {return self._attachmentHash != nil}
  mutating func clearAttachmentHash() {self._attachmentHash = nil}

  var isSensitiveContent: Bool {
    get {return _isSensitiveContent ?? false}
    set {_isSensitiveContent = newValue}
  }
  var hasIsSensitiveContent: Bool {return self._isSensitiveContent != nil}
  mutating func clearIsSensitiveContent() {self._isSensitiveContent = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum TypeEnum: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown
    case image
    case video
    case androidApp
    case audio
    case document
    case contactCard

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .image
      case 2: self = .video
      case 3: self = .androidApp
      case 4: self = .audio
      case 5: self = .document
      case 6: self = .contactCard
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .image: return 1
      case .video: return 2
      case .androidApp: return 3
      case .audio: return 4
      case .document: return 5
      case .contactCard: return 6
      }
    }

  }

  init() {}

  fileprivate var _name: String? = nil
  fileprivate var _type: Sharing_Nearby_FileMetadata.TypeEnum? = nil
  fileprivate var _payloadID: Int64? = nil
  fileprivate var _size: Int64? = nil
  fileprivate var _mimeType: String? = nil
  fileprivate var _id: Int64? = nil
  fileprivate var _parentFolder: String? = nil
  fileprivate var _attachmentHash: Int64? = nil
  fileprivate var _isSensitiveContent: Bool? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_FileMetadata.TypeEnum: CaseIterable {
}

#endif

struct Sharing_Nearby_TextMetadata {

  var textTitle: String {
    get {return _textTitle ?? String()}
    set {_textTitle = newValue}
  }
  var hasTextTitle: Bool {return self._textTitle != nil}
  mutating func clearTextTitle() {self._textTitle = nil}

  var type: Sharing_Nearby_TextMetadata.TypeEnum {
    get {return _type ?? .unknown}
    set {_type = newValue}
  }
  var hasType: Bool {return self._type != nil}
  mutating func clearType() {self._type = nil}

  var payloadID: Int64 {
    get {return _payloadID ?? 0}
    set {_payloadID = newValue}
  }
  var hasPayloadID: Bool {return self._payloadID != nil}
  mutating func clearPayloadID() {self._payloadID = nil}

  var size: Int64 {
    get {return _size ?? 0}
    set {_size = newValue}
  }
  var hasSize: Bool {return self._size != nil}
  mutating func clearSize() {self._size = nil}

  var id: Int64 {
    get {return _id ?? 0}
    set {_id = newValue}
  }
  var hasID: Bool {return self._id != nil}
  mutating func clearID() {self._id = nil}

  var isSensitiveText: Bool {
    get {return _isSensitiveText ?? false}
    set {_isSensitiveText = newValue}
  }
  var hasIsSensitiveText: Bool {return self._isSensitiveText != nil}
  mutating func clearIsSensitiveText() {self._isSensitiveText = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum TypeEnum: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown
    case text

    case url

    case address

    case phoneNumber

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .text
      case 2: self = .url
      case 3: self = .address
      case 4: self = .phoneNumber
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .text: return 1
      case .url: return 2
      case .address: return 3
      case .phoneNumber: return 4
      }
    }

  }

  init() {}

  fileprivate var _textTitle: String? = nil
  fileprivate var _type: Sharing_Nearby_TextMetadata.TypeEnum? = nil
  fileprivate var _payloadID: Int64? = nil
  fileprivate var _size: Int64? = nil
  fileprivate var _id: Int64? = nil
  fileprivate var _isSensitiveText: Bool? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_TextMetadata.TypeEnum: CaseIterable {
}

#endif

struct Sharing_Nearby_WifiCredentialsMetadata {

  var ssid: String {
    get {return _ssid ?? String()}
    set {_ssid = newValue}
  }
  var hasSsid: Bool {return self._ssid != nil}
  mutating func clearSsid() {self._ssid = nil}

  var securityType: Sharing_Nearby_WifiCredentialsMetadata.SecurityType {
    get {return _securityType ?? .unknownSecurityType}
    set {_securityType = newValue}
  }
  var hasSecurityType: Bool {return self._securityType != nil}
  mutating func clearSecurityType() {self._securityType = nil}

  var payloadID: Int64 {
    get {return _payloadID ?? 0}
    set {_payloadID = newValue}
  }
  var hasPayloadID: Bool {return self._payloadID != nil}
  mutating func clearPayloadID() {self._payloadID = nil}

  var id: Int64 {
    get {return _id ?? 0}
    set {_id = newValue}
  }
  var hasID: Bool {return self._id != nil}
  mutating func clearID() {self._id = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum SecurityType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownSecurityType
    case `open`
    case wpaPsk
    case wep
    case sae

    init() {
      self = .unknownSecurityType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownSecurityType
      case 1: self = .open
      case 2: self = .wpaPsk
      case 3: self = .wep
      case 4: self = .sae
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownSecurityType: return 0
      case .open: return 1
      case .wpaPsk: return 2
      case .wep: return 3
      case .sae: return 4
      }
    }

  }

  init() {}

  fileprivate var _ssid: String? = nil
  fileprivate var _securityType: Sharing_Nearby_WifiCredentialsMetadata.SecurityType? = nil
  fileprivate var _payloadID: Int64? = nil
  fileprivate var _id: Int64? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_WifiCredentialsMetadata.SecurityType: CaseIterable {
}

#endif

struct Sharing_Nearby_AppMetadata {

  var appName: String {
    get {return _appName ?? String()}
    set {_appName = newValue}
  }
  var hasAppName: Bool {return self._appName != nil}
  mutating func clearAppName() {self._appName = nil}

  var size: Int64 {
    get {return _size ?? 0}
    set {_size = newValue}
  }
  var hasSize: Bool {return self._size != nil}
  mutating func clearSize() {self._size = nil}

  var payloadID: [Int64] = []

  var id: Int64 {
    get {return _id ?? 0}
    set {_id = newValue}
  }
  var hasID: Bool {return self._id != nil}
  mutating func clearID() {self._id = nil}

  var fileName: [String] = []

  var fileSize: [Int64] = []

  var packageName: String {
    get {return _packageName ?? String()}
    set {_packageName = newValue}
  }
  var hasPackageName: Bool {return self._packageName != nil}
  mutating func clearPackageName() {self._packageName = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _appName: String? = nil
  fileprivate var _size: Int64? = nil
  fileprivate var _id: Int64? = nil
  fileprivate var _packageName: String? = nil
}

struct Sharing_Nearby_StreamMetadata {

  var description_p: String {
    get {return _description_p ?? String()}
    set {_description_p = newValue}
  }
  var hasDescription_p: Bool {return self._description_p != nil}
  mutating func clearDescription_p() {self._description_p = nil}

  var packageName: String {
    get {return _packageName ?? String()}
    set {_packageName = newValue}
  }
  var hasPackageName: Bool {return self._packageName != nil}
  mutating func clearPackageName() {self._packageName = nil}

  var payloadID: Int64 {
    get {return _payloadID ?? 0}
    set {_payloadID = newValue}
  }
  var hasPayloadID: Bool {return self._payloadID != nil}
  mutating func clearPayloadID() {self._payloadID = nil}

  var attributedAppName: String {
    get {return _attributedAppName ?? String()}
    set {_attributedAppName = newValue}
  }
  var hasAttributedAppName: Bool {return self._attributedAppName != nil}
  mutating func clearAttributedAppName() {self._attributedAppName = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _description_p: String? = nil
  fileprivate var _packageName: String? = nil
  fileprivate var _payloadID: Int64? = nil
  fileprivate var _attributedAppName: String? = nil
}

struct Sharing_Nearby_Frame {

  var version: Sharing_Nearby_Frame.Version {
    get {return _version ?? .unknownVersion}
    set {_version = newValue}
  }
  var hasVersion: Bool {return self._version != nil}
  mutating func clearVersion() {self._version = nil}

  var v1: Sharing_Nearby_V1Frame {
    get {return _v1 ?? Sharing_Nearby_V1Frame()}
    set {_v1 = newValue}
  }
  var hasV1: Bool {return self._v1 != nil}
  mutating func clearV1() {self._v1 = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum Version: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownVersion
    case v1

    init() {
      self = .unknownVersion
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownVersion
      case 1: self = .v1
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownVersion: return 0
      case .v1: return 1
      }
    }

  }

  init() {}

  fileprivate var _version: Sharing_Nearby_Frame.Version? = nil
  fileprivate var _v1: Sharing_Nearby_V1Frame? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_Frame.Version: CaseIterable {
}

#endif

struct Sharing_Nearby_V1Frame {

  var type: Sharing_Nearby_V1Frame.FrameType {
    get {return _storage._type ?? .unknownFrameType}
    set {_uniqueStorage()._type = newValue}
  }
  var hasType: Bool {return _storage._type != nil}
  mutating func clearType() {_uniqueStorage()._type = nil}

  var introduction: Sharing_Nearby_IntroductionFrame {
    get {return _storage._introduction ?? Sharing_Nearby_IntroductionFrame()}
    set {_uniqueStorage()._introduction = newValue}
  }
  var hasIntroduction: Bool {return _storage._introduction != nil}
  mutating func clearIntroduction() {_uniqueStorage()._introduction = nil}

  var connectionResponse: Sharing_Nearby_ConnectionResponseFrame {
    get {return _storage._connectionResponse ?? Sharing_Nearby_ConnectionResponseFrame()}
    set {_uniqueStorage()._connectionResponse = newValue}
  }
  var hasConnectionResponse: Bool {return _storage._connectionResponse != nil}
  mutating func clearConnectionResponse() {_uniqueStorage()._connectionResponse = nil}

  var pairedKeyEncryption: Sharing_Nearby_PairedKeyEncryptionFrame {
    get {return _storage._pairedKeyEncryption ?? Sharing_Nearby_PairedKeyEncryptionFrame()}
    set {_uniqueStorage()._pairedKeyEncryption = newValue}
  }
  var hasPairedKeyEncryption: Bool {return _storage._pairedKeyEncryption != nil}
  mutating func clearPairedKeyEncryption() {_uniqueStorage()._pairedKeyEncryption = nil}

  var pairedKeyResult: Sharing_Nearby_PairedKeyResultFrame {
    get {return _storage._pairedKeyResult ?? Sharing_Nearby_PairedKeyResultFrame()}
    set {_uniqueStorage()._pairedKeyResult = newValue}
  }
  var hasPairedKeyResult: Bool {return _storage._pairedKeyResult != nil}
  mutating func clearPairedKeyResult() {_uniqueStorage()._pairedKeyResult = nil}

  var certificateInfo: Sharing_Nearby_CertificateInfoFrame {
    get {return _storage._certificateInfo ?? Sharing_Nearby_CertificateInfoFrame()}
    set {_uniqueStorage()._certificateInfo = newValue}
  }
  var hasCertificateInfo: Bool {return _storage._certificateInfo != nil}
  mutating func clearCertificateInfo() {_uniqueStorage()._certificateInfo = nil}

  var progressUpdate: Sharing_Nearby_ProgressUpdateFrame {
    get {return _storage._progressUpdate ?? Sharing_Nearby_ProgressUpdateFrame()}
    set {_uniqueStorage()._progressUpdate = newValue}
  }
  var hasProgressUpdate: Bool {return _storage._progressUpdate != nil}
  mutating func clearProgressUpdate() {_uniqueStorage()._progressUpdate = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum FrameType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownFrameType
    case introduction
    case response
    case pairedKeyEncryption
    case pairedKeyResult

    case certificateInfo
    case cancel

    case progressUpdate

    init() {
      self = .unknownFrameType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownFrameType
      case 1: self = .introduction
      case 2: self = .response
      case 3: self = .pairedKeyEncryption
      case 4: self = .pairedKeyResult
      case 5: self = .certificateInfo
      case 6: self = .cancel
      case 7: self = .progressUpdate
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownFrameType: return 0
      case .introduction: return 1
      case .response: return 2
      case .pairedKeyEncryption: return 3
      case .pairedKeyResult: return 4
      case .certificateInfo: return 5
      case .cancel: return 6
      case .progressUpdate: return 7
      }
    }

  }

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

#if swift(>=4.2)

extension Sharing_Nearby_V1Frame.FrameType: CaseIterable {
}

#endif

struct Sharing_Nearby_IntroductionFrame {

  var fileMetadata: [Sharing_Nearby_FileMetadata] = []

  var textMetadata: [Sharing_Nearby_TextMetadata] = []

  var requiredPackage: String {
    get {return _requiredPackage ?? String()}
    set {_requiredPackage = newValue}
  }
  var hasRequiredPackage: Bool {return self._requiredPackage != nil}
  mutating func clearRequiredPackage() {self._requiredPackage = nil}

  var wifiCredentialsMetadata: [Sharing_Nearby_WifiCredentialsMetadata] = []

  var appMetadata: [Sharing_Nearby_AppMetadata] = []

  var startTransfer: Bool {
    get {return _startTransfer ?? false}
    set {_startTransfer = newValue}
  }
  var hasStartTransfer: Bool {return self._startTransfer != nil}
  mutating func clearStartTransfer() {self._startTransfer = nil}

  var streamMetadata: [Sharing_Nearby_StreamMetadata] = []

  var useCase: Sharing_Nearby_IntroductionFrame.SharingUseCase {
    get {return _useCase ?? .unknown}
    set {_useCase = newValue}
  }
  var hasUseCase: Bool {return self._useCase != nil}
  mutating func clearUseCase() {self._useCase = nil}

  var previewPayloadIds: [Int64] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum SharingUseCase: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown
    case nearbyShare
    case remoteCopy

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .nearbyShare
      case 2: self = .remoteCopy
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .nearbyShare: return 1
      case .remoteCopy: return 2
      }
    }

  }

  init() {}

  fileprivate var _requiredPackage: String? = nil
  fileprivate var _startTransfer: Bool? = nil
  fileprivate var _useCase: Sharing_Nearby_IntroductionFrame.SharingUseCase? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_IntroductionFrame.SharingUseCase: CaseIterable {
}

#endif

struct Sharing_Nearby_ProgressUpdateFrame {

  var progress: Float {
    get {return _progress ?? 0}
    set {_progress = newValue}
  }
  var hasProgress: Bool {return self._progress != nil}
  mutating func clearProgress() {self._progress = nil}

  var startTransfer: Bool {
    get {return _startTransfer ?? false}
    set {_startTransfer = newValue}
  }
  var hasStartTransfer: Bool {return self._startTransfer != nil}
  mutating func clearStartTransfer() {self._startTransfer = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _progress: Float? = nil
  fileprivate var _startTransfer: Bool? = nil
}

struct Sharing_Nearby_ConnectionResponseFrame {

  var status: Sharing_Nearby_ConnectionResponseFrame.Status {
    get {return _status ?? .unknown}
    set {_status = newValue}
  }
  var hasStatus: Bool {return self._status != nil}
  mutating func clearStatus() {self._status = nil}

  var attachmentDetails: Dictionary<Int64,Sharing_Nearby_AttachmentDetails> = [:]

  var streamMetadata: [Sharing_Nearby_StreamMetadata] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum Status: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown
    case accept
    case reject
    case notEnoughSpace
    case unsupportedAttachmentType
    case timedOut

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .accept
      case 2: self = .reject
      case 3: self = .notEnoughSpace
      case 4: self = .unsupportedAttachmentType
      case 5: self = .timedOut
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .accept: return 1
      case .reject: return 2
      case .notEnoughSpace: return 3
      case .unsupportedAttachmentType: return 4
      case .timedOut: return 5
      }
    }

  }

  init() {}

  fileprivate var _status: Sharing_Nearby_ConnectionResponseFrame.Status? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_ConnectionResponseFrame.Status: CaseIterable {
}

#endif

struct Sharing_Nearby_AttachmentDetails {

  var type: Sharing_Nearby_AttachmentDetails.TypeEnum {
    get {return _type ?? .unknown}
    set {_type = newValue}
  }
  var hasType: Bool {return self._type != nil}
  mutating func clearType() {self._type = nil}

  var fileAttachmentDetails: Sharing_Nearby_FileAttachmentDetails {
    get {return _fileAttachmentDetails ?? Sharing_Nearby_FileAttachmentDetails()}
    set {_fileAttachmentDetails = newValue}
  }
  var hasFileAttachmentDetails: Bool {return self._fileAttachmentDetails != nil}
  mutating func clearFileAttachmentDetails() {self._fileAttachmentDetails = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum TypeEnum: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown

    case file

    case text

    case wifiCredentials

    case app

    case stream

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .file
      case 2: self = .text
      case 3: self = .wifiCredentials
      case 4: self = .app
      case 5: self = .stream
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .file: return 1
      case .text: return 2
      case .wifiCredentials: return 3
      case .app: return 4
      case .stream: return 5
      }
    }

  }

  init() {}

  fileprivate var _type: Sharing_Nearby_AttachmentDetails.TypeEnum? = nil
  fileprivate var _fileAttachmentDetails: Sharing_Nearby_FileAttachmentDetails? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_AttachmentDetails.TypeEnum: CaseIterable {
}

#endif

struct Sharing_Nearby_FileAttachmentDetails {

  var receiverExistingFileSize: Int64 {
    get {return _receiverExistingFileSize ?? 0}
    set {_receiverExistingFileSize = newValue}
  }
  var hasReceiverExistingFileSize: Bool {return self._receiverExistingFileSize != nil}
  mutating func clearReceiverExistingFileSize() {self._receiverExistingFileSize = nil}

  var attachmentHashPayloads: Dictionary<Int64,Sharing_Nearby_PayloadsDetails> = [:]

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _receiverExistingFileSize: Int64? = nil
}

struct Sharing_Nearby_PayloadsDetails {

  var payloadDetails: [Sharing_Nearby_PayloadDetails] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sharing_Nearby_PayloadDetails {

  var id: Int64 {
    get {return _id ?? 0}
    set {_id = newValue}
  }
  var hasID: Bool {return self._id != nil}
  mutating func clearID() {self._id = nil}

  var creationTimestampMillis: Int64 {
    get {return _creationTimestampMillis ?? 0}
    set {_creationTimestampMillis = newValue}
  }
  var hasCreationTimestampMillis: Bool {return self._creationTimestampMillis != nil}
  mutating func clearCreationTimestampMillis() {self._creationTimestampMillis = nil}

  var size: Int64 {
    get {return _size ?? 0}
    set {_size = newValue}
  }
  var hasSize: Bool {return self._size != nil}
  mutating func clearSize() {self._size = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _id: Int64? = nil
  fileprivate var _creationTimestampMillis: Int64? = nil
  fileprivate var _size: Int64? = nil
}

struct Sharing_Nearby_PairedKeyEncryptionFrame {

  var signedData: Data {
    get {return _signedData ?? Data()}
    set {_signedData = newValue}
  }
  var hasSignedData: Bool {return self._signedData != nil}
  mutating func clearSignedData() {self._signedData = nil}

  var secretIDHash: Data {
    get {return _secretIDHash ?? Data()}
    set {_secretIDHash = newValue}
  }
  var hasSecretIDHash: Bool {return self._secretIDHash != nil}
  mutating func clearSecretIDHash() {self._secretIDHash = nil}

  var optionalSignedData: Data {
    get {return _optionalSignedData ?? Data()}
    set {_optionalSignedData = newValue}
  }
  var hasOptionalSignedData: Bool {return self._optionalSignedData != nil}
  mutating func clearOptionalSignedData() {self._optionalSignedData = nil}

  var qrCodeHandshakeData: Data {
    get {return _qrCodeHandshakeData ?? Data()}
    set {_qrCodeHandshakeData = newValue}
  }
  var hasQrCodeHandshakeData: Bool {return self._qrCodeHandshakeData != nil}
  mutating func clearQrCodeHandshakeData() {self._qrCodeHandshakeData = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _signedData: Data? = nil
  fileprivate var _secretIDHash: Data? = nil
  fileprivate var _optionalSignedData: Data? = nil
  fileprivate var _qrCodeHandshakeData: Data? = nil
}

struct Sharing_Nearby_PairedKeyResultFrame {

  var status: Sharing_Nearby_PairedKeyResultFrame.Status {
    get {return _status ?? .unknown}
    set {_status = newValue}
  }
  var hasStatus: Bool {return self._status != nil}
  mutating func clearStatus() {self._status = nil}

  var osType: Location_Nearby_Proto_Sharing_OSType {
    get {return _osType ?? .unknownOsType}
    set {_osType = newValue}
  }
  var hasOsType: Bool {return self._osType != nil}
  mutating func clearOsType() {self._osType = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum Status: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown
    case success
    case fail
    case unable

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .success
      case 2: self = .fail
      case 3: self = .unable
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .success: return 1
      case .fail: return 2
      case .unable: return 3
      }
    }

  }

  init() {}

  fileprivate var _status: Sharing_Nearby_PairedKeyResultFrame.Status? = nil
  fileprivate var _osType: Location_Nearby_Proto_Sharing_OSType? = nil
}

#if swift(>=4.2)

extension Sharing_Nearby_PairedKeyResultFrame.Status: CaseIterable {
}

#endif

struct Sharing_Nearby_CertificateInfoFrame {

  var publicCertificate: [Sharing_Nearby_PublicCertificate] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Sharing_Nearby_PublicCertificate {

  var secretID: Data {
    get {return _secretID ?? Data()}
    set {_secretID = newValue}
  }
  var hasSecretID: Bool {return self._secretID != nil}
  mutating func clearSecretID() {self._secretID = nil}

  var authenticityKey: Data {
    get {return _authenticityKey ?? Data()}
    set {_authenticityKey = newValue}
  }
  var hasAuthenticityKey: Bool {return self._authenticityKey != nil}
  mutating func clearAuthenticityKey() {self._authenticityKey = nil}

  var publicKey: Data {
    get {return _publicKey ?? Data()}
    set {_publicKey = newValue}
  }
  var hasPublicKey: Bool {return self._publicKey != nil}
  mutating func clearPublicKey() {self._publicKey = nil}

  var startTime: Int64 {
    get {return _startTime ?? 0}
    set {_startTime = newValue}
  }
  var hasStartTime: Bool {return self._startTime != nil}
  mutating func clearStartTime() {self._startTime = nil}

  var endTime: Int64 {
    get {return _endTime ?? 0}
    set {_endTime = newValue}
  }
  var hasEndTime: Bool {return self._endTime != nil}
  mutating func clearEndTime() {self._endTime = nil}

  var encryptedMetadataBytes: Data {
    get {return _encryptedMetadataBytes ?? Data()}
    set {_encryptedMetadataBytes = newValue}
  }
  var hasEncryptedMetadataBytes: Bool {return self._encryptedMetadataBytes != nil}
  mutating func clearEncryptedMetadataBytes() {self._encryptedMetadataBytes = nil}

  var metadataEncryptionKeyTag: Data {
    get {return _metadataEncryptionKeyTag ?? Data()}
    set {_metadataEncryptionKeyTag = newValue}
  }
  var hasMetadataEncryptionKeyTag: Bool {return self._metadataEncryptionKeyTag != nil}
  mutating func clearMetadataEncryptionKeyTag() {self._metadataEncryptionKeyTag = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _secretID: Data? = nil
  fileprivate var _authenticityKey: Data? = nil
  fileprivate var _publicKey: Data? = nil
  fileprivate var _startTime: Int64? = nil
  fileprivate var _endTime: Int64? = nil
  fileprivate var _encryptedMetadataBytes: Data? = nil
  fileprivate var _metadataEncryptionKeyTag: Data? = nil
}

struct Sharing_Nearby_WifiCredentials {

  var password: String {
    get {return _password ?? String()}
    set {_password = newValue}
  }
  var hasPassword: Bool {return self._password != nil}
  mutating func clearPassword() {self._password = nil}

  var hiddenSsid: Bool {
    get {return _hiddenSsid ?? false}
    set {_hiddenSsid = newValue}
  }
  var hasHiddenSsid: Bool {return self._hiddenSsid != nil}
  mutating func clearHiddenSsid() {self._hiddenSsid = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _password: String? = nil
  fileprivate var _hiddenSsid: Bool? = nil
}

struct Sharing_Nearby_StreamDetails {

  var inputStreamParcelFileDescriptorBytes: Data {
    get {return _inputStreamParcelFileDescriptorBytes ?? Data()}
    set {_inputStreamParcelFileDescriptorBytes = newValue}
  }
  var hasInputStreamParcelFileDescriptorBytes: Bool {return self._inputStreamParcelFileDescriptorBytes != nil}
  mutating func clearInputStreamParcelFileDescriptorBytes() {self._inputStreamParcelFileDescriptorBytes = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _inputStreamParcelFileDescriptorBytes: Data? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Sharing_Nearby_FileMetadata: @unchecked Sendable {}
extension Sharing_Nearby_FileMetadata.TypeEnum: @unchecked Sendable {}
extension Sharing_Nearby_TextMetadata: @unchecked Sendable {}
extension Sharing_Nearby_TextMetadata.TypeEnum: @unchecked Sendable {}
extension Sharing_Nearby_WifiCredentialsMetadata: @unchecked Sendable {}
extension Sharing_Nearby_WifiCredentialsMetadata.SecurityType: @unchecked Sendable {}
extension Sharing_Nearby_AppMetadata: @unchecked Sendable {}
extension Sharing_Nearby_StreamMetadata: @unchecked Sendable {}
extension Sharing_Nearby_Frame: @unchecked Sendable {}
extension Sharing_Nearby_Frame.Version: @unchecked Sendable {}
extension Sharing_Nearby_V1Frame: @unchecked Sendable {}
extension Sharing_Nearby_V1Frame.FrameType: @unchecked Sendable {}
extension Sharing_Nearby_IntroductionFrame: @unchecked Sendable {}
extension Sharing_Nearby_IntroductionFrame.SharingUseCase: @unchecked Sendable {}
extension Sharing_Nearby_ProgressUpdateFrame: @unchecked Sendable {}
extension Sharing_Nearby_ConnectionResponseFrame: @unchecked Sendable {}
extension Sharing_Nearby_ConnectionResponseFrame.Status: @unchecked Sendable {}
extension Sharing_Nearby_AttachmentDetails: @unchecked Sendable {}
extension Sharing_Nearby_AttachmentDetails.TypeEnum: @unchecked Sendable {}
extension Sharing_Nearby_FileAttachmentDetails: @unchecked Sendable {}
extension Sharing_Nearby_PayloadsDetails: @unchecked Sendable {}
extension Sharing_Nearby_PayloadDetails: @unchecked Sendable {}
extension Sharing_Nearby_PairedKeyEncryptionFrame: @unchecked Sendable {}
extension Sharing_Nearby_PairedKeyResultFrame: @unchecked Sendable {}
extension Sharing_Nearby_PairedKeyResultFrame.Status: @unchecked Sendable {}
extension Sharing_Nearby_CertificateInfoFrame: @unchecked Sendable {}
extension Sharing_Nearby_PublicCertificate: @unchecked Sendable {}
extension Sharing_Nearby_WifiCredentials: @unchecked Sendable {}
extension Sharing_Nearby_StreamDetails: @unchecked Sendable {}
#endif

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "sharing.nearby"

extension Sharing_Nearby_FileMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".FileMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "name"),
    2: .same(proto: "type"),
    3: .standard(proto: "payload_id"),
    4: .same(proto: "size"),
    5: .standard(proto: "mime_type"),
    6: .same(proto: "id"),
    7: .standard(proto: "parent_folder"),
    8: .standard(proto: "attachment_hash"),
    9: .standard(proto: "is_sensitive_content"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._name) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._type) }()
      case 3: try { try decoder.decodeSingularInt64Field(value: &self._payloadID) }()
      case 4: try { try decoder.decodeSingularInt64Field(value: &self._size) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self._mimeType) }()
      case 6: try { try decoder.decodeSingularInt64Field(value: &self._id) }()
      case 7: try { try decoder.decodeSingularStringField(value: &self._parentFolder) }()
      case 8: try { try decoder.decodeSingularInt64Field(value: &self._attachmentHash) }()
      case 9: try { try decoder.decodeSingularBoolField(value: &self._isSensitiveContent) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._name {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._type {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._payloadID {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._size {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._mimeType {
      try visitor.visitSingularStringField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._id {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._parentFolder {
      try visitor.visitSingularStringField(value: v, fieldNumber: 7)
    } }()
    try { if let v = self._attachmentHash {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 8)
    } }()
    try { if let v = self._isSensitiveContent {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 9)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_FileMetadata, rhs: Sharing_Nearby_FileMetadata) -> Bool {
    if lhs._name != rhs._name {return false}
    if lhs._type != rhs._type {return false}
    if lhs._payloadID != rhs._payloadID {return false}
    if lhs._size != rhs._size {return false}
    if lhs._mimeType != rhs._mimeType {return false}
    if lhs._id != rhs._id {return false}
    if lhs._parentFolder != rhs._parentFolder {return false}
    if lhs._attachmentHash != rhs._attachmentHash {return false}
    if lhs._isSensitiveContent != rhs._isSensitiveContent {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_FileMetadata.TypeEnum: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "IMAGE"),
    2: .same(proto: "VIDEO"),
    3: .same(proto: "ANDROID_APP"),
    4: .same(proto: "AUDIO"),
    5: .same(proto: "DOCUMENT"),
    6: .same(proto: "CONTACT_CARD"),
  ]
}

extension Sharing_Nearby_TextMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".TextMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    2: .standard(proto: "text_title"),
    3: .same(proto: "type"),
    4: .standard(proto: "payload_id"),
    5: .same(proto: "size"),
    6: .same(proto: "id"),
    7: .standard(proto: "is_sensitive_text"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 2: try { try decoder.decodeSingularStringField(value: &self._textTitle) }()
      case 3: try { try decoder.decodeSingularEnumField(value: &self._type) }()
      case 4: try { try decoder.decodeSingularInt64Field(value: &self._payloadID) }()
      case 5: try { try decoder.decodeSingularInt64Field(value: &self._size) }()
      case 6: try { try decoder.decodeSingularInt64Field(value: &self._id) }()
      case 7: try { try decoder.decodeSingularBoolField(value: &self._isSensitiveText) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._textTitle {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._type {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._payloadID {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._size {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._id {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._isSensitiveText {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 7)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_TextMetadata, rhs: Sharing_Nearby_TextMetadata) -> Bool {
    if lhs._textTitle != rhs._textTitle {return false}
    if lhs._type != rhs._type {return false}
    if lhs._payloadID != rhs._payloadID {return false}
    if lhs._size != rhs._size {return false}
    if lhs._id != rhs._id {return false}
    if lhs._isSensitiveText != rhs._isSensitiveText {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_TextMetadata.TypeEnum: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "TEXT"),
    2: .same(proto: "URL"),
    3: .same(proto: "ADDRESS"),
    4: .same(proto: "PHONE_NUMBER"),
  ]
}

extension Sharing_Nearby_WifiCredentialsMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".WifiCredentialsMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    2: .same(proto: "ssid"),
    3: .standard(proto: "security_type"),
    4: .standard(proto: "payload_id"),
    5: .same(proto: "id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 2: try { try decoder.decodeSingularStringField(value: &self._ssid) }()
      case 3: try { try decoder.decodeSingularEnumField(value: &self._securityType) }()
      case 4: try { try decoder.decodeSingularInt64Field(value: &self._payloadID) }()
      case 5: try { try decoder.decodeSingularInt64Field(value: &self._id) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._ssid {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._securityType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._payloadID {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._id {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 5)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_WifiCredentialsMetadata, rhs: Sharing_Nearby_WifiCredentialsMetadata) -> Bool {
    if lhs._ssid != rhs._ssid {return false}
    if lhs._securityType != rhs._securityType {return false}
    if lhs._payloadID != rhs._payloadID {return false}
    if lhs._id != rhs._id {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_WifiCredentialsMetadata.SecurityType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_SECURITY_TYPE"),
    1: .same(proto: "OPEN"),
    2: .same(proto: "WPA_PSK"),
    3: .same(proto: "WEP"),
    4: .same(proto: "SAE"),
  ]
}

extension Sharing_Nearby_AppMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AppMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "app_name"),
    2: .same(proto: "size"),
    3: .standard(proto: "payload_id"),
    4: .same(proto: "id"),
    5: .standard(proto: "file_name"),
    6: .standard(proto: "file_size"),
    7: .standard(proto: "package_name"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._appName) }()
      case 2: try { try decoder.decodeSingularInt64Field(value: &self._size) }()
      case 3: try { try decoder.decodeRepeatedInt64Field(value: &self.payloadID) }()
      case 4: try { try decoder.decodeSingularInt64Field(value: &self._id) }()
      case 5: try { try decoder.decodeRepeatedStringField(value: &self.fileName) }()
      case 6: try { try decoder.decodeRepeatedInt64Field(value: &self.fileSize) }()
      case 7: try { try decoder.decodeSingularStringField(value: &self._packageName) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._appName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._size {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 2)
    } }()
    if !self.payloadID.isEmpty {
      try visitor.visitPackedInt64Field(value: self.payloadID, fieldNumber: 3)
    }
    try { if let v = self._id {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 4)
    } }()
    if !self.fileName.isEmpty {
      try visitor.visitRepeatedStringField(value: self.fileName, fieldNumber: 5)
    }
    if !self.fileSize.isEmpty {
      try visitor.visitPackedInt64Field(value: self.fileSize, fieldNumber: 6)
    }
    try { if let v = self._packageName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 7)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_AppMetadata, rhs: Sharing_Nearby_AppMetadata) -> Bool {
    if lhs._appName != rhs._appName {return false}
    if lhs._size != rhs._size {return false}
    if lhs.payloadID != rhs.payloadID {return false}
    if lhs._id != rhs._id {return false}
    if lhs.fileName != rhs.fileName {return false}
    if lhs.fileSize != rhs.fileSize {return false}
    if lhs._packageName != rhs._packageName {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_StreamMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".StreamMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "description"),
    2: .standard(proto: "package_name"),
    3: .standard(proto: "payload_id"),
    4: .standard(proto: "attributed_app_name"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._description_p) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self._packageName) }()
      case 3: try { try decoder.decodeSingularInt64Field(value: &self._payloadID) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self._attributedAppName) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._description_p {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._packageName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._payloadID {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._attributedAppName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_StreamMetadata, rhs: Sharing_Nearby_StreamMetadata) -> Bool {
    if lhs._description_p != rhs._description_p {return false}
    if lhs._packageName != rhs._packageName {return false}
    if lhs._payloadID != rhs._payloadID {return false}
    if lhs._attributedAppName != rhs._attributedAppName {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_Frame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Frame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "version"),
    2: .same(proto: "v1"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._version) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._v1) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._version {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._v1 {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_Frame, rhs: Sharing_Nearby_Frame) -> Bool {
    if lhs._version != rhs._version {return false}
    if lhs._v1 != rhs._v1 {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_Frame.Version: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_VERSION"),
    1: .same(proto: "V1"),
  ]
}

extension Sharing_Nearby_V1Frame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".V1Frame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "type"),
    2: .same(proto: "introduction"),
    3: .standard(proto: "connection_response"),
    4: .standard(proto: "paired_key_encryption"),
    5: .standard(proto: "paired_key_result"),
    6: .standard(proto: "certificate_info"),
    7: .standard(proto: "progress_update"),
  ]

  fileprivate class _StorageClass {
    var _type: Sharing_Nearby_V1Frame.FrameType? = nil
    var _introduction: Sharing_Nearby_IntroductionFrame? = nil
    var _connectionResponse: Sharing_Nearby_ConnectionResponseFrame? = nil
    var _pairedKeyEncryption: Sharing_Nearby_PairedKeyEncryptionFrame? = nil
    var _pairedKeyResult: Sharing_Nearby_PairedKeyResultFrame? = nil
    var _certificateInfo: Sharing_Nearby_CertificateInfoFrame? = nil
    var _progressUpdate: Sharing_Nearby_ProgressUpdateFrame? = nil

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _type = source._type
      _introduction = source._introduction
      _connectionResponse = source._connectionResponse
      _pairedKeyEncryption = source._pairedKeyEncryption
      _pairedKeyResult = source._pairedKeyResult
      _certificateInfo = source._certificateInfo
      _progressUpdate = source._progressUpdate
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
        case 1: try { try decoder.decodeSingularEnumField(value: &_storage._type) }()
        case 2: try { try decoder.decodeSingularMessageField(value: &_storage._introduction) }()
        case 3: try { try decoder.decodeSingularMessageField(value: &_storage._connectionResponse) }()
        case 4: try { try decoder.decodeSingularMessageField(value: &_storage._pairedKeyEncryption) }()
        case 5: try { try decoder.decodeSingularMessageField(value: &_storage._pairedKeyResult) }()
        case 6: try { try decoder.decodeSingularMessageField(value: &_storage._certificateInfo) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._progressUpdate) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      try { if let v = _storage._type {
        try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
      } }()
      try { if let v = _storage._introduction {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
      } }()
      try { if let v = _storage._connectionResponse {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
      } }()
      try { if let v = _storage._pairedKeyEncryption {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
      } }()
      try { if let v = _storage._pairedKeyResult {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
      } }()
      try { if let v = _storage._certificateInfo {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
      } }()
      try { if let v = _storage._progressUpdate {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_V1Frame, rhs: Sharing_Nearby_V1Frame) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._type != rhs_storage._type {return false}
        if _storage._introduction != rhs_storage._introduction {return false}
        if _storage._connectionResponse != rhs_storage._connectionResponse {return false}
        if _storage._pairedKeyEncryption != rhs_storage._pairedKeyEncryption {return false}
        if _storage._pairedKeyResult != rhs_storage._pairedKeyResult {return false}
        if _storage._certificateInfo != rhs_storage._certificateInfo {return false}
        if _storage._progressUpdate != rhs_storage._progressUpdate {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_V1Frame.FrameType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_FRAME_TYPE"),
    1: .same(proto: "INTRODUCTION"),
    2: .same(proto: "RESPONSE"),
    3: .same(proto: "PAIRED_KEY_ENCRYPTION"),
    4: .same(proto: "PAIRED_KEY_RESULT"),
    5: .same(proto: "CERTIFICATE_INFO"),
    6: .same(proto: "CANCEL"),
    7: .same(proto: "PROGRESS_UPDATE"),
  ]
}

extension Sharing_Nearby_IntroductionFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".IntroductionFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "file_metadata"),
    2: .standard(proto: "text_metadata"),
    3: .standard(proto: "required_package"),
    4: .standard(proto: "wifi_credentials_metadata"),
    5: .standard(proto: "app_metadata"),
    6: .standard(proto: "start_transfer"),
    7: .standard(proto: "stream_metadata"),
    8: .standard(proto: "use_case"),
    9: .standard(proto: "preview_payload_ids"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.fileMetadata) }()
      case 2: try { try decoder.decodeRepeatedMessageField(value: &self.textMetadata) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self._requiredPackage) }()
      case 4: try { try decoder.decodeRepeatedMessageField(value: &self.wifiCredentialsMetadata) }()
      case 5: try { try decoder.decodeRepeatedMessageField(value: &self.appMetadata) }()
      case 6: try { try decoder.decodeSingularBoolField(value: &self._startTransfer) }()
      case 7: try { try decoder.decodeRepeatedMessageField(value: &self.streamMetadata) }()
      case 8: try { try decoder.decodeSingularEnumField(value: &self._useCase) }()
      case 9: try { try decoder.decodeRepeatedInt64Field(value: &self.previewPayloadIds) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.fileMetadata.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.fileMetadata, fieldNumber: 1)
    }
    if !self.textMetadata.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.textMetadata, fieldNumber: 2)
    }
    try { if let v = self._requiredPackage {
      try visitor.visitSingularStringField(value: v, fieldNumber: 3)
    } }()
    if !self.wifiCredentialsMetadata.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.wifiCredentialsMetadata, fieldNumber: 4)
    }
    if !self.appMetadata.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.appMetadata, fieldNumber: 5)
    }
    try { if let v = self._startTransfer {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 6)
    } }()
    if !self.streamMetadata.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.streamMetadata, fieldNumber: 7)
    }
    try { if let v = self._useCase {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 8)
    } }()
    if !self.previewPayloadIds.isEmpty {
      try visitor.visitRepeatedInt64Field(value: self.previewPayloadIds, fieldNumber: 9)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_IntroductionFrame, rhs: Sharing_Nearby_IntroductionFrame) -> Bool {
    if lhs.fileMetadata != rhs.fileMetadata {return false}
    if lhs.textMetadata != rhs.textMetadata {return false}
    if lhs._requiredPackage != rhs._requiredPackage {return false}
    if lhs.wifiCredentialsMetadata != rhs.wifiCredentialsMetadata {return false}
    if lhs.appMetadata != rhs.appMetadata {return false}
    if lhs._startTransfer != rhs._startTransfer {return false}
    if lhs.streamMetadata != rhs.streamMetadata {return false}
    if lhs._useCase != rhs._useCase {return false}
    if lhs.previewPayloadIds != rhs.previewPayloadIds {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_IntroductionFrame.SharingUseCase: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "NEARBY_SHARE"),
    2: .same(proto: "REMOTE_COPY"),
  ]
}

extension Sharing_Nearby_ProgressUpdateFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ProgressUpdateFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "progress"),
    2: .standard(proto: "start_transfer"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularFloatField(value: &self._progress) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self._startTransfer) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._progress {
      try visitor.visitSingularFloatField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._startTransfer {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_ProgressUpdateFrame, rhs: Sharing_Nearby_ProgressUpdateFrame) -> Bool {
    if lhs._progress != rhs._progress {return false}
    if lhs._startTransfer != rhs._startTransfer {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_ConnectionResponseFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ConnectionResponseFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "status"),
    2: .standard(proto: "attachment_details"),
    3: .standard(proto: "stream_metadata"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._status) }()
      case 2: try { try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufInt64,Sharing_Nearby_AttachmentDetails>.self, value: &self.attachmentDetails) }()
      case 3: try { try decoder.decodeRepeatedMessageField(value: &self.streamMetadata) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._status {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    if !self.attachmentDetails.isEmpty {
      try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufInt64,Sharing_Nearby_AttachmentDetails>.self, value: self.attachmentDetails, fieldNumber: 2)
    }
    if !self.streamMetadata.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.streamMetadata, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_ConnectionResponseFrame, rhs: Sharing_Nearby_ConnectionResponseFrame) -> Bool {
    if lhs._status != rhs._status {return false}
    if lhs.attachmentDetails != rhs.attachmentDetails {return false}
    if lhs.streamMetadata != rhs.streamMetadata {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_ConnectionResponseFrame.Status: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "ACCEPT"),
    2: .same(proto: "REJECT"),
    3: .same(proto: "NOT_ENOUGH_SPACE"),
    4: .same(proto: "UNSUPPORTED_ATTACHMENT_TYPE"),
    5: .same(proto: "TIMED_OUT"),
  ]
}

extension Sharing_Nearby_AttachmentDetails: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AttachmentDetails"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "type"),
    2: .standard(proto: "file_attachment_details"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._type) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._fileAttachmentDetails) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._type {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._fileAttachmentDetails {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_AttachmentDetails, rhs: Sharing_Nearby_AttachmentDetails) -> Bool {
    if lhs._type != rhs._type {return false}
    if lhs._fileAttachmentDetails != rhs._fileAttachmentDetails {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_AttachmentDetails.TypeEnum: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "FILE"),
    2: .same(proto: "TEXT"),
    3: .same(proto: "WIFI_CREDENTIALS"),
    4: .same(proto: "APP"),
    5: .same(proto: "STREAM"),
  ]
}

extension Sharing_Nearby_FileAttachmentDetails: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".FileAttachmentDetails"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "receiver_existing_file_size"),
    2: .standard(proto: "attachment_hash_payloads"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt64Field(value: &self._receiverExistingFileSize) }()
      case 2: try { try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufInt64,Sharing_Nearby_PayloadsDetails>.self, value: &self.attachmentHashPayloads) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._receiverExistingFileSize {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 1)
    } }()
    if !self.attachmentHashPayloads.isEmpty {
      try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufInt64,Sharing_Nearby_PayloadsDetails>.self, value: self.attachmentHashPayloads, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_FileAttachmentDetails, rhs: Sharing_Nearby_FileAttachmentDetails) -> Bool {
    if lhs._receiverExistingFileSize != rhs._receiverExistingFileSize {return false}
    if lhs.attachmentHashPayloads != rhs.attachmentHashPayloads {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_PayloadsDetails: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PayloadsDetails"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "payload_details"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.payloadDetails) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.payloadDetails.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.payloadDetails, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_PayloadsDetails, rhs: Sharing_Nearby_PayloadsDetails) -> Bool {
    if lhs.payloadDetails != rhs.payloadDetails {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_PayloadDetails: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PayloadDetails"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "id"),
    2: .standard(proto: "creation_timestamp_millis"),
    3: .same(proto: "size"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt64Field(value: &self._id) }()
      case 2: try { try decoder.decodeSingularInt64Field(value: &self._creationTimestampMillis) }()
      case 3: try { try decoder.decodeSingularInt64Field(value: &self._size) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._id {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._creationTimestampMillis {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._size {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_PayloadDetails, rhs: Sharing_Nearby_PayloadDetails) -> Bool {
    if lhs._id != rhs._id {return false}
    if lhs._creationTimestampMillis != rhs._creationTimestampMillis {return false}
    if lhs._size != rhs._size {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_PairedKeyEncryptionFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PairedKeyEncryptionFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "signed_data"),
    2: .standard(proto: "secret_id_hash"),
    3: .standard(proto: "optional_signed_data"),
    4: .standard(proto: "qr_code_handshake_data"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._signedData) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._secretIDHash) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._optionalSignedData) }()
      case 4: try { try decoder.decodeSingularBytesField(value: &self._qrCodeHandshakeData) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._signedData {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._secretIDHash {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._optionalSignedData {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._qrCodeHandshakeData {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_PairedKeyEncryptionFrame, rhs: Sharing_Nearby_PairedKeyEncryptionFrame) -> Bool {
    if lhs._signedData != rhs._signedData {return false}
    if lhs._secretIDHash != rhs._secretIDHash {return false}
    if lhs._optionalSignedData != rhs._optionalSignedData {return false}
    if lhs._qrCodeHandshakeData != rhs._qrCodeHandshakeData {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_PairedKeyResultFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PairedKeyResultFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "status"),
    2: .standard(proto: "os_type"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._status) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._osType) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._status {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._osType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_PairedKeyResultFrame, rhs: Sharing_Nearby_PairedKeyResultFrame) -> Bool {
    if lhs._status != rhs._status {return false}
    if lhs._osType != rhs._osType {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_PairedKeyResultFrame.Status: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "SUCCESS"),
    2: .same(proto: "FAIL"),
    3: .same(proto: "UNABLE"),
  ]
}

extension Sharing_Nearby_CertificateInfoFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".CertificateInfoFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "public_certificate"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedMessageField(value: &self.publicCertificate) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.publicCertificate.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.publicCertificate, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_CertificateInfoFrame, rhs: Sharing_Nearby_CertificateInfoFrame) -> Bool {
    if lhs.publicCertificate != rhs.publicCertificate {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_PublicCertificate: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PublicCertificate"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "secret_id"),
    2: .standard(proto: "authenticity_key"),
    3: .standard(proto: "public_key"),
    4: .standard(proto: "start_time"),
    5: .standard(proto: "end_time"),
    6: .standard(proto: "encrypted_metadata_bytes"),
    7: .standard(proto: "metadata_encryption_key_tag"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._secretID) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._authenticityKey) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._publicKey) }()
      case 4: try { try decoder.decodeSingularInt64Field(value: &self._startTime) }()
      case 5: try { try decoder.decodeSingularInt64Field(value: &self._endTime) }()
      case 6: try { try decoder.decodeSingularBytesField(value: &self._encryptedMetadataBytes) }()
      case 7: try { try decoder.decodeSingularBytesField(value: &self._metadataEncryptionKeyTag) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._secretID {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._authenticityKey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._publicKey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._startTime {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._endTime {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._encryptedMetadataBytes {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._metadataEncryptionKeyTag {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 7)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_PublicCertificate, rhs: Sharing_Nearby_PublicCertificate) -> Bool {
    if lhs._secretID != rhs._secretID {return false}
    if lhs._authenticityKey != rhs._authenticityKey {return false}
    if lhs._publicKey != rhs._publicKey {return false}
    if lhs._startTime != rhs._startTime {return false}
    if lhs._endTime != rhs._endTime {return false}
    if lhs._encryptedMetadataBytes != rhs._encryptedMetadataBytes {return false}
    if lhs._metadataEncryptionKeyTag != rhs._metadataEncryptionKeyTag {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_WifiCredentials: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".WifiCredentials"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "password"),
    2: .standard(proto: "hidden_ssid"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._password) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self._hiddenSsid) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._password {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._hiddenSsid {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_WifiCredentials, rhs: Sharing_Nearby_WifiCredentials) -> Bool {
    if lhs._password != rhs._password {return false}
    if lhs._hiddenSsid != rhs._hiddenSsid {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Sharing_Nearby_StreamDetails: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".StreamDetails"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "input_stream_parcel_file_descriptor_bytes"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._inputStreamParcelFileDescriptorBytes) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._inputStreamParcelFileDescriptorBytes {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Sharing_Nearby_StreamDetails, rhs: Sharing_Nearby_StreamDetails) -> Bool {
    if lhs._inputStreamParcelFileDescriptorBytes != rhs._inputStreamParcelFileDescriptorBytes {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}