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
REPOSITORY = ROOT.parents[1]
SOURCE_SHA256 = 'b14e4d4d5be16d8f93da1e46008ddb3166b572ba05c9ecc587d02b3111652872'
PUBLIC_SOURCE = 'Sapphire/Localizable.xcstrings on this branch; reused records are stored inline in reused-public-entries.json'
spec = importlib.util.spec_from_file_location('catalog_validator', REPOSITORY / 'script/check_localization.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
source_path = ROOT / 'Sapphire-PrivateBuild.json'
translated_path = ROOT / 'Sapphire-PrivateBuild.zh-Hant.xcstrings'
source = json.loads(source_path.read_text())
translated = json.loads(translated_path.read_text())
public = json.loads((ROOT / 'reused-public-entries.json').read_text())
public_catalog = json.loads((REPOSITORY / 'Sapphire/Localizable.xcstrings').read_text())
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
check('only_en_and_zh_hant', all(set(v.get('localizations', {})) == {'en', 'zh-Hant'} for v in translated['strings'].values()))
check('original_comments_preserved', all(v['comment'] == translated['strings'].get(k, {}).get('comment') for k, v in source['strings'].items()))
check('manual_extraction_preserved', all(v.get('extractionState') == 'manual' for v in translated['strings'].values()))
overlap = source['strings'].keys() & public['strings'].keys()
check('exactly_37_existing_keys', len(overlap) == 37)
check('reused_records_match_public_catalog', all(
    public['strings'][k]['localizations'] == {lang: public_catalog['strings'].get(k, {}).get('localizations', {}).get(lang) for lang in ('en', 'zh-Hant')}
    for k in public['strings']))
check('all_37_en_hant_records_unchanged', all(translated['strings'][k]['localizations'][lang] == public['strings'][k]['localizations'][lang] for k in overlap for lang in ('en', 'zh-Hant')))
check('new_key_english_exact', all(translated['strings'][k]['localizations']['en'] == {'stringUnit': {'state': 'translated', 'value': k}} for k in source['strings'].keys() - overlap))
raw = re.compile(r'\\\([^)]*\)')
for key, value in translated['strings'].items():
    en_units = validator.units(value['localizations']['en'])
    zh_units = validator.units(value['localizations']['zh-Hant'])
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

report = {
    'passed': not errors,
    'scope': 'catalog structure, completeness, exact source keys/comments, placeholders, and overlap reuse; no private runtime or UI acceptance',
    'source_sha256': sha256(source_path.read_bytes()).hexdigest(),
    'translated_sha256': sha256(translated_path.read_bytes()).hexdigest(),
    'public_source': PUBLIC_SOURCE,
    'entries': len(translated['strings']),
    'reused_public_entries': len(overlap),
    'new_entries': len(source['strings'].keys() - overlap),
    'translated_languages': ['en', 'zh-Hant'],
    'chinese_string_units': sum(len(validator.units(v['localizations']['zh-Hant'])) for v in translated['strings'].values()),
    'english_string_units': sum(len(validator.units(v['localizations']['en'])) for v in translated['strings'].values()),
    'printf_keys': sum(bool(validator.FORMAT.search(k)) for k in source['strings']),
    'raw_swift_interpolation_keys': [k for k in source['strings'] if raw.search(k)],
    'checks': checks,
    'errors': errors,
}
(ROOT / 'validation-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(0 if report['passed'] else 1)
