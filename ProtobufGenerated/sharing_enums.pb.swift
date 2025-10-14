//
//  sharing_enums.pb.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-30
//

import Foundation
import SwiftProtobuf

fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

enum Location_Nearby_Proto_Sharing_EventType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownEventType

  case acceptAgreements

  case enableNearbySharing

  case setVisibility

  case describeAttachments

  case scanForShareTargetsStart

  case scanForShareTargetsEnd

  case advertiseDevicePresenceStart

  case advertiseDevicePresenceEnd

  case sendFastInitialization

  case receiveFastInitialization

  case discoverShareTarget

  case sendIntroduction

  case receiveIntroduction

  case respondToIntroduction

  case sendAttachmentsStart

  case sendAttachmentsEnd

  case receiveAttachmentsStart

  case receiveAttachmentsEnd

  case cancelSendingAttachments

  case cancelReceivingAttachments

  case openReceivedAttachments

  case launchSetupActivity

  case addContact

  case removeContact

  case fastShareServerResponse

  case sendStart

  case acceptFastInitialization

  case setDataUsage

  case dismissFastInitialization

  case cancelConnection

  case launchActivity

  case dismissPrivacyNotification

  case tapPrivacyNotification

  case tapHelp

  case tapFeedback

  case addQuickSettingsTile

  case removeQuickSettingsTile

  case launchPhoneConsent

  case displayPhoneConsent

  case tapQuickSettingsTile

  case installApk

  case verifyApk

  case launchConsent

  case processReceivedAttachmentsEnd

  case toggleShowNotification

  case setDeviceName

  case declineAgreements

  case requestSettingPermissions

  case establishConnection

  case deviceSettings

  case autoDismissFastInitialization

  case appCrash

  case tapQuickSettingsFileShare

  case displayPrivacyNotification

  case preferencesUsage

  case defaultOptIn

  case setupWizard

  case tapQrCode

  case qrCodeLinkShown

  case parsingFailedEndpointID

  case fastInitDiscoverDevice

  case sendDesktopNotification

  case setAccount

  case decryptCertificateFailure

  case showAllowPermissionAutoAccess

  case sendDesktopTransferEvent

  case waitingForAccept

  case highQualityMediumSetup

  case rpcCallStatus

  case startQrCodeSession

  case qrCodeOpenedInWebClient

  case hatsJointEvent

  case receivePreviews

  init() {
    self = .unknownEventType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownEventType
    case 1: self = .acceptAgreements
    case 2: self = .enableNearbySharing
    case 3: self = .setVisibility
    case 4: self = .describeAttachments
    case 5: self = .scanForShareTargetsStart
    case 6: self = .scanForShareTargetsEnd
    case 7: self = .advertiseDevicePresenceStart
    case 8: self = .advertiseDevicePresenceEnd
    case 9: self = .sendFastInitialization
    case 10: self = .receiveFastInitialization
    case 11: self = .discoverShareTarget
    case 12: self = .sendIntroduction
    case 13: self = .receiveIntroduction
    case 14: self = .respondToIntroduction
    case 15: self = .sendAttachmentsStart
    case 16: self = .sendAttachmentsEnd
    case 17: self = .receiveAttachmentsStart
    case 18: self = .receiveAttachmentsEnd
    case 19: self = .cancelSendingAttachments
    case 20: self = .cancelReceivingAttachments
    case 21: self = .openReceivedAttachments
    case 22: self = .launchSetupActivity
    case 23: self = .addContact
    case 24: self = .removeContact
    case 25: self = .fastShareServerResponse
    case 26: self = .sendStart
    case 27: self = .acceptFastInitialization
    case 28: self = .setDataUsage
    case 29: self = .dismissFastInitialization
    case 30: self = .cancelConnection
    case 31: self = .launchActivity
    case 32: self = .dismissPrivacyNotification
    case 33: self = .tapPrivacyNotification
    case 34: self = .tapHelp
    case 35: self = .tapFeedback
    case 36: self = .addQuickSettingsTile
    case 37: self = .removeQuickSettingsTile
    case 38: self = .launchPhoneConsent
    case 39: self = .tapQuickSettingsTile
    case 40: self = .installApk
    case 41: self = .verifyApk
    case 42: self = .launchConsent
    case 43: self = .processReceivedAttachmentsEnd
    case 44: self = .toggleShowNotification
    case 45: self = .setDeviceName
    case 46: self = .declineAgreements
    case 47: self = .requestSettingPermissions
    case 48: self = .establishConnection
    case 49: self = .deviceSettings
    case 50: self = .autoDismissFastInitialization
    case 51: self = .appCrash
    case 52: self = .tapQuickSettingsFileShare
    case 53: self = .displayPrivacyNotification
    case 54: self = .displayPhoneConsent
    case 55: self = .preferencesUsage
    case 56: self = .defaultOptIn
    case 57: self = .setupWizard
    case 58: self = .tapQrCode
    case 59: self = .qrCodeLinkShown
    case 60: self = .parsingFailedEndpointID
    case 61: self = .fastInitDiscoverDevice
    case 62: self = .sendDesktopNotification
    case 63: self = .setAccount
    case 64: self = .decryptCertificateFailure
    case 65: self = .showAllowPermissionAutoAccess
    case 66: self = .sendDesktopTransferEvent
    case 67: self = .waitingForAccept
    case 68: self = .highQualityMediumSetup
    case 69: self = .rpcCallStatus
    case 70: self = .startQrCodeSession
    case 71: self = .qrCodeOpenedInWebClient
    case 72: self = .hatsJointEvent
    case 73: self = .receivePreviews
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownEventType: return 0
    case .acceptAgreements: return 1
    case .enableNearbySharing: return 2
    case .setVisibility: return 3
    case .describeAttachments: return 4
    case .scanForShareTargetsStart: return 5
    case .scanForShareTargetsEnd: return 6
    case .advertiseDevicePresenceStart: return 7
    case .advertiseDevicePresenceEnd: return 8
    case .sendFastInitialization: return 9
    case .receiveFastInitialization: return 10
    case .discoverShareTarget: return 11
    case .sendIntroduction: return 12
    case .receiveIntroduction: return 13
    case .respondToIntroduction: return 14
    case .sendAttachmentsStart: return 15
    case .sendAttachmentsEnd: return 16
    case .receiveAttachmentsStart: return 17
    case .receiveAttachmentsEnd: return 18
    case .cancelSendingAttachments: return 19
    case .cancelReceivingAttachments: return 20
    case .openReceivedAttachments: return 21
    case .launchSetupActivity: return 22
    case .addContact: return 23
    case .removeContact: return 24
    case .fastShareServerResponse: return 25
    case .sendStart: return 26
    case .acceptFastInitialization: return 27
    case .setDataUsage: return 28
    case .dismissFastInitialization: return 29
    case .cancelConnection: return 30
    case .launchActivity: return 31
    case .dismissPrivacyNotification: return 32
    case .tapPrivacyNotification: return 33
    case .tapHelp: return 34
    case .tapFeedback: return 35
    case .addQuickSettingsTile: return 36
    case .removeQuickSettingsTile: return 37
    case .launchPhoneConsent: return 38
    case .tapQuickSettingsTile: return 39
    case .installApk: return 40
    case .verifyApk: return 41
    case .launchConsent: return 42
    case .processReceivedAttachmentsEnd: return 43
    case .toggleShowNotification: return 44
    case .setDeviceName: return 45
    case .declineAgreements: return 46
    case .requestSettingPermissions: return 47
    case .establishConnection: return 48
    case .deviceSettings: return 49
    case .autoDismissFastInitialization: return 50
    case .appCrash: return 51
    case .tapQuickSettingsFileShare: return 52
    case .displayPrivacyNotification: return 53
    case .displayPhoneConsent: return 54
    case .preferencesUsage: return 55
    case .defaultOptIn: return 56
    case .setupWizard: return 57
    case .tapQrCode: return 58
    case .qrCodeLinkShown: return 59
    case .parsingFailedEndpointID: return 60
    case .fastInitDiscoverDevice: return 61
    case .sendDesktopNotification: return 62
    case .setAccount: return 63
    case .decryptCertificateFailure: return 64
    case .showAllowPermissionAutoAccess: return 65
    case .sendDesktopTransferEvent: return 66
    case .waitingForAccept: return 67
    case .highQualityMediumSetup: return 68
    case .rpcCallStatus: return 69
    case .startQrCodeSession: return 70
    case .qrCodeOpenedInWebClient: return 71
    case .hatsJointEvent: return 72
    case .receivePreviews: return 73
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_EventType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_EventCategory: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownEventCategory
  case sendingEvent
  case receivingEvent
  case settingsEvent
  case rpcEvent

  init() {
    self = .unknownEventCategory
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownEventCategory
    case 1: self = .sendingEvent
    case 2: self = .receivingEvent
    case 3: self = .settingsEvent
    case 4: self = .rpcEvent
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownEventCategory: return 0
    case .sendingEvent: return 1
    case .receivingEvent: return 2
    case .settingsEvent: return 3
    case .rpcEvent: return 4
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_EventCategory: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_NearbySharingStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownNearbySharingStatus
  case on
  case off

  init() {
    self = .unknownNearbySharingStatus
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownNearbySharingStatus
    case 1: self = .on
    case 2: self = .off
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownNearbySharingStatus: return 0
    case .on: return 1
    case .off: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_NearbySharingStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_Visibility: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownVisibility
  case contactsOnly
  case everyone
  case selectedContactsOnly
  case hidden
  case selfShare

  init() {
    self = .unknownVisibility
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownVisibility
    case 1: self = .contactsOnly
    case 2: self = .everyone
    case 3: self = .selectedContactsOnly
    case 4: self = .hidden
    case 5: self = .selfShare
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownVisibility: return 0
    case .contactsOnly: return 1
    case .everyone: return 2
    case .selectedContactsOnly: return 3
    case .hidden: return 4
    case .selfShare: return 5
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_Visibility: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_DataUsage: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownDataUsage
  case online
  case wifiOnly
  case offline

  init() {
    self = .unknownDataUsage
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownDataUsage
    case 1: self = .online
    case 2: self = .wifiOnly
    case 3: self = .offline
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownDataUsage: return 0
    case .online: return 1
    case .wifiOnly: return 2
    case .offline: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_DataUsage: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_EstablishConnectionStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case connectionStatusUnknown
  case connectionStatusSuccess
  case connectionStatusFailure
  case connectionStatusCancellation
  case connectionStatusMediaUnavailableAttachment
  case connectionStatusFailedPairedKeyhandshake
  case connectionStatusFailedWriteIntroduction
  case connectionStatusFailedNullConnection
  case connectionStatusFailedNoTransferUpdateCallback
  case connectionStatusLostConnectivity

  case connectionStatusInvalidAdvertisement

  init() {
    self = .connectionStatusUnknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .connectionStatusUnknown
    case 1: self = .connectionStatusSuccess
    case 2: self = .connectionStatusFailure
    case 3: self = .connectionStatusCancellation
    case 4: self = .connectionStatusMediaUnavailableAttachment
    case 5: self = .connectionStatusFailedPairedKeyhandshake
    case 6: self = .connectionStatusFailedWriteIntroduction
    case 7: self = .connectionStatusFailedNullConnection
    case 8: self = .connectionStatusFailedNoTransferUpdateCallback
    case 9: self = .connectionStatusLostConnectivity
    case 10: self = .connectionStatusInvalidAdvertisement
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .connectionStatusUnknown: return 0
    case .connectionStatusSuccess: return 1
    case .connectionStatusFailure: return 2
    case .connectionStatusCancellation: return 3
    case .connectionStatusMediaUnavailableAttachment: return 4
    case .connectionStatusFailedPairedKeyhandshake: return 5
    case .connectionStatusFailedWriteIntroduction: return 6
    case .connectionStatusFailedNullConnection: return 7
    case .connectionStatusFailedNoTransferUpdateCallback: return 8
    case .connectionStatusLostConnectivity: return 9
    case .connectionStatusInvalidAdvertisement: return 10
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_EstablishConnectionStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_AttachmentTransmissionStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownAttachmentTransmissionStatus
  case completeAttachmentTransmissionStatus
  case canceledAttachmentTransmissionStatus
  case failedAttachmentTransmissionStatus
  case rejectedAttachment
  case timedOutAttachment
  case awaitingRemoteAcceptanceFailedAttachment
  case notEnoughSpaceAttachment
  case failedNoTransferUpdateCallback
  case mediaUnavailableAttachment
  case unsupportedAttachmentTypeAttachment
  case noAttachmentFound
  case failedNoShareTargetEndpoint
  case failedPairedKeyhandshake
  case failedNullConnection
  case failedNoPayload
  case failedWriteIntroduction

  case failedUnknownRemoteResponse

  case failedNullConnectionInitOutgoing
  case failedNullConnectionDisconnected

  case failedNullConnectionLostConnectivity

  case failedNullConnectionFailure
  case rejectedAttachmentTransmissionStatus
  case timedOutAttachmentTransmissionStatus
  case notEnoughSpaceAttachmentTransmissionStatus
  case unsupportedAttachmentTypeAttachmentTransmissionStatus
  case failedUnknownRemoteResponseTransmissionStatus

  case noResponseFrameConnectionClosedLostConnectivityTransmissionStatus

  case noResponseFrameConnectionClosedTransmissionStatus

  case lostConnectivityTransmissionStatus

  case failedDisallowedMedium

  init() {
    self = .unknownAttachmentTransmissionStatus
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownAttachmentTransmissionStatus
    case 1: self = .completeAttachmentTransmissionStatus
    case 2: self = .canceledAttachmentTransmissionStatus
    case 3: self = .failedAttachmentTransmissionStatus
    case 4: self = .rejectedAttachment
    case 5: self = .timedOutAttachment
    case 6: self = .awaitingRemoteAcceptanceFailedAttachment
    case 7: self = .notEnoughSpaceAttachment
    case 8: self = .failedNoTransferUpdateCallback
    case 9: self = .mediaUnavailableAttachment
    case 10: self = .unsupportedAttachmentTypeAttachment
    case 11: self = .noAttachmentFound
    case 12: self = .failedNoShareTargetEndpoint
    case 13: self = .failedPairedKeyhandshake
    case 14: self = .failedNullConnection
    case 15: self = .failedNoPayload
    case 16: self = .failedWriteIntroduction
    case 17: self = .failedUnknownRemoteResponse
    case 18: self = .failedNullConnectionInitOutgoing
    case 19: self = .failedNullConnectionDisconnected
    case 20: self = .failedNullConnectionLostConnectivity
    case 21: self = .failedNullConnectionFailure
    case 22: self = .rejectedAttachmentTransmissionStatus
    case 23: self = .timedOutAttachmentTransmissionStatus
    case 24: self = .notEnoughSpaceAttachmentTransmissionStatus
    case 25: self = .unsupportedAttachmentTypeAttachmentTransmissionStatus
    case 26: self = .failedUnknownRemoteResponseTransmissionStatus
    case 27: self = .noResponseFrameConnectionClosedLostConnectivityTransmissionStatus
    case 28: self = .noResponseFrameConnectionClosedTransmissionStatus
    case 29: self = .lostConnectivityTransmissionStatus
    case 30: self = .failedDisallowedMedium
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownAttachmentTransmissionStatus: return 0
    case .completeAttachmentTransmissionStatus: return 1
    case .canceledAttachmentTransmissionStatus: return 2
    case .failedAttachmentTransmissionStatus: return 3
    case .rejectedAttachment: return 4
    case .timedOutAttachment: return 5
    case .awaitingRemoteAcceptanceFailedAttachment: return 6
    case .notEnoughSpaceAttachment: return 7
    case .failedNoTransferUpdateCallback: return 8
    case .mediaUnavailableAttachment: return 9
    case .unsupportedAttachmentTypeAttachment: return 10
    case .noAttachmentFound: return 11
    case .failedNoShareTargetEndpoint: return 12
    case .failedPairedKeyhandshake: return 13
    case .failedNullConnection: return 14
    case .failedNoPayload: return 15
    case .failedWriteIntroduction: return 16
    case .failedUnknownRemoteResponse: return 17
    case .failedNullConnectionInitOutgoing: return 18
    case .failedNullConnectionDisconnected: return 19
    case .failedNullConnectionLostConnectivity: return 20
    case .failedNullConnectionFailure: return 21
    case .rejectedAttachmentTransmissionStatus: return 22
    case .timedOutAttachmentTransmissionStatus: return 23
    case .notEnoughSpaceAttachmentTransmissionStatus: return 24
    case .unsupportedAttachmentTypeAttachmentTransmissionStatus: return 25
    case .failedUnknownRemoteResponseTransmissionStatus: return 26
    case .noResponseFrameConnectionClosedLostConnectivityTransmissionStatus: return 27
    case .noResponseFrameConnectionClosedTransmissionStatus: return 28
    case .lostConnectivityTransmissionStatus: return 29
    case .failedDisallowedMedium: return 30
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_AttachmentTransmissionStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ConnectionLayerStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int

  case unknown

  case success

  case error

  case outOfOrderApiCall

  case alreadyHaveActiveStrategy

  case alreadyAdvertising

  case alreadyDiscovering

  case alreadyListening

  case endPointIoError

  case endPointUnknown

  case connectionRejected

  case alreadyConnectedToEndPoint

  case notConnectedToEndPoint

  case bluetoothError

  case bleError

  case wifiLanError

  case payloadUnknown

  case reset

  case timeout

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .success
    case 2: self = .error
    case 3: self = .outOfOrderApiCall
    case 4: self = .alreadyHaveActiveStrategy
    case 5: self = .alreadyAdvertising
    case 6: self = .alreadyDiscovering
    case 7: self = .alreadyListening
    case 8: self = .endPointIoError
    case 9: self = .endPointUnknown
    case 10: self = .connectionRejected
    case 11: self = .alreadyConnectedToEndPoint
    case 12: self = .notConnectedToEndPoint
    case 13: self = .bluetoothError
    case 14: self = .bleError
    case 15: self = .wifiLanError
    case 16: self = .payloadUnknown
    case 17: self = .reset
    case 18: self = .timeout
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .success: return 1
    case .error: return 2
    case .outOfOrderApiCall: return 3
    case .alreadyHaveActiveStrategy: return 4
    case .alreadyAdvertising: return 5
    case .alreadyDiscovering: return 6
    case .alreadyListening: return 7
    case .endPointIoError: return 8
    case .endPointUnknown: return 9
    case .connectionRejected: return 10
    case .alreadyConnectedToEndPoint: return 11
    case .notConnectedToEndPoint: return 12
    case .bluetoothError: return 13
    case .bleError: return 14
    case .wifiLanError: return 15
    case .payloadUnknown: return 16
    case .reset: return 17
    case .timeout: return 18
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ConnectionLayerStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ProcessReceivedAttachmentsStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case processingStatusUnknown
  case processingStatusCompleteProcessingAttachments
  case processingStatusFailedMovingFiles
  case processingStatusFailedReceivingApk
  case processingStatusFailedReceivingText
  case processingStatusFailedReceivingWifiCredentials

  init() {
    self = .processingStatusUnknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .processingStatusUnknown
    case 1: self = .processingStatusCompleteProcessingAttachments
    case 2: self = .processingStatusFailedMovingFiles
    case 3: self = .processingStatusFailedReceivingApk
    case 4: self = .processingStatusFailedReceivingText
    case 5: self = .processingStatusFailedReceivingWifiCredentials
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .processingStatusUnknown: return 0
    case .processingStatusCompleteProcessingAttachments: return 1
    case .processingStatusFailedMovingFiles: return 2
    case .processingStatusFailedReceivingApk: return 3
    case .processingStatusFailedReceivingText: return 4
    case .processingStatusFailedReceivingWifiCredentials: return 5
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ProcessReceivedAttachmentsStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_SessionStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownSessionStatus
  case succeededSessionStatus

  case failedSessionStatus

  init() {
    self = .unknownSessionStatus
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownSessionStatus
    case 1: self = .succeededSessionStatus
    case 2: self = .failedSessionStatus
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownSessionStatus: return 0
    case .succeededSessionStatus: return 1
    case .failedSessionStatus: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_SessionStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ResponseToIntroduction: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownResponseToIntroduction
  case acceptIntroduction
  case rejectIntroduction
  case failIntroduction

  init() {
    self = .unknownResponseToIntroduction
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownResponseToIntroduction
    case 1: self = .acceptIntroduction
    case 2: self = .rejectIntroduction
    case 3: self = .failIntroduction
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownResponseToIntroduction: return 0
    case .acceptIntroduction: return 1
    case .rejectIntroduction: return 2
    case .failIntroduction: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ResponseToIntroduction: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_DeviceType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownDeviceType
  case phone
  case tablet
  case laptop
  case car
  case foldable
  case xr

  init() {
    self = .unknownDeviceType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownDeviceType
    case 1: self = .phone
    case 2: self = .tablet
    case 3: self = .laptop
    case 4: self = .car
    case 5: self = .foldable
    case 6: self = .xr
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownDeviceType: return 0
    case .phone: return 1
    case .tablet: return 2
    case .laptop: return 3
    case .car: return 4
    case .foldable: return 5
    case .xr: return 6
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_DeviceType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_OSType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownOsType
  case android
  case chromeOs
  case ios
  case windows
  case macos

  init() {
    self = .unknownOsType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownOsType
    case 1: self = .android
    case 2: self = .chromeOs
    case 3: self = .ios
    case 4: self = .windows
    case 5: self = .macos
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownOsType: return 0
    case .android: return 1
    case .chromeOs: return 2
    case .ios: return 3
    case .windows: return 4
    case .macos: return 5
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_OSType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_DeviceRelationship: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownDeviceRelationship

  case isSelf

  case isContact

  case isStranger

  init() {
    self = .unknownDeviceRelationship
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownDeviceRelationship
    case 1: self = .isSelf
    case 2: self = .isContact
    case 3: self = .isStranger
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownDeviceRelationship: return 0
    case .isSelf: return 1
    case .isContact: return 2
    case .isStranger: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_DeviceRelationship: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_LogSource: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unspecifiedSource

  case labDevices

  case internalDevices

  case betaTesterDevices

  case oemDevices

  case debugDevices

  case nearbyModuleFoodDevices

  case betoDogfoodDevices

  case nearbyDogfoodDevices

  case nearbyTeamfoodDevices

  init() {
    self = .unspecifiedSource
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unspecifiedSource
    case 1: self = .labDevices
    case 2: self = .internalDevices
    case 3: self = .betaTesterDevices
    case 4: self = .oemDevices
    case 5: self = .debugDevices
    case 6: self = .nearbyModuleFoodDevices
    case 7: self = .betoDogfoodDevices
    case 8: self = .nearbyDogfoodDevices
    case 9: self = .nearbyTeamfoodDevices
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unspecifiedSource: return 0
    case .labDevices: return 1
    case .internalDevices: return 2
    case .betaTesterDevices: return 3
    case .oemDevices: return 4
    case .debugDevices: return 5
    case .nearbyModuleFoodDevices: return 6
    case .betoDogfoodDevices: return 7
    case .nearbyDogfoodDevices: return 8
    case .nearbyTeamfoodDevices: return 9
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_LogSource: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ServerActionName: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownServerAction
  case uploadCertificates
  case downloadCertificates
  case checkReachability
  case uploadContacts
  case updateDeviceName
  case uploadSenderCertificates
  case downloadSenderCertificates
  case uploadContactsAndCertificates
  case listReachablePhoneNumbers
  case listMyDevices
  case listContactPeople

  case downloadCertificatesInfo

  init() {
    self = .unknownServerAction
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownServerAction
    case 1: self = .uploadCertificates
    case 2: self = .downloadCertificates
    case 3: self = .checkReachability
    case 4: self = .uploadContacts
    case 5: self = .updateDeviceName
    case 6: self = .uploadSenderCertificates
    case 7: self = .downloadSenderCertificates
    case 8: self = .uploadContactsAndCertificates
    case 9: self = .listReachablePhoneNumbers
    case 10: self = .listMyDevices
    case 11: self = .listContactPeople
    case 12: self = .downloadCertificatesInfo
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownServerAction: return 0
    case .uploadCertificates: return 1
    case .downloadCertificates: return 2
    case .checkReachability: return 3
    case .uploadContacts: return 4
    case .updateDeviceName: return 5
    case .uploadSenderCertificates: return 6
    case .downloadSenderCertificates: return 7
    case .uploadContactsAndCertificates: return 8
    case .listReachablePhoneNumbers: return 9
    case .listMyDevices: return 10
    case .listContactPeople: return 11
    case .downloadCertificatesInfo: return 12
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ServerActionName: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ServerResponseState: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownServerResponseState
  case serverResponseSuccess
  case serverResponseUnknownFailure

  case serverResponseStatusOtherFailure
  case serverResponseStatusDeadlineExceeded
  case serverResponseStatusPermissionDenied
  case serverResponseStatusUnavailable
  case serverResponseStatusUnauthenticated
  case serverResponseStatusInvalidArgument

  case serverResponseGoogleAuthFailure

  case serverResponseNotConnectedToInternet

  init() {
    self = .unknownServerResponseState
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownServerResponseState
    case 1: self = .serverResponseSuccess
    case 2: self = .serverResponseUnknownFailure
    case 3: self = .serverResponseStatusOtherFailure
    case 4: self = .serverResponseStatusDeadlineExceeded
    case 5: self = .serverResponseStatusPermissionDenied
    case 6: self = .serverResponseStatusUnavailable
    case 7: self = .serverResponseStatusUnauthenticated
    case 8: self = .serverResponseGoogleAuthFailure
    case 9: self = .serverResponseStatusInvalidArgument
    case 10: self = .serverResponseNotConnectedToInternet
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownServerResponseState: return 0
    case .serverResponseSuccess: return 1
    case .serverResponseUnknownFailure: return 2
    case .serverResponseStatusOtherFailure: return 3
    case .serverResponseStatusDeadlineExceeded: return 4
    case .serverResponseStatusPermissionDenied: return 5
    case .serverResponseStatusUnavailable: return 6
    case .serverResponseStatusUnauthenticated: return 7
    case .serverResponseGoogleAuthFailure: return 8
    case .serverResponseStatusInvalidArgument: return 9
    case .serverResponseNotConnectedToInternet: return 10
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ServerResponseState: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_SyncPurpose: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown

  case onDemandSync

  case chimeNotification

  case dailySync

  case optInFirstSync

  case checkDefaultOptIn

  case nearbyShareEnabled

  case syncAtFastInit

  case syncAtDiscovery

  case syncAtLoadPrivateCertificate

  case syncAtAdvertisement

  case contactListChange

  case showC11NView

  case regularCheckContactReachability

  case visibilitySelectedContactChange

  case accountChange

  case regenerateCertificates

  case deviceContactsConsentChange

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .onDemandSync
    case 2: self = .chimeNotification
    case 3: self = .dailySync
    case 4: self = .optInFirstSync
    case 5: self = .checkDefaultOptIn
    case 6: self = .nearbyShareEnabled
    case 7: self = .syncAtFastInit
    case 8: self = .syncAtDiscovery
    case 9: self = .syncAtLoadPrivateCertificate
    case 10: self = .syncAtAdvertisement
    case 11: self = .contactListChange
    case 12: self = .showC11NView
    case 13: self = .regularCheckContactReachability
    case 14: self = .visibilitySelectedContactChange
    case 15: self = .accountChange
    case 16: self = .regenerateCertificates
    case 17: self = .deviceContactsConsentChange
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .onDemandSync: return 1
    case .chimeNotification: return 2
    case .dailySync: return 3
    case .optInFirstSync: return 4
    case .checkDefaultOptIn: return 5
    case .nearbyShareEnabled: return 6
    case .syncAtFastInit: return 7
    case .syncAtDiscovery: return 8
    case .syncAtLoadPrivateCertificate: return 9
    case .syncAtAdvertisement: return 10
    case .contactListChange: return 11
    case .showC11NView: return 12
    case .regularCheckContactReachability: return 13
    case .visibilitySelectedContactChange: return 14
    case .accountChange: return 15
    case .regenerateCertificates: return 16
    case .deviceContactsConsentChange: return 17
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_SyncPurpose: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ClientRole: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case sender
  case receiver

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .sender
    case 2: self = .receiver
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .sender: return 1
    case .receiver: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ClientRole: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ScanType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownScanType
  case foregroundScan
  case foregroundRetryScan
  case directShareScan
  case backgroundScan

  init() {
    self = .unknownScanType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownScanType
    case 1: self = .foregroundScan
    case 2: self = .foregroundRetryScan
    case 3: self = .directShareScan
    case 4: self = .backgroundScan
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownScanType: return 0
    case .foregroundScan: return 1
    case .foregroundRetryScan: return 2
    case .directShareScan: return 3
    case .backgroundScan: return 4
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ScanType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ParsingFailedType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case failedUnknownType

  case failedParseAdvertisement

  case failedConvertShareTarget

  init() {
    self = .failedUnknownType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .failedUnknownType
    case 1: self = .failedParseAdvertisement
    case 2: self = .failedConvertShareTarget
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .failedUnknownType: return 0
    case .failedParseAdvertisement: return 1
    case .failedConvertShareTarget: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ParsingFailedType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_AdvertisingMode: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownAdvertisingMode
  case screenOffAdvertisingMode
  case backgroundAdvertisingMode
  case midgroundAdvertisingMode
  case foregroundAdvertisingMode
  case suspendedAdvertisingMode

  init() {
    self = .unknownAdvertisingMode
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownAdvertisingMode
    case 1: self = .screenOffAdvertisingMode
    case 2: self = .backgroundAdvertisingMode
    case 3: self = .midgroundAdvertisingMode
    case 4: self = .foregroundAdvertisingMode
    case 5: self = .suspendedAdvertisingMode
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownAdvertisingMode: return 0
    case .screenOffAdvertisingMode: return 1
    case .backgroundAdvertisingMode: return 2
    case .midgroundAdvertisingMode: return 3
    case .foregroundAdvertisingMode: return 4
    case .suspendedAdvertisingMode: return 5
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_AdvertisingMode: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_DiscoveryMode: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownDiscoveryMode
  case screenOffDiscoveryMode
  case backgroundDiscoveryMode
  case midgroundDiscoveryMode
  case foregroundDiscoveryMode
  case suspendedDiscoveryMode

  init() {
    self = .unknownDiscoveryMode
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownDiscoveryMode
    case 1: self = .screenOffDiscoveryMode
    case 2: self = .backgroundDiscoveryMode
    case 3: self = .midgroundDiscoveryMode
    case 4: self = .foregroundDiscoveryMode
    case 5: self = .suspendedDiscoveryMode
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownDiscoveryMode: return 0
    case .screenOffDiscoveryMode: return 1
    case .backgroundDiscoveryMode: return 2
    case .midgroundDiscoveryMode: return 3
    case .foregroundDiscoveryMode: return 4
    case .suspendedDiscoveryMode: return 5
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_DiscoveryMode: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ActivityName: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownActivity
  case shareSheetActivity
  case settingsActivity
  case receiveSurfaceActivity
  case setupActivity
  case deviceVisibilityActivity
  case consentsActivity
  case setDeviceNameDialog
  case setDataUsageDialog
  case quickSettingsActivity
  case remoteCopyShareSheetActivity
  case setupWizardActivity
  case settingsReviewActivity

  init() {
    self = .unknownActivity
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownActivity
    case 1: self = .shareSheetActivity
    case 2: self = .settingsActivity
    case 3: self = .receiveSurfaceActivity
    case 4: self = .setupActivity
    case 5: self = .deviceVisibilityActivity
    case 6: self = .consentsActivity
    case 7: self = .setDeviceNameDialog
    case 8: self = .setDataUsageDialog
    case 9: self = .quickSettingsActivity
    case 10: self = .remoteCopyShareSheetActivity
    case 11: self = .setupWizardActivity
    case 12: self = .settingsReviewActivity
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownActivity: return 0
    case .shareSheetActivity: return 1
    case .settingsActivity: return 2
    case .receiveSurfaceActivity: return 3
    case .setupActivity: return 4
    case .deviceVisibilityActivity: return 5
    case .consentsActivity: return 6
    case .setDeviceNameDialog: return 7
    case .setDataUsageDialog: return 8
    case .quickSettingsActivity: return 9
    case .remoteCopyShareSheetActivity: return 10
    case .setupWizardActivity: return 11
    case .settingsReviewActivity: return 12
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ActivityName: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ConsentType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown

  case c11N

  case deviceContact

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .c11N
    case 2: self = .deviceContact
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .c11N: return 1
    case .deviceContact: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ConsentType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ConsentAcceptanceStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case consentUnknownAcceptStatus
  case consentAccepted
  case consentDeclined

  case consentUnableToEnable

  init() {
    self = .consentUnknownAcceptStatus
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .consentUnknownAcceptStatus
    case 1: self = .consentAccepted
    case 2: self = .consentDeclined
    case 3: self = .consentUnableToEnable
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .consentUnknownAcceptStatus: return 0
    case .consentAccepted: return 1
    case .consentDeclined: return 2
    case .consentUnableToEnable: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ConsentAcceptanceStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ApkSource: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownApkSource
  case apkFromSdCard
  case installedApp

  init() {
    self = .unknownApkSource
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownApkSource
    case 1: self = .apkFromSdCard
    case 2: self = .installedApp
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownApkSource: return 0
    case .apkFromSdCard: return 1
    case .installedApp: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ApkSource: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_InstallAPKStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownInstallApkStatus
  case failInstallation
  case successInstallation

  init() {
    self = .unknownInstallApkStatus
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownInstallApkStatus
    case 1: self = .failInstallation
    case 2: self = .successInstallation
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownInstallApkStatus: return 0
    case .failInstallation: return 1
    case .successInstallation: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_InstallAPKStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_VerifyAPKStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownVerifyApkStatus
  case notInstallable
  case installable
  case alreadyInstalled

  init() {
    self = .unknownVerifyApkStatus
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownVerifyApkStatus
    case 1: self = .notInstallable
    case 2: self = .installable
    case 3: self = .alreadyInstalled
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownVerifyApkStatus: return 0
    case .notInstallable: return 1
    case .installable: return 2
    case .alreadyInstalled: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_VerifyAPKStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ShowNotificationStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknownShowNotificationStatus
  case show
  case notShow

  init() {
    self = .unknownShowNotificationStatus
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknownShowNotificationStatus
    case 1: self = .show
    case 2: self = .notShow
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknownShowNotificationStatus: return 0
    case .show: return 1
    case .notShow: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ShowNotificationStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_PermissionRequestResult: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case permissionUnknownRequestResult
  case permissionGranted
  case permissionRejected
  case permissionUnableToGrant

  init() {
    self = .permissionUnknownRequestResult
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .permissionUnknownRequestResult
    case 1: self = .permissionGranted
    case 2: self = .permissionRejected
    case 3: self = .permissionUnableToGrant
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .permissionUnknownRequestResult: return 0
    case .permissionGranted: return 1
    case .permissionRejected: return 2
    case .permissionUnableToGrant: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_PermissionRequestResult: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_PermissionRequestType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case permissionUnknownType
  case permissionAirplaneModeOff
  case permissionWifi
  case permissionBluetooth
  case permissionLocation
  case permissionWifiHotspot

  init() {
    self = .permissionUnknownType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .permissionUnknownType
    case 1: self = .permissionAirplaneModeOff
    case 2: self = .permissionWifi
    case 3: self = .permissionBluetooth
    case 4: self = .permissionLocation
    case 5: self = .permissionWifiHotspot
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .permissionUnknownType: return 0
    case .permissionAirplaneModeOff: return 1
    case .permissionWifi: return 2
    case .permissionBluetooth: return 3
    case .permissionLocation: return 4
    case .permissionWifiHotspot: return 5
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_PermissionRequestType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_SharingUseCase: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case useCaseUnknown
  case useCaseNearbyShare
  case useCaseRemoteCopyPaste
  case useCaseWifiCredential
  case useCaseAppShare
  case useCaseQuickSettingFileShare
  case useCaseSetupWizard

  case useCaseNearbyShareWithQrCode

  case useCaseRedirectedFromBluetoothShare

  init() {
    self = .useCaseUnknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .useCaseUnknown
    case 1: self = .useCaseNearbyShare
    case 2: self = .useCaseRemoteCopyPaste
    case 3: self = .useCaseWifiCredential
    case 4: self = .useCaseAppShare
    case 5: self = .useCaseQuickSettingFileShare
    case 6: self = .useCaseSetupWizard
    case 7: self = .useCaseNearbyShareWithQrCode
    case 8: self = .useCaseRedirectedFromBluetoothShare
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .useCaseUnknown: return 0
    case .useCaseNearbyShare: return 1
    case .useCaseRemoteCopyPaste: return 2
    case .useCaseWifiCredential: return 3
    case .useCaseAppShare: return 4
    case .useCaseQuickSettingFileShare: return 5
    case .useCaseSetupWizard: return 6
    case .useCaseNearbyShareWithQrCode: return 7
    case .useCaseRedirectedFromBluetoothShare: return 8
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_SharingUseCase: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_AppCrashReason: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_AppCrashReason: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_AttachmentSourceType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case attachmentSourceUnknown
  case attachmentSourceContextMenu
  case attachmentSourceDragAndDrop
  case attachmentSourceSelectFilesButton
  case attachmentSourcePaste
  case attachmentSourceSelectFoldersButton
  case attachmentSourceShareActivation

  init() {
    self = .attachmentSourceUnknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .attachmentSourceUnknown
    case 1: self = .attachmentSourceContextMenu
    case 2: self = .attachmentSourceDragAndDrop
    case 3: self = .attachmentSourceSelectFilesButton
    case 4: self = .attachmentSourcePaste
    case 5: self = .attachmentSourceSelectFoldersButton
    case 6: self = .attachmentSourceShareActivation
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .attachmentSourceUnknown: return 0
    case .attachmentSourceContextMenu: return 1
    case .attachmentSourceDragAndDrop: return 2
    case .attachmentSourceSelectFilesButton: return 3
    case .attachmentSourcePaste: return 4
    case .attachmentSourceSelectFoldersButton: return 5
    case .attachmentSourceShareActivation: return 6
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_AttachmentSourceType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_PreferencesAction: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case noAction

  case loadPreferences
  case savePreferencess
  case attemptLoad
  case restoreFromBackup

  case createPreferencesPath
  case makePreferencesBackupFile
  case checkIfPreferencesPathExists
  case checkIfPreferencesInputStreamStatus
  case checkIfPreferencesFileIsCorrupted
  case checkIfPreferencesBackupFileExists

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .noAction
    case 2: self = .loadPreferences
    case 3: self = .savePreferencess
    case 4: self = .attemptLoad
    case 5: self = .restoreFromBackup
    case 6: self = .createPreferencesPath
    case 7: self = .makePreferencesBackupFile
    case 8: self = .checkIfPreferencesPathExists
    case 9: self = .checkIfPreferencesInputStreamStatus
    case 10: self = .checkIfPreferencesFileIsCorrupted
    case 11: self = .checkIfPreferencesBackupFileExists
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .noAction: return 1
    case .loadPreferences: return 2
    case .savePreferencess: return 3
    case .attemptLoad: return 4
    case .restoreFromBackup: return 5
    case .createPreferencesPath: return 6
    case .makePreferencesBackupFile: return 7
    case .checkIfPreferencesPathExists: return 8
    case .checkIfPreferencesInputStreamStatus: return 9
    case .checkIfPreferencesFileIsCorrupted: return 10
    case .checkIfPreferencesBackupFileExists: return 11
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_PreferencesAction: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_PreferencesActionStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case success
  case fail

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .success
    case 2: self = .fail
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .success: return 1
    case .fail: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_PreferencesActionStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_FastInitState: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case fastInitUnknownState

  case fastInitCloseState

  case fastInitFarState

  case fastInitLostState

  init() {
    self = .fastInitUnknownState
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .fastInitUnknownState
    case 1: self = .fastInitCloseState
    case 2: self = .fastInitFarState
    case 3: self = .fastInitLostState
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .fastInitUnknownState: return 0
    case .fastInitCloseState: return 1
    case .fastInitFarState: return 2
    case .fastInitLostState: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_FastInitState: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_FastInitType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case fastInitUnknownType

  case fastInitNotifyType

  case fastInitSilentType

  init() {
    self = .fastInitUnknownType
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .fastInitUnknownType
    case 1: self = .fastInitNotifyType
    case 2: self = .fastInitSilentType
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .fastInitUnknownType: return 0
    case .fastInitNotifyType: return 1
    case .fastInitSilentType: return 2
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_FastInitType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_DesktopNotification: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case connecting
  case progress
  case accept
  case received
  case error

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .connecting
    case 2: self = .progress
    case 3: self = .accept
    case 4: self = .received
    case 5: self = .error
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .connecting: return 1
    case .progress: return 2
    case .accept: return 3
    case .received: return 4
    case .error: return 5
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_DesktopNotification: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_DesktopTransferEventType: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown

  case desktopTransferEventReceiveTypeAccept
  case desktopTransferEventReceiveTypeProgress
  case desktopTransferEventReceiveTypeReceived
  case desktopTransferEventReceiveTypeError

  case desktopTransferEventSendTypeStart
  case desktopTransferEventSendTypeSelectADevice
  case desktopTransferEventSendTypeProgress
  case desktopTransferEventSendTypeSent
  case desktopTransferEventSendTypeError

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .desktopTransferEventReceiveTypeAccept
    case 2: self = .desktopTransferEventReceiveTypeProgress
    case 3: self = .desktopTransferEventReceiveTypeReceived
    case 4: self = .desktopTransferEventReceiveTypeError
    case 5: self = .desktopTransferEventSendTypeStart
    case 6: self = .desktopTransferEventSendTypeSelectADevice
    case 7: self = .desktopTransferEventSendTypeProgress
    case 8: self = .desktopTransferEventSendTypeSent
    case 9: self = .desktopTransferEventSendTypeError
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .desktopTransferEventReceiveTypeAccept: return 1
    case .desktopTransferEventReceiveTypeProgress: return 2
    case .desktopTransferEventReceiveTypeReceived: return 3
    case .desktopTransferEventReceiveTypeError: return 4
    case .desktopTransferEventSendTypeStart: return 5
    case .desktopTransferEventSendTypeSelectADevice: return 6
    case .desktopTransferEventSendTypeProgress: return 7
    case .desktopTransferEventSendTypeSent: return 8
    case .desktopTransferEventSendTypeError: return 9
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_DesktopTransferEventType: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_DecryptCertificateFailureStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case decryptCertUnknownFailure
  case decryptCertNoSuchAlgorithmFailure
  case decryptCertNoSuchPaddingFailure
  case decryptCertInvalidKeyFailure
  case decryptCertInvalidAlgorithmParameterFailure
  case decryptCertIllegalBlockSizeFailure
  case decryptCertBadPaddingFailure

  init() {
    self = .decryptCertUnknownFailure
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .decryptCertUnknownFailure
    case 1: self = .decryptCertNoSuchAlgorithmFailure
    case 2: self = .decryptCertNoSuchPaddingFailure
    case 3: self = .decryptCertInvalidKeyFailure
    case 4: self = .decryptCertInvalidAlgorithmParameterFailure
    case 5: self = .decryptCertIllegalBlockSizeFailure
    case 6: self = .decryptCertBadPaddingFailure
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .decryptCertUnknownFailure: return 0
    case .decryptCertNoSuchAlgorithmFailure: return 1
    case .decryptCertNoSuchPaddingFailure: return 2
    case .decryptCertInvalidKeyFailure: return 3
    case .decryptCertInvalidAlgorithmParameterFailure: return 4
    case .decryptCertIllegalBlockSizeFailure: return 5
    case .decryptCertBadPaddingFailure: return 6
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_DecryptCertificateFailureStatus: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ContactAccess: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case noContactUploaded
  case onlyUploadGoogleContact
  case uploadContactForDeviceContactConsent
  case uploadContactForQuickShareConsent

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .noContactUploaded
    case 2: self = .onlyUploadGoogleContact
    case 3: self = .uploadContactForDeviceContactConsent
    case 4: self = .uploadContactForQuickShareConsent
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .noContactUploaded: return 1
    case .onlyUploadGoogleContact: return 2
    case .uploadContactForDeviceContactConsent: return 3
    case .uploadContactForQuickShareConsent: return 4
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ContactAccess: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_IdentityVerification: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case noPhoneNumberVerified
  case phoneNumberVerifiedNotLinkedToGaia
  case phoneNumberVerifiedLinkedToQsGaia

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .noPhoneNumberVerified
    case 2: self = .phoneNumberVerifiedNotLinkedToGaia
    case 3: self = .phoneNumberVerifiedLinkedToQsGaia
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .noPhoneNumberVerified: return 1
    case .phoneNumberVerifiedNotLinkedToGaia: return 2
    case .phoneNumberVerifiedLinkedToQsGaia: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_IdentityVerification: CaseIterable {
}

#endif

enum Location_Nearby_Proto_Sharing_ButtonStatus: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case unknown
  case clickAccept
  case clickReject
  case ignore

  init() {
    self = .unknown
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .clickAccept
    case 2: self = .clickReject
    case 3: self = .ignore
    default: return nil
    }
  }

  var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .clickAccept: return 1
    case .clickReject: return 2
    case .ignore: return 3
    }
  }

}

#if swift(>=4.2)

extension Location_Nearby_Proto_Sharing_ButtonStatus: CaseIterable {
}

#endif

#if swift(>=5.5) && canImport(_Concurrency)
extension Location_Nearby_Proto_Sharing_EventType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_EventCategory: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_NearbySharingStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_Visibility: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_DataUsage: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_EstablishConnectionStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_AttachmentTransmissionStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ConnectionLayerStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ProcessReceivedAttachmentsStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_SessionStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ResponseToIntroduction: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_DeviceType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_OSType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_DeviceRelationship: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_LogSource: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ServerActionName: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ServerResponseState: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_SyncPurpose: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ClientRole: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ScanType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ParsingFailedType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_AdvertisingMode: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_DiscoveryMode: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ActivityName: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ConsentType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ConsentAcceptanceStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ApkSource: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_InstallAPKStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_VerifyAPKStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ShowNotificationStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_PermissionRequestResult: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_PermissionRequestType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_SharingUseCase: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_AppCrashReason: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_AttachmentSourceType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_PreferencesAction: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_PreferencesActionStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_FastInitState: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_FastInitType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_DesktopNotification: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_DesktopTransferEventType: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_DecryptCertificateFailureStatus: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ContactAccess: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_IdentityVerification: @unchecked Sendable {}
extension Location_Nearby_Proto_Sharing_ButtonStatus: @unchecked Sendable {}
#endif

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Location_Nearby_Proto_Sharing_EventType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_EVENT_TYPE"),
    1: .same(proto: "ACCEPT_AGREEMENTS"),
    2: .same(proto: "ENABLE_NEARBY_SHARING"),
    3: .same(proto: "SET_VISIBILITY"),
    4: .same(proto: "DESCRIBE_ATTACHMENTS"),
    5: .same(proto: "SCAN_FOR_SHARE_TARGETS_START"),
    6: .same(proto: "SCAN_FOR_SHARE_TARGETS_END"),
    7: .same(proto: "ADVERTISE_DEVICE_PRESENCE_START"),
    8: .same(proto: "ADVERTISE_DEVICE_PRESENCE_END"),
    9: .same(proto: "SEND_FAST_INITIALIZATION"),
    10: .same(proto: "RECEIVE_FAST_INITIALIZATION"),
    11: .same(proto: "DISCOVER_SHARE_TARGET"),
    12: .same(proto: "SEND_INTRODUCTION"),
    13: .same(proto: "RECEIVE_INTRODUCTION"),
    14: .same(proto: "RESPOND_TO_INTRODUCTION"),
    15: .same(proto: "SEND_ATTACHMENTS_START"),
    16: .same(proto: "SEND_ATTACHMENTS_END"),
    17: .same(proto: "RECEIVE_ATTACHMENTS_START"),
    18: .same(proto: "RECEIVE_ATTACHMENTS_END"),
    19: .same(proto: "CANCEL_SENDING_ATTACHMENTS"),
    20: .same(proto: "CANCEL_RECEIVING_ATTACHMENTS"),
    21: .same(proto: "OPEN_RECEIVED_ATTACHMENTS"),
    22: .same(proto: "LAUNCH_SETUP_ACTIVITY"),
    23: .same(proto: "ADD_CONTACT"),
    24: .same(proto: "REMOVE_CONTACT"),
    25: .same(proto: "FAST_SHARE_SERVER_RESPONSE"),
    26: .same(proto: "SEND_START"),
    27: .same(proto: "ACCEPT_FAST_INITIALIZATION"),
    28: .same(proto: "SET_DATA_USAGE"),
    29: .same(proto: "DISMISS_FAST_INITIALIZATION"),
    30: .same(proto: "CANCEL_CONNECTION"),
    31: .same(proto: "LAUNCH_ACTIVITY"),
    32: .same(proto: "DISMISS_PRIVACY_NOTIFICATION"),
    33: .same(proto: "TAP_PRIVACY_NOTIFICATION"),
    34: .same(proto: "TAP_HELP"),
    35: .same(proto: "TAP_FEEDBACK"),
    36: .same(proto: "ADD_QUICK_SETTINGS_TILE"),
    37: .same(proto: "REMOVE_QUICK_SETTINGS_TILE"),
    38: .same(proto: "LAUNCH_PHONE_CONSENT"),
    39: .same(proto: "TAP_QUICK_SETTINGS_TILE"),
    40: .same(proto: "INSTALL_APK"),
    41: .same(proto: "VERIFY_APK"),
    42: .same(proto: "LAUNCH_CONSENT"),
    43: .same(proto: "PROCESS_RECEIVED_ATTACHMENTS_END"),
    44: .same(proto: "TOGGLE_SHOW_NOTIFICATION"),
    45: .same(proto: "SET_DEVICE_NAME"),
    46: .same(proto: "DECLINE_AGREEMENTS"),
    47: .same(proto: "REQUEST_SETTING_PERMISSIONS"),
    48: .same(proto: "ESTABLISH_CONNECTION"),
    49: .same(proto: "DEVICE_SETTINGS"),
    50: .same(proto: "AUTO_DISMISS_FAST_INITIALIZATION"),
    51: .same(proto: "APP_CRASH"),
    52: .same(proto: "TAP_QUICK_SETTINGS_FILE_SHARE"),
    53: .same(proto: "DISPLAY_PRIVACY_NOTIFICATION"),
    54: .same(proto: "DISPLAY_PHONE_CONSENT"),
    55: .same(proto: "PREFERENCES_USAGE"),
    56: .same(proto: "DEFAULT_OPT_IN"),
    57: .same(proto: "SETUP_WIZARD"),
    58: .same(proto: "TAP_QR_CODE"),
    59: .same(proto: "QR_CODE_LINK_SHOWN"),
    60: .same(proto: "PARSING_FAILED_ENDPOINT_ID"),
    61: .same(proto: "FAST_INIT_DISCOVER_DEVICE"),
    62: .same(proto: "SEND_DESKTOP_NOTIFICATION"),
    63: .same(proto: "SET_ACCOUNT"),
    64: .same(proto: "DECRYPT_CERTIFICATE_FAILURE"),
    65: .same(proto: "SHOW_ALLOW_PERMISSION_AUTO_ACCESS"),
    66: .same(proto: "SEND_DESKTOP_TRANSFER_EVENT"),
    67: .same(proto: "WAITING_FOR_ACCEPT"),
    68: .same(proto: "HIGH_QUALITY_MEDIUM_SETUP"),
    69: .same(proto: "RPC_CALL_STATUS"),
    70: .same(proto: "START_QR_CODE_SESSION"),
    71: .same(proto: "QR_CODE_OPENED_IN_WEB_CLIENT"),
    72: .same(proto: "HATS_JOINT_EVENT"),
    73: .same(proto: "RECEIVE_PREVIEWS"),
  ]
}

extension Location_Nearby_Proto_Sharing_EventCategory: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_EVENT_CATEGORY"),
    1: .same(proto: "SENDING_EVENT"),
    2: .same(proto: "RECEIVING_EVENT"),
    3: .same(proto: "SETTINGS_EVENT"),
    4: .same(proto: "RPC_EVENT"),
  ]
}

extension Location_Nearby_Proto_Sharing_NearbySharingStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_NEARBY_SHARING_STATUS"),
    1: .same(proto: "ON"),
    2: .same(proto: "OFF"),
  ]
}

extension Location_Nearby_Proto_Sharing_Visibility: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_VISIBILITY"),
    1: .same(proto: "CONTACTS_ONLY"),
    2: .same(proto: "EVERYONE"),
    3: .same(proto: "SELECTED_CONTACTS_ONLY"),
    4: .same(proto: "HIDDEN"),
    5: .same(proto: "SELF_SHARE"),
  ]
}

extension Location_Nearby_Proto_Sharing_DataUsage: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_DATA_USAGE"),
    1: .same(proto: "ONLINE"),
    2: .same(proto: "WIFI_ONLY"),
    3: .same(proto: "OFFLINE"),
  ]
}

extension Location_Nearby_Proto_Sharing_EstablishConnectionStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CONNECTION_STATUS_UNKNOWN"),
    1: .same(proto: "CONNECTION_STATUS_SUCCESS"),
    2: .same(proto: "CONNECTION_STATUS_FAILURE"),
    3: .same(proto: "CONNECTION_STATUS_CANCELLATION"),
    4: .same(proto: "CONNECTION_STATUS_MEDIA_UNAVAILABLE_ATTACHMENT"),
    5: .same(proto: "CONNECTION_STATUS_FAILED_PAIRED_KEYHANDSHAKE"),
    6: .same(proto: "CONNECTION_STATUS_FAILED_WRITE_INTRODUCTION"),
    7: .same(proto: "CONNECTION_STATUS_FAILED_NULL_CONNECTION"),
    8: .same(proto: "CONNECTION_STATUS_FAILED_NO_TRANSFER_UPDATE_CALLBACK"),
    9: .same(proto: "CONNECTION_STATUS_LOST_CONNECTIVITY"),
    10: .same(proto: "CONNECTION_STATUS_INVALID_ADVERTISEMENT"),
  ]
}

extension Location_Nearby_Proto_Sharing_AttachmentTransmissionStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_ATTACHMENT_TRANSMISSION_STATUS"),
    1: .same(proto: "COMPLETE_ATTACHMENT_TRANSMISSION_STATUS"),
    2: .same(proto: "CANCELED_ATTACHMENT_TRANSMISSION_STATUS"),
    3: .same(proto: "FAILED_ATTACHMENT_TRANSMISSION_STATUS"),
    4: .same(proto: "REJECTED_ATTACHMENT"),
    5: .same(proto: "TIMED_OUT_ATTACHMENT"),
    6: .same(proto: "AWAITING_REMOTE_ACCEPTANCE_FAILED_ATTACHMENT"),
    7: .same(proto: "NOT_ENOUGH_SPACE_ATTACHMENT"),
    8: .same(proto: "FAILED_NO_TRANSFER_UPDATE_CALLBACK"),
    9: .same(proto: "MEDIA_UNAVAILABLE_ATTACHMENT"),
    10: .same(proto: "UNSUPPORTED_ATTACHMENT_TYPE_ATTACHMENT"),
    11: .same(proto: "NO_ATTACHMENT_FOUND"),
    12: .same(proto: "FAILED_NO_SHARE_TARGET_ENDPOINT"),
    13: .same(proto: "FAILED_PAIRED_KEYHANDSHAKE"),
    14: .same(proto: "FAILED_NULL_CONNECTION"),
    15: .same(proto: "FAILED_NO_PAYLOAD"),
    16: .same(proto: "FAILED_WRITE_INTRODUCTION"),
    17: .same(proto: "FAILED_UNKNOWN_REMOTE_RESPONSE"),
    18: .same(proto: "FAILED_NULL_CONNECTION_INIT_OUTGOING"),
    19: .same(proto: "FAILED_NULL_CONNECTION_DISCONNECTED"),
    20: .same(proto: "FAILED_NULL_CONNECTION_LOST_CONNECTIVITY"),
    21: .same(proto: "FAILED_NULL_CONNECTION_FAILURE"),
    22: .same(proto: "REJECTED_ATTACHMENT_TRANSMISSION_STATUS"),
    23: .same(proto: "TIMED_OUT_ATTACHMENT_TRANSMISSION_STATUS"),
    24: .same(proto: "NOT_ENOUGH_SPACE_ATTACHMENT_TRANSMISSION_STATUS"),
    25: .same(proto: "UNSUPPORTED_ATTACHMENT_TYPE_ATTACHMENT_TRANSMISSION_STATUS"),
    26: .same(proto: "FAILED_UNKNOWN_REMOTE_RESPONSE_TRANSMISSION_STATUS"),
    27: .same(proto: "NO_RESPONSE_FRAME_CONNECTION_CLOSED_LOST_CONNECTIVITY_TRANSMISSION_STATUS"),
    28: .same(proto: "NO_RESPONSE_FRAME_CONNECTION_CLOSED_TRANSMISSION_STATUS"),
    29: .same(proto: "LOST_CONNECTIVITY_TRANSMISSION_STATUS"),
    30: .same(proto: "FAILED_DISALLOWED_MEDIUM"),
  ]
}

extension Location_Nearby_Proto_Sharing_ConnectionLayerStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CONNECTION_LAYER_STATUS_UNKNOWN"),
    1: .same(proto: "CONNECTION_LAYER_STATUS_SUCCESS"),
    2: .same(proto: "CONNECTION_LAYER_STATUS_ERROR"),
    3: .same(proto: "CONNECTION_LAYER_STATUS_OUT_OF_ORDER_API_CALL"),
    4: .same(proto: "CONNECTION_LAYER_STATUS_ALREADY_HAVE_ACTIVE_STRATEGY"),
    5: .same(proto: "CONNECTION_LAYER_STATUS_ALREADY_ADVERTISING"),
    6: .same(proto: "CONNECTION_LAYER_STATUS_ALREADY_DISCOVERING"),
    7: .same(proto: "CONNECTION_LAYER_STATUS_ALREADY_LISTENING"),
    8: .same(proto: "CONNECTION_LAYER_STATUS_END_POINT_IO_ERROR"),
    9: .same(proto: "CONNECTION_LAYER_STATUS_END_POINT_UNKNOWN"),
    10: .same(proto: "CONNECTION_LAYER_STATUS_CONNECTION_REJECTED"),
    11: .same(proto: "CONNECTION_LAYER_STATUS_ALREADY_CONNECTED_TO_END_POINT"),
    12: .same(proto: "CONNECTION_LAYER_STATUS_NOT_CONNECTED_TO_END_POINT"),
    13: .same(proto: "CONNECTION_LAYER_STATUS_BLUETOOTH_ERROR"),
    14: .same(proto: "CONNECTION_LAYER_STATUS_BLE_ERROR"),
    15: .same(proto: "CONNECTION_LAYER_STATUS_WIFI_LAN_ERROR"),
    16: .same(proto: "CONNECTION_LAYER_STATUS_PAYLOAD_UNKNOWN"),
    17: .same(proto: "CONNECTION_LAYER_STATUS_RESET"),
    18: .same(proto: "CONNECTION_LAYER_STATUS_TIMEOUT"),
  ]
}

extension Location_Nearby_Proto_Sharing_ProcessReceivedAttachmentsStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "PROCESSING_STATUS_UNKNOWN"),
    1: .same(proto: "PROCESSING_STATUS_COMPLETE_PROCESSING_ATTACHMENTS"),
    2: .same(proto: "PROCESSING_STATUS_FAILED_MOVING_FILES"),
    3: .same(proto: "PROCESSING_STATUS_FAILED_RECEIVING_APK"),
    4: .same(proto: "PROCESSING_STATUS_FAILED_RECEIVING_TEXT"),
    5: .same(proto: "PROCESSING_STATUS_FAILED_RECEIVING_WIFI_CREDENTIALS"),
  ]
}

extension Location_Nearby_Proto_Sharing_SessionStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_SESSION_STATUS"),
    1: .same(proto: "SUCCEEDED_SESSION_STATUS"),
    2: .same(proto: "FAILED_SESSION_STATUS"),
  ]
}

extension Location_Nearby_Proto_Sharing_ResponseToIntroduction: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_RESPONSE_TO_INTRODUCTION"),
    1: .same(proto: "ACCEPT_INTRODUCTION"),
    2: .same(proto: "REJECT_INTRODUCTION"),
    3: .same(proto: "FAIL_INTRODUCTION"),
  ]
}

extension Location_Nearby_Proto_Sharing_DeviceType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_DEVICE_TYPE"),
    1: .same(proto: "PHONE"),
    2: .same(proto: "TABLET"),
    3: .same(proto: "LAPTOP"),
    4: .same(proto: "CAR"),
    5: .same(proto: "FOLDABLE"),
    6: .same(proto: "XR"),
  ]
}

extension Location_Nearby_Proto_Sharing_OSType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_OS_TYPE"),
    1: .same(proto: "ANDROID"),
    2: .same(proto: "CHROME_OS"),
    3: .same(proto: "IOS"),
    4: .same(proto: "WINDOWS"),
    5: .same(proto: "MACOS"),
  ]
}

extension Location_Nearby_Proto_Sharing_DeviceRelationship: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_DEVICE_RELATIONSHIP"),
    1: .same(proto: "IS_SELF"),
    2: .same(proto: "IS_CONTACT"),
    3: .same(proto: "IS_STRANGER"),
  ]
}

