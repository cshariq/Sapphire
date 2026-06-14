import Foundation
import Combine

// MARK: - Live API Configuration
struct GeminiLiveConfiguration {
    var apiKey: String {
        APIKeyManager.shared.geminiAPIKey
    }

    /// Gemini 3.1 Flash Live Preview — low-latency audio-to-audio Live API model.
    var model: String {
        "models/gemini-3.1-flash-live-preview"
    }

    var systemInstruction: String? {
        "You are Sapphire, a concise and helpful voice assistant running on macOS."
    }
}

// MARK: - WebSocket URL
extension GeminiAPI {
    static func liveWebSocketURL(apiKey: String) -> URL {
        URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)")!
    }
}

// MARK: - Message Types
enum GeminiLiveServerMessage {
    case setupComplete
    case serverContent(modelTurn: [String: Any]?, turnComplete: Bool, interrupted: Bool)
    case toolCall(functionCalls: [[String: Any]])
    case toolCallCancellation(ids: [String])
}

enum GeminiLiveError: LocalizedError {
    case websocketError(String)
    case apiError(String)
    case disconnected
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .websocketError(let msg): return "WebSocket error: \(msg)"
        case .apiError(let msg): return "Gemini Live API error: \(msg)"
        case .disconnected: return "Disconnected from Gemini Live"
        case .invalidMessage: return "Invalid message from server"
        }
    }
}

// MARK: - Gemini API
struct GeminiAPI {
    static let modelName = "models/gemini-2.0-flash-exp"
}

