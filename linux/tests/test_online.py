import json
import os
import subprocess
import threading
from types import SimpleNamespace
import pytest
from opencommander import online_ui


def test_private_config_and_mount_are_separate(tmp_path):
    state = tmp_path / 'state'
    state.mkdir()
    path = online_ui.private_config(state)
    assert path.stat().st_mode & 0o777 == 0o600
    assert path.parent.stat().st_mode & 0o777 == 0o700
    mount = online_ui.mount_path(state, 'oc_example')
    assert state not in mount.parents


def test_password_passed_without_arguments_or_logs(tmp_path, monkeypatch):
    config = online_ui.private_config(tmp_path / 'state')
    calls = []
    class Process:
        returncode = 0
        def __init__(self, command, **kwargs):
            calls.append((command, kwargs))
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def communicate(self, **kwargs): return '{"State":""}', ''
        def poll(self): return 0
    monkeypatch.setattr(online_ui.shutil, 'which', lambda _: '/usr/bin/rclone')
    monkeypatch.setattr(online_ui.subprocess, 'Popen', Process)
    value = online_ui.command_json(config, ['config', 'update', 'test'], threading.Event(), result='private-password')
    assert value == {'State': ''}
    command, arguments = calls[0]
    assert not any('private-password' in part for part in command)
    assert arguments['env']['RCLONE_RESULT'] == 'private-password'
    assert 'shell' not in arguments


def test_ftps_and_ssh_mount_reject_insecure_configuration(tmp_path):
    main = SimpleNamespace(state_dir=tmp_path / 'state')
    config = online_ui.private_config(main.state_dir)
    config.write_text('[oc_test]\ntype = ftp\nexplicit_tls = false\n')
    with pytest.raises(RuntimeError, match='FTPS'):
        online_ui.mount_profile(main, dict(id='oc_test', kind='ftps'), threading.Event())
    with pytest.raises(RuntimeError, match='SSH'):
        online_ui.mount_profile(main, dict(id='oc_test', kind='sftp'), threading.Event())


def test_real_rclone_config_state_machine_without_account(tmp_path):
    if not online_ui.shutil.which('rclone'):
        pytest.skip('rclone not installed')
    config = online_ui.private_config(tmp_path / 'state')
    first = online_ui.command_json(config, ['config', 'create', 'oc_fixture', 'onedrive', '--non-interactive'], threading.Event())
    assert first['Option']['Name'] == 'config_is_local'
    second = online_ui.command_json(config, ['config', 'update', 'oc_fixture', '--continue', '--state', first['State'], '--non-interactive'],
                                    threading.Event(), result='false')
    assert second['Option']['Name'] == 'config_token'
    assert config.stat().st_mode & 0o777 == 0o600


def test_cancel_before_start(tmp_path):
    config = online_ui.private_config(tmp_path / 'state')
    cancel = threading.Event(); cancel.set()
    if not online_ui.shutil.which('rclone'):
        pytest.skip('rclone not installed')
    with pytest.raises(RuntimeError, match='Cancelled'):
        online_ui.command_json(config, ['config', 'providers'], cancel)


def test_rclone_mount_transfer_trash_and_recovery(tmp_path):
    from pathlib import Path
    from opencommander.operations import FileEngine
    if not Path('/dev/fuse').exists() or not online_ui.shutil.which('rclone') or not online_ui.shutil.which('fusermount3'):
        pytest.skip('FUSE/rclone unavailable')
    state, backing = tmp_path / 'state', tmp_path / 'backing'
    state.mkdir(); backing.mkdir()
    main = SimpleNamespace(state_dir=state)
    config = online_ui.private_config(state)
    config.write_text('[oc_fixture]\ntype = alias\nremote = ' + str(backing) + '\n')
    from PySide6.QtCore import QSize
    from PySide6.QtGui import QImage, QColor
    from opencommander.media import online_image
    from opencommander.filesystem import Entry
    photo = backing / 'fixture.JPG'
    image = QImage(120, 80, QImage.Format_RGB32); image.fill(QColor('green'))
    assert image.save(str(photo))
    mount = None
    try:
        mount = online_ui.mount_profile(main, dict(id='oc_fixture', kind='alias'), threading.Event())
        from opencommander import provider_mounts
        provider_mounts._roots.discard(mount)
        assert not provider_mounts.managed(mount)
        assert provider_mounts.same_mount(mount / 'a', mount / 'b')
        remote_photo = mount / photo.name
        preview = online_image(Entry(photo.name, remote_photo, False, photo.stat().st_size), QSize(96, 64), threading.Event())
        assert not preview.isNull()
        source = tmp_path / 'fixture.txt'; source.write_text('generated FUSE fixture')
        engine = FileEngine(state)
        engine.transfer([source], mount)
        assert (backing / source.name).read_text() == source.read_text()
        # Same-name transfer must keep both, not replace the original.
        engine.transfer([source], mount)
        assert (backing / 'fixture (2).txt').read_text() == source.read_text()
        engine.undo()
        assert not (backing / 'fixture (2).txt').exists()
        engine.trash([mount / source.name])
        assert not (backing / source.name).exists()
        engine.undo()
        assert (backing / source.name).read_text() == source.read_text()
    finally:
        if mount is not None:
            result = subprocess.run(['fusermount3', '-u', str(mount)], capture_output=True, timeout=10)
            assert result.returncode == 0


