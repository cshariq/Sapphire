//
//  LyricsViews.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import SwiftUI
import AppKit
import Combine

// MARK: - Consolidated from LyricsView.swift

struct WordSyncedLyricText: View {
    let lyric: LyricLine
    let elapsedTime: TimeInterval
    let isActive: Bool
    let highlightColor: Color
    let inactiveColor: Color

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *), isActive, let timing = MomentumLineTiming(line: lyric) {
            MomentumLyricText(
                lyric: lyric,
                timing: timing,
                highlightColor: highlightColor,
                inactiveColor: inactiveColor
            )
            .accessibilityLabel(lyric.text)
        } else {
            renderedText
                .animation(.linear(duration: 0.12), value: highlightedWordCount)
                .accessibilityLabel(lyric.text)
        }
    }

    private var renderedText: Text {
        guard isActive, lyric.hasReconstructibleWordTiming else {
            return Text(lyric.text)
                .foregroundColor(isActive ? highlightColor : inactiveColor)
        }

        return lyric.words.reduce(Text("")) { text, word in
            let color = word.timestamp <= elapsedTime
                ? highlightColor
                : inactiveColor.opacity(0.38)
            return text + Text(word.text).foregroundColor(color)
        }
    }

    private var highlightedWordCount: Int {
        guard isActive, lyric.hasReconstructibleWordTiming else { return 0 }
        return lyric.words.reduce(into: 0) { count, word in
            if word.timestamp <= elapsedTime {
                count += 1
            }
        }
    }
}

// MARK: - Compact Karaoke Ticker (Live Activity bottom bar)

struct KaraokeLyricTicker: View {
    let lyric: LyricLine
    let containerWidth: CGFloat
    let fontSize: CGFloat
    let highlightColor: Color
    let inactiveColor: Color

    private var musicWidget: MusicManager { .shared }

    private var font: Font {
        .system(size: fontSize, weight: .semibold, design: .rounded)
    }

    private var tracksWords: Bool {
        lyric.translatedText == nil && lyric.hasReconstructibleWordTiming
    }

