//
//  MomentumLyricText.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-12

import SwiftUI

struct MomentumLineTiming: Equatable {
    struct Token: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let group: Int
        let glyphOffset: Int
    }

    struct Group: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let glyphCount: Int
        let emphasis: Double
    }

    static let settleDuration: TimeInterval = 0.45
    static let emphasisMinimumDuration: TimeInterval = 1.0
    static let emphasisMaximumLetters = 12

    let tokens: [Token]
    let groups: [Group]
    let animationEnd: TimeInterval

    init?(line: LyricLine) {
        guard line.hasReconstructibleWordTiming else { return nil }
        var tokens: [Token] = []
        var groups: [Group] = []
        tokens.reserveCapacity(line.words.count)

        var groupStart: TimeInterval?
        var groupEnd: TimeInterval = 0
        var letters = 0
        for (index, word) in line.words.enumerated() {
            let start = word.timestamp
            let end = max(start, line.wordFillEndTimestamp(at: index) ?? start)
            if groupStart == nil { groupStart = start }
            tokens.append(Token(start: start, end: end, group: groups.count, glyphOffset: letters))
            letters += word.text.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
            groupEnd = max(groupEnd, end)

            let endsWord = index == line.words.count - 1
                || word.text.last?.isWhitespace == true
                || word.text.last.map(Self.isCJK) == true
            guard endsWord, let start = groupStart else { continue }
            let duration = groupEnd - start
            let isHeld = duration >= Self.emphasisMinimumDuration
                && (1...Self.emphasisMaximumLetters).contains(letters)
            groups.append(Group(
                start: start,
                end: groupEnd,
                glyphCount: max(letters, 1),
                emphasis: isHeld ? min(1, 0.55 + (duration - Self.emphasisMinimumDuration) * 0.3) : 0
            ))
            groupStart = nil
            groupEnd = 0
            letters = 0
        }

        self.tokens = tokens
        self.groups = groups
        self.animationEnd = (groups.map(\.end).max() ?? 0) + Self.settleDuration
    }

    func progress(ofToken index: Int, at elapsed: TimeInterval) -> Double {
        let token = tokens[index]
        guard elapsed > token.start else { return 0 }
        guard token.end > token.start else { return 1 }
        return min((elapsed - token.start) / (token.end - token.start), 1)
    }

    func swell(ofGroup index: Int, glyph: Int, at elapsed: TimeInterval) -> Double {
        let group = groups[index]
        guard group.emphasis > 0, elapsed > group.start, elapsed < group.end + Self.settleDuration else { return 0 }
        let duration = max(group.end - group.start, 0.001)
        let lead = 0.55 * Double(min(glyph, group.glyphCount - 1)) / Double(group.glyphCount)
        let rise = Self.smoothstep(((elapsed - group.start) / duration - lead) / 0.45)
        let fall = 1 - Self.smoothstep((elapsed - group.end) / Self.settleDuration)
        return rise * fall * group.emphasis
    }

    static func smoothstep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }
}

struct MomentumToken: TextAttribute {
    let index: Int
}

@available(macOS 15.0, *)
struct MomentumLyricRenderer: TextRenderer {
    static let inactiveOpacity = 0.38
    static let liftFraction = 0.06
    static let swellScale = 0.13

    let timing: MomentumLineTiming
    let elapsed: TimeInterval
    let highlight: Color
    let inactive: Color

    var displayPadding: EdgeInsets { EdgeInsets(top: 18, leading: 12, bottom: 12, trailing: 12) }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let index = run[MomentumToken.self]?.index, timing.tokens.indices.contains(index) else {
                    ctx.draw(run)
                    continue
                }
                drawToken(run, index: index, in: ctx)
            }
        }
    }

    private func drawToken(_ run: Text.Layout.Run, index: Int, in ctx: GraphicsContext) {
        let token = timing.tokens[index]
        let bounds = run.typographicBounds.rect
        let progress = timing.progress(ofToken: index, at: elapsed)
        let lift = bounds.height * Self.liftFraction * (1 - pow(1 - progress, 3))

        let group = timing.groups[token.group]
        let swelling = group.emphasis > 0
            && elapsed > group.start
            && elapsed < group.end + MomentumLineTiming.settleDuration
        guard swelling else {
            var context = ctx
            context.translateBy(x: 0, y: -lift)
            paint(bounds, progress: progress, in: context) { $0.draw(run) }
            return
        }

        for (offset, slice) in run.enumerated() {
            let swell = timing.swell(ofGroup: token.group, glyph: token.glyphOffset + offset, at: elapsed)
            let glyph = slice.typographicBounds.rect
            var context = ctx
            let scale = 1 + Self.swellScale * swell
            context.translateBy(x: glyph.midX, y: glyph.maxY - lift - bounds.height * 0.05 * swell)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -glyph.midX, y: -glyph.maxY)
            if swell > 0.01 {
                context.addFilter(.shadow(color: highlight.opacity(0.75 * swell), radius: glyph.height * 0.28))
            }
            paint(bounds, progress: progress, in: context) { $0.draw(slice) }
        }
    }

    private func paint(
        _ bounds: CGRect,
        progress: Double,
        in ctx: GraphicsContext,
        draw: (inout GraphicsContext) -> Void
    ) {
        if progress < 1 {
            var dim = ctx
            dim.opacity = Self.inactiveOpacity
            dim.addFilter(.colorMultiply(inactive))
            draw(&dim)
        }
        guard progress > 0 else { return }

        var lit = ctx
        lit.addFilter(.colorMultiply(highlight))
        if progress < 1 {
            let feather = max(bounds.height * 0.5, 6)
            let edge = bounds.minX - feather + (bounds.width + 2 * feather) * progress
            lit.clipToLayer { mask in
                mask.fill(
                    Path(bounds.insetBy(dx: -2 * feather, dy: -bounds.height)),
                    with: .linearGradient(
                        Gradient(colors: [.black, .clear]),
                        startPoint: CGPoint(x: edge - feather, y: bounds.midY),
                        endPoint: CGPoint(x: edge + feather, y: bounds.midY)
                    )
                )
            }
        }
        draw(&lit)
    }
}

@available(macOS 15.0, *)
struct MomentumLyricText: View {
    let lyric: LyricLine
    let timing: MomentumLineTiming
    let highlightColor: Color
    let inactiveColor: Color

    private var musicManager: MusicManager { .shared }

    var body: some View {
        let text = lyric.words.enumerated().reduce(Text("")) { text, item in
            text + Text(verbatim: item.element.text).customAttribute(MomentumToken(index: item.offset))
        }
        .foregroundStyle(.white)

        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !isAnimating)) { context in
            text.textRenderer(MomentumLyricRenderer(
                timing: timing,
                elapsed: musicManager.lyricsElapsedTime(at: context.date),
                highlight: highlightColor,
                inactive: inactiveColor
            ))
        }
    }

    static let frameInterval: TimeInterval = 1.0 / 60

    private var isAnimating: Bool {
        musicManager.isPlaying && musicManager.lyricsElapsedTime() < timing.animationEnd
    }
}

enum LyricsMomentumScroll {
    static let stagger: TimeInterval = 0.045
    static let maximumDelay: TimeInterval = 0.4

    static func animation(index: Int, currentIndex: Int) -> Animation {
        let delay = min(Double(max(index - currentIndex, 0)) * stagger, maximumDelay)
        return .spring(response: 0.62, dampingFraction: 0.82).delay(delay)
    }
}