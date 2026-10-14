import io
import json
import os
from pathlib import Path
import subprocess
import threading
import zipfile
from types import SimpleNamespace

import pytest
from opencommander import windows_native, windows_mounts
from opencommander.operations import FileEngine, SafetyError, checked_members, rename_new
from opencommander.platform_support import data_directory, helper_command, root_directory


def test_native_paths_and_drive_identity(tmp_path):
    assert data_directory().name == 'OpenCommander'
    assert root_directory().is_absolute()
    assert Path(tmp_path.anchor) in windows_native.drive_roots()
    identity = windows_native.mount_identity(tmp_path)
    assert identity['device'] and identity['filesystem']
    assert windows_native.remote_location(r'\\server\share\folder')
    assert not windows_native.remote_location(tmp_path)


def test_atomic_rename_does_not_replace_case_insensitive_destination(tmp_path):
    source, target = tmp_path / 'source', tmp_path / 'Target'
    source.write_bytes(b'new'); target.write_bytes(b'old')
    with pytest.raises(FileExistsError):
        rename_new(source, tmp_path / 'target')
    assert source.read_bytes() == b'new' and target.read_bytes() == b'old'


@pytest.mark.parametrize('name', ['C:/escape', 'file:stream', 'NUL', 'con.txt', 'COM1', 'dir./a', 'dir /a', r'a\b', '../escape'])
def test_archive_rejects_windows_aliases_and_escape_names(name):
    member = zipfile.ZipInfo('safe')
    member.filename = name  # Bypass Windows ZipInfo's separator normalization.
    with pytest.raises(SafetyError):
        checked_members(SimpleNamespace(infolist=lambda: [member]))


def test_archive_rejects_case_collisions():
    with pytest.raises(SafetyError):
        checked_members(SimpleNamespace(infolist=lambda: [zipfile.ZipInfo('A'), zipfile.ZipInfo('a')]))


@pytest.mark.parametrize('name', ['NUL', 'a:b', r'..\escape', 'name.', 'name ', 'C:\\escape'])
def test_mutation_names_cannot_escape_or_create_streams(tmp_path, name):
    engine = FileEngine(tmp_path / 'state')
    source = tmp_path / 'original'; source.write_bytes(b'original')
    with pytest.raises(SafetyError): engine.rename(source, name)
    with pytest.raises(SafetyError): engine.mkdir(tmp_path, name)
    assert source.read_bytes() == b'original'


def test_native_handles_preserve_binary_data_and_reject_directory(tmp_path):
    path = tmp_path / 'binary'; data = bytes(range(256)) * 50
    path.write_bytes(data)
    with os.fdopen(windows_native.open_regular(path, os.O_RDONLY), 'rb') as stream:
        assert stream.read() == data
    with pytest.raises((OSError, SafetyError)):
        windows_native.open_regular(tmp_path, os.O_RDONLY)
    with os.fdopen(windows_native.open_regular(path, os.O_WRONLY | os.O_APPEND), 'wb') as stream:
        stream.write(b'\r\n\x1a')
    assert path.read_bytes() == data + b'\r\n\x1a'


def test_bridge_scans_unicode_and_properties_without_gui(tmp_path):
    path = tmp_path / 'Grüße 日本語.txt'; path.write_bytes(b'content')
    rows = windows_native.invoke('scan', str(tmp_path))
    assert rows[0]['name'] == path.name
    props = windows_native.invoke('properties', str(path))
    assert props['size'] == 7 and props['created'] > 0
    result = windows_native.invoke('directory-size', str(tmp_path))
    assert result['complete'] and result['bytes'] == 7


def test_bridge_cancellation_does_not_wait_for_scan(tmp_path):
    cancel = threading.Event(); cancel.set()
    with pytest.raises(RuntimeError, match='Cancelled'):
        windows_native.invoke('scan', str(tmp_path), cancel)


def test_windows_hidden_attribute(tmp_path):
    import win32api, win32con
    from opencommander.filesystem import listing
    path = tmp_path / 'hidden.txt'; path.write_bytes(b'hidden')
    win32api.SetFileAttributes(str(path), win32con.FILE_ATTRIBUTE_HIDDEN)
    assert listing(tmp_path) == []
    assert listing(tmp_path, hidden=True)[0].name == path.name


