#!/usr/bin/env python3
"""Exercise compiled resources with fresh Foundation processes, without launching Sapphire.

python3 script/test_localization.py --output /tmp/localization-result.json
python3 script/test_localization.py --app /absolute/Sapphire.app --output /tmp/bundle-result.json

The default mode compiles source catalogs; --app reads an existing app's resources.
ProbeFixtures is a separate table and never supplies product strings. This is a
resource test, not a SwiftUI, TCC, WidgetKit, helper, or full SapphireTests result.
"""

import argparse
import datetime
import hashlib
import json
import platform
import plistlib
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SUPPORT = Path(__file__).resolve().parent / "localization"
CAMERA_EN = "Sapphire uses the camera for the Mirror widget so you can see yourself in the notch."
SCENARIOS = [
    ("english", "(en)", "en_US", "en"),
    ("simplified-Chinese", "(zh-Hans)", "zh_CN", "zh-Hans"),
    ("unsupported-language", "(fr)", "fr_FR", "en"),
    ("ordered-language-fallback", "(fr,zh-Hans,en)", "en_US", "zh-Hans"),
    ("Chinese-with-US-region", "(zh-Hans)", "en_US", "zh-Hans"),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, report, *, timeout=60):
    completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    report["commands"].append({
        "argv": [str(value) for value in command],
        "exit_code": completed.returncode,
        "stdout": completed.stdout[-24000:],
        "stderr": completed.stderr[-24000:],
    })
    return completed


def compile_catalog(catalog, destination, report):
    completed = run([
        "xcrun", "xcstringstool", "compile", str(catalog),
        "--output-directory", str(destination), "--serialization-format", "text",
    ], report)
    if completed.returncode:
        raise RuntimeError(f"xcstringstool failed for {catalog}")


