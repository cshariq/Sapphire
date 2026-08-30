# Spotify-Style Progress Scrubber Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Spotify-like hover scrub chrome (glass thumb, floating time tooltip, ahead preview wash) to shared `InteractiveProgressBar` for all call sites.

**Architecture:** Pure math helpers + glass thumb/tooltip subviews; extend `InteractiveProgressBar` with hover tracking and optional `duration` / `trackHeight`; wire duration from player and lyrics; keep seek-on-release.

**Tech Stack:** SwiftUI, AppKit (`onContinuousHover`), `LiquidGlassShapeFill` / `VisualEffectView`, Swift Testing (`SapphireTests`)

## Global Constraints

- Enrich shared `InteractiveProgressBar` only — no second scrubber API
- Thumb/tooltip use `LiquidGlassShapeFill` + VisualEffect fallback (same structure as lock/notch glass)
- Thumb blends `.withinWindow`, appearance `.dark`
- Seek commits on gesture end; no continuous Media Remote seeks while dragging
- Hover anywhere on bar → thumb + tooltip; ahead-only preview wash
- Tooltip floats above pointer; hide when `duration` nil or ≤ 0
- Work in a new git worktree / feature branch
- Spec: `docs/superpowers/specs/2026-08-30-spotify-style-progress-scrubber-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Sapphire/Utilities/ProgressScrubMath.swift` | Clamp progress, thumb inset X, format `m:ss`, preview range |
| `Sapphire/Utilities/ProgressScrubChrome.swift` | `ProgressScrubThumb`, `ProgressScrubTooltip` glass + fallback views |
| `Sapphire/Utilities/Helpers.swift` | Extended `InteractiveProgressBar` (hover, wash, chrome, gestures) |
| `Sapphire/Widgets/MusicPlayer/MusicPlayerViews.swift` | Pass `duration` / `trackHeight` from `PlayerProgressView` |
| `Sapphire/Widgets/MusicPlayer/LyricsViews.swift` | Pass duration; stop outer clip that would hide thumb |
| `SapphireTests/ProgressScrubMathTests.swift` | Unit tests for math helpers |

---

### Task 1: Progress scrub math helpers + tests

**Files:**
- Create: `Sapphire/Utilities/ProgressScrubMath.swift`
- Create: `SapphireTests/ProgressScrubMathTests.swift`

**Interfaces:**
- Produces:
  - `enum ProgressScrubMath`
  - `static func clampProgress(_ value: Double) -> Double`
  - `static func progress(fromX x: CGFloat, width: CGFloat) -> Double`
  - `static func thumbCenterX(progress: Double, width: CGFloat, thumbDiameter: CGFloat) -> CGFloat`
  - `static func formatTime(_ seconds: Double) -> String`
  - `static func tooltipTime(progress: Double, duration: TimeInterval) -> String?`
  - `static func thumbDiameter(trackHeight: CGFloat, multiplier: CGFloat = 1.6, minimum: CGFloat = 10) -> CGFloat`

- [ ] **Step 1: Write the failing tests**

```swift
// SapphireTests/ProgressScrubMathTests.swift
import Foundation
import Testing
@testable import Sapphire

struct ProgressScrubMathTests {
    @Test func clampProgressLimitsToUnitInterval() {
        #expect(ProgressScrubMath.clampProgress(-0.2) == 0)
        #expect(ProgressScrubMath.clampProgress(0.4) == 0.4)
        #expect(ProgressScrubMath.clampProgress(1.5) == 1)
        #expect(ProgressScrubMath.clampProgress(.nan) == 0)
    }

    @Test func progressFromXMapsAndClamps() {
        #expect(ProgressScrubMath.progress(fromX: -10, width: 100) == 0)
        #expect(ProgressScrubMath.progress(fromX: 50, width: 100) == 0.5)
        #expect(ProgressScrubMath.progress(fromX: 150, width: 100) == 1)
        #expect(ProgressScrubMath.progress(fromX: 50, width: 0) == 0)
    }

    @Test func thumbCenterXInsetsAtEnds() {
        #expect(ProgressScrubMath.thumbCenterX(progress: 0, width: 100, thumbDiameter: 10) == 5)
        #expect(ProgressScrubMath.thumbCenterX(progress: 1, width: 100, thumbDiameter: 10) == 95)
        #expect(ProgressScrubMath.thumbCenterX(progress: 0.5, width: 100, thumbDiameter: 10) == 50)
    }

    @Test func formatTimeUsesMinutesAndZeroPaddedSeconds() {
        #expect(ProgressScrubMath.formatTime(0) == "0:00")
        #expect(ProgressScrubMath.formatTime(65) == "1:05")
        #expect(ProgressScrubMath.formatTime(3661) == "61:01")
        #expect(ProgressScrubMath.formatTime(.nan) == "0:00")
    }

    @Test func tooltipTimeRequiresPositiveDuration() {
        #expect(ProgressScrubMath.tooltipTime(progress: 0.5, duration: 0) == nil)
        #expect(ProgressScrubMath.tooltipTime(progress: 0.5, duration: -1) == nil)
        #expect(ProgressScrubMath.tooltipTime(progress: 0.5, duration: 120) == "1:00")
    }

    @Test func thumbDiameterScalesWithFloor() {
        #expect(ProgressScrubMath.thumbDiameter(trackHeight: 10) == 16)
        #expect(ProgressScrubMath.thumbDiameter(trackHeight: 4) == 10)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Sapphire -destination 'platform=macOS' -only-testing:SapphireTests/ProgressScrubMathTests 2>&1 | tail -40`

