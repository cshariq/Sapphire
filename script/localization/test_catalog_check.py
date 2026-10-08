"""Regression cases for mistakes that native catalog compilation accepts."""
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("catalog_check", Path(__file__).parents[1] / "check_localization.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


def catalog(key="Hello %@", english="Hello %@", chinese="你好，%@"):
    return {"sourceLanguage": "en", "version": "1.0", "strings": {
        key: {"localizations": {
            "en": {"stringUnit": {"state": "translated", "value": english}},
            "zh-Hans": {"stringUnit": {"state": "translated", "value": chinese}},
        }}
    }}


class CatalogCheckTests(unittest.TestCase):
    def test_missing_or_empty_catalog_cannot_report_success(self):
        for value in ({"sourceLanguage": "en"}, {"sourceLanguage": "en", "strings": {}}):
            self.assertTrue(CHECK.validate_catalog(value))

    def test_translator_can_reorder_parameters_but_not_change_their_types(self):
        valid = catalog("Send %@ to %lld devices", "Send %@ to %lld devices", "向 %2$lld 台设备发送 %1$@")
        self.assertEqual(CHECK.validate_catalog(valid), [])
        invalid = catalog("Send %@ to %lld devices", "Send %@ to %lld devices", "向 %1$lld 台设备发送 %2$@")
        self.assertTrue(any("format" in error for error in CHECK.validate_catalog(invalid)))

    def test_missing_variable_is_rejected(self):
        self.assertTrue(any("format" in error for error in CHECK.validate_catalog(catalog(chinese="你好"))))

    def test_semantic_keys_have_english_values_and_need_chinese(self):
        value = catalog("weather.condition.clear", "Clear", "晴")
        self.assertEqual(CHECK.validate_catalog(value), [])
        del value["strings"]["weather.condition.clear"]["localizations"]["zh-Hans"]
        self.assertTrue(any("zh-Hans" in error for error in CHECK.validate_catalog(value)))

    def test_natural_percent_signs_are_not_printf_arguments(self):
        self.assertEqual(CHECK.validate_catalog(catalog("100% charge", "100% charge", "100% 电量")), [])
        self.assertEqual(CHECK.validate_catalog(catalog("%lld%%", "%lld%%", "%lld%%")), [])

    def test_chinese_other_plural_is_checked_against_english_other(self):
        value = catalog("NFiles", "%lld files", "%lld 个文件")
        localizations = value["strings"]["NFiles"]["localizations"]
        for language in ("en", "zh-Hans"):
            localizations[language] = {"variations": {"plural": {"other": localizations[language]}}}
        localizations["en"]["variations"]["plural"]["one"] = {"stringUnit": {"state": "translated", "value": "%lld file"}}
        self.assertEqual(CHECK.validate_catalog(value), [])
        localizations["zh-Hans"]["variations"]["plural"]["other"]["stringUnit"]["value"] = "%@ 个文件"
        self.assertTrue(any("format" in error for error in CHECK.validate_catalog(value)))

    def test_blank_or_unreviewed_translation_is_not_complete(self):
        for chinese in ("", "   "):
            self.assertTrue(CHECK.validate_catalog(catalog(chinese=chinese)))
        value = catalog()
        value["strings"]["Hello %@"]["localizations"]["zh-Hans"]["stringUnit"]["state"] = "needs_review"
        self.assertTrue(CHECK.validate_catalog(value))

    def test_compiler_inventory_requires_real_nonempty_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, "No compiler"):
                CHECK.compiler_keys(root)
            path = root / "File.stringsdata"
            path.write_text(json.dumps({"tables": {"Localizable": [{"key": ""}]}}))
            with self.assertRaisesRegex(ValueError, "No Localizable keys"):
                CHECK.compiler_keys(root)
            path.write_text(json.dumps({"tables": {"Localizable": [{"key": "Hello"}, {"key": "Hello"}, {"key": ""}]}}))
            self.assertEqual(CHECK.compiler_keys(root), {"Hello"})

    def test_built_bundle_cannot_omit_widget_translation_or_change_plural_values(self):
        with tempfile.TemporaryDirectory() as directory:
            expected = Path(directory) / "expected"
            actual = Path(directory) / "SapphireAndroidWidgets.appex/Contents/Resources"
            for language in ("en", "zh-Hans"):
                path = expected / f"{language}.lproj/Localizable.strings"
                path.parent.mkdir(parents=True)
                path.write_bytes(plistlib.dumps({"Widget": "Widget" if language == "en" else "小组件"}))
            plural = expected / "en.lproj/Localizable.stringsdict"
            plural.write_bytes(plistlib.dumps({"%lld sessions": {
                "NSStringLocalizedFormatKey": "%#@arg1@",
                "arg1": {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                         "NSStringFormatValueTypeKey": "lld", "one": "%lld session", "other": "%lld sessions"}
            }}))
            self.assertTrue(CHECK.compare_compiled_tables(expected, actual, "Localizable"))
            shutil.copytree(expected, actual)
            self.assertEqual(CHECK.compare_compiled_tables(expected, actual, "Localizable"), [])
            (actual / "zh-Hans.lproj/Localizable.strings").unlink()
            self.assertTrue(any("Missing" in error for error in CHECK.compare_compiled_tables(expected, actual, "Localizable")))
            shutil.copy2(expected / "zh-Hans.lproj/Localizable.strings", actual / "zh-Hans.lproj/Localizable.strings")
            values = plistlib.loads(plural.read_bytes())
            values["%lld sessions"]["arg1"]["one"] = "%lld sessions"
            (actual / "en.lproj/Localizable.stringsdict").write_bytes(plistlib.dumps(values))
            self.assertTrue(any("differ" in error for error in CHECK.compare_compiled_tables(expected, actual, "Localizable")))

    def test_cli_unions_linked_library_keys_and_rejects_missing_product_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "script/check_localization.py"
            script.parent.mkdir()
            shutil.copy2(Path(CHECK.__file__), script)
            for relative in ("Sapphire/Localizable.xcstrings", "Sapphire/App/InfoPlist.xcstrings", "SapphireAndroidWidgets/Localizable.xcstrings"):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(catalog()))
            command = [sys.executable, str(script)]
            for target in ("app", "library", "widget"):
                path = root / target / "File.stringsdata"
                path.parent.mkdir()
                path.write_text(json.dumps({"tables": {"Localizable": [{"key": "Hello %@"}]}}))
                command += ["--widget-stringsdata" if target == "widget" else "--app-stringsdata", str(path.parent)]
            passed = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
            self.assertEqual(json.loads(passed.stdout)["catalogs"]["app"]["compiler_keys"], 1)
            (root / "library/File.stringsdata").write_text(json.dumps({"tables": {"Localizable": [{"key": "New library message"}]}}))
            failed = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
            self.assertEqual(json.loads(failed.stdout)["catalogs"]["app"]["missing_compiler_keys"], ["New library message"])


if __name__ == "__main__":
    unittest.main()