    var body: some View {
        Group {
            if tracksWords {
                Text(lyric.text)
                    .font(font)
                    .lineLimit(1)
                    .hidden()
                    .frame(width: containerWidth)
                    .overlay {
                        KaraokeWordStrip(
                            lyric: lyric,
                            fontSize: fontSize,
                            highlightColor: highlightColor,
                            inactiveColor: inactiveColor,
                            isPlaying: musicWidget.isPlaying
                        )
                        .allowsHitTesting(false)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lyric.text)
            } else {
                Text(lyric.translatedText ?? lyric.text)
                    .font(font)
                    .foregroundColor(highlightColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: containerWidth)
        .onChange(of: lyric.id, initial: true) {
            LyricsLog.info(
                "Live activity ticker shown: \(lyric.words.count) words, tracksWords=\(tracksWords), translated=\(lyric.translatedText != nil), playing=\(musicWidget.isPlaying)"
            )
        }
    }
}

struct KaraokeTickerTimeline: Equatable {
    struct Fill: Equatable {
        let start: TimeInterval
        let end: TimeInterval
    }

    struct Step: Equatable {
        let time: TimeInterval
        let word: Int
    }

    let fills: [Fill]
    let steps: [Step]

    init(line: LyricLine) {
        fills = line.words.indices.map { index in
            let start = line.words[index].timestamp
            return Fill(start: start, end: max(start, line.wordFillEndTimestamp(at: index) ?? start))
        }

        var steps: [Step] = []
        var reached = -TimeInterval.infinity
        for (index, word) in line.words.enumerated() {
            reached = max(reached, word.timestamp)
            guard index > 0 else { continue }
            if steps.last?.time == reached { steps.removeLast() }
            steps.append(Step(time: reached, word: index))
        }
        self.steps = steps
    }
}

private struct KaraokeWordStrip: NSViewRepresentable {
    let lyric: LyricLine
    let fontSize: CGFloat
    let highlightColor: Color
    let inactiveColor: Color
    let isPlaying: Bool

    func makeNSView(context: Context) -> KaraokeWordStripView {
        KaraokeWordStripView()
    }

    func updateNSView(_ view: KaraokeWordStripView, context: Context) {
        view.show(
            KaraokeWordStripView.Line(
                words: lyric.words.map(\.text),
                timeline: KaraokeTickerTimeline(line: lyric),
                fontSize: fontSize,
                highlightColor: NSColor(highlightColor).cgColor,
                inactiveColor: NSColor(inactiveColor.opacity(0.35)).cgColor
            ),
            isPlaying: isPlaying
        )
    }

    static func dismantleNSView(_ view: KaraokeWordStripView, coordinator: ()) {
        view.stopDriftTimer()
    }
}

final class KaraokeWordStripView: NSView {
    struct Line: Equatable {
        let words: [String]
        let timeline: KaraokeTickerTimeline
        let fontSize: CGFloat
        let highlightColor: CGColor
        let inactiveColor: CGColor
    }

    private static let clockOrigin: CFTimeInterval = 10_000
    private static let slideDuration: CFTimeInterval = 0.2
    private static let driftTolerance: TimeInterval = 0.05

    private let strip = CALayer()
    private var line: Line?
    private var isPlaying = false
    private var builtSize: CGSize = .zero
    private var builtScale: CGFloat = 0
    private var builtColorSpace: CGColorSpace?
    private var driftTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        strip.anchorPoint = .zero
        layer?.addSublayer(strip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ line: Line, isPlaying: Bool) {
        let lineChanged = line != self.line
        let playbackChanged = isPlaying != self.isPlaying
        self.line = line
        self.isPlaying = isPlaying
        if lineChanged {
            builtSize = .zero
            build()
        }
        if lineChanged || playbackChanged { syncClock() }
        updateDriftTimer()
    }

    func stopDriftTimer() {
        driftTimer?.invalidate()
        driftTimer = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        build()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        build()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        build()
        updateDriftTimer()
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopDriftTimer()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        syncClock()
        updateDriftTimer()
    }

    private func build() {
        guard let line, !line.words.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let space = window?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)
        guard bounds.size != builtSize || scale != builtScale || space != builtColorSpace else { return }
        builtSize = bounds.size
        builtScale = scale
        builtColorSpace = space

        let row = KaraokeWordRow(words: line.words, fontSize: line.fontSize, height: bounds.height, scale: scale)
        let litImage = row.image(color: line.highlightColor, in: space)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        strip.removeAllAnimations()
        strip.sublayers = nil
        strip.bounds = CGRect(x: 0, y: 0, width: row.width, height: bounds.height)

        let dim = CALayer()
        dim.contents = row.image(color: line.inactiveColor, in: space)
        dim.contentsScale = scale
        dim.frame = row.imageFrame
        strip.addSublayer(dim)

        for (index, fill) in line.timeline.fills.enumerated() where row.widths.indices.contains(index) {
            let clip = CALayer()
            clip.anchorPoint = .zero
            clip.bounds = CGRect(x: 0, y: 0, width: row.widths[index], height: bounds.height)
            clip.position = CGPoint(x: row.lefts[index], y: 0)
            clip.masksToBounds = true

            let word = CALayer()
            word.contents = litImage
            word.contentsScale = scale
            word.frame = row.imageFrame.offsetBy(dx: -row.lefts[index], dy: 0)
            clip.addSublayer(word)

            let sweep = CABasicAnimation(keyPath: "bounds.size.width")
            sweep.fromValue = 0
            sweep.toValue = row.widths[index]
            sweep.beginTime = Self.clockOrigin + fill.start
            sweep.duration = max(fill.end - fill.start, 0.001)
            sweep.fillMode = .both
            sweep.isRemovedOnCompletion = false
            clip.add(sweep, forKey: "fill")
            strip.addSublayer(clip)
        }

        let offsets = row.lefts.indices.map { index in
            ((bounds.width / 2 - row.lefts[index] - row.widths[index] / 2) * scale).rounded() / scale
        }
        strip.position = CGPoint(x: offsets[line.timeline.steps.last?.word ?? 0], y: 0)
        var centred = 0
        for (index, step) in line.timeline.steps.enumerated() where offsets.indices.contains(step.word) {
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.isAdditive = true
            slide.fromValue = offsets[centred] - offsets[step.word]
            slide.toValue = 0
            slide.beginTime = Self.clockOrigin + step.time
            slide.duration = Self.slideDuration
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            slide.fillMode = .both
            slide.isRemovedOnCompletion = false
            strip.add(slide, forKey: "slide\(index)")
            centred = step.word
        }
    }

    private func syncClock() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        strip.timeOffset = Self.clockOrigin + MusicManager.shared.lyricsElapsedTime()
        strip.speed = isPlaying ? 1 : 0
        CATransaction.commit()
    }

    private func updateDriftTimer() {
        guard isPlaying, line != nil, window != nil, !isHiddenOrHasHiddenAncestor else {
            stopDriftTimer()
            return
        }
        guard driftTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDrift() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        driftTimer = timer
    }

    private func checkDrift() {
        let clock = strip.convertTime(CACurrentMediaTime(), from: nil) - Self.clockOrigin
        if abs(clock - MusicManager.shared.lyricsElapsedTime()) > Self.driftTolerance {
            syncClock()
        }
    }
}

private struct KaraokeWordRow {
    private static let inkPadding: CGFloat = 2

    private let lines: [CTLine]
    let lefts: [CGFloat]
    let widths: [CGFloat]
    let width: CGFloat
    private let height: CGFloat
    private let baseline: CGFloat
    private let scale: CGFloat