Expected: compile failure — `ProgressScrubMath` not found

- [ ] **Step 3: Implement math helpers**

```swift
// Sapphire/Utilities/ProgressScrubMath.swift
import Foundation
import CoreGraphics

enum ProgressScrubMath {
    static func clampProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(0, value), 1)
    }

    static func progress(fromX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, x.isFinite, width.isFinite else { return 0 }
        return clampProgress(Double(x / width))
    }

    static func thumbCenterX(progress: Double, width: CGFloat, thumbDiameter: CGFloat) -> CGFloat {
        guard width > 0, thumbDiameter.isFinite, width.isFinite else { return 0 }
        let radius = thumbDiameter / 2
        let usable = max(0, width - thumbDiameter)
        let p = CGFloat(clampProgress(progress))
        return radius + usable * p
    }

    static func formatTime(_ seconds: Double) -> String {
        let clean = seconds.isFinite ? max(0, seconds) : 0
        let total = Int(clean)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func tooltipTime(progress: Double, duration: TimeInterval) -> String? {
        guard duration.isFinite, duration > 0 else { return nil }
        return formatTime(clampProgress(progress) * duration)
    }

    static func thumbDiameter(trackHeight: CGFloat, multiplier: CGFloat = 1.6, minimum: CGFloat = 10) -> CGFloat {
        guard trackHeight.isFinite, trackHeight > 0 else { return minimum }
        return max(minimum, trackHeight * multiplier)
    }
}
```

If the Xcode project does not auto-include new files under `Sapphire/Utilities`, add `ProgressScrubMath.swift` to the Sapphire target in `Sapphire.xcodeproj/project.pbxproj` the same way sibling Utilities files are referenced (or confirm synchronized root group).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Sapphire -destination 'platform=macOS' -only-testing:SapphireTests/ProgressScrubMathTests 2>&1 | tail -40`

Expected: all `ProgressScrubMathTests` PASS

- [ ] **Step 5: Commit**

```bash
git add Sapphire/Utilities/ProgressScrubMath.swift SapphireTests/ProgressScrubMathTests.swift Sapphire.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
Add progress scrub math helpers and unit tests.

EOF
)"
```

---

### Task 2: Glass thumb and tooltip chrome

**Files:**
- Create: `Sapphire/Utilities/ProgressScrubChrome.swift`

**Interfaces:**
- Consumes: `LiquidGlassShapeFill`, `LiquidGlassView.isSystemGlassAvailable`, `VisualEffectView`, `ProgressScrubMath`
- Produces:
  - `struct ProgressScrubThumb: View` — `diameter: CGFloat`, `intensity: Double`, `isHovered: Bool`
  - `struct ProgressScrubTooltip: View` — `text: String`, `intensity: Double`

- [ ] **Step 1: Implement chrome views**

```swift
// Sapphire/Utilities/ProgressScrubChrome.swift
import SwiftUI
import AppKit

struct ProgressScrubThumb: View {
    var diameter: CGFloat
    var intensity: Double = 0.65
    var isHovered: Bool = true

