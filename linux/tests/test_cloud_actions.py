from pathlib import Path
from types import SimpleNamespace
import threading
import pytest
from PySide6.QtWidgets import QApplication, QMenu
from opencommander import cloud_actions as cloud
from opencommander.filesystem import Entry
from opencommander.online_ui import mount_path


def main_fixture(tmp_path, kind='drive'):
    profile = dict(id='oc_test', kind=kind, name='Test cloud')
    return SimpleNamespace(state_dir=tmp_path, online_profiles=[profile], language='de', closing=False), profile


def test_cloud_target_uses_saved_mount_without_remote_stat(tmp_path, monkeypatch):
    main, profile = main_fixture(tmp_path)
    path = mount_path(tmp_path, profile['id']) / 'Grüße' / 'photo.jpg'
    monkeypatch.setattr(Path, 'resolve', lambda *_: pytest.fail('Must not resolve provider paths'))
    assert cloud.cloud_target(main, Entry(path.name, path, False)) == (profile, 'Grüße/photo.jpg')
    assert cloud.cloud_target(main, Entry('local', tmp_path / 'local', False)) is None
    assert cloud.cloud_target(main, Entry(path.name, path, False, member='archive')) is None
    assert cloud.cloud_target(main, Entry(path.name, path, False, link=True)) is None
    assert cloud.cloud_target(main, Entry('other', Path(str(mount_path(tmp_path, profile['id'])) + '-other/file'), False)) is None


def fake_backend(tmp_path, monkeypatch, code):
    binary = tmp_path / 'rclone-fixture'
    binary.write_text('#!/usr/bin/python3\n' + code)
    binary.chmod(0o700)
    monkeypatch.setattr(cloud.rclone_runtime, 'binary', lambda: str(binary))


@pytest.mark.parametrize('kind', ['drive', 'onedrive', 'dropbox'])
def test_share_link_command_and_unicode_path(tmp_path, monkeypatch, kind):
    main, profile = main_fixture(tmp_path, kind)
    fake_backend(tmp_path, monkeypatch, '''import sys
assert 'oc_test:folder/Grüße.txt' in sys.argv
assert 'link' in sys.argv
assert '--config' in sys.argv
if '--onedrive-link-type' in sys.argv:
    assert sys.argv[sys.argv.index('--onedrive-link-type')+1] == 'view'
    assert sys.argv[sys.argv.index('--onedrive-link-scope')+1] == 'anonymous'
print('https://example.org/share/test')
''')
    assert cloud.share_link(main, profile, 'folder/Grüße.txt', threading.Event()) == 'https://example.org/share/test'


@pytest.mark.parametrize('output', ['http://example.org/link', 'javascript:alert(1)', 'https://user:pass@example.org/link', ''])
def test_share_link_rejects_invalid_output(tmp_path, monkeypatch, output):
    main, profile = main_fixture(tmp_path)
    fake_backend(tmp_path, monkeypatch, f'print({output!r})\n')
    with pytest.raises(RuntimeError, match='HTTPS'):
        cloud.share_link(main, profile, 'file', threading.Event())


def test_share_link_redacts_provider_error_and_is_bounded(tmp_path, monkeypatch):
    main, profile = main_fixture(tmp_path)
    fake_backend(tmp_path, monkeypatch, "import sys\nprint('PRIVATE_TOKEN_FIXTURE',file=sys.stderr)\nsys.exit(1)\n")
    with pytest.raises(RuntimeError) as error:
        cloud.share_link(main, profile, 'file', threading.Event())
    assert 'PRIVATE_TOKEN_FIXTURE' not in str(error.value)
    fake_backend(tmp_path, monkeypatch, 'import time\ntime.sleep(5)\n')
    with pytest.raises(RuntimeError, match='Timed out'):
        cloud.share_link(main, profile, 'file', threading.Event(), timeout=.1)
    cancel = threading.Event()
    cancel.set()
    with pytest.raises(RuntimeError, match='Cancelled'):
        cloud.share_link(main, profile, 'file', cancel)


@pytest.mark.parametrize('relative', ['', '../outside', 'folder/../outside', '/outside'])
def test_share_link_rejects_root_or_outside_target(tmp_path, relative):
    main, profile = main_fixture(tmp_path)
    with pytest.raises(ValueError):
        cloud.share_link(main, profile, relative, threading.Event())


def test_cloud_context_capabilities_files_folders_multiselect(tmp_path):
    app = QApplication.instance() or QApplication([])
    for kind, enabled in [('drive', True), ('onedrive', True), ('dropbox', True), ('iclouddrive', False)]:
        main, profile = main_fixture(tmp_path, kind)
        root = mount_path(tmp_path, profile['id'])
        for directory in (False, True):
            entry = Entry('item', root / 'item', directory)
            pane = SimpleNamespace(main=main, archive=None, selected=lambda: [entry])
            menu = QMenu()
            cloud.add_cloud_actions(menu, pane)
            submenu = menu.actions()[-1].menu()
            assert submenu.actions()[0].isEnabled() == enabled
            submenu.actions()[1].trigger()
            assert app.clipboard().text() == '/item'
        pane.selected = lambda: [entry, Entry('other', root / 'other', False)]
        menu = QMenu()
        cloud.add_cloud_actions(menu, pane)
        assert not menu.actions()[-1].menu().actions()[0].isEnabled()
        pane.archive = root / 'file.zip'
        menu = QMenu()
        cloud.add_cloud_actions(menu, pane)
        assert not menu.actions()
    app.clipboard().clear()
