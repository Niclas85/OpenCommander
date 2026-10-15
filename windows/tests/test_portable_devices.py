"""Native COM checks and filesystem-protocol tests; no real device data touched."""
import base64
from contextlib import contextmanager
import ctypes
import io
import json
from pathlib import Path
import subprocess
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import uuid

import pytest
from opencommander.device_dav import DeviceServer, Namespace, component, path_parts
from opencommander import windows_wpd as wpd


class TestDevice:
    __test__ = False

    def __init__(self):
        self.rows = {'storage': dict(id='storage', parent='DEVICE', name='Internal Storage',
                     directory=True, storage=True, size=0, modified=1700000000)}
        self.data = {}
        self.fail_move = False
        self.fail_rename = False
        self.fail_create = False
        self.disconnect = False

    def children(self, identifier):
        if self.disconnect:
            raise OSError('Device disconnected')
        return [dict(row) for row in self.rows.values() if row['parent'] == identifier]

    def info(self, identifier):
        return dict(self.rows[identifier])

    def mkdir(self, parent, name):
        return self.add(parent, name, None)

    def add(self, parent, name, data):
        identifier = uuid.uuid4().hex
        self.rows[identifier] = dict(id=identifier, parent=parent, name=name, directory=data is None,
                                    storage=False, size=len(data or b''), modified=1700000000)
        if data is not None:
            self.data[identifier] = data
        return identifier

    def create(self, parent, name, stream, size):
        if self.fail_create:
            raise PermissionError('Device is read-only')
        data = stream.read()
        assert len(data) == size
        return self.add(parent, name, data)

    @contextmanager
    def read(self, identifier):
        if self.disconnect:
            raise OSError('Device disconnected')
        yield io.BytesIO(self.data[identifier])

    def move(self, identifier, parent):
        if self.fail_move:
            raise OSError('Unsupported device move')
        self.rows[identifier]['parent'] = parent

    def rename(self, identifier, name):
        if self.fail_rename:
            raise OSError('Unsupported rename')
        self.rows[identifier]['name'] = name

    def delete(self, identifier):
        self.rows.pop(identifier)
        self.data.pop(identifier, None)


@pytest.fixture
def device_server(tmp_path):
    cache = tmp_path / 'private'
    cache.mkdir()
    device = TestDevice()
    with DeviceServer(device, 'test-' + uuid.uuid4().hex, cache) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            yield server, device
        finally:
            server.shutdown()
            worker.join(timeout=3)
            assert not worker.is_alive()


def request(server, path='/', method='GET', data=None, headers=None):
    auth = base64.b64encode(('OpenCommander:' + server.password).encode()).decode()
    headers = dict({'Authorization': 'Basic ' + auth}, **(headers or {}))
    return urlopen(Request(f'http://127.0.0.1:{server.server_port}' + path,
                           method=method, data=data, headers=headers), timeout=5)


def test_real_wpd_com_values_and_64_bit_abi():
    assert (ctypes.sizeof(wpd.GUID), ctypes.sizeof(wpd.Key), ctypes.sizeof(wpd.Variant)) == (16, 20, 24)
    with wpd.apartment(), wpd.Values.new() as values:
        values.set_string(wpd.KEYS['name'], 'Grüße 日本語')
        values.set_number(wpd.KEYS['size'], 2**40 + 123)
        values.set_guid(wpd.KEYS['type'], wpd.FOLDER)
        assert values.string(wpd.KEYS['name']) == 'Grüße 日本語'
        assert values.number(wpd.KEYS['size']) == 2**40 + 123
        assert values.guid(wpd.KEYS['type']) == wpd.FOLDER
        with wpd.object_ids('synthetic-object') as identifiers:
            count = wpd.U32()
            identifiers.call(3, (ctypes.POINTER(wpd.U32),), (ctypes.byref(count),))
            assert count.value == 1


def test_frozen_device_helper_uses_the_shipped_rclone_without_download(tmp_path, monkeypatch):
    import sys
    from opencommander import rclone_runtime
    helper = tmp_path / 'helpers/OpenCommanderHelper.exe'
    backend = tmp_path / 'tools/rclone.exe'
    backend.parent.mkdir()
    backend.write_bytes(b'packaged runtime fixture')
    monkeypatch.setattr(sys, 'frozen', True, raising=False)
    monkeypatch.setattr(sys, 'executable', str(helper))
    assert rclone_runtime.binary() == str(backend)