extension Location_Nearby_Proto_Sharing_LogSource: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNSPECIFIED_SOURCE"),
    1: .same(proto: "LAB_DEVICES"),
    2: .same(proto: "INTERNAL_DEVICES"),
    3: .same(proto: "BETA_TESTER_DEVICES"),
    4: .same(proto: "OEM_DEVICES"),
    5: .same(proto: "DEBUG_DEVICES"),
    6: .same(proto: "NEARBY_MODULE_FOOD_DEVICES"),
    7: .same(proto: "BETO_DOGFOOD_DEVICES"),
    8: .same(proto: "NEARBY_DOGFOOD_DEVICES"),
    9: .same(proto: "NEARBY_TEAMFOOD_DEVICES"),
  ]
}

extension Location_Nearby_Proto_Sharing_ServerActionName: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_SERVER_ACTION"),
    1: .same(proto: "UPLOAD_CERTIFICATES"),
    2: .same(proto: "DOWNLOAD_CERTIFICATES"),
    3: .same(proto: "CHECK_REACHABILITY"),
    4: .same(proto: "UPLOAD_CONTACTS"),
    5: .same(proto: "UPDATE_DEVICE_NAME"),
    6: .same(proto: "UPLOAD_SENDER_CERTIFICATES"),
    7: .same(proto: "DOWNLOAD_SENDER_CERTIFICATES"),
    8: .same(proto: "UPLOAD_CONTACTS_AND_CERTIFICATES"),
    9: .same(proto: "LIST_REACHABLE_PHONE_NUMBERS"),
    10: .same(proto: "LIST_MY_DEVICES"),
    11: .same(proto: "LIST_CONTACT_PEOPLE"),
    12: .same(proto: "DOWNLOAD_CERTIFICATES_INFO"),
  ]
}