// MARK: - Protobuf Encoding
enum ProtoWireType: Int {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

func protoTag(field: Int, wireType: ProtoWireType) -> Data {
    encodeVarint(UInt64((field << 3) | wireType.rawValue))
}

func encodeVarint(_ value: UInt64) -> Data {
    var v = value
    var data = Data()
    while v > 127 {
        data.append(UInt8(v & 0x7F) | 0x80)
        v >>= 7
    }
    data.append(UInt8(v))
    return data
}

func encodeString(field: Int, _ value: String) -> Data {
    guard let stringData = value.data(using: .utf8) else { return Data() }
    var data = protoTag(field: field, wireType: .lengthDelimited)
    data.append(encodeVarint(UInt64(stringData.count)))
    data.append(stringData)
    return data
}

func encodeBytes(field: Int, _ value: Data) -> Data {
    var data = protoTag(field: field, wireType: .lengthDelimited)
    data.append(encodeVarint(UInt64(value.count)))
    data.append(value)
    return data
}

func encodeMessage(field: Int, _ messageData: Data) -> Data {
    var data = protoTag(field: field, wireType: .lengthDelimited)
    data.append(encodeVarint(UInt64(messageData.count)))
    data.append(messageData)
    return data
}

func encodeBool(field: Int, _ value: Bool) -> Data {
    var data = protoTag(field: field, wireType: .varint)
    data.append(encodeVarint(value ? 1 : 0))
    return data
}

func encodeInt32(field: Int, _ value: Int32) -> Data {
    var data = protoTag(field: field, wireType: .varint)
    data.append(encodeVarint(UInt64(bitPattern: Int64(value))))
    return data
}

func encodeFloat32(field: Int, _ value: Float32) -> Data {
    var data = protoTag(field: field, wireType: .fixed32)
    var val = value
    withUnsafeBytes(of: &val) { data.append(contentsOf: $0) }
    return data
}

// MARK: - Part & Content Encoding
func encodePart(_ part: [String: Any]) -> Data {
    if let text = part["text"] as? String {
        return encodeString(field: 1, text)
    } else if let inlineData = part["inlineData"] as? [String: Any] {
        return encodeBlob(inlineData, field: 6)
    } else if let functionCall = part["functionCall"] as? [String: Any] {
        return encodeFunctionCallMessage(functionCall)
    } else if let functionResponse = part["functionResponse"] as? [String: Any] {
        return encodeFunctionResponseMessage(functionResponse)
    }
    return Data()
}

func encodeBlob(_ blob: [String: Any], field: Int = 6) -> Data {
    var data = Data()
    if let mimeType = blob["mimeType"] as? String {
        data.append(encodeString(field: 1, mimeType))
    }
    if let base64Data = blob["data"] as? String,
       let decodedData = Data(base64Encoded: base64Data) {
        data.append(encodeBytes(field: 2, decodedData))
    } else if let rawData = blob["data"] as? Data {
        data.append(encodeBytes(field: 2, rawData))
    }
    return encodeMessage(field: field, data)
}

func encodeContent(parts: [[String: Any]], role: String? = nil) -> Data {
    var data = Data()
    for part in parts {
        data.append(encodePart(part))
    }
    if let role = role {
        data.append(encodeString(field: 2, role))
    }
    return data
}

func encodeFunctionCallMessage(_ fc: [String: Any]) -> Data {
    var data = Data()
    if let name = fc["name"] as? String {
        data.append(encodeString(field: 1, name))
    }
    if let args = fc["args"] as? [String: Any],
       let argsData = try? JSONSerialization.data(withJSONObject: args) {
        data.append(encodeBytes(field: 2, argsData))
    }
    return encodeMessage(field: 4, data)
}

func encodeFunctionResponseMessage(_ fr: [String: Any]) -> Data {
    var data = Data()
    if let name = fr["name"] as? String {
        data.append(encodeString(field: 1, name))
    }
    if let response = fr["response"] as? [String: Any],
       let respData = try? JSONSerialization.data(withJSONObject: response) {
        data.append(encodeBytes(field: 2, respData))
    }
    return encodeMessage(field: 5, data)
}

// MARK: - Tool Encoding
func encodeFunctionDeclaration(_ decl: [String: Any]) -> Data {
    var data = Data()
    if let name = decl["name"] as? String {
        data.append(encodeString(field: 1, name))
    }
    if let description = decl["description"] as? String {
        data.append(encodeString(field: 2, description))
    }
    if let parameters = decl["parameters"] as? [String: Any] {
        data.append(encodeMessage(field: 3, encodeSchema(parameters)))
    }
    return encodeMessage(field: 1, data)
}

func encodeSchema(_ schema: [String: Any]) -> Data {
    var data = Data()
    if let type = schema["type"] as? String {
        let typeValue: Int32
        switch type.lowercased() {
        case "string": typeValue = 1
        case "number": typeValue = 2
        case "integer": typeValue = 3
        case "boolean": typeValue = 4
        case "array": typeValue = 5
        case "object": typeValue = 6
        default: typeValue = 0
        }
        data.append(encodeInt32(field: 1, typeValue))
    }
    if let format = schema["format"] as? String {
        data.append(encodeString(field: 2, format))
    }
    if let description = schema["description"] as? String {
        data.append(encodeString(field: 3, description))
    }
    if let items = schema["items"] as? [String: Any] {
        data.append(encodeMessage(field: 6, encodeSchema(items)))
    }
    if let properties = schema["properties"] as? [String: Any] {
        for (key, value) in properties {
            if let propSchema = value as? [String: Any] {
                var entry = encodeString(field: 1, key)
                entry.append(encodeMessage(field: 2, encodeSchema(propSchema)))
                data.append(encodeMessage(field: 7, entry))
            }
        }
    }
    if let required = schema["required"] as? [String] {
        for r in required {
            data.append(encodeString(field: 8, r))
        }
    }
    if let `enum` = schema["enum"] as? [String] {
        for e in `enum` {
            data.append(encodeString(field: 9, e))
        }
    }
    return data
}

// MARK: - Generation Config Encoding
func encodeGenerationConfig(_ config: [String: Any]) -> Data {
    var data = Data()
    if let temp = config["temperature"] as? Double {
        data.append(encodeFloat32(field: 2, Float32(temp)))
    }
    if let topP = config["topP"] as? Double {
        data.append(encodeFloat32(field: 3, Float32(topP)))
    }
    if let topK = config["topK"] as? NSNumber {
        data.append(encodeFloat32(field: 4, Float32(truncating: topK)))
    } else if let topK = config["topK"] as? Double {
        data.append(encodeFloat32(field: 4, Float32(topK)))
    }
    if let maxTokens = config["maxOutputTokens"] as? Double {
        data.append(encodeInt32(field: 6, Int32(maxTokens)))
    } else if let maxTokens = config["maxOutputTokens"] as? Int {
        data.append(encodeInt32(field: 6, Int32(maxTokens)))
    }
    if let modalities = config["responseModalities"] as? [String] {
        for m in modalities {
            data.append(encodeString(field: 14, m))
        }
    }
    return data
}

// MARK: - Build Complete Messages
func encodeSetupMessage(model: String, systemInstruction: String?, generationConfig: [String: Any]?) -> Data {
    var setupData = Data()
    setupData.append(encodeString(field: 1, model))

    if let sysInstr = systemInstruction, !sysInstr.isEmpty {
        let contentData = encodeContent(parts: [["text": sysInstr]])
        setupData.append(encodeMessage(field: 2, contentData))
    }

    if let genCfg = generationConfig {
        setupData.append(encodeMessage(field: 5, encodeGenerationConfig(genCfg)))
    }

    var requestData = Data()
    requestData.append(encodeMessage(field: 1, setupData))
    return addGrpcWebFrame(requestData)
}

func encodeClientContentMessage(turns: [[String: Any]], turnCompleteMode: Int32 = 1) -> Data {
    var contentData = Data()
    for turn in turns {
        guard let parts = turn["parts"] as? [[String: Any]] else { continue }
        let role = turn["role"] as? String
        let turnData = encodeContent(parts: parts, role: role)
        contentData.append(encodeMessage(field: 1, turnData))
    }
    contentData.append(encodeInt32(field: 2, turnCompleteMode))

    var requestData = Data()
    requestData.append(encodeMessage(field: 2, contentData))
    return addGrpcWebFrame(requestData)
}

func encodeRealtimeInputMessage(audioData: Data) -> Data {
    var blobData = encodeString(field: 1, "audio/pcm")
    blobData.append(encodeBytes(field: 2, audioData))

    let inputData = encodeMessage(field: 1, blobData)

    var requestData = Data()
    requestData.append(encodeMessage(field: 3, inputData))
    return addGrpcWebFrame(requestData)
}

func encodeToolResponseMessage(functionResponses: [[String: Any]]) -> Data {
    var toolData = Data()
    for response in functionResponses {
        var frData = Data()
        if let name = response["name"] as? String {
            frData.append(encodeString(field: 1, name))
        }
        if let resp = response["response"] as? [String: Any],
           let respData = try? JSONSerialization.data(withJSONObject: resp) {
            frData.append(encodeBytes(field: 2, respData))
        }
        toolData.append(encodeMessage(field: 1, frData))
    }

    var requestData = Data()
    requestData.append(encodeMessage(field: 4, toolData))
    return addGrpcWebFrame(requestData)
}

func encodeInterruptMessage() -> Data {
    var requestData = Data()
    requestData.append(encodeBool(field: 5, true))
    return addGrpcWebFrame(requestData)
}

// MARK: - gRPC-Web Framing
func addGrpcWebFrame(_ payload: Data) -> Data {
    var frame = Data()
    frame.append(0x00)
    var length = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
    frame.append(payload)
    return frame
}

// MARK: - Protobuf Decoding
func parseTag(_ data: Data, offset: Int) -> (field: Int, wireType: Int)? {
    guard offset < data.count else { return nil }
    let (varint, _) = parseVarint(data, offset: offset) ?? (0, 0)
    let field = Int(varint >> 3)
    let wire = Int(varint & 0x7)
    return (field, wire)
}

func parseVarint(_ data: Data, offset: Int) -> (UInt64, Int)? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    var consumed = 0
    for i in offset..<data.count {
        let byte = data[i]
        result |= UInt64(byte & 0x7F) << shift
        consumed += 1
        if byte & 0x80 == 0 {
            return (result, consumed)
        }
        shift += 7
    }
    return nil
}

