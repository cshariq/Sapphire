# Release Source Retarget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Point in-app update checks and related GitHub links at `Idan-sh/SapphireNotch` via a single `ReleaseSource`, and clear stale upstream “update available” state so the app stays quiet until this repo publishes releases.

**Architecture:** Add a small `ReleaseSource` enum with owner/repo and URL helpers. `UpdateChecker` and About/onboarding links consume it. One-time clear of `SapphirePersistedAvailableUpdate` removes leftover upstream offers. Empty releases continue to map to `upToDate`.

**Tech Stack:** Swift / SwiftUI / AppKit, GitHub Releases REST API (existing), Xcode synchronized `Sapphire/` group (new files under `Sapphire/` are picked up automatically).

## Global Constraints

- Release owner/repo must be exactly `Idan-sh` / `SapphireNotch`
- Do not hard-disable background checks or remove update UI
- Do not change download/install/`install_update.sh` behavior
- Do not retarget README/CONTRIBUTING in this plan
- No in-app update path may hardcode `cshariq/Sapphire`

---

## File Structure

| File | Role |
|------|------|
| `Sapphire/Models/ReleaseSource.swift` | Single source of truth for repo identity + URLs |
| `Sapphire/App Settings/UpdateChecker.swift` | Use `ReleaseSource`; clear stale persisted update |
| `Sapphire/App Settings/SettingsPanes.swift` | About GitHub link → `ReleaseSource.repositoryURL` |
| `Sapphire/App/OnboardingView.swift` | Repo + releases links → `ReleaseSource` |

---

### Task 1: Add `ReleaseSource`

**Files:**
- Create: `Sapphire/Models/ReleaseSource.swift`

**Interfaces:**
- Produces: `enum ReleaseSource` with `owner`, `repo`, `releasesAPIURL`, `releasesPageURL`, `repositoryURL`

- [x] **Step 1: Create `ReleaseSource.swift`**

```swift
//
//  ReleaseSource.swift
//  Sapphire
//

import Foundation

enum ReleaseSource {
    static let owner = "Idan-sh"
    static let repo = "SapphireNotch"

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)")!
    }

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases")!
    }

    static var releasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=30")!
    }
}
```

- [x] **Step 2: Confirm file is under synchronized `Sapphire/` group**

No `project.pbxproj` edit required (PBXFileSystemSynchronizedRootGroup).

- [x] **Step 3: Commit** (skipped — user did not ask for commits)

---

### Task 2: Retarget `UpdateChecker` + clear stale persist

**Files:**
- Modify: `Sapphire/App Settings/UpdateChecker.swift`

**Interfaces:**
- Consumes: `ReleaseSource.releasesAPIURL`, `ReleaseSource.releasesPageURL`
- Produces: unchanged public `UpdateChecker` API

- [x] **Step 1: In `init()`, clear persisted available update once for the retarget**

After `super.init()`, before `restorePersistedAvailableUpdateIfNeeded()`, clear the old key so upstream leftovers cannot restore:

```swift
private override init() {
    super.init()
    // One-time: drop any persisted offer from the former upstream release feed.
    clearPersistedAvailableUpdate()
    restorePersistedAvailableUpdateIfNeeded()
}
```

Note: With the clear before restore, restore is a no-op until a future session persists a new offer from this repo. That matches soft-quiet with no releases. Prefer keeping `restorePersistedAvailableUpdateIfNeeded()` for future releases after the user has seen an offer in a later session—so only clear once using a migration flag:

```swift
private let releaseSourceMigrationKey = "SapphireReleaseSource.IdanSh.SapphireNotch.v1"

private override init() {
    super.init()
    if !UserDefaults.standard.bool(forKey: releaseSourceMigrationKey) {
        clearPersistedAvailableUpdate()
        UserDefaults.standard.set(true, forKey: releaseSourceMigrationKey)
    }
    restorePersistedAvailableUpdateIfNeeded()
}
```

Use the migration-flag variant (above).

- [x] **Step 2: Replace API URLs in `checkForUpdates()` and `checkForBetaUpdates()`**

Replace:

```swift
guard let url = URL(string: "https://api.github.com/repos/cshariq/Sapphire/releases?per_page=30") else {
```

with:

```swift
let url = ReleaseSource.releasesAPIURL
```

Remove the `guard let url = URL(...)` failure path for invalid URL (URL is non-optional from `ReleaseSource`). Keep the rest of each method identical. For `checkForUpdates`, change the opening of the network section to:

```swift
applyStatus(.checking)
let url = ReleaseSource.releasesAPIURL
```

Same for `checkForBetaUpdates`.

- [x] **Step 3: Replace fallback notes URL in `applyReleaseNotes`**

Replace:

```swift
releaseNotesURL = URL(string: "https://github.com/cshariq/Sapphire/releases")
```

with:

```swift
releaseNotesURL = ReleaseSource.releasesPageURL
```

- [x] **Step 4: Grep for leftover upstream update URLs in this file**

Run: `rg 'cshariq/Sapphire' "Sapphire/App Settings/UpdateChecker.swift"`  
Expected: no matches

---

### Task 3: Retarget Settings About + Onboarding links

**Files:**
- Modify: `Sapphire/App Settings/SettingsPanes.swift` (About GitHub `Link`)
- Modify: `Sapphire/App/OnboardingView.swift` (repo `Link` + updates “Download from GitHub” `Link`)

**Interfaces:**
- Consumes: `ReleaseSource.repositoryURL`, `ReleaseSource.releasesPageURL`

- [x] **Step 1: Settings About link**

Replace:

```swift
Link(destination: URL(string: "https://github.com/cshariq/Sapphire")!) {
```

with:

```swift
Link(destination: ReleaseSource.repositoryURL) {
```

- [x] **Step 2: Onboarding repo link**

Replace:

```swift
Link(destination: URL(string: "https://github.com/cshariq/Sapphire")!) {
```

with:

```swift
Link(destination: ReleaseSource.repositoryURL) {
```

- [x] **Step 3: Onboarding download link**

Replace the `.available` case link destination:

```swift
Link(destination: ReleaseSource.releasesPageURL) { Text("Download from GitHub") }
```

- [x] **Step 4: Verify no in-app update hardcodes remain**

Run:

```bash
rg 'cshariq/Sapphire' Sapphire --glob '*.swift'
```

Expected: no matches under `Sapphire/**/*.swift` (README/CONTRIBUTING may still mention upstream; that is out of scope).

---

### Task 4: Manual verification

**Files:** none

- [x] **Step 1: Build** (if Xcode available)

```bash
xcodebuild -scheme Sapphire -configuration Debug build 2>&1 | tail -30
```

Expected: **BUILD SUCCEEDED** (confirmed).

- [ ] **Step 2: Runtime checks** (user: relaunch to confirm no notch nag)
---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| `ReleaseSource` with Idan-sh/SapphireNotch | Task 1 |
| UpdateChecker uses ReleaseSource | Task 2 |
| Clear stale persisted upstream offer | Task 2 (migration flag) |
| About / onboarding links | Task 3 |
| Soft quiet / empty releases | Existing behavior; verified Task 4 |
| Leave install/channel/notch wiring | No task changes those |
| README/CONTRIBUTING out of scope | Not touched |
