//
//  securegcm.pb.swift
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

enum Securegcm_AppleDeviceDiagonalMils: SwiftProtobuf.Enum {
  typealias RawValue = Int

  case applePhone

  case applePad

  init() {
    self = .applePhone
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 4000: self = .applePhone
    case 7900: self = .applePad
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .applePhone: return 4000
    case .applePad: return 7900
    }
  }

}

#if swift(>=4.2)

extension Securegcm_AppleDeviceDiagonalMils: CaseIterable {
}

#endif

enum Securegcm_DeviceType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case android
  case chrome
  case ios
  case browser
  case osx

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .android
    case 2: self = .chrome
    case 3: self = .ios
    case 4: self = .browser
    case 5: self = .osx
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .android: return 1
    case .chrome: return 2
    case .ios: return 3
    case .browser: return 4
    case .osx: return 5
    }
  }

}

#if swift(>=4.2)

extension Securegcm_DeviceType: CaseIterable {
}

#endif

enum Securegcm_SoftwareFeature: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownFeature
  case betterTogetherHost
  case betterTogetherClient
  case easyUnlockHost
  case easyUnlockClient
  case magicTetherHost
  case magicTetherClient
  case smsConnectHost
  case smsConnectClient

  init() {
    self = .unknownFeature
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownFeature
    case 1: self = .betterTogetherHost
    case 2: self = .betterTogetherClient
    case 3: self = .easyUnlockHost
    case 4: self = .easyUnlockClient
    case 5: self = .magicTetherHost
    case 6: self = .magicTetherClient
    case 7: self = .smsConnectHost
    case 8: self = .smsConnectClient
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownFeature: return 0
    case .betterTogetherHost: return 1
    case .betterTogetherClient: return 2
    case .easyUnlockHost: return 3
    case .easyUnlockClient: return 4
    case .magicTetherHost: return 5
    case .magicTetherClient: return 6
    case .smsConnectHost: return 7
    case .smsConnectClient: return 8
    }
  }

}

#if swift(>=4.2)

extension Securegcm_SoftwareFeature: CaseIterable {
}

#endif

enum Securegcm_InvocationReason: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case reasonUnknown

  case reasonInitialization

  case reasonPeriodic

  case reasonSlowPeriodic

  case reasonFastPeriodic

  case reasonExpiration

  case reasonFailureRecovery

  case reasonNewAccount

  case reasonChangedAccount

  case reasonFeatureToggled

  case reasonServerInitiated

  case reasonAddressChange

  case reasonSoftwareUpdate

  case reasonManual

  case reasonCustomKeyInvalidation

  case reasonProximityPeriodic

  init() {
    self = .reasonUnknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .reasonUnknown
    case 1: self = .reasonInitialization
    case 2: self = .reasonPeriodic
    case 3: self = .reasonSlowPeriodic
    case 4: self = .reasonFastPeriodic
    case 5: self = .reasonExpiration
    case 6: self = .reasonFailureRecovery
    case 7: self = .reasonNewAccount
    case 8: self = .reasonChangedAccount
    case 9: self = .reasonFeatureToggled
    case 10: self = .reasonServerInitiated
    case 11: self = .reasonAddressChange
    case 12: self = .reasonSoftwareUpdate
    case 13: self = .reasonManual
    case 14: self = .reasonCustomKeyInvalidation
    case 15: self = .reasonProximityPeriodic
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .reasonUnknown: return 0
    case .reasonInitialization: return 1
    case .reasonPeriodic: return 2
    case .reasonSlowPeriodic: return 3
    case .reasonFastPeriodic: return 4
    case .reasonExpiration: return 5
    case .reasonFailureRecovery: return 6
    case .reasonNewAccount: return 7
    case .reasonChangedAccount: return 8
    case .reasonFeatureToggled: return 9
    case .reasonServerInitiated: return 10
    case .reasonAddressChange: return 11
    case .reasonSoftwareUpdate: return 12
    case .reasonManual: return 13
    case .reasonCustomKeyInvalidation: return 14
    case .reasonProximityPeriodic: return 15
    }
  }

}

#if swift(>=4.2)

extension Securegcm_InvocationReason: CaseIterable {
}

#endif

enum Securegcm_Type: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case enrollment
  case tickle
  case txRequest
  case txReply
  case txSyncRequest
  case txSyncResponse
  case txPing
  case deviceInfoUpdate
  case txCancelRequest

  case proximityauthPairing

  case gcmv1IdentityAssertion

  case deviceToDeviceResponderHelloPayload

  case deviceToDeviceMessage

  case deviceProximityCallback

  case unlockKeySignedChallenge

  case loginNotification

  init() {
    self = .enrollment
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .enrollment
    case 1: self = .tickle
    case 2: self = .txRequest
    case 3: self = .txReply
    case 4: self = .txSyncRequest
    case 5: self = .txSyncResponse
    case 6: self = .txPing
    case 7: self = .deviceInfoUpdate
    case 8: self = .txCancelRequest
    case 10: self = .proximityauthPairing
    case 11: self = .gcmv1IdentityAssertion
    case 12: self = .deviceToDeviceResponderHelloPayload
    case 13: self = .deviceToDeviceMessage
    case 14: self = .deviceProximityCallback
    case 15: self = .unlockKeySignedChallenge
    case 101: self = .loginNotification
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .enrollment: return 0
    case .tickle: return 1
    case .txRequest: return 2
    case .txReply: return 3
    case .txSyncRequest: return 4
    case .txSyncResponse: return 5
    case .txPing: return 6
    case .deviceInfoUpdate: return 7
    case .txCancelRequest: return 8
    case .proximityauthPairing: return 10
    case .gcmv1IdentityAssertion: return 11
    case .deviceToDeviceResponderHelloPayload: return 12
    case .deviceToDeviceMessage: return 13
    case .deviceProximityCallback: return 14
    case .unlockKeySignedChallenge: return 15
    case .loginNotification: return 101
    }
  }

}