    init(words: [String], fontSize: CGFloat, height: CGFloat, scale: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font(size: fontSize),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        var lines: [CTLine] = []
        var edges: [CGFloat] = [0]
        var ascent: CGFloat = 0
        for word in words {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: word, attributes: attributes))
            var wordAscent: CGFloat = 0
            let advance = CGFloat(CTLineGetTypographicBounds(line, &wordAscent, nil, nil))
            ascent = max(ascent, wordAscent)
            lines.append(line)
            edges.append((edges.last ?? 0) + (advance * scale).rounded(.up) / scale)
        }

        self.lines = lines
        lefts = Array(edges.dropLast())
        widths = zip(edges.dropFirst(), edges).map { $0 - $1 }
        width = edges.last ?? 0
        self.height = height
        baseline = height - ascent.rounded(.up)
        self.scale = scale
    }

    var imageFrame: CGRect {
        CGRect(x: -Self.inkPadding, y: 0, width: width + 2 * Self.inkPadding, height: height)
    }

    func image(color: CGColor, in space: CGColorSpace?) -> CGImage? {
        let frame = imageFrame
        func context(in space: CGColorSpace?) -> CGContext? {
            guard let space, space.model == .rgb else { return nil }
            return CGContext(
                data: nil,
                width: Int((frame.width * scale).rounded(.up)),
                height: Int((frame.height * scale).rounded(.up)),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        guard let context = context(in: space) ?? context(in: CGColorSpace(name: CGColorSpace.displayP3)) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(color)
        for (line, left) in zip(lines, lefts) {
            context.textPosition = CGPoint(x: left + Self.inkPadding, y: baseline)
            CTLineDraw(line, context)
        }
        return context.makeImage()
    }

    private static func font(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }
}

struct KaraokeFillSchedule: TimelineSchedule {
    let referenceDate: Date
    let referenceElapsed: TimeInterval
    let windows: [ClosedRange<TimeInterval>]
    private let boundaries: [TimeInterval]

    static let idleInterval: TimeInterval = 60
    static let landingDelay: TimeInterval = 0.001

    init(
        referenceDate: Date,
        referenceElapsed: TimeInterval,
        windows: [ClosedRange<TimeInterval>]
    ) {
        self.referenceDate = referenceDate
        self.referenceElapsed = referenceElapsed
        self.windows = windows

        let sorted = windows
            .flatMap { [$0.lowerBound, $0.upperBound] }
            .filter(\.isFinite)
            .sorted()
        self.boundaries = sorted.reduce(into: []) { result, value in
            if result.last != value { result.append(value) }
        }
    }

    static func eventWindows(for lyrics: [LyricLine]) -> [ClosedRange<TimeInterval>] {
        lyrics.flatMap { line in
            var events = [line.timestamp]
            if let end = line.endTimestamp { events.append(end) }
            for word in line.words + line.background where word.timestamp >= 0 {
                events.append(word.timestamp)
                if let end = word.endTimestamp { events.append(end) }
            }
            if let timing = MomentumLineTiming(line: line) { events.append(timing.animationEnd) }
            return events.map { $0...$0 }
        }
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        let elapsed = elapsed(at: startDate)
        return Entries(
            schedule: self,
            cursor: startDate,
            nextBoundaryIndex: boundaries.firstIndex {
                $0 + Self.landingDelay > elapsed + Entries.epsilon
            } ?? boundaries.endIndex,
            lowFrequency: mode == .lowFrequency
        )
    }

    fileprivate func elapsed(at date: Date) -> TimeInterval {
        referenceElapsed + date.timeIntervalSince(referenceDate)
    }

    fileprivate func date(atElapsed elapsed: TimeInterval) -> Date {
        referenceDate.addingTimeInterval(elapsed - referenceElapsed)
    }

    struct Entries: Sequence, IteratorProtocol {
        fileprivate static let epsilon = 0.0005

        let schedule: KaraokeFillSchedule
        var cursor: Date
        var nextBoundaryIndex: Int
        let lowFrequency: Bool

        mutating func next() -> Date? {
            let date = cursor
            if !lowFrequency, nextBoundaryIndex < schedule.boundaries.endIndex {
                cursor = schedule.date(
                    atElapsed: schedule.boundaries[nextBoundaryIndex] + KaraokeFillSchedule.landingDelay
                )
                nextBoundaryIndex += 1
            } else {
                cursor = date.addingTimeInterval(KaraokeFillSchedule.idleInterval)
            }
            return date
        }
    }
}

struct LyricLineView: View, Equatable {
    let lyric: LyricLine
    let isCurrent: Bool
    let accentColor: Color
    let elapsedTime: TimeInterval
    var alignment: HorizontalAlignment = .center
    var fontSize: CGFloat = 26

    static func == (lhs: LyricLineView, rhs: LyricLineView) -> Bool {
        guard lhs.lyric == rhs.lyric,
              lhs.isCurrent == rhs.isCurrent,
              lhs.accentColor == rhs.accentColor,
              lhs.alignment == rhs.alignment,
              lhs.fontSize == rhs.fontSize else { return false }

        return lhs.highlightedWordCount == rhs.highlightedWordCount
            && lhs.backgroundStarted == rhs.backgroundStarted
    }

    private var highlightedWordCount: Int {
        guard isCurrent, lyric.hasReconstructibleWordTiming else { return 0 }
        var lowerBound = 0
        var upperBound = lyric.words.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if lyric.words[midpoint].timestamp <= elapsedTime {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        return lowerBound
    }

    private var backgroundLine: LyricLine? { LyricsVocalParts.backgroundLine(of: lyric) }

    private var backgroundStarted: Bool {
        guard isCurrent, let start = backgroundLine?.timestamp else { return false }
        return elapsedTime >= start - 0.3
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            WordSyncedLyricText(
                lyric: lyric,
                elapsedTime: elapsedTime,
                isActive: isCurrent,
                highlightColor: accentColor,
                inactiveColor: .primary
            )
                .font(.system(size: fontSize, weight: .bold))
                .multilineTextAlignment(textAlignment)
                .shadow(radius: 5)

            if let backgroundLine {
                WordSyncedLyricText(
                    lyric: backgroundLine,
                    elapsedTime: elapsedTime,
                    isActive: backgroundStarted,
                    highlightColor: accentColor,
                    inactiveColor: .primary
                )
                    .font(.system(size: fontSize * 0.62, weight: .semibold))
                    .multilineTextAlignment(textAlignment)
                    .opacity(0.85)
            }

            if let romanization = lyric.romanization {
                Text(romanization)
                    .font(.system(size: fontSize * 0.5, weight: .medium))
                    .multilineTextAlignment(textAlignment)
                    .foregroundStyle(.secondary)
            }

            if let translated = lyric.translatedText, !translated.isEmpty {
                Text(translated)
                    .font(.system(size: fontSize * 0.7, weight: .medium))
                    .multilineTextAlignment(textAlignment)
                    .foregroundColor(isCurrent ? accentColor : .secondary)
                    .opacity(isCurrent ? 0.8 : 0.6)
            }
        }
        .scaleEffect(isCurrent ? 1.0 : 0.90)
        .opacity(isCurrent ? 1.0 : 0.5)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isCurrent)
    }
}

