from pathlib import Path
from types import SimpleNamespace
import json
import threading
import pytest
from opencommander import external_cloud, provider_mounts, online_ui, cloud_actions
from opencommander.filesystem import Entry


@pytest.mark.parametrize('kind', ['drive', 'onedrive', 'dropbox', 'iclouddrive'])
def test_external_mount_discovery_keeps_namespace_and_never_returns_secrets(tmp_path, monkeypatch, kind):
    proc = tmp_path / 'proc'; proc.mkdir()
    process = proc / '123'; process.mkdir()
    root = tmp_path / 'cloud'
    config = tmp_path / 'rclone.conf'
    config.write_text(f'[fixture]\ntype = {kind}\ntoken = PRIVATE_TEST_TOKEN\n')
    (process / 'cmdline').write_bytes('\0'.join(['/usr/bin/rclone', 'mount', 'fixture:subfolder', str(root), '--config', str(config)]).encode())
    monkeypatch.setattr(provider_mounts, 'rclone_mount', lambda path: (root, '99'))
    profiles = external_cloud.discover(proc)
    assert len(profiles) == 1
    profile = profiles[0]
    assert profile['kind'] == kind and profile['remote_base'] == 'fixture:subfolder'
    assert 'PRIVATE_TEST_TOKEN' not in json.dumps(profiles)
    main = SimpleNamespace(online_profiles=[], external_cloud_profiles=profiles)
    assert cloud_actions.cloud_target(main, Entry('photo.jpg', root / 'folder/photo.jpg', False)) == (profile, 'folder/photo.jpg')
    assert external_cloud.remote_for(profile, 'folder/photo.jpg') == 'fixture:subfolder/folder/photo.jpg'
    (process / 'cmdline').write_bytes('\0'.join(['/usr/bin/rclone', 'mount', 'fixture:', str(root), '--config', str(config), '--drive-shared-with-me']).encode())
    assert not external_cloud.discover(proc)
    (process / 'cmdline').write_bytes(b'bad\x00mount')
    assert not external_cloud.discover(proc)


def test_external_list_and_share_use_same_config_and_remote_root(tmp_path, monkeypatch):
    config = tmp_path / 'external.conf'
    root = tmp_path / 'drive'
    profile = dict(id='external_fixture', external=True, name='Drive', kind='drive', mount_root=str(root),
                   config_path=str(config), remote_base='fixture:photos')
    main = SimpleNamespace(state_dir=tmp_path / 'state')
    script = tmp_path / 'rclone'
    script.write_text('#!/usr/bin/python3\nimport sys,json\n'
                      f'assert sys.argv[sys.argv.index("--config")+1] == {str(config)!r}\n'
                      'if "lsjson" in sys.argv:\n'
                      ' assert "fixture:photos/folder" in sys.argv\n'
                      ' print(json.dumps([{"Name":"image.jpg","IsDir":False,"Size":12}]))\n'
                      'else:\n'
                      ' assert "fixture:photos/folder/image.jpg" in sys.argv\n'
                      ' print("https://example.org/share")\n')
    script.chmod(0o700)
    monkeypatch.setattr(online_ui.rclone_runtime, 'binary', lambda: str(script))
    rows = online_ui.list_cloud(main, profile, root / 'folder', threading.Event())
    assert rows[0].path == root / 'folder/image.jpg'
    assert cloud_actions.share_link(main, profile, 'folder/image.jpg', threading.Event()) == 'https://example.org/share'
    assert not (main.state_dir / 'online/rclone.conf').exists()


@pytest.mark.parametrize('kind', ['drive', 'onedrive', 'dropbox', 'iclouddrive'])
def test_all_cloud_backends_error_recovery_and_cancellation(tmp_path, monkeypatch, kind):
    main = SimpleNamespace(state_dir=tmp_path / 'state')
    profile = dict(id='oc_fixture', kind=kind)
    script = tmp_path / 'rclone'
    script.write_text('#!/usr/bin/python3\nimport sys\nprint("couldn\'t decrypt password: PRIVATE_FIXTURE",file=sys.stderr)\nsys.exit(1)\n')
    script.chmod(0o700)
    monkeypatch.setattr(online_ui.rclone_runtime, 'binary', lambda: str(script))
    root = online_ui.mount_path(main.state_dir, profile['id'])
    with pytest.raises(RuntimeError, match='Anmeldung') as error:
        online_ui.list_cloud(main, profile, root, threading.Event())
    assert 'PRIVATE_FIXTURE' not in str(error.value)
    script.write_text('#!/usr/bin/python3\nprint("[]")\n')
    assert online_ui.list_cloud(main, profile, root, threading.Event()) == []
    cancel = threading.Event(); cancel.set()
    with pytest.raises(RuntimeError, match='Cancelled'):
        online_ui.list_cloud(main, profile, root, cancel)