#if swift(>=4.2)

extension Securegcm_Type: CaseIterable {
}

#endif

struct Securegcm_GcmDeviceInfo {

  var androidDeviceID: UInt64 {
    get {return _storage._androidDeviceID ?? 0}
    set {_uniqueStorage()._androidDeviceID = newValue}
  }
  var hasAndroidDeviceID: Bool {return _storage._androidDeviceID != nil}
  mutating func clearAndroidDeviceID() {_uniqueStorage()._androidDeviceID = nil}

  var gcmRegistrationID: Data {
    get {return _storage._gcmRegistrationID ?? Data()}
    set {_uniqueStorage()._gcmRegistrationID = newValue}
  }
  var hasGcmRegistrationID: Bool {return _storage._gcmRegistrationID != nil}
  mutating func clearGcmRegistrationID() {_uniqueStorage()._gcmRegistrationID = nil}

  var apnRegistrationID: Data {
    get {return _storage._apnRegistrationID ?? Data()}
    set {_uniqueStorage()._apnRegistrationID = newValue}
  }
  var hasApnRegistrationID: Bool {return _storage._apnRegistrationID != nil}
  mutating func clearApnRegistrationID() {_uniqueStorage()._apnRegistrationID = nil}

  var notificationEnabled: Bool {
    get {return _storage._notificationEnabled ?? true}
    set {_uniqueStorage()._notificationEnabled = newValue}
  }
  var hasNotificationEnabled: Bool {return _storage._notificationEnabled != nil}
  mutating func clearNotificationEnabled() {_uniqueStorage()._notificationEnabled = nil}

  var bluetoothMacAddress: String {
    get {return _storage._bluetoothMacAddress ?? String()}
    set {_uniqueStorage()._bluetoothMacAddress = newValue}
  }
  var hasBluetoothMacAddress: Bool {return _storage._bluetoothMacAddress != nil}
  mutating func clearBluetoothMacAddress() {_uniqueStorage()._bluetoothMacAddress = nil}

  var deviceMasterKeyHash: Data {
    get {return _storage._deviceMasterKeyHash ?? Data()}
    set {_uniqueStorage()._deviceMasterKeyHash = newValue}
  }
  var hasDeviceMasterKeyHash: Bool {return _storage._deviceMasterKeyHash != nil}
  mutating func clearDeviceMasterKeyHash() {_uniqueStorage()._deviceMasterKeyHash = nil}

  var userPublicKey: Data {
    get {return _storage._userPublicKey ?? Data()}
    set {_uniqueStorage()._userPublicKey = newValue}
  }
  var hasUserPublicKey: Bool {return _storage._userPublicKey != nil}
  mutating func clearUserPublicKey() {_uniqueStorage()._userPublicKey = nil}

  var deviceModel: String {
    get {return _storage._deviceModel ?? String()}
    set {_uniqueStorage()._deviceModel = newValue}
  }
  var hasDeviceModel: Bool {return _storage._deviceModel != nil}
  mutating func clearDeviceModel() {_uniqueStorage()._deviceModel = nil}

  var locale: String {
    get {return _storage._locale ?? String()}
    set {_uniqueStorage()._locale = newValue}
  }
  var hasLocale: Bool {return _storage._locale != nil}
  mutating func clearLocale() {_uniqueStorage()._locale = nil}

  var keyHandle: Data {
    get {return _storage._keyHandle ?? Data()}
    set {_uniqueStorage()._keyHandle = newValue}
  }
  var hasKeyHandle: Bool {return _storage._keyHandle != nil}
  mutating func clearKeyHandle() {_uniqueStorage()._keyHandle = nil}

  var counter: Int64 {
    get {return _storage._counter ?? 0}
    set {_uniqueStorage()._counter = newValue}
  }
  var hasCounter: Bool {return _storage._counter != nil}
  mutating func clearCounter() {_uniqueStorage()._counter = nil}

  var deviceOsVersion: String {
    get {return _storage._deviceOsVersion ?? String()}
    set {_uniqueStorage()._deviceOsVersion = newValue}
  }
  var hasDeviceOsVersion: Bool {return _storage._deviceOsVersion != nil}
  mutating func clearDeviceOsVersion() {_uniqueStorage()._deviceOsVersion = nil}

  var deviceOsVersionCode: Int64 {
    get {return _storage._deviceOsVersionCode ?? 0}
    set {_uniqueStorage()._deviceOsVersionCode = newValue}
  }
  var hasDeviceOsVersionCode: Bool {return _storage._deviceOsVersionCode != nil}
  mutating func clearDeviceOsVersionCode() {_uniqueStorage()._deviceOsVersionCode = nil}

  var deviceOsRelease: String {
    get {return _storage._deviceOsRelease ?? String()}
    set {_uniqueStorage()._deviceOsRelease = newValue}
  }
  var hasDeviceOsRelease: Bool {return _storage._deviceOsRelease != nil}
  mutating func clearDeviceOsRelease() {_uniqueStorage()._deviceOsRelease = nil}

  var deviceOsCodename: String {
    get {return _storage._deviceOsCodename ?? String()}
    set {_uniqueStorage()._deviceOsCodename = newValue}
  }
  var hasDeviceOsCodename: Bool {return _storage._deviceOsCodename != nil}
  mutating func clearDeviceOsCodename() {_uniqueStorage()._deviceOsCodename = nil}

  var deviceSoftwareVersion: String {
    get {return _storage._deviceSoftwareVersion ?? String()}
    set {_uniqueStorage()._deviceSoftwareVersion = newValue}
  }
  var hasDeviceSoftwareVersion: Bool {return _storage._deviceSoftwareVersion != nil}
  mutating func clearDeviceSoftwareVersion() {_uniqueStorage()._deviceSoftwareVersion = nil}