def test_credentials_use_windows_vault_without_plaintext_file(tmp_path):
    import secrets
    secret = secrets.token_urlsafe(24) + 'ü'
    try:
        windows_native.keyring(tmp_path, 'test-only', 'store', secret)
        assert windows_native.keyring(tmp_path, 'test-only', 'lookup') == secret
        assert not list(tmp_path.iterdir())
    finally:
        windows_native.keyring(tmp_path, 'test-only', 'clear')
    assert windows_native.keyring(tmp_path, 'test-only', 'lookup') is None


def test_network_addresses_use_native_unc():
    assert windows_native.network_path('smb://nas/share/folder') == r'\\nas\share\folder'
    assert windows_native.network_path('davs://example.org:8443/data') == r'\\example.org@SSL@8443\DavWWWRoot\data'


def test_encrypted_openssh_key_remains_off_disk(tmp_path):
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.hazmat.primitives import serialization
    from opencommander.server_connections import credential_environment
    key = ed25519.Ed25519PrivateKey.generate()
    path = tmp_path / 'key'
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH,
                                      serialization.BestAvailableEncryption(b'fixture-password')))
    original = path.read_bytes()
    main = SimpleNamespace(server_secrets={'fixture': 'fixture-password'})
    profile = dict(id='fixture', server_login=True, auth_mode='key', key_path=str(path), agent_key=True)
    env = credential_environment(main, profile)
    assert 'PRIVATE KEY' in env['RCLONE_CONFIG_FIXTURE_KEY_PEM']
    assert env['RCLONE_CONFIG_FIXTURE_KEY_USE_AGENT'] == 'false'
    assert path.read_bytes() == original and list(tmp_path.iterdir()) == [path]


def test_external_mount_namespace_overrides_are_not_shared(tmp_path, monkeypatch):
    root = tmp_path / 'cloud'
    monkeypatch.setattr(windows_mounts, 'processes', lambda: [(None, ['rclone.exe', 'mount', 'remote:', str(root),
                         '--drive-shared-with-me'], 'remote:', root)])
    monkeypatch.setattr(Path, 'is_mount', lambda self: self == root)
    assert windows_mounts.discover() == []


def test_shell_registration_is_per_user_and_quoted(monkeypatch):
    import winreg
    from opencommander import windows_shell
    writes = []
    class Key:
        def __init__(self, path): self.path = path
        def __enter__(self): return self
        def __exit__(self, *args): pass
    def create(hive, path):
        assert hive == winreg.HKEY_CURRENT_USER
        return Key(path)
    monkeypatch.setattr(winreg, 'CreateKey', create)
    monkeypatch.setattr(winreg, 'SetValueEx', lambda key, name, reserved, kind, value: writes.append((key.path, value)))
    windows_shell.register()
    assert all(value.endswith(' "%1"') for path, value in writes if path.endswith('command'))
    assert len(writes) == 4


def test_backend_directory_acl_is_private(tmp_path):
    import win32security
    from opencommander.online_ui import private_config
    config = private_config(tmp_path / 'state')
    descriptor = win32security.GetNamedSecurityInfo(str(config.parent), win32security.SE_FILE_OBJECT,
                                                    win32security.DACL_SECURITY_INFORMATION)
    acl = descriptor.GetSecurityDescriptorDacl()
    assert acl.GetAceCount() == 2
    assert all(win32security.ConvertSidToStringSid(acl.GetAce(index)[2]) not in ('S-1-1-0', 'S-1-5-32-545')
               for index in range(acl.GetAceCount()))