func varintLength(_ data: Data, offset: Int) -> Int {
    var consumed = 0
    for i in offset..<data.count {
        consumed += 1
        if data[i] & 0x80 == 0 { break }
    }
    return consumed
}

func skipField(data: Data, idx: inout Int, wireType: Int) {
    switch wireType {
    case 0:
        let _ = parseVarint(data, offset: idx)
        idx += varintLength(data, offset: idx)
    case 1:
        idx += 8
    case 2:
        guard let (_, len) = parseVarint(data, offset: idx) else { return }
        idx += varintLength(data, offset: idx)
        idx += Int(len)
    case 5:
        idx += 4
    default:
        idx += 1
    }
}

func parseLengthDelimited(_ data: Data, offset: Int) -> (Data, Int)? {
    guard let (len, vlen) = parseVarint(data, offset: offset) else { return nil }
    let start = offset + vlen
    let end = start + Int(len)
    guard end <= data.count else { return nil }
    return (data[start..<end], end - offset)
}

// MARK: - Server Message Decoding
func decodeServerWebSocketMessage(_ data: Data) -> GeminiLiveServerMessage? {
    guard data.count > 5 else { return nil }
    let payload = data.dropFirst(5)
    return parseResponsePayload(payload)
}

func parseResponsePayload(_ data: Data) -> GeminiLiveServerMessage? {
    var idx = 0
    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)

        switch (field, wireType) {
        case (1, 2):
            guard let (_, len) = parseVarint(data, offset: idx) else { return nil }
            idx += varintLength(data, offset: idx)
            idx += Int(len)
            return .setupComplete

        case (2, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { return nil }
            idx += consumed
            return parseServerContent(subData)

        case (3, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { return nil }
            idx += consumed
            return parseToolCall(subData)

        case (4, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { return nil }
            idx += consumed
            return parseToolCallCancellation(subData)

        default:
            skipField(data: data, idx: &idx, wireType: wireType)
        }
    }
    return nil
}

func parseServerContent(_ data: Data) -> GeminiLiveServerMessage {
    var modelTurn: [String: Any]?
    var turnComplete = false
    var interrupted = false

    var idx = 0
    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)

        switch (field, wireType) {
        case (1, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { idx += 1; continue }
            idx += consumed
            modelTurn = parseContent(subData)

        case (2, 0):
            guard let (val, vlen) = parseVarint(data, offset: idx) else { idx += 1; continue }
            idx += vlen
            turnComplete = val == 1

        case (3, 0):
            guard let (val, vlen) = parseVarint(data, offset: idx) else { idx += 1; continue }
            idx += vlen
            interrupted = val == 1

        default:
            skipField(data: data, idx: &idx, wireType: wireType)
        }
    }

    return .serverContent(modelTurn: modelTurn, turnComplete: turnComplete, interrupted: interrupted)
}