extension Location_Nearby_Proto_Sharing_ServerResponseState: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_SERVER_RESPONSE_STATE"),
    1: .same(proto: "SERVER_RESPONSE_SUCCESS"),
    2: .same(proto: "SERVER_RESPONSE_UNKNOWN_FAILURE"),
    3: .same(proto: "SERVER_RESPONSE_STATUS_OTHER_FAILURE"),
    4: .same(proto: "SERVER_RESPONSE_STATUS_DEADLINE_EXCEEDED"),
    5: .same(proto: "SERVER_RESPONSE_STATUS_PERMISSION_DENIED"),
    6: .same(proto: "SERVER_RESPONSE_STATUS_UNAVAILABLE"),
    7: .same(proto: "SERVER_RESPONSE_STATUS_UNAUTHENTICATED"),
    8: .same(proto: "SERVER_RESPONSE_GOOGLE_AUTH_FAILURE"),
    9: .same(proto: "SERVER_RESPONSE_STATUS_INVALID_ARGUMENT"),
    10: .same(proto: "SERVER_RESPONSE_NOT_CONNECTED_TO_INTERNET"),
  ]
}

extension Location_Nearby_Proto_Sharing_SyncPurpose: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "SYNC_PURPOSE_UNKNOWN"),
    1: .same(proto: "SYNC_PURPOSE_ON_DEMAND_SYNC"),
    2: .same(proto: "SYNC_PURPOSE_CHIME_NOTIFICATION"),
    3: .same(proto: "SYNC_PURPOSE_DAILY_SYNC"),
    4: .same(proto: "SYNC_PURPOSE_OPT_IN_FIRST_SYNC"),
    5: .same(proto: "SYNC_PURPOSE_CHECK_DEFAULT_OPT_IN"),
    6: .same(proto: "SYNC_PURPOSE_NEARBY_SHARE_ENABLED"),
    7: .same(proto: "SYNC_PURPOSE_SYNC_AT_FAST_INIT"),
    8: .same(proto: "SYNC_PURPOSE_SYNC_AT_DISCOVERY"),
    9: .same(proto: "SYNC_PURPOSE_SYNC_AT_LOAD_PRIVATE_CERTIFICATE"),
    10: .same(proto: "SYNC_PURPOSE_SYNC_AT_ADVERTISEMENT"),
    11: .same(proto: "SYNC_PURPOSE_CONTACT_LIST_CHANGE"),
    12: .same(proto: "SYNC_PURPOSE_SHOW_C11N_VIEW"),
    13: .same(proto: "SYNC_PURPOSE_REGULAR_CHECK_CONTACT_REACHABILITY"),
    14: .same(proto: "SYNC_PURPOSE_VISIBILITY_SELECTED_CONTACT_CHANGE"),
    15: .same(proto: "SYNC_PURPOSE_ACCOUNT_CHANGE"),
    16: .same(proto: "SYNC_PURPOSE_REGENERATE_CERTIFICATES"),
    17: .same(proto: "SYNC_PURPOSE_DEVICE_CONTACTS_CONSENT_CHANGE"),
  ]
}