def write_report(report, output):
    body = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(body)
        print(f"{report['status']}: {output}")
    else:
        print(body, end="")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=Path, help="Read-only path to a built Sapphire.app")
    parser.add_argument("--output", type=Path, help="Write JSON evidence here; default: stdout")
    args = parser.parse_args()
    app = args.app.expanduser().resolve() if args.app else None
    output = args.output.expanduser().resolve() if args.output else None
    catalogs = [ROOT / "Sapphire/Localizable.xcstrings", ROOT / "Sapphire/App/InfoPlist.xcstrings"]
    probe_source = SUPPORT / "LocalizationProbe.swift"
    fixtures = SUPPORT / "ProbeFixtures.xcstrings"
    report = {
        "status": "PRECONDITION_FAILED", "passed": False,
        "mode": "built-app-resources" if app else "compiled-source-catalogs",
        "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "repository": str(ROOT), "app": str(app) if app else None,
        "host": {"macos": platform.mac_ver()[0], "architecture": platform.machine()},
        "commands": [], "scenarios": [], "inputs": [], "errors": [],
        "limitations": [
            "Does not launch Sapphire/NSApplication or change user/system defaults.",
            "Fixture checks validate native resource behavior, not product translations.",
            "Does not establish UI layout, TCC prompts, WidgetKit, helper, signing, or full test-suite success.",
        ],
    }
    required = [Path(__file__).resolve(), probe_source, fixtures]
    required += [app / "Contents/Info.plist"] if app else catalogs
    if output and ((app and output.is_relative_to(app)) or output in required):
        parser.error("--output must not overwrite an input or write inside the tested app")
    report["errors"] = [f"Missing required input: {path}" for path in required if not path.is_file()]
    if sys.platform != "darwin":
        report["errors"].append("macOS with Xcode command-line tools is required")
    if report["errors"]:
        write_report(report, output)
        return 2

    snapshots = {path: path.read_bytes() for path in required}
    for path, content in snapshots.items():
        report["inputs"].append({"path": str(path), "sha256": hashlib.sha256(content).hexdigest()})
    app_resources = []
    if app:
        for language in ["en", "zh-Hans"]:
            for table in ["Localizable", "InfoPlist"]:
                for extension in ["strings", "stringsdict"]:
                    path = app / f"Contents/Resources/{language}.lproj/{table}.{extension}"
                    app_resources.append(path)
        app_before = {path: digest(path) if path.is_file() else None for path in app_resources}
        app_before[app / "Contents/Info.plist"] = digest(app / "Contents/Info.plist")
    head = run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], report)
    report["head"] = head.stdout.strip() if head.returncode == 0 else None
    try:
        # Only this owned temporary directory is ever removed. Failures retain
        # bounded command output and results in the report, not executables/caches.
        with tempfile.TemporaryDirectory(prefix="sapphire-localization-") as scratch:
            directory = Path(scratch)
            snapshot_dir = directory / "inputs"
            snapshot_dir.mkdir()
            for path, content in snapshots.items():
                (snapshot_dir / path.name).write_bytes(content)
            bundle = directory / "LocalizationProbe.app"
            resources = bundle / "Contents/Resources"
            executable = bundle / "Contents/MacOS/LocalizationProbe"
            resources.mkdir(parents=True)
            executable.parent.mkdir(parents=True)
            info = {
                "CFBundleExecutable": "LocalizationProbe",
                "CFBundleIdentifier": "local.sapphire.localization-probe." + uuid.uuid4().hex,
                "CFBundlePackageType": "APPL", "CFBundleDevelopmentRegion": "en",
                "CFBundleName": "LocalizationProbe", "CFBundleVersion": "1",
                "NSCameraUsageDescription": CAMERA_EN,
            }
            (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            report["stage"] = {"path": str(bundle), "temporary": True, "removed_after_run": True}
            compile_catalog(snapshot_dir / fixtures.name, resources, report)
            if not app:
                for catalog in catalogs:
                    compile_catalog(snapshot_dir / catalog.name, resources, report)
            architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
            completed = run([
                "xcrun", "swiftc", str(snapshot_dir / probe_source.name), "-o", str(executable),
                "-target", architecture + "-apple-macosx13.5",
                "-module-cache-path", str(directory / "module-cache"),
            ], report, timeout=180)
            if completed.returncode:
                raise RuntimeError("Foundation probe compilation failed")
            for name, languages, region, expected_language in SCENARIOS:
                command = [str(executable), "-AppleLanguages", languages,
                           "-AppleLocale", region, "--expected-language", expected_language]
                if app:
                    command += ["--app", str(app)]
                completed = run(command, report, timeout=20)
                try:
                    observed = json.loads(completed.stdout)
                except json.JSONDecodeError as error:
                    raise RuntimeError(f"{name}: probe did not return JSON: {error}") from error
                report["scenarios"].append({
                    "name": name, "exit_code": completed.returncode, "observation": observed,
                    "passed": completed.returncode == 0 and observed.get("passed") is True,
                })
                failures = [check["name"] for check in observed.get("checks", []) if not check["passed"]]
                print(f"{name}: {'FAIL ' + ', '.join(failures) if failures else 'PASS'}", file=sys.stderr)
            product_resources = app / "Contents/Resources" if app else resources
            for language in ["en", "zh-Hans"]:
                for table in ["Localizable", "InfoPlist"]:
                    for extension in ["strings", "stringsdict"]:
                        path = product_resources / f"{language}.lproj/{table}.{extension}"
                        if path.is_file():
                            report["inputs"].append({"path": str(path), "sha256": digest(path)})
            report["passed"] = all(scenario["passed"] for scenario in report["scenarios"])
            if app and any((digest(path) if path.is_file() else None) != before for path, before in app_before.items()):
                report["passed"] = False
                report["errors"].append("Tested app resources changed during the run; results are not attributable")
            report["status"] = "PASS" if report["passed"] else "BEHAVIOR_FAILED"
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["status"] = "TOOL_FAILED"
        report["errors"].append(str(error))
    write_report(report, output)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
