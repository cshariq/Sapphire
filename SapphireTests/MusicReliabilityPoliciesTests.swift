//
//  MusicReliabilityPoliciesTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import AppKit
import Foundation
import Testing
@testable import Sapphire

@Suite("Now-playing stream restarts")
struct StreamRestartPolicyTests {
    @Test func delaysDoubleThenGiveUp() {
        var policy = StreamRestartPolicy(baseDelay: 1, maxDelay: 32, maxAttempts: 4, stableLifetime: 60)
        #expect(policy.delayAfterExit(lifetime: 0.5) == 1)
        #expect(policy.delayAfterExit(lifetime: 0.5) == 2)
        #expect(policy.delayAfterExit(lifetime: 0.5) == 4)
        #expect(policy.delayAfterExit(lifetime: 0.5) == 8)
        #expect(policy.delayAfterExit(lifetime: 0.5) == nil)
        #expect(policy.isExhausted)
    }

    @Test func delayIsCapped() {
        var policy = StreamRestartPolicy(baseDelay: 1, maxDelay: 3, maxAttempts: 5, stableLifetime: 60)
        let delays = (0..<5).compactMap { _ in policy.delayAfterExit(lifetime: 0) }
        #expect(delays == [1, 2, 3, 3, 3])
    }

    @Test func aLongLivedStreamRefillsTheBudget() {
        var policy = StreamRestartPolicy(baseDelay: 1, maxDelay: 32, maxAttempts: 2, stableLifetime: 60)
        _ = policy.delayAfterExit(lifetime: 1)
        _ = policy.delayAfterExit(lifetime: 1)
        #expect(policy.isExhausted)
        #expect(policy.delayAfterExit(lifetime: 61) == 1)
    }

    @Test func resetRefillsTheBudget() {
        var policy = StreamRestartPolicy(baseDelay: 1, maxDelay: 32, maxAttempts: 1, stableLifetime: 60)
        _ = policy.delayAfterExit(lifetime: 0)
        #expect(policy.delayAfterExit(lifetime: 0) == nil)
        policy.reset()
        #expect(policy.delayAfterExit(lifetime: 0) == 1)
    }
}

@Suite("Newline framing")
struct NewlineFramerTests {
    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func splitsAcrossChunks() {
        var framer = NewlineFramer(limit: 100)
        #expect(strings(framer.append(Data("ab".utf8))).isEmpty)
        #expect(strings(framer.append(Data("c\nde\n\nf".utf8))) == ["abc", "de"])
        #expect(strings(framer.append(Data("\n".utf8))) == ["f"])
    }

    @Test func dropsAnOversizedLineAndResynchronises() {
        var framer = NewlineFramer(limit: 4)
        #expect(framer.append(Data("123456".utf8)).isEmpty)
        #expect(framer.append(Data("789".utf8)).isEmpty)
        #expect(strings(framer.append(Data("0\nok\n".utf8))) == ["ok"])
        #expect(framer.droppedLines == 1)
    }

    @Test func dropsAnOversizedLineEndingInTheSameChunk() {
        var framer = NewlineFramer(limit: 3)
        #expect(strings(framer.append(Data("toolong\nyes\n".utf8))) == ["yes"])
    }
}

@Suite("Artwork change detection")
struct ArtworkChangeTests {
    @Test func identicalPayloadsMatch() {
        let art = String(repeating: "QUJD", count: 200)
        #expect(ArtworkDigest.of(base64: art) == ArtworkDigest.of(base64: String(art)))
    }

    @Test func sameLengthAndEdgesStillDiffer() {
        var bytes = Array(repeating: UInt8(ascii: "A"), count: 400)
        let first = String(decoding: bytes, as: UTF8.self)
        bytes[200] = UInt8(ascii: "B")
        let second = String(decoding: bytes, as: UTF8.self)
        #expect(ArtworkDigest.of(base64: first) != ArtworkDigest.of(base64: second))
    }

