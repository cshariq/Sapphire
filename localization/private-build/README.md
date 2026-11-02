# Private-build Traditional Chinese delivery

`Sapphire-PrivateBuild.zh-Hant.xcstrings` contains English and Traditional Chinese (Taiwan) for all 1,189 entries in the maintainer's [published catalog](https://github.com/user-attachments/files/33520868/Sapphire-PrivateBuild.json). It reuses 37 English/Traditional Chinese records unchanged from this branch's public `Sapphire/Localizable.xcstrings` (stored inline in `reused-public-entries.json`) and adds 1,152 translations. Keys flagged below use provisional choices.

This directory is outside the public application's synchronized resource group. It is a translation handoff, with no private executable or UI acceptance. The original attachment, its SHA-256, source references, preserved overlap records, and unresolved integration questions are recorded alongside the deliverable.

## Integration

1. Compare the attachment's exact keys with a fresh private-build compiler extraction, especially the raw `\\(manager.searchQuery)` interpolation key.
2. Merge the `zh-Hant` records by exact key into the private application's `Localizable.xcstrings`, retaining the public entries. Do not add the file as a second default table. Compiling this filename directly creates a separate table named after the file.
3. Resolve the questions below in the private source and catalog, then build and inspect the Traditional Chinese locale in the private UI.

## Maintainer checks

- Eight keys contain an English plural-suffix argument such as `%lld item%@`. The placeholders are preserved; callers passing `s` or `es` need locale-aware plural handling before Chinese output is accepted.
- `Hits` is shared by hockey and baseball. Split the semantic key so Chinese can distinguish body checks from base hits.
- Confirm the raw Swift interpolation key against the private compiler inventory before renaming it.
- Check compact sports labels `K`, `PP`, `T`, `TD`, and `TOP` against their panels; these abbreviations remain unchanged.
- Confirm that `Quote` means a financial quote in its card context.
- Replace the English configuration message referring to "the end of this chat" with durable product instructions, then update its translation.

The precise affected keys and acceptance steps are in `private-catalog-manifest.json`. Structural validation and native catalog compilation do not resolve these runtime questions.

## Validation

From the repository root:

```sh
python3 localization/private-build/check_private_catalog.py
mkdir -p /tmp/sapphire-private-catalog
xcrun xcstringstool compile localization/private-build/Sapphire-PrivateBuild.zh-Hant.xcstrings --output-directory /tmp/sapphire-private-catalog
```

The validator checks the attachment hash, key order and set, source metadata and comments, translation completeness, argument positions and types, raw interpolation preservation, and the 37 reused records, including that they still equal the public catalog's English and Traditional Chinese values. It writes `validation-report.json` with explicit coverage limits.