extension Location_Nearby_Proto_Sharing_ClientRole: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CLIENT_ROLE_UNKNOWN"),
    1: .same(proto: "CLIENT_ROLE_SENDER"),
    2: .same(proto: "CLIENT_ROLE_RECEIVER"),
  ]
}

extension Location_Nearby_Proto_Sharing_ScanType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_SCAN_TYPE"),
    1: .same(proto: "FOREGROUND_SCAN"),
    2: .same(proto: "FOREGROUND_RETRY_SCAN"),
    3: .same(proto: "DIRECT_SHARE_SCAN"),
    4: .same(proto: "BACKGROUND_SCAN"),
  ]
}

extension Location_Nearby_Proto_Sharing_ParsingFailedType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "FAILED_UNKNOWN_TYPE"),
    1: .same(proto: "FAILED_PARSE_ADVERTISEMENT"),
    2: .same(proto: "FAILED_CONVERT_SHARE_TARGET"),
  ]
}

extension Location_Nearby_Proto_Sharing_AdvertisingMode: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_ADVERTISING_MODE"),
    1: .same(proto: "SCREEN_OFF_ADVERTISING_MODE"),
    2: .same(proto: "BACKGROUND_ADVERTISING_MODE"),
    3: .same(proto: "MIDGROUND_ADVERTISING_MODE"),
    4: .same(proto: "FOREGROUND_ADVERTISING_MODE"),
    5: .same(proto: "SUSPENDED_ADVERTISING_MODE"),
  ]
}

