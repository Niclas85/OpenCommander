"""Opt-in external SFTP acceptance using a saved Windows credential, never a CLI password."""
import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from types import SimpleNamespace
import uuid

REPO = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', required=True, type=Path)
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, default=22)
    parser.add_argument('--user', required=True)
    parser.add_argument('--allow-server-writes', required=True, action='store_true')
    args = parser.parse_args()
    installed = Path(os.environ['LOCALAPPDATA']) / 'Programs/OpenCommander'
    sys.path.insert(0, str(installed / 'source/linux'))
    from PySide6.QtCore import QSettings
    from opencommander import platform_support, rclone_runtime, server_connections, windows_mounts, windows_native
    from opencommander.online_ui import private_config
    from opencommander.operations import FileEngine, Cancelled
    from opencommander.commander_tools import compare, search
    platform_support.helper_command = lambda name: [str(installed / 'helpers/OpenCommanderHelper.exe'), name]
    rclone_runtime.binary = lambda: str(installed / 'tools/rclone.exe')
    state = args.state_dir.absolute()
    config = private_config(state)
    sections = configparser.ConfigParser(interpolation=None)
    sections.read(config, encoding='utf-8')
    profiles = json.loads(QSettings(str(state / 'settings.ini'), QSettings.IniFormat).value('online_profiles', '[]'))
    profiles = [row for row in profiles if row.get('kind') == 'sftp' and sections.has_section(row['id'])
                and sections[row['id']].get('host') == args.host
                and sections[row['id']].getint('port', 22) == args.port
                and sections[row['id']].get('user') == args.user]
    assert len(profiles) == 1, 'One saved SFTP profile matching host, port and user is required'
    profile = profiles[0]
    assert profile.get('remember_secret'), 'Save the password in Windows Credential Manager first'
    assert not any(key in sections[profile['id']] for key in ('pass', 'password', 'key_file_pass'))
    main_window = SimpleNamespace(state_dir=state, server_secrets={})
    token = uuid.uuid4().hex
    local = REPO / 'windows/build/sftp-hardware' / token
    local.mkdir(parents=True)
    report = dict(checks=[], cleanup=False, credential_source='Windows Credential Manager',
                  session_password_supplied=False, installed_helper=True)
    def save():
        value = json.dumps(report, ensure_ascii=False, indent=2)
        (local / 'results.json').write_text(value, encoding='utf-8')
        (REPO / 'windows/build/sftp-external-results.json').write_text(value, encoding='utf-8')
    def check(name, callback):
        print('START ' + name, flush=True)
        start = time.monotonic()
        try:
            callback()
            result = dict(name=name, status='pass')
        except Exception as error:
            result = dict(name=name, status='failed', error_type=type(error).__name__, error=str(error))
        result['seconds'] = round(time.monotonic() - start, 2)
        report['checks'].append(result)
        save()
        print(json.dumps(result, ensure_ascii=False), flush=True)
        return result['status'] == 'pass'
    def remote(*command):
        # A fresh environment and child connection each time proves that no
        # password from the GUI's session cache is required. Never log stderr/env.
        env = server_connections.credential_environment(main_window, profile)
        return subprocess.run([rclone_runtime.binary(), '--config', str(config), *command,
            '--contimeout', '5s', '--timeout', '10s', '--retries', '1', '--low-level-retries', '1'],
            env=env, capture_output=True, timeout=30)
    def saved_login():
        result = remote('lsjson', profile['id'] + ':' + profile.get('remote_directory', ''), '--stat')
        assert result.returncode == 0, 'Saved-credential SFTP connection failed (private backend output suppressed)'
        assert isinstance(json.loads(result.stdout), dict)
    if not check('fresh SFTP authentication from saved Windows credential', saved_login):
        report['status'] = 'failed'; save(); return 1
    root = windows_mounts.mount_profile(main_window, profile, threading.Event())
    assert windows_native.mount_identity(root)['filesystem'] == 'fuse.rclone'
    folder = root / ('OpenCommander-SFTP-Test-' + token)
    marker = folder / 'OPENCOMMANDER-TEST-OWNER.txt'
    assert not folder.exists()
    folder.mkdir()
    marker.write_text(token, encoding='ascii')
    report['test_folder'] = folder.name
    engine = FileEngine(local / 'recovery')
    payload = bytes(range(256)) * 4096
    source = local / 'Grüße 日本語.bin'
    source.write_bytes(payload)
    uploaded = folder / source.name
    def equal(path, data):
        assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(data).digest()
    def roundtrip():
        engine.transfer([source], folder)
        equal(uploaded, payload)
        target = local / 'download'; target.mkdir()
        engine.transfer([uploaded], target)
        equal(target / source.name, payload)
        assert any(row['name'] == source.name and row['size'] == len(payload)
                   for row in windows_native.invoke('scan', str(folder)))
        assert windows_native.invoke('properties', str(uploaded))['size'] == len(payload)
    if check('1-MiB Unicode upload/download, SHA-256 and frozen helper', roundtrip):
        def history():
            engine.rename(uploaded, 'renamed.bin')
            FileEngine(engine.state_dir).undo()
            equal(uploaded, payload)
            operation = engine.trash([uploaded])
            assert not uploaded.exists()
            FileEngine(engine.state_dir).undo(operation['id'])
            equal(uploaded, payload)
        check('rename, recoverable removal and persistent undo', history)
        def conflicts():
            engine.transfer([source], folder, conflict='keep')
            equal(folder / 'Grüße 日本語 (2).bin', payload)
            replacement = local / 'replacement'; replacement.mkdir()
            path = replacement / source.name; path.write_bytes(b'generated replacement')
            operation = engine.transfer([path], folder, conflict='replace')
            equal(uploaded, path.read_bytes())
            FileEngine(engine.state_dir).undo(operation['id'])
            equal(uploaded, payload)
        check('keep both and replace with original recovery', conflicts)
        def fresh_read():
            base = profile.get('remote_directory', '')
            suffix = folder.name + '/' + source.name
            remote_path = base.rstrip('/') + '/' + suffix if base else suffix
            result = remote('cat', profile['id'] + ':' + remote_path)
            assert result.returncode == 0 and result.stdout == payload
        check('fresh independent SFTP read using saved credential', fresh_read)
    def resumed_move():
        current = FileEngine(local / 'queued-recovery')
        paused = local / 'paused.bin'; paused.write_bytes(payload * 4)
        job = current.transfers.create([paused], folder, 'keep')
        def pause(count, _):
            if count >= 1024 * 1024:
                current.pause.set(); current.cancel.set()
        current.progress = pause
        try:
            current.transfer([paused], folder, job_id=job['id'])
        except Cancelled:
            pass
        else:
            raise AssertionError('Transfer did not pause')
        resumed = FileEngine(current.state_dir)
        resumed.transfer([paused], folder, job_id=job['id'])
        equal(folder / paused.name, paused.read_bytes())
        assert not resumed.transfers.jobs()
        moving = local / 'move.bin'; moving.write_bytes(payload)
        operation = resumed.transfer([moving], folder, move=True)
        assert not moving.exists()
        equal(folder / moving.name, payload)
        FileEngine(current.state_dir).undo(operation['id'])
        equal(moving, payload)
    check('4-MiB pause/resume and cross-volume move/undo', resumed_move)
    def tools():
        tree = local / 'tree'; (tree / 'nested').mkdir(parents=True)
        text = tree / 'nested/Prüfung.txt'; text.write_text('SFTP test: Grüße 日本語\n', encoding='utf-8')
        engine.transfer([tree], folder)
        rows, warnings = compare(tree, folder / 'tree', True, threading.Event())
        assert rows and not warnings and all(row[1] == 'equal' for row in rows)
        hits, warnings = search(folder / 'tree', '*.txt', False, False, threading.Event())
        assert len(hits) == 1 and not warnings
        engine.make_zip([folder / 'tree'], folder / 'archive.zip')
        extracted = folder / 'extracted'; extracted.mkdir()
        engine.extract_zip(folder / 'archive.zip', extracted)
        equal(extracted / 'tree/nested/Prüfung.txt', text.read_bytes())
        operation_id = engine.history[-1]['id']
        FileEngine(engine.state_dir).undo(operation_id)
        assert not (extracted / 'tree').exists()
    check('nested copy, search, comparison, remote ZIP roundtrip and extraction undo', tools)
    def cleanup():
        assert folder.parent == root and folder.name == 'OpenCommander-SFTP-Test-' + token
        assert marker.read_text(encoding='ascii') == token
        # The nested undo location exceeds MAX_PATH in a Codex/MSIX profile.
        # Exercise the same extended-path support as FileEngine mutations.
        native_folder = platform_support.native_path(folder)
        native_marker = native_folder / marker.name
        paths = list(native_folder.rglob('*'))
        assert all(native_folder in path.parents and not path.is_symlink() and not path.is_junction() for path in paths)
        for path in sorted(paths, key=lambda path: len(path.parts), reverse=True):
            if path != native_marker:
                path.rmdir() if path.is_dir() else path.unlink()
        native_marker.unlink(); native_folder.rmdir()
        assert not folder.exists()
        report['cleanup'] = True
    check('remove only owned generated server test data', cleanup)
    report['status'] = 'pass' if all(row['status'] == 'pass' for row in report['checks']) else 'failed'
    save()
    return 0 if report['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