    @Test func graceKeepsTheOldCoverBriefly() {
        let changed = Date(timeIntervalSince1970: 1_000)
        #expect(!ArtworkGracePolicy.isArtworkKnownAbsent(trackChangedAt: changed, now: changed.addingTimeInterval(0.5), hasArtwork: false))
        #expect(ArtworkGracePolicy.isArtworkKnownAbsent(trackChangedAt: changed, now: changed.addingTimeInterval(ArtworkGracePolicy.interval), hasArtwork: false))
        #expect(!ArtworkGracePolicy.isArtworkKnownAbsent(trackChangedAt: changed, now: changed.addingTimeInterval(10), hasArtwork: true))
        #expect(ArtworkGracePolicy.isArtworkKnownAbsent(trackChangedAt: nil, now: changed, hasArtwork: false))
    }

    @Test func thumbnailIsBoundedAndDecodable() throws {
        let size = 1_200
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let image = try #require(NowPlayingStreamParser.thumbnail(from: png))
        #expect(max(image.size.width, image.size.height) <= CGFloat(NowPlayingStreamParser.artworkMaxPixelSize))
        #expect(NowPlayingStreamParser.thumbnail(from: Data("not an image".utf8)) == nil)
    }

    @Test func parserDropsBase64AndReportsArtworkStates() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let base64 = try #require(rep.representation(using: .png, properties: [:])).base64EncodedString()
        let parser = NowPlayingStreamParser()

        let first = parser.consume(Data("{\"payload\":{\"title\":\"A\"}}\n".utf8))
        #expect(first.count == 1)
        if case .removed = first[0].artwork {} else { Issue.record("first snapshot without art should read as removed") }

        let withArt = parser.consume(Data("{\"payload\":{\"artworkData\":\"\(base64)\"}}\n".utf8))
        #expect(withArt[0].metadata["artworkData"] == nil)
        guard case .image(let digest, let image) = withArt[0].artwork else {
            Issue.record("expected an image")
            return
        }
        #expect(image != nil)

        let again = parser.consume(Data("{\"payload\":{\"artworkData\":\"\(base64)\"}}\n".utf8))
        if case .image(let sameDigest, let sameImage) = again[0].artwork {
            #expect(sameDigest == digest)
            #expect(sameImage === image)
        } else {
            Issue.record("expected the cached image")
        }

        let diff = parser.consume(Data("{\"payload\":{\"playing\":true}}\n".utf8))
        #expect(diff[0].artwork.isUnchanged)

        let removed = parser.consume(Data("{\"payload\":{\"artworkData\":null}}\n".utf8))
        if case .removed = removed[0].artwork {} else { Issue.record("null artwork should read as removed") }
    }
}

@Suite("Adapter command queue")
struct AdapterCommandQueueTests {
    @Test func seeksCoalesceToTheLatest() {
        var queue = AdapterCommandQueue()
        queue.enqueue(.seek(micros: 1))
        queue.enqueue(.send(2))
        queue.enqueue(.seek(micros: 2))
        queue.enqueue(.seek(micros: 3))
        #expect(queue.items == [.seek(micros: 1), .send(2), .seek(micros: 3)])
    }

    @Test func otherCommandsKeepTheirOrder() {
        var queue = AdapterCommandQueue()
        queue.enqueue(.send(4))
        queue.enqueue(.send(4))
        #expect(queue.dequeue() == .send(4))
        #expect(queue.dequeue() == .send(4))
        #expect(queue.dequeue() == nil)
    }

    @Test func burstsAreBounded() {
        var queue = AdapterCommandQueue(capacity: 2)
        queue.enqueue(.send(0))
        queue.enqueue(.send(1))
        queue.enqueue(.send(2))
        #expect(queue.items == [.send(1), .send(2)])
    }