extension Location_Nearby_Proto_Sharing_DiscoveryMode: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_DISCOVERY_MODE"),
    1: .same(proto: "SCREEN_OFF_DISCOVERY_MODE"),
    2: .same(proto: "BACKGROUND_DISCOVERY_MODE"),
    3: .same(proto: "MIDGROUND_DISCOVERY_MODE"),
    4: .same(proto: "FOREGROUND_DISCOVERY_MODE"),
    5: .same(proto: "SUSPENDED_DISCOVERY_MODE"),
  ]
}

extension Location_Nearby_Proto_Sharing_ActivityName: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_ACTIVITY"),
    1: .same(proto: "SHARE_SHEET_ACTIVITY"),
    2: .same(proto: "SETTINGS_ACTIVITY"),
    3: .same(proto: "RECEIVE_SURFACE_ACTIVITY"),
    4: .same(proto: "SETUP_ACTIVITY"),
    5: .same(proto: "DEVICE_VISIBILITY_ACTIVITY"),
    6: .same(proto: "CONSENTS_ACTIVITY"),
    7: .same(proto: "SET_DEVICE_NAME_DIALOG"),
    8: .same(proto: "SET_DATA_USAGE_DIALOG"),
    9: .same(proto: "QUICK_SETTINGS_ACTIVITY"),
    10: .same(proto: "REMOTE_COPY_SHARE_SHEET_ACTIVITY"),
    11: .same(proto: "SETUP_WIZARD_ACTIVITY"),
    12: .same(proto: "SETTINGS_REVIEW_ACTIVITY"),
  ]
}