enum LyricsLayout {
    static func duetSides(_ lyrics: [LyricLine]) -> [UUID: HorizontalAlignment] {
        var order: [String] = []
        for agent in lyrics.compactMap(\.agent) where !order.contains(agent) { order.append(agent) }
        guard order.count >= 2 else { return [:] }
        return Dictionary(uniqueKeysWithValues: lyrics.map { line in
            (line.id, line.agent == order[1] ? HorizontalAlignment.trailing : .leading)
        })
    }

    static let minimumInterlude: TimeInterval = 4

    static func interlude(in lyrics: [LyricLine], at elapsed: TimeInterval) -> (start: TimeInterval, end: TimeInterval, nextIndex: Int)? {
        guard let nextIndex = lyrics.firstIndex(where: { $0.timestamp > elapsed && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let next = lyrics[nextIndex]
        let previous = lyrics[..<nextIndex].last { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let start: TimeInterval
        if let previous {
            let sungEnd = (previous.words + previous.background).map { $0.endTimestamp ?? $0.timestamp }.max()
            start = previous.endTimestamp ?? sungEnd ?? previous.timestamp + LyricsWordAligner.fallbackLineDuration
        } else {
            start = 0
        }
        guard next.timestamp - start >= minimumInterlude, elapsed >= start else { return nil }
        return (start, next.timestamp, nextIndex)
    }
}

struct LyricsInterludeDots: View {
    let start: TimeInterval
    let end: TimeInterval
    let color: Color

    private var musicManager: MusicManager { .shared }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !musicManager.isPlaying)) { context in
            let elapsed = musicManager.lyricsElapsedTime(at: context.date)
            let progress = min(max((elapsed - start) / max(end - start, 0.1), 0), 1)
            let remaining = end - elapsed
            let exit = MomentumLineTiming.smoothstep(remaining / 0.5)
            let breath = 1 + 0.12 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.4)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { dot in
                    let fill = MomentumLineTiming.smoothstep(progress * 3 - Double(dot))
                    Circle()
                        .fill(color.opacity(0.3 + 0.7 * fill))
                        .frame(width: 12, height: 12)
                }
            }
            .scaleEffect(breath * exit)
            .opacity(exit)
        }
    }
}

private struct LyricsPlaybackState {
    let elapsed: TimeInterval
    let activeIDs: Set<UUID>
    let currentID: UUID?
}