func parseContent(_ data: Data) -> [String: Any] {
    var result: [String: Any] = [:]
    var parts: [[String: Any]] = []
    var idx = 0

    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)

        switch (field, wireType) {
        case (1, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { idx += 1; continue }
            idx += consumed
            if let part = parsePart(subData) {
                parts.append(part)
            }

        case (2, 2):
            guard let (strData, consumed) = parseLengthDelimited(data, offset: idx) else { idx += 1; continue }
            idx += consumed
            result["role"] = String(data: strData, encoding: .utf8)

        default:
            skipField(data: data, idx: &idx, wireType: wireType)
        }
    }

    if !parts.isEmpty {
        result["parts"] = parts
    }
    return result
}

func parsePart(_ data: Data) -> [String: Any]? {
    var result: [String: Any] = [:]
    var idx = 0

    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)

        switch (field, wireType) {
        case (1, 2):
            guard let (strData, consumed) = parseLengthDelimited(data, offset: idx) else { idx += 1; continue }
            idx += consumed
            result["text"] = String(data: strData, encoding: .utf8)

        case (6, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { idx += 1; continue }
            idx += consumed
            if let blob = parseBlob(subData) {
                result["inlineData"] = blob
                if let mime = blob["mimeType"] as? String, mime.contains("audio"),
                   let audioData = blob["data"] as? Data {
                    result["audioData"] = audioData
                }
            }

        case (4, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { idx += 1; continue }
            idx += consumed
            if let fc = parseFunctionCall(subData) {
                result["functionCall"] = fc
            }

        case (5, 2):
            guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { idx += 1; continue }
            idx += consumed
            if let fr = parseFunctionResponse(subData) {
                result["functionResponse"] = fr
            }

        default:
            skipField(data: data, idx: &idx, wireType: wireType)
        }
    }

    return result.isEmpty ? nil : result
}

