# Spotify-Style Progress Scrubber Design

**Date:** 2026-08-30  
**Status:** Approved for implementation planning  
**Repo:** SapphireNotch  
**Primary surface:** `InteractiveProgressBar` (`Sapphire/Utilities/Helpers.swift`)

## Problem

The music progress bar is a thumbless capsule. Users can tap/drag anywhere to seek, but there is no visible handle on the current progress edge, no hover time preview, and no Spotify-style “scrub ahead” wash. Scrubbing is harder to discover and less precise than expected.

## Goals

1. On hover anywhere over the progress bar, show a **glass bead thumb** on the **current** progress edge and a **floating time tooltip** above the pointer.
2. When the pointer is **ahead** of current progress, show a **lighter preview wash** from the current tip to the hover position.
3. Keep drag/click seek behavior: live UI while dragging, commit `onSeek` on release (no continuous Media Remote seeks while dragging).
4. Ship the behavior in shared `InteractiveProgressBar` so **all call sites** (expanded player, lyrics bar, future uses) get it.
5. Style thumb and tooltip with the app’s **Liquid Glass** component structure (`LiquidGlassShapeFill` + existing VisualEffect fallback), not a one-off painted disc.

## Non-goals

- Continuous seek-to-player while dragging
- Replacing the side elapsed / remaining time labels
- Full `NSGlassEffectView` redesign of the track fill itself
- Changing Media Remote optimistic-seek hold logic beyond what the existing scrub path already does
- Separate scrubber API / wrapper control

## Decision

**Approach:** Enrich `InteractiveProgressBar` with hover chrome (thumb, tooltip, preview wash) and an optional `duration` for tooltip formatting.

Rejected alternatives:

- New wrapper around the existing bar — safer rollback, but two APIs and awkward hit-testing
- Split track vs chrome components — cleaner long-term, unnecessary refactor for this feature

## Architecture

```
InteractiveProgressBar
  ├── Track (capsule): background + gradient fill (existing)
  ├── Preview wash (hover ahead only): lighter fill tip → hoverX
  ├── Thumb: LiquidGlassShapeFill(Circle) | VisualEffect fallback
  ├── Tooltip: LiquidGlassShapeFill(Capsule) | VisualEffect fallback + m:ss
  └── Gestures: hover location + DragGesture(minimumDistance: 0)

Call sites
  ├── PlayerProgressView  → pass duration + existing onSeek / onDragChanged
  └── LyricsDetachedBottomBar → pass duration; thinner visual height
```

## Components

### `InteractiveProgressBar` (extended)

**Existing**

- `@Binding var value: Double`
- `gradient: Gradient`
- `onSeek: (Double) -> Void`
- `onDragChanged: ((Double) -> Void)?`

**Add**

- `duration: TimeInterval? = nil` — if nil or ≤ 0, hide tooltip only; thumb/preview still work
- `trackHeight: CGFloat = 10` — so lyrics (height 4) and player stay consistent via one parameter (call sites that currently frame the bar externally should pass the visual track height they intend)
- Optional `glassIntensity: Double = 0.65` for thumb/tooltip Liquid Glass params (aligned with app defaults)

**Internal state**

- `isDragging` / `dragValue` (existing)
- `isHovering`
- `hoverProgress` (0…1 from pointer X / width)

**Displayed progress**

- Dragging → `dragValue`
- Else → `value`
- Thumb X follows displayed progress (inset so the bead stays inside the capsule at 0% / 100%)

### Thumb (`ProgressScrubThumb` or private subview)

- Visible when `isHovering || isDragging`
- Size: ~1.4–1.8× `trackHeight`, clamped to a minimum usable size (~10–12pt) for thin bars
- **Glass path** (macOS 26+ and system glass available): `LiquidGlassShapeFill(shape: Circle(), intensity:, blendingMode: .withinWindow, appearance: .dark, interaction: isHovering ? .hovered : .normal)`
- **Fallback:** `VisualEffectView` clipped to `Circle()` + light top→bottom white stroke (same language as lock-screen non-glass path)
- Appear/dismiss: short opacity + scale (~0.15s); no bounce on live progress ticks

### Tooltip (`ProgressScrubTooltip` or private subview)

- Visible when hovering or dragging **and** `duration > 0`
- Time = `hoverProgress * duration` (while dragging, use drag position for the tooltip so it matches the pointer/scrub target — same as Spotify)
- Format: `m:ss`, monospaced digit style consistent with player times
- Position: above pointer X; clamp horizontally within bar bounds
- Glass: capsule `LiquidGlassShapeFill` (prefer `.tooltip` material if it reads well at small size; otherwise intensity-resolved material like other controls). Same VisualEffect + stroke fallback as thumb

### Preview wash

- When `hoverProgress > displayedProgress` (and hovering, not necessarily dragging): lighter tint of the accent/gradient from displayed tip → hover X, lower opacity than the real fill
- When hover is behind current progress: no wash
- Pure SwiftUI fill overlays — not Liquid Glass

## Data flow

1. Pointer enters bar → `isHovering = true`; update `hoverProgress` from X.
2. Render thumb at displayed progress; tooltip at hover time above pointer; optional preview wash.
3. Drag starts → freeze via existing `onDragChanged` / player seek lock; fill + thumb follow `dragValue`.
4. Drag/click ends → `onSeek(final)`; write binding with animations disabled (existing anti-bounce).
5. Pointer exits (and not dragging) → dismiss chrome promptly.

## Visual / Liquid Glass rules

- Reuse `LiquidGlassShapeFill` / `LiquidGlassView` + `LiquidGlassIntensityParams` — same structure as notch / lock screen / menu bar glass surfaces.
- Thumb and tooltip use **within-window** blending (controls live inside the notch HUD, not as desktop behind-window chrome).
- Track and preview wash remain opaque/gradient fills (current design language).
- Cursor while hovering/dragging: horizontal resize or pointing hand.

## Edge cases

| Case | Behavior |
|------|----------|
| `duration` nil or ≤ 0 | Hide tooltip; thumb + preview OK |
| Bar width ≤ 0 | No hover math; no chrome |
| Progress 0% / 100% | Inset thumb so it is not clipped |
| Tooltip near ends | Shift X to stay within bar bounds |
| Glass unavailable / pre-macOS 26 | VisualEffect + stroke fallback |
| Lyrics thin track | Scale thumb with height; min size clamp |
| Hover while playing | Live `value` keeps updating until drag; chrome follows |
| Rapid mouse leave | Dismiss chrome; cancel appear animation |

## Testing

**Manual**

- Player bar: hover → thumb + tooltip; hover ahead → wash; drag/click seek commits cleanly without bounce
- Lyrics bar: same chrome at smaller scale, still grabable
- Liquid Glass on and fallback path both usable
- Side times still correct while scrubbing; optimistic seek hold still prevents jump-back

**Automated (light)**

- Pure helpers for clamp + `progress × duration → m:ss` if easy to place next to existing utilities; no snapshot requirement

## Implementation notes

- Prefer keeping chrome in `Helpers.swift` or a small adjacent file if `InteractiveProgressBar` grows too large — same module, no new public API surface beyond the added parameters.
- Wire `duration` from `PlayerProgressView` and lyrics bottom bar from existing music duration sources.
- Implementation work should land on a **feature branch in a new git worktree** (requested), after the implementation plan is written.

## Open questions

None — resolved in brainstorming:

- Scope: all `InteractiveProgressBar` call sites
- Hover model: Spotify-like (bar hover → thumb + tooltip + ahead wash)
- Tooltip: floating above pointer
- Thumb chrome: real Liquid Glass structure + fallback
- Approach: enrich shared control