@pytest.mark.parametrize('host,port', [('-oBad', 22), ('host;cmd', 22), ('host\ncmd', 22), ('valid.host', 0)])
def test_hostkey_lookup_rejects_argument_injection(host, port):
    with pytest.raises(ValueError):
        online_ui.ssh_fingerprints(host, port)


def test_changed_hostkey_is_not_added(tmp_path, monkeypatch):
    path = tmp_path / 'known_hosts'
    original = 'example ssh-ed25519 original-key\n'
    path.write_text(original)
    monkeypatch.setattr(online_ui.subprocess, 'run', lambda *args, **kwargs:
                        SimpleNamespace(returncode=0, stdout=original.encode()))
    with pytest.raises(RuntimeError, match='changed'):
        online_ui.save_hostkeys(path, b'example ssh-ed25519 changed-key\n')
    assert path.read_text() == original


@pytest.mark.parametrize('url', ['https://example.com/auth?state=' + 'a' * 22,
    'http://127.0.0.1:53682/auth?state=short', 'http://127.0.0.1:53682/auth?state=' + 'a' * 23,
    'http://127.0.0.1:1234/auth?state=' + 'a' * 22])
def test_browser_url_rejects_unexpected_endpoints(url):
    assert online_ui.oauth_browser_url(url) is None


def test_browser_url_accepts_only_local_oauth():
    url = 'http://127.0.0.1:53682/auth?state=' + 'aB_9-' * 4 + 'aB'
    assert online_ui.oauth_browser_url(('NOTICE: Please go to: ' + url + '\n').encode()) == url


def test_real_oauth_delivers_browser_url_without_external_launch(tmp_path, monkeypatch):
    if not online_ui.rclone_runtime.binary():
        pytest.skip('rclone unavailable')
    config = online_ui.private_config(tmp_path / 'state')
    first = online_ui.command_json(config, ['config', 'create', 'oc_fixture', 'onedrive', '--non-interactive'], threading.Event())
    # A fixture launcher must never be called: the GUI owns browser activation.
    marker = tmp_path / 'external-launch'
    launcher = tmp_path / 'xdg-open'
    launcher.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\n')
    launcher.chmod(0o700)
    monkeypatch.setenv('PATH', str(tmp_path) + ':' + os.environ.get('PATH', ''))
    cancel = threading.Event()
    received = []
    def browser(url):
        received.append(url)
        cancel.set()
    with pytest.raises(RuntimeError, match='Cancelled'):
        online_ui.command_json(config, ['config', 'update', 'oc_fixture', '--continue', '--state', first['State'], '--non-interactive'],
                               cancel, result='true', timeout=10, browser_callback=browser)
    assert len(received) == 1
    assert online_ui.oauth_browser_url(received[0]) == received[0]
    assert not marker.exists()


def test_managed_fuse_record_waits_for_stable_verification(tmp_path, monkeypatch):
    from opencommander import operations, provider_mounts
    engine = operations.FileEngine(tmp_path / 'state')
    target = tmp_path / 'mount' / 'file'
    monkeypatch.setattr(provider_mounts, 'managed', lambda path: path == target)
    snapshots = iter(['initial-attributes', 'refreshed-attributes', 'refreshed-attributes'])
    monkeypatch.setattr(operations, 'safe_snapshot', lambda _: next(snapshots))
    operation = engine.begin('move')
    engine.record(operation, tmp_path / 'source', target, 'move')
    assert operation['records'][0]['snapshot'] == 'refreshed-attributes'


def test_verification_rejects_change_during_content_read(tmp_path, monkeypatch):
    from pathlib import Path
    from opencommander import operations
    target = tmp_path / 'file'
    target.write_text('initial')
    original = Path.open
    def changed_open(path, *args, **kwargs):
        if path == target and args == ('rb',):
            with original(path, 'w') as stream:
                stream.write('changed content and size')
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, 'open', changed_open)
    with pytest.raises(operations.SafetyError, match='changed while verifying'):
        operations.fingerprint(target)


