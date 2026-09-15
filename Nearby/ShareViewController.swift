//
//  ShareViewController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 12.09.2023.
//

import Foundation
import Cocoa
import QRCode
import UniformTypeIdentifiers

class ShareViewController: NSViewController, ShareExtensionDelegate{

    private var urls:[URL]=[]
    private var foundDevices:[RemoteDeviceInfo]=[]
    private var chosenDevice:RemoteDeviceInfo?
    private var lastError:Error?
    private var sheetWindow:NSWindow?
    private var pendingAttachmentURLs: [URL?] = []
    private var pendingAttachmentCount = 0
    private var dismissalWorkItem: DispatchWorkItem?

    @IBOutlet var filesIcon:NSImageView?
    @IBOutlet var filesLabel:NSTextField?
    @IBOutlet var loadingOverlay:NSStackView?
    @IBOutlet var largeProgress:NSProgressIndicator?
    @IBOutlet var listView:NSCollectionView?
    @IBOutlet var listViewWrapper:NSView?
    @IBOutlet var contentWrap:NSView?
    @IBOutlet var progressView:NSView?
    @IBOutlet var progressDeviceIcon:NSImageView?
    @IBOutlet var progressDeviceName:NSTextField?
    @IBOutlet var progressProgressBar:NSProgressIndicator?
    @IBOutlet var progressState:NSTextField?
    @IBOutlet var progressDeviceIconWrap:NSView?
    @IBOutlet var progressDeviceSecondaryIcon:NSImageView?
    @IBOutlet var qrCodeButton:NSButton?

