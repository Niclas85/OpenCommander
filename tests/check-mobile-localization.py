"""Release gate for the iPhone storage/permission strings in all supported languages."""
from pathlib import Path
import json
import re
source = (Path(__file__).resolve().parents[1] / 'ios/OpenCommander/Localization.swift').read_text()
source = source.split('private static let mobileStrings:', 1)[1].split('static func get(', 1)[0]
blocks = re.findall(r'^        "([^"]+)": \[\n(.*?)^        \],', source, re.M | re.S)
expected = set('en de fr es it pt nl zh-Hans ja ko ar hi ru tr pl id vi th uk sv'.split())
assert {language for language, _ in blocks} == expected
reference = None
for language, body in blocks:
    entries = re.findall(r'^            (".*?"): (".*"),$', body, re.M)
    values = {json.loads(k): json.loads(v) for k, v in entries}
    assert len(values) == 17 and len(entries) == 17, language
    assert all(values.values()), language
    if reference is None: reference = set(values)
    assert set(values) == reference, language
    assert all('%' not in value for value in values.values()), language
print('PASS: 17 mobile storage strings, complete in all 20 languages, no placeholder drift')