    @Test func serveLinesMatchTheScript() {
        #expect(AdapterCommand.send(2).serveLine == "send 2")
        #expect(AdapterCommand.seek(micros: 1_500_000).serveLine == "seek 1500000")
        #expect(AdapterCommand.seek(micros: 7).oneShotArguments == ["seek", "7"])
    }

    @Test func repeatedCrashesPreferOneShot() {
        var health = CommandServerHealth(window: 60, maxCrashes: 3)
        let start = Date(timeIntervalSince1970: 0)
        health.recordCrash(at: start)
        health.recordCrash(at: start.addingTimeInterval(1))
        #expect(!health.prefersOneShot(at: start.addingTimeInterval(2)))
        health.recordCrash(at: start.addingTimeInterval(2))
        #expect(health.prefersOneShot(at: start.addingTimeInterval(3)))
        #expect(!health.prefersOneShot(at: start.addingTimeInterval(70)))
    }
}

@Suite("Player mode calibration")
struct PlayerModeCalibrationTests {
    @Test func trustsANumberingAfterTwoAgreements() {
        var calibration = PlayerModeCalibration()
        calibration.observe(shuffle: 3, repeat: 2, actualShuffle: true, actualRepeat: .track)
        #expect(calibration.trusted == nil)
        calibration.observe(shuffle: 1, repeat: 3, actualShuffle: false, actualRepeat: .context)
        #expect(calibration.trusted == .oneBased)
        let modes = calibration.modes(shuffle: 1, repeat: 1)
        #expect(modes?.shuffle == false)
        #expect(modes?.repeat == .off)
    }

    @Test func zeroBasedIsRecognisedToo() {
        var calibration = PlayerModeCalibration()
        calibration.observe(shuffle: 1, repeat: 1, actualShuffle: true, actualRepeat: .track)
        calibration.observe(shuffle: 0, repeat: 2, actualShuffle: false, actualRepeat: .context)
        #expect(calibration.trusted == .zeroBased)
    }

    @Test func disagreementFallsBackForGood() {
        var calibration = PlayerModeCalibration()
        calibration.observe(shuffle: 1, repeat: 1, actualShuffle: false, actualRepeat: .context)
        #expect(calibration.isRejected)
        #expect(calibration.modes(shuffle: 1, repeat: 1) == nil)
    }

    @Test func missingPayloadValuesNeverAnswer() {
        var calibration = PlayerModeCalibration()
        calibration.observe(shuffle: 3, repeat: 2, actualShuffle: true, actualRepeat: .track)
        calibration.observe(shuffle: 3, repeat: 3, actualShuffle: true, actualRepeat: .context)
        #expect(calibration.modes(shuffle: nil, repeat: 2) == nil)
    }
}

@Suite("Lyrics duration matching")
struct LyricsDurationMatchTests {
    @Test func requestDurationIsRoundedAndSane() {
        #expect(LyricsDurationMatch.requestDuration(213.6) == 214)
        #expect(LyricsDurationMatch.requestDuration(0) == nil)
        #expect(LyricsDurationMatch.requestDuration(nil) == nil)
        #expect(LyricsDurationMatch.requestDuration(.infinity) == nil)
        #expect(LyricsDurationMatch.requestDuration(10_000) == nil)
    }

    @Test func acceptsWithinTwoSeconds() {
        #expect(LyricsDurationMatch.accepts(expected: 200, actual: 201.9))
        #expect(LyricsDurationMatch.accepts(expected: 200, actual: 198))
        #expect(!LyricsDurationMatch.accepts(expected: 200, actual: 202.5))
        #expect(!LyricsDurationMatch.accepts(expected: 200, actual: 260))
    }

    @Test func unknownDurationsPass() {
        #expect(LyricsDurationMatch.accepts(expected: nil, actual: 100))
        #expect(LyricsDurationMatch.accepts(expected: 100, actual: nil))
        #expect(LyricsDurationMatch.accepts(expected: 0, actual: 100))
    }
}

