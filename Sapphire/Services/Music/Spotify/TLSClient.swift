//
//  CustomTLSClient.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-18.
//

import Foundation
import Network
import Security

struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let cookies: [HTTPCookie]
}

actor CookieManager {
    private var cookies: [String: HTTPCookie] = [:]
    func setCookie(_ cookie: HTTPCookie) { cookies[cookie.name] = cookie }
    func setCookies(_ newCookies: [HTTPCookie]) { for cookie in newCookies { cookies[cookie.name] = cookie } }
    func allCookies() -> [String: HTTPCookie] { return cookies }
    func clear() { cookies.removeAll() }
}

class CustomTLSClient {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    internal let userAgent: String
    private let cookieManager: CookieManager
    internal var accessToken: String?
    internal var clientToken: String?
    internal var clientVersion: String?
    private let queue: DispatchQueue

    init(host: String, port: UInt16 = 443, userAgent: String, cookieManager: CookieManager) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        self.userAgent = userAgent
        self.cookieManager = cookieManager
        self.queue = DispatchQueue(label: "com.shariq.sapphire.customtlsclient.\(host).\(UUID().uuidString)")
    }

    private func send(data: Data, on connection: NWConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func receive(on connection: NWConnection, min: Int, max: Int) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: min, maximumLength: max) { content, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (content, isComplete))
                }
            }
        }
    }

    private func readData(on connection: NWConnection) async throws -> HTTPResponse {
        var buffer = Data()
        let headerSeparator = "\r\n\r\n".data(using: .utf8)!

        while buffer.range(of: headerSeparator) == nil {
            let (content, isComplete) = try await receive(on: connection, min: 1, max: 8192)
            if let data = content { buffer.append(data) }
            if isComplete { throw SpotAPIError.connectionClosedUnexpectedly }
        }

        guard let headerEndRange = buffer.range(of: headerSeparator) else {
            throw SpotAPIError.invalidResponse
        }
        
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEndRange.lowerBound)
        var bodyBuffer = buffer.subdata(in: headerEndRange.upperBound..<buffer.endIndex)

        let (statusCode, headers, cookies) = try await parseHeaders(headerData: headerData)
        
        if let contentLengthStr = headers["content-length"], let contentLength = Int(contentLengthStr) {
            while bodyBuffer.count < contentLength {
                let bytesNeeded = contentLength - bodyBuffer.count
                let (content, isComplete) = try await receive(on: connection, min: 1, max: bytesNeeded)
                if let data = content { bodyBuffer.append(data) }
                if isComplete && bodyBuffer.count < contentLength { throw SpotAPIError.connectionClosedUnexpectedly }
            }
        } else if headers["transfer-encoding"]?.lowercased() == "chunked" {
            bodyBuffer = try await readChunkedBody(on: connection, initialData: bodyBuffer)
        } else if statusCode != 204 {
             while true {
                 let (content, isComplete) = try await receive(on: connection, min: 0, max: 8192)
                 if let data = content { bodyBuffer.append(data) }
                 if isComplete { break }
             }
        }
        
        return HTTPResponse(statusCode: statusCode, headers: headers, body: bodyBuffer, cookies: cookies)
    }

    private func readChunkedBody(on connection: NWConnection, initialData: Data) async throws -> Data {
        var body = Data()
        var buffer = initialData
        let crlf = "\r\n".data(using: .utf8)!

        while true {
            var sizeLineRange: Range<Data.Index>?
            while true {
                sizeLineRange = buffer.range(of: crlf)
                if sizeLineRange != nil { break }
                let (content, isComplete) = try await receive(on: connection, min: 1, max: 1024)
                guard let data = content, !isComplete else { throw SpotAPIError.invalidResponse }
                buffer.append(data)
            }
            
            let sizeLineData = buffer.subdata(in: 0..<sizeLineRange!.lowerBound)
            guard let sizeHex = String(data: sizeLineData, encoding: .ascii),
                  let chunkSize = Int(sizeHex, radix: 16) else {
                throw SpotAPIError.apiError("Invalid chunk size format")
            }
            
            buffer.removeSubrange(0..<sizeLineRange!.upperBound)

            if chunkSize == 0 { break }

            let requiredBytesForChunk = chunkSize + crlf.count
            while buffer.count < requiredBytesForChunk {
                let (content, isComplete) = try await receive(on: connection, min: 1, max: requiredBytesForChunk - buffer.count)
                guard let data = content, !isComplete else { throw SpotAPIError.invalidResponse }
                buffer.append(data)
            }

            let chunkData = buffer.subdata(in: 0..<chunkSize)
            body.append(chunkData)
            buffer.removeSubrange(0..<requiredBytesForChunk)
        }
        return body
    }
    
    private func parseHeaders(headerData: Data) async throws -> (Int, [String: String], [HTTPCookie]) {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw SpotAPIError.invalidResponse
        }
        
        let lines = headerString.components(separatedBy: "\r\n")
        var statusCode = 0
        var headers: [String: String] = [:]
        var cookies: [HTTPCookie] = []
        
        if let statusLine = lines.first {
            let parts = statusLine.split(separator: " ", maxSplits: 2)
            if parts.count >= 2, let code = Int(parts[1]) { statusCode = code }
        }
        
        for line in lines.dropFirst() {
            if let separatorIndex = line.firstIndex(of: ":") {
                let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
                
                if key == "set-cookie", let cookie = HTTPCookie(string: value) {
                    cookies.append(cookie)
                    await cookieManager.setCookie(cookie)
                }
            }
        }
        
        return (statusCode, headers, cookies)
    }

    private func performRequest(method: String, path: String, queryItems: [URLQueryItem]? = nil, body: Data? = nil, contentType: String? = nil, acceptType: String = "*/*", additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.noDelay = true
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let connection = NWConnection(to: .hostPort(host: host, port: port), using: parameters)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var hasResumed = false
                
                connection.stateUpdateHandler = { newState in
                    if hasResumed { return }

                    switch newState {
                    case .ready:
                        hasResumed = true
                        continuation.resume()
                    case .failed(let error):
                        hasResumed = true
                        continuation.resume(throwing: error)
                    case .cancelled:
                        hasResumed = true
                        continuation.resume(throwing: URLError(.cancelled))
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
            }
            
            var fullPath = path
            if let queryItems = queryItems, !queryItems.isEmpty {
                var components = URLComponents()
                components.queryItems = queryItems
                if let queryString = components.query { fullPath += "?\(queryString)" }
            }

            var httpHeaders: [String: String] = [
                "Host": self.host.debugDescription, "User-Agent": self.userAgent,
                "Accept": acceptType, "Accept-Language": "en-US,en;q=0.9", "app-platform": "WebPlayer",
                "Connection": "keep-alive", "sec-ch-ua": "\"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"",
                "sec-ch-ua-mobile": "?0", "sec-ch-ua-platform": "\"macOS\"", "Referer": "https://\(self.host.debugDescription)/"
            ]
            
            if let type = contentType { httpHeaders["Content-Type"] = type }
            if let b = body { httpHeaders["Content-Length"] = "\(b.count)" }
            
            if authenticate {
                if let token = accessToken { httpHeaders["Authorization"] = "Bearer \(token)" }
                if let cToken = clientToken { httpHeaders["Client-Token"] = cToken }
                if let cVersion = clientVersion { httpHeaders["Spotify-App-Version"] = cVersion }
            }
            
            let currentCookies = await cookieManager.allCookies()
            if !currentCookies.isEmpty {
                httpHeaders["Cookie"] = currentCookies.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
            
            additionalHeaders?.forEach { key, value in httpHeaders[key] = value }

            let headerLines = httpHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            let requestLine = "\(method.uppercased()) \(fullPath) HTTP/1.1"
            let requestString = "\(requestLine)\r\n\(headerLines)\r\n\r\n"
            var requestData = requestString.data(using: .utf8)!

            if let b = body { requestData.append(b) }

            try await send(data: requestData, on: connection)
            
            let response = try await readData(on: connection)
            connection.cancel()
            return response
            
        } catch {
            connection.cancel()
            throw error
        }
    }
    
    internal func get(path: String, queryItems: [URLQueryItem]? = nil, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        return try await performRequest(method: "GET", path: path, queryItems: queryItems, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }
    
    internal func post(path: String, bodyData: Data, additionalHeaders: [String: String]? = nil) async throws -> HTTPResponse {
        let contentType = additionalHeaders?["Content-Type"] ?? "application/octet-stream"
        return try await performRequest(method: "POST", path: path, body: bodyData, contentType: contentType, additionalHeaders: additionalHeaders)
    }

    internal func post(path: String, queryItems: [URLQueryItem]? = nil, jsonBody: [String: Any]? = nil, urlEncodedBody: [String: String]? = nil, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        var bodyData: Data?
        var contentType: String?
        var acceptType = "*/*"

        if let json = jsonBody {
            bodyData = try? JSONSerialization.data(withJSONObject: json)
            contentType = "application/json"
            acceptType = "application/json"
        } else if let urlEncoded = urlEncodedBody {
            let queryString = urlEncoded.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
            bodyData = queryString.data(using: .utf8)
            contentType = "application/x-form-urlencoded"
        }
        return try await performRequest(method: "POST", path: path, queryItems: queryItems, body: bodyData, contentType: contentType, acceptType: acceptType, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }

    internal func put(path: String, queryItems: [URLQueryItem]? = nil, jsonBody: [String: Any]? = nil, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        var bodyData: Data?
        var contentType: String?
        var acceptType = "*/*"

        if let json = jsonBody {
            bodyData = try? JSONSerialization.data(withJSONObject: json)
            contentType = "application/json"
            acceptType = "application/json"
        }
        return try await performRequest(method: "PUT", path: path, queryItems: queryItems, body: bodyData, contentType: contentType, acceptType: acceptType, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }
    
    internal func delete(path: String, additionalHeaders: [String: String]? = nil, authenticate: Bool = true) async throws -> HTTPResponse {
        return try await performRequest(method: "DELETE", path: path, additionalHeaders: additionalHeaders, authenticate: authenticate)
    }
}

// MARK: - HTTPCookie Extension
extension HTTPCookie {
    convenience init?(string: String) {
        let components = string.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let nameValue = components.first, nameValue.contains("=") else { return nil }
        
        let nameValueParts = nameValue.split(separator: "=", maxSplits: 1)
        let name = String(nameValueParts[0])
        let value = String(nameValueParts.count > 1 ? nameValueParts[1] : "")
        
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .path: "/"
        ]
        
        for component in components.dropFirst() {
            let parts = component.split(separator: "=", maxSplits: 1)
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespaces)
            
            switch key {
            case "domain":
                properties[.domain] = val
            case "path":
                properties[.path] = val
            case "expires":
                let formatter = DateFormatter()
                let formats = ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz"]
                for format in formats {
                    formatter.dateFormat = format
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    if let date = formatter.date(from: val) {
                        properties[.expires] = date
                        break
                    }
                }
            case "max-age":
                if let maxAge = Int(val) { properties[.maximumAge] = maxAge }
            case "secure":
                properties[.secure] = "true"
            case "httponly":
                break
            default:
                break
            }
        }
        
        self.init(properties: properties)
    }
}
