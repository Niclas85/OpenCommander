import io
import hashlib
import threading
import zipfile
from pathlib import Path
from types import SimpleNamespace
import pytest
from opencommander import online_ui, rclone_runtime


def test_browser_login_is_automatic_but_credentials_are_not():
    answer = online_ui.automatic_auth_answer
    assert answer('onedrive', {'Name': 'config_is_local', 'DefaultStr': 'false'}) == 'true'
    assert answer('onedrive', {'Name': 'config_refresh_token'}) == 'true'
    assert answer('iclouddrive', {'Name': 'service'}) == 'drive'
    assert answer('drive', {'Name':'config_change_team_drive','DefaultStr':'true'})=='false'
    for field in ('apple_id', 'password', 'config_2fa', 'config_token', 'config_driveid'):
        assert answer('iclouddrive', {'Name': field}) is None


def test_private_runtime_download_checks_checksum(tmp_path, monkeypatch):
    payload = io.BytesIO()
    with zipfile.ZipFile(payload, 'w') as archive:
        archive.writestr('rclone-v1.75.2-linux-amd64/rclone', b'fixture executable')
        archive.writestr('rclone-v1.75.2-linux-amd64/README.txt', b'fixture license')
    data = payload.getvalue()
    def fetch(url, cancel, destination=None):
        if url.endswith('version.txt'):
            return b'rclone v1.75.2\n'
        if url.endswith('SHA256SUMS'):
            return (hashlib.sha256(data).hexdigest() + '  rclone-v1.75.2-linux-amd64.zip\n').encode()
        destination.write(data)
    monkeypatch.setattr(rclone_runtime, 'runtime_root', lambda: tmp_path / 'runtime')
    monkeypatch.setattr(rclone_runtime.platform, 'machine', lambda: 'x86_64')
    monkeypatch.setattr(rclone_runtime, 'fetch', fetch)
    monkeypatch.setattr(rclone_runtime.subprocess, 'run', lambda *a, **kw: SimpleNamespace(returncode=0))
    path = Path(rclone_runtime.install(threading.Event()))
    assert path.read_bytes() == b'fixture executable'
    assert path.stat().st_mode & 0o777 == 0o700
    assert (path.parent / 'rclone-README.txt').read_text() == 'fixture license'


def test_bad_checksum_never_replaces_existing_runtime(tmp_path, monkeypatch):
    root = tmp_path / 'runtime'; root.mkdir()
    existing = root / 'rclone'; existing.write_bytes(b'previous executable')
    def fetch(url, cancel, destination=None):
        if url.endswith('version.txt'):
            return b'rclone v1.75.2'
        if url.endswith('SHA256SUMS'):
            return ('0' * 64 + '  rclone-v1.75.2-linux-amd64.zip').encode()
        destination.write(b'corrupt archive')
    monkeypatch.setattr(rclone_runtime, 'runtime_root', lambda: root)
    monkeypatch.setattr(rclone_runtime.platform, 'machine', lambda: 'x86_64')
    monkeypatch.setattr(rclone_runtime, 'fetch', fetch)
    with pytest.raises(RuntimeError, match='checksum mismatch'):
        rclone_runtime.install(threading.Event())
    assert existing.read_bytes() == b'previous executable'


def test_icloud_hides_advanced_defaults_but_keeps_password_and_2fa_explicit():
    assert online_ui.automatic_auth_answer('iclouddrive',{'Name':'config_fs_advanced','DefaultStr':'false'})=='false'
    for name in ('apple_id','password','config_2fa'):
        assert online_ui.automatic_auth_answer('iclouddrive',{'Name':name}) is None
