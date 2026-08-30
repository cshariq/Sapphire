# Release Source Retarget Design

**Date:** 2026-08-30  
**Status:** Approved for implementation planning  
**Repo:** https://github.com/Idan-sh/SapphireNotch

## Problem

The in-app “Update Available” feature still talks to the upstream author’s GitHub releases (`cshariq/Sapphire`). That can:

- Show false update prompts against upstream version numbers
- Offer download/install of packages that are not this fork (risk of replacing a `com.idansh.sapphire` build with upstream)

This fork has **no GitHub Releases yet** (personal build). Soft-quiet behavior is required: keep update infrastructure, do not nag until a real release exists on this repo.

## Goals

1. Point all **in-app** update/feed and related GitHub links at `Idan-sh/SapphireNotch`.
2. Centralize that source in one place (`ReleaseSource`) so future renames are a single edit.
3. Preserve existing check / download / install / notch UX for when releases are published later.
4. Soft quiet: empty releases list → treat as up to date (no notch banner).
5. Clear any persisted “available update” leftover from the old upstream so prompts stop immediately after this change.

## Non-goals

- Publishing the first GitHub Release or CI release workflow
- Sparkle, Mac App Store, or other updaters
- Hard-disabling background checks or removing update Settings UI
- Retargeting README / CONTRIBUTING docs (out of scope for the running app)
- Soft-quiet for missing `.zip` on a newer tag or network errors (keep current Settings error behavior)

## Decision

**Approach:** Single `ReleaseSource` constant + retarget callers (soft quiet via empty releases).

Rejected alternatives:

- Minimal string swap only — works but scatters the repo identity
- Hard-off / strip UX until opt-in — unnecessary given empty releases already yield `upToDate`
- Soft-quiet for all non-success paths — deferred; not needed while there are no releases

## Architecture

```
ReleaseSource (owner, repo, URL helpers)
        │
        ├── UpdateChecker (API + fallback release notes URL)
        ├── About / Settings GitHub link
        └── Onboarding GitHub / “Download from GitHub” links

UpdateChecker status
        │
        ├── .upToDate  → no notch activity
        ├── .available → sapphireUpdateAvailable → Update Available live activity
        └── .error / checking / downloading / … → Settings UI only (existing)
```

## Components

### `ReleaseSource`

New small type (enum or struct with static members), placed near update settings or Models:

| Member | Value / behavior |
|--------|------------------|
| `owner` | `Idan-sh` |
| `repo` | `SapphireNotch` |
| `releasesAPIURL` | `https://api.github.com/repos/Idan-sh/SapphireNotch/releases?per_page=30` |
| `releasesPageURL` | `https://github.com/Idan-sh/SapphireNotch/releases` |
| `repositoryURL` | `https://github.com/Idan-sh/SapphireNotch` |

No runtime settings UI for changing the source in this iteration.

### `UpdateChecker`

- Replace hardcoded `cshariq/Sapphire` API and fallback notes URLs with `ReleaseSource`.
- Stable / beta channel logic, version ordering, download, `install_update.sh` install path: **unchanged**.
- **Stale persistence:** On init (or first apply after retarget), ensure a persisted `SapphirePersistedAvailableUpdate` from upstream cannot keep status `.available` when this repo has nothing newer. Prefer an explicit one-time clear of the persisted key as part of this change (simplest, correct for “no releases yet”), in addition to existing “still relevant vs current version” checks.

### UI call sites (in scope)

- `Sapphire/App Settings/UpdateChecker.swift` — API + fallback notes URL
- `Sapphire/App Settings/SettingsPanes.swift` — About GitHub link (~line with `cshariq/Sapphire`)
- `Sapphire/App/OnboardingView.swift` — repo link + “Download from GitHub” releases link

### Leave unchanged

- Notch `UpdateAvailable*` views and `LiveActivityManager` wiring
- Periodic checks in `AppDelegate` (`startPeriodicChecks`)
- `ReleaseChannelPolicy` / beta entitlement gating
- `install_update.sh`
- README / CONTRIBUTING upstream links

## Data flow

1. Launch → restore persisted available update only if still relevant; after this change, old upstream persist should be cleared so restore does not resurrect a false offer.
2. Background / About / channel change → `checkForUpdatesMatchingCurrentChannel()` → GitHub API via `ReleaseSource.releasesAPIURL`.
3. Empty stable (or beta) candidate set → `upToDate`.
4. Newer marketing version with `.zip` asset → `.available` → notification → notch + Settings download/install.
5. Same or older → `upToDate`.

## Error handling

| Situation | Behavior |
|-----------|----------|
| No releases | `upToDate` (soft quiet) |
| Newer tag, no `.zip` | Existing Settings `.error` (“No zip download…”) |
| Network / parse failure | Existing Settings `.error` |
| Persisted upstream offer | Cleared by migration/clear in this change |

## Testing (manual)

1. Cold launch with no releases on `Idan-sh/SapphireNotch` → no “Update Available” notch activity; About shows up to date (or checking then up to date).
2. About / onboarding GitHub links open `Idan-sh/SapphireNotch` (not `cshariq/Sapphire`).
3. If a prior build had shown an upstream update, after this build the prompt is gone without reinstalling OS state beyond normal app UserDefaults.
4. (Future) Publish a prerelease/release with higher `CFBundleShortVersionString` and a `.zip` asset → prompt, download, and install path still work.

## Success criteria

- No in-app update code path or update-related UI link still hardcodes `cshariq/Sapphire`.
- With zero releases on the fork, the user is not nagged by “Update Available”.
- Publishing a proper release later requires no redesign—only a GitHub Release with a versioned `.zip`.