@Suite("Lyrics retry policy")
struct LyricsRetryPolicyTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test func failuresBackOffExponentially() {
        var policy = LyricsRetryPolicy(baseDelay: 10, maxDelay: 35, capacity: 8)
        #expect(policy.isDue("a", now: start))
        #expect(policy.recordFailure("a", now: start) == start.addingTimeInterval(10))
        #expect(!policy.isDue("a", now: start.addingTimeInterval(9)))
        #expect(policy.isDue("a", now: start.addingTimeInterval(10)))
        #expect(policy.recordFailure("a", now: start) == start.addingTimeInterval(20))
        #expect(policy.recordFailure("a", now: start) == start.addingTimeInterval(35))
        #expect(policy.isDue("b", now: start))
    }

    @Test func successClearsAndWakeMakesDue() {
        var policy = LyricsRetryPolicy(baseDelay: 10, maxDelay: 100, capacity: 8)
        policy.recordFailure("a", now: start)
        policy.recordFailure("b", now: start)
        policy.recordSuccess("a")
        #expect(policy.isDue("a", now: start))
        #expect(!policy.isDue("b", now: start))
        policy.makeAllDue(now: start)
        #expect(policy.isDue("b", now: start))
    }

    @Test func isBounded() {
        var policy = LyricsRetryPolicy(baseDelay: 10, maxDelay: 100, capacity: 2)
        policy.recordFailure("a", now: start)
        policy.recordFailure("b", now: start)
        policy.recordFailure("c", now: start)
        #expect(policy.retryDate(for: "a") == nil)
        #expect(policy.retryDate(for: "c") != nil)
    }
}

@Suite("Lyrics caches")
struct LyricsCacheTests {
    @Test func evictsLeastRecentlyUsed() {
        var cache = BoundedLRUCache<String, Int>(capacity: 2)
        cache.set(1, for: "a")
        cache.set(2, for: "b")
        _ = cache.value(for: "a")
        cache.set(3, for: "c")
        #expect(cache.peek("a") == 1)
        #expect(cache.peek("b") == nil)
        #expect(cache.peek("c") == 3)
    }

    @Test func trimKeepsTheCurrentEntry() {
        var cache = BoundedLRUCache<String, Int>(capacity: 10)
        for (index, key) in ["current", "b", "c", "d"].enumerated() { cache.set(index, for: key) }
        cache.trim(to: 2, keeping: "current")
        #expect(cache.count == 2)
        #expect(cache.peek("current") == 0)
        #expect(cache.peek("d") == 3)
        cache.trim(to: 0, keeping: "current")
        #expect(cache.keys == ["current"])
    }

    @Test func emptyArrayIsACachedMiss() {
        var cache = BoundedLRUCache<String, [LyricLine]>(capacity: 4)
        cache.set([], for: "song")
        #expect(cache.value(for: "song") == [])
        #expect(cache.value(for: "other") == nil)
    }

    @Test func translationsApplyByOriginalText() {
        let lines = [
            LyricLine(text: "Hola", timestamp: 1),
            LyricLine(text: "  ", timestamp: 2),
            LyricLine(text: "Adiós", timestamp: 3),
        ]
        var translated = lines
        translated[0].translatedText = "Hello"
        translated[2].translatedText = "Goodbye"
        let entry = LyricsTranslation(sourceLanguage: "es", translatedLines: translated)

        let rebuilt = lines.map { LyricLine(text: $0.text, timestamp: $0.timestamp) }
        let applied = entry.applied(to: rebuilt)
        #expect(applied?.map(\.translatedText) == ["Hello", "", "Goodbye"])

        let extra = rebuilt + [LyricLine(text: "Nuevo", timestamp: 4)]
        #expect(entry.applied(to: extra) == nil)
        #expect(LyricsTranslation.cacheKey(trackKey: "t|a|b", targetLanguage: "en") == "t|a|b|en")
    }
}