extension Location_Nearby_Proto_Sharing_ConsentType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CONSENT_TYPE_UNKNOWN"),
    1: .same(proto: "CONSENT_TYPE_C11N"),
    2: .same(proto: "CONSENT_TYPE_DEVICE_CONTACT"),
  ]
}

extension Location_Nearby_Proto_Sharing_ConsentAcceptanceStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CONSENT_UNKNOWN_ACCEPT_STATUS"),
    1: .same(proto: "CONSENT_ACCEPTED"),
    2: .same(proto: "CONSENT_DECLINED"),
    3: .same(proto: "CONSENT_UNABLE_TO_ENABLE"),
  ]
}

extension Location_Nearby_Proto_Sharing_ApkSource: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_APK_SOURCE"),
    1: .same(proto: "APK_FROM_SD_CARD"),
    2: .same(proto: "INSTALLED_APP"),
  ]
}

extension Location_Nearby_Proto_Sharing_InstallAPKStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_INSTALL_APK_STATUS"),
    1: .same(proto: "FAIL_INSTALLATION"),
    2: .same(proto: "SUCCESS_INSTALLATION"),
  ]
}

extension Location_Nearby_Proto_Sharing_VerifyAPKStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_VERIFY_APK_STATUS"),
    1: .same(proto: "NOT_INSTALLABLE"),
    2: .same(proto: "INSTALLABLE"),
    3: .same(proto: "ALREADY_INSTALLED"),
  ]
}