    var body: some View {
        let shape = Circle()
        ZStack {
            if #available(macOS 26.0, *), LiquidGlassView.isSystemGlassAvailable {
                LiquidGlassShapeFill(
                    shape: shape,
                    cornerRadius: diameter / 2,
                    intensity: intensity,
                    blendingMode: .withinWindow,
                    appearance: .dark,
                    interaction: isHovered ? .hovered : .normal
                )
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(shape)
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}

struct ProgressScrubTooltip: View {
    var text: String
    var intensity: Double = 0.65

    var body: some View {
        let shape = Capsule()
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    if #available(macOS 26.0, *), LiquidGlassView.isSystemGlassAvailable {
                        LiquidGlassShapeFill(
                            material: .tooltip,
                            shape: shape,
                            intensity: intensity,
                            blendingMode: .withinWindow,
                            appearance: .dark,
                            interaction: .hovered
                        )
                    } else {
                        VisualEffectView(material: .toolTip, blendingMode: .withinWindow)
                            .clipShape(shape)
                        shape.stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
                }
            }
            .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `xcodebuild -scheme Sapphire -destination 'platform=macOS' build 2>&1 | tail -30`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sapphire/Utilities/ProgressScrubChrome.swift Sapphire.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
Add Liquid Glass progress scrub thumb and tooltip.

EOF
)"
```

---

### Task 3: Extend `InteractiveProgressBar`

**Files:**
- Modify: `Sapphire/Utilities/Helpers.swift` (`InteractiveProgressBar`)

**Interfaces:**
- Consumes: `ProgressScrubMath`, `ProgressScrubThumb`, `ProgressScrubTooltip`
- Produces updated initializer params:
  - `duration: TimeInterval? = nil`
  - `trackHeight: CGFloat = 10`
  - `glassIntensity: Double = 0.65`
  - existing `value`, `gradient`, `onSeek`, `onDragChanged` unchanged

- [ ] **Step 1: Replace `InteractiveProgressBar` body**

Replace the existing struct (approx. lines 192–236 in `Helpers.swift`) with an implementation that:

1. Tracks `isHovering`, `hoverLocationX` via `.onContinuousHover(coordinateSpace: .local)`.
2. Computes `displayed = isDragging ? dragValue : value`.
3. Draws track + fill at `trackHeight`, clipped to capsule.
4. When hovering and `hoverProgress > displayed`, draws a lighter gradient wash from `displayed` width to hover width (same gradient colors at ~0.35 opacity).
5. Shows `ProgressScrubThumb` centered at `thumbCenterX(displayed, …)` when `isHovering || isDragging`.
6. Shows `ProgressScrubTooltip` when chrome visible and `tooltipTime(hoverOrDragProgress, duration)` non-nil; position above pointer X, clamp so tooltip center stays within `[tooltipWidth/2, barWidth - tooltipWidth/2]` (approximate tooltip width ~54 or measure via preference if already patterned; fixed offset Y of `-(thumbDiameter/2 + 18)` is fine).
7. Keeps existing `DragGesture(minimumDistance: 0)` seek-on-end + animation suppression.
8. Sets cursor to `.resizeLeftRight` while hovering or dragging (`.onHover` / NSCursor push-pop, or SwiftUI `.pointerStyle(.resizeLeftRight)` if targeting a version that has it; otherwise AppKit cursor override on hover change).
9. Uses `contentShape(Rectangle())` for full hit area; do **not** clip the outer ZStack to capsule (only the track fill), so the thumb can overhang.

Sketch of core layout:

```swift
struct InteractiveProgressBar: View {
    @Binding var value: Double
    var gradient: Gradient
    var onSeek: (Double) -> Void
    var onDragChanged: ((Double) -> Void)? = nil
    var duration: TimeInterval? = nil
    var trackHeight: CGFloat = 10
    var glassIntensity: Double = 0.65

    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var isHovering = false
    @State private var hoverX: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let displayed = isDragging ? dragValue : value
            let hoverProgress = ProgressScrubMath.progress(fromX: hoverX, width: width)
            let pointerProgress = isDragging ? dragValue : hoverProgress
            let thumbSize = ProgressScrubMath.thumbDiameter(trackHeight: trackHeight)
            let showChrome = (isHovering || isDragging) && width > 0
            let tooltipText = ProgressScrubMath.tooltipTime(
                progress: pointerProgress,
                duration: duration ?? 0
            )