def test_junction_is_not_recursively_copied_and_trash_can_restore_it(tmp_path):
    import _winapi
    outside = tmp_path / 'outside'; outside.mkdir()
    file = outside / 'keep'; file.write_bytes(b'original')
    junction = tmp_path / 'junction'
    _winapi.CreateJunction(str(outside), str(junction))
    destination = tmp_path / 'destination'; destination.mkdir()
    engine = FileEngine(tmp_path / 'state')
    with pytest.raises(SafetyError): engine.transfer([junction], destination)
    assert file.read_bytes() == b'original' and not list(destination.iterdir())
    engine.trash([junction]); assert not junction.exists() and file.exists()
    engine.undo(); assert junction.is_junction() and file.read_bytes() == b'original'


def test_resume_rejects_staging_directory_replaced_by_junction(tmp_path):
    import _winapi
    from opencommander.operations import Cancelled
    source = tmp_path / 'source'; source.mkdir()
    (source / 'large').write_bytes(b'x' * 2 * 1024**2)
    destination = tmp_path / 'destination'; destination.mkdir()
    outside = tmp_path / 'outside'; outside.mkdir()
    (outside / 'keep').write_bytes(b'untouched')
    engine = FileEngine(tmp_path / 'state')
    job = engine.transfers.create([source], destination, 'keep')
    def pause(*args):
        engine.pause.set(); engine.cancel.set()
    engine.progress = pause
    with pytest.raises(Cancelled):
        engine.transfer([source], destination, job_id=job['id'])
    saved = engine.transfers.get(job['id'])
    payload = Path(saved['roots'][0]['staging']) / 'payload'
    payload.rename(payload.with_name('original-payload'))
    _winapi.CreateJunction(str(outside), str(payload))
    restarted = FileEngine(engine.state_dir)
    with pytest.raises(SafetyError):
        restarted.transfer([source], destination, job_id=job['id'])
    assert list(outside.iterdir()) == [outside / 'keep']
    assert (outside / 'keep').read_bytes() == b'untouched'
    assert not (destination / source.name).exists()


def test_native_clipboard_copy_and_cut(window, app):
    from PySide6.QtWidgets import QApplication
    from PySide6.QtCore import QMimeData, QUrl
    from test_ui import wait
    left, right = window.panes
    source = left.model.entries[0].path
    left.table.selectRow(0)
    window.copy_clipboard(True)
    mime = QApplication.clipboard().mimeData()
    assert bytes(mime.data('application/x-qt-windows-mime;value="Preferred DropEffect"')) == b'\x02\0\0\0'
    native = QMimeData(); native.setUrls([QUrl.fromLocalFile(str(source))])
    native.setData('application/x-qt-windows-mime;value="Preferred DropEffect"', b'\x02\0\0\0')
    QApplication.clipboard().setMimeData(native)
    window.activate(right); window.paste_clipboard()
    wait(app, lambda: not window.busy and (right.directory / source.name).exists())
    assert not source.exists()


from test_ui import app, window


def test_provider_containment_does_not_resolve_winfsp_volume(tmp_path, monkeypatch):
    from opencommander import provider_mounts
    from opencommander.platform_support import canonical_path
    root = tmp_path / 'mounted'; root.mkdir()
    monkeypatch.setattr(provider_mounts, '_roots', {root})
    original = Path.resolve
    def resolve(path, *args, **kwargs):
        if path == root or root in path.parents:
            raise OSError(1005, 'Windows does not support final path lookup on this volume')
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, 'resolve', resolve)
    assert canonical_path(root / 'folder' / 'file') == root / 'folder' / 'file'
    source = tmp_path / 'source'; source.write_bytes(b'provider data')
    engine = FileEngine(tmp_path / 'state')
    engine.transfer([source], root)
    assert (root / source.name).read_bytes() == b'provider data'
    engine.undo(); assert not (root / source.name).exists()


def test_mount_control_credential_does_not_resolve_mount_leaf(tmp_path, monkeypatch):
    root = tmp_path / 'mount'
    original = Path.resolve
    def resolve(path, *args, **kwargs):
        if path == root:
            raise OSError(1005, 'final path lookup unsupported')
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, 'resolve', resolve)
    try:
        windows_native.keyring(root, 'test-mount-control', 'store', 'fixture-only')
        assert windows_native.keyring(root, 'test-mount-control', 'lookup') == 'fixture-only'
    finally:
        windows_native.keyring(root, 'test-mount-control', 'clear')


