# Sapphire vs Vorssaint — gap map and plan

Compiled 2026-10-07 from a read-only review of both codebases. Vorssaint
(github.com/vorssaint/vorssaint-utils) is **GPL-3.0**: it is a feature and approach
reference only. Nothing from it — code, structure, strings — goes into Sapphire.

Status key: **✓** complete · **◐** partial · **✗** missing · **⚠** present but broken/unsafe.
Effort: S (≤1 day) · M (days) · L (week+).

## Phase 1 — safety & correctness bugs in features Sapphire already ships

| # | Bug | Where | Effort |
|---|---|---|---|
| 1 | Fan control: helper never restores automatic mode on app quit/crash/XPC disconnect, no heartbeat lease, dedup cache never cleared on wake → fans can stay forced indefinitely. RPM shown is stale. | `com.shariq.sapphireHelper/XPCServer.swift:26-31`, `Helper.swift:216-221,1053-1125`, `Services/Battery/FanManager.swift` | S–M |
| 2 | Keep Awake: spawns `caffeinate` without `-w <pid>` (survives a crash), respawns with no backoff, and its dev-task auto-start runs even with Keep Awake turned off. | `Services/System/CaffeinateManager.swift:73-157,252,511-525`, `BatteryManager.swift:90` | S |
| 3 | Quit protection "extra modifier" mode passes ⌃⌘Q (Lock Screen) / ⇧⌘Q (Log Out) straight through; `extraModifier` never used. | `SystemEnhanceQuitProtection.swift:226-238,318` | S |
| 4 | Mouse Control swallows middle click (and buttons 4/5 set to None). | `Services/Mouse/MouseControlManager.swift:241-243,282-284` | S |
| 5 | Super key likely sticks with default right-⌘ hyper (generic ⌘ flag vs synthetic left ⌘). | `Services/Mouse/SuperKeyManager.swift:220-229` | S |
| 6 | Side-button key-up race (down posted async, up can arrive first). | `MouseControlManager.swift:315-321` | S |
| 7 | AutoQuit can terminate apps whose windows are on another Space (no Screen Recording → looks windowless). | `SystemEnhanceAutoQuit.swift:84-136`, `SystemEnhanceWindowRegistry.swift:695` | M |
| 8 | Finder ⌘X/⌘V never moves files; ⌘X swallowed in Finder text fields; pasteboard + LaunchServices on the tap thread; F2 posts Return. | `Services/Clipboard/FinderCutPasteManager.swift:134,152-203,171-179,260,278` | M |
| 9 | Dock Clicks swallows mouse-down (active icon can't be dragged), tile cache stale after Dock changes → wrong app. | `SystemEnhanceDockClicks.swift:242`, `SystemEnhanceSupport.swift:441-540` | M |
| 10 | Display software dimming is a no-op; no fallback when DDC fails; DDC writes sleep on the main thread every key repeat; rebuild storms on screen changes. | `System/Display/Model/OtherDisplay.swift:16,77-80,122`, `Support/Arm64DDC.swift:106-118`, `SystemHUD.swift:200-204,579` | M |
| 11 | DMG installer: synchronous unmount waits block main (up to 24 s); manual copy turns framework symlinks into folders → broken signatures. | `Services/DMGInstaller/DMGInstallerManager.swift:226-265,394-425` | S–M |
| 12 | Media/file conversion: video conversion always fails (`AVFileType(ext)`), filename mangled at last `_`, silent overwrite, main-thread image work, progress never ends on failure; optimizer drops EXIF orientation + colour profile; PDF pages cropped to Letter; clipboard auto-optimize drops other pasteboard types. | `Services/Dropbox/FileConversionManager.swift:72-203`, `Services/MediaOptimizer/MediaOptimizer.swift:99-182,408`, `MediaOptimizerManager.swift:116-153` | S–M |
| 13 | Stats: CPU tick subtraction traps on wrap (long uptime crash); EnergyReader parses the wrong `top` sample every 5 s; reads every SMC key every 3 s; IOKit leaks; RAM "used" overstated. | `Services/Stats/Stats.swift:651-686,762,886-943,1042-1114`, `Services/Battery/EnergyReader.swift` | S–M |
| 14 | Mixer: `retiredEQSetups` grows forever while dragging EQ; all HAL work on main; possible teardown use-after-free; CoreAudio from a signal handler. | `Services/Audio/MultiAudioManager.swift:577-871,1018-1183,1580-1613` | M |
| 15 | Clipboard: all capture/transcode on main, history unlimited by default, uncached full-text search per keystroke; auto-clear "on lock" never fires on a real lock; shelf leaks temp copies and never expires; notes not autosaved; Downloads scan on main. | `ClipboardManager.swift:421,477-578`, `SettingsModel.swift:1284-1286`, `ClipboardAutoClearManager.swift:68-74`, `FileShelfManager.swift:37,67-110,137-150`, `NotesWidgetView.swift:292-306`, `FileProgressTracker.swift:278-336` | M |
| 16 | App updates: full network scan on every launch (ignores saved `lastCheckedAt`), re-announces the same updates each launch, Homebrew run without env (slow `brew update`, sudo casks hang 30 min). | `App Settings/InstalledAppUpdates.swift:1093-1097,1438,2120-2161,2678` | S–M |
| 17 | Misc: OCR overlay uses `NSScreen.main`/main-display bounds (wrong pixels on 2nd display) and no Screen Recording preflight; mirror can't cancel a pending start; XDR support from a hard-coded model list and resets every display's gamma; pointer-acceleration toggle is a no-op and also touches trackpads; scroll inversion applies to trackpads and re-posts every event. | `OCRScreenshotMonitor.swift:148,206,218-237`, `MirrorCameraManager.swift:112-181`, `XDRUtil.swift:55-59`, `XDRGamma.swift:206`, `MouseControlManager.swift:142,172-217,399-418` | M |

## Phase 1b — deep-pass findings (2026-10-07, second review)

### Infrastructure
| # | Issue | Where | Effort |
|---|---|---|---|
| I1 | `$settings` sinks fire before the value is stored (`current` set in didSet) → NearDrop/Launchpad toggles do nothing until relaunch, Launchpad item stays after disabling, Mouse Control arms backwards, Continuity sends previous Focus settings, file-progress/app-activity read stale lists. Publish after store; migrate raw sinks to `changes(of:)`; regression test. | `Models/SettingsModel.swift:2606-2616`, `AppDelegate.swift:433-472,874,1386,1418`, `ContinuityFocusModeManager.swift:117-125`, `AppActivityMonitor.swift:80-101` | S–M |
| I2 | Window registry runs whenever Accessibility is granted even with all consumers off (main idle CPU source). Ref-count acquire/release. | `AppDelegate.swift:755`, `SystemEnhanceWindowRegistry.swift:50-65` | S |
| I3 | Settings blob 135 KB / 682 fields, re-encoded on every change and every launch; ~60 KB is repeated ICC data in every CodableColor; dock presets 42 KB inline. Encode colours as components, split presets out, skip launch persist. | `ShortcutModels.swift:60-73`, `SettingsModel.swift:2707-2722,2839-2898` | M |
| I4 | Tolerant decode silently drops newer settings and overwrites the payload (downgrade/channel switch). Backup raw payload, schemaVersion guard. | `SettingsModel.swift:2192-2231,2709-2714` | S |
| I5 | Launch: Firebase configure sync on main; notification prompt + login item + privileged helper registered before onboarding; Bluetooth paired-devices on main; `NSUpdateDynamicServices` every launch; keychain reads on main. | `AppDelegate.swift:346,360,447-455,751,803,886`, `FirebaseBootstrap.swift:23-82`, `HelperManager.swift:394-418`, `APIKeyManager.swift:35-60` | S–M |
| I6 | Crash safety: forced Low Power Mode / lid auto-mute / non-lease fan path not journaled; no startup-crash marker; no `applicationShouldHandleReopen` (hidden icon = unreachable app). | `LidAngleAutomationManager.swift:148-196`, `FanManager.swift:640-645`, `AppDelegate` | S each |
| I7 | GlobalEventTap: `tapCreate` while holding the dispatch lock → events skip handlers during register/rebuild; `.replace` returns an unretained new event. | `System/GlobalEventTap.swift:161-262` | S |
| I8 | URLSession leaks (11/13 never invalidated; per-redirect session+delegate in Circle to Search); LyricsDatabase unbounded. | `UpdateChecker.swift:550`, `CircleToSearchLookup.swift:238`, `LyricsDatabase.swift:14` | S |
| I9 | One false AXIsProcessTrusted read after any app's a11y broadcast terminates Sapphire; PermissionsManager republishes everything on activation; Local Network "granted" is not real. | `System/Accessibility.swift:125-172`, `App/PermissionsManager.swift:127-474` | S |
| I10 | Menu bar: `isAgentHosted` evaluated once (agent started later → divider hides nothing all session); full Settings copy per update. Two Sapphire instances overwrite each other's settings. | `StatusBarController.swift:399,533`, `SapphireInstanceCoordination` | S |

### Notch / live activities
| # | Issue | Where | Effort |
|---|---|---|---|
| N1 | Root hosting view autoresizes with the window → every `setFrame` relayouts both SwiftUI trees (20–50 ms on open/close/hover). Fixed-size stage, move origin only; don't go full-window on plain hover. | `AppDelegate.swift:1577-1580`, `NotchHostWindowSizer`, `NotchController.swift:349,2661-2672` | S–M |
| N2 | Widget plane is re-parented each open → SwiftUI discards its graph → full widget rebuild every open. Keep the plane host a permanent sibling, show/hide via layer, explicit "presented" environment flag for timers. | `NotchWidgetPlane.swift:295-305` | M |
| N3 | `@EnvironmentObject ActiveAppMonitor` back in NotchController (regression of app-switch fix); body reads `activityContent`/`activityHasBottomContent` directly → full re-render per lyric line on every display. | `NotchController.swift:65,298-347,527-542,606` | S |
| N4 | Multi-display: TrackpadGestureHandler callbacks last-writer-wins (swipe hides wrong notch), MenuBarInteractionManager suspend per controller, focusable window = `notchWindows.first`, music-queue/circle-to-search notifications open every display. | `NotchController.swift:625-660,667,1035-1236`, `AppDelegate.swift:1643-1670` | S–M |
| N5 | Ungated `asyncAfter` blur/scale resets fire after state changed; sizer falls back to `NSScreen.main`; `.full` content equality ignores view → updates dropped; `showLyricsBinding` dead; timer/dev-activity numericText → LayerNumericText. | `NotchController.swift:1480-1522`, `NotchHostWindowSizer.swift:63,90`, `AppModels.swift:217`, `LiveActivityComponents.swift:584,1388` | S |
| N6 | Glass: keep one persistent surface, avoid per-frame `_setPath:` (fade glass at ends or fixed path + mask) — needs Shariq's sign-off on look; CA morph (clip-reveal) also needs sign-off. | `NotchSurfaceBackground.swift`, `LiquidGlassView.swift` | M / L |

### Media & services
| # | Issue | Where | Effort |
|---|---|---|---|
| M1 | Now-playing stream: each death restarts twice (self-restart + `onListenerTerminated`), leaking an untracked perl process; no launch token, no restart budget; shared buffer interleaves. Commands spawn a perl per action; stream never paused on sleep/lock. | `NativeMediaController.swift:206-319`, `MusicManager.swift:1736-1739,2147` | M |
| M2 | Artwork decoded full-size on main; "same artwork" check = length + 3 bytes. | `NativeMediaController.swift:443-472` | S–M |
| M3 | Bluetooth battery: shared continuation → second refresh orphans the first (continuation leak); system_profiler parser always returns [] but still runs 1–3 s; per-connect chain incl. 12 s GATT; mouse connect posts fake AirPods "connected". | `BluetoothBatteryReader.swift:38-311`, `BluetoothManager.swift:211-257`, `MagicBattery.swift:258-263` | M |
| M4 | Calendar: 48 h snapshot never refreshed on day/clock/tz/wake; milestones keyed by eventIdentifier → recurring occurrences never notify; 7+ EKEventStores. | `CalendarService.swift:148-173`, `LiveActivityManager.swift:1858-2000` | S–M |
| M5 | Lyrics: no duration in LRCLIB request, failures block retries forever, translations uncached, trimLyricsCache inverted. | `MusicUtilities.swift:385-412`, `MusicManager.swift:2682-2693,2878-2887,3086-3121` | S |
| M6 | Timers ring late after sleep (Timer clock pauses); permanent `log stream` child with 1 s respawn, no orphan protection. | `TimerManager.swift:134-139,379-674` | S–M |
| M7 | Notification DB query/plist decode/icon lookup on main; simultaneous notifications overwrite each other. | `NotificationManager.swift:237-334` | S |
| M8 | Dev activity: Claude project slug only maps `/ . _` → paths with spaces never match. | `DevAgentSessionActivity.swift:55-62` | S |
| M9 | ProcessRunner reads with two readers on one fd; SystemLogParser drops partial lines/UTF-8; Spotify ping timer leak; BatteryDataLogger file grows forever, decoded on main; weather no wake refresh; LyricsAudioTap leak on format failure; setenv off-main. | `ProcessRunner.swift:67-70`, `SystemLogParser.swift:41-48`, `SpotifyNetwork.swift:614-626`, `BatteryLogEntry.swift:162-190`, `WeatherViewModel.swift:192-205`, `LyricsAudioTap.swift:41`, `LogReader.swift:62-69` | S each |

(Items already sent to Wave 1 owners: I1 for MouseControlManager, Chrome-History copy + coalescing + I1 for FileProgressTracker.)

## Phase 2 — performance/architecture that the bugs point to

- **Feature runtime:** ~30 managers start unconditionally in `AppDelegate.swift:760-800`; gate each behind its setting with lazy creation (precursor to "install only what you use" + presets + per-feature permissions).
- **App switcher** onto the shared `GlobalEventTap`, no SwiftUI layout in the tap callback, temporary takeover of the system ⌘Tab hotkey, MRU order, search, Space/display filters, icon mode.
- **One HID-level wheel transform** on the pointer thread (in-place edits, mouse-only, exclusions by app under pointer) → inversion, linear, sideways-modifier and smooth scrolling from one path; per-device acceleration with restore.
- **Clipboard lane:** one serialized off-main pasteboard access path shared by history, auto-clear, Clean URL, plain paste, snippets.
- **Stats sampling policy:** run only while a consumer is visible, per-metric strides, ring buffers for history.
- `AXEnhancedUserInterface` suspension around all AX frame writes (snapping, maximize).

## Phase 3 — features Sapphire is missing or thin on

| Area | Missing (✗) / thin (◐) | Effort |
|---|---|---|
| Capture | ✗ unified capture overlay (screenshot/OCR/colour/QR with loupe, per-display), ✗ screenshot quick-preview/pin/annotate/redact/backdrop/scrolling, ✗ screen recorder (SCStream + AVAssetWriter, separate system/mic tracks, trim, GIF), ✗ colour picker, ✗ QR reading | M–L each |
| Sound | ◐ boost >100% with lookahead limiter + ramps, ✗ per-app output routing, ✗ pin/reorder, ✗ output switcher hotkey + headphone-disconnect volume drop, ◐ preferred input + mic-mute hotkey, ✗ Music launch blocker, ◐ real live EQ bars from a player tap | S–M each |
| Monitoring | ◐ monitor panel with history graphs, E/P cores, per-process energy via `proc_pid_rusage`, ✗ network section (64-bit counters, totals, IP, speed test), ◐ richer menu bar readouts, ◐ temperature/low-battery alerts with an uptime-clock gate | M–L |
| Windows | ◐ snapping presets (halves/thirds/quarters, gaps, cycling), ✗ move to next display, ✗ restore, ✗ edge snap + modifier-drag, ◐ Dock preview move/snap/autohide-hold, ✗ fixed Space order | S–L |
| Input | ✗ smooth/linear/sideways scrolling, ✗ three-finger middle click, ◐ Caps Lock super key (crash-safe remap), ◐ snippet library + suffix matching, ◐ per-feature exceptions, ◐ shortcut conflict detection | S–M |
| Clipboard & files | ◐ pins + ⌘1–9 + preview + ignored apps, ◐ manual Clean URL + more params, ◐ cursor shelf (no global pointer monitor — drive from drag-pasteboard changes) | M |
| Tools | ✗ command bar (apps/windows/files/clipboard/snippets/menus/calc/units/emoji), ✗ quick panel, ✗ quick toggles, ✗ radial menu, ◐ scratchpad (tabs, markdown, autosave), ✗ cleaning mode (with guaranteed escape), ◐ AI agents usage (limits/resets/tokens/finished notice, OpenCode/Copilot) | S–L |
| App management | ◐ batch updates + skip version, ✗ Homebrew manager, ◐ cleaner leftovers/launch agents/logs + schedule, ◐ uninstaller elevation + receipts + Homebrew, ✗ port manager, ✗ messaging-downloads retention | S–L |
| Energy & display | ◐ keep-awake triggers (apps/power/display), ◐ per-display brightness page + ½/¼ steps + extra dimming, ✗ Bluetooth off during sleep | S–M |
| Platform | ✗ modular features + presets, ◐ settings export with versioned key allowlist, ◐ per-feature permissions onboarding, ✗ localization | M–L |

Where Sapphire is already ahead (keep): single shared `GlobalEventTap`, per-app EQ/8D/surround, broader app-update source detection, signed auto-update with team-ID check, Continuity, notch/live activities, lyrics.