func parseBlob(_ data: Data) -> [String: Any]? {
    var result: [String: Any] = [:]
    var idx = 0

    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)
        guard wireType == 2 else { skipField(data: data, idx: &idx, wireType: wireType); continue }
        guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { continue }
        idx += consumed

        switch field {
        case 1:
            result["mimeType"] = String(data: subData, encoding: .utf8)
        case 2:
            result["data"] = Data(subData)
        default:
            break
        }
    }

    return result.isEmpty ? nil : result
}

func parseFunctionCall(_ data: Data) -> [String: Any]? {
    var result: [String: Any] = [:]
    var idx = 0

    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)
        guard wireType == 2 else { skipField(data: data, idx: &idx, wireType: wireType); continue }
        guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { continue }
        idx += consumed

        switch field {
        case 1:
            result["name"] = String(data: subData, encoding: .utf8)
        case 2:
            if let json = try? JSONSerialization.jsonObject(with: subData) as? [String: Any] {
                result["args"] = json
            }
        default:
            break
        }
    }

    return result.isEmpty ? nil : result
}

func parseFunctionResponse(_ data: Data) -> [String: Any]? {
    var result: [String: Any] = [:]
    var idx = 0

    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)
        guard wireType == 2 else { skipField(data: data, idx: &idx, wireType: wireType); continue }
        guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { continue }
        idx += consumed

        switch field {
        case 1:
            result["name"] = String(data: subData, encoding: .utf8)
        case 2:
            if let json = try? JSONSerialization.jsonObject(with: subData) as? [String: Any] {
                result["response"] = json
            }
        default:
            break
        }
    }

    return result.isEmpty ? nil : result
}

func parseToolCall(_ data: Data) -> GeminiLiveServerMessage {
    var functionCalls: [[String: Any]] = []
    var idx = 0

    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)
        guard field == 1, wireType == 2 else { skipField(data: data, idx: &idx, wireType: wireType); continue }
        guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { continue }
        idx += consumed
        if let fc = parseFunctionCall(subData) {
            functionCalls.append(fc)
        }
    }

    return .toolCall(functionCalls: functionCalls)
}

func parseToolCallCancellation(_ data: Data) -> GeminiLiveServerMessage {
    var ids: [String] = []
    var idx = 0

    while idx < data.count {
        guard let (field, wireType) = parseTag(data, offset: idx) else { break }
        idx += varintLength(data, offset: idx)
        guard field == 1, wireType == 2 else { skipField(data: data, idx: &idx, wireType: wireType); continue }
        guard let (subData, consumed) = parseLengthDelimited(data, offset: idx) else { continue }
        idx += consumed
        if let str = String(data: subData, encoding: .utf8) {
            ids.append(str)
        }
    }

    return .toolCallCancellation(ids: ids)
}