  var deviceSoftwareVersionCode: Int64 {
    get {return _storage._deviceSoftwareVersionCode ?? 0}
    set {_uniqueStorage()._deviceSoftwareVersionCode = newValue}
  }
  var hasDeviceSoftwareVersionCode: Bool {return _storage._deviceSoftwareVersionCode != nil}
  mutating func clearDeviceSoftwareVersionCode() {_uniqueStorage()._deviceSoftwareVersionCode = nil}

  var deviceSoftwarePackage: String {
    get {return _storage._deviceSoftwarePackage ?? String()}
    set {_uniqueStorage()._deviceSoftwarePackage = newValue}
  }
  var hasDeviceSoftwarePackage: Bool {return _storage._deviceSoftwarePackage != nil}
  mutating func clearDeviceSoftwarePackage() {_uniqueStorage()._deviceSoftwarePackage = nil}

  var deviceDisplayDiagonalMils: Int32 {
    get {return _storage._deviceDisplayDiagonalMils ?? 0}
    set {_uniqueStorage()._deviceDisplayDiagonalMils = newValue}
  }
  var hasDeviceDisplayDiagonalMils: Bool {return _storage._deviceDisplayDiagonalMils != nil}
  mutating func clearDeviceDisplayDiagonalMils() {_uniqueStorage()._deviceDisplayDiagonalMils = nil}

  var deviceAuthzenVersion: Int32 {
    get {return _storage._deviceAuthzenVersion ?? 0}
    set {_uniqueStorage()._deviceAuthzenVersion = newValue}
  }
  var hasDeviceAuthzenVersion: Bool {return _storage._deviceAuthzenVersion != nil}
  mutating func clearDeviceAuthzenVersion() {_uniqueStorage()._deviceAuthzenVersion = nil}

  var longDeviceID: Data {
    get {return _storage._longDeviceID ?? Data()}
    set {_uniqueStorage()._longDeviceID = newValue}
  }
  var hasLongDeviceID: Bool {return _storage._longDeviceID != nil}
  mutating func clearLongDeviceID() {_uniqueStorage()._longDeviceID = nil}

  var deviceManufacturer: String {
    get {return _storage._deviceManufacturer ?? String()}
    set {_uniqueStorage()._deviceManufacturer = newValue}
  }
  var hasDeviceManufacturer: Bool {return _storage._deviceManufacturer != nil}
  mutating func clearDeviceManufacturer() {_uniqueStorage()._deviceManufacturer = nil}

  var deviceType: Securegcm_DeviceType {
    get {return _storage._deviceType ?? .android}
    set {_uniqueStorage()._deviceType = newValue}
  }
  var hasDeviceType: Bool {return _storage._deviceType != nil}
  mutating func clearDeviceType() {_uniqueStorage()._deviceType = nil}

  var usingSecureScreenlock: Bool {
    get {return _storage._usingSecureScreenlock ?? false}
    set {_uniqueStorage()._usingSecureScreenlock = newValue}
  }
  var hasUsingSecureScreenlock: Bool {return _storage._usingSecureScreenlock != nil}
  mutating func clearUsingSecureScreenlock() {_uniqueStorage()._usingSecureScreenlock = nil}

  var autoUnlockScreenlockSupported: Bool {
    get {return _storage._autoUnlockScreenlockSupported ?? false}
    set {_uniqueStorage()._autoUnlockScreenlockSupported = newValue}
  }
  var hasAutoUnlockScreenlockSupported: Bool {return _storage._autoUnlockScreenlockSupported != nil}
  mutating func clearAutoUnlockScreenlockSupported() {_uniqueStorage()._autoUnlockScreenlockSupported = nil}

  var autoUnlockScreenlockEnabled: Bool {
    get {return _storage._autoUnlockScreenlockEnabled ?? false}
    set {_uniqueStorage()._autoUnlockScreenlockEnabled = newValue}
  }
  var hasAutoUnlockScreenlockEnabled: Bool {return _storage._autoUnlockScreenlockEnabled != nil}
  mutating func clearAutoUnlockScreenlockEnabled() {_uniqueStorage()._autoUnlockScreenlockEnabled = nil}

  var bluetoothRadioSupported: Bool {
    get {return _storage._bluetoothRadioSupported ?? false}
    set {_uniqueStorage()._bluetoothRadioSupported = newValue}
  }
  var hasBluetoothRadioSupported: Bool {return _storage._bluetoothRadioSupported != nil}
  mutating func clearBluetoothRadioSupported() {_uniqueStorage()._bluetoothRadioSupported = nil}

  var bluetoothRadioEnabled: Bool {
    get {return _storage._bluetoothRadioEnabled ?? false}
    set {_uniqueStorage()._bluetoothRadioEnabled = newValue}
  }
  var hasBluetoothRadioEnabled: Bool {return _storage._bluetoothRadioEnabled != nil}
  mutating func clearBluetoothRadioEnabled() {_uniqueStorage()._bluetoothRadioEnabled = nil}

  var mobileDataSupported: Bool {
    get {return _storage._mobileDataSupported ?? false}
    set {_uniqueStorage()._mobileDataSupported = newValue}
  }
  var hasMobileDataSupported: Bool {return _storage._mobileDataSupported != nil}
  mutating func clearMobileDataSupported() {_uniqueStorage()._mobileDataSupported = nil}

  var tetheringSupported: Bool {
    get {return _storage._tetheringSupported ?? false}
    set {_uniqueStorage()._tetheringSupported = newValue}
  }
  var hasTetheringSupported: Bool {return _storage._tetheringSupported != nil}
  mutating func clearTetheringSupported() {_uniqueStorage()._tetheringSupported = nil}

  var bleRadioSupported: Bool {
    get {return _storage._bleRadioSupported ?? false}
    set {_uniqueStorage()._bleRadioSupported = newValue}
  }
  var hasBleRadioSupported: Bool {return _storage._bleRadioSupported != nil}
  mutating func clearBleRadioSupported() {_uniqueStorage()._bleRadioSupported = nil}