extension Location_Nearby_Proto_Sharing_ShowNotificationStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN_SHOW_NOTIFICATION_STATUS"),
    1: .same(proto: "SHOW"),
    2: .same(proto: "NOT_SHOW"),
  ]
}

extension Location_Nearby_Proto_Sharing_PermissionRequestResult: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "PERMISSION_UNKNOWN_REQUEST_RESULT"),
    1: .same(proto: "PERMISSION_GRANTED"),
    2: .same(proto: "PERMISSION_REJECTED"),
    3: .same(proto: "PERMISSION_UNABLE_TO_GRANT"),
  ]
}

extension Location_Nearby_Proto_Sharing_PermissionRequestType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "PERMISSION_UNKNOWN_TYPE"),
    1: .same(proto: "PERMISSION_AIRPLANE_MODE_OFF"),
    2: .same(proto: "PERMISSION_WIFI"),
    3: .same(proto: "PERMISSION_BLUETOOTH"),
    4: .same(proto: "PERMISSION_LOCATION"),
    5: .same(proto: "PERMISSION_WIFI_HOTSPOT"),
  ]
}

extension Location_Nearby_Proto_Sharing_SharingUseCase: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "USE_CASE_UNKNOWN"),
    1: .same(proto: "USE_CASE_NEARBY_SHARE"),
    2: .same(proto: "USE_CASE_REMOTE_COPY_PASTE"),
    3: .same(proto: "USE_CASE_WIFI_CREDENTIAL"),
    4: .same(proto: "USE_CASE_APP_SHARE"),
    5: .same(proto: "USE_CASE_QUICK_SETTING_FILE_SHARE"),
    6: .same(proto: "USE_CASE_SETUP_WIZARD"),
    7: .same(proto: "USE_CASE_NEARBY_SHARE_WITH_QR_CODE"),
    8: .same(proto: "USE_CASE_REDIRECTED_FROM_BLUETOOTH_SHARE"),
  ]
}