// MARK: - WebSocket Session (Official JSON Live API)
class GeminiLiveSession: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var isConnecting = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var apiKey: String = ""
    private var isSetupComplete = false
    private var pendingSetup: [String: Any]?

    let serverMessagePublisher = PassthroughSubject<GeminiLiveServerMessage, Never>()
    let connectionErrorPublisher = PassthroughSubject<Error, Never>()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func connect(
        apiKey: String,
        model: String,
        systemInstruction: String?,
        generationConfig: [String: Any]?
    ) {
        self.apiKey = apiKey
        guard !isConnected && !isConnecting else { return }
        isConnecting = true
        isSetupComplete = false

        var setup: [String: Any] = ["model": model]
        var genCfg = generationConfig ?? [:]
        if genCfg["responseModalities"] == nil {
            genCfg["responseModalities"] = ["AUDIO"]
        }
        setup["generationConfig"] = genCfg
        if let instruction = systemInstruction, !instruction.isEmpty {
            setup["systemInstruction"] = ["parts": [["text": instruction]]]
        }
        pendingSetup = ["setup": setup]

        let url = GeminiAPI.liveWebSocketURL(apiKey: apiKey)
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessages()
    }

    func disconnect() {
        isConnected = false
        isConnecting = false
        isSetupComplete = false
        pendingSetup = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    func sendSetup(model: String, systemInstruction: String?, generationConfig: [String: Any]?) {
        var setup: [String: Any] = ["model": model]

        if var genCfg = generationConfig {
            if genCfg["responseModalities"] == nil {
                genCfg["responseModalities"] = ["AUDIO"]
            }
            setup["generationConfig"] = genCfg
        } else {
            setup["generationConfig"] = ["responseModalities": ["AUDIO"]]
        }

        if let instruction = systemInstruction, !instruction.isEmpty {
            setup["systemInstruction"] = [
                "parts": [["text": instruction]]
            ]
        }

        let message: [String: Any] = ["setup": setup]
        if isSetupComplete {
            sendJSON(message)
        } else {
            pendingSetup = message
        }
    }

    func sendRealtimeAudio(_ audioData: Data) {
        guard isSetupComplete else { return }
        let message: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": audioData.base64EncodedString()
                ]
            ]
        ]
        sendJSON(message)
    }

    func sendClientContent(turns: [[String: Any]], turnComplete: Bool = false) {
        guard isSetupComplete else { return }
        var clientContent: [String: Any] = [:]
        if !turns.isEmpty {
            clientContent["turns"] = turns
        }
        if turnComplete {
            clientContent["turnComplete"] = true
        }
        sendJSON(["clientContent": clientContent])
    }

    func sendToolResponse(functionResponses: [[String: Any]]) {
        guard isSetupComplete else { return }
        sendJSON(["toolResponse": ["functionResponses": functionResponses]])
    }

    func sendInterrupt() {
        guard isSetupComplete else { return }
        sendJSON(["realtimeInput": ["audioStreamEnd": true]])
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.isConnecting = false
            self.isConnected = true
            if let setup = self.pendingSetup {
                self.sendJSON(setup)
                self.pendingSetup = nil
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.isConnected = false
            self.isConnecting = false
            self.isSetupComplete = false
        }
    }

    // MARK: - Private

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.connectionErrorPublisher.send(GeminiLiveError.websocketError(error.localizedDescription))
                }
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let serverMsg = decodeLiveJSONMessage(data) {
                        Task { @MainActor in
                            if case .setupComplete = serverMsg {
                                self.isSetupComplete = true
                            }
                            self.serverMessagePublisher.send(serverMsg)
                        }
                    }
                case .data(let data):
                    if let serverMsg = decodeLiveJSONMessage(data) {
                        Task { @MainActor in
                            if case .setupComplete = serverMsg {
                                self.isSetupComplete = true
                            }
                            self.serverMessagePublisher.send(serverMsg)
                        }
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()

            case .failure(let error):
                Task { @MainActor in
                    self.isConnected = false
                    self.isConnecting = false
                    self.isSetupComplete = false
                    self.connectionErrorPublisher.send(error)
                }
            }
        }
    }
}

// MARK: - JSON Live API decoding
private func decodeLiveJSONMessage(_ data: Data) -> GeminiLiveServerMessage? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    if json["setupComplete"] != nil {
        return .setupComplete
    }

    if let serverContent = json["serverContent"] as? [String: Any] {
        let turnComplete = serverContent["turnComplete"] as? Bool ?? false
        let interrupted = serverContent["interrupted"] as? Bool ?? false
        var modelTurn: [String: Any]?

        if let turn = serverContent["modelTurn"] as? [String: Any],
           let parts = turn["parts"] as? [[String: Any]] {
            var parsedParts: [[String: Any]] = []
            for part in parts {
                var parsed = part
                if let inlineData = part["inlineData"] as? [String: Any],
                   let mime = inlineData["mimeType"] as? String,
                   mime.contains("audio"),
                   let b64 = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: b64) {
                    parsed["audioData"] = audioData
                }
                parsedParts.append(parsed)
            }
            modelTurn = ["parts": parsedParts]
        }

        return .serverContent(modelTurn: modelTurn, turnComplete: turnComplete, interrupted: interrupted)
    }

    if let toolCall = json["toolCall"] as? [String: Any],
       let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
        return .toolCall(functionCalls: functionCalls)
    }

    if let cancellation = json["toolCallCancellation"] as? [String: Any],
       let ids = cancellation["ids"] as? [String] {
        return .toolCallCancellation(ids: ids)
    }

    return nil
}
