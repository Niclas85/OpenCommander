"""Detect duplicate literal keys that Swift otherwise traps on at app startup."""
from collections import Counter
from pathlib import Path
import re

source = (Path(__file__).resolve().parents[1] / "ios/OpenCommander/Localization.swift").read_text()
blocks = list(re.finditer(r'^        "([^\"]+)": \[\n(.*?)^        \],', source, re.M | re.S))
assert blocks, "No localization dictionaries detected"
for block in blocks:
    keys = re.findall(r'^            "([^\"]+)":', block.group(2), re.M)
    duplicates = sorted(key for key, count in Counter(keys).items() if count > 1)
    assert not duplicates, (block.group(1), "duplicate keys", duplicates)
    assert keys, (block.group(1), "empty dictionary")
print(f"PASS: {len(blocks)} Swift localization dictionaries contain no duplicate keys")