def test_google_shared_choice_routes_to_visible_setup_without_empty_answer_loop(window, monkeypatch):
    window.online_locations(); dialog = window.online_dialog
    dialog.provider.setCurrentIndex(dialog.provider.findData('drive'))
    dialog.profile = dict(id='oc_fixture', kind='drive', name='Fixture'); dialog.cloud_auth = True
    dialog.question(dict(State='client_id_warning', Option=dict(Name='config_shared_client_id', DefaultStr='false',
        Examples=[dict(Value='true',Help='Yes'),dict(Value='false',Help='No')])))
    assert dialog.answer.findData('true') >= 0 and not dialog.answer.isEditable()
    assert 'Browser' in dialog.answer.itemText(dialog.answer.findData('true'))
    calls=[];monkeypatch.setattr(dialog,'work',lambda *args,**kwargs:calls.append(args))
    dialog.next()
    assert dialog.state == '' and dialog.google_custom.isChecked()
    assert dialog.google_client_id.isVisible() and dialog.google_client_secret.isVisible()
    dialog.next()
    assert not calls and 'Client-ID' in dialog.status.text()
    dialog.close()


def test_google_shared_browser_choice_requires_explicit_selection(window, monkeypatch):
    window.online_locations(); dialog=window.online_dialog
    dialog.provider.setCurrentIndex(dialog.provider.findData('drive'))
    dialog.profile=dict(id='oc_fixture',kind='drive',name='Fixture');dialog.cloud_auth=True
    dialog.question(dict(State='client_id_warning',Option=dict(Name='config_shared_client_id',DefaultStr='false')))
    calls=[];monkeypatch.setattr(dialog,'continue_auth',lambda answer:calls.append(answer))
    dialog.answer.setCurrentIndex(dialog.answer.findData('true'));dialog.next()
    assert calls == ['true']
    dialog.close()


def test_real_windows_oauth_delivers_url_before_process_exits(tmp_path):
    from opencommander import online_ui
    import threading
    import socket
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1',53682))==0:
            pytest.skip('A live user sign-in currently owns the fixed OAuth port')
    config = online_ui.private_config(tmp_path / 'state')
    cancel = threading.Event()
    first = online_ui.command_json(config, ['config', 'create', 'oc_fixture', 'onedrive', '--non-interactive'], cancel)
    urls = []
    def browser(url):
        urls.append(url)
        cancel.set()
    with pytest.raises(RuntimeError, match='Cancelled'):
        online_ui.command_json(config, ['config', 'update', 'oc_fixture', '--continue', '--state', first['State'], '--non-interactive'],
                               cancel, result='true', timeout=10, browser_callback=browser)
    assert len(urls) == 1
    assert online_ui.oauth_browser_url(urls[0]) == urls[0]


def test_terminal_cloud_error_without_question_cannot_submit_empty_answer(window):
    window.online_locations();dialog=window.online_dialog
    dialog.provider.setCurrentIndex(dialog.provider.findData('dropbox'))
    dialog.profile=dict(id='oc_fixture',kind='dropbox',name='Fixture');dialog.cloud_auth=True
    dialog.state='*oauth-islocal,,,'
    dialog.question(dict(State='*oauth-error,,,',Error='Input not accepted: synthetic-private-provider-reply',Option=None))
    assert dialog.state=='' and dialog.provider.isEnabled()
    assert not dialog.answer.isVisible()
    assert 'Neue Anmeldung' in dialog.status.text()
    assert 'synthetic-private-provider-reply' not in dialog.status.text()
    dialog.close()


def test_restart_cloud_login_removes_stale_question_and_error(window):
    from PySide6.QtWidgets import QPushButton
    window.online_locations();dialog=window.online_dialog
    dialog.provider.setCurrentIndex(dialog.provider.findData('dropbox'))
    dialog.profile=dict(id='oc_fixture',kind='dropbox',name='Fixture');dialog.cloud_auth=True
    dialog.question(dict(State='*oauth-islocal,,,',Option=dict(Name='config_is_local',DefaultStr='true'),Error='retry'))
    dialog.status.setText('stale failure');dialog.answer.show()
    restart=next(button for button in dialog.findChildren(QPushButton) if button.text()=='Neue Anmeldung beginnen')
    restart.click()
    assert dialog.state=='' and dialog.profile is None
    assert not dialog.answer.isVisible() and not dialog.status.text()
    assert 'Dropbox' in dialog.next_button.text()
    dialog.close()


