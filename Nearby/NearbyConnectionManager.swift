//
//  NearbyConnectionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-21.
//

import Foundation
import Network
import System
import Combine
import CryptoKit
import SwiftECC

public enum NearDropUserAction {
    case save
    case open
    case copy
}

public struct RemoteDeviceInfo{
    public let name:String
    public let type:DeviceType
    public let qrCodeData:Data?
    public var id:String?

    init(name: String, type: DeviceType, id: String? = nil) {
        self.name = name
        self.type = type
        self.id = id
        self.qrCodeData = nil
    }

    init(info:EndpointInfo, id: String? = nil){
        self.name=info.name!
        self.type=info.deviceType
        self.qrCodeData=info.qrCodeData
        self.id=id
    }

    public enum DeviceType:Int32{
        case unknown=0
        case phone
        case tablet
        case computer

        public static func fromRawValue(value:Int) -> DeviceType{
            switch value {
            case 0:
                return .unknown
            case 1:
                return .phone
            case 2:
                return .tablet
            case 3:
                return .computer
            default:
                return .unknown
            }
        }
    }
}

public enum NearbyError: Error, Equatable {
    case protocolError(_ message: String)
    case requiredFieldMissing(_ message: String)
    case ukey2
    case inputOutput
    case canceled(reason: CancellationReason)

    public enum CancellationReason: Equatable {
        case userRejected, userCanceled, notEnoughSpace, unsupportedType, timedOut
    }

    public static func == (lhs: NearbyError, rhs: NearbyError) -> Bool {
        switch (lhs, rhs) {
        case (.protocolError(let lMsg), .protocolError(let rMsg)):
            return lMsg == rMsg
        case (.requiredFieldMissing(let lMsg), .requiredFieldMissing(let rMsg)):
            return lMsg == rMsg
        case (.ukey2, .ukey2):
            return true
        case (.inputOutput, .inputOutput):
            return true
        case (.canceled(let lReason), .canceled(let rReason)):
            return lReason == rReason
        default:
            return false
        }
    }
}

public struct TransferMetadata{
    public let files:[FileMetadata]
    public let id:String
    public let pinCode:String?
    public let textDescription:String?

    init(files: [FileMetadata], id: String, pinCode: String?, textDescription: String?=nil){
        self.files = files
        self.id = id
        self.pinCode = pinCode
        self.textDescription = textDescription
    }
}

public struct FileMetadata{
    public let name:String
    public let size:Int64
    public let mimeType:String
}

struct FoundServiceInfo{
    let service:NWBrowser.Result
    var device:RemoteDeviceInfo?
}

struct OutgoingTransferInfo{
    let service:NWBrowser.Result
    let device:RemoteDeviceInfo
    let connection:OutboundNearbyConnection
    let delegate:ShareExtensionDelegate
}

struct EndpointInfo{
    var name:String?
    let deviceType:RemoteDeviceInfo.DeviceType
    let qrCodeData:Data?

    init(name: String, deviceType: RemoteDeviceInfo.DeviceType){
        self.name = name
        self.deviceType = deviceType
        self.qrCodeData=nil
    }

    init?(data:Data){
        guard data.count>17 else {return nil}
        let hasName=(data[0] & 0x10)==0
        let deviceNameLength:Int
        let deviceName:String?
        if hasName{
            deviceNameLength=Int(data[17])
            guard data.count>=deviceNameLength+18 else {return nil}
            guard let _deviceName=String(data: data[18..<(18+deviceNameLength)], encoding: .utf8) else {return nil}
            deviceName=_deviceName
        }else{
            deviceNameLength=0
            deviceName=nil
        }
        let rawDeviceType:Int=Int(data[0] & 7) >> 1
        self.name=deviceName
        self.deviceType=RemoteDeviceInfo.DeviceType.fromRawValue(value: rawDeviceType)
        var offset=1+16
        if hasName{
            offset=offset+1+deviceNameLength
        }
        var qrCodeData:Data?=nil
        while data.count-offset>2{
            let type=data[offset]
            let length=Int(data[offset+1])
            offset=offset+2
            if data.count-offset>=length{
                if type==1{
                    qrCodeData=data.subdata(in: offset..<offset+length)
                }
                offset=offset+length
            }
        }
        self.qrCodeData=qrCodeData
    }