private extension MusicManager {
    func lyricsPlaybackState(for lyrics: [LyricLine], at date: Date) -> LyricsPlaybackState {
        let elapsed = lyricsElapsedTime(at: date)
        let activeIndices = LyricsTimeline.activeIndices(
            in: lyrics,
            at: elapsed,
            trackDuration: totalDuration > 0 ? totalDuration : nil
        )
        let activeIDs = Set(activeIndices.compactMap { index in
            lyrics.indices.contains(index) ? lyrics[index].id : nil
        })
        let currentID = activeIndices.max { lhs, rhs in
            if lyrics[lhs].timestamp == lyrics[rhs].timestamp {
                return lhs < rhs
            }
            return lyrics[lhs].timestamp < lyrics[rhs].timestamp
        }.map { lyrics[$0].id }
            ?? lyrics.last(where: { $0.timestamp <= elapsed })?.id

        return LyricsPlaybackState(elapsed: elapsed, activeIDs: activeIDs, currentID: currentID)
    }
}

struct LyricsView: View {
    var musicManager: MusicManager { .shared }

    private var lyrics: [LyricLine] { musicManager.lyrics }
    private var accentColor: Color { musicManager.accentColor }

    private let lineSpacing: CGFloat = 70.0

    var body: some View {
        TimelineView(KaraokeFillSchedule(
            referenceDate: Date(),
            referenceElapsed: musicManager.lyricsElapsedTime(),
            windows: musicManager.isPlaying ? KaraokeFillSchedule.eventWindows(for: lyrics) : []
        )) { context in
            let playbackState = musicManager.lyricsPlaybackState(for: lyrics, at: context.date)
            let playbackElapsed = musicManager.elapsedTime(at: context.date)

            GeometryReader { geometry in
                let computedOffset = calculateScrollOffset(
                    fullViewHeight: geometry.size.height,
                    currentLyricID: playbackState.currentID
                )

                ZStack(alignment: .topLeading) {
                    Group {
                        if lyrics.isEmpty {
                            emptyLyricsView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            let currentIndex = lyrics.firstIndex { $0.id == playbackState.currentID } ?? 0
                            VStack(spacing: 0) {
                                ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, lyric in
                                    LyricLineView(
                                        lyric: lyric,
                                        isCurrent: playbackState.activeIDs.contains(lyric.id),
                                        accentColor: accentColor,
                                        elapsedTime: playbackState.elapsed
                                    )
                                    .equatable()
                                    .frame(height: lineSpacing)
                                    .offset(y: computedOffset)
                                    .animation(
                                        LyricsMomentumScroll.animation(index: index, currentIndex: currentIndex),
                                        value: playbackState.currentID
                                    )
                                }
                            }
                            .frame(width: geometry.size.width)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask {
                        let viewHeight = geometry.size.height

                        if viewHeight > 0 {
                            let topFadeLength: CGFloat = 10
                            let bottomFadeLength: CGFloat = 18
                            let topFadePercentage = topFadeLength / viewHeight
                            let bottomFadePercentage = bottomFadeLength / viewHeight

                            let solidStartLocation = min(topFadePercentage, 0.5)
                            let solidEndLocation = max(1.0 - bottomFadePercentage, 0.5)

                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: solidStartLocation),
                                    .init(color: .black, location: solidEndLocation),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color.black
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    trackHeaderView(elapsed: playbackElapsed)
                        .padding(.leading, 5)
                }
            }
        }
        .frame(width: 550, height: 250)
        .onAppear {
            Task { await musicManager.setLyricsDetailOpen(true) }
        }
        .onDisappear {
            Task { await musicManager.setLyricsDetailOpen(false) }
        }
    }

    private func calculateScrollOffset(fullViewHeight: CGFloat, currentLyricID: UUID?) -> CGFloat {
        guard let currentIndex = lyrics.firstIndex(where: { $0.id == currentLyricID }) else {
            let totalContentHeight = CGFloat(lyrics.count) * lineSpacing
            return (fullViewHeight - totalContentHeight) / 2
        }

        let targetOffset = (fullViewHeight / 2) - (lineSpacing / 2) - (CGFloat(currentIndex) * lineSpacing)
        return targetOffset
    }

    private var emptyLyricsView: some View {
        Text("No lyrics available.")
            .font(.headline)
            .foregroundColor(.secondary)
    }

    private func trackHeaderView(elapsed: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let artwork = musicManager.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .foregroundStyle(.white.opacity(0.85))
                            .background(.white.opacity(0.12))
                    }
                }
                .frame(width: 25, height: 26)

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(displayTitle)
                        .font(.system(size: 9, weight: .semibold))

                    if let album = musicManager.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let artist = musicManager.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("\(elapsed.asMinuteSecondClock) / \(musicManager.totalDuration.asMinuteSecondClock)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Button(action: openLyricsWindow) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                    Text("Open in Window")
                }
                .font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var displayTitle: String {
        if let title = musicManager.title, !title.isEmpty {
            return title
        }
        return "Not Playing"
    }

    private func openLyricsWindow() {
        (NSApp.delegate as? AppDelegate)?.openLyricsWindow()
    }
}

// MARK: - Consolidated from LyricsDetachedWindowView.swift

// MARK: - Window Accessor Helper
struct WindowAccessor: NSViewRepresentable {
    var onChange: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onChange(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct LyricsDetachedWindowView: View {
    @State private var hostingWindow: NSWindow? = nil
    private let musicManager = MusicManager.shared

    var body: some View {
        ZStack {
            // MARK: - Apple TV Ambient Background (Micro-Blur optimized)
            LyricsDetachedAmbientBackground()

            VStack(spacing: 0) {
                // MARK: - Top Window Controls (Invisible Drag Area)
                HStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(nsColor: .systemRed)).frame(width: 12, height: 12)
                            .onTapGesture { hostingWindow?.performClose(nil) }
                        Circle().fill(Color(nsColor: .systemYellow)).frame(width: 12, height: 12)
                            .onTapGesture { hostingWindow?.miniaturize(nil) }
                        Circle().fill(Color(nsColor: .systemGreen)).frame(width: 12, height: 12)
                            .onTapGesture { hostingWindow?.zoom(nil) }
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.leading, 20)
                .frame(height: 30)
                .background(Color.clear)

                // MARK: - Middle Content (Art + Lyrics)
                HStack(alignment: .center, spacing: 60) {
                    LyricsDetachedLeftPane()
                        .frame(width: 320)

                    LyricsDetachedRightPane()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)
                .padding(.bottom, 40)

                // MARK: - Bottom Player Controls (Scrubber & Buttons)
                LyricsDetachedBottomBar()
                    .padding(.horizontal, 60)
                    .padding(.bottom, 30)
            }
        }
        .frame(minWidth: 1100, idealWidth: 1280, minHeight: 650, idealHeight: 760)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .background(
            WindowAccessor { window in
                self.hostingWindow = window
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true

                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        )
        .onAppear {
            Task { await musicManager.setDetachedLyricsOpen(true) }
        }
        .onDisappear {
            Task { await musicManager.setDetachedLyricsOpen(false) }
        }
    }
}

private struct LyricsDetachedAmbientBackground: View {
    private var musicManager: MusicManager { .shared }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = musicManager.artwork ?? musicManager.appIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width / 10, height: geo.size.height / 10)
                        .blur(radius: 12, opaque: true)
                        .saturation(1.2)
                        .scaleEffect(10.5)
                        .animation(.easeInOut(duration: 1.5), value: image)
                } else {
                    musicManager.accentColor
                        .opacity(0.4)
                        .blur(radius: 100)
                }

