#!/usr/bin/env python3
"""Check reviewed en/zh-Hans catalog values and optional compiler-key coverage.

This does not prove UI layout or runtime behavior. Run test_localization.py for
native lookup/formatting and the Xcode test scheme for application code.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = {
    "app": ROOT / "Sapphire/Localizable.xcstrings",
    "permissions": ROOT / "Sapphire/App/InfoPlist.xcstrings",
    "widget": ROOT / "SapphireAndroidWidgets/Localizable.xcstrings",
}
# Swift extraction uses object, integer and floating-point printf arguments.
# A space after % is deliberately not a flag: ordinary labels include “100% charge”.
FORMAT = re.compile(r"%(?:(?P<position>\d+)\$)?[-+#0]*\d*(?:\.\d+)?(?P<length>hh|ll|[hlLzjtq])?(?P<type>[@diuoxXfFeEgGaAcCsSp%])")


def arguments(text):
    result = Counter()
    implicit_position = 1
    for match in FORMAT.finditer(text):
        if match["type"] == "%":
            continue
        position = int(match["position"]) if match["position"] else implicit_position
        if not match["position"]:
            implicit_position += 1
        result[(position, (match["length"] or "") + match["type"])] += 1
    return result


def units(node, path=()):
    result = {}
    if isinstance(node, dict):
        if "stringUnit" in node:
            result[path] = node["stringUnit"]
        for key, value in node.items():
            if key != "stringUnit":
                result.update(units(value, path + (key,)))
    return result


def validate_catalog(catalog):
    errors = []
    if catalog.get("sourceLanguage") != "en":
        errors.append("sourceLanguage must remain en")
    if not isinstance(catalog.get("strings"), dict) or not catalog["strings"]:
        return errors + ["Catalog must contain strings"]
    for key, entry in catalog.get("strings", {}).items():
        if not key:  # SwiftUI permits intentionally empty labels.
            continue
        languages = entry.get("localizations", {})
        english = units(languages.get("en", {}))
        chinese = units(languages.get("zh-Hans", {}))
        for language, values in (("en", english), ("zh-Hans", chinese)):
            if not values:
                errors.append(f"{key!r}: missing {language} value")
            for unit in values.values():
                if not isinstance(unit.get("value"), str) or not unit["value"].strip():
                    errors.append(f"{key!r}: blank {language} value")
                if unit.get("state") != "translated":
                    errors.append(f"{key!r}: {language} is not reviewed/translated")
        for path, translated in chinese.items():
            source = english.get(path)
            if source is None and len(english) == 1:
                source = next(iter(english.values()))
            if source is None:
                errors.append(f"{key!r}: no English counterpart for {path}")
            elif isinstance(source.get("value"), str) and isinstance(translated.get("value"), str):
                if arguments(source["value"]) != arguments(translated["value"]):
                    errors.append(f"{key!r}: format argument positions/types differ at {path}")
    return errors


def compiler_keys(directory):
    paths = sorted(directory.rglob("*.stringsdata"))
    if not paths:
        raise ValueError(f"No compiler .stringsdata files in {directory}")
    keys = set()
    for path in paths:
        data = json.loads(path.read_text())
        keys.update(item["key"] for item in data.get("tables", {}).get("Localizable", []) if item["key"])
    if not keys:
        raise ValueError(f"No Localizable keys extracted in {directory}")
    return keys


def read_compiled_table(path):
    # plutil handles both Xcode's binary files and xcstrings' OpenStep strings.
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def compare_compiled_tables(expected, actual, table):
    errors = []
    for language in ("en", "zh-Hans"):
        for extension in ("strings", "stringsdict"):
            relative = Path(f"{language}.lproj/{table}.{extension}")
            source, built = expected / relative, actual / relative
            if not source.is_file():
                if built.exists():
                    errors.append(f"Unexpected compiled resource: {built}")
                continue
            if not built.is_file():
                errors.append(f"Missing compiled resource: {built}")
                continue
            expected_values, actual_values = read_compiled_table(source), read_compiled_table(built)
            if expected_values != actual_values:
                keys = sorted(key for key in expected_values.keys() | actual_values.keys()
                              if expected_values.get(key) != actual_values.get(key))
                errors.append(f"Compiled values differ in {built}: {keys!r}")
    return errors


def validate_built_app(app):
    """Compare actual target resources with freshly compiled source catalogs."""
    result = {}
    with tempfile.TemporaryDirectory(prefix="sapphire-catalog-check-") as directory:
        for name, catalog in CATALOGS.items():
            expected = Path(directory) / name
            expected.mkdir()
            subprocess.run(["xcrun", "xcstringstool", "compile", str(catalog),
                            "--output-directory", str(expected)],
                           capture_output=True, text=True, check=True)
            bundle = app / "Contents/PlugIns/SapphireAndroidWidgets.appex" if name == "widget" else app
            result[name] = compare_compiled_tables(expected, bundle / "Contents/Resources", catalog.stem)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-stringsdata", type=Path, action="append", help="Fresh app or linked-library Objects-normal directory; repeat for each target")
    parser.add_argument("--widget-stringsdata", type=Path, action="append", help="Fresh Widget Objects-normal directory from a successful build")
    parser.add_argument("--app", type=Path, help="Read-only built Sapphire.app; compare main, InfoPlist and embedded Widget resources (macOS)")
    args = parser.parse_args()
    report = {"passed": True, "catalogs": {}, "errors": [], "scope": "catalog integrity and supplied compiler inventories; not UI coverage"}
    built_errors = {}
    if args.app:
        try:
            built_errors = validate_built_app(args.app)
            report["built_app"] = str(args.app)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            report["errors"].append(f"Built resource verification failed: {error}")
    for name, path in CATALOGS.items():
        data = json.loads(path.read_text())
        errors = validate_catalog(data)
        errors += built_errors.get(name, [])
        values = data.get("strings", {})
        details = {"path": str(path.relative_to(ROOT)), "entries": len(values), "preserved": sum(entry.get("shouldTranslate") is False for entry in values.values())}
        directories = args.app_stringsdata if name == "app" else args.widget_stringsdata if name == "widget" else None
        if directories:
            try:
                keys = set().union(*(compiler_keys(directory) for directory in directories))
                missing = sorted(keys - values.keys())
                details.update({"compiler_keys": len(keys), "missing_compiler_keys": missing})
                errors += [f"Missing compiler key: {key!r}" for key in missing]
            except (OSError, ValueError, KeyError) as error:
                errors.append(str(error))
        details["errors"] = errors
        report["catalogs"][name] = details
        report["errors"] += [f"{name}: {error}" for error in errors]
    report["passed"] = not report["errors"]
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