    func serialize()->Data{
        var endpointInfo:[UInt8]=[UInt8(deviceType.rawValue << 1)]
        for _ in 0...15{
            endpointInfo.append(UInt8.random(in: 0...255))
        }
        var nameChars=[UInt8](name!.utf8)
        if nameChars.count>255{
            nameChars=[UInt8](nameChars[0..<255])
        }
        endpointInfo.append(UInt8(nameChars.count))
        endpointInfo.append(contentsOf: nameChars)
        return Data(endpointInfo)
    }
}

public protocol ShareExtensionDelegate:AnyObject{
    func addDevice(device:RemoteDeviceInfo)
    func removeDevice(id:String)
    func startTransferWithQrCode(device:RemoteDeviceInfo)
    func connectionWasEstablished(pinCode:String)
    func connectionFailed(with error:Error)
    func transferAccepted()
    func transferProgress(progress:Double)
    func transferFinished()
}

public protocol MainAppDelegate {
    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, fileURLs: [URL])
    func incomingTransfer(id: String, didUpdateProgress progress: Double)
    func incomingTransfer(id: String, didFinishWith error: Error?)
}

public class NearbyConnectionManager: NSObject, ObservableObject, NetServiceDelegate, InboundNearbyConnectionDelegate, OutboundNearbyConnectionDelegate {

    private var tcpListener: NWListener;
    public let endpointID: [UInt8] = generateEndpointID()
    private var mdnsService: NetService?
    private var activeConnections: [String: InboundNearbyConnection] = [:]
    private var foundServices: [String: FoundServiceInfo] = [:]
    private var shareExtensionDelegates: [ShareExtensionDelegate] = []
    private var outgoingTransfers: [String: OutgoingTransferInfo] = [:]
    public var mainAppDelegate: (any MainAppDelegate)?
    private var discoveryRefCount = 0
    private var browser: NWBrowser?

    private var qrCodePublicKey:ECPublicKey?
    private var qrCodePrivateKey:ECPrivateKey?
    private var qrCodeAdvertisingToken:Data?
    private var qrCodeNameEncryptionKey:SymmetricKey?
    private var qrCodeData:Data?

    @Published public var transfers: [TransferProgressInfo] = []
    private var cleanupTimers: [String: Timer] = [:]

    public var deviceDisplayName: String = Host.current().localizedName ?? "My Mac" {
        didSet {
            if mdnsService != nil {
                initMDNS()
            }
        }
    }

    public static let shared = NearbyConnectionManager()

    override init() {
        self.tcpListener = try! NWListener(using: NWParameters(tls: .none))
        super.init()
    }

    public func becomeVisible() { startTCPListener() }

    private func startTCPListener() {
        tcpListener.stateUpdateHandler = { [weak self] state in if case .ready = state { self?.initMDNS() } }
        tcpListener.newConnectionHandler = { [weak self] connection in
            let id = UUID().uuidString
            print("[NCM] New inbound connection with ID: \(id)")
            let conn = InboundNearbyConnection(connection: connection, id: id)
            self?.activeConnections[id] = conn
            conn.delegate = self
            conn.start()
        }
        tcpListener.start(queue: .global(qos: .utility))
    }