def test_rclone_detection_respects_other_nested_mounts(tmp_path, monkeypatch):
    from pathlib import Path
    from opencommander import provider_mounts
    monkeypatch.setattr(provider_mounts, '_roots', set())
    data = ('1 0 0:1 / / rw - ext4 /dev/root rw\n'
            '2 1 0:2 / /cloud rw - fuse.rclone remote: rw\n'
            '3 2 0:3 / /cloud/nested rw - ext4 /dev/other rw\n')
    real_read = Path.read_text
    monkeypatch.setattr(Path, 'read_text', lambda path, *args, **kwargs: data if str(path) == '/proc/self/mountinfo' else real_read(path, *args, **kwargs))
    assert provider_mounts.same_mount(Path('/cloud/a'), Path('/cloud/b'))
    assert not provider_mounts.same_mount(Path('/cloud/a'), Path('/cloud/nested/b'))
    assert not provider_mounts.same_mount(Path('/cloud/a'), Path('/elsewhere/b'))


def test_rclone_rename_fallback_preserves_existing_target(tmp_path, monkeypatch):
    import errno
    from opencommander import operations, provider_mounts
    class Rename:
        def __call__(self, *args): return -1
    monkeypatch.setattr(operations.ctypes, 'CDLL', lambda *args, **kwargs: SimpleNamespace(renameat2=Rename()))
    monkeypatch.setattr(operations.ctypes, 'get_errno', lambda: errno.EINVAL)
    monkeypatch.setattr(provider_mounts, 'same_mount', lambda *args: True)
    source, target = tmp_path / 'source', tmp_path / 'target'
    source.write_text('original source'); target.write_text('original target')
    with pytest.raises(FileExistsError):
        operations.rename_new(source, target)
    assert source.read_text() == 'original source'
    assert target.read_text() == 'original target'
    target.unlink()
    operations.rename_new(source, target)
    assert target.read_text() == 'original source'
    assert not source.exists()


def test_rclone_rename_fails_closed_when_target_cannot_be_checked(tmp_path, monkeypatch):
    import errno
    from pathlib import Path
    from opencommander import operations, provider_mounts
    class Rename:
        def __call__(self, *args): return -1
    monkeypatch.setattr(operations.ctypes, 'CDLL', lambda *args, **kwargs: SimpleNamespace(renameat2=Rename()))
    monkeypatch.setattr(operations.ctypes, 'get_errno', lambda: errno.EINVAL)
    monkeypatch.setattr(provider_mounts, 'same_mount', lambda *args: True)
    source, target = tmp_path / 'source', tmp_path / 'target'
    source.write_text('source retained')
    real_stat = Path.lstat
    def denied(path, *args, **kwargs):
        if path == target:
            raise PermissionError('Target cannot be checked')
        return real_stat(path, *args, **kwargs)
    monkeypatch.setattr(Path, 'lstat', denied)
    with pytest.raises(PermissionError):
        operations.rename_new(source, target)
    assert source.read_text() == 'source retained'


def test_gvfs_provider_detection_limits_rename_to_same_share(monkeypatch):
    from pathlib import Path
    from opencommander import provider_mounts
    monkeypatch.setattr(provider_mounts, '_roots', set())
    data = ('1 0 0:1 / / rw - ext4 /dev/root rw\n'
            '2 1 0:2 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw\n'
            '3 2 0:3 / /run/user/1000/gvfs/smb-share:server=test,share=a/nested rw - ext4 /dev/other rw\n')
    real_read = Path.read_text
    monkeypatch.setattr(Path, 'read_text', lambda path, *a, **kw: data if str(path) == '/proc/self/mountinfo' else real_read(path, *a, **kw))
    root = Path('/run/user/1000/gvfs')
    a = root / 'smb-share:server=test,share=a'
    b = root / 'smb-share:server=test,share=b'
    assert provider_mounts.provider_mount(a / 'file') == (a, '2')
    assert provider_mounts.same_mount(a / 'temporary/file', a / 'final')
    assert not provider_mounts.same_mount(a / 'file', b / 'file')
    assert not provider_mounts.same_mount(a / 'file', a / 'nested/file')
    assert provider_mounts.rclone_mount(a / 'file') is None
    assert provider_mounts.provider_mount(root) is None