    @IBOutlet var qrCodeSheetView:NSView?
    @IBOutlet var qrCodeView:NSImageView?
    @IBOutlet var qrCodeWrapView:NSView?

    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }

    override func loadView() {
        super.loadView()

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments,
              !attachments.isEmpty else {
            cancelExtension(with: NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError))
            return
        }

        pendingAttachmentURLs = Array(repeating: nil, count: attachments.count)
        pendingAttachmentCount = attachments.count
        for (index, provider) in attachments.enumerated() {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
                let loadedURL: URL?
                if let data = item as? Data {
                    loadedURL = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: false)
                } else if let url = item as? URL {
                    loadedURL = url
                } else if let url = item as? NSURL {
                    loadedURL = url as URL
                } else {
                    loadedURL = nil
                }
                DispatchQueue.main.async {
                    self?.attachmentDidLoad(at: index, url: loadedURL, error: error)
                }
            }
        }

        guard let contentWrap,
              let listViewWrapper,
              let loadingOverlay,
              let progressView else {
            cancelExtension(with: NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError))
            return
        }

        contentWrap.addSubview(listViewWrapper)
        contentWrap.addSubview(loadingOverlay)
        contentWrap.addSubview(progressView)
        progressView.isHidden=true

        listViewWrapper.translatesAutoresizingMaskIntoConstraints=false
        loadingOverlay.translatesAutoresizingMaskIntoConstraints=false
        progressView.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([
            listViewWrapper.widthAnchor.constraint(equalTo: contentWrap.widthAnchor),
            listViewWrapper.heightAnchor.constraint(equalTo: contentWrap.heightAnchor),
            loadingOverlay.widthAnchor.constraint(equalTo: contentWrap.widthAnchor),
            loadingOverlay.centerYAnchor.constraint(equalTo: contentWrap.centerYAnchor),
            progressView.widthAnchor.constraint(equalTo: contentWrap.widthAnchor),
            progressView.centerYAnchor.constraint(equalTo: contentWrap.centerYAnchor)
        ])

        largeProgress?.startAnimation(nil)
        let flowLayout=NSCollectionViewFlowLayout()
        flowLayout.itemSize=NSSize(width: 75, height: 90)
        flowLayout.sectionInset=NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        flowLayout.minimumInteritemSpacing=10
        flowLayout.minimumLineSpacing=10
        listView?.collectionViewLayout=flowLayout
        listView?.dataSource=self

        progressDeviceIconWrap?.wantsLayer=true
        progressDeviceIconWrap?.layer?.masksToBounds=false

        qrCodeWrapView?.wantsLayer=true
        qrCodeWrapView?.layer?.masksToBounds=false
        qrCodeWrapView?.layer?.shadowColor = .black
        qrCodeWrapView?.layer?.shadowOpacity=0.3
        qrCodeWrapView?.layer?.shadowRadius=12
        qrCodeWrapView?.layer?.shadowOffset=CGSizeMake(0, -5)
    }

    override func viewDidLoad(){
        super.viewDidLoad()
        NearbyConnectionManager.shared.startDeviceDiscovery()
        NearbyConnectionManager.shared.addShareExtensionDelegate(self)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        dismissalWorkItem?.cancel()
        if chosenDevice==nil{
            NearbyConnectionManager.shared.stopDeviceDiscovery()
        }
        NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
    }

    @IBAction func cancel(_ sender: AnyObject?) {
        if let deviceID=chosenDevice?.id{
            NearbyConnectionManager.shared.cancelOutgoingTransfer(id: deviceID)
        }
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        cancelExtension(with: cancelError)
    }

    @IBAction func useQrCode(_ sender: AnyObject?) {
        guard let window=contentWrap?.window,
              let qrCodeSheetView,
              let qrCodeView else { return }
        let sheetWindow=NSWindow()
        sheetWindow.contentView=qrCodeSheetView
        let size=NSSize(width: 380, height: 400)
        sheetWindow.contentMaxSize=size
        sheetWindow.contentMinSize=size
        sheetWindow.setContentSize(size)

        let qrKey=NearbyConnectionManager.shared.generateQrCodeKey()
        do {
            let qrCodeImage=try QRCode.build
                .text("https://quickshare.google/qrcode#key=\(qrKey)")
                .backgroundColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0))
                .quietZonePixelCount(3)
                .onPixels.shape(.circle())
                .eye.shape(.roundedPointing())
                .errorCorrection(.low)
                .generate.image(dimension: max(Int(qrCodeView.frame.width)*2, 256))
            qrCodeView.image=NSImage(cgImage: qrCodeImage, size: qrCodeImage.size)
        } catch {
            lastError = error
            connectionFailed(with: error)
            return
        }

        self.sheetWindow=sheetWindow
        window.beginSheet(sheetWindow) { [weak self] _ in
            self?.sheetWindow=nil
        }
    }

    @IBAction func dismissQrCodeSheet(_ sender: AnyObject?){
        guard let sheetWindow, let window=contentWrap?.window else { return }
        window.endSheet(sheetWindow)
        self.sheetWindow=nil
    }

    private func attachmentDidLoad(at index: Int, url: URL?, error: Error?) {
        guard pendingAttachmentURLs.indices.contains(index), pendingAttachmentCount > 0 else { return }
        pendingAttachmentURLs[index] = url
        if let error, lastError == nil { lastError = error }
        pendingAttachmentCount -= 1
        guard pendingAttachmentCount == 0 else { return }

        guard lastError == nil,
              pendingAttachmentURLs.allSatisfy({ $0 != nil }) else {
            cancelExtension(with: lastError ?? NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError))
            return
        }
        urls = pendingAttachmentURLs.compactMap { $0 }
        urlsReady()
    }

    private func cancelExtension(with error: Error) {
        extensionContext?.cancelRequest(withError: error)
    }

    private func urlsReady(){
        for url in urls{
            if url.isFileURL{
                var isDirectory = ObjCBool(false)
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue{
                    print("Canceling share request because URL \(url) is a directory")
                    let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
                    cancelExtension(with: cancelError)
                    return
                }
            }
        }
        if urls.count==1{
            if urls[0].isFileURL{
                filesLabel?.stringValue=urls[0].lastPathComponent
                filesIcon?.image=NSWorkspace.shared.icon(forFile: urls[0].path)
            }else if urls[0].scheme=="http" || urls[0].scheme=="https"{
                filesLabel?.stringValue=urls[0].absoluteString
                filesIcon?.image=NSImage(named: NSImage.networkName)
            }
        }else{
            filesLabel?.stringValue=String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), urls.count)
            filesIcon?.image=NSImage(named: NSImage.multipleDocumentsName)
        }
    }

    func addDevice(device: RemoteDeviceInfo) {
        guard !foundDevices.contains(where: { $0.id == device.id }) else { return }
        if foundDevices.isEmpty{
            loadingOverlay?.animator().isHidden=true
        }
        foundDevices.append(device)
        listView?.animator().insertItems(at: [[0, foundDevices.count-1]])
    }

    func removeDevice(id: String){
        if chosenDevice != nil{
            return
        }
        for i in foundDevices.indices{
            if foundDevices[i].id==id{
                foundDevices.remove(at: i)
                listView?.animator().deleteItems(at: [[0, i]])
                break
            }
        }
        if foundDevices.isEmpty{
            loadingOverlay?.animator().isHidden=false
        }
    }

    func startTransferWithQrCode(device: RemoteDeviceInfo){
        if sheetWindow != nil { dismissQrCodeSheet(nil) }
        selectDevice(device: device)
    }

    func connectionWasEstablished(pinCode: String) {
        progressState?.stringValue=String(format:NSLocalizedString("PinCode", value: "PIN: %@", comment: ""), arguments: [pinCode])
        progressProgressBar?.isIndeterminate=false
        progressProgressBar?.maxValue=1000
        progressProgressBar?.doubleValue=0
    }

    func connectionFailed(with error: Error) {
        progressProgressBar?.isIndeterminate=false
        progressProgressBar?.maxValue=1000
        progressProgressBar?.doubleValue=0
        lastError=error
        if let ne=(error as? NearbyError), case let .canceled(reason)=ne{
            switch reason{
            case .userRejected:
                progressState?.stringValue=NSLocalizedString("TransferDeclined", value: "Declined", comment: "")
            case .userCanceled:
                progressState?.stringValue=NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
            case .notEnoughSpace:
                progressState?.stringValue=NSLocalizedString("NotEnoughSpace", value: "Not enough disk space", comment: "")
            case .unsupportedType:
                progressState?.stringValue=NSLocalizedString("UnsupportedType", value: "Attachment type not supported", comment: "")
            case .timedOut:
                progressState?.stringValue=NSLocalizedString("TransferTimedOut", value: "Timed out", comment: "")
            }
            progressDeviceSecondaryIcon?.isHidden=false
            dismissDelayed()
        }else{
            let alert=NSAlert(error: error)
            guard let window=view.window else {
                cancelExtension(with: error)
                return
            }
            alert.beginSheetModal(for: window) { [weak self] _ in
                self?.cancelExtension(with: error)
            }
        }
    }

    func transferAccepted() {
        progressState?.stringValue=NSLocalizedString("Sending", value: "Sending...", comment: "")
    }

    func transferProgress(progress: Double) {
        guard let progressProgressBar else { return }
        progressProgressBar.doubleValue=min(max(progress, 0), 1)*progressProgressBar.maxValue
    }

    func transferFinished() {
        progressState?.stringValue=NSLocalizedString("TransferFinished", value: "Transfer finished", comment: "")
        dismissDelayed()
    }

    func selectDevice(device:RemoteDeviceInfo){
        guard let deviceID=device.id else {
            connectionFailed(with: NearbyError.protocolError("Selected device has no endpoint identifier"))
            return
        }
        NearbyConnectionManager.shared.stopDeviceDiscovery()
        listViewWrapper?.animator().isHidden=true
        progressView?.animator().isHidden=false
        qrCodeButton?.animator().isHidden=true
        progressDeviceName?.stringValue=device.name
        progressDeviceIcon?.image=imageForDeviceType(type: device.type)
        progressProgressBar?.startAnimation(nil)
        progressState?.stringValue=NSLocalizedString("Connecting", value: "Connecting...", comment: "")
        chosenDevice=device
        NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: deviceID, delegate: self, urls: urls)
    }

    private func dismissDelayed(){
        dismissalWorkItem?.cancel()
        let workItem=DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let error=self.lastError{
                self.cancelExtension(with: error)
            }else{
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
        dismissalWorkItem=workItem
        DispatchQueue.main.asyncAfter(deadline: .now()+2.0, execute: workItem)
    }
}

fileprivate func imageForDeviceType(type:RemoteDeviceInfo.DeviceType)->NSImage{
    let imageName:String
    switch type{
    case .tablet:
        imageName="com.apple.ipad"
    case .computer:
        imageName="com.apple.macbookpro-13-unibody"
    default:
        imageName="com.apple.iphone"
    }
    if let image=NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(imageName).icns") {
        return image
    }
    return NSImage(systemSymbolName: "laptopcomputer.and.iphone", accessibilityDescription: nil) ?? NSImage()
}

extension ShareViewController:NSCollectionViewDataSource{
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return foundDevices.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item=collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DeviceListCell"), for: indexPath)
        guard let collectionViewItem = item as? DeviceListCell else {return item}
        guard foundDevices.indices.contains(indexPath.item) else { return item }
        let device=foundDevices[indexPath.item]
        collectionViewItem.textField?.stringValue=device.name
        collectionViewItem.imageView?.image=imageForDeviceType(type: device.type)
        collectionViewItem.clickHandler={
            self.selectDevice(device: device)
        }
        return collectionViewItem
    }
}