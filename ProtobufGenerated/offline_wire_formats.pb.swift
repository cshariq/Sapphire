//
//  offline_wire_formats.pb.swift
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

enum Location_Nearby_Connections_EndpointType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownEndpoint
  case connectionsEndpoint
  case presenceEndpoint

  init() {
    self = .unknownEndpoint
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownEndpoint
    case 1: self = .connectionsEndpoint
    case 2: self = .presenceEndpoint
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownEndpoint: return 0
    case .connectionsEndpoint: return 1
    case .presenceEndpoint: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Connections_EndpointType: CaseIterable {
}

#endif

struct Location_Nearby_Connections_OfflineFrame {

  var version: Location_Nearby_Connections_OfflineFrame.Version {
    get {return _version ?? .unknownVersion}
    set {_version = newValue}
  }
  var hasVersion: Bool {return self._version != nil}
  mutating func clearVersion() {self._version = nil}

  var v1: Location_Nearby_Connections_V1Frame {
    get {return _v1 ?? Location_Nearby_Connections_V1Frame()}
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

  fileprivate var _version: Location_Nearby_Connections_OfflineFrame.Version? = nil
  fileprivate var _v1: Location_Nearby_Connections_V1Frame? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_OfflineFrame.Version: CaseIterable {
}

#endif

struct Location_Nearby_Connections_V1Frame {

  var type: Location_Nearby_Connections_V1Frame.FrameType {
    get {return _storage._type ?? .unknownFrameType}
    set {_uniqueStorage()._type = newValue}
  }
  var hasType: Bool {return _storage._type != nil}
  mutating func clearType() {_uniqueStorage()._type = nil}

  var connectionRequest: Location_Nearby_Connections_ConnectionRequestFrame {
    get {return _storage._connectionRequest ?? Location_Nearby_Connections_ConnectionRequestFrame()}
    set {_uniqueStorage()._connectionRequest = newValue}
  }
  var hasConnectionRequest: Bool {return _storage._connectionRequest != nil}
  mutating func clearConnectionRequest() {_uniqueStorage()._connectionRequest = nil}

  var connectionResponse: Location_Nearby_Connections_ConnectionResponseFrame {
    get {return _storage._connectionResponse ?? Location_Nearby_Connections_ConnectionResponseFrame()}
    set {_uniqueStorage()._connectionResponse = newValue}
  }
  var hasConnectionResponse: Bool {return _storage._connectionResponse != nil}
  mutating func clearConnectionResponse() {_uniqueStorage()._connectionResponse = nil}

  var payloadTransfer: Location_Nearby_Connections_PayloadTransferFrame {
    get {return _storage._payloadTransfer ?? Location_Nearby_Connections_PayloadTransferFrame()}
    set {_uniqueStorage()._payloadTransfer = newValue}
  }
  var hasPayloadTransfer: Bool {return _storage._payloadTransfer != nil}
  mutating func clearPayloadTransfer() {_uniqueStorage()._payloadTransfer = nil}

  var bandwidthUpgradeNegotiation: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame {
    get {return _storage._bandwidthUpgradeNegotiation ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame()}
    set {_uniqueStorage()._bandwidthUpgradeNegotiation = newValue}
  }
  var hasBandwidthUpgradeNegotiation: Bool {return _storage._bandwidthUpgradeNegotiation != nil}
  mutating func clearBandwidthUpgradeNegotiation() {_uniqueStorage()._bandwidthUpgradeNegotiation = nil}

  var keepAlive: Location_Nearby_Connections_KeepAliveFrame {
    get {return _storage._keepAlive ?? Location_Nearby_Connections_KeepAliveFrame()}
    set {_uniqueStorage()._keepAlive = newValue}
  }
  var hasKeepAlive: Bool {return _storage._keepAlive != nil}
  mutating func clearKeepAlive() {_uniqueStorage()._keepAlive = nil}

  var disconnection: Location_Nearby_Connections_DisconnectionFrame {
    get {return _storage._disconnection ?? Location_Nearby_Connections_DisconnectionFrame()}
    set {_uniqueStorage()._disconnection = newValue}
  }
  var hasDisconnection: Bool {return _storage._disconnection != nil}
  mutating func clearDisconnection() {_uniqueStorage()._disconnection = nil}

  var pairedKeyEncryption: Location_Nearby_Connections_PairedKeyEncryptionFrame {
    get {return _storage._pairedKeyEncryption ?? Location_Nearby_Connections_PairedKeyEncryptionFrame()}
    set {_uniqueStorage()._pairedKeyEncryption = newValue}
  }
  var hasPairedKeyEncryption: Bool {return _storage._pairedKeyEncryption != nil}
  mutating func clearPairedKeyEncryption() {_uniqueStorage()._pairedKeyEncryption = nil}

  var authenticationMessage: Location_Nearby_Connections_AuthenticationMessageFrame {
    get {return _storage._authenticationMessage ?? Location_Nearby_Connections_AuthenticationMessageFrame()}
    set {_uniqueStorage()._authenticationMessage = newValue}
  }
  var hasAuthenticationMessage: Bool {return _storage._authenticationMessage != nil}
  mutating func clearAuthenticationMessage() {_uniqueStorage()._authenticationMessage = nil}

  var authenticationResult: Location_Nearby_Connections_AuthenticationResultFrame {
    get {return _storage._authenticationResult ?? Location_Nearby_Connections_AuthenticationResultFrame()}
    set {_uniqueStorage()._authenticationResult = newValue}
  }
  var hasAuthenticationResult: Bool {return _storage._authenticationResult != nil}
  mutating func clearAuthenticationResult() {_uniqueStorage()._authenticationResult = nil}

  var autoResume: Location_Nearby_Connections_AutoResumeFrame {
    get {return _storage._autoResume ?? Location_Nearby_Connections_AutoResumeFrame()}
    set {_uniqueStorage()._autoResume = newValue}
  }
  var hasAutoResume: Bool {return _storage._autoResume != nil}
  mutating func clearAutoResume() {_uniqueStorage()._autoResume = nil}

  var autoReconnect: Location_Nearby_Connections_AutoReconnectFrame {
    get {return _storage._autoReconnect ?? Location_Nearby_Connections_AutoReconnectFrame()}
    set {_uniqueStorage()._autoReconnect = newValue}
  }
  var hasAutoReconnect: Bool {return _storage._autoReconnect != nil}
  mutating func clearAutoReconnect() {_uniqueStorage()._autoReconnect = nil}

  var bandwidthUpgradeRetry: Location_Nearby_Connections_BandwidthUpgradeRetryFrame {
    get {return _storage._bandwidthUpgradeRetry ?? Location_Nearby_Connections_BandwidthUpgradeRetryFrame()}
    set {_uniqueStorage()._bandwidthUpgradeRetry = newValue}
  }
  var hasBandwidthUpgradeRetry: Bool {return _storage._bandwidthUpgradeRetry != nil}
  mutating func clearBandwidthUpgradeRetry() {_uniqueStorage()._bandwidthUpgradeRetry = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum FrameType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownFrameType
    case connectionRequest
    case connectionResponse
    case payloadTransfer
    case bandwidthUpgradeNegotiation
    case keepAlive
    case disconnection
    case pairedKeyEncryption
    case authenticationMessage
    case authenticationResult
    case autoResume
    case autoReconnect
    case bandwidthUpgradeRetry

    init() {
      self = .unknownFrameType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownFrameType
      case 1: self = .connectionRequest
      case 2: self = .connectionResponse
      case 3: self = .payloadTransfer
      case 4: self = .bandwidthUpgradeNegotiation
      case 5: self = .keepAlive
      case 6: self = .disconnection
      case 7: self = .pairedKeyEncryption
      case 8: self = .authenticationMessage
      case 9: self = .authenticationResult
      case 10: self = .autoResume
      case 11: self = .autoReconnect
      case 12: self = .bandwidthUpgradeRetry
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownFrameType: return 0
      case .connectionRequest: return 1
      case .connectionResponse: return 2
      case .payloadTransfer: return 3
      case .bandwidthUpgradeNegotiation: return 4
      case .keepAlive: return 5
      case .disconnection: return 6
      case .pairedKeyEncryption: return 7
      case .authenticationMessage: return 8
      case .authenticationResult: return 9
      case .autoResume: return 10
      case .autoReconnect: return 11
      case .bandwidthUpgradeRetry: return 12
      }
    }

  }

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

#if swift(>=4.2)

extension Location_Nearby_Connections_V1Frame.FrameType: CaseIterable {
}

#endif

struct Location_Nearby_Connections_ConnectionRequestFrame {

  var endpointID: String {
    get {return _storage._endpointID ?? String()}
    set {_uniqueStorage()._endpointID = newValue}
  }
  var hasEndpointID: Bool {return _storage._endpointID != nil}
  mutating func clearEndpointID() {_uniqueStorage()._endpointID = nil}

  var endpointName: String {
    get {return _storage._endpointName ?? String()}
    set {_uniqueStorage()._endpointName = newValue}
  }
  var hasEndpointName: Bool {return _storage._endpointName != nil}
  mutating func clearEndpointName() {_uniqueStorage()._endpointName = nil}

  var handshakeData: Data {
    get {return _storage._handshakeData ?? Data()}
    set {_uniqueStorage()._handshakeData = newValue}
  }
  var hasHandshakeData: Bool {return _storage._handshakeData != nil}
  mutating func clearHandshakeData() {_uniqueStorage()._handshakeData = nil}

  var nonce: Int32 {
    get {return _storage._nonce ?? 0}
    set {_uniqueStorage()._nonce = newValue}
  }
  var hasNonce: Bool {return _storage._nonce != nil}
  mutating func clearNonce() {_uniqueStorage()._nonce = nil}

  var mediums: [Location_Nearby_Connections_ConnectionRequestFrame.Medium] {
    get {return _storage._mediums}
    set {_uniqueStorage()._mediums = newValue}
  }

  var endpointInfo: Data {
    get {return _storage._endpointInfo ?? Data()}
    set {_uniqueStorage()._endpointInfo = newValue}
  }
  var hasEndpointInfo: Bool {return _storage._endpointInfo != nil}
  mutating func clearEndpointInfo() {_uniqueStorage()._endpointInfo = nil}

  var mediumMetadata: Location_Nearby_Connections_MediumMetadata {
    get {return _storage._mediumMetadata ?? Location_Nearby_Connections_MediumMetadata()}
    set {_uniqueStorage()._mediumMetadata = newValue}
  }
  var hasMediumMetadata: Bool {return _storage._mediumMetadata != nil}
  mutating func clearMediumMetadata() {_uniqueStorage()._mediumMetadata = nil}

  var keepAliveIntervalMillis: Int32 {
    get {return _storage._keepAliveIntervalMillis ?? 0}
    set {_uniqueStorage()._keepAliveIntervalMillis = newValue}
  }
  var hasKeepAliveIntervalMillis: Bool {return _storage._keepAliveIntervalMillis != nil}
  mutating func clearKeepAliveIntervalMillis() {_uniqueStorage()._keepAliveIntervalMillis = nil}

  var keepAliveTimeoutMillis: Int32 {
    get {return _storage._keepAliveTimeoutMillis ?? 0}
    set {_uniqueStorage()._keepAliveTimeoutMillis = newValue}
  }
  var hasKeepAliveTimeoutMillis: Bool {return _storage._keepAliveTimeoutMillis != nil}
  mutating func clearKeepAliveTimeoutMillis() {_uniqueStorage()._keepAliveTimeoutMillis = nil}

  var deviceType: Int32 {
    get {return _storage._deviceType ?? 0}
    set {_uniqueStorage()._deviceType = newValue}
  }
  var hasDeviceType: Bool {return _storage._deviceType != nil}
  mutating func clearDeviceType() {_uniqueStorage()._deviceType = nil}

  var deviceInfo: Data {
    get {return _storage._deviceInfo ?? Data()}
    set {_uniqueStorage()._deviceInfo = newValue}
  }
  var hasDeviceInfo: Bool {return _storage._deviceInfo != nil}
  mutating func clearDeviceInfo() {_uniqueStorage()._deviceInfo = nil}

  var device: OneOf_Device? {
    get {return _storage._device}
    set {_uniqueStorage()._device = newValue}
  }

  var connectionsDevice: Location_Nearby_Connections_ConnectionsDevice {
    get {
      if case .connectionsDevice(let v)? = _storage._device {return v}
      return Location_Nearby_Connections_ConnectionsDevice()
    }
    set {_uniqueStorage()._device = .connectionsDevice(newValue)}
  }

  var presenceDevice: Location_Nearby_Connections_PresenceDevice {
    get {
      if case .presenceDevice(let v)? = _storage._device {return v}
      return Location_Nearby_Connections_PresenceDevice()
    }
    set {_uniqueStorage()._device = .presenceDevice(newValue)}
  }

  var connectionMode: Location_Nearby_Connections_ConnectionRequestFrame.ConnectionMode {
    get {return _storage._connectionMode ?? .legacy}
    set {_uniqueStorage()._connectionMode = newValue}
  }
  var hasConnectionMode: Bool {return _storage._connectionMode != nil}
  mutating func clearConnectionMode() {_uniqueStorage()._connectionMode = nil}

  var locationHint: Location_Nearby_Connections_LocationHint {
    get {return _storage._locationHint ?? Location_Nearby_Connections_LocationHint()}
    set {_uniqueStorage()._locationHint = newValue}
  }
  var hasLocationHint: Bool {return _storage._locationHint != nil}
  mutating func clearLocationHint() {_uniqueStorage()._locationHint = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OneOf_Device: Equatable {
    case connectionsDevice(Location_Nearby_Connections_ConnectionsDevice)
    case presenceDevice(Location_Nearby_Connections_PresenceDevice)

  #if !swift(>=4.1)
    static func ==(lhs: Location_Nearby_Connections_ConnectionRequestFrame.OneOf_Device, rhs: Location_Nearby_Connections_ConnectionRequestFrame.OneOf_Device) -> Bool {
      switch (lhs, rhs) {
      case (.connectionsDevice, .connectionsDevice): return {
        guard case .connectionsDevice(let l) = lhs, case .connectionsDevice(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.presenceDevice, .presenceDevice): return {
        guard case .presenceDevice(let l) = lhs, case .presenceDevice(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      default: return false
      }
    }
  #endif
  }

  enum Medium: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownMedium
    case mdns
    case bluetooth
    case wifiHotspot
    case ble
    case wifiLan
    case wifiAware
    case nfc
    case wifiDirect
    case webRtc
    case bleL2Cap
    case usb
    case webRtcNonCellular
    case awdl

    init() {
      self = .unknownMedium
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownMedium
      case 1: self = .mdns
      case 2: self = .bluetooth
      case 3: self = .wifiHotspot
      case 4: self = .ble
      case 5: self = .wifiLan
      case 6: self = .wifiAware
      case 7: self = .nfc
      case 8: self = .wifiDirect
      case 9: self = .webRtc
      case 10: self = .bleL2Cap
      case 11: self = .usb
      case 12: self = .webRtcNonCellular
      case 13: self = .awdl
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownMedium: return 0
      case .mdns: return 1
      case .bluetooth: return 2
      case .wifiHotspot: return 3
      case .ble: return 4
      case .wifiLan: return 5
      case .wifiAware: return 6
      case .nfc: return 7
      case .wifiDirect: return 8
      case .webRtc: return 9
      case .bleL2Cap: return 10
      case .usb: return 11
      case .webRtcNonCellular: return 12
      case .awdl: return 13
      }
    }

  }

  enum ConnectionMode: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case legacy
    case instant

    init() {
      self = .legacy
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .legacy
      case 1: self = .instant
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .legacy: return 0
      case .instant: return 1
      }
    }

  }

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

#if swift(>=4.2)

extension Location_Nearby_Connections_ConnectionRequestFrame.Medium: CaseIterable {
}

extension Location_Nearby_Connections_ConnectionRequestFrame.ConnectionMode: CaseIterable {
}

#endif

struct Location_Nearby_Connections_ConnectionResponseFrame {

  var status: Int32 {
    get {return _status ?? 0}
    set {_status = newValue}
  }
  var hasStatus: Bool {return self._status != nil}
  mutating func clearStatus() {self._status = nil}

  var handshakeData: Data {
    get {return _handshakeData ?? Data()}
    set {_handshakeData = newValue}
  }
  var hasHandshakeData: Bool {return self._handshakeData != nil}
  mutating func clearHandshakeData() {self._handshakeData = nil}

  var response: Location_Nearby_Connections_ConnectionResponseFrame.ResponseStatus {
    get {return _response ?? .unknownResponseStatus}
    set {_response = newValue}
  }
  var hasResponse: Bool {return self._response != nil}
  mutating func clearResponse() {self._response = nil}

  var osInfo: Location_Nearby_Connections_OsInfo {
    get {return _osInfo ?? Location_Nearby_Connections_OsInfo()}
    set {_osInfo = newValue}
  }
  var hasOsInfo: Bool {return self._osInfo != nil}
  mutating func clearOsInfo() {self._osInfo = nil}

  var multiplexSocketBitmask: Int32 {
    get {return _multiplexSocketBitmask ?? 0}
    set {_multiplexSocketBitmask = newValue}
  }
  var hasMultiplexSocketBitmask: Bool {return self._multiplexSocketBitmask != nil}
  mutating func clearMultiplexSocketBitmask() {self._multiplexSocketBitmask = nil}

  var nearbyConnectionsVersion: Int32 {
    get {return _nearbyConnectionsVersion ?? 0}
    set {_nearbyConnectionsVersion = newValue}
  }
  var hasNearbyConnectionsVersion: Bool {return self._nearbyConnectionsVersion != nil}
  mutating func clearNearbyConnectionsVersion() {self._nearbyConnectionsVersion = nil}

  var safeToDisconnectVersion: Int32 {
    get {return _safeToDisconnectVersion ?? 0}
    set {_safeToDisconnectVersion = newValue}
  }
  var hasSafeToDisconnectVersion: Bool {return self._safeToDisconnectVersion != nil}
  mutating func clearSafeToDisconnectVersion() {self._safeToDisconnectVersion = nil}

  var locationHint: Location_Nearby_Connections_LocationHint {
    get {return _locationHint ?? Location_Nearby_Connections_LocationHint()}
    set {_locationHint = newValue}
  }
  var hasLocationHint: Bool {return self._locationHint != nil}
  mutating func clearLocationHint() {self._locationHint = nil}

  var keepAliveTimeoutMillis: Int32 {
    get {return _keepAliveTimeoutMillis ?? 0}
    set {_keepAliveTimeoutMillis = newValue}
  }
  var hasKeepAliveTimeoutMillis: Bool {return self._keepAliveTimeoutMillis != nil}
  mutating func clearKeepAliveTimeoutMillis() {self._keepAliveTimeoutMillis = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum ResponseStatus: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownResponseStatus
    case accept
    case reject

    init() {
      self = .unknownResponseStatus
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownResponseStatus
      case 1: self = .accept
      case 2: self = .reject
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownResponseStatus: return 0
      case .accept: return 1
      case .reject: return 2
      }
    }

  }

  init() {}

  fileprivate var _status: Int32? = nil
  fileprivate var _handshakeData: Data? = nil
  fileprivate var _response: Location_Nearby_Connections_ConnectionResponseFrame.ResponseStatus? = nil
  fileprivate var _osInfo: Location_Nearby_Connections_OsInfo? = nil
  fileprivate var _multiplexSocketBitmask: Int32? = nil
  fileprivate var _nearbyConnectionsVersion: Int32? = nil
  fileprivate var _safeToDisconnectVersion: Int32? = nil
  fileprivate var _locationHint: Location_Nearby_Connections_LocationHint? = nil
  fileprivate var _keepAliveTimeoutMillis: Int32? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_ConnectionResponseFrame.ResponseStatus: CaseIterable {
}

#endif

struct Location_Nearby_Connections_PayloadTransferFrame {

  var packetType: Location_Nearby_Connections_PayloadTransferFrame.PacketType {
    get {return _packetType ?? .unknownPacketType}
    set {_packetType = newValue}
  }
  var hasPacketType: Bool {return self._packetType != nil}
  mutating func clearPacketType() {self._packetType = nil}

  var payloadHeader: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader {
    get {return _payloadHeader ?? Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader()}
    set {_payloadHeader = newValue}
  }
  var hasPayloadHeader: Bool {return self._payloadHeader != nil}
  mutating func clearPayloadHeader() {self._payloadHeader = nil}

  var payloadChunk: Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk {
    get {return _payloadChunk ?? Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk()}
    set {_payloadChunk = newValue}
  }
  var hasPayloadChunk: Bool {return self._payloadChunk != nil}
  mutating func clearPayloadChunk() {self._payloadChunk = nil}

  var controlMessage: Location_Nearby_Connections_PayloadTransferFrame.ControlMessage {
    get {return _controlMessage ?? Location_Nearby_Connections_PayloadTransferFrame.ControlMessage()}
    set {_controlMessage = newValue}
  }
  var hasControlMessage: Bool {return self._controlMessage != nil}
  mutating func clearControlMessage() {self._controlMessage = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum PacketType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownPacketType
    case data
    case control
    case payloadAck

    init() {
      self = .unknownPacketType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownPacketType
      case 1: self = .data
      case 2: self = .control
      case 3: self = .payloadAck
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownPacketType: return 0
      case .data: return 1
      case .control: return 2
      case .payloadAck: return 3
      }
    }

  }

  struct PayloadHeader {

    var id: Int64 {
      get {return _id ?? 0}
      set {_id = newValue}
    }
    var hasID: Bool {return self._id != nil}
    mutating func clearID() {self._id = nil}

    var type: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader.PayloadType {
      get {return _type ?? .unknownPayloadType}
      set {_type = newValue}
    }
    var hasType: Bool {return self._type != nil}
    mutating func clearType() {self._type = nil}

    var totalSize: Int64 {
      get {return _totalSize ?? 0}
      set {_totalSize = newValue}
    }
    var hasTotalSize: Bool {return self._totalSize != nil}
    mutating func clearTotalSize() {self._totalSize = nil}

    var isSensitive: Bool {
      get {return _isSensitive ?? false}
      set {_isSensitive = newValue}
    }
    var hasIsSensitive: Bool {return self._isSensitive != nil}
    mutating func clearIsSensitive() {self._isSensitive = nil}

    var fileName: String {
      get {return _fileName ?? String()}
      set {_fileName = newValue}
    }
    var hasFileName: Bool {return self._fileName != nil}
    mutating func clearFileName() {self._fileName = nil}

    var parentFolder: String {
      get {return _parentFolder ?? String()}
      set {_parentFolder = newValue}
    }
    var hasParentFolder: Bool {return self._parentFolder != nil}
    mutating func clearParentFolder() {self._parentFolder = nil}

    var lastModifiedTimestampMillis: Int64 {
      get {return _lastModifiedTimestampMillis ?? 0}
      set {_lastModifiedTimestampMillis = newValue}
    }
    var hasLastModifiedTimestampMillis: Bool {return self._lastModifiedTimestampMillis != nil}
    mutating func clearLastModifiedTimestampMillis() {self._lastModifiedTimestampMillis = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    enum PayloadType: SwiftProtobuf.Enum {
      typealias RawValue = Int
      case unknownPayloadType
      case bytes
      case file
      case stream

      init() {
        self = .unknownPayloadType
      }

      init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unknownPayloadType
        case 1: self = .bytes
        case 2: self = .file
        case 3: self = .stream
        default: return nil
        }
      }

      var rawValue: Int {
        switch self {
        case .unknownPayloadType: return 0
        case .bytes: return 1
        case .file: return 2
        case .stream: return 3
        }
      }

    }

    init() {}

    fileprivate var _id: Int64? = nil
    fileprivate var _type: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader.PayloadType? = nil
    fileprivate var _totalSize: Int64? = nil
    fileprivate var _isSensitive: Bool? = nil
    fileprivate var _fileName: String? = nil
    fileprivate var _parentFolder: String? = nil
    fileprivate var _lastModifiedTimestampMillis: Int64? = nil
  }

  struct PayloadChunk {

    var flags: Int32 {
      get {return _flags ?? 0}
      set {_flags = newValue}
    }
    var hasFlags: Bool {return self._flags != nil}
    mutating func clearFlags() {self._flags = nil}

    var offset: Int64 {
      get {return _offset ?? 0}
      set {_offset = newValue}
    }
    var hasOffset: Bool {return self._offset != nil}
    mutating func clearOffset() {self._offset = nil}

    var body: Data {
      get {return _body ?? Data()}
      set {_body = newValue}
    }
    var hasBody: Bool {return self._body != nil}
    mutating func clearBody() {self._body = nil}

    var index: Int32 {
      get {return _index ?? 0}
      set {_index = newValue}
    }
    var hasIndex: Bool {return self._index != nil}
    mutating func clearIndex() {self._index = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    enum Flags: SwiftProtobuf.Enum {
      typealias RawValue = Int
      case lastChunk

      init() {
        self = .lastChunk
      }

      init?(rawValue: Int) {
        switch rawValue {
        case 1: self = .lastChunk
        default: return nil
        }
      }

      var rawValue: Int {
        switch self {
        case .lastChunk: return 1
        }
      }

    }

    init() {}

    fileprivate var _flags: Int32? = nil
    fileprivate var _offset: Int64? = nil
    fileprivate var _body: Data? = nil
    fileprivate var _index: Int32? = nil
  }

  struct ControlMessage {

    var event: Location_Nearby_Connections_PayloadTransferFrame.ControlMessage.EventType {
      get {return _event ?? .unknownEventType}
      set {_event = newValue}
    }
    var hasEvent: Bool {return self._event != nil}
    mutating func clearEvent() {self._event = nil}

    var offset: Int64 {
      get {return _offset ?? 0}
      set {_offset = newValue}
    }
    var hasOffset: Bool {return self._offset != nil}
    mutating func clearOffset() {self._offset = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    enum EventType: SwiftProtobuf.Enum {
      typealias RawValue = Int
      case unknownEventType
      case payloadError
      case payloadCanceled

      case payloadReceivedAck

      init() {
        self = .unknownEventType
      }

      init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unknownEventType
        case 1: self = .payloadError
        case 2: self = .payloadCanceled
        case 3: self = .payloadReceivedAck
        default: return nil
        }
      }

      var rawValue: Int {
        switch self {
        case .unknownEventType: return 0
        case .payloadError: return 1
        case .payloadCanceled: return 2
        case .payloadReceivedAck: return 3
        }
      }

    }

    init() {}

    fileprivate var _event: Location_Nearby_Connections_PayloadTransferFrame.ControlMessage.EventType? = nil
    fileprivate var _offset: Int64? = nil
  }

  init() {}

  fileprivate var _packetType: Location_Nearby_Connections_PayloadTransferFrame.PacketType? = nil
  fileprivate var _payloadHeader: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader? = nil
  fileprivate var _payloadChunk: Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk? = nil
  fileprivate var _controlMessage: Location_Nearby_Connections_PayloadTransferFrame.ControlMessage? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_PayloadTransferFrame.PacketType: CaseIterable {
}

extension Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader.PayloadType: CaseIterable {
}

extension Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk.Flags: CaseIterable {
}

extension Location_Nearby_Connections_PayloadTransferFrame.ControlMessage.EventType: CaseIterable {
}

#endif

struct Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame {

  var eventType: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.EventType {
    get {return _eventType ?? .unknownEventType}
    set {_eventType = newValue}
  }
  var hasEventType: Bool {return self._eventType != nil}
  mutating func clearEventType() {self._eventType = nil}

  var upgradePathInfo: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo {
    get {return _upgradePathInfo ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo()}
    set {_upgradePathInfo = newValue}
  }
  var hasUpgradePathInfo: Bool {return self._upgradePathInfo != nil}
  mutating func clearUpgradePathInfo() {self._upgradePathInfo = nil}

  var clientIntroduction: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroduction {
    get {return _clientIntroduction ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroduction()}
    set {_clientIntroduction = newValue}
  }
  var hasClientIntroduction: Bool {return self._clientIntroduction != nil}
  mutating func clearClientIntroduction() {self._clientIntroduction = nil}

  var clientIntroductionAck: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroductionAck {
    get {return _clientIntroductionAck ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroductionAck()}
    set {_clientIntroductionAck = newValue}
  }
  var hasClientIntroductionAck: Bool {return self._clientIntroductionAck != nil}
  mutating func clearClientIntroductionAck() {self._clientIntroductionAck = nil}

  var safeToClosePriorChannel: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel {
    get {return _safeToClosePriorChannel ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel()}
    set {_safeToClosePriorChannel = newValue}
  }
  var hasSafeToClosePriorChannel: Bool {return self._safeToClosePriorChannel != nil}
  mutating func clearSafeToClosePriorChannel() {self._safeToClosePriorChannel = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum EventType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownEventType
    case upgradePathAvailable
    case lastWriteToPriorChannel
    case safeToClosePriorChannel
    case clientIntroduction
    case upgradeFailure
    case clientIntroductionAck

    case upgradePathRequest

    init() {
      self = .unknownEventType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownEventType
      case 1: self = .upgradePathAvailable
      case 2: self = .lastWriteToPriorChannel
      case 3: self = .safeToClosePriorChannel
      case 4: self = .clientIntroduction
      case 5: self = .upgradeFailure
      case 6: self = .clientIntroductionAck
      case 7: self = .upgradePathRequest
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownEventType: return 0
      case .upgradePathAvailable: return 1
      case .lastWriteToPriorChannel: return 2
      case .safeToClosePriorChannel: return 3
      case .clientIntroduction: return 4
      case .upgradeFailure: return 5
      case .clientIntroductionAck: return 6
      case .upgradePathRequest: return 7
      }
    }

  }

  struct UpgradePathInfo {

    var medium: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium {
      get {return _storage._medium ?? .unknownMedium}
      set {_uniqueStorage()._medium = newValue}
    }
    var hasMedium: Bool {return _storage._medium != nil}
    mutating func clearMedium() {_uniqueStorage()._medium = nil}

    var wifiHotspotCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials {
      get {return _storage._wifiHotspotCredentials ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials()}
      set {_uniqueStorage()._wifiHotspotCredentials = newValue}
    }
    var hasWifiHotspotCredentials: Bool {return _storage._wifiHotspotCredentials != nil}
    mutating func clearWifiHotspotCredentials() {_uniqueStorage()._wifiHotspotCredentials = nil}

    var wifiLanSocket: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket {
      get {return _storage._wifiLanSocket ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket()}
      set {_uniqueStorage()._wifiLanSocket = newValue}
    }
    var hasWifiLanSocket: Bool {return _storage._wifiLanSocket != nil}
    mutating func clearWifiLanSocket() {_uniqueStorage()._wifiLanSocket = nil}

    var bluetoothCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials {
      get {return _storage._bluetoothCredentials ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials()}
      set {_uniqueStorage()._bluetoothCredentials = newValue}
    }
    var hasBluetoothCredentials: Bool {return _storage._bluetoothCredentials != nil}
    mutating func clearBluetoothCredentials() {_uniqueStorage()._bluetoothCredentials = nil}

    var wifiAwareCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials {
      get {return _storage._wifiAwareCredentials ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials()}
      set {_uniqueStorage()._wifiAwareCredentials = newValue}
    }
    var hasWifiAwareCredentials: Bool {return _storage._wifiAwareCredentials != nil}
    mutating func clearWifiAwareCredentials() {_uniqueStorage()._wifiAwareCredentials = nil}

    var wifiDirectCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials {
      get {return _storage._wifiDirectCredentials ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials()}
      set {_uniqueStorage()._wifiDirectCredentials = newValue}
    }
    var hasWifiDirectCredentials: Bool {return _storage._wifiDirectCredentials != nil}
    mutating func clearWifiDirectCredentials() {_uniqueStorage()._wifiDirectCredentials = nil}

    var webRtcCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials {
      get {return _storage._webRtcCredentials ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials()}
      set {_uniqueStorage()._webRtcCredentials = newValue}
    }
    var hasWebRtcCredentials: Bool {return _storage._webRtcCredentials != nil}
    mutating func clearWebRtcCredentials() {_uniqueStorage()._webRtcCredentials = nil}

    var awdlCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials {
      get {return _storage._awdlCredentials ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials()}
      set {_uniqueStorage()._awdlCredentials = newValue}
    }
    var hasAwdlCredentials: Bool {return _storage._awdlCredentials != nil}
    mutating func clearAwdlCredentials() {_uniqueStorage()._awdlCredentials = nil}

    var supportsDisablingEncryption: Bool {
      get {return _storage._supportsDisablingEncryption ?? false}
      set {_uniqueStorage()._supportsDisablingEncryption = newValue}
    }
    var hasSupportsDisablingEncryption: Bool {return _storage._supportsDisablingEncryption != nil}
    mutating func clearSupportsDisablingEncryption() {_uniqueStorage()._supportsDisablingEncryption = nil}

    var supportsClientIntroductionAck: Bool {
      get {return _storage._supportsClientIntroductionAck ?? false}
      set {_uniqueStorage()._supportsClientIntroductionAck = newValue}
    }
    var hasSupportsClientIntroductionAck: Bool {return _storage._supportsClientIntroductionAck != nil}
    mutating func clearSupportsClientIntroductionAck() {_uniqueStorage()._supportsClientIntroductionAck = nil}

    var upgradePathRequest: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest {
      get {return _storage._upgradePathRequest ?? Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest()}
      set {_uniqueStorage()._upgradePathRequest = newValue}
    }
    var hasUpgradePathRequest: Bool {return _storage._upgradePathRequest != nil}
    mutating func clearUpgradePathRequest() {_uniqueStorage()._upgradePathRequest = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    enum Medium: SwiftProtobuf.Enum {
      typealias RawValue = Int
      case unknownMedium
      case mdns
      case bluetooth
      case wifiHotspot
      case ble
      case wifiLan
      case wifiAware
      case nfc
      case wifiDirect
      case webRtc

      case usb
      case webRtcNonCellular
      case awdl

      init() {
        self = .unknownMedium
      }

      init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unknownMedium
        case 1: self = .mdns
        case 2: self = .bluetooth
        case 3: self = .wifiHotspot
        case 4: self = .ble
        case 5: self = .wifiLan
        case 6: self = .wifiAware
        case 7: self = .nfc
        case 8: self = .wifiDirect
        case 9: self = .webRtc
        case 11: self = .usb
        case 12: self = .webRtcNonCellular
        case 13: self = .awdl
        default: return nil
        }
      }

      var rawValue: Int {
        switch self {
        case .unknownMedium: return 0
        case .mdns: return 1
        case .bluetooth: return 2
        case .wifiHotspot: return 3
        case .ble: return 4
        case .wifiLan: return 5
        case .wifiAware: return 6
        case .nfc: return 7
        case .wifiDirect: return 8
        case .webRtc: return 9
        case .usb: return 11
        case .webRtcNonCellular: return 12
        case .awdl: return 13
        }
      }

    }

    struct WifiHotspotCredentials {

      var ssid: String {
        get {return _ssid ?? String()}
        set {_ssid = newValue}
      }
      var hasSsid: Bool {return self._ssid != nil}
      mutating func clearSsid() {self._ssid = nil}

      var password: String {
        get {return _password ?? String()}
        set {_password = newValue}
      }
      var hasPassword: Bool {return self._password != nil}
      mutating func clearPassword() {self._password = nil}

      var port: Int32 {
        get {return _port ?? 0}
        set {_port = newValue}
      }
      var hasPort: Bool {return self._port != nil}
      mutating func clearPort() {self._port = nil}

      var gateway: String {
        get {return _gateway ?? "0.0.0.0"}
        set {_gateway = newValue}
      }
      var hasGateway: Bool {return self._gateway != nil}
      mutating func clearGateway() {self._gateway = nil}

      var frequency: Int32 {
        get {return _frequency ?? -1}
        set {_frequency = newValue}
      }
      var hasFrequency: Bool {return self._frequency != nil}
      mutating func clearFrequency() {self._frequency = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _ssid: String? = nil
      fileprivate var _password: String? = nil
      fileprivate var _port: Int32? = nil
      fileprivate var _gateway: String? = nil
      fileprivate var _frequency: Int32? = nil
    }

    struct WifiLanSocket {

      var ipAddress: Data {
        get {return _ipAddress ?? Data()}
        set {_ipAddress = newValue}
      }
      var hasIpAddress: Bool {return self._ipAddress != nil}
      mutating func clearIpAddress() {self._ipAddress = nil}

      var wifiPort: Int32 {
        get {return _wifiPort ?? 0}
        set {_wifiPort = newValue}
      }
      var hasWifiPort: Bool {return self._wifiPort != nil}
      mutating func clearWifiPort() {self._wifiPort = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _ipAddress: Data? = nil
      fileprivate var _wifiPort: Int32? = nil
    }

    struct BluetoothCredentials {

      var serviceName: String {
        get {return _serviceName ?? String()}
        set {_serviceName = newValue}
      }
      var hasServiceName: Bool {return self._serviceName != nil}
      mutating func clearServiceName() {self._serviceName = nil}

      var macAddress: String {
        get {return _macAddress ?? String()}
        set {_macAddress = newValue}
      }
      var hasMacAddress: Bool {return self._macAddress != nil}
      mutating func clearMacAddress() {self._macAddress = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _serviceName: String? = nil
      fileprivate var _macAddress: String? = nil
    }

    struct WifiAwareCredentials {

      var serviceID: String {
        get {return _serviceID ?? String()}
        set {_serviceID = newValue}
      }
      var hasServiceID: Bool {return self._serviceID != nil}
      mutating func clearServiceID() {self._serviceID = nil}

      var serviceInfo: Data {
        get {return _serviceInfo ?? Data()}
        set {_serviceInfo = newValue}
      }
      var hasServiceInfo: Bool {return self._serviceInfo != nil}
      mutating func clearServiceInfo() {self._serviceInfo = nil}

      var password: String {
        get {return _password ?? String()}
        set {_password = newValue}
      }
      var hasPassword: Bool {return self._password != nil}
      mutating func clearPassword() {self._password = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _serviceID: String? = nil
      fileprivate var _serviceInfo: Data? = nil
      fileprivate var _password: String? = nil
    }

    struct WifiDirectCredentials {

      var ssid: String {
        get {return _ssid ?? String()}
        set {_ssid = newValue}
      }
      var hasSsid: Bool {return self._ssid != nil}
      mutating func clearSsid() {self._ssid = nil}

      var password: String {
        get {return _password ?? String()}
        set {_password = newValue}
      }
      var hasPassword: Bool {return self._password != nil}
      mutating func clearPassword() {self._password = nil}

      var port: Int32 {
        get {return _port ?? 0}
        set {_port = newValue}
      }
      var hasPort: Bool {return self._port != nil}
      mutating func clearPort() {self._port = nil}

      var frequency: Int32 {
        get {return _frequency ?? 0}
        set {_frequency = newValue}
      }
      var hasFrequency: Bool {return self._frequency != nil}
      mutating func clearFrequency() {self._frequency = nil}

      var gateway: String {
        get {return _gateway ?? "0.0.0.0"}
        set {_gateway = newValue}
      }
      var hasGateway: Bool {return self._gateway != nil}
      mutating func clearGateway() {self._gateway = nil}

      var ipV6Address: Data {
        get {return _ipV6Address ?? Data()}
        set {_ipV6Address = newValue}
      }
      var hasIpV6Address: Bool {return self._ipV6Address != nil}
      mutating func clearIpV6Address() {self._ipV6Address = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _ssid: String? = nil
      fileprivate var _password: String? = nil
      fileprivate var _port: Int32? = nil
      fileprivate var _frequency: Int32? = nil
      fileprivate var _gateway: String? = nil
      fileprivate var _ipV6Address: Data? = nil
    }

    struct WebRtcCredentials {

      var peerID: String {
        get {return _peerID ?? String()}
        set {_peerID = newValue}
      }
      var hasPeerID: Bool {return self._peerID != nil}
      mutating func clearPeerID() {self._peerID = nil}

      var locationHint: Location_Nearby_Connections_LocationHint {
        get {return _locationHint ?? Location_Nearby_Connections_LocationHint()}
        set {_locationHint = newValue}
      }
      var hasLocationHint: Bool {return self._locationHint != nil}
      mutating func clearLocationHint() {self._locationHint = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _peerID: String? = nil
      fileprivate var _locationHint: Location_Nearby_Connections_LocationHint? = nil
    }

    struct AwdlCredentials {

      var serviceName: String {
        get {return _serviceName ?? String()}
        set {_serviceName = newValue}
      }
      var hasServiceName: Bool {return self._serviceName != nil}
      mutating func clearServiceName() {self._serviceName = nil}

      var serviceType: String {
        get {return _serviceType ?? String()}
        set {_serviceType = newValue}
      }
      var hasServiceType: Bool {return self._serviceType != nil}
      mutating func clearServiceType() {self._serviceType = nil}

      var password: String {
        get {return _password ?? String()}
        set {_password = newValue}
      }
      var hasPassword: Bool {return self._password != nil}
      mutating func clearPassword() {self._password = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _serviceName: String? = nil
      fileprivate var _serviceType: String? = nil
      fileprivate var _password: String? = nil
    }

    struct UpgradePathRequest {

      var mediums: [Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium] = []

      var mediumMetaData: Location_Nearby_Connections_MediumMetadata {
        get {return _mediumMetaData ?? Location_Nearby_Connections_MediumMetadata()}
        set {_mediumMetaData = newValue}
      }
      var hasMediumMetaData: Bool {return self._mediumMetaData != nil}
      mutating func clearMediumMetaData() {self._mediumMetaData = nil}

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}

      fileprivate var _mediumMetaData: Location_Nearby_Connections_MediumMetadata? = nil
    }

    init() {}

    fileprivate var _storage = _StorageClass.defaultInstance
  }

  struct SafeToClosePriorChannel {

    var staFrequency: Int32 {
      get {return _staFrequency ?? 0}
      set {_staFrequency = newValue}
    }
    var hasStaFrequency: Bool {return self._staFrequency != nil}
    mutating func clearStaFrequency() {self._staFrequency = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    fileprivate var _staFrequency: Int32? = nil
  }

  struct ClientIntroduction {

    var endpointID: String {
      get {return _endpointID ?? String()}
      set {_endpointID = newValue}
    }
    var hasEndpointID: Bool {return self._endpointID != nil}
    mutating func clearEndpointID() {self._endpointID = nil}

    var supportsDisablingEncryption: Bool {
      get {return _supportsDisablingEncryption ?? false}
      set {_supportsDisablingEncryption = newValue}
    }
    var hasSupportsDisablingEncryption: Bool {return self._supportsDisablingEncryption != nil}
    mutating func clearSupportsDisablingEncryption() {self._supportsDisablingEncryption = nil}

    var lastEndpointID: String {
      get {return _lastEndpointID ?? String()}
      set {_lastEndpointID = newValue}
    }
    var hasLastEndpointID: Bool {return self._lastEndpointID != nil}
    mutating func clearLastEndpointID() {self._lastEndpointID = nil}

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}

    fileprivate var _endpointID: String? = nil
    fileprivate var _supportsDisablingEncryption: Bool? = nil
    fileprivate var _lastEndpointID: String? = nil
  }

  struct ClientIntroductionAck {

    var unknownFields = SwiftProtobuf.UnknownStorage()

    init() {}
  }

  init() {}

  fileprivate var _eventType: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.EventType? = nil
  fileprivate var _upgradePathInfo: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo? = nil
  fileprivate var _clientIntroduction: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroduction? = nil
  fileprivate var _clientIntroductionAck: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroductionAck? = nil
  fileprivate var _safeToClosePriorChannel: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.EventType: CaseIterable {
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium: CaseIterable {
}

#endif

struct Location_Nearby_Connections_BandwidthUpgradeRetryFrame {

  var supportedMedium: [Location_Nearby_Connections_BandwidthUpgradeRetryFrame.Medium] = []

  var isRequest: Bool {
    get {return _isRequest ?? false}
    set {_isRequest = newValue}
  }
  var hasIsRequest: Bool {return self._isRequest != nil}
  mutating func clearIsRequest() {self._isRequest = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum Medium: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownMedium

    case bluetooth
    case wifiHotspot
    case ble
    case wifiLan
    case wifiAware
    case nfc
    case wifiDirect
    case webRtc
    case bleL2Cap
    case usb
    case webRtcNonCellular
    case awdl

    init() {
      self = .unknownMedium
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownMedium
      case 2: self = .bluetooth
      case 3: self = .wifiHotspot
      case 4: self = .ble
      case 5: self = .wifiLan
      case 6: self = .wifiAware
      case 7: self = .nfc
      case 8: self = .wifiDirect
      case 9: self = .webRtc
      case 10: self = .bleL2Cap
      case 11: self = .usb
      case 12: self = .webRtcNonCellular
      case 13: self = .awdl
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownMedium: return 0
      case .bluetooth: return 2
      case .wifiHotspot: return 3
      case .ble: return 4
      case .wifiLan: return 5
      case .wifiAware: return 6
      case .nfc: return 7
      case .wifiDirect: return 8
      case .webRtc: return 9
      case .bleL2Cap: return 10
      case .usb: return 11
      case .webRtcNonCellular: return 12
      case .awdl: return 13
      }
    }

  }

  init() {}

  fileprivate var _isRequest: Bool? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_BandwidthUpgradeRetryFrame.Medium: CaseIterable {
}

#endif

struct Location_Nearby_Connections_KeepAliveFrame {

  var ack: Bool {
    get {return _ack ?? false}
    set {_ack = newValue}
  }
  var hasAck: Bool {return self._ack != nil}
  mutating func clearAck() {self._ack = nil}

  var seqNum: UInt32 {
    get {return _seqNum ?? 0}
    set {_seqNum = newValue}
  }
  var hasSeqNum: Bool {return self._seqNum != nil}
  mutating func clearSeqNum() {self._seqNum = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _ack: Bool? = nil
  fileprivate var _seqNum: UInt32? = nil
}

struct Location_Nearby_Connections_DisconnectionFrame {

  var requestSafeToDisconnect: Bool {
    get {return _requestSafeToDisconnect ?? false}
    set {_requestSafeToDisconnect = newValue}
  }
  var hasRequestSafeToDisconnect: Bool {return self._requestSafeToDisconnect != nil}
  mutating func clearRequestSafeToDisconnect() {self._requestSafeToDisconnect = nil}

  var ackSafeToDisconnect: Bool {
    get {return _ackSafeToDisconnect ?? false}
    set {_ackSafeToDisconnect = newValue}
  }
  var hasAckSafeToDisconnect: Bool {return self._ackSafeToDisconnect != nil}
  mutating func clearAckSafeToDisconnect() {self._ackSafeToDisconnect = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _requestSafeToDisconnect: Bool? = nil
  fileprivate var _ackSafeToDisconnect: Bool? = nil
}

struct Location_Nearby_Connections_PairedKeyEncryptionFrame {

  var signedData: Data {
    get {return _signedData ?? Data()}
    set {_signedData = newValue}
  }
  var hasSignedData: Bool {return self._signedData != nil}
  mutating func clearSignedData() {self._signedData = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _signedData: Data? = nil
}

struct Location_Nearby_Connections_AuthenticationMessageFrame {

  var authMessage: Data {
    get {return _authMessage ?? Data()}
    set {_authMessage = newValue}
  }
  var hasAuthMessage: Bool {return self._authMessage != nil}
  mutating func clearAuthMessage() {self._authMessage = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _authMessage: Data? = nil
}

struct Location_Nearby_Connections_AuthenticationResultFrame {

  var result: Int32 {
    get {return _result ?? 0}
    set {_result = newValue}
  }
  var hasResult: Bool {return self._result != nil}
  mutating func clearResult() {self._result = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _result: Int32? = nil
}

struct Location_Nearby_Connections_AutoResumeFrame {

  var eventType: Location_Nearby_Connections_AutoResumeFrame.EventType {
    get {return _eventType ?? .unknownAutoResumeEventType}
    set {_eventType = newValue}
  }
  var hasEventType: Bool {return self._eventType != nil}
  mutating func clearEventType() {self._eventType = nil}

  var pendingPayloadID: Int64 {
    get {return _pendingPayloadID ?? 0}
    set {_pendingPayloadID = newValue}
  }
  var hasPendingPayloadID: Bool {return self._pendingPayloadID != nil}
  mutating func clearPendingPayloadID() {self._pendingPayloadID = nil}

  var nextPayloadChunkIndex: Int32 {
    get {return _nextPayloadChunkIndex ?? 0}
    set {_nextPayloadChunkIndex = newValue}
  }
  var hasNextPayloadChunkIndex: Bool {return self._nextPayloadChunkIndex != nil}
  mutating func clearNextPayloadChunkIndex() {self._nextPayloadChunkIndex = nil}

  var version: Int32 {
    get {return _version ?? 0}
    set {_version = newValue}
  }
  var hasVersion: Bool {return self._version != nil}
  mutating func clearVersion() {self._version = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum EventType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownAutoResumeEventType
    case payloadResumeTransferStart
    case payloadResumeTransferAck

    init() {
      self = .unknownAutoResumeEventType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownAutoResumeEventType
      case 1: self = .payloadResumeTransferStart
      case 2: self = .payloadResumeTransferAck
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownAutoResumeEventType: return 0
      case .payloadResumeTransferStart: return 1
      case .payloadResumeTransferAck: return 2
      }
    }

  }

  init() {}

  fileprivate var _eventType: Location_Nearby_Connections_AutoResumeFrame.EventType? = nil
  fileprivate var _pendingPayloadID: Int64? = nil
  fileprivate var _nextPayloadChunkIndex: Int32? = nil
  fileprivate var _version: Int32? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_AutoResumeFrame.EventType: CaseIterable {
}

#endif

struct Location_Nearby_Connections_AutoReconnectFrame {

  var endpointID: String {
    get {return _endpointID ?? String()}
    set {_endpointID = newValue}
  }
  var hasEndpointID: Bool {return self._endpointID != nil}
  mutating func clearEndpointID() {self._endpointID = nil}

  var eventType: Location_Nearby_Connections_AutoReconnectFrame.EventType {
    get {return _eventType ?? .unknownEventType}
    set {_eventType = newValue}
  }
  var hasEventType: Bool {return self._eventType != nil}
  mutating func clearEventType() {self._eventType = nil}

  var lastEndpointID: String {
    get {return _lastEndpointID ?? String()}
    set {_lastEndpointID = newValue}
  }
  var hasLastEndpointID: Bool {return self._lastEndpointID != nil}
  mutating func clearLastEndpointID() {self._lastEndpointID = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum EventType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownEventType
    case clientIntroduction
    case clientIntroductionAck

    init() {
      self = .unknownEventType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownEventType
      case 1: self = .clientIntroduction
      case 2: self = .clientIntroductionAck
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownEventType: return 0
      case .clientIntroduction: return 1
      case .clientIntroductionAck: return 2
      }
    }

  }

  init() {}

  fileprivate var _endpointID: String? = nil
  fileprivate var _eventType: Location_Nearby_Connections_AutoReconnectFrame.EventType? = nil
  fileprivate var _lastEndpointID: String? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_AutoReconnectFrame.EventType: CaseIterable {
}

#endif

struct Location_Nearby_Connections_MediumMetadata {

  var supports5Ghz: Bool {
    get {return _storage._supports5Ghz ?? false}
    set {_uniqueStorage()._supports5Ghz = newValue}
  }
  var hasSupports5Ghz: Bool {return _storage._supports5Ghz != nil}
  mutating func clearSupports5Ghz() {_uniqueStorage()._supports5Ghz = nil}

  var bssid: String {
    get {return _storage._bssid ?? String()}
    set {_uniqueStorage()._bssid = newValue}
  }
  var hasBssid: Bool {return _storage._bssid != nil}
  mutating func clearBssid() {_uniqueStorage()._bssid = nil}

  var ipAddress: Data {
    get {return _storage._ipAddress ?? Data()}
    set {_uniqueStorage()._ipAddress = newValue}
  }
  var hasIpAddress: Bool {return _storage._ipAddress != nil}
  mutating func clearIpAddress() {_uniqueStorage()._ipAddress = nil}

  var supports6Ghz: Bool {
    get {return _storage._supports6Ghz ?? false}
    set {_uniqueStorage()._supports6Ghz = newValue}
  }
  var hasSupports6Ghz: Bool {return _storage._supports6Ghz != nil}
  mutating func clearSupports6Ghz() {_uniqueStorage()._supports6Ghz = nil}

  var mobileRadio: Bool {
    get {return _storage._mobileRadio ?? false}
    set {_uniqueStorage()._mobileRadio = newValue}
  }
  var hasMobileRadio: Bool {return _storage._mobileRadio != nil}
  mutating func clearMobileRadio() {_uniqueStorage()._mobileRadio = nil}

  var apFrequency: Int32 {
    get {return _storage._apFrequency ?? -1}
    set {_uniqueStorage()._apFrequency = newValue}
  }
  var hasApFrequency: Bool {return _storage._apFrequency != nil}
  mutating func clearApFrequency() {_uniqueStorage()._apFrequency = nil}

  var availableChannels: Location_Nearby_Connections_AvailableChannels {
    get {return _storage._availableChannels ?? Location_Nearby_Connections_AvailableChannels()}
    set {_uniqueStorage()._availableChannels = newValue}
  }
  var hasAvailableChannels: Bool {return _storage._availableChannels != nil}
  mutating func clearAvailableChannels() {_uniqueStorage()._availableChannels = nil}

  var wifiDirectCliUsableChannels: Location_Nearby_Connections_WifiDirectCliUsableChannels {
    get {return _storage._wifiDirectCliUsableChannels ?? Location_Nearby_Connections_WifiDirectCliUsableChannels()}
    set {_uniqueStorage()._wifiDirectCliUsableChannels = newValue}
  }
  var hasWifiDirectCliUsableChannels: Bool {return _storage._wifiDirectCliUsableChannels != nil}
  mutating func clearWifiDirectCliUsableChannels() {_uniqueStorage()._wifiDirectCliUsableChannels = nil}

  var wifiLanUsableChannels: Location_Nearby_Connections_WifiLanUsableChannels {
    get {return _storage._wifiLanUsableChannels ?? Location_Nearby_Connections_WifiLanUsableChannels()}
    set {_uniqueStorage()._wifiLanUsableChannels = newValue}
  }
  var hasWifiLanUsableChannels: Bool {return _storage._wifiLanUsableChannels != nil}
  mutating func clearWifiLanUsableChannels() {_uniqueStorage()._wifiLanUsableChannels = nil}

  var wifiAwareUsableChannels: Location_Nearby_Connections_WifiAwareUsableChannels {
    get {return _storage._wifiAwareUsableChannels ?? Location_Nearby_Connections_WifiAwareUsableChannels()}
    set {_uniqueStorage()._wifiAwareUsableChannels = newValue}
  }
  var hasWifiAwareUsableChannels: Bool {return _storage._wifiAwareUsableChannels != nil}
  mutating func clearWifiAwareUsableChannels() {_uniqueStorage()._wifiAwareUsableChannels = nil}

  var wifiHotspotStaUsableChannels: Location_Nearby_Connections_WifiHotspotStaUsableChannels {
    get {return _storage._wifiHotspotStaUsableChannels ?? Location_Nearby_Connections_WifiHotspotStaUsableChannels()}
    set {_uniqueStorage()._wifiHotspotStaUsableChannels = newValue}
  }
  var hasWifiHotspotStaUsableChannels: Bool {return _storage._wifiHotspotStaUsableChannels != nil}
  mutating func clearWifiHotspotStaUsableChannels() {_uniqueStorage()._wifiHotspotStaUsableChannels = nil}

  var mediumRole: Location_Nearby_Connections_MediumRole {
    get {return _storage._mediumRole ?? Location_Nearby_Connections_MediumRole()}
    set {_uniqueStorage()._mediumRole = newValue}
  }
  var hasMediumRole: Bool {return _storage._mediumRole != nil}
  mutating func clearMediumRole() {_uniqueStorage()._mediumRole = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

struct Location_Nearby_Connections_AvailableChannels {

  var channels: [Int32] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Location_Nearby_Connections_WifiDirectCliUsableChannels {

  var channels: [Int32] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Location_Nearby_Connections_WifiLanUsableChannels {

  var channels: [Int32] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Location_Nearby_Connections_WifiAwareUsableChannels {

  var channels: [Int32] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Location_Nearby_Connections_WifiHotspotStaUsableChannels {

  var channels: [Int32] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct Location_Nearby_Connections_MediumRole {

  var supportWifiDirectGroupOwner: Bool {
    get {return _supportWifiDirectGroupOwner ?? false}
    set {_supportWifiDirectGroupOwner = newValue}
  }
  var hasSupportWifiDirectGroupOwner: Bool {return self._supportWifiDirectGroupOwner != nil}
  mutating func clearSupportWifiDirectGroupOwner() {self._supportWifiDirectGroupOwner = nil}

  var supportWifiDirectGroupClient: Bool {
    get {return _supportWifiDirectGroupClient ?? false}
    set {_supportWifiDirectGroupClient = newValue}
  }
  var hasSupportWifiDirectGroupClient: Bool {return self._supportWifiDirectGroupClient != nil}
  mutating func clearSupportWifiDirectGroupClient() {self._supportWifiDirectGroupClient = nil}

  var supportWifiHotspotHost: Bool {
    get {return _supportWifiHotspotHost ?? false}
    set {_supportWifiHotspotHost = newValue}
  }
  var hasSupportWifiHotspotHost: Bool {return self._supportWifiHotspotHost != nil}
  mutating func clearSupportWifiHotspotHost() {self._supportWifiHotspotHost = nil}

  var supportWifiHotspotClient: Bool {
    get {return _supportWifiHotspotClient ?? false}
    set {_supportWifiHotspotClient = newValue}
  }
  var hasSupportWifiHotspotClient: Bool {return self._supportWifiHotspotClient != nil}
  mutating func clearSupportWifiHotspotClient() {self._supportWifiHotspotClient = nil}

  var supportWifiAwarePublisher: Bool {
    get {return _supportWifiAwarePublisher ?? false}
    set {_supportWifiAwarePublisher = newValue}
  }
  var hasSupportWifiAwarePublisher: Bool {return self._supportWifiAwarePublisher != nil}
  mutating func clearSupportWifiAwarePublisher() {self._supportWifiAwarePublisher = nil}

  var supportWifiAwareSubscriber: Bool {
    get {return _supportWifiAwareSubscriber ?? false}
    set {_supportWifiAwareSubscriber = newValue}
  }
  var hasSupportWifiAwareSubscriber: Bool {return self._supportWifiAwareSubscriber != nil}
  mutating func clearSupportWifiAwareSubscriber() {self._supportWifiAwareSubscriber = nil}

  var supportAwdlPublisher: Bool {
    get {return _supportAwdlPublisher ?? false}
    set {_supportAwdlPublisher = newValue}
  }
  var hasSupportAwdlPublisher: Bool {return self._supportAwdlPublisher != nil}
  mutating func clearSupportAwdlPublisher() {self._supportAwdlPublisher = nil}

  var supportAwdlSubscriber: Bool {
    get {return _supportAwdlSubscriber ?? false}
    set {_supportAwdlSubscriber = newValue}
  }
  var hasSupportAwdlSubscriber: Bool {return self._supportAwdlSubscriber != nil}
  mutating func clearSupportAwdlSubscriber() {self._supportAwdlSubscriber = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _supportWifiDirectGroupOwner: Bool? = nil
  fileprivate var _supportWifiDirectGroupClient: Bool? = nil
  fileprivate var _supportWifiHotspotHost: Bool? = nil
  fileprivate var _supportWifiHotspotClient: Bool? = nil
  fileprivate var _supportWifiAwarePublisher: Bool? = nil
  fileprivate var _supportWifiAwareSubscriber: Bool? = nil
  fileprivate var _supportAwdlPublisher: Bool? = nil
  fileprivate var _supportAwdlSubscriber: Bool? = nil
}

struct Location_Nearby_Connections_LocationHint {

  var location: String {
    get {return _location ?? String()}
    set {_location = newValue}
  }
  var hasLocation: Bool {return self._location != nil}
  mutating func clearLocation() {self._location = nil}

  var format: Location_Nearby_Connections_LocationStandard.Format {
    get {return _format ?? .unknown}
    set {_format = newValue}
  }
  var hasFormat: Bool {return self._format != nil}
  mutating func clearFormat() {self._format = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _location: String? = nil
  fileprivate var _format: Location_Nearby_Connections_LocationStandard.Format? = nil
}

struct Location_Nearby_Connections_LocationStandard {

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum Format: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown

    case e164Calling

    case iso31661Alpha2

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .e164Calling
      case 2: self = .iso31661Alpha2
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .e164Calling: return 1
      case .iso31661Alpha2: return 2
      }
    }

  }

  init() {}
}

#if swift(>=4.2)

extension Location_Nearby_Connections_LocationStandard.Format: CaseIterable {
}

#endif

struct Location_Nearby_Connections_OsInfo {

  var type: Location_Nearby_Connections_OsInfo.OsType {
    get {return _type ?? .unknownOsType}
    set {_type = newValue}
  }
  var hasType: Bool {return self._type != nil}
  mutating func clearType() {self._type = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum OsType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknownOsType
    case android
    case chromeOs
    case windows
    case apple

    case linux

    init() {
      self = .unknownOsType
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknownOsType
      case 1: self = .android
      case 2: self = .chromeOs
      case 3: self = .windows
      case 4: self = .apple
      case 100: self = .linux
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknownOsType: return 0
      case .android: return 1
      case .chromeOs: return 2
      case .windows: return 3
      case .apple: return 4
      case .linux: return 100
      }
    }

  }

  init() {}

  fileprivate var _type: Location_Nearby_Connections_OsInfo.OsType? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_OsInfo.OsType: CaseIterable {
}

#endif

struct Location_Nearby_Connections_ConnectionsDevice {

  var endpointID: String {
    get {return _endpointID ?? String()}
    set {_endpointID = newValue}
  }
  var hasEndpointID: Bool {return self._endpointID != nil}
  mutating func clearEndpointID() {self._endpointID = nil}

  var endpointType: Location_Nearby_Connections_EndpointType {
    get {return _endpointType ?? .unknownEndpoint}
    set {_endpointType = newValue}
  }
  var hasEndpointType: Bool {return self._endpointType != nil}
  mutating func clearEndpointType() {self._endpointType = nil}

  var connectivityInfoList: Data {
    get {return _connectivityInfoList ?? Data()}
    set {_connectivityInfoList = newValue}
  }
  var hasConnectivityInfoList: Bool {return self._connectivityInfoList != nil}
  mutating func clearConnectivityInfoList() {self._connectivityInfoList = nil}

  var endpointInfo: Data {
    get {return _endpointInfo ?? Data()}
    set {_endpointInfo = newValue}
  }
  var hasEndpointInfo: Bool {return self._endpointInfo != nil}
  mutating func clearEndpointInfo() {self._endpointInfo = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _endpointID: String? = nil
  fileprivate var _endpointType: Location_Nearby_Connections_EndpointType? = nil
  fileprivate var _connectivityInfoList: Data? = nil
  fileprivate var _endpointInfo: Data? = nil
}

struct Location_Nearby_Connections_PresenceDevice {

  var endpointID: String {
    get {return _endpointID ?? String()}
    set {_endpointID = newValue}
  }
  var hasEndpointID: Bool {return self._endpointID != nil}
  mutating func clearEndpointID() {self._endpointID = nil}

  var endpointType: Location_Nearby_Connections_EndpointType {
    get {return _endpointType ?? .unknownEndpoint}
    set {_endpointType = newValue}
  }
  var hasEndpointType: Bool {return self._endpointType != nil}
  mutating func clearEndpointType() {self._endpointType = nil}

  var connectivityInfoList: Data {
    get {return _connectivityInfoList ?? Data()}
    set {_connectivityInfoList = newValue}
  }
  var hasConnectivityInfoList: Bool {return self._connectivityInfoList != nil}
  mutating func clearConnectivityInfoList() {self._connectivityInfoList = nil}

  var deviceID: Int64 {
    get {return _deviceID ?? 0}
    set {_deviceID = newValue}
  }
  var hasDeviceID: Bool {return self._deviceID != nil}
  mutating func clearDeviceID() {self._deviceID = nil}

  var deviceName: String {
    get {return _deviceName ?? String()}
    set {_deviceName = newValue}
  }
  var hasDeviceName: Bool {return self._deviceName != nil}
  mutating func clearDeviceName() {self._deviceName = nil}

  var deviceType: Location_Nearby_Connections_PresenceDevice.DeviceType {
    get {return _deviceType ?? .unknown}
    set {_deviceType = newValue}
  }
  var hasDeviceType: Bool {return self._deviceType != nil}
  mutating func clearDeviceType() {self._deviceType = nil}

  var deviceImageURL: String {
    get {return _deviceImageURL ?? String()}
    set {_deviceImageURL = newValue}
  }
  var hasDeviceImageURL: Bool {return self._deviceImageURL != nil}
  mutating func clearDeviceImageURL() {self._deviceImageURL = nil}

  var discoveryMedium: [Location_Nearby_Connections_ConnectionRequestFrame.Medium] = []

  var actions: [Int32] = []

  var identityType: [Int64] = []

  var unknownFields = SwiftProtobuf.UnknownStorage()

  enum DeviceType: SwiftProtobuf.Enum {
    typealias RawValue = Int
    case unknown
    case phone
    case tablet
    case display
    case laptop
    case tv
    case watch

    init() {
      self = .unknown
    }

    init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .phone
      case 2: self = .tablet
      case 3: self = .display
      case 4: self = .laptop
      case 5: self = .tv
      case 6: self = .watch
      default: return nil
      }
    }

    var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .phone: return 1
      case .tablet: return 2
      case .display: return 3
      case .laptop: return 4
      case .tv: return 5
      case .watch: return 6
      }
    }

  }

  init() {}

  fileprivate var _endpointID: String? = nil
  fileprivate var _endpointType: Location_Nearby_Connections_EndpointType? = nil
  fileprivate var _connectivityInfoList: Data? = nil
  fileprivate var _deviceID: Int64? = nil
  fileprivate var _deviceName: String? = nil
  fileprivate var _deviceType: Location_Nearby_Connections_PresenceDevice.DeviceType? = nil
  fileprivate var _deviceImageURL: String? = nil
}

#if swift(>=4.2)

extension Location_Nearby_Connections_PresenceDevice.DeviceType: CaseIterable {
}

#endif

#if swift(>=5.5) && canImport(_Concurrency)
extension Location_Nearby_Connections_EndpointType: @unchecked Sendable {}
extension Location_Nearby_Connections_OfflineFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_OfflineFrame.Version: @unchecked Sendable {}
extension Location_Nearby_Connections_V1Frame: @unchecked Sendable {}
extension Location_Nearby_Connections_V1Frame.FrameType: @unchecked Sendable {}
extension Location_Nearby_Connections_ConnectionRequestFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_ConnectionRequestFrame.OneOf_Device: @unchecked Sendable {}
extension Location_Nearby_Connections_ConnectionRequestFrame.Medium: @unchecked Sendable {}
extension Location_Nearby_Connections_ConnectionRequestFrame.ConnectionMode: @unchecked Sendable {}
extension Location_Nearby_Connections_ConnectionResponseFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_ConnectionResponseFrame.ResponseStatus: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame.PacketType: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader.PayloadType: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk.Flags: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame.ControlMessage: @unchecked Sendable {}
extension Location_Nearby_Connections_PayloadTransferFrame.ControlMessage.EventType: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.EventType: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroduction: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroductionAck: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeRetryFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_BandwidthUpgradeRetryFrame.Medium: @unchecked Sendable {}
extension Location_Nearby_Connections_KeepAliveFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_DisconnectionFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_PairedKeyEncryptionFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_AuthenticationMessageFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_AuthenticationResultFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_AutoResumeFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_AutoResumeFrame.EventType: @unchecked Sendable {}
extension Location_Nearby_Connections_AutoReconnectFrame: @unchecked Sendable {}
extension Location_Nearby_Connections_AutoReconnectFrame.EventType: @unchecked Sendable {}
extension Location_Nearby_Connections_MediumMetadata: @unchecked Sendable {}
extension Location_Nearby_Connections_AvailableChannels: @unchecked Sendable {}
extension Location_Nearby_Connections_WifiDirectCliUsableChannels: @unchecked Sendable {}
extension Location_Nearby_Connections_WifiLanUsableChannels: @unchecked Sendable {}
extension Location_Nearby_Connections_WifiAwareUsableChannels: @unchecked Sendable {}
extension Location_Nearby_Connections_WifiHotspotStaUsableChannels: @unchecked Sendable {}
extension Location_Nearby_Connections_MediumRole: @unchecked Sendable {}
extension Location_Nearby_Connections_LocationHint: @unchecked Sendable {}
extension Location_Nearby_Connections_LocationStandard: @unchecked Sendable {}
extension Location_Nearby_Connections_LocationStandard.Format: @unchecked Sendable {}
extension Location_Nearby_Connections_OsInfo: @unchecked Sendable {}
extension Location_Nearby_Connections_OsInfo.OsType: @unchecked Sendable {}
extension Location_Nearby_Connections_ConnectionsDevice: @unchecked Sendable {}
extension Location_Nearby_Connections_PresenceDevice: @unchecked Sendable {}
extension Location_Nearby_Connections_PresenceDevice.DeviceType: @unchecked Sendable {}
#endif

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "location.nearby.connections"

extension Location_Nearby_Connections_EndpointType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_ENDPOINT"),
    1: .same(proto: "CONNECTIONS_ENDPOINT"),
    2: .same(proto: "PRESENCE_ENDPOINT"),
  ]
}

extension Location_Nearby_Connections_OfflineFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".OfflineFrame"
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

  static func ==(lhs: Location_Nearby_Connections_OfflineFrame, rhs: Location_Nearby_Connections_OfflineFrame) -> Bool {
    if lhs._version != rhs._version {return false}
    if lhs._v1 != rhs._v1 {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_OfflineFrame.Version: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_VERSION"),
    1: .same(proto: "V1"),
  ]
}

extension Location_Nearby_Connections_V1Frame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".V1Frame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "type"),
    2: .standard(proto: "connection_request"),
    3: .standard(proto: "connection_response"),
    4: .standard(proto: "payload_transfer"),
    5: .standard(proto: "bandwidth_upgrade_negotiation"),
    6: .standard(proto: "keep_alive"),
    7: .same(proto: "disconnection"),
    8: .standard(proto: "paired_key_encryption"),
    9: .standard(proto: "authentication_message"),
    10: .standard(proto: "authentication_result"),
    11: .standard(proto: "auto_resume"),
    12: .standard(proto: "auto_reconnect"),
    13: .standard(proto: "bandwidth_upgrade_retry"),
  ]

  fileprivate class _StorageClass {
    var _type: Location_Nearby_Connections_V1Frame.FrameType? = nil
    var _connectionRequest: Location_Nearby_Connections_ConnectionRequestFrame? = nil
    var _connectionResponse: Location_Nearby_Connections_ConnectionResponseFrame? = nil
    var _payloadTransfer: Location_Nearby_Connections_PayloadTransferFrame? = nil
    var _bandwidthUpgradeNegotiation: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame? = nil
    var _keepAlive: Location_Nearby_Connections_KeepAliveFrame? = nil
    var _disconnection: Location_Nearby_Connections_DisconnectionFrame? = nil
    var _pairedKeyEncryption: Location_Nearby_Connections_PairedKeyEncryptionFrame? = nil
    var _authenticationMessage: Location_Nearby_Connections_AuthenticationMessageFrame? = nil
    var _authenticationResult: Location_Nearby_Connections_AuthenticationResultFrame? = nil
    var _autoResume: Location_Nearby_Connections_AutoResumeFrame? = nil
    var _autoReconnect: Location_Nearby_Connections_AutoReconnectFrame? = nil
    var _bandwidthUpgradeRetry: Location_Nearby_Connections_BandwidthUpgradeRetryFrame? = nil

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _type = source._type
      _connectionRequest = source._connectionRequest
      _connectionResponse = source._connectionResponse
      _payloadTransfer = source._payloadTransfer
      _bandwidthUpgradeNegotiation = source._bandwidthUpgradeNegotiation
      _keepAlive = source._keepAlive
      _disconnection = source._disconnection
      _pairedKeyEncryption = source._pairedKeyEncryption
      _authenticationMessage = source._authenticationMessage
      _authenticationResult = source._authenticationResult
      _autoResume = source._autoResume
      _autoReconnect = source._autoReconnect
      _bandwidthUpgradeRetry = source._bandwidthUpgradeRetry
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
        case 2: try { try decoder.decodeSingularMessageField(value: &_storage._connectionRequest) }()
        case 3: try { try decoder.decodeSingularMessageField(value: &_storage._connectionResponse) }()
        case 4: try { try decoder.decodeSingularMessageField(value: &_storage._payloadTransfer) }()
        case 5: try { try decoder.decodeSingularMessageField(value: &_storage._bandwidthUpgradeNegotiation) }()
        case 6: try { try decoder.decodeSingularMessageField(value: &_storage._keepAlive) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._disconnection) }()
        case 8: try { try decoder.decodeSingularMessageField(value: &_storage._pairedKeyEncryption) }()
        case 9: try { try decoder.decodeSingularMessageField(value: &_storage._authenticationMessage) }()
        case 10: try { try decoder.decodeSingularMessageField(value: &_storage._authenticationResult) }()
        case 11: try { try decoder.decodeSingularMessageField(value: &_storage._autoResume) }()
        case 12: try { try decoder.decodeSingularMessageField(value: &_storage._autoReconnect) }()
        case 13: try { try decoder.decodeSingularMessageField(value: &_storage._bandwidthUpgradeRetry) }()
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
      try { if let v = _storage._connectionRequest {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
      } }()
      try { if let v = _storage._connectionResponse {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
      } }()
      try { if let v = _storage._payloadTransfer {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
      } }()
      try { if let v = _storage._bandwidthUpgradeNegotiation {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
      } }()
      try { if let v = _storage._keepAlive {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
      } }()
      try { if let v = _storage._disconnection {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._pairedKeyEncryption {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
      } }()
      try { if let v = _storage._authenticationMessage {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 9)
      } }()
      try { if let v = _storage._authenticationResult {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 10)
      } }()
      try { if let v = _storage._autoResume {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 11)
      } }()
      try { if let v = _storage._autoReconnect {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 12)
      } }()
      try { if let v = _storage._bandwidthUpgradeRetry {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 13)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_V1Frame, rhs: Location_Nearby_Connections_V1Frame) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._type != rhs_storage._type {return false}
        if _storage._connectionRequest != rhs_storage._connectionRequest {return false}
        if _storage._connectionResponse != rhs_storage._connectionResponse {return false}
        if _storage._payloadTransfer != rhs_storage._payloadTransfer {return false}
        if _storage._bandwidthUpgradeNegotiation != rhs_storage._bandwidthUpgradeNegotiation {return false}
        if _storage._keepAlive != rhs_storage._keepAlive {return false}
        if _storage._disconnection != rhs_storage._disconnection {return false}
        if _storage._pairedKeyEncryption != rhs_storage._pairedKeyEncryption {return false}
        if _storage._authenticationMessage != rhs_storage._authenticationMessage {return false}
        if _storage._authenticationResult != rhs_storage._authenticationResult {return false}
        if _storage._autoResume != rhs_storage._autoResume {return false}
        if _storage._autoReconnect != rhs_storage._autoReconnect {return false}
        if _storage._bandwidthUpgradeRetry != rhs_storage._bandwidthUpgradeRetry {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_V1Frame.FrameType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_FRAME_TYPE"),
    1: .same(proto: "CONNECTION_REQUEST"),
    2: .same(proto: "CONNECTION_RESPONSE"),
    3: .same(proto: "PAYLOAD_TRANSFER"),
    4: .same(proto: "BANDWIDTH_UPGRADE_NEGOTIATION"),
    5: .same(proto: "KEEP_ALIVE"),
    6: .same(proto: "DISCONNECTION"),
    7: .same(proto: "PAIRED_KEY_ENCRYPTION"),
    8: .same(proto: "AUTHENTICATION_MESSAGE"),
    9: .same(proto: "AUTHENTICATION_RESULT"),
    10: .same(proto: "AUTO_RESUME"),
    11: .same(proto: "AUTO_RECONNECT"),
    12: .same(proto: "BANDWIDTH_UPGRADE_RETRY"),
  ]
}

extension Location_Nearby_Connections_ConnectionRequestFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ConnectionRequestFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "endpoint_id"),
    2: .standard(proto: "endpoint_name"),
    3: .standard(proto: "handshake_data"),
    4: .same(proto: "nonce"),
    5: .same(proto: "mediums"),
    6: .standard(proto: "endpoint_info"),
    7: .standard(proto: "medium_metadata"),
    8: .standard(proto: "keep_alive_interval_millis"),
    9: .standard(proto: "keep_alive_timeout_millis"),
    10: .standard(proto: "device_type"),
    11: .standard(proto: "device_info"),
    12: .standard(proto: "connections_device"),
    13: .standard(proto: "presence_device"),
    14: .standard(proto: "connection_mode"),
    15: .standard(proto: "location_hint"),
  ]

  fileprivate class _StorageClass {
    var _endpointID: String? = nil
    var _endpointName: String? = nil
    var _handshakeData: Data? = nil
    var _nonce: Int32? = nil
    var _mediums: [Location_Nearby_Connections_ConnectionRequestFrame.Medium] = []
    var _endpointInfo: Data? = nil
    var _mediumMetadata: Location_Nearby_Connections_MediumMetadata? = nil
    var _keepAliveIntervalMillis: Int32? = nil
    var _keepAliveTimeoutMillis: Int32? = nil
    var _deviceType: Int32? = nil
    var _deviceInfo: Data? = nil
    var _device: Location_Nearby_Connections_ConnectionRequestFrame.OneOf_Device?
    var _connectionMode: Location_Nearby_Connections_ConnectionRequestFrame.ConnectionMode? = nil
    var _locationHint: Location_Nearby_Connections_LocationHint? = nil

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _endpointID = source._endpointID
      _endpointName = source._endpointName
      _handshakeData = source._handshakeData
      _nonce = source._nonce
      _mediums = source._mediums
      _endpointInfo = source._endpointInfo
      _mediumMetadata = source._mediumMetadata
      _keepAliveIntervalMillis = source._keepAliveIntervalMillis
      _keepAliveTimeoutMillis = source._keepAliveTimeoutMillis
      _deviceType = source._deviceType
      _deviceInfo = source._deviceInfo
      _device = source._device
      _connectionMode = source._connectionMode
      _locationHint = source._locationHint
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
        case 1: try { try decoder.decodeSingularStringField(value: &_storage._endpointID) }()
        case 2: try { try decoder.decodeSingularStringField(value: &_storage._endpointName) }()
        case 3: try { try decoder.decodeSingularBytesField(value: &_storage._handshakeData) }()
        case 4: try { try decoder.decodeSingularInt32Field(value: &_storage._nonce) }()
        case 5: try { try decoder.decodeRepeatedEnumField(value: &_storage._mediums) }()
        case 6: try { try decoder.decodeSingularBytesField(value: &_storage._endpointInfo) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._mediumMetadata) }()
        case 8: try { try decoder.decodeSingularInt32Field(value: &_storage._keepAliveIntervalMillis) }()
        case 9: try { try decoder.decodeSingularInt32Field(value: &_storage._keepAliveTimeoutMillis) }()
        case 10: try { try decoder.decodeSingularInt32Field(value: &_storage._deviceType) }()
        case 11: try { try decoder.decodeSingularBytesField(value: &_storage._deviceInfo) }()
        case 12: try {
          var v: Location_Nearby_Connections_ConnectionsDevice?
          var hadOneofValue = false
          if let current = _storage._device {
            hadOneofValue = true
            if case .connectionsDevice(let m) = current {v = m}
          }
          try decoder.decodeSingularMessageField(value: &v)
          if let v = v {
            if hadOneofValue {try decoder.handleConflictingOneOf()}
            _storage._device = .connectionsDevice(v)
          }
        }()
        case 13: try {
          var v: Location_Nearby_Connections_PresenceDevice?
          var hadOneofValue = false
          if let current = _storage._device {
            hadOneofValue = true
            if case .presenceDevice(let m) = current {v = m}
          }
          try decoder.decodeSingularMessageField(value: &v)
          if let v = v {
            if hadOneofValue {try decoder.handleConflictingOneOf()}
            _storage._device = .presenceDevice(v)
          }
        }()
        case 14: try { try decoder.decodeSingularEnumField(value: &_storage._connectionMode) }()
        case 15: try { try decoder.decodeSingularMessageField(value: &_storage._locationHint) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      try { if let v = _storage._endpointID {
        try visitor.visitSingularStringField(value: v, fieldNumber: 1)
      } }()
      try { if let v = _storage._endpointName {
        try visitor.visitSingularStringField(value: v, fieldNumber: 2)
      } }()
      try { if let v = _storage._handshakeData {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
      } }()
      try { if let v = _storage._nonce {
        try visitor.visitSingularInt32Field(value: v, fieldNumber: 4)
      } }()
      if !_storage._mediums.isEmpty {
        try visitor.visitRepeatedEnumField(value: _storage._mediums, fieldNumber: 5)
      }
      try { if let v = _storage._endpointInfo {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 6)
      } }()
      try { if let v = _storage._mediumMetadata {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._keepAliveIntervalMillis {
        try visitor.visitSingularInt32Field(value: v, fieldNumber: 8)
      } }()
      try { if let v = _storage._keepAliveTimeoutMillis {
        try visitor.visitSingularInt32Field(value: v, fieldNumber: 9)
      } }()
      try { if let v = _storage._deviceType {
        try visitor.visitSingularInt32Field(value: v, fieldNumber: 10)
      } }()
      try { if let v = _storage._deviceInfo {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 11)
      } }()
      switch _storage._device {
      case .connectionsDevice?: try {
        guard case .connectionsDevice(let v)? = _storage._device else { preconditionFailure() }
        try visitor.visitSingularMessageField(value: v, fieldNumber: 12)
      }()
      case .presenceDevice?: try {
        guard case .presenceDevice(let v)? = _storage._device else { preconditionFailure() }
        try visitor.visitSingularMessageField(value: v, fieldNumber: 13)
      }()
      case nil: break
      }
      try { if let v = _storage._connectionMode {
        try visitor.visitSingularEnumField(value: v, fieldNumber: 14)
      } }()
      try { if let v = _storage._locationHint {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 15)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_ConnectionRequestFrame, rhs: Location_Nearby_Connections_ConnectionRequestFrame) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._endpointID != rhs_storage._endpointID {return false}
        if _storage._endpointName != rhs_storage._endpointName {return false}
        if _storage._handshakeData != rhs_storage._handshakeData {return false}
        if _storage._nonce != rhs_storage._nonce {return false}
        if _storage._mediums != rhs_storage._mediums {return false}
        if _storage._endpointInfo != rhs_storage._endpointInfo {return false}
        if _storage._mediumMetadata != rhs_storage._mediumMetadata {return false}
        if _storage._keepAliveIntervalMillis != rhs_storage._keepAliveIntervalMillis {return false}
        if _storage._keepAliveTimeoutMillis != rhs_storage._keepAliveTimeoutMillis {return false}
        if _storage._deviceType != rhs_storage._deviceType {return false}
        if _storage._deviceInfo != rhs_storage._deviceInfo {return false}
        if _storage._device != rhs_storage._device {return false}
        if _storage._connectionMode != rhs_storage._connectionMode {return false}
        if _storage._locationHint != rhs_storage._locationHint {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_ConnectionRequestFrame.Medium: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_MEDIUM"),
    1: .same(proto: "MDNS"),
    2: .same(proto: "BLUETOOTH"),
    3: .same(proto: "WIFI_HOTSPOT"),
    4: .same(proto: "BLE"),
    5: .same(proto: "WIFI_LAN"),
    6: .same(proto: "WIFI_AWARE"),
    7: .same(proto: "NFC"),
    8: .same(proto: "WIFI_DIRECT"),
    9: .same(proto: "WEB_RTC"),
    10: .same(proto: "BLE_L2CAP"),
    11: .same(proto: "USB"),
    12: .same(proto: "WEB_RTC_NON_CELLULAR"),
    13: .same(proto: "AWDL"),
  ]
}

extension Location_Nearby_Connections_ConnectionRequestFrame.ConnectionMode: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "LEGACY"),
    1: .same(proto: "INSTANT"),
  ]
}

extension Location_Nearby_Connections_ConnectionResponseFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ConnectionResponseFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "status"),
    2: .standard(proto: "handshake_data"),
    3: .same(proto: "response"),
    4: .standard(proto: "os_info"),
    5: .standard(proto: "multiplex_socket_bitmask"),
    6: .standard(proto: "nearby_connections_version"),
    7: .standard(proto: "safe_to_disconnect_version"),
    8: .standard(proto: "location_hint"),
    9: .standard(proto: "keep_alive_timeout_millis"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt32Field(value: &self._status) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._handshakeData) }()
      case 3: try { try decoder.decodeSingularEnumField(value: &self._response) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._osInfo) }()
      case 5: try { try decoder.decodeSingularInt32Field(value: &self._multiplexSocketBitmask) }()
      case 6: try { try decoder.decodeSingularInt32Field(value: &self._nearbyConnectionsVersion) }()
      case 7: try { try decoder.decodeSingularInt32Field(value: &self._safeToDisconnectVersion) }()
      case 8: try { try decoder.decodeSingularMessageField(value: &self._locationHint) }()
      case 9: try { try decoder.decodeSingularInt32Field(value: &self._keepAliveTimeoutMillis) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._status {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._handshakeData {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._response {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._osInfo {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._multiplexSocketBitmask {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._nearbyConnectionsVersion {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._safeToDisconnectVersion {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 7)
    } }()
    try { if let v = self._locationHint {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
    } }()
    try { if let v = self._keepAliveTimeoutMillis {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 9)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_ConnectionResponseFrame, rhs: Location_Nearby_Connections_ConnectionResponseFrame) -> Bool {
    if lhs._status != rhs._status {return false}
    if lhs._handshakeData != rhs._handshakeData {return false}
    if lhs._response != rhs._response {return false}
    if lhs._osInfo != rhs._osInfo {return false}
    if lhs._multiplexSocketBitmask != rhs._multiplexSocketBitmask {return false}
    if lhs._nearbyConnectionsVersion != rhs._nearbyConnectionsVersion {return false}
    if lhs._safeToDisconnectVersion != rhs._safeToDisconnectVersion {return false}
    if lhs._locationHint != rhs._locationHint {return false}
    if lhs._keepAliveTimeoutMillis != rhs._keepAliveTimeoutMillis {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_ConnectionResponseFrame.ResponseStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_RESPONSE_STATUS"),
    1: .same(proto: "ACCEPT"),
    2: .same(proto: "REJECT"),
  ]
}

extension Location_Nearby_Connections_PayloadTransferFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PayloadTransferFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "packet_type"),
    2: .standard(proto: "payload_header"),
    3: .standard(proto: "payload_chunk"),
    4: .standard(proto: "control_message"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._packetType) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._payloadHeader) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._payloadChunk) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._controlMessage) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._packetType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._payloadHeader {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._payloadChunk {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._controlMessage {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_PayloadTransferFrame, rhs: Location_Nearby_Connections_PayloadTransferFrame) -> Bool {
    if lhs._packetType != rhs._packetType {return false}
    if lhs._payloadHeader != rhs._payloadHeader {return false}
    if lhs._payloadChunk != rhs._payloadChunk {return false}
    if lhs._controlMessage != rhs._controlMessage {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_PayloadTransferFrame.PacketType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_PACKET_TYPE"),
    1: .same(proto: "DATA"),
    2: .same(proto: "CONTROL"),
    3: .same(proto: "PAYLOAD_ACK"),
  ]
}

extension Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_PayloadTransferFrame.protoMessageName + ".PayloadHeader"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "id"),
    2: .same(proto: "type"),
    3: .standard(proto: "total_size"),
    4: .standard(proto: "is_sensitive"),
    5: .standard(proto: "file_name"),
    6: .standard(proto: "parent_folder"),
    7: .standard(proto: "last_modified_timestamp_millis"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt64Field(value: &self._id) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._type) }()
      case 3: try { try decoder.decodeSingularInt64Field(value: &self._totalSize) }()
      case 4: try { try decoder.decodeSingularBoolField(value: &self._isSensitive) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self._fileName) }()
      case 6: try { try decoder.decodeSingularStringField(value: &self._parentFolder) }()
      case 7: try { try decoder.decodeSingularInt64Field(value: &self._lastModifiedTimestampMillis) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._id {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._type {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._totalSize {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._isSensitive {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._fileName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._parentFolder {
      try visitor.visitSingularStringField(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._lastModifiedTimestampMillis {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 7)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader, rhs: Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader) -> Bool {
    if lhs._id != rhs._id {return false}
    if lhs._type != rhs._type {return false}
    if lhs._totalSize != rhs._totalSize {return false}
    if lhs._isSensitive != rhs._isSensitive {return false}
    if lhs._fileName != rhs._fileName {return false}
    if lhs._parentFolder != rhs._parentFolder {return false}
    if lhs._lastModifiedTimestampMillis != rhs._lastModifiedTimestampMillis {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader.PayloadType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_PAYLOAD_TYPE"),
    1: .same(proto: "BYTES"),
    2: .same(proto: "FILE"),
    3: .same(proto: "STREAM"),
  ]
}

extension Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_PayloadTransferFrame.protoMessageName + ".PayloadChunk"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "flags"),
    2: .same(proto: "offset"),
    3: .same(proto: "body"),
    4: .same(proto: "index"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt32Field(value: &self._flags) }()
      case 2: try { try decoder.decodeSingularInt64Field(value: &self._offset) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._body) }()
      case 4: try { try decoder.decodeSingularInt32Field(value: &self._index) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._flags {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._offset {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._body {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._index {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk, rhs: Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk) -> Bool {
    if lhs._flags != rhs._flags {return false}
    if lhs._offset != rhs._offset {return false}
    if lhs._body != rhs._body {return false}
    if lhs._index != rhs._index {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_PayloadTransferFrame.PayloadChunk.Flags: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "LAST_CHUNK"),
  ]
}

extension Location_Nearby_Connections_PayloadTransferFrame.ControlMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_PayloadTransferFrame.protoMessageName + ".ControlMessage"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "event"),
    2: .same(proto: "offset"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._event) }()
      case 2: try { try decoder.decodeSingularInt64Field(value: &self._offset) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._event {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._offset {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_PayloadTransferFrame.ControlMessage, rhs: Location_Nearby_Connections_PayloadTransferFrame.ControlMessage) -> Bool {
    if lhs._event != rhs._event {return false}
    if lhs._offset != rhs._offset {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_PayloadTransferFrame.ControlMessage.EventType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_EVENT_TYPE"),
    1: .same(proto: "PAYLOAD_ERROR"),
    2: .same(proto: "PAYLOAD_CANCELED"),
    3: .same(proto: "PAYLOAD_RECEIVED_ACK"),
  ]
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".BandwidthUpgradeNegotiationFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "event_type"),
    2: .standard(proto: "upgrade_path_info"),
    3: .standard(proto: "client_introduction"),
    4: .standard(proto: "client_introduction_ack"),
    5: .standard(proto: "safe_to_close_prior_channel"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._eventType) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._upgradePathInfo) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._clientIntroduction) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._clientIntroductionAck) }()
      case 5: try { try decoder.decodeSingularMessageField(value: &self._safeToClosePriorChannel) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._eventType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._upgradePathInfo {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._clientIntroduction {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._clientIntroductionAck {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._safeToClosePriorChannel {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame) -> Bool {
    if lhs._eventType != rhs._eventType {return false}
    if lhs._upgradePathInfo != rhs._upgradePathInfo {return false}
    if lhs._clientIntroduction != rhs._clientIntroduction {return false}
    if lhs._clientIntroductionAck != rhs._clientIntroductionAck {return false}
    if lhs._safeToClosePriorChannel != rhs._safeToClosePriorChannel {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.EventType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_EVENT_TYPE"),
    1: .same(proto: "UPGRADE_PATH_AVAILABLE"),
    2: .same(proto: "LAST_WRITE_TO_PRIOR_CHANNEL"),
    3: .same(proto: "SAFE_TO_CLOSE_PRIOR_CHANNEL"),
    4: .same(proto: "CLIENT_INTRODUCTION"),
    5: .same(proto: "UPGRADE_FAILURE"),
    6: .same(proto: "CLIENT_INTRODUCTION_ACK"),
    7: .same(proto: "UPGRADE_PATH_REQUEST"),
  ]
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.protoMessageName + ".UpgradePathInfo"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "medium"),
    2: .standard(proto: "wifi_hotspot_credentials"),
    3: .standard(proto: "wifi_lan_socket"),
    4: .standard(proto: "bluetooth_credentials"),
    5: .standard(proto: "wifi_aware_credentials"),
    6: .standard(proto: "wifi_direct_credentials"),
    8: .standard(proto: "web_rtc_credentials"),
    11: .standard(proto: "awdl_credentials"),
    7: .standard(proto: "supports_disabling_encryption"),
    9: .standard(proto: "supports_client_introduction_ack"),
    10: .standard(proto: "upgrade_path_request"),
  ]

  fileprivate class _StorageClass {
    var _medium: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium? = nil
    var _wifiHotspotCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials? = nil
    var _wifiLanSocket: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket? = nil
    var _bluetoothCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials? = nil
    var _wifiAwareCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials? = nil
    var _wifiDirectCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials? = nil
    var _webRtcCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials? = nil
    var _awdlCredentials: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials? = nil
    var _supportsDisablingEncryption: Bool? = nil
    var _supportsClientIntroductionAck: Bool? = nil
    var _upgradePathRequest: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest? = nil

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _medium = source._medium
      _wifiHotspotCredentials = source._wifiHotspotCredentials
      _wifiLanSocket = source._wifiLanSocket
      _bluetoothCredentials = source._bluetoothCredentials
      _wifiAwareCredentials = source._wifiAwareCredentials
      _wifiDirectCredentials = source._wifiDirectCredentials
      _webRtcCredentials = source._webRtcCredentials
      _awdlCredentials = source._awdlCredentials
      _supportsDisablingEncryption = source._supportsDisablingEncryption
      _supportsClientIntroductionAck = source._supportsClientIntroductionAck
      _upgradePathRequest = source._upgradePathRequest
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
        case 1: try { try decoder.decodeSingularEnumField(value: &_storage._medium) }()
        case 2: try { try decoder.decodeSingularMessageField(value: &_storage._wifiHotspotCredentials) }()
        case 3: try { try decoder.decodeSingularMessageField(value: &_storage._wifiLanSocket) }()
        case 4: try { try decoder.decodeSingularMessageField(value: &_storage._bluetoothCredentials) }()
        case 5: try { try decoder.decodeSingularMessageField(value: &_storage._wifiAwareCredentials) }()
        case 6: try { try decoder.decodeSingularMessageField(value: &_storage._wifiDirectCredentials) }()
        case 7: try { try decoder.decodeSingularBoolField(value: &_storage._supportsDisablingEncryption) }()
        case 8: try { try decoder.decodeSingularMessageField(value: &_storage._webRtcCredentials) }()
        case 9: try { try decoder.decodeSingularBoolField(value: &_storage._supportsClientIntroductionAck) }()
        case 10: try { try decoder.decodeSingularMessageField(value: &_storage._upgradePathRequest) }()
        case 11: try { try decoder.decodeSingularMessageField(value: &_storage._awdlCredentials) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      try { if let v = _storage._medium {
        try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
      } }()
      try { if let v = _storage._wifiHotspotCredentials {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
      } }()
      try { if let v = _storage._wifiLanSocket {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
      } }()
      try { if let v = _storage._bluetoothCredentials {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
      } }()
      try { if let v = _storage._wifiAwareCredentials {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 5)
      } }()
      try { if let v = _storage._wifiDirectCredentials {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
      } }()
      try { if let v = _storage._supportsDisablingEncryption {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._webRtcCredentials {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
      } }()
      try { if let v = _storage._supportsClientIntroductionAck {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 9)
      } }()
      try { if let v = _storage._upgradePathRequest {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 10)
      } }()
      try { if let v = _storage._awdlCredentials {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 11)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._medium != rhs_storage._medium {return false}
        if _storage._wifiHotspotCredentials != rhs_storage._wifiHotspotCredentials {return false}
        if _storage._wifiLanSocket != rhs_storage._wifiLanSocket {return false}
        if _storage._bluetoothCredentials != rhs_storage._bluetoothCredentials {return false}
        if _storage._wifiAwareCredentials != rhs_storage._wifiAwareCredentials {return false}
        if _storage._wifiDirectCredentials != rhs_storage._wifiDirectCredentials {return false}
        if _storage._webRtcCredentials != rhs_storage._webRtcCredentials {return false}
        if _storage._awdlCredentials != rhs_storage._awdlCredentials {return false}
        if _storage._supportsDisablingEncryption != rhs_storage._supportsDisablingEncryption {return false}
        if _storage._supportsClientIntroductionAck != rhs_storage._supportsClientIntroductionAck {return false}
        if _storage._upgradePathRequest != rhs_storage._upgradePathRequest {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_MEDIUM"),
    1: .same(proto: "MDNS"),
    2: .same(proto: "BLUETOOTH"),
    3: .same(proto: "WIFI_HOTSPOT"),
    4: .same(proto: "BLE"),
    5: .same(proto: "WIFI_LAN"),
    6: .same(proto: "WIFI_AWARE"),
    7: .same(proto: "NFC"),
    8: .same(proto: "WIFI_DIRECT"),
    9: .same(proto: "WEB_RTC"),
    11: .same(proto: "USB"),
    12: .same(proto: "WEB_RTC_NON_CELLULAR"),
    13: .same(proto: "AWDL"),
  ]
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".WifiHotspotCredentials"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "ssid"),
    2: .same(proto: "password"),
    3: .same(proto: "port"),
    4: .same(proto: "gateway"),
    5: .same(proto: "frequency"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._ssid) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self._password) }()
      case 3: try { try decoder.decodeSingularInt32Field(value: &self._port) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self._gateway) }()
      case 5: try { try decoder.decodeSingularInt32Field(value: &self._frequency) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._ssid {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._password {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._port {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._gateway {
      try visitor.visitSingularStringField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._frequency {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 5)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials) -> Bool {
    if lhs._ssid != rhs._ssid {return false}
    if lhs._password != rhs._password {return false}
    if lhs._port != rhs._port {return false}
    if lhs._gateway != rhs._gateway {return false}
    if lhs._frequency != rhs._frequency {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".WifiLanSocket"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "ip_address"),
    2: .standard(proto: "wifi_port"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._ipAddress) }()
      case 2: try { try decoder.decodeSingularInt32Field(value: &self._wifiPort) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._ipAddress {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._wifiPort {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket) -> Bool {
    if lhs._ipAddress != rhs._ipAddress {return false}
    if lhs._wifiPort != rhs._wifiPort {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".BluetoothCredentials"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "service_name"),
    2: .standard(proto: "mac_address"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._serviceName) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self._macAddress) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._serviceName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._macAddress {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials) -> Bool {
    if lhs._serviceName != rhs._serviceName {return false}
    if lhs._macAddress != rhs._macAddress {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".WifiAwareCredentials"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "service_id"),
    2: .standard(proto: "service_info"),
    3: .same(proto: "password"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._serviceID) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self._serviceInfo) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self._password) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._serviceID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._serviceInfo {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._password {
      try visitor.visitSingularStringField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials) -> Bool {
    if lhs._serviceID != rhs._serviceID {return false}
    if lhs._serviceInfo != rhs._serviceInfo {return false}
    if lhs._password != rhs._password {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".WifiDirectCredentials"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "ssid"),
    2: .same(proto: "password"),
    3: .same(proto: "port"),
    4: .same(proto: "frequency"),
    5: .same(proto: "gateway"),
    6: .standard(proto: "ip_v6_address"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._ssid) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self._password) }()
      case 3: try { try decoder.decodeSingularInt32Field(value: &self._port) }()
      case 4: try { try decoder.decodeSingularInt32Field(value: &self._frequency) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self._gateway) }()
      case 6: try { try decoder.decodeSingularBytesField(value: &self._ipV6Address) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._ssid {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._password {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._port {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._frequency {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._gateway {
      try visitor.visitSingularStringField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._ipV6Address {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 6)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials) -> Bool {
    if lhs._ssid != rhs._ssid {return false}
    if lhs._password != rhs._password {return false}
    if lhs._port != rhs._port {return false}
    if lhs._frequency != rhs._frequency {return false}
    if lhs._gateway != rhs._gateway {return false}
    if lhs._ipV6Address != rhs._ipV6Address {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".WebRtcCredentials"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "peer_id"),
    2: .standard(proto: "location_hint"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._peerID) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._locationHint) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._peerID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._locationHint {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials) -> Bool {
    if lhs._peerID != rhs._peerID {return false}
    if lhs._locationHint != rhs._locationHint {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".AwdlCredentials"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "service_name"),
    2: .standard(proto: "service_type"),
    3: .same(proto: "password"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._serviceName) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self._serviceType) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self._password) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._serviceName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._serviceType {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._password {
      try visitor.visitSingularStringField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials) -> Bool {
    if lhs._serviceName != rhs._serviceName {return false}
    if lhs._serviceType != rhs._serviceType {return false}
    if lhs._password != rhs._password {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.protoMessageName + ".UpgradePathRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "mediums"),
    2: .standard(proto: "medium_meta_data"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedEnumField(value: &self.mediums) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._mediumMetaData) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.mediums.isEmpty {
      try visitor.visitPackedEnumField(value: self.mediums, fieldNumber: 1)
    }
    try { if let v = self._mediumMetaData {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest) -> Bool {
    if lhs.mediums != rhs.mediums {return false}
    if lhs._mediumMetaData != rhs._mediumMetaData {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.protoMessageName + ".SafeToClosePriorChannel"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "sta_frequency"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt32Field(value: &self._staFrequency) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._staFrequency {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel) -> Bool {
    if lhs._staFrequency != rhs._staFrequency {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroduction: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.protoMessageName + ".ClientIntroduction"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "endpoint_id"),
    2: .standard(proto: "supports_disabling_encryption"),
    3: .standard(proto: "last_endpoint_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._endpointID) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self._supportsDisablingEncryption) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self._lastEndpointID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._endpointID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._supportsDisablingEncryption {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._lastEndpointID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroduction, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroduction) -> Bool {
    if lhs._endpointID != rhs._endpointID {return false}
    if lhs._supportsDisablingEncryption != rhs._supportsDisablingEncryption {return false}
    if lhs._lastEndpointID != rhs._lastEndpointID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroductionAck: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.protoMessageName + ".ClientIntroductionAck"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroductionAck, rhs: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame.ClientIntroductionAck) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeRetryFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".BandwidthUpgradeRetryFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "supported_medium"),
    2: .standard(proto: "is_request"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedEnumField(value: &self.supportedMedium) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self._isRequest) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.supportedMedium.isEmpty {
      try visitor.visitRepeatedEnumField(value: self.supportedMedium, fieldNumber: 1)
    }
    try { if let v = self._isRequest {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_BandwidthUpgradeRetryFrame, rhs: Location_Nearby_Connections_BandwidthUpgradeRetryFrame) -> Bool {
    if lhs.supportedMedium != rhs.supportedMedium {return false}
    if lhs._isRequest != rhs._isRequest {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_BandwidthUpgradeRetryFrame.Medium: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_MEDIUM"),
    2: .same(proto: "BLUETOOTH"),
    3: .same(proto: "WIFI_HOTSPOT"),
    4: .same(proto: "BLE"),
    5: .same(proto: "WIFI_LAN"),
    6: .same(proto: "WIFI_AWARE"),
    7: .same(proto: "NFC"),
    8: .same(proto: "WIFI_DIRECT"),
    9: .same(proto: "WEB_RTC"),
    10: .same(proto: "BLE_L2CAP"),
    11: .same(proto: "USB"),
    12: .same(proto: "WEB_RTC_NON_CELLULAR"),
    13: .same(proto: "AWDL"),
  ]
}

extension Location_Nearby_Connections_KeepAliveFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".KeepAliveFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "ack"),
    2: .standard(proto: "seq_num"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self._ack) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self._seqNum) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._ack {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._seqNum {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_KeepAliveFrame, rhs: Location_Nearby_Connections_KeepAliveFrame) -> Bool {
    if lhs._ack != rhs._ack {return false}
    if lhs._seqNum != rhs._seqNum {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_DisconnectionFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".DisconnectionFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "request_safe_to_disconnect"),
    2: .standard(proto: "ack_safe_to_disconnect"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self._requestSafeToDisconnect) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self._ackSafeToDisconnect) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._requestSafeToDisconnect {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._ackSafeToDisconnect {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_DisconnectionFrame, rhs: Location_Nearby_Connections_DisconnectionFrame) -> Bool {
    if lhs._requestSafeToDisconnect != rhs._requestSafeToDisconnect {return false}
    if lhs._ackSafeToDisconnect != rhs._ackSafeToDisconnect {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_PairedKeyEncryptionFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PairedKeyEncryptionFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "signed_data"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._signedData) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._signedData {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_PairedKeyEncryptionFrame, rhs: Location_Nearby_Connections_PairedKeyEncryptionFrame) -> Bool {
    if lhs._signedData != rhs._signedData {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_AuthenticationMessageFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AuthenticationMessageFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "auth_message"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self._authMessage) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._authMessage {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_AuthenticationMessageFrame, rhs: Location_Nearby_Connections_AuthenticationMessageFrame) -> Bool {
    if lhs._authMessage != rhs._authMessage {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_AuthenticationResultFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AuthenticationResultFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "result"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularInt32Field(value: &self._result) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._result {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_AuthenticationResultFrame, rhs: Location_Nearby_Connections_AuthenticationResultFrame) -> Bool {
    if lhs._result != rhs._result {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_AutoResumeFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AutoResumeFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "event_type"),
    2: .standard(proto: "pending_payload_id"),
    3: .standard(proto: "next_payload_chunk_index"),
    4: .same(proto: "version"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._eventType) }()
      case 2: try { try decoder.decodeSingularInt64Field(value: &self._pendingPayloadID) }()
      case 3: try { try decoder.decodeSingularInt32Field(value: &self._nextPayloadChunkIndex) }()
      case 4: try { try decoder.decodeSingularInt32Field(value: &self._version) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._eventType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._pendingPayloadID {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._nextPayloadChunkIndex {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._version {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_AutoResumeFrame, rhs: Location_Nearby_Connections_AutoResumeFrame) -> Bool {
    if lhs._eventType != rhs._eventType {return false}
    if lhs._pendingPayloadID != rhs._pendingPayloadID {return false}
    if lhs._nextPayloadChunkIndex != rhs._nextPayloadChunkIndex {return false}
    if lhs._version != rhs._version {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_AutoResumeFrame.EventType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_AUTO_RESUME_EVENT_TYPE"),
    1: .same(proto: "PAYLOAD_RESUME_TRANSFER_START"),
    2: .same(proto: "PAYLOAD_RESUME_TRANSFER_ACK"),
  ]
}

extension Location_Nearby_Connections_AutoReconnectFrame: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AutoReconnectFrame"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "endpoint_id"),
    2: .standard(proto: "event_type"),
    3: .standard(proto: "last_endpoint_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._endpointID) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._eventType) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self._lastEndpointID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._endpointID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._eventType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._lastEndpointID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_AutoReconnectFrame, rhs: Location_Nearby_Connections_AutoReconnectFrame) -> Bool {
    if lhs._endpointID != rhs._endpointID {return false}
    if lhs._eventType != rhs._eventType {return false}
    if lhs._lastEndpointID != rhs._lastEndpointID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_AutoReconnectFrame.EventType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_EVENT_TYPE"),
    1: .same(proto: "CLIENT_INTRODUCTION"),
    2: .same(proto: "CLIENT_INTRODUCTION_ACK"),
  ]
}

extension Location_Nearby_Connections_MediumMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".MediumMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "supports_5_ghz"),
    2: .same(proto: "bssid"),
    3: .standard(proto: "ip_address"),
    4: .standard(proto: "supports_6_ghz"),
    5: .standard(proto: "mobile_radio"),
    6: .standard(proto: "ap_frequency"),
    7: .standard(proto: "available_channels"),
    8: .standard(proto: "wifi_direct_cli_usable_channels"),
    9: .standard(proto: "wifi_lan_usable_channels"),
    10: .standard(proto: "wifi_aware_usable_channels"),
    11: .standard(proto: "wifi_hotspot_sta_usable_channels"),
    12: .standard(proto: "medium_role"),
  ]

  fileprivate class _StorageClass {
    var _supports5Ghz: Bool? = nil
    var _bssid: String? = nil
    var _ipAddress: Data? = nil
    var _supports6Ghz: Bool? = nil
    var _mobileRadio: Bool? = nil
    var _apFrequency: Int32? = nil
    var _availableChannels: Location_Nearby_Connections_AvailableChannels? = nil
    var _wifiDirectCliUsableChannels: Location_Nearby_Connections_WifiDirectCliUsableChannels? = nil
    var _wifiLanUsableChannels: Location_Nearby_Connections_WifiLanUsableChannels? = nil
    var _wifiAwareUsableChannels: Location_Nearby_Connections_WifiAwareUsableChannels? = nil
    var _wifiHotspotStaUsableChannels: Location_Nearby_Connections_WifiHotspotStaUsableChannels? = nil
    var _mediumRole: Location_Nearby_Connections_MediumRole? = nil

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _supports5Ghz = source._supports5Ghz
      _bssid = source._bssid
      _ipAddress = source._ipAddress
      _supports6Ghz = source._supports6Ghz
      _mobileRadio = source._mobileRadio
      _apFrequency = source._apFrequency
      _availableChannels = source._availableChannels
      _wifiDirectCliUsableChannels = source._wifiDirectCliUsableChannels
      _wifiLanUsableChannels = source._wifiLanUsableChannels
      _wifiAwareUsableChannels = source._wifiAwareUsableChannels
      _wifiHotspotStaUsableChannels = source._wifiHotspotStaUsableChannels
      _mediumRole = source._mediumRole
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
        case 1: try { try decoder.decodeSingularBoolField(value: &_storage._supports5Ghz) }()
        case 2: try { try decoder.decodeSingularStringField(value: &_storage._bssid) }()
        case 3: try { try decoder.decodeSingularBytesField(value: &_storage._ipAddress) }()
        case 4: try { try decoder.decodeSingularBoolField(value: &_storage._supports6Ghz) }()
        case 5: try { try decoder.decodeSingularBoolField(value: &_storage._mobileRadio) }()
        case 6: try { try decoder.decodeSingularInt32Field(value: &_storage._apFrequency) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._availableChannels) }()
        case 8: try { try decoder.decodeSingularMessageField(value: &_storage._wifiDirectCliUsableChannels) }()
        case 9: try { try decoder.decodeSingularMessageField(value: &_storage._wifiLanUsableChannels) }()
        case 10: try { try decoder.decodeSingularMessageField(value: &_storage._wifiAwareUsableChannels) }()
        case 11: try { try decoder.decodeSingularMessageField(value: &_storage._wifiHotspotStaUsableChannels) }()
        case 12: try { try decoder.decodeSingularMessageField(value: &_storage._mediumRole) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      try { if let v = _storage._supports5Ghz {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 1)
      } }()
      try { if let v = _storage._bssid {
        try visitor.visitSingularStringField(value: v, fieldNumber: 2)
      } }()
      try { if let v = _storage._ipAddress {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
      } }()
      try { if let v = _storage._supports6Ghz {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 4)
      } }()
      try { if let v = _storage._mobileRadio {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 5)
      } }()
      try { if let v = _storage._apFrequency {
        try visitor.visitSingularInt32Field(value: v, fieldNumber: 6)
      } }()
      try { if let v = _storage._availableChannels {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._wifiDirectCliUsableChannels {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
      } }()
      try { if let v = _storage._wifiLanUsableChannels {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 9)
      } }()
      try { if let v = _storage._wifiAwareUsableChannels {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 10)
      } }()
      try { if let v = _storage._wifiHotspotStaUsableChannels {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 11)
      } }()
      try { if let v = _storage._mediumRole {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 12)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_MediumMetadata, rhs: Location_Nearby_Connections_MediumMetadata) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._supports5Ghz != rhs_storage._supports5Ghz {return false}
        if _storage._bssid != rhs_storage._bssid {return false}
        if _storage._ipAddress != rhs_storage._ipAddress {return false}
        if _storage._supports6Ghz != rhs_storage._supports6Ghz {return false}
        if _storage._mobileRadio != rhs_storage._mobileRadio {return false}
        if _storage._apFrequency != rhs_storage._apFrequency {return false}
        if _storage._availableChannels != rhs_storage._availableChannels {return false}
        if _storage._wifiDirectCliUsableChannels != rhs_storage._wifiDirectCliUsableChannels {return false}
        if _storage._wifiLanUsableChannels != rhs_storage._wifiLanUsableChannels {return false}
        if _storage._wifiAwareUsableChannels != rhs_storage._wifiAwareUsableChannels {return false}
        if _storage._wifiHotspotStaUsableChannels != rhs_storage._wifiHotspotStaUsableChannels {return false}
        if _storage._mediumRole != rhs_storage._mediumRole {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_AvailableChannels: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".AvailableChannels"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channels"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedInt32Field(value: &self.channels) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.channels.isEmpty {
      try visitor.visitPackedInt32Field(value: self.channels, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_AvailableChannels, rhs: Location_Nearby_Connections_AvailableChannels) -> Bool {
    if lhs.channels != rhs.channels {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_WifiDirectCliUsableChannels: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".WifiDirectCliUsableChannels"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channels"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedInt32Field(value: &self.channels) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.channels.isEmpty {
      try visitor.visitPackedInt32Field(value: self.channels, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_WifiDirectCliUsableChannels, rhs: Location_Nearby_Connections_WifiDirectCliUsableChannels) -> Bool {
    if lhs.channels != rhs.channels {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_WifiLanUsableChannels: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".WifiLanUsableChannels"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channels"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedInt32Field(value: &self.channels) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.channels.isEmpty {
      try visitor.visitPackedInt32Field(value: self.channels, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_WifiLanUsableChannels, rhs: Location_Nearby_Connections_WifiLanUsableChannels) -> Bool {
    if lhs.channels != rhs.channels {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_WifiAwareUsableChannels: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".WifiAwareUsableChannels"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channels"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedInt32Field(value: &self.channels) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.channels.isEmpty {
      try visitor.visitPackedInt32Field(value: self.channels, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_WifiAwareUsableChannels, rhs: Location_Nearby_Connections_WifiAwareUsableChannels) -> Bool {
    if lhs.channels != rhs.channels {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_WifiHotspotStaUsableChannels: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".WifiHotspotStaUsableChannels"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "channels"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedInt32Field(value: &self.channels) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.channels.isEmpty {
      try visitor.visitPackedInt32Field(value: self.channels, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_WifiHotspotStaUsableChannels, rhs: Location_Nearby_Connections_WifiHotspotStaUsableChannels) -> Bool {
    if lhs.channels != rhs.channels {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_MediumRole: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".MediumRole"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "support_wifi_direct_group_owner"),
    2: .standard(proto: "support_wifi_direct_group_client"),
    3: .standard(proto: "support_wifi_hotspot_host"),
    4: .standard(proto: "support_wifi_hotspot_client"),
    5: .standard(proto: "support_wifi_aware_publisher"),
    6: .standard(proto: "support_wifi_aware_subscriber"),
    7: .standard(proto: "support_awdl_publisher"),
    8: .standard(proto: "support_awdl_subscriber"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self._supportWifiDirectGroupOwner) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self._supportWifiDirectGroupClient) }()
      case 3: try { try decoder.decodeSingularBoolField(value: &self._supportWifiHotspotHost) }()
      case 4: try { try decoder.decodeSingularBoolField(value: &self._supportWifiHotspotClient) }()
      case 5: try { try decoder.decodeSingularBoolField(value: &self._supportWifiAwarePublisher) }()
      case 6: try { try decoder.decodeSingularBoolField(value: &self._supportWifiAwareSubscriber) }()
      case 7: try { try decoder.decodeSingularBoolField(value: &self._supportAwdlPublisher) }()
      case 8: try { try decoder.decodeSingularBoolField(value: &self._supportAwdlSubscriber) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._supportWifiDirectGroupOwner {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._supportWifiDirectGroupClient {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._supportWifiHotspotHost {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._supportWifiHotspotClient {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._supportWifiAwarePublisher {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._supportWifiAwareSubscriber {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._supportAwdlPublisher {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 7)
    } }()
    try { if let v = self._supportAwdlSubscriber {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 8)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_MediumRole, rhs: Location_Nearby_Connections_MediumRole) -> Bool {
    if lhs._supportWifiDirectGroupOwner != rhs._supportWifiDirectGroupOwner {return false}
    if lhs._supportWifiDirectGroupClient != rhs._supportWifiDirectGroupClient {return false}
    if lhs._supportWifiHotspotHost != rhs._supportWifiHotspotHost {return false}
    if lhs._supportWifiHotspotClient != rhs._supportWifiHotspotClient {return false}
    if lhs._supportWifiAwarePublisher != rhs._supportWifiAwarePublisher {return false}
    if lhs._supportWifiAwareSubscriber != rhs._supportWifiAwareSubscriber {return false}
    if lhs._supportAwdlPublisher != rhs._supportAwdlPublisher {return false}
    if lhs._supportAwdlSubscriber != rhs._supportAwdlSubscriber {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_LocationHint: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".LocationHint"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "location"),
    2: .same(proto: "format"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._location) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._format) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._location {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._format {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_LocationHint, rhs: Location_Nearby_Connections_LocationHint) -> Bool {
    if lhs._location != rhs._location {return false}
    if lhs._format != rhs._format {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_LocationStandard: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".LocationStandard"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_LocationStandard, rhs: Location_Nearby_Connections_LocationStandard) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_LocationStandard.Format: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "E164_CALLING"),
    2: .same(proto: "ISO_3166_1_ALPHA_2"),
  ]
}

extension Location_Nearby_Connections_OsInfo: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".OsInfo"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "type"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._type) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._type {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_OsInfo, rhs: Location_Nearby_Connections_OsInfo) -> Bool {
    if lhs._type != rhs._type {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_OsInfo.OsType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_OS_TYPE"),
    1: .same(proto: "ANDROID"),
    2: .same(proto: "CHROME_OS"),
    3: .same(proto: "WINDOWS"),
    4: .same(proto: "APPLE"),
    100: .same(proto: "LINUX"),
  ]
}

extension Location_Nearby_Connections_ConnectionsDevice: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ConnectionsDevice"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "endpoint_id"),
    2: .standard(proto: "endpoint_type"),
    3: .standard(proto: "connectivity_info_list"),
    4: .standard(proto: "endpoint_info"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._endpointID) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._endpointType) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._connectivityInfoList) }()
      case 4: try { try decoder.decodeSingularBytesField(value: &self._endpointInfo) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._endpointID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._endpointType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._connectivityInfoList {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._endpointInfo {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_ConnectionsDevice, rhs: Location_Nearby_Connections_ConnectionsDevice) -> Bool {
    if lhs._endpointID != rhs._endpointID {return false}
    if lhs._endpointType != rhs._endpointType {return false}
    if lhs._connectivityInfoList != rhs._connectivityInfoList {return false}
    if lhs._endpointInfo != rhs._endpointInfo {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_PresenceDevice: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".PresenceDevice"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "endpoint_id"),
    2: .standard(proto: "endpoint_type"),
    3: .standard(proto: "connectivity_info_list"),
    4: .standard(proto: "device_id"),
    5: .standard(proto: "device_name"),
    6: .standard(proto: "device_type"),
    7: .standard(proto: "device_image_url"),
    8: .standard(proto: "discovery_medium"),
    9: .same(proto: "actions"),
    10: .standard(proto: "identity_type"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self._endpointID) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self._endpointType) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self._connectivityInfoList) }()
      case 4: try { try decoder.decodeSingularInt64Field(value: &self._deviceID) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self._deviceName) }()
      case 6: try { try decoder.decodeSingularEnumField(value: &self._deviceType) }()
      case 7: try { try decoder.decodeSingularStringField(value: &self._deviceImageURL) }()
      case 8: try { try decoder.decodeRepeatedEnumField(value: &self.discoveryMedium) }()
      case 9: try { try decoder.decodeRepeatedInt32Field(value: &self.actions) }()
      case 10: try { try decoder.decodeRepeatedInt64Field(value: &self.identityType) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._endpointID {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._endpointType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._connectivityInfoList {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._deviceID {
      try visitor.visitSingularInt64Field(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._deviceName {
      try visitor.visitSingularStringField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._deviceType {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 6)
    } }()
    try { if let v = self._deviceImageURL {
      try visitor.visitSingularStringField(value: v, fieldNumber: 7)
    } }()
    if !self.discoveryMedium.isEmpty {
      try visitor.visitPackedEnumField(value: self.discoveryMedium, fieldNumber: 8)
    }
    if !self.actions.isEmpty {
      try visitor.visitPackedInt32Field(value: self.actions, fieldNumber: 9)
    }
    if !self.identityType.isEmpty {
      try visitor.visitPackedInt64Field(value: self.identityType, fieldNumber: 10)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Location_Nearby_Connections_PresenceDevice, rhs: Location_Nearby_Connections_PresenceDevice) -> Bool {
    if lhs._endpointID != rhs._endpointID {return false}
    if lhs._endpointType != rhs._endpointType {return false}
    if lhs._connectivityInfoList != rhs._connectivityInfoList {return false}
    if lhs._deviceID != rhs._deviceID {return false}
    if lhs._deviceName != rhs._deviceName {return false}
    if lhs._deviceType != rhs._deviceType {return false}
    if lhs._deviceImageURL != rhs._deviceImageURL {return false}
    if lhs.discoveryMedium != rhs.discoveryMedium {return false}
    if lhs.actions != rhs.actions {return false}
    if lhs.identityType != rhs.identityType {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Location_Nearby_Connections_PresenceDevice.DeviceType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "PHONE"),
    2: .same(proto: "TABLET"),
    3: .same(proto: "DISPLAY"),
    4: .same(proto: "LAPTOP"),
    5: .same(proto: "TV"),
    6: .same(proto: "WATCH"),
  ]
}