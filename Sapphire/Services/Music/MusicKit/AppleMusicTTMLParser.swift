//
//  AppleMusicTTMLParser.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-13

import Foundation

final class AppleMusicTTMLParser: NSObject, XMLParserDelegate {
    static func lines(from ttml: String) -> [LyricLine]? {
        guard let data = ttml.data(using: .utf8) else { return nil }
        let delegate = AppleMusicTTMLParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        let lines = delegate.finishedLines.map { line in
            let romanization = line.key.flatMap { delegate.transliterations[$0] }?.trimmingCharacters(in: .whitespaces)
            return LyricLine(
                text: line.words.isEmpty ? line.plainText.trimmingCharacters(in: .whitespacesAndNewlines) : line.words.map(\.text).joined(),
                timestamp: line.begin,
                endTimestamp: line.end,
                words: line.words.map { LyricWord(text: $0.text, timestamp: $0.begin, endTimestamp: $0.end) },
                background: line.background.map { LyricWord(text: $0.text, timestamp: $0.begin, endTimestamp: $0.end) },
                agent: line.agent,
                songPart: line.songPart,
                romanization: romanization?.isEmpty == false ? romanization : nil
            )
        }
        return lines.isEmpty ? nil : lines
    }

    static func seconds(_ value: String?) -> TimeInterval? {
        guard var text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasSuffix("s") { text.removeLast() }
        var total: Double = 0
        for part in text.split(separator: ":") {
            guard let number = Double(part) else { return nil }
            total = total * 60 + number
        }
        return total
    }

    // MARK: - Parsing state

    private struct Piece {
        var text: String
        let begin: TimeInterval
        let end: TimeInterval?
    }

    private struct Line {
        let begin: TimeInterval
        let end: TimeInterval?
        let agent: String?
        let songPart: String?
        let key: String?
        var words: [Piece] = []
        var background: [Piece] = []
        var plainText = ""
    }

    private enum Span {
        case word
        case background
        case other
    }

    private var finishedLines: [Line] = []
    private var line: Line?
    private var spans: [Span] = []
    private var songPart: String?
    private var inTransliterations = false
    private var transliterationKey: String?
    private var transliterations: [String: String] = [:]

    private var inBackground: Bool { spans.contains(.background) }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "div":
            songPart = attributes["itunes:songPart"] ?? attributes["songPart"]
        case "p":
            guard let begin = Self.seconds(attributes["begin"]) else { return }
            line = Line(
                begin: begin,
                end: Self.seconds(attributes["end"]),
                agent: attributes["ttm:agent"],
                songPart: songPart,
                key: attributes["itunes:key"]
            )
        case "span":
            let role = attributes["ttm:role"]
            if role == "x-bg" {
                spans.append(.background)
            } else if let begin = Self.seconds(attributes["begin"]), role == nil {
                spans.append(.word)
                let piece = Piece(text: "", begin: begin, end: Self.seconds(attributes["end"]))
                if inBackground { line?.background.append(piece) } else { line?.words.append(piece) }
            } else {
                spans.append(.other)
            }
        case "transliterations":
            inTransliterations = true
        case "text" where inTransliterations:
            transliterationKey = attributes["for"]
            if let key = transliterationKey { transliterations[key] = "" }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTransliterations, let key = transliterationKey {
            transliterations[key, default: ""] += string
            return
        }
        guard line != nil else { return }
        if spans.last == .word {
            if inBackground {
                line!.background[line!.background.count - 1].text += string
            } else {
                line!.words[line!.words.count - 1].text += string
            }
        } else if spans.contains(.other) {
            return
        } else {
            if inBackground, !line!.background.isEmpty {
                if string.contains(where: \.isWhitespace) { line!.background[line!.background.count - 1].text += " " }
            } else if !line!.words.isEmpty {
                if string.contains(where: \.isWhitespace) { line!.words[line!.words.count - 1].text += " " }
                else { line!.words[line!.words.count - 1].text += string }
            } else {
                line!.plainText += string
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "span":
            if !spans.isEmpty { spans.removeLast() }
        case "p":
            if var finished = line {
                finished.words = Self.tidy(finished.words)
                finished.background = Self.tidy(finished.background)
                finishedLines.append(finished)
            }
            line = nil
            spans.removeAll()
        case "div":
            songPart = nil
        case "transliterations":
            inTransliterations = false
        case "text":
            transliterationKey = nil
        default:
            break
        }
    }

    private static func tidy(_ pieces: [Piece]) -> [Piece] {
        var result = pieces.filter { !$0.text.isEmpty }
        for index in result.indices {
            result[index].text = result[index].text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        if let last = result.indices.last {
            result[last].text = result[last].text.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}