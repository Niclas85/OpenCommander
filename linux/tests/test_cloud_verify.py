import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import threading

import pytest
from opencommander import cloud_verify
from opencommander.operations import FileEngine, Cancelled


def test_pending_or_present_local_cache_never_allows_remote_proof(tmp_path, monkeypatch):
    from opencommander import external_cloud, provider_mounts
    mount = tmp_path / 'mount';mount.mkdir()
    cache = tmp_path / 'cache'
    namespace = cache / 'vfsMeta/gdrive';namespace.mkdir(parents=True)
    profile = dict(kind='drive', mount_root=str(mount), remote_base='gdrive:', config_path=str(tmp_path / 'config'))
    process = tmp_path / '123';process.mkdir()
    (process / 'cmdline').write_bytes(('rclone\0mount\0gdrive:\0'+str(mount)+'\0--cache-dir\0'+str(cache)+'\0--vfs-cache-mode\0full\0').encode())
    real_path = Path
    monkeypatch.setattr(cloud_verify, 'Path', lambda value: tmp_path if str(value) == '/proc' else real_path(value))
    monkeypatch.setattr(external_cloud, 'discover', lambda: [profile])
    monkeypatch.setattr(provider_mounts, 'rclone_mount', lambda path: (mount, 'fixture'))
    path = mount / 'saved.jpg'
    assert cloud_verify.evicted_target(path) is not None
    meta = namespace / 'saved.jpg';meta.write_text('{"Dirty":true}')
    assert cloud_verify.evicted_target(path) is None
    meta.unlink()
    data = cache / 'vfs/gdrive/saved.jpg';data.parent.mkdir(parents=True);data.write_bytes(b'pending')
    assert cloud_verify.evicted_target(path) is None


@pytest.mark.parametrize('value', ['valid', 'missing', 'wrong_size', 'directory'])
def test_server_proof_requires_exact_size_regular_file_and_sha256(tmp_path, monkeypatch, value):
    engine = FileEngine(tmp_path / 'state')
    digest = hashlib.sha256(b'fixture').hexdigest()
    row = dict(IsDir=value == 'directory', Size=8 if value == 'wrong_size' else 7,
               Hashes={} if value == 'missing' else {'sha256':digest})
    script = tmp_path / 'rclone';script.write_text('#!/usr/bin/python3\nprint('+repr(json.dumps(row))+')\n');script.chmod(0o700)
    profile = dict(config_path=str(tmp_path / 'config'), remote_base='gdrive:')
    monkeypatch.setattr(cloud_verify, 'evicted_target', lambda path: (profile, 'saved.jpg', (tmp_path / 'missing_meta',)))
    monkeypatch.setattr(cloud_verify.rclone_runtime, 'binary', lambda: str(script))
    assert cloud_verify.server_digest(engine, tmp_path / 'saved.jpg', 7) == (digest if value == 'valid' else None)


def test_server_proof_can_be_cancelled_before_network(tmp_path, monkeypatch):
    engine = FileEngine(tmp_path / 'state');engine.cancel.set()
    monkeypatch.setattr(cloud_verify, 'evicted_target', lambda p: ({'config_path':'fixture','remote_base':'gdrive:'}, 'saved.jpg', (tmp_path / 'missing',)))
    monkeypatch.setattr(cloud_verify.rclone_runtime, 'binary', lambda: '/fixture')
    with pytest.raises(Cancelled):
        cloud_verify.server_digest(engine, tmp_path / 'saved.jpg', 7)


def test_new_local_cache_entry_during_query_invalidates_remote_proof(tmp_path, monkeypatch):
    engine = FileEngine(tmp_path / 'state')
    guard = tmp_path / 'metadata'
    digest = hashlib.sha256(b'fixture').hexdigest()
    script = tmp_path / 'rclone'
    script.write_text('#!/usr/bin/python3\nfrom pathlib import Path\nPath('+repr(str(guard))+').write_text("pending")\nprint('+repr(json.dumps(dict(IsDir=False, Size=7, Hashes={'sha256':digest})))+')\n')
    script.chmod(0o700)
    monkeypatch.setattr(cloud_verify, 'evicted_target', lambda p: ({'config_path':'fixture','remote_base':'gdrive:'}, 'saved.jpg', (guard,)))
    monkeypatch.setattr(cloud_verify.rclone_runtime, 'binary', lambda: str(script))
    assert cloud_verify.server_digest(engine, tmp_path / 'saved.jpg', 7) is None


def test_remote_verification_can_be_cancelled_while_provider_hangs(tmp_path, monkeypatch):
    import time
    engine = FileEngine(tmp_path / 'state')
    script = tmp_path / 'rclone';script.write_text('#!/usr/bin/python3\nimport time\ntime.sleep(30)\n');script.chmod(0o700)
    monkeypatch.setattr(cloud_verify, 'evicted_target', lambda p: ({'config_path':'fixture','remote_base':'gdrive:'}, 'saved.jpg', (tmp_path / 'missing',)))
    monkeypatch.setattr(cloud_verify.rclone_runtime, 'binary', lambda: str(script))
    timer = threading.Timer(.2,engine.cancel.set);timer.start()
    started = time.monotonic()
    try:
        with pytest.raises(Cancelled):
            cloud_verify.server_digest(engine,tmp_path / 'saved.jpg',7)
    finally:
        timer.cancel()
    assert time.monotonic()-started < 2