extension Location_Nearby_Proto_Sharing_AppCrashReason: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "APP_CRASH_REASON_UNKNOWN"),
  ]
}

extension Location_Nearby_Proto_Sharing_AttachmentSourceType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "ATTACHMENT_SOURCE_UNKNOWN"),
    1: .same(proto: "ATTACHMENT_SOURCE_CONTEXT_MENU"),
    2: .same(proto: "ATTACHMENT_SOURCE_DRAG_AND_DROP"),
    3: .same(proto: "ATTACHMENT_SOURCE_SELECT_FILES_BUTTON"),
    4: .same(proto: "ATTACHMENT_SOURCE_PASTE"),
    5: .same(proto: "ATTACHMENT_SOURCE_SELECT_FOLDERS_BUTTON"),
    6: .same(proto: "ATTACHMENT_SOURCE_SHARE_ACTIVATION"),
  ]
}

extension Location_Nearby_Proto_Sharing_PreferencesAction: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "PREFERENCES_ACTION_UNKNOWN"),
    1: .same(proto: "PREFERENCES_ACTION_NO_ACTION"),
    2: .same(proto: "PREFERENCES_ACTION_LOAD_PREFERENCES"),
    3: .same(proto: "PREFERENCES_ACTION_SAVE_PREFERENCESS"),
    4: .same(proto: "PREFERENCES_ACTION_ATTEMPT_LOAD"),
    5: .same(proto: "PREFERENCES_ACTION_RESTORE_FROM_BACKUP"),
    6: .same(proto: "PREFERENCES_ACTION_CREATE_PREFERENCES_PATH"),
    7: .same(proto: "PREFERENCES_ACTION_MAKE_PREFERENCES_BACKUP_FILE"),
    8: .same(proto: "PREFERENCES_ACTION_CHECK_IF_PREFERENCES_PATH_EXISTS"),
    9: .same(proto: "PREFERENCES_ACTION_CHECK_IF_PREFERENCES_INPUT_STREAM_STATUS"),
    10: .same(proto: "PREFERENCES_ACTION_CHECK_IF_PREFERENCES_FILE_IS_CORRUPTED"),
    11: .same(proto: "PREFERENCES_ACTION_CHECK_IF_PREFERENCES_BACKUP_FILE_EXISTS"),
  ]
}

extension Location_Nearby_Proto_Sharing_PreferencesActionStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "PREFERENCES_ACTION_STATUS_UNKNOWN"),
    1: .same(proto: "PREFERENCES_ACTION_STATUS_SUCCESS"),
    2: .same(proto: "PREFERENCES_ACTION_STATUS_FAIL"),
  ]
}

extension Location_Nearby_Proto_Sharing_FastInitState: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "FAST_INIT_UNKNOWN_STATE"),
    1: .same(proto: "FAST_INIT_CLOSE_STATE"),
    2: .same(proto: "FAST_INIT_FAR_STATE"),
    3: .same(proto: "FAST_INIT_LOST_STATE"),
  ]
}

extension Location_Nearby_Proto_Sharing_FastInitType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "FAST_INIT_UNKNOWN_TYPE"),
    1: .same(proto: "FAST_INIT_NOTIFY_TYPE"),
    2: .same(proto: "FAST_INIT_SILENT_TYPE"),
  ]
}

extension Location_Nearby_Proto_Sharing_DesktopNotification: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "DESKTOP_NOTIFICATION_UNKNOWN"),
    1: .same(proto: "DESKTOP_NOTIFICATION_CONNECTING"),
    2: .same(proto: "DESKTOP_NOTIFICATION_PROGRESS"),
    3: .same(proto: "DESKTOP_NOTIFICATION_ACCEPT"),
    4: .same(proto: "DESKTOP_NOTIFICATION_RECEIVED"),
    5: .same(proto: "DESKTOP_NOTIFICATION_ERROR"),
  ]
}

extension Location_Nearby_Proto_Sharing_DesktopTransferEventType: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "DESKTOP_TRANSFER_EVENT_TYPE_UNKNOWN"),
    1: .same(proto: "DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_ACCEPT"),
    2: .same(proto: "DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_PROGRESS"),
    3: .same(proto: "DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_RECEIVED"),
    4: .same(proto: "DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_ERROR"),
    5: .same(proto: "DESKTOP_TRANSFER_EVENT_SEND_TYPE_START"),
    6: .same(proto: "DESKTOP_TRANSFER_EVENT_SEND_TYPE_SELECT_A_DEVICE"),
    7: .same(proto: "DESKTOP_TRANSFER_EVENT_SEND_TYPE_PROGRESS"),
    8: .same(proto: "DESKTOP_TRANSFER_EVENT_SEND_TYPE_SENT"),
    9: .same(proto: "DESKTOP_TRANSFER_EVENT_SEND_TYPE_ERROR"),
  ]
}

extension Location_Nearby_Proto_Sharing_DecryptCertificateFailureStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "DECRYPT_CERT_UNKNOWN_FAILURE"),
    1: .same(proto: "DECRYPT_CERT_NO_SUCH_ALGORITHM_FAILURE"),
    2: .same(proto: "DECRYPT_CERT_NO_SUCH_PADDING_FAILURE"),
    3: .same(proto: "DECRYPT_CERT_INVALID_KEY_FAILURE"),
    4: .same(proto: "DECRYPT_CERT_INVALID_ALGORITHM_PARAMETER_FAILURE"),
    5: .same(proto: "DECRYPT_CERT_ILLEGAL_BLOCK_SIZE_FAILURE"),
    6: .same(proto: "DECRYPT_CERT_BAD_PADDING_FAILURE"),
  ]
}

extension Location_Nearby_Proto_Sharing_ContactAccess: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CONTACT_ACCESS_UNKNOWN"),
    1: .same(proto: "CONTACT_ACCESS_NO_CONTACT_UPLOADED"),
    2: .same(proto: "CONTACT_ACCESS_ONLY_UPLOAD_GOOGLE_CONTACT"),
    3: .same(proto: "CONTACT_ACCESS_UPLOAD_CONTACT_FOR_DEVICE_CONTACT_CONSENT"),
    4: .same(proto: "CONTACT_ACCESS_UPLOAD_CONTACT_FOR_QUICK_SHARE_CONSENT"),
  ]
}

extension Location_Nearby_Proto_Sharing_IdentityVerification: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "IDENTITY_VERIFICATION_UNKNOWN"),
    1: .same(proto: "IDENTITY_VERIFICATION_NO_PHONE_NUMBER_VERIFIED"),
    2: .same(proto: "IDENTITY_VERIFICATION_PHONE_NUMBER_VERIFIED_NOT_LINKED_TO_GAIA"),
    3: .same(proto: "IDENTITY_VERIFICATION_PHONE_NUMBER_VERIFIED_LINKED_TO_QS_GAIA"),
  ]
}

extension Location_Nearby_Proto_Sharing_ButtonStatus: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "BUTTON_STATUS_UNKNOWN"),
    1: .same(proto: "BUTTON_STATUS_CLICK_ACCEPT"),
    2: .same(proto: "BUTTON_STATUS_CLICK_REJECT"),
    3: .same(proto: "BUTTON_STATUS_IGNORE"),
  ]
}