@pytest.mark.parametrize('name', ['CON', 'NUL.txt', 'a:b', 'a/b', 'a\\b', 'a.', 'a ', 'x%2Fy', 'Grüße 日本語'])
def test_device_names_are_visible_and_legal_on_windows(name):
    from opencommander.platform_support import validate_component
    result = component(name)
    validate_component(result)
    assert '/' not in result and '\\' not in result
    assert path_parts('/' + __import__('urllib.parse', fromlist=['quote']).quote(result, safe='')) == [result]


@pytest.mark.parametrize('path', ['/../x', '/x/../y', '/x//y', '/%2e%2e/x', '/x%5cy', '/x%00', '//server/x', '/x?password=y'])
def test_device_path_escape_is_rejected(path):
    with pytest.raises(ValueError):
        path_parts(path)


def test_duplicate_case_names_never_select_the_wrong_object():
    device = TestDevice()
    device.add('storage', 'Photo.jpg', b'one')
    device.add('storage', 'photo.jpg', b'two')
    namespace = Namespace(device)
    rows = namespace.children(namespace.resolve(['Internal Storage']))
    assert len({row['display'].casefold() for row in rows}) == 2
    for row in rows:
        assert namespace.resolve(['Internal Storage', row['display']])['id'] == row['id']
    with pytest.raises(FileNotFoundError):
        namespace.resolve(['Internal Storage', 'photo.jpg'])


def test_protocol_real_bytes_range_unicode_and_no_overwrite(device_server):
    server, device = device_server
    data = bytes(range(256)) * 8192
    from urllib.parse import quote
    path = '/Internal%20Storage/' + quote('Grüße 日本語.bin')
    with request(server, path, 'PUT', data) as response:
        assert response.status == 201
    with request(server, path) as response:
        assert response.read() == data
    with request(server, path, headers={'Range': 'bytes=250-520'}) as response:
        assert response.status == 206 and response.read() == data[250:521]
    with pytest.raises(HTTPError) as error:
        request(server, path, 'PUT', b'overwritten')
    assert error.value.code == 412
    with request(server, path) as response:
        assert response.read() == data
    assert list(server.cache.iterdir()) == []


def test_no_credentials_or_browser_origin_cannot_read_or_write(device_server):
    server, device = device_server
    address = f'http://127.0.0.1:{server.server_port}'
    for method in ('GET', 'PUT', 'DELETE', 'PROPFIND'):
        with pytest.raises(HTTPError) as error:
            urlopen(Request(address + '/Internal%20Storage/x', method=method), timeout=5)
        assert error.value.code == 401
    with pytest.raises((HTTPError, ConnectionError)) as error:
        request(server, '/Internal%20Storage/x', 'PUT', b'no', {'Origin': 'https://example.org'})
    # Windows may reset a refused upload while its unread body is in flight.
    if isinstance(error.value, HTTPError):
        assert error.value.code == 403
    assert len(device.rows) == 1