    private func getBroadcastName() -> String {
        let trimmedName = deviceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let nameToSanitize = trimmedName.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
            if let asciiData = nameToSanitize.data(using: .ascii, allowLossyConversion: true), let sanitizedName = String(data: asciiData, encoding: .ascii) {
                print("[NCM] Using sanitized custom name: '\(sanitizedName)'")
                return sanitizedName
            }
        }
        let defaultName = Host.current().localizedName ?? "My Mac"; print("[NCM] Custom name is empty or invalid. Falling back to default system name: '\(defaultName)'"); return defaultName
    }

    private static func generateEndpointID() -> [UInt8] {
        var id: [UInt8] = []; let alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".compactMap { UInt8($0.asciiValue!) }
        for _ in 0...3 { id.append(alphabet[Int.random(in: 0..<alphabet.count)]) }
        return id
    }

    private func initMDNS() {
        mdnsService?.stop()
        let broadcastName = getBroadcastName()
        let endpointInfo = EndpointInfo(name: broadcastName, deviceType: .computer)
        let nameBytes: [UInt8] = [0x23] + endpointID + [0xFC, 0x9F, 0x5E, 0, 0]
        let name = Data(nameBytes).urlSafeBase64EncodedString()
        guard let port = tcpListener.port, let servicePort = Int32(exactly: port.rawValue) else { print("[NCM] Error: Could not get a valid port from listener for mDNS broadcast."); return }
        print("[NCM] Broadcasting service on port \(servicePort) with final name '\(broadcastName)'")
        mdnsService = NetService(domain: "", type: "_FC9F5ED42C8A._tcp.", name: name, port: servicePort)
        mdnsService?.delegate = self
        mdnsService?.setTXTRecord(NetService.data(fromTXTRecord: ["n": endpointInfo.serialize().urlSafeBase64EncodedString().data(using: .utf8)!]))
        mdnsService?.publish()
    }

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo, fileURLs: [URL]) {
        let info = TransferProgressInfo(id: transfer.id, deviceName: device.name, fileDescription: fileDescription(for: transfer), direction: .incoming, iconName: iconName(for: transfer))
        DispatchQueue.main.async {
            self.transfers.insert(info, at: 0)
        }
        mainAppDelegate?.obtainUserConsent(for: transfer, from: device, fileURLs: fileURLs)
    }

    func connection(_ connection: InboundNearbyConnection, didUpdateProgress progress: Double) {
        mainAppDelegate?.incomingTransfer(id: connection.id, didUpdateProgress: progress)
        DispatchQueue.main.async {
            if let index = self.transfers.firstIndex(where: { $0.id == connection.id }) { self.transfers[index].progress = progress }
        }
    }

    func connectionWasTerminated(connection: InboundNearbyConnection, error: Error?) {
        print("[NCM] Inbound connection \(connection.id) terminated. Error: \(String(describing: error))")
        mainAppDelegate?.incomingTransfer(id: connection.id, didFinishWith: error)
        DispatchQueue.main.async {
            if let index = self.transfers.firstIndex(where: { $0.id == connection.id }) {
                if let error = error { self.transfers[index].state = (error as? NearbyError) == .canceled(reason: .userCanceled) ? .canceled : .failed }
                else { self.transfers[index].state = .finished }
                self.scheduleCleanup(for: connection.id)
            }
        }
        activeConnections.removeValue(forKey: connection.id)
    }

    public func submitUserConsent(transferID: String, accept: Bool, action: NearDropUserAction = .save) {
        print("[NCM] User consent for transfer \(transferID): \(accept ? "Accepted" : "Rejected") with action \(action)")
        activeConnections[transferID]?.submitUserConsent(accepted: accept, action: action)
        DispatchQueue.main.async {
            guard let index = self.transfers.firstIndex(where: { $0.id == transferID }) else {
                print("[NCM] Warning: Could not find transfer with ID \(transferID) to update consent.")
                return
            }

            if accept {
                self.transfers[index].state = .inProgress
            } else {
                self.transfers.remove(at: index)
            }
        }
    }

    public func cancelIncomingTransfer(id: String) {
        print("[NCM] Canceling incoming transfer \(id)")
        activeConnections[id]?.disconnect()
    }

    public func startDeviceDiscovery() {
        print("[NCM] Starting device discovery (ref count: \(discoveryRefCount+1))")
        if discoveryRefCount == 0 {
            foundServices.removeAll()
            browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_FC9F5ED42C8A._tcp.", domain: nil), using: .tcp)
            browser?.browseResultsChangedHandler = { _, changes in for change in changes { switch change { case let .added(res): self.maybeAddFoundDevice(service: res); case let .removed(res): self.maybeRemoveFoundDevice(service: res); default: break } } }
            browser?.start(queue: .main)
        }
        discoveryRefCount += 1
    }

    public func stopDeviceDiscovery() {
        discoveryRefCount -= 1; assert(discoveryRefCount >= 0)
        print("[NCM] Stopping device discovery (ref count: \(discoveryRefCount))")
        if discoveryRefCount == 0 { browser?.cancel(); browser = nil }
    }

    public func addShareExtensionDelegate(_ delegate: ShareExtensionDelegate) {
        shareExtensionDelegates.append(delegate)
        for service in foundServices.values { if let device = service.device { delegate.addDevice(device: device) } }
    }

    public func removeShareExtensionDelegate(_ delegate: ShareExtensionDelegate) { shareExtensionDelegates.removeAll { $0 === delegate } }
    public func cancelOutgoingTransfer(id: String) {
        print("[NCM] Canceling outgoing transfer \(id)")
        outgoingTransfers[id]?.connection.cancel()
    }

    private func endpointID(for service: NWBrowser.Result) -> String? {
        guard case let .service(name: serviceName, _, _, _) = service.endpoint, let nameData = Data.dataFromUrlSafeBase64(serviceName), nameData.count >= 10,
              nameData[0] == 0x23, nameData.subdata(in: 5..<8) == Data([0xFC, 0x9F, 0x5E]) else { return nil }
        return String(data: nameData.subdata(in: 1..<5), encoding: .ascii)
    }

    private func maybeAddFoundDevice(service:NWBrowser.Result){
        #if DEBUG
        print("[NCM] Found service \(service)")
        #endif
        for interface in service.interfaces{
            if case .loopback=interface.type{
                #if DEBUG
                print("[NCM] Ignoring localhost service")
                #endif
                return
            }
        }
        guard let endpointID=endpointID(for: service) else {return}
        #if DEBUG
        print("[NCM] Service name is valid, endpoint ID \(endpointID)")
        #endif
        var foundService=FoundServiceInfo(service: service)

        guard case let NWBrowser.Result.Metadata.bonjour(txtRecord)=service.metadata else {return}
        guard let endpointInfoEncoded=txtRecord.dictionary["n"] else {return}
        guard let endpointInfoSerialized=Data.dataFromUrlSafeBase64(endpointInfoEncoded) else {return}
        guard var endpointInfo=EndpointInfo(data: endpointInfoSerialized) else {return}

        var deviceInfo:RemoteDeviceInfo?
        if let _=endpointInfo.name{
            deviceInfo=addFoundDevice(foundService: &foundService, endpointInfo: endpointInfo, endpointID: endpointID)
        }

        if let qrData=endpointInfo.qrCodeData, let _=qrCodeAdvertisingToken{
            #if DEBUG
            print("[NCM] Device has QR data: \(qrData.base64EncodedString()), our advertising token is \(qrCodeAdvertisingToken!.base64EncodedString())")
            #endif
            if qrData==qrCodeAdvertisingToken!{
                if let deviceInfo=deviceInfo{
                    for delegate in shareExtensionDelegates{
                        delegate.startTransferWithQrCode(device: deviceInfo)
                    }
                }
            }else if qrData.count>28{
                do{
                    let box=try AES.GCM.SealedBox(combined: qrData)
                    let decryptedName=try AES.GCM.open(box, using: qrCodeNameEncryptionKey!, authenticating: qrCodeAdvertisingToken!)
                    guard let name=String.init(data: decryptedName, encoding: .utf8) else {return}
                    endpointInfo.name=name
                    let deviceInfo=addFoundDevice(foundService: &foundService, endpointInfo: endpointInfo, endpointID: endpointID)
                    for delegate in shareExtensionDelegates{
                        delegate.startTransferWithQrCode(device: deviceInfo)
                    }
                }catch{
                    #if DEBUG
                    print("[NCM] Error decrypting QR code data of an invisible device: \(error)")
                    #endif
                }
            }
        }
    }

    private func addFoundDevice(foundService:inout FoundServiceInfo, endpointInfo:EndpointInfo, endpointID:String) -> RemoteDeviceInfo{
        let deviceInfo=RemoteDeviceInfo(info: endpointInfo, id: endpointID)
        foundService.device=deviceInfo
        foundServices[endpointID]=foundService
        print("[NCM] Added device: \(deviceInfo.name) (\(deviceInfo.id!))")
        for delegate in shareExtensionDelegates{
            delegate.addDevice(device: deviceInfo)
        }
        return deviceInfo
    }

    private func maybeRemoveFoundDevice(service: NWBrowser.Result) {
        guard let endpointID = endpointID(for: service), let removed = foundServices.removeValue(forKey: endpointID) else { return }
        print("[NCM] Removed device: \(removed.device?.name ?? "Unknown") (\(endpointID))")
        for delegate in shareExtensionDelegates { delegate.removeDevice(id: endpointID) }
    }

    public func generateQrCodeKey() -> String{
        let domain=Domain.instance(curve: .EC256r1)
        let (pubKey, privKey)=domain.makeKeyPair()
        qrCodePublicKey=pubKey
        qrCodePrivateKey=privKey
        var keyData=Data()
        keyData.append(contentsOf: [0, 0, 2])
        let keyBytes=Data(pubKey.w.x.asSignedBytes())
        keyData.append(contentsOf: keyBytes.suffix(32))

        let ikm=SymmetricKey(data: keyData)
        qrCodeAdvertisingToken=NearbyConnection.hkdf(inputKeyMaterial: ikm, salt: Data(), info: "advertisingContext".data(using: .utf8)!, outputByteCount: 16).data()
        qrCodeNameEncryptionKey=NearbyConnection.hkdf(inputKeyMaterial: ikm, salt: Data(), info: "encryptionKey".data(using: .utf8)!, outputByteCount: 16)
        qrCodeData=keyData

        print("[NCM] Generated new QR code key.")
        return keyData.urlSafeBase64EncodedString()
    }

    public func clearQrCodeKey(){
        print("[NCM] Clearing QR code key.")
        qrCodePublicKey=nil
        qrCodePrivateKey=nil
        qrCodeAdvertisingToken=nil
        qrCodeNameEncryptionKey=nil
        qrCodeData=nil
    }

    public func startOutgoingTransfer(deviceID: String, delegate: ShareExtensionDelegate, urls: [URL]) {
        guard let info = foundServices[deviceID] else { print("[NCM] Error: Attempted to start transfer to unknown device ID \(deviceID)"); return }
        print("[NCM] Starting outgoing transfer to \(info.device?.name ?? "Unknown") (\(deviceID))")
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let nwconn = NWConnection(to: info.service.endpoint, using: NWParameters(tls: .none, tcp: tcp))
        let conn = OutboundNearbyConnection(connection: nwconn, id: deviceID, urlsToSend: urls)
        conn.delegate = self
        conn.qrCodePrivateKey=qrCodePrivateKey
        outgoingTransfers[deviceID] = OutgoingTransferInfo(service: info.service, device: info.device!, connection: conn, delegate: delegate)

        let transferInfo = TransferProgressInfo(id: deviceID, deviceName: info.device!.name, fileDescription: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files", direction: .outgoing, iconName: "arrow.up.doc")
        DispatchQueue.main.async { self.transfers.insert(transferInfo, at: 0) }
        conn.start()
    }

    func outboundConnectionWasEstablished(connection: OutboundNearbyConnection) {
        if let transfer = outgoingTransfers[connection.id] {
            print("[NCM] Outbound connection to \(transfer.device.name) established. PIN: \(connection.pinCode ?? "N/A")")
            DispatchQueue.main.async { transfer.delegate.connectionWasEstablished(pinCode: connection.pinCode!) }
        }
    }

    func outboundConnectionTransferAccepted(connection: OutboundNearbyConnection) {
        if let transfer = outgoingTransfers[connection.id] {
            print("[NCM] Transfer to \(transfer.device.name) accepted by peer.")
            DispatchQueue.main.async {
                transfer.delegate.transferAccepted()
                if let index = self.transfers.firstIndex(where: { $0.id == connection.id }) { self.transfers[index].state = .inProgress }
            }
        }
    }

    func outboundConnection(connection: OutboundNearbyConnection, transferProgress: Double) {
        if let transfer = outgoingTransfers[connection.id] {
            DispatchQueue.main.async {
                transfer.delegate.transferProgress(progress: transferProgress)
                if let index = self.transfers.firstIndex(where: { $0.id == connection.id }) { self.transfers[index].progress = transferProgress }
            }
        }
    }

    func outboundConnection(connection: OutboundNearbyConnection, failedWithError: Error) {
        if let transfer = outgoingTransfers.removeValue(forKey: connection.id) {
            print("[NCM] Outbound connection to \(transfer.device.name) failed with error: \(failedWithError)")
            DispatchQueue.main.async {
                transfer.delegate.connectionFailed(with: failedWithError)
                if let index = self.transfers.firstIndex(where: { $0.id == connection.id }) { self.transfers[index].state = .failed; self.scheduleCleanup(for: connection.id) }
            }
        }
    }

    func outboundConnectionTransferFinished(connection: OutboundNearbyConnection) {
        if let transfer = outgoingTransfers.removeValue(forKey: connection.id) {
            print("[NCM] Outbound transfer to \(transfer.device.name) finished successfully.")
            DispatchQueue.main.async {
                transfer.delegate.transferFinished()
                if let index = self.transfers.firstIndex(where: { $0.id == connection.id }) { self.transfers[index].state = .finished; self.scheduleCleanup(for: connection.id) }
            }
        }
    }

    private func scheduleCleanup(for transferID: String) {
        cleanupTimers[transferID]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.transfers.removeAll { $0.id == transferID }
                self.cleanupTimers.removeValue(forKey: transferID)
            }
        }
        cleanupTimers[transferID] = timer
    }

    private func fileDescription(for transfer: TransferMetadata) -> String {
        if let text = transfer.textDescription { return text }
        if transfer.files.count == 1 { return transfer.files[0].name }
        return "\(transfer.files.count) files"
    }

    private func iconName(for transfer: TransferMetadata) -> String {
        if let desc = transfer.textDescription {
             if let _ = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue).firstMatch(in: desc, options: [], range: NSRange(location: 0, length: desc.utf16.count)) { return "link" }
            return "text.quote"
        }
        guard let firstFile = transfer.files.first else { return "questionmark" }
        if transfer.files.count > 1 { return "doc.on.doc.fill" }
        let mimeType = firstFile.mimeType.lowercased()
        if mimeType.starts(with: "image/") { return "photo" }
        if mimeType.starts(with: "video/") { return "video.fill" }
        if mimeType.starts(with: "audio/") { return "music.note" }
        if mimeType.contains("pdf") { return "doc.richtext.fill" }
        if mimeType.contains("zip") || mimeType.contains("archive") { return "archivebox.fill" }
        return "doc.fill"
    }
}