  var pixelExperience: Bool {
    get {return _storage._pixelExperience ?? false}
    set {_uniqueStorage()._pixelExperience = newValue}
  }
  var hasPixelExperience: Bool {return _storage._pixelExperience != nil}
  mutating func clearPixelExperience() {_uniqueStorage()._pixelExperience = nil}

  var arcPlusPlus: Bool {
    get {return _storage._arcPlusPlus ?? false}
    set {_uniqueStorage()._arcPlusPlus = newValue}
  }
  var hasArcPlusPlus: Bool {return _storage._arcPlusPlus != nil}
  mutating func clearArcPlusPlus() {_uniqueStorage()._arcPlusPlus = nil}

  var isScreenlockStateFlaky: Bool {
    get {return _storage._isScreenlockStateFlaky ?? false}
    set {_uniqueStorage()._isScreenlockStateFlaky = newValue}
  }
  var hasIsScreenlockStateFlaky: Bool {return _storage._isScreenlockStateFlaky != nil}
  mutating func clearIsScreenlockStateFlaky() {_uniqueStorage()._isScreenlockStateFlaky = nil}

  var supportedSoftwareFeatures: [Securegcm_SoftwareFeature] {
    get {return _storage._supportedSoftwareFeatures}
    set {_uniqueStorage()._supportedSoftwareFeatures = newValue}
  }

  var enabledSoftwareFeatures: [Securegcm_SoftwareFeature] {
    get {return _storage._enabledSoftwareFeatures}
    set {_uniqueStorage()._enabledSoftwareFeatures = newValue}
  }

  var enrollmentSessionID: Data {
    get {return _storage._enrollmentSessionID ?? Data()}
    set {_uniqueStorage()._enrollmentSessionID = newValue}
  }
  var hasEnrollmentSessionID: Bool {return _storage._enrollmentSessionID != nil}
  mutating func clearEnrollmentSessionID() {_uniqueStorage()._enrollmentSessionID = nil}

  var oauthToken: String {
    get {return _storage._oauthToken ?? String()}
    set {_uniqueStorage()._oauthToken = newValue}
  }
  var hasOauthToken: Bool {return _storage._oauthToken != nil}
  mutating func clearOauthToken() {_uniqueStorage()._oauthToken = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

struct Securegcm_GcmMetadata {

  var type: Securegcm_Type {
    get {return _type ?? .enrollment}
    set {_type = newValue}
  }
  var hasType: Bool {return self._type != nil}
  mutating func clearType() {self._type = nil}

  var version: Int32 {
    get {return _version ?? 0}
    set {_version = newValue}
  }
  var hasVersion: Bool {return self._version != nil}
  mutating func clearVersion() {self._version = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _type: Securegcm_Type? = nil
  fileprivate var _version: Int32? = nil
}

struct Securegcm_Tickle {

  var expiryTime: UInt64 {
    get {return _expiryTime ?? 0}
    set {_expiryTime = newValue}
  }
  var hasExpiryTime: Bool {return self._expiryTime != nil}
  mutating func clearExpiryTime() {self._expiryTime = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _expiryTime: UInt64? = nil
}

struct Securegcm_LoginNotificationInfo {

  var creationTime: UInt64 {
    get {return _creationTime ?? 0}
    set {_creationTime = newValue}
  }
  var hasCreationTime: Bool {return self._creationTime != nil}
  mutating func clearCreationTime() {self._creationTime = nil}

  var email: String {
    get {return _email ?? String()}
    set {_email = newValue}
  }
  var hasEmail: Bool {return self._email != nil}
  mutating func clearEmail() {self._email = nil}

  var host: String {
    get {return _host ?? String()}
    set {_host = newValue}
  }
  var hasHost: Bool {return self._host != nil}
  mutating func clearHost() {self._host = nil}

  var source: String {
    get {return _source ?? String()}
    set {_source = newValue}
  }
  var hasSource: Bool {return self._source != nil}
  mutating func clearSource() {self._source = nil}

  var eventType: String {
    get {return _eventType ?? String()}
    set {_eventType = newValue}
  }
  var hasEventType: Bool {return self._eventType != nil}
  mutating func clearEventType() {self._eventType = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _creationTime: UInt64? = nil
  fileprivate var _email: String? = nil
  fileprivate var _host: String? = nil
  fileprivate var _source: String? = nil
  fileprivate var _eventType: String? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Securegcm_AppleDeviceDiagonalMils: @unchecked Sendable {}
extension Securegcm_DeviceType: @unchecked Sendable {}
extension Securegcm_SoftwareFeature: @unchecked Sendable {}
extension Securegcm_InvocationReason: @unchecked Sendable {}
extension Securegcm_Type: @unchecked Sendable {}
extension Securegcm_GcmDeviceInfo: @unchecked Sendable {}
extension Securegcm_GcmMetadata: @unchecked Sendable {}
extension Securegcm_Tickle: @unchecked Sendable {}
extension Securegcm_LoginNotificationInfo: @unchecked Sendable {}
#endif

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "securegcm"

extension Securegcm_AppleDeviceDiagonalMils: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    4000: .same(proto: "APPLE_PHONE"),
    7900: .same(proto: "APPLE_PAD"),
  ]
}

extension Securegcm_DeviceType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "ANDROID"),
    2: .same(proto: "CHROME"),
    3: .same(proto: "IOS"),
    4: .same(proto: "BROWSER"),
    5: .same(proto: "OSX"),
  ]
}

extension Securegcm_SoftwareFeature: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_FEATURE"),
    1: .same(proto: "BETTER_TOGETHER_HOST"),
    2: .same(proto: "BETTER_TOGETHER_CLIENT"),
    3: .same(proto: "EASY_UNLOCK_HOST"),
    4: .same(proto: "EASY_UNLOCK_CLIENT"),
    5: .same(proto: "MAGIC_TETHER_HOST"),
    6: .same(proto: "MAGIC_TETHER_CLIENT"),
    7: .same(proto: "SMS_CONNECT_HOST"),
    8: .same(proto: "SMS_CONNECT_CLIENT"),
  ]
}