            ZStack(alignment: .leading) {
                // track + fill + preview (clipped)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.3))
                    Capsule()
                        .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, width * CGFloat(ProgressScrubMath.clampProgress(displayed))))
                    if showChrome, hoverProgress > displayed {
                        let start = width * CGFloat(ProgressScrubMath.clampProgress(displayed))
                        let end = width * CGFloat(hoverProgress)
                        Capsule()
                            .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                            .opacity(0.35)
                            .frame(width: max(0, end - start))
                            .offset(x: start)
                    }
                }
                .frame(height: trackHeight)
                .frame(maxHeight: .infinity, alignment: .center)

                if showChrome {
                    ProgressScrubThumb(diameter: thumbSize, intensity: glassIntensity, isHovered: isHovering || isDragging)
                        .position(
                            x: ProgressScrubMath.thumbCenterX(progress: displayed, width: width, thumbDiameter: thumbSize),
                            y: geometry.size.height / 2
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))

                    if let tooltipText {
                        ProgressScrubTooltip(text: tooltipText, intensity: glassIntensity)
                            .position(
                                x: clampedTooltipX(pointerX: isDragging ? width * CGFloat(dragValue) : hoverX, width: width),
                                y: geometry.size.height / 2 - thumbSize / 2 - 16
                            )
                            .transition(.opacity)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(/* existing drag seek logic using ProgressScrubMath.progress */)
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    isHovering = true
                    hoverX = loc.x
                case .ended:
                    isHovering = false
                }
            }
            .animation(.easeOut(duration: 0.15), value: showChrome)
            .transaction { transaction in
                if !isDragging { transaction.animation = nil }
            }
        }
    }

    private func clampedTooltipX(pointerX: CGFloat, width: CGFloat) -> CGFloat {
        let approxHalf: CGFloat = 28
        return min(max(pointerX, approxHalf), max(approxHalf, width - approxHalf))
    }
}
```

Preserve the exact seek end behavior from the current bar (disable animations when writing `value`, call `onSeek`, clear `isDragging`).

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Sapphire -destination 'platform=macOS' build 2>&1 | tail -30`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sapphire/Utilities/Helpers.swift
git commit -m "$(cat <<'EOF'
Add Spotify-style hover scrub chrome to InteractiveProgressBar.

EOF
)"
```

---

### Task 4: Wire call sites

**Files:**
- Modify: `Sapphire/Widgets/MusicPlayer/MusicPlayerViews.swift` (`PlayerProgressView`)
- Modify: `Sapphire/Widgets/MusicPlayer/LyricsViews.swift` (`LyricsDetachedBottomBar`)

**Interfaces:**
- Consumes: extended `InteractiveProgressBar(duration:trackHeight:)`
- Produces: player + lyrics pass `musicManager.totalDuration`

- [ ] **Step 1: Update `PlayerProgressView`**

Pass:

```swift
InteractiveProgressBar(
    value: Binding(
        get: { liveProgress },
        set: { seekProgress = $0 }
    ),
    gradient: Gradient(colors: lightStyle
        ? [.white, .white.opacity(0.75)]
        : [musicManager.leftGradientColor, musicManager.rightGradientColor]),
    onSeek: { /* unchanged */ },
    onDragChanged: { progress in
        isSeeking = true
        seekProgress = progress
    },
    duration: musicManager.totalDuration,
    trackHeight: lightStyle ? 6 : 10
)
.frame(height: lightStyle ? 14 : 30)
```

Keep existing shadow.

- [ ] **Step 2: Update lyrics bar**

```swift
InteractiveProgressBar(
    value: $currentProgress,
    gradient: Gradient(colors: [.white, .white.opacity(0.8)]),
    onSeek: { newProgress in
        let seekTime = newProgress * musicManager.totalDuration
        if seekTime.isFinite && musicManager.totalDuration > 0 {
            Task { await musicManager.seek(to: seekTime) }
        }
    },
    onDragChanged: { progress in
        currentProgress = progress
    },
    duration: musicManager.totalDuration,
    trackHeight: 4
)
.frame(height: 16)
```

Remove the outer `.background(Color.white.opacity(0.2)).clipShape(Capsule())` that would clip the thumb. If a light track wash is still desired, pass it by changing the bar’s track fill color via a new optional `trackColor: Color = Color.secondary.opacity(0.3)` parameter defaulting to today’s look, and for lyrics use `trackColor: Color.white.opacity(0.2)`.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Sapphire -destination 'platform=macOS' build 2>&1 | tail -30`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Manual smoke (if app runnable)**

- Hover player bar → glass thumb + tooltip
- Hover ahead → preview wash
- Drag / click → seek on release, no bounce
- Lyrics bar → smaller chrome, no clipped thumb

- [ ] **Step 5: Commit**

```bash
git add Sapphire/Widgets/MusicPlayer/MusicPlayerViews.swift Sapphire/Widgets/MusicPlayer/LyricsViews.swift Sapphire/Utilities/Helpers.swift
git commit -m "$(cat <<'EOF'
Wire scrubber duration and track height in player and lyrics.

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Hover anywhere → thumb + tooltip | 3 |
| Ahead preview wash | 3 |
| Glass thumb/tooltip structure + fallback | 2 |
| Seek on release / no bounce | 3 (preserve) |
| All `InteractiveProgressBar` call sites | 4 |
| Optional duration hides tooltip | 1 + 3 |
| Thumb inset at ends | 1 + 3 |
| Thin lyrics bar min thumb | 1 + 4 |
| Worktree / feature branch | Setup before Task 1 |

## Execution handoff

User requested plan + implement in one session → **inline execution** on a new worktree (`feature/spotify-style-progress-scrubber`).
