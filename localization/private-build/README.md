# Private-build Simplified Chinese delivery

`Sapphire-PrivateBuild.zh-Hans.xcstrings` contains English and Simplified Chinese for all 1,189 entries in the maintainer's [published catalog](https://github.com/user-attachments/files/33520868/Sapphire-PrivateBuild.json). It reuses 37 English/Simplified Chinese records from public localization commit `7a016b1f7c8ac41dc894d55646b15d48f85a6b76` and adds 1,152 translations. Private Traditional Chinese is reserved for the collaborating translator.

This directory is outside the public application's synchronized resource group. It is a translation handoff, with no private executable or UI acceptance. The original attachment, its SHA-256, source references, preserved overlap records, and unresolved integration questions are recorded alongside the deliverable.

## Integration

1. Compare the attachment's exact keys with a fresh private-build compiler extraction, especially the raw `\\(manager.searchQuery)` interpolation key.
2. Merge the `zh-Hans` records by exact key into the private application's `Localizable.xcstrings`; retain the public entries and combine the collaborator's `zh-Hant` records. Do not add this file as a second default table. Compiling this filename directly creates a separate table named `Sapphire-PrivateBuild.zh-Hans`.
3. Resolve the questions below in the private source and catalog, then build and inspect both Chinese locales in the private UI.

## Maintainer checks

- Eight keys contain an English plural-suffix argument such as `%lld item%@`. The placeholders are preserved; callers passing `s` or `es` need locale-aware plural handling before Chinese output is accepted.
- `Hits` is shared by hockey and baseball. Split the semantic key so Chinese can distinguish body checks from base hits.
- Confirm the raw Swift interpolation key against the private compiler inventory before renaming it.
- Check compact sports labels `K`, `PP`, `T`, `TD`, and `TOP` against their panels; these abbreviations remain unchanged.
- Confirm that `Quote` means a financial quote in its card context.
- Replace the English configuration message referring to "the end of this chat" with durable product instructions, then update its translations.

The precise affected keys and acceptance steps are in `private-catalog-manifest.json`. Structural validation and native catalog compilation do not resolve these runtime questions.

## Validation

From the repository root:

```sh
python3 localization/private-build/check_private_catalog.py
mkdir -p /tmp/sapphire-private-catalog
xcrun xcstringstool compile localization/private-build/Sapphire-PrivateBuild.zh-Hans.xcstrings --output-directory /tmp/sapphire-private-catalog
```

The validator checks the attachment hash, key order and set, source metadata and comments, translation completeness, argument positions and types, raw interpolation preservation, and the 37 reused records. It writes `validation-report.json` with explicit coverage limits.
