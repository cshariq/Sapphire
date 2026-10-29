#!/usr/bin/env python3
"""Validate private translation delivery; does not establish private runtime coverage."""
from collections import Counter
from hashlib import sha256
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
SOURCE_SHA256 = 'b14e4d4d5be16d8f93da1e46008ddb3166b572ba05c9ecc587d02b3111652872'
BASE_COMMIT = '7a016b1f7c8ac41dc894d55646b15d48f85a6b76'
spec = importlib.util.spec_from_file_location('catalog_validator', ROOT.parents[1] / 'script/check_localization.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
source_path = ROOT / 'Sapphire-PrivateBuild.json'
translated_path = ROOT / 'Sapphire-PrivateBuild.zh-Hans.xcstrings'
source = json.loads(source_path.read_text())
translated = json.loads(translated_path.read_text())
public = json.loads((ROOT / 'reused-public-entries.json').read_text())
errors = validator.validate_catalog(translated)
checks = {}
def check(name, condition):
    checks[name] = bool(condition)
    if not condition:
        errors.append(name)

check('original_sha256', sha256(source_path.read_bytes()).hexdigest() == SOURCE_SHA256)
check('entry_count_1189', len(source['strings']) == len(translated['strings']) == 1189)
check('exact_key_order_and_set', list(source['strings']) == list(translated['strings']))
check('metadata_source_language_and_version', all(source[k] == translated[k] for k in ('sourceLanguage', 'version')))
check('only_en_and_zh_hans', all(set(v.get('localizations', {})) == {'en', 'zh-Hans'} for v in translated['strings'].values()))
check('original_comments_preserved', all(v['comment'] == translated['strings'].get(k, {}).get('comment') for k, v in source['strings'].items()))
check('manual_extraction_preserved', all(v.get('extractionState') == 'manual' for v in translated['strings'].values()))
overlap = source['strings'].keys() & public['strings'].keys()
check('exactly_37_existing_keys', len(overlap) == 37)
check('all_37_en_hans_records_unchanged', all(translated['strings'][k]['localizations'][lang] == public['strings'][k]['localizations'][lang] for k in overlap for lang in ('en', 'zh-Hans')))
check('new_key_english_exact', all(translated['strings'][k]['localizations']['en'] == {'stringUnit': {'state': 'translated', 'value': k}} for k in source['strings'].keys() - overlap))
raw = re.compile(r'\\\([^)]*\)')
for key, value in translated['strings'].items():
    en_units = validator.units(value['localizations']['en'])
    zh_units = validator.units(value['localizations']['zh-Hans'])
    for path, unit in zh_units.items():
        en = en_units.get(path)
        if en is None and len(en_units) == 1:
            en = next(iter(en_units.values()))
        if en is not None:
            if Counter(raw.findall(unit['value'])) != Counter(raw.findall(en['value'])):
                errors.append(f'Raw Swift interpolation changed: {key!r}')
            if unit['value'].count('%%') != en['value'].count('%%'):
                errors.append(f'Escaped percent count changed: {key!r}')
check('catalog_validator_passed', not validator.validate_catalog(translated))

# Traditional Chinese delivery: same keys, comments and English records, zh-Hant only.
hant_path = ROOT / 'Sapphire-PrivateBuild.zh-Hant.xcstrings'
hant = json.loads(hant_path.read_text())
check('zh_hant_exact_key_order_and_set', list(source['strings']) == list(hant['strings']))
check('zh_hant_metadata_source_language_and_version', all(source[k] == hant[k] for k in ('sourceLanguage', 'version')))
check('zh_hant_only_en_and_zh_hant', all(set(v.get('localizations', {})) == {'en', 'zh-Hant'} for v in hant['strings'].values()))
check('zh_hant_original_comments_preserved', all(v['comment'] == hant['strings'].get(k, {}).get('comment') for k, v in source['strings'].items()))
check('zh_hant_manual_extraction_preserved', all(v.get('extractionState') == 'manual' for v in hant['strings'].values()))
check('zh_hant_english_matches_zh_hans_delivery', all(hant['strings'][k]['localizations']['en'] == v['localizations']['en'] for k, v in translated['strings'].items()))
check('all_37_zh_hant_records_unchanged', all(hant['strings'][k]['localizations']['zh-Hant'] == public['strings'][k]['localizations']['zh-Hant'] for k in overlap))
for key, value in hant['strings'].items():
    en_units = validator.units(value['localizations']['en'])
    for path, unit in validator.units(value['localizations']['zh-Hant']).items():
        en = en_units.get(path)
        if en is None and len(en_units) == 1:
            en = next(iter(en_units.values()))
        if en is not None:
            if Counter(raw.findall(unit['value'])) != Counter(raw.findall(en['value'])):
                errors.append(f'zh-Hant raw Swift interpolation changed: {key!r}')
            if unit['value'].count('%%') != en['value'].count('%%'):
                errors.append(f'zh-Hant escaped percent count changed: {key!r}')
validator.REQUIRED_TRANSLATIONS = ('zh-Hant',)
hant_errors = validator.validate_catalog(hant)
errors.extend(hant_errors)
check('zh_hant_catalog_validator_passed', not hant_errors)

report = {
    'passed': not errors,
    'scope': 'catalog structure, completeness, exact source keys/comments, placeholders, and overlap reuse; no private runtime or UI acceptance',
    'source_sha256': sha256(source_path.read_bytes()).hexdigest(),
    'translated_sha256': sha256(translated_path.read_bytes()).hexdigest(),
    'public_base_commit': BASE_COMMIT,
    'entries': len(translated['strings']),
    'reused_public_entries': len(overlap),
    'new_entries': len(source['strings'].keys() - overlap),
    'zh_hant_sha256': sha256(hant_path.read_bytes()).hexdigest(),
    'translated_languages': ['en', 'zh-Hans', 'zh-Hant'],
    'chinese_string_units': sum(len(validator.units(v['localizations']['zh-Hans'])) for v in translated['strings'].values()),
    'zh_hant_string_units': sum(len(validator.units(v['localizations']['zh-Hant'])) for v in hant['strings'].values()),
    'english_string_units': sum(len(validator.units(v['localizations']['en'])) for v in translated['strings'].values()),
    'printf_keys': sum(bool(validator.FORMAT.search(k)) for k in source['strings']),
    'raw_swift_interpolation_keys': [k for k in source['strings'] if raw.search(k)],
    'checks': checks,
    'errors': errors,
}
(ROOT / 'validation-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(0 if report['passed'] else 1)