def test_cloud_list_direct_metadata_and_cancellation(tmp_path, monkeypatch):
    import json
    import threading
    from types import SimpleNamespace
    from pathlib import Path
    script = tmp_path / 'rclone-fixture'
    script.write_text('#!/usr/bin/python3\nimport json\nprint(json.dumps(['
                      '{"Name":"photo.jpg","IsDir":False,"Size":123,"ModTime":"2026-10-10T10:00:00Z"},'
                      '{"Name":"folder","IsDir":True,"Size":-1,"ModTime":""},'
                      '{"Name":"../escape","IsDir":False,"Size":1}]))\n')
    script.chmod(0o700)
    monkeypatch.setattr(online_ui.rclone_runtime, 'binary', lambda: str(script))
    main = SimpleNamespace(state_dir=tmp_path / 'state')
    profile = dict(id='oc_fixture', kind='onedrive')
    root = online_ui.mount_path(main.state_dir, profile['id'])
    cancel = threading.Event()
    entries = online_ui.list_cloud(main, profile, root, cancel)
    assert [entry.name for entry in entries] == ['photo.jpg', 'folder']
    assert entries[0].path == root / 'photo.jpg'
    assert entries[0].size == 123 and entries[0].modified > 0
    assert entries[1].size == 0 and entries[1].directory
    cancel.set()
    with pytest.raises(RuntimeError, match='Abgebrochen'):
        online_ui.list_cloud(main, profile, root, cancel)
    cancel.clear()
    from opencommander.cloud_listing import CloudListings
    main.cloud_listings = CloudListings()  # Test a first load without a usable cached listing.
    script.write_text('#!/usr/bin/python3\nimport time\ntime.sleep(60)\n')
    with pytest.raises(RuntimeError, match='rechtzeitig'):
        online_ui.list_cloud(main, profile, root, cancel, timeout=.2)
    main.cloud_listings = CloudListings()
    script.write_text('#!/usr/bin/python3\nimport sys\nprint("401 unauthorized SECRET-TOKEN",file=sys.stderr)\nsys.exit(1)\n')
    with pytest.raises(RuntimeError) as error:
        online_ui.list_cloud(main, profile, root, cancel)
    assert 'Anmeldung' in str(error.value)
    assert 'SECRET-TOKEN' not in str(error.value)


def test_remote_alias_detected_without_probing_provider(tmp_path, monkeypatch):
    from opencommander.filesystem import remote_location
    from pathlib import Path
    mount = tmp_path / 'cloud'
    alias = tmp_path / 'OneDrive'
    alias.symlink_to(mount)
    data = f'1 0 0:1 / {mount} rw - fuse.rclone oc_fixture: rw\n'
    real_read, real_link = Path.read_text, os.readlink
    monkeypatch.setattr(Path, 'read_text', lambda path, *a, **kw: data if str(path) == '/proc/self/mountinfo' else real_read(path, *a, **kw))
    def readlink(path):
        assert mount != Path(path) and mount not in Path(path).parents, 'Must not probe the provider'
        return real_link(path)
    monkeypatch.setattr(os, 'readlink', readlink)
    assert remote_location(alias / 'folder/photo.jpg')
    assert not remote_location(tmp_path / 'local')


def test_parallel_mount_requests_launch_one_daemon(tmp_path, monkeypatch):
    import concurrent.futures
    from opencommander import provider_mounts
    main = SimpleNamespace(state_dir=tmp_path / 'state')
    config = online_ui.private_config(main.state_dir)
    config.write_text('[oc_parallel]\ntype = drive\n')
    profile = dict(id='oc_parallel', kind='drive')
    entered, release, mounted = threading.Event(), threading.Event(), threading.Event()
    calls = []
    monkeypatch.setattr(online_ui, 'mount_path', lambda *_: tmp_path / 'mount')
    monkeypatch.setattr(online_ui, 'remote_location', lambda _: mounted.is_set())
    monkeypatch.setattr(online_ui.rclone_runtime, 'binary', lambda: '/fixture/rclone')
    monkeypatch.setattr(online_ui.shutil, 'which', lambda _: '/fixture/fusermount')
    monkeypatch.setattr(online_ui.server, 'credential_environment', lambda *_: {})
    monkeypatch.setattr(provider_mounts, 'register', lambda *_: None)
    def mount(*args, **kwargs):
        calls.append(args)
        entered.set()
        assert release.wait(5)
        mounted.set()
        return SimpleNamespace(returncode=0)
    monkeypatch.setattr(online_ui.subprocess, 'run', mount)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(online_ui.mount_profile, main, profile, threading.Event())
        assert entered.wait(5)
        second = pool.submit(online_ui.mount_profile, main, profile, threading.Event())
        release.set()
        assert first.result(timeout=5) == second.result(timeout=5)
    assert len(calls) == 1


def test_waiting_for_same_mount_is_independently_cancellable(tmp_path, monkeypatch):
    import concurrent.futures
    main = SimpleNamespace(state_dir=tmp_path)
    profile = dict(id='oc_cancel', kind='drive')
    entered, release = threading.Event(), threading.Event()
    def mount(*args):
        entered.set()
        assert release.wait(5)
        return tmp_path
    monkeypatch.setattr(online_ui, '_mount_profile', mount)
    cancel = threading.Event()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(online_ui.mount_profile, main, profile, threading.Event())
        assert entered.wait(5)
        second = pool.submit(online_ui.mount_profile, main, profile, cancel)
        try:
            cancel.set()
            with pytest.raises(RuntimeError, match='Cancelled'):
                second.result(timeout=1)
        finally:
            release.set()
        assert first.result(timeout=5) == tmp_path