extension Securegcm_InvocationReason: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "REASON_UNKNOWN"),
    1: .same(proto: "REASON_INITIALIZATION"),
    2: .same(proto: "REASON_PERIODIC"),
    3: .same(proto: "REASON_SLOW_PERIODIC"),
    4: .same(proto: "REASON_FAST_PERIODIC"),
    5: .same(proto: "REASON_EXPIRATION"),
    6: .same(proto: "REASON_FAILURE_RECOVERY"),
    7: .same(proto: "REASON_NEW_ACCOUNT"),
    8: .same(proto: "REASON_CHANGED_ACCOUNT"),
    9: .same(proto: "REASON_FEATURE_TOGGLED"),
    10: .same(proto: "REASON_SERVER_INITIATED"),
    11: .same(proto: "REASON_ADDRESS_CHANGE"),
    12: .same(proto: "REASON_SOFTWARE_UPDATE"),
    13: .same(proto: "REASON_MANUAL"),
    14: .same(proto: "REASON_CUSTOM_KEY_INVALIDATION"),
    15: .same(proto: "REASON_PROXIMITY_PERIODIC"),
  ]
}

extension Securegcm_Type: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "ENROLLMENT"),
    1: .same(proto: "TICKLE"),
    2: .same(proto: "TX_REQUEST"),
    3: .same(proto: "TX_REPLY"),
    4: .same(proto: "TX_SYNC_REQUEST"),
    5: .same(proto: "TX_SYNC_RESPONSE"),
    6: .same(proto: "TX_PING"),
    7: .same(proto: "DEVICE_INFO_UPDATE"),
    8: .same(proto: "TX_CANCEL_REQUEST"),
    10: .same(proto: "PROXIMITYAUTH_PAIRING"),
    11: .same(proto: "GCMV1_IDENTITY_ASSERTION"),
    12: .same(proto: "DEVICE_TO_DEVICE_RESPONDER_HELLO_PAYLOAD"),
    13: .same(proto: "DEVICE_TO_DEVICE_MESSAGE"),
    14: .same(proto: "DEVICE_PROXIMITY_CALLBACK"),
    15: .same(proto: "UNLOCK_KEY_SIGNED_CHALLENGE"),
    101: .same(proto: "LOGIN_NOTIFICATION"),
  ]
}

