import Foundation

class LyricsFetcher {

    func fetchSyncedLyrics(for title: String, artist: String, album: String) async -> [LyricLine]? {

        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album)
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            struct LrcLibResponse: Decodable {
                let syncedLyrics: String?
            }

            let response = try Self.decoder.decode(LrcLibResponse.self, from: data)

            if let lrcString = response.syncedLyrics, !lrcString.isEmpty {
                return parseLRC(lrcString)
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    private func parseLRC(_ lrcString: String) -> [LyricLine] {
        var lyrics: [LyricLine] = []
        let lines = lrcString.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("[") && line.contains("]") {
                let components = line.components(separatedBy: "]")
                if components.count > 1 {
                    let timestampString = String(components[0].dropFirst())
                    let text = components[1].trimmingCharacters(in: .whitespaces)

                    let timeComponents = timestampString.components(separatedBy: ":")
                    if timeComponents.count == 2,
                       let minutes = Double(timeComponents[0]),
                       let seconds = Double(timeComponents[1]) {

                        let timestamp = (minutes * 60) + seconds
                        lyrics.append(LyricLine(text: text, timestamp: timestamp))
                    }
                }
            }
        }
        return lyrics.sorted { $0.timestamp < $1.timestamp }
    }

    func detectLanguage(for text: String) async -> String? {

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: trimmedText.prefix(500).description)
        ]

        guard let url = components.url else { return nil }

        struct UnofficialGoogleDetectionResponse: Decodable {
            let detectedLanguage: String?
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                _ = try? container.nestedUnkeyedContainer()
                _ = try? container.decode(String?.self)
                self.detectedLanguage = try? container.decode(String.self)
            }
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let unofficialResponse = try Self.decoder.decode(UnofficialGoogleDetectionResponse.self, from: data)
            if let lang = unofficialResponse.detectedLanguage {
                return lang
            }
        } catch {
        }
        return nil
    }

    // High performance batch translation of lyric strings
    func translate(lyrics: inout [LyricLine], from sourceLanguage: String, to targetLanguage: String) async {
        guard !lyrics.isEmpty else { return }

        // We group lyric lines to fit safely under standard API character limitations
        var chunks: [[(index: Int, text: String)]] = []
        var currentChunk: [(index: Int, text: String)] = []
        var currentLength = 0

        for i in 0..<lyrics.count {
            let originalText = lyrics[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if originalText.isEmpty {
                lyrics[i].translatedText = ""
                continue
            }
            
            if currentLength + originalText.count + 1 > 1800 && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                currentLength = 0
            }
            
            currentChunk.append((index: i, text: originalText))
            currentLength += originalText.count + 1
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        struct UnofficialGoogleTranslateResponse: Decodable {
            let translatedText: String?
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                if var outerArray = try? container.nestedUnkeyedContainer() {
                    var combinedTranslation = ""
                    while !outerArray.isAtEnd {
                        if var firstInnerArray = try? outerArray.nestedUnkeyedContainer(),
                           let translatedSegment = try? firstInnerArray.decode(String.self) {
                            combinedTranslation += translatedSegment
                        } else {
                            _ = try? outerArray.decode(AnyCodable.self)
                        }
                    }
                    self.translatedText = combinedTranslation.isEmpty ? nil : combinedTranslation
                } else {
                    self.translatedText = nil
                }
            }
        }

        struct AnyCodable: Decodable {}

        await withTaskGroup(of: [(Int, String)].self) { group in
            for chunk in chunks {
                group.addTask {
                    let combinedText = chunk.map { $0.text }.joined(separator: "\n")
                    
                    var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
                    components.queryItems = [
                        URLQueryItem(name: "client", value: "gtx"),
                        URLQueryItem(name: "sl", value: sourceLanguage),
                        URLQueryItem(name: "tl", value: targetLanguage),
                        URLQueryItem(name: "dt", value: "t"),
                        URLQueryItem(name: "q", value: combinedText)
                    ]

                    guard let url = components.url else { return [] }

                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let unofficialResponse = try Self.decoder.decode(UnofficialGoogleTranslateResponse.self, from: data)
                        
                        if let translatedResult = unofficialResponse.translatedText {
                            let translatedLines = translatedResult.components(separatedBy: "\n")
                            var results: [(Int, String)] = []
                            for (offset, item) in chunk.enumerated() {
                                if offset < translatedLines.count {
                                    let cleanText = translatedLines[offset].trimmingCharacters(in: .whitespacesAndNewlines)
                                    results.append((item.index, cleanText.isEmpty ? item.text : cleanText))
                                } else {
                                    results.append((item.index, item.text))
                                }
                            }
                            return results
                        }
                    } catch {
                    }
                    return chunk.map { ($0.index, $0.text) }
                }
            }

            for await chunkResult in group {
                for (index, translatedText) in chunkResult {
                    lyrics[index].translatedText = translatedText
                }
            }
        }

        for i in 0..<lyrics.count {
            if lyrics[i].translatedText == nil {
                lyrics[i].translatedText = lyrics[i].text
            }
        }
    }

    private static let decoder: JSONDecoder = {
        return JSONDecoder()
    }()
}