def test_winfsp_device_mount_uses_shared_file_engine_and_persistent_undo(device_server, tmp_path):
    import os
    import secrets
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\WinFsp', 0,
                            winreg.KEY_READ | winreg.KEY_WOW64_32KEY):
            pass
    except OSError:
        pytest.skip('WinFsp is required for the real filesystem integration check')
    from opencommander import provider_mounts, windows_mounts, windows_native
    from opencommander.operations import FileEngine
    server, device = device_server
    binary = Path(__file__).resolve().parents[1] / 'build/runtime/rclone.exe'
    assert binary.is_file()
    config = tmp_path / 'mount.conf'
    obscured = subprocess.run([str(binary), 'obscure', '-'], input=server.password + '\n',
                              text=True, capture_output=True, check=True).stdout.strip()
    config.write_text(f'[test]\ntype=webdav\nvendor=other\nurl=http://127.0.0.1:{server.server_port}/\nuser=OpenCommander\npass={obscured}\n')
    root = tmp_path / 'mount'
    import socket
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    password = secrets.token_urlsafe(32)
    command = [str(binary), '--config', str(config), 'mount', 'test:', str(root),
                                '--vfs-cache-mode', 'off', '--dir-cache-time', '1s', '--attr-timeout', '0s',
                                '--fuse-flag', '-oVolumeSerialNumber=1234abcd',
                                '--rc', '--rc-addr', f'127.0.0.1:{port}']
    environment = dict(os.environ, RCLONE_RC_USER='OpenCommander', RCLONE_RC_PASS=password)
    process = subprocess.Popen(command,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                               env=environment)
    ready = False
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and process.poll() is None:
            if root.is_mount() or root.is_junction():
                ready = True
                break
            time.sleep(.1)
        assert ready, process.stderr.read().decode() if process.poll() is not None else 'Mount timed out'
        provider_mounts.register(root, portable=True)
        windows_native.keyring(root, 'mount-control', 'store', json.dumps(dict(port=port, password=password)))
        source = tmp_path / 'Grüße 日本語.bin'
        payload = bytes(range(256)) * 4096
        source.write_bytes(payload)
        engine = FileEngine(tmp_path / 'recovery')
        storage = root / 'Internal Storage'
        engine.transfer([source], storage)
        uploaded = storage / source.name
        assert uploaded.read_bytes() == payload
        engine.rename(uploaded, 'renamed.bin')
        before = (storage / 'renamed.bin').stat()
        time.sleep(1.1)  # Expire the actual VFS directory cache before verification.
        assert (storage / 'renamed.bin').read_bytes() == payload
        restored = FileEngine(engine.state_dir)
        after = (storage / 'renamed.bin').stat()
        from opencommander.operations import fingerprint
        assert restored.history[-1]['records'][0]['snapshot'] == fingerprint(storage / 'renamed.bin', ignore_inode=True), (
            'provider metadata', (before.st_dev, before.st_mode, before.st_mtime_ns, before.st_size),
            (after.st_dev, after.st_mode, after.st_mtime_ns, after.st_size))
        restored.undo()
        assert uploaded.read_bytes() == payload
        destination = tmp_path / 'download'
        destination.mkdir()
        restored.transfer([uploaded], destination)
        assert (destination / source.name).read_bytes() == payload
        restored.trash([uploaded])
        assert not uploaded.exists()
        restored.undo()
        assert uploaded.read_bytes() == payload
        from opencommander.operations import Cancelled
        paused_source = tmp_path / 'paused.bin'
        paused_source.write_bytes(payload * 2)
        paused_job = restored.transfers.create([paused_source], storage, 'keep')
        def pause_after_block(count, _):
            if count >= 1024 * 1024:
                restored.pause.set()
                restored.cancel.set()
        restored.progress = pause_after_block
        with pytest.raises(Cancelled):
            restored.transfer([paused_source], storage, job_id=paused_job['id'])
        resumed = FileEngine(engine.state_dir)
        resumed.transfer([paused_source], storage, job_id=paused_job['id'])
        resumed_bytes = (storage / paused_source.name).read_bytes()
        paused_object = server.namespace.resolve(['Internal Storage', paused_source.name])
        assert resumed_bytes == paused_source.read_bytes(), (len(resumed_bytes), paused_source.stat().st_size,
            len(device.data[paused_object['id']]), paused_object['size'])
        assert not resumed.transfers.jobs()
        moving_source = tmp_path / 'move-to-device.bin'
        moving_source.write_bytes(payload)
        move_job = resumed.transfers.create([moving_source], storage, 'keep', move=True)
        move_operation = resumed.transfer([moving_source], storage, move=True, job_id=move_job['id'])
        assert not moving_source.exists()
        assert (storage / moving_source.name).read_bytes() == payload
        resumed.undo(move_operation['id'])
        assert moving_source.read_bytes() == payload
        restored = resumed
        # A new WinFsp session must retain the same device identity and accept
        # only the unchanged bytes recorded before disconnect.
        restored.rename(uploaded, 'after-reconnect.bin')
        windows_mounts.unmount(root)
        ready = False
        process.wait(timeout=10)
        process.stderr.close()
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=environment)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and process.poll() is None:
            if root.is_mount() or root.is_junction():
                ready = True
                break
            time.sleep(.1)
        assert ready
        provider_mounts.register(root, portable=True)
        windows_native.keyring(root, 'mount-control', 'store', json.dumps(dict(port=port, password=password)))
        reconnected = FileEngine(engine.state_dir)
        reconnected.undo()
        assert uploaded.read_bytes() == payload
        reconnected.rename(uploaded, 'external-change.bin')
        changed = server.namespace.resolve(['Internal Storage', 'external-change.bin'])
        device.data[changed['id']] = bytes(value ^ 255 for value in payload)
        from opencommander.operations import SafetyError
        with pytest.raises(SafetyError, match='file changed'):
            reconnected.undo()
        assert (storage / 'external-change.bin').read_bytes() != payload
        assert source.read_bytes() == payload
        # Some cameras allow browsing but reject file creation. A failed device
        # write must not be reported as a successful upload or remove its source.
        device.fail_create = True
        rejected_source = tmp_path / 'read-only-device.bin'
        rejected_source.write_bytes(payload)
        with pytest.raises((OSError, SafetyError)):
            FileEngine(engine.state_dir).transfer([rejected_source], storage)
        assert rejected_source.read_bytes() == payload
        with pytest.raises((OSError, SafetyError)):
            FileEngine(engine.state_dir).transfer([rejected_source], storage, move=True)
        assert rejected_source.read_bytes() == payload
        windows_mounts.unmount(root)
        ready = False
        process.wait(timeout=10)
        assert not root.is_junction()
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=10)
        process.stderr.close()
        provider_mounts._roots.discard(root)
        provider_mounts._portable_roots.discard(root)
        windows_native.keyring(root, 'mount-control', 'clear')