                Color.black.opacity(0.65)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Left Pane (Artwork & Text)
private struct LyricsDetachedLeftPane: View {
    var musicManager: MusicManager { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Group {
                if let image = musicManager.artwork ?? musicManager.appIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.05)
                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
            }
            .frame(width: 320, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .scaleEffect(musicManager.isPlaying ? 1.0 : 0.95)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: musicManager.isPlaying)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.tv.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(displayTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(displayArtist)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.leading, 4)

            SongCreditsView(title: musicManager.title, artist: musicManager.artist)
                .padding(.leading, 4)
        }
    }

    private var displayTitle: String {
        if let title = musicManager.title, !title.isEmpty { return title }
        return "Not Playing"
    }

    private var displayArtist: String {
        if let artist = musicManager.artist, !artist.isEmpty { return artist }
        return "Unknown Artist"
    }
}

private struct SongCreditsView: View {
    let title: String?
    let artist: String?

    @State private var info: SongInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info {
                if let album = info.album {
                    Text([album, info.releaseYear].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                ForEach(info.creditSections) { section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.35))
                        Text(section.names.joined(separator: ", "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(width: 320, alignment: .leading)
        .animation(.easeOut(duration: 0.25), value: info)
        .task(id: "\(title ?? "")|\(artist ?? "")") {
            info = nil
            guard let title, let artist, !title.isEmpty, !artist.isEmpty else { return }
            info = await SongInfoService.shared.info(title: title, artist: artist)
        }
    }
}

private struct SongCreditsFooter: View {
    let title: String?
    let artist: String?

    @State private var writers: [String] = []

    var body: some View {
        Group {
            if !writers.isEmpty {
                Text("Written by: \(writers.joined(separator: ", "))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .task(id: "\(title ?? "")|\(artist ?? "")") {
            writers = []
            guard let title, let artist, !title.isEmpty, !artist.isEmpty,
                  let info = await SongInfoService.shared.info(title: title, artist: artist) else { return }
            writers = info.creditSections.first { $0.title == "Written By" }?.names ?? []
        }
    }
}

// MARK: - Right Pane (Lyrics)
private struct LyricsDetachedRightPane: View {
    var musicManager: MusicManager { .shared }

    private var lyrics: [LyricLine] { musicManager.lyrics }

    private static let lineSpacing: CGFloat = 32
    private static let estimatedLineHeight: CGFloat = 52
    private static let anchorFraction: CGFloat = 0.36
    private static let browseHold: Duration = .seconds(3)

    @State private var lineHeights: [UUID: CGFloat] = [:]
    @State private var browseOffset: CGFloat = 0
    @State private var isBrowsing = false
    @State private var isHovering = false
    @State private var scrollMonitor: Any?
    @State private var browseReset: Task<Void, Never>?

    var body: some View {
        TimelineView(KaraokeFillSchedule(
            referenceDate: Date(),
            referenceElapsed: musicManager.lyricsElapsedTime(),
            windows: musicManager.isPlaying ? KaraokeFillSchedule.eventWindows(for: lyrics) : []
        )) { context in
            let playbackState = musicManager.lyricsPlaybackState(for: lyrics, at: context.date)

            Group {
                if lyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Lyrics aren't available.")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    GeometryReader { geometry in
                        column(playbackState: playbackState, size: geometry.size)
                    }
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.2),
                                .init(color: .black, location: 0.8),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onAppear(perform: installScrollMonitor)
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
            browseReset?.cancel()
        }
    }

    private func column(playbackState: LyricsPlaybackState, size: CGSize) -> some View {
        let lyrics = self.lyrics
        let currentIndex = lyrics.firstIndex { $0.id == playbackState.currentID } ?? 0
        var tops: [CGFloat] = []
        tops.reserveCapacity(lyrics.count)
        var cursor: CGFloat = 0
        for lyric in lyrics {
            tops.append(cursor)
            cursor += (lineHeights[lyric.id] ?? Self.estimatedLineHeight) + Self.lineSpacing
        }
        let origin = size.height * Self.anchorFraction - (tops.indices.contains(currentIndex) ? tops[currentIndex] : 0) + browseOffset
        let sides = LyricsLayout.duetSides(lyrics)
        let interlude = LyricsLayout.interlude(in: lyrics, at: playbackState.elapsed)

        return ZStack(alignment: .topLeading) {
            ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, lyric in
                let isCurrent = playbackState.activeIDs.contains(lyric.id)
                let distance = abs(index - currentIndex)
                let side = sides[lyric.id] ?? .leading
                let frameAlignment: Alignment = side == .trailing ? .trailing : .leading
                let anchor: UnitPoint = side == .trailing ? .trailing : .leading

                LyricLineView(
                    lyric: lyric,
                    isCurrent: isCurrent,
                    accentColor: .white,
                    elapsedTime: playbackState.elapsed,
                    alignment: side,
                    fontSize: isCurrent ? 44 : 36
                )
                .equatable()
                .foregroundStyle(.white)
                .scaleEffect(isCurrent ? 1.0 : 0.95, anchor: anchor)
                .opacity(isCurrent || isBrowsing ? 1.0 : 0.35)
                .blur(radius: isCurrent || isBrowsing || distance > 6 ? 0 : min(CGFloat(distance), 4) * 0.6)
                .animation(.spring(response: 0.45, dampingFraction: 0.8, blendDuration: 0.1), value: isCurrent)
                .frame(width: size.width * (sides.isEmpty ? 1 : 0.86), alignment: frameAlignment)
                .frame(width: size.width, alignment: frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeights[lyric.id] = $0 }
                .contentShape(Rectangle())
                .onTapGesture { Task { await musicManager.seek(to: lyric.timestamp) } }
                .offset(y: origin + tops[index])
                .animation(
                    LyricsMomentumScroll.animation(index: index, currentIndex: currentIndex),
                    value: playbackState.currentID
                )
            }

            if let interlude, tops.indices.contains(interlude.nextIndex) {
                LyricsInterludeDots(start: interlude.start, end: interlude.end, color: .white)
                    .frame(width: size.width, alignment: sides[lyrics[interlude.nextIndex].id] == .trailing ? .trailing : .leading)
                    .offset(y: origin + tops[interlude.nextIndex] - 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
            }

            SongCreditsFooter(title: musicManager.title, artist: musicManager.artist)
                .frame(width: size.width, alignment: .leading)
                .offset(y: origin + cursor + 12)
                .animation(LyricsMomentumScroll.animation(index: lyrics.count, currentIndex: currentIndex), value: playbackState.currentID)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHovering, !lyrics.isEmpty else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
            browseOffset += delta
            isBrowsing = true
            browseReset?.cancel()
            browseReset = Task { @MainActor in
                try? await Task.sleep(for: Self.browseHold)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                    browseOffset = 0
                    isBrowsing = false
                }
            }
            return nil
        }
    }
}

// MARK: - Bottom Pane (Scrubber & Playback)
private struct LyricsDetachedBottomBar: View {
    var musicManager: MusicManager { .shared }
    @ObservedSettings var settings: SettingsObserver
    @State private var currentProgress: Double = 0.0
    @State private var displayedElapsedTime: TimeInterval = 0
    @StateObject private var holdFeedback = MusicHoldFeedbackController(palette: .lightOverlay)

    private var holdFeedbackIcon: String? { holdFeedback.icon }
    private var holdFeedbackColor: Color { holdFeedback.color }
    private var holdFeedbackButtonID: String? { holdFeedback.buttonID }

    var body: some View {
        VStack(spacing: 20) {

            VStack(spacing: 8) {
                InteractiveProgressBar(
                    value: $currentProgress,
                    gradient: Gradient(colors: [.white, .white.opacity(0.8)]),
                    onSeek: { newProgress in
                        let seekTime = newProgress * musicManager.totalDuration
                        if seekTime.isFinite && musicManager.totalDuration > 0 {
                            Task { await musicManager.seek(to: seekTime) }
                        }
                    }
                )
                .frame(height: 4)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())

                HStack {
                    Text(displayedElapsedTime.asMinuteSecondClock)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Text("-" + (max(0, musicManager.totalDuration - displayedElapsedTime)).asMinuteSecondClock)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(spacing: 32) {
                SeekButton(
                    systemName: "backward.fill",
                    onTap: { Task { await musicManager.previousTrack() } },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: skipHoldClosure(for: .previous),
                    holdAction: skipHoldAction(for: .previous),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "previous") },
                    onHoldEnded: endHoldFeedback,
                    displayedSystemName: holdFeedbackButtonID == "previous" ? holdFeedbackIcon : nil
                )
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(holdFeedbackButtonID == "previous" ? holdFeedbackColor : .white.opacity(0.8))
                .help(MusicLongPressUI.skipHelp(primary: "Previous", target: .previous, settings: settings.settings.value))

                LongPressControlButton(
                    onTap: {
                        Task {
                            if musicManager.isPlaying {
                                await musicManager.pause()
                            } else {
                                await musicManager.play()
                            }
                        }
                    },
                    onLongPress: accessoryHoldHandler(for: .playPause),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "playPause") },
                    holdAction: settings.settings.value.resolvedAccessoryHoldAction(for: .playPause),
                    onHoldEnded: endHoldFeedback
                ) {
                    Image(systemName: holdFeedbackButtonID == "playPause"
                          ? (holdFeedbackIcon ?? (musicManager.isPlaying ? "pause.fill" : "play.fill"))
                          : (musicManager.isPlaying ? "pause.fill" : "play.fill"))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(holdFeedbackButtonID == "playPause" ? holdFeedbackColor : .white)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .scaleEffect(musicManager.isPlaying ? 1.0 : 0.95)
                .animation(.easeInOut(duration: 0.15), value: holdFeedbackIcon)
                .help(MusicLongPressUI.accessoryHelp(primary: "Play / Pause", target: .playPause, settings: settings.settings.value))

                SeekButton(
                    systemName: "forward.fill",
                    onTap: { Task { await musicManager.nextTrack() } },
                    onSeek: { isForward in Task { await musicManager.seek(by: isForward ? 5.0 : -5.0) } },
                    onLongPressAction: skipHoldClosure(for: .next),
                    holdAction: skipHoldAction(for: .next),
                    onHoldBegan: { action in beginHoldFeedback(action: action, buttonID: "next") },
                    onHoldEnded: endHoldFeedback,
                    displayedSystemName: holdFeedbackButtonID == "next" ? holdFeedbackIcon : nil
                )
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(holdFeedbackButtonID == "next" ? holdFeedbackColor : .white.opacity(0.8))
                .help(MusicLongPressUI.skipHelp(primary: "Next", target: .next, settings: settings.settings.value))
            }
        }
        .onAppear {
            currentProgress = musicManager.playbackProgress
            displayedElapsedTime = musicManager.currentElapsedTime
        }
        .onReceive(musicManager.playbackTimePublisher) { payload in
            displayedElapsedTime = payload.elapsed
            currentProgress = payload.progress
        }
    }

    private func accessoryHoldHandler(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = settings.settings.value.resolvedAccessoryHoldAction(for: target) else { return nil }
        return holdFeedback.handler(for: action, musicManager: musicManager, navigation: .notifications)
    }

    private func skipHoldAction(for target: MusicLongPressTarget) -> MusicLongPressAction? {
        holdFeedback.skipAction(for: target, settings: settings.settings.value)
    }

    private func skipHoldClosure(for target: MusicLongPressTarget) -> (() -> Void)? {
        guard let action = skipHoldAction(for: target) else { return nil }
        return holdFeedback.handler(for: action, musicManager: musicManager, navigation: .notifications)
    }

    private func beginHoldFeedback(action: MusicLongPressAction, buttonID: String) {
        holdFeedback.begin(action: action, buttonID: buttonID, musicManager: musicManager)
    }

    private func endHoldFeedback() {
        holdFeedback.end()
    }

}