extension Securegcm_GcmDeviceInfo: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GcmDeviceInfo"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "android_device_id"),
    102: .standard(proto: "gcm_registration_id"),
    202: .standard(proto: "apn_registration_id"),
    203: .standard(proto: "notification_enabled"),
    302: .standard(proto: "bluetooth_mac_address"),
    103: .standard(proto: "device_master_key_hash"),
    4: .standard(proto: "user_public_key"),
    7: .standard(proto: "device_model"),
    8: .same(proto: "locale"),
    9: .standard(proto: "key_handle"),
    12: .same(proto: "counter"),
    13: .standard(proto: "device_os_version"),
    14: .standard(proto: "device_os_version_code"),
    15: .standard(proto: "device_os_release"),
    16: .standard(proto: "device_os_codename"),
    17: .standard(proto: "device_software_version"),
    18: .standard(proto: "device_software_version_code"),
    19: .standard(proto: "device_software_package"),
    22: .standard(proto: "device_display_diagonal_mils"),
    24: .standard(proto: "device_authzen_version"),
    29: .standard(proto: "long_device_id"),
    31: .standard(proto: "device_manufacturer"),
    32: .standard(proto: "device_type"),
    400: .standard(proto: "using_secure_screenlock"),
    401: .standard(proto: "auto_unlock_screenlock_supported"),
    402: .standard(proto: "auto_unlock_screenlock_enabled"),
    403: .standard(proto: "bluetooth_radio_supported"),
    404: .standard(proto: "bluetooth_radio_enabled"),
    405: .standard(proto: "mobile_data_supported"),
    406: .standard(proto: "tethering_supported"),
    407: .standard(proto: "ble_radio_supported"),
    408: .standard(proto: "pixel_experience"),
    409: .standard(proto: "arc_plus_plus"),
    410: .standard(proto: "is_screenlock_state_flaky"),
    411: .standard(proto: "supported_software_features"),
    412: .standard(proto: "enabled_software_features"),
    1000: .standard(proto: "enrollment_session_id"),
    1001: .standard(proto: "oauth_token"),
  ]

  fileprivate class _StorageClass {
    var _androidDeviceID: UInt64? = nil
    var _gcmRegistrationID: Data? = nil
    var _apnRegistrationID: Data? = nil
    var _notificationEnabled: Bool? = nil
    var _bluetoothMacAddress: String? = nil
    var _deviceMasterKeyHash: Data? = nil
    var _userPublicKey: Data? = nil
    var _deviceModel: String? = nil
    var _locale: String? = nil
    var _keyHandle: Data? = nil
    var _counter: Int64? = nil
    var _deviceOsVersion: String? = nil
    var _deviceOsVersionCode: Int64? = nil
    var _deviceOsRelease: String? = nil
    var _deviceOsCodename: String? = nil
    var _deviceSoftwareVersion: String? = nil
    var _deviceSoftwareVersionCode: Int64? = nil
    var _deviceSoftwarePackage: String? = nil
    var _deviceDisplayDiagonalMils: Int32? = nil
    var _deviceAuthzenVersion: Int32? = nil
    var _longDeviceID: Data? = nil
    var _deviceManufacturer: String? = nil
    var _deviceType: Securegcm_DeviceType? = nil
    var _usingSecureScreenlock: Bool? = nil
    var _autoUnlockScreenlockSupported: Bool? = nil
    var _autoUnlockScreenlockEnabled: Bool? = nil
    var _bluetoothRadioSupported: Bool? = nil
    var _bluetoothRadioEnabled: Bool? = nil
    var _mobileDataSupported: Bool? = nil
    var _tetheringSupported: Bool? = nil
    var _bleRadioSupported: Bool? = nil
    var _pixelExperience: Bool? = nil
    var _arcPlusPlus: Bool? = nil
    var _isScreenlockStateFlaky: Bool? = nil
    var _supportedSoftwareFeatures: [Securegcm_SoftwareFeature] = []
    var _enabledSoftwareFeatures: [Securegcm_SoftwareFeature] = []
    var _enrollmentSessionID: Data? = nil
    var _oauthToken: String? = nil

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _androidDeviceID = source._androidDeviceID
      _gcmRegistrationID = source._gcmRegistrationID
      _apnRegistrationID = source._apnRegistrationID
      _notificationEnabled = source._notificationEnabled
      _bluetoothMacAddress = source._bluetoothMacAddress
      _deviceMasterKeyHash = source._deviceMasterKeyHash
      _userPublicKey = source._userPublicKey
      _deviceModel = source._deviceModel
      _locale = source._locale
      _keyHandle = source._keyHandle
      _counter = source._counter
      _deviceOsVersion = source._deviceOsVersion
      _deviceOsVersionCode = source._deviceOsVersionCode
      _deviceOsRelease = source._deviceOsRelease
      _deviceOsCodename = source._deviceOsCodename
      _deviceSoftwareVersion = source._deviceSoftwareVersion
      _deviceSoftwareVersionCode = source._deviceSoftwareVersionCode
      _deviceSoftwarePackage = source._deviceSoftwarePackage
      _deviceDisplayDiagonalMils = source._deviceDisplayDiagonalMils
      _deviceAuthzenVersion = source._deviceAuthzenVersion
      _longDeviceID = source._longDeviceID
      _deviceManufacturer = source._deviceManufacturer
      _deviceType = source._deviceType
      _usingSecureScreenlock = source._usingSecureScreenlock
      _autoUnlockScreenlockSupported = source._autoUnlockScreenlockSupported
      _autoUnlockScreenlockEnabled = source._autoUnlockScreenlockEnabled
      _bluetoothRadioSupported = source._bluetoothRadioSupported
      _bluetoothRadioEnabled = source._bluetoothRadioEnabled
      _mobileDataSupported = source._mobileDataSupported
      _tetheringSupported = source._tetheringSupported
      _bleRadioSupported = source._bleRadioSupported
      _pixelExperience = source._pixelExperience
      _arcPlusPlus = source._arcPlusPlus
      _isScreenlockStateFlaky = source._isScreenlockStateFlaky
      _supportedSoftwareFeatures = source._supportedSoftwareFeatures
      _enabledSoftwareFeatures = source._enabledSoftwareFeatures
      _enrollmentSessionID = source._enrollmentSessionID
      _oauthToken = source._oauthToken
    }
  }

  fileprivate mutating func _uniqueStorage() -> _StorageClass {
    if !isKnownUniquelyReferenced(&_storage) {
      _storage = _StorageClass(copying: _storage)
    }
    return _storage
  }

  public var isInitialized: Bool {
    return withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      if _storage._userPublicKey == nil {return false}
      return true
    }
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    _ = _uniqueStorage()
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      while let fieldNumber = try decoder.nextFieldNumber() {
        switch fieldNumber {
        case 1: try { try decoder.decodeSingularFixed64Field(value: &_storage._androidDeviceID) }()
        case 4: try { try decoder.decodeSingularBytesField(value: &_storage._userPublicKey) }()
        case 7: try { try decoder.decodeSingularStringField(value: &_storage._deviceModel) }()
        case 8: try { try decoder.decodeSingularStringField(value: &_storage._locale) }()
        case 9: try { try decoder.decodeSingularBytesField(value: &_storage._keyHandle) }()
        case 12: try { try decoder.decodeSingularInt64Field(value: &_storage._counter) }()
        case 13: try { try decoder.decodeSingularStringField(value: &_storage._deviceOsVersion) }()
        case 14: try { try decoder.decodeSingularInt64Field(value: &_storage._deviceOsVersionCode) }()
        case 15: try { try decoder.decodeSingularStringField(value: &_storage._deviceOsRelease) }()
        case 16: try { try decoder.decodeSingularStringField(value: &_storage._deviceOsCodename) }()
        case 17: try { try decoder.decodeSingularStringField(value: &_storage._deviceSoftwareVersion) }()
        case 18: try { try decoder.decodeSingularInt64Field(value: &_storage._deviceSoftwareVersionCode) }()
        case 19: try { try decoder.decodeSingularStringField(value: &_storage._deviceSoftwarePackage) }()
        case 22: try { try decoder.decodeSingularInt32Field(value: &_storage._deviceDisplayDiagonalMils) }()
        case 24: try { try decoder.decodeSingularInt32Field(value: &_storage._deviceAuthzenVersion) }()
        case 29: try { try decoder.decodeSingularBytesField(value: &_storage._longDeviceID) }()
        case 31: try { try decoder.decodeSingularStringField(value: &_storage._deviceManufacturer) }()
        case 32: try { try decoder.decodeSingularEnumField(value: &_storage._deviceType) }()
        case 102: try { try decoder.decodeSingularBytesField(value: &_storage._gcmRegistrationID) }()
        case 103: try { try decoder.decodeSingularBytesField(value: &_storage._deviceMasterKeyHash) }()
        case 202: try { try decoder.decodeSingularBytesField(value: &_storage._apnRegistrationID) }()
        case 203: try { try decoder.decodeSingularBoolField(value: &_storage._notificationEnabled) }()
        case 302: try { try decoder.decodeSingularStringField(value: &_storage._bluetoothMacAddress) }()
        case 400: try { try decoder.decodeSingularBoolField(value: &_storage._usingSecureScreenlock) }()
        case 401: try { try decoder.decodeSingularBoolField(value: &_storage._autoUnlockScreenlockSupported) }()
        case 402: try { try decoder.decodeSingularBoolField(value: &_storage._autoUnlockScreenlockEnabled) }()
        case 403: try { try decoder.decodeSingularBoolField(value: &_storage._bluetoothRadioSupported) }()
        case 404: try { try decoder.decodeSingularBoolField(value: &_storage._bluetoothRadioEnabled) }()
        case 405: try { try decoder.decodeSingularBoolField(value: &_storage._mobileDataSupported) }()
        case 406: try { try decoder.decodeSingularBoolField(value: &_storage._tetheringSupported) }()
        case 407: try { try decoder.decodeSingularBoolField(value: &_storage._bleRadioSupported) }()
        case 408: try { try decoder.decodeSingularBoolField(value: &_storage._pixelExperience) }()
        case 409: try { try decoder.decodeSingularBoolField(value: &_storage._arcPlusPlus) }()
        case 410: try { try decoder.decodeSingularBoolField(value: &_storage._isScreenlockStateFlaky) }()
        case 411: try { try decoder.decodeRepeatedEnumField(value: &_storage._supportedSoftwareFeatures) }()
        case 412: try { try decoder.decodeRepeatedEnumField(value: &_storage._enabledSoftwareFeatures) }()
        case 1000: try { try decoder.decodeSingularBytesField(value: &_storage._enrollmentSessionID) }()
        case 1001: try { try decoder.decodeSingularStringField(value: &_storage._oauthToken) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      try { if let v = _storage._androidDeviceID {
        try visitor.visitSingularFixed64Field(value: v, fieldNumber: 1)
      } }()
      try { if let v = _storage._userPublicKey {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 4)
      } }()
      try { if let v = _storage._deviceModel {
        try visitor.visitSingularStringField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._locale {
        try visitor.visitSingularStringField(value: v, fieldNumber: 8)
      } }()
      try { if let v = _storage._keyHandle {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 9)
      } }()
      try { if let v = _storage._counter {
        try visitor.visitSingularInt64Field(value: v, fieldNumber: 12)
      } }()
      try { if let v = _storage._deviceOsVersion {
        try visitor.visitSingularStringField(value: v, fieldNumber: 13)
      } }()
      try { if let v = _storage._deviceOsVersionCode {
        try visitor.visitSingularInt64Field(value: v, fieldNumber: 14)
      } }()
      try { if let v = _storage._deviceOsRelease {
        try visitor.visitSingularStringField(value: v, fieldNumber: 15)
      } }()
      try { if let v = _storage._deviceOsCodename {
        try visitor.visitSingularStringField(value: v, fieldNumber: 16)
      } }()
      try { if let v = _storage._deviceSoftwareVersion {
        try visitor.visitSingularStringField(value: v, fieldNumber: 17)
      } }()
      try { if let v = _storage._deviceSoftwareVersionCode {
        try visitor.visitSingularInt64Field(value: v, fieldNumber: 18)
      } }()
      try { if let v = _storage._deviceSoftwarePackage {
        try visitor.visitSingularStringField(value: v, fieldNumber: 19)
      } }()
      try { if let v = _storage._deviceDisplayDiagonalMils {
        try visitor.visitSingularInt32Field(value: v, fieldNumber: 22)
      } }()
      try { if let v = _storage._deviceAuthzenVersion {
        try visitor.visitSingularInt32Field(value: v, fieldNumber: 24)
      } }()
      try { if let v = _storage._longDeviceID {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 29)
      } }()
      try { if let v = _storage._deviceManufacturer {
        try visitor.visitSingularStringField(value: v, fieldNumber: 31)
      } }()
      try { if let v = _storage._deviceType {
        try visitor.visitSingularEnumField(value: v, fieldNumber: 32)
      } }()
      try { if let v = _storage._gcmRegistrationID {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 102)
      } }()
      try { if let v = _storage._deviceMasterKeyHash {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 103)
      } }()
      try { if let v = _storage._apnRegistrationID {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 202)
      } }()
      try { if let v = _storage._notificationEnabled {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 203)
      } }()
      try { if let v = _storage._bluetoothMacAddress {
        try visitor.visitSingularStringField(value: v, fieldNumber: 302)
      } }()
      try { if let v = _storage._usingSecureScreenlock {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 400)
      } }()
      try { if let v = _storage._autoUnlockScreenlockSupported {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 401)
      } }()
      try { if let v = _storage._autoUnlockScreenlockEnabled {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 402)
      } }()
      try { if let v = _storage._bluetoothRadioSupported {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 403)
      } }()
      try { if let v = _storage._bluetoothRadioEnabled {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 404)
      } }()
      try { if let v = _storage._mobileDataSupported {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 405)
      } }()
      try { if let v = _storage._tetheringSupported {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 406)
      } }()
      try { if let v = _storage._bleRadioSupported {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 407)
      } }()
      try { if let v = _storage._pixelExperience {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 408)
      } }()
      try { if let v = _storage._arcPlusPlus {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 409)
      } }()
      try { if let v = _storage._isScreenlockStateFlaky {
        try visitor.visitSingularBoolField(value: v, fieldNumber: 410)
      } }()
      if !_storage._supportedSoftwareFeatures.isEmpty {
        try visitor.visitRepeatedEnumField(value: _storage._supportedSoftwareFeatures, fieldNumber: 411)
      }
      if !_storage._enabledSoftwareFeatures.isEmpty {
        try visitor.visitRepeatedEnumField(value: _storage._enabledSoftwareFeatures, fieldNumber: 412)
      }
      try { if let v = _storage._enrollmentSessionID {
        try visitor.visitSingularBytesField(value: v, fieldNumber: 1000)
      } }()
      try { if let v = _storage._oauthToken {
        try visitor.visitSingularStringField(value: v, fieldNumber: 1001)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_GcmDeviceInfo, rhs: Securegcm_GcmDeviceInfo) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._androidDeviceID != rhs_storage._androidDeviceID {return false}
        if _storage._gcmRegistrationID != rhs_storage._gcmRegistrationID {return false}
        if _storage._apnRegistrationID != rhs_storage._apnRegistrationID {return false}
        if _storage._notificationEnabled != rhs_storage._notificationEnabled {return false}
        if _storage._bluetoothMacAddress != rhs_storage._bluetoothMacAddress {return false}
        if _storage._deviceMasterKeyHash != rhs_storage._deviceMasterKeyHash {return false}
        if _storage._userPublicKey != rhs_storage._userPublicKey {return false}
        if _storage._deviceModel != rhs_storage._deviceModel {return false}
        if _storage._locale != rhs_storage._locale {return false}
        if _storage._keyHandle != rhs_storage._keyHandle {return false}
        if _storage._counter != rhs_storage._counter {return false}
        if _storage._deviceOsVersion != rhs_storage._deviceOsVersion {return false}
        if _storage._deviceOsVersionCode != rhs_storage._deviceOsVersionCode {return false}
        if _storage._deviceOsRelease != rhs_storage._deviceOsRelease {return false}
        if _storage._deviceOsCodename != rhs_storage._deviceOsCodename {return false}
        if _storage._deviceSoftwareVersion != rhs_storage._deviceSoftwareVersion {return false}
        if _storage._deviceSoftwareVersionCode != rhs_storage._deviceSoftwareVersionCode {return false}
        if _storage._deviceSoftwarePackage != rhs_storage._deviceSoftwarePackage {return false}
        if _storage._deviceDisplayDiagonalMils != rhs_storage._deviceDisplayDiagonalMils {return false}
        if _storage._deviceAuthzenVersion != rhs_storage._deviceAuthzenVersion {return false}
        if _storage._longDeviceID != rhs_storage._longDeviceID {return false}
        if _storage._deviceManufacturer != rhs_storage._deviceManufacturer {return false}
        if _storage._deviceType != rhs_storage._deviceType {return false}
        if _storage._usingSecureScreenlock != rhs_storage._usingSecureScreenlock {return false}
        if _storage._autoUnlockScreenlockSupported != rhs_storage._autoUnlockScreenlockSupported {return false}
        if _storage._autoUnlockScreenlockEnabled != rhs_storage._autoUnlockScreenlockEnabled {return false}
        if _storage._bluetoothRadioSupported != rhs_storage._bluetoothRadioSupported {return false}
        if _storage._bluetoothRadioEnabled != rhs_storage._bluetoothRadioEnabled {return false}
        if _storage._mobileDataSupported != rhs_storage._mobileDataSupported {return false}
        if _storage._tetheringSupported != rhs_storage._tetheringSupported {return false}
        if _storage._bleRadioSupported != rhs_storage._bleRadioSupported {return false}
        if _storage._pixelExperience != rhs_storage._pixelExperience {return false}
        if _storage._arcPlusPlus != rhs_storage._arcPlusPlus {return false}
        if _storage._isScreenlockStateFlaky != rhs_storage._isScreenlockStateFlaky {return false}
        if _storage._supportedSoftwareFeatures != rhs_storage._supportedSoftwareFeatures {return false}
        if _storage._enabledSoftwareFeatures != rhs_storage._enabledSoftwareFeatures {return false}
        if _storage._enrollmentSessionID != rhs_storage._enrollmentSessionID {return false}
        if _storage._oauthToken != rhs_storage._oauthToken {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securegcm_GcmMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GcmMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "type"),
    2: .same(proto: "version"),
  ]

  public var isInitialized: Bool {
    if self._type == nil {return false}
    return true
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self._type) }()
      case 2: try { try decoder.decodeSingularInt32Field(value: &self._version) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._type {
      try visitor.visitSingularEnumField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._version {
      try visitor.visitSingularInt32Field(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_GcmMetadata, rhs: Securegcm_GcmMetadata) -> Bool {
    if lhs._type != rhs._type {return false}
    if lhs._version != rhs._version {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securegcm_Tickle: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Tickle"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "expiry_time"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularFixed64Field(value: &self._expiryTime) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._expiryTime {
      try visitor.visitSingularFixed64Field(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_Tickle, rhs: Securegcm_Tickle) -> Bool {
    if lhs._expiryTime != rhs._expiryTime {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Securegcm_LoginNotificationInfo: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".LoginNotificationInfo"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    2: .standard(proto: "creation_time"),
    3: .same(proto: "email"),
    4: .same(proto: "host"),
    5: .same(proto: "source"),
    6: .standard(proto: "event_type"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 2: try { try decoder.decodeSingularFixed64Field(value: &self._creationTime) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self._email) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self._host) }()
      case 5: try { try decoder.decodeSingularStringField(value: &self._source) }()
      case 6: try { try decoder.decodeSingularStringField(value: &self._eventType) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try { if let v = self._creationTime {
      try visitor.visitSingularFixed64Field(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._email {
      try visitor.visitSingularStringField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._host {
      try visitor.visitSingularStringField(value: v, fieldNumber: 4)
    } }()
    try { if let v = self._source {
      try visitor.visitSingularStringField(value: v, fieldNumber: 5)
    } }()
    try { if let v = self._eventType {
      try visitor.visitSingularStringField(value: v, fieldNumber: 6)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Securegcm_LoginNotificationInfo, rhs: Securegcm_LoginNotificationInfo) -> Bool {
    if lhs._creationTime != rhs._creationTime {return false}
    if lhs._email != rhs._email {return false}
    if lhs._host != rhs._host {return false}
    if lhs._source != rhs._source {return false}
    if lhs._eventType != rhs._eventType {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}