# Localization

Sapphire uses Apple's String Catalogs. The source language is English; Simplified Chinese is `zh-Hans`. macOS selects the application language using the system language order or the per-app language preference. Quit and reopen Sapphire after changing that preference. No application-specific language setting is required.

## Resource ownership

| Bundle | Catalog | Purpose |
| --- | --- | --- |
| Sapphire | `Sapphire/Localizable.xcstrings` | App UI, menus, app-owned status messages and errors |
| Sapphire | `Sapphire/App/InfoPlist.xcstrings` | macOS permission-purpose descriptions |
| SapphireAndroidWidgets | `SapphireAndroidWidgets/Localizable.xcstrings` | Widget configuration, discovery and empty states |

The main app uses a filesystem-synchronized Xcode group. The Widget target has explicit resource membership in `project.pbxproj`. A resource in the app does not automatically become a resource in its extension. NearbyShare is a linked library in this public build; its app UI reads the main bundle's table.

One integrator edits each catalog while module contributors supply reviewed keys and translations. Run Xcode extraction after changes to find new strings and preserve translator comments. A compiler-extracted key is an inventory entry, not proof that a screen has been tested.

## Writing UI text

- Use `LocalizedStringKey` for reusable SwiftUI components accepting fixed labels. Keep string literals at the call site so Xcode can extract them.
- Use `String(localized:)` for app-owned strings that must cross a `String` API, such as AppKit menus, alerts and model display properties.
- Pass user content, file names, device names, song titles, lyrics and third-party responses as `String`/`Text(verbatim:)`. Do not convert arbitrary runtime strings into localization keys.
- Keep IDs, enum raw values, Codable values, defaults keys, URLs, protocol values, paths, commands and diagnostic codes unchanged. Add a display property when a stored identifier is shown to a user.
- Use a distinct key when the same English word has different meanings. For example, the onboarding next-step button differs from music playback. English values belong in the catalog; use an explicit English `defaultValue` with `String(localized:)` when using a semantic key.
- Keep interpolation placeholders intact. English values must reproduce Sapphire's existing English output exactly, including its wording, plurals, units and number and date formats; only the translations change what users see. A Chinese plural normally has an `other` form.
- `String(localized:)` formats interpolated integers with the locale's grouping separator (`1,013`). When a plain `String` was built before and the number can reach four digits, interpolate `String(value)` so English keeps its ungrouped digits. Where Chinese needs a different number or date convention (for example 万/亿 counts), branch on `ChineseFormatting.isActive` and leave the English code path unchanged.
- Settings search uses each section's English `searchTokens` unchanged. Terms for other languages go in `settings.search.keywords.<section>` as a comma-separated list; its English value is the section name, so English search behaves as before.
- Translate the message around an error code, never the code itself. Permission text describes the existing permission; localization must not request new access or change feature behavior.

## Terminology

| English | Simplified Chinese |
| --- | --- |
| Sapphire | Sapphire |
| Notch | 刘海区域（导航短标签可用“刘海”） |
| Widget | 小组件 |
| Live Activity | 实时活动 |
| File Shelf | 文件暂存架 |
| Caffeinate | 保持唤醒 |
| Eye Break | 护眼休息 |
| Focus Session | 专注时段 |
| HUD | 提示浮层 |
| Helper | 辅助服务（macOS 登录项中的注册名 Sapphire Helper 保留） |

Product and service names such as Spotify, Apple Music, Gemini and Shopify retain their names. Public-build placeholders must continue to say that unavailable functionality is not included; translated text does not imply that a private implementation exists.

## Verification

Use Xcode 26.1.1 or newer: Sapphire uses Swift 6.2 isolated protocol conformances. CI selects Xcode 26.1.1 explicitly because the macOS 15 runner's default Xcode 16.4 cannot compile that syntax.

Run `script/test_localization.sh` to build and execute the `SapphireLocalizationTests` scheme in English/US, Simplified Chinese/China, and Simplified Chinese/US, or add `build` to compile without executing. Both modes check the actual app and embedded Widget resources against freshly compiled catalogs, compare the app/NearbyShare/Widget compiler inventories, and run native bundle probes. Its test host suppresses application lifecycle work under XCTest. The original `SapphireTests` scheme remains available; missing private implementations in a public checkout must be reported separately rather than removing their tests.

The native resource checks do not launch Sapphire or change preferences:

```sh
python3 script/check_localization.py
python3 script/localization/test_catalog_check.py
python3 script/test_localization.py --output /absolute/resource-check.json
python3 script/test_localization.py --app /absolute/Sapphire.app --output /absolute/bundle-check.json
```

The catalog validator rejects missing translations and changed format arguments. Its optional `--app-stringsdata` and `--widget-stringsdata` arguments compare against fresh compiler extraction; repeat the app argument for linked libraries that use the main bundle. `test_localization.py` compiles source catalogs by default, or reads the supplied app with `--app`. Both modes run fresh Foundation processes for English, Simplified Chinese, an unsupported language, ordered fallback and independent region settings. Formatting fixtures are separate from product strings and cannot establish UI coverage.

The Localization resources workflow runs catalog validation, native resource checks and the application test entry point on pull requests. It does not accept UI layout, system permissions or hardware-dependent features.

Before delivery, also verify the built Widget resources, run the navigation tests, and inspect actual Chinese and English screens for clipping, wrapping, search, menus and alerts. Record the tested source commit and app hash. Build success, resource checks, UI acceptance, helper permission, signing and distribution readiness are separate results. Keep hardware-, account- or permission-blocked scenarios visible in the acceptance record.
