"""Verify frozen helper I/O and dependencies using a disposable local fixture."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

bundle = Path(sys.argv[1])
helper = bundle / 'helpers/OpenCommanderHelper.exe'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / 'Grüße 日本語.bin'
    source.write_bytes(bytes(range(256)) * 100)
    scan = subprocess.run([str(helper), 'windows_bridge'], input=json.dumps(dict(action='scan', id=str(root))),
                          text=True, capture_output=True, timeout=20, check=True)
    assert json.loads(scan.stdout)['locations'][0]['name'] == source.name
    target = root / 'copy'
    fetch = subprocess.run([str(helper), 'media_fetch'], input=json.dumps(dict(source=str(source), target=str(target), limit=30000)),
                           text=True, capture_output=True, timeout=20, check=True)
    assert json.loads(fetch.stdout.splitlines()[-1])['done']
    assert source.read_bytes() == target.read_bytes()
    backend = subprocess.run([str(bundle / 'tools/rclone.exe'), 'version'], capture_output=True, check=True, timeout=10)
    assert b'rclone v' in backend.stdout
print('PASS: packaged Windows helper, Unicode listing, binary media download and rclone runtime')
