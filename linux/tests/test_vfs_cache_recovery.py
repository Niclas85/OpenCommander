"""Real FUSE recovery test using only a temporary local alias backend."""
import json
from pathlib import Path
import shutil
import subprocess
import time

import pytest
from opencommander import rclone_runtime
from opencommander.desktop import host_environment


def test_pending_full_cache_upload_survives_runtime_upgrade(tmp_path):
    old = shutil.which('rclone')
    new = rclone_runtime.binary()
    unmount = shutil.which('fusermount3')
    if not old or not new or not unmount or not Path('/dev/fuse').exists():
        pytest.skip('rclone/FUSE unavailable')
    backing, mount, cache = (tmp_path / name for name in ('backing', 'mount', 'cache'))
    backing.mkdir(); mount.mkdir()
    config = tmp_path / 'config'
    config.write_text('[fixture]\ntype=alias\nremote=' + str(backing) + '\n')
    config.chmod(0o600)
    def start(binary, delay):
        subprocess.run([binary, 'mount', 'fixture:', str(mount), '--config', str(config),
                        '--cache-dir', str(cache), '--vfs-cache-mode', 'full',
                        '--vfs-write-back', delay, '--daemon', '--daemon-wait', '10s'],
                       capture_output=True, check=True, timeout=15, env=host_environment())
    def stop():
        subprocess.run([unmount, '-u', str(mount)], capture_output=True, check=True, timeout=10)
        # Only the isolated local alias is used. Never recurse through a mounted
        # directory when teardown fails, particularly for account-backed mounts.
        assert not mount.is_mount()
        time.sleep(2)  # Let the old daemon release its cache before another opens it.
    payload = b'pending upload recovery fixture'
    start(old, '1h')
    try:
        (mount / 'probe.txt').write_bytes(payload)
        time.sleep(1)
        assert not (backing / 'probe.txt').exists()
        assert any(json.loads(path.read_text()).get('Dirty')
                   for path in (cache / 'vfsMeta').rglob('*') if path.is_file())
    finally:
        stop()
    start(new, '1s')
    try:
        until = time.monotonic() + 20
        while not (backing / 'probe.txt').exists() and time.monotonic() < until:
            time.sleep(.2)
        assert (backing / 'probe.txt').read_bytes() == payload
    finally:
        stop()
