//
//  OpenBubblesActivationView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-13
//

import SwiftUI
import QRCode
import CommonCrypto
import SwiftProtobuf

// MARK: - Custom Button Style for Pill Shape
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.1 : 0.2))
            .clipShape(Capsule())
            .foregroundColor(.accentColor)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct OpenBubblesActivationView: View {
    // MARK: - State Properties
    @State private var preventSharing: Bool = false
    @State private var hardwareQrImage: CGImage?
    @State private var appDownloadQrImage: CGImage?
    @State private var oneTimeActivationCode: String?
    @State private var defaultActivationCode: String?
    @State private var buttonState: ButtonState = .idle
    @State private var isShowingDownloadQrSheet: Bool = false

    @State private var identifiers: Data?

    private var buttonTitle: String {
        switch buttonState {
        case .idle: return "Generate One-Time Activation Code"
        case .processing: return "Generating..."
        case .success: return "Succeeded!"
        case .error: return "An Error Occurred"
        }
    }

    enum ButtonState {
        case idle, processing, success, error
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading) {
                Text("iMessage Registration")
                    .font(.largeTitle.bold())
                Text("For OpenBubbles")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title).foregroundStyle(.blue)
                    Text("What is OpenBubbles?").font(.headline)
                }
                Text("OpenBubbles is a free, open-source project that brings iMessage, FaceTime, and other Apple services to Android, Windows, and Linux. This tool generates a registration code using your Mac's hardware identifiers, allowing other devices to connect directly to Apple's services.")
                    .font(.subheadline).foregroundStyle(.secondary)

                Divider().padding(.vertical, 5)

                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Link(destination: URL(string: "https://openbubbles.app")!) {
                            Label("Visit Website", systemImage: "safari.fill")
                        }
                        .buttonStyle(PillButtonStyle())

                        Link(destination: URL(string: "https://discord.gg/98fWS4AQqN")!) {
                            Label("Join Discord", systemImage: "message.fill")
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                    GridRow {
                        Link(destination: URL(string: "https://play.google.com/store/apps/details?id=com.openbubbles.messaging")!) {
                            Label("Download App", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(PillButtonStyle())

                        Button(action: { isShowingDownloadQrSheet = true }) {
                            Label("Show QR to Download", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }
            }
            .padding()
            .background(.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(alignment: .top, spacing: 20) {
                VStack {
                    if let hardwareQrImage {
                        Image(hardwareQrImage, scale: 1.0, label: Text("Hardware Info QR Code"))
                            .interpolation(.none).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 180, height: 180).padding(10).background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 15) {
                    Text("This QR code contains your Mac's unique hardware data. **Scan it with the OpenBubbles app** on your other devices to register them for iMessage.")
                        .font(.caption).foregroundStyle(.secondary)

                    Toggle("Generate a shareable, single-use code", isOn: $preventSharing)

                    if preventSharing {
                        oneTimeCodeSection
                    } else {
                        defaultCodeSection
                    }
                }
                .animation(.easeInOut, value: preventSharing)
            }
        }
        .task {
            await loadHardwareInfo(); generateAppDownloadQrCode()
        }
        .sheet(isPresented: $isShowingDownloadQrSheet) {
            AppDownloadQrView(qrImage: appDownloadQrImage)
        }
    }

    // MARK: - Subviews
    @ViewBuilder private var oneTimeCodeSection: some View {
        VStack {
            if let code = oneTimeActivationCode {
                VStack(alignment: .leading) {
                    Text("Your One-Time Code:").font(.caption)
                    HStack {
                        TextField("Activation Code", text: .constant(code)).textFieldStyle(.plain).disabled(true)
                        Button(action: { copyToClipboard(code) }) { Image(systemName: "doc.on.doc.fill") }.buttonStyle(.plain)
                    }.padding(8).background(Color.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Button(action: generateOneTimeCode) {
                Text(buttonTitle).fontWeight(.semibold).frame(maxWidth: .infinity).padding(10)
                    .background(buttonState == .processing ? Color.gray.gradient : Color.accentColor.gradient)
                    .foregroundColor(.white).cornerRadius(8)
            }.buttonStyle(.plain).disabled(buttonState == .processing || identifiers == nil)
        }.transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder private var defaultCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("Do not share this code publicly. It is permanently tied to your Mac's hardware identity.").font(.caption)
            }.padding(10).background(.orange.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Your Personal Code (Unlimited Use):").font(.caption)
            if let code = defaultActivationCode {
                HStack {
                    TextField("Activation Code", text: .constant(code)).textFieldStyle(.plain).disabled(true)
                    Button(action: { copyToClipboard(code) }) { Image(systemName: "doc.on.doc.fill") }.buttonStyle(.plain)
                }.padding(8).background(Color.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ProgressView().frame(height: 30)
            }
        }.transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Logic & Helpers
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    private func loadHardwareInfo() async {
        if identifiers != nil { return }
        let data = await Task.detached(priority: .userInitiated) { try? getHwInfo().serializedData() }.value
        self.identifiers = data; updateHardwareQrCode(); generateDefaultActivationCode()
    }
    private func generateAppDownloadQrCode() {
        let urlString = "https://play.google.com/store/apps/details?id=com.openbubbles.messaging"
        self.appDownloadQrImage = try? QRCode.Document(utf8String: urlString, errorCorrection: .low).cgImage(CGSize(width: 256, height: 256))
    }
    private func generateDefaultActivationCode() {
        guard let identifiers else { return }
        var data = "OABS".data(using: .utf8)!; data.append(0); data.append(identifiers)
        self.defaultActivationCode = data.base64EncodedString()
    }
    private func getPayloadForOneTimeCode() -> Data? {
        guard let identifiers else { return nil }
        var data = "OABS".data(using: .utf8)!; data.append(1); data.append(identifiers)
        return data
    }
    private func updateHardwareQrCode() {
        guard let identifiers else { return }
        var data = "OABS".data(using: .utf8)!; data.append(0); data.append(identifiers)
        self.hardwareQrImage = try? QRCode.Document(data: data, errorCorrection: .medium).cgImage(CGSize(width: 512, height: 512))
    }
    private func generateOneTimeCode() {
        guard let payload = getPayloadForOneTimeCode() else { return }
        buttonState = .processing; oneTimeActivationCode = nil
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ123456789"); var code = "MB"
        for i in 0..<4 {
            var bytes = [UInt8](repeating: 0, count: 4)
            guard SecRandomCopyBytes(kSecRandomDefault, 4, &bytes) == errSecSuccess else { self.buttonState = .error; return }
            code += bytes.map { chars[Int($0) % chars.count] }; if i != 3 { code += "-" }
        }
        let serverCode = sha256(data: code.data(using: .utf8)!).map { String(format: "%02x", $0) }.joined()
        let encrypted = encryptAESDart(textData: payload, passphrase: code)
        guard let url = URL(string: "https://hw.openbubbles.app/code") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        struct CodeMessage: Encodable { let data: String, id: String }
        guard let httpBody = try? JSONEncoder().encode(CodeMessage(data: encrypted, id: serverCode)) else { self.buttonState = .error; return }
        request.httpBody = httpBody; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async {
                if statusCode == 200 { self.oneTimeActivationCode = code; self.buttonState = .success }
                else { self.buttonState = .error }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.buttonState = .idle }
            }
        }
        task.resume()
    }
    private func deriveKeyAndIV(passphrase: String, salt: Data) -> (key: Data, iv: Data) {
        let password = passphrase.data(using: .utf8)!; var concatenatedHashes = Data(); var currentHash = Data()
        while concatenatedHashes.count < 48 {
            let preHash = currentHash + password + salt; currentHash = MD5(messageData: preHash)
            concatenatedHashes += currentHash
        }
        return (key: concatenatedHashes[0..<32], iv: concatenatedHashes[32..<48])
    }
    private func encryptAESDart(textData: Data, passphrase: String) -> String {
        var salt = Data(count: 8)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }) == errSecSuccess else { fatalError("Failed to generate salt") }
        let keyAndIv = deriveKeyAndIV(passphrase: passphrase, salt: salt); var encryptedBytes = "Salted__".data(using: .utf8)! + salt
        let dataOutSize = textData.count + kCCBlockSizeAES128; var dataOut = Data(count: dataOutSize); var numBytesEncrypted: size_t = 0
        let cryptStatus = dataOut.withUnsafeMutableBytes { dataOutBytes in
            textData.withUnsafeBytes { textBytes in
                keyAndIv.key.withUnsafeBytes { keyBytes in
                    keyAndIv.iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress, kCCKeySizeAES256, ivBytes.baseAddress, textBytes.baseAddress, textData.count, dataOutBytes.baseAddress, dataOutSize, &numBytesEncrypted)
                    }
                }
            }
        }
        guard cryptStatus == kCCSuccess else { fatalError("Encryption failed") }
        dataOut.count = numBytesEncrypted; encryptedBytes += dataOut
        return encryptedBytes.base64EncodedString()
    }
}

// MARK: - Helper View for QR Code Sheet
struct AppDownloadQrView: View {
    let qrImage: CGImage?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Text("Scan to Download").font(.largeTitle.bold())
            Text("Open the camera app on your phone and point it at this QR code to go to the download page.")
                .font(.headline).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            if let qrImage {
                Image(qrImage, scale: 1.0, label: Text("App Download QR Code"))
                    .interpolation(.none).resizable().scaledToFit().frame(width: 250, height: 250)
                    .background(Color.white).padding(10).clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ProgressView().frame(width: 250, height: 250)
            }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).padding(.top)
        }.padding(40).frame(minWidth: 400, minHeight: 450)
    }
}