@pytest.mark.parametrize('prefix', ['\\\\?\\', '\\??\\'])
def test_remote_alias_never_reads_provider_links(tmp_path, monkeypatch, prefix):
    from opencommander import provider_mounts
    provider, alias = tmp_path / 'provider', tmp_path / 'alias'
    monkeypatch.setattr(provider_mounts, '_roots', {provider})
    original_link, original_read = Path.is_symlink, os.readlink
    def is_link(path):
        assert path != provider and provider not in path.parents
        return path == alias or original_link(path)
    def read_link(path):
        assert Path(path) != provider and provider not in Path(path).parents
        return prefix + str(provider) if Path(path) == alias else original_read(path)
    monkeypatch.setattr(Path, 'is_symlink', is_link)
    monkeypatch.setattr(os, 'readlink', read_link)
    assert windows_native.remote_location(alias / 'folder/photo.jpg')
    assert not windows_native.remote_location(tmp_path / 'local')


@pytest.mark.parametrize('prefix', ['\\\\?\\', '\\??\\'])
def test_transfer_reservations_normalize_native_alias_targets(tmp_path, monkeypatch, prefix):
    from opencommander import filesystem
    from opencommander.transfers_ui import resources, conflicts
    remote, alias = tmp_path / 'provider', tmp_path / 'alias'
    remote.mkdir()
    alias.mkdir()
    monkeypatch.setattr(filesystem, 'remote_location', lambda path: Path(path) == remote or remote in Path(path).parents)
    monkeypatch.setattr(windows_native, 'lexical_remote_location', filesystem.remote_location)
    original_link = Path.is_symlink
    def local_link(path):
        assert not filesystem.remote_location(path), 'Scheduler must not stat provider paths'
        return path == alias or original_link(path)
    monkeypatch.setattr(Path, 'is_symlink', local_link)
    monkeypatch.setattr(os, 'readlink', lambda path: prefix + str(remote) if Path(path) == alias else pytest.fail('Unexpected alias read'))
    copy = dict(sources=[str(remote / 'source')], directory=str(tmp_path / 'destination'))
    move = dict(sources=[str(alias / 'source')], directory=str(tmp_path / 'other'), move=True)
    assert conflicts(resources(copy), resources(move))


@pytest.mark.parametrize('reader', ['S-1-1-0', 'S-1-5-5-100-101'])
def test_private_ssh_key_rejects_world_readable_ntfs_acl(tmp_path, reader):
    import win32security
    import ntsecuritycon
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.hazmat.primitives import serialization
    from opencommander import server_connections
    windows_native.protect_private_directory(tmp_path)
    path = tmp_path / 'private-key'
    path.write_bytes(ed25519.Ed25519PrivateKey.generate().private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH, serialization.NoEncryption()))
    assert windows_native.private_key_readers(path)
    descriptor = win32security.GetNamedSecurityInfo(str(path), win32security.SE_FILE_OBJECT,
                                                  win32security.DACL_SECURITY_INFORMATION)
    acl = descriptor.GetSecurityDescriptorDacl()
    acl.AddAccessAllowedAce(win32security.ACL_REVISION, ntsecuritycon.FILE_GENERIC_READ,
                           win32security.ConvertStringSidToSid(reader))
    win32security.SetNamedSecurityInfo(str(path), win32security.SE_FILE_OBJECT,
        win32security.DACL_SECURITY_INFORMATION | win32security.PROTECTED_DACL_SECURITY_INFORMATION,
        None, None, acl, None)
    assert not windows_native.private_key_readers(path)
    with pytest.raises(ValueError, match='NTFS'):
        server_connections.settings('sftp', 'localhost', 22, 'fixture', 'key', str(path))