def test_storage_deletion_and_recursive_move_rejected(device_server):
    server, device = device_server
    namespace = server.namespace
    namespace.mkdir(['Internal Storage', 'folder'])
    with pytest.raises(PermissionError):
        namespace.move(['Internal Storage', 'folder'], ['Internal Storage', 'folder', 'nested'])
    with pytest.raises(PermissionError):
        namespace.delete(['Internal Storage'])
    with pytest.raises(PermissionError):
        namespace.mkdir(['new storage'])
    assert len(device.rows) == 2


def test_unsupported_move_preserves_source_and_conflicts_preserve_both(device_server):
    server, device = device_server
    namespace = server.namespace
    origin = device.add('storage', 'source', b'original')
    occupied = device.add('storage', 'occupied', b'previous')
    directory = device.add('storage', 'folder', None)
    with pytest.raises(FileExistsError):
        namespace.move(['Internal Storage', 'source'], ['Internal Storage', 'occupied'])
    device.fail_move = True
    with pytest.raises(OSError):
        namespace.move(['Internal Storage', 'source'], ['Internal Storage', 'folder', 'source'])
    assert device.data[origin] == b'original' and device.data[occupied] == b'previous'
    assert device.rows[origin]['parent'] == 'storage'


def test_device_disconnect_is_reported_not_an_empty_success(device_server):
    server, device = device_server
    device.disconnect = True
    with pytest.raises(HTTPError) as error:
        request(server, '/', 'PROPFIND', b'', {'Depth': '1'})
    assert error.value.code == 409


def test_failed_rename_after_device_move_restores_original_without_deletion(device_server):
    server, device = device_server
    origin = device.add('storage', 'source', b'original')
    device.add('storage', 'folder', None)
    device.fail_rename = True
    with pytest.raises(OSError):
        server.namespace.move(['Internal Storage', 'source'], ['Internal Storage', 'folder', 'renamed'])
    assert device.rows[origin]['parent'] == 'storage'
    assert device.rows[origin]['name'] == 'source'
    assert device.data[origin] == b'original'


def test_moving_aliased_device_name_keeps_original_filename(device_server):
    server, device = device_server
    origin = device.add('storage', 'photo:1.jpg', b'original')
    target = device.add('storage', 'folder', None)
    server.namespace.move(['Internal Storage', 'photo%3A1.jpg'], ['Internal Storage', 'folder', 'photo%3A1.jpg'])
    assert device.rows[origin]['parent'] == target
    assert device.rows[origin]['name'] == 'photo:1.jpg'


def test_rclone_uses_actual_device_protocol_for_streaming_upload_and_move(device_server, tmp_path):
    server, device = device_server
    binary = Path(__file__).resolve().parents[1] / 'build/runtime/rclone.exe'
    if not binary.is_file():
        pytest.skip('Build downloads the verified rclone runtime before running this integration test')
    obscured = subprocess.run([str(binary), 'obscure', '-'], input=server.password + '\n',
                              text=True, capture_output=True, check=True).stdout.strip()
    config = tmp_path / 'rclone.conf'
    config.write_text(f'[test]\ntype=webdav\nvendor=other\nurl=http://127.0.0.1:{server.server_port}/\nuser=OpenCommander\npass={obscured}\n')
    def run(*args, data=None, success=True):
        result = subprocess.run([str(binary), '--config', str(config), '--retries', '1', '--low-level-retries', '1',
                                 *args], input=data, capture_output=True, timeout=30)
        if success:
            assert result.returncode == 0, result.stderr.decode('utf-8', errors='replace')
        return result
    data = bytes(range(256)) * 8192
    run('rcat', 'test:Internal Storage/Grüße 日本語.bin', data=data)
    assert run('cat', 'test:Internal Storage/Grüße 日本語.bin').stdout == data
    run('mkdir', 'test:Internal Storage/target')
    run('moveto', 'test:Internal Storage/Grüße 日本語.bin', 'test:Internal Storage/target/renamed.bin')
    assert run('cat', 'test:Internal Storage/target/renamed.bin').stdout == data
    listing = json.loads(run('lsjson', 'test:Internal Storage/target').stdout)
    assert [(row['Name'], row['Size']) for row in listing] == [('renamed.bin', len(data))]
    run('deletefile', 'test:Internal Storage/target/renamed.bin')
    run('rmdir', 'test:Internal Storage/target')
    assert len(device.rows) == 1
