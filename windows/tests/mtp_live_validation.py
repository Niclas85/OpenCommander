"""Opt-in real WPD/MTP acceptance using only a uniquely owned device folder.

Requires an unlocked phone in file-transfer mode and the installed Windows app.
Never opens personal files. No physical USB eject or debugging-mode changes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import threading
import traceback
import uuid

REPO = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-device-writes', action='store_true', required=True)
    parser.add_argument('--source', action='store_true', help='Probe source code before rebuilding the installed app')
    parser.add_argument('--installed-dir', type=Path,
                        default=Path(os.environ['LOCALAPPDATA']) / 'Programs/OpenCommander')
    parser.add_argument('--ui-ready-file', type=Path,
                        help='Optional local coordination file for a bounded UI test before cleanup')
    args = parser.parse_args()
    installed = args.installed_dir.resolve(strict=True)
    sys.path.insert(0, str(REPO / 'linux' if args.source else installed / 'source/linux'))
    from opencommander import platform_support, windows_devices, provider_mounts
    from opencommander.windows_wpd import devices
    from opencommander.operations import FileEngine, Cancelled

    helper = installed / 'helpers/OpenCommanderHelper.exe'
    assert helper.is_file()
    if not args.source:
        platform_support.helper_command = lambda name: [str(helper), name]
    rows = devices()
    assert len(rows) == 1, 'Exactly one connected WPD device required'
    identifier = 'wpd:' + rows[0]['id']
    root = windows_devices.mount(identifier)
    if not args.source:
        from opencommander.windows_mounts import processes
        mounted = [process for process, _, _, path in processes() if path == root]
        assert len(mounted) == 1
        parent = mounted[0].parent()
        assert parent and Path(parent.exe()).resolve() == helper.resolve(), (
            'Existing mount uses a different helper; disconnect it logically before acceptance')
    storages = [p for p in root.iterdir() if p.is_dir()]
    assert len(storages) == 1, 'Exactly one accessible storage required'
    token = uuid.uuid4().hex
    local = REPO / 'windows/build/mtp-hardware' / token
    local.mkdir(parents=True, exist_ok=False)
    folder = storages[0] / ('OpenCommander-MTP-Test-' + token)
    marker = folder / 'OPENCOMMANDER-TEST-OWNER.txt'
    engine = FileEngine(local / 'recovery')
    results = dict(device=rows[0]['name'], installed_helper=not args.source,
                   installed_exe_sha256=hashlib.sha256((installed / 'OpenCommander.exe').read_bytes()).hexdigest(),
                   test_folder=folder.name, checks=[], cleanup='not started')

    def save():
        (local / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
        (REPO / 'windows/build/mtp-hardware-results.json').write_text(
            json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')

    def check(name, action):
        print('START', name, flush=True)
        start = time.monotonic()
        try:
            action()
            result = dict(name=name, status='pass')
        except Exception as error:
            result = dict(name=name, status='failed', error=str(error))
            trace = error.__traceback__
            while trace:
                values = trace.tb_frame.f_locals
                if trace.tb_frame.f_code.co_name == 'copy_file' and all(
                        key in values for key in ('partial_info', 'current_partial')):
                    result['partial_metadata'] = {
                        key: {field: getattr(values[key], field) for field in
                              ('st_dev', 'st_ino', 'st_mode', 'st_size', 'st_mtime_ns')}
                        for key in ('partial_info', 'current_partial')}
                trace = trace.tb_next
            traceback.print_exc()
        result['seconds'] = round(time.monotonic() - start, 2)
        results['checks'].append(result)
        save()
        print(result, flush=True)
        return result['status'] == 'pass'

    def equal(path, data):
        actual = path.read_bytes()
        assert len(actual) == len(data) and hashlib.sha256(actual).digest() == hashlib.sha256(data).digest(), 'Byte comparison failed'

    payload = bytes(range(256)) * 1024
    source = local / 'Grüße 日本語.bin'
    source.write_bytes(payload)
    uploaded = folder / source.name

    def initialize():
        assert not folder.exists(), 'Test path already exists'
        folder.mkdir()
        marker.write_text(token, encoding='ascii')
        assert marker.read_text(encoding='ascii') == token

    if not check('create owned folder and marker', initialize):
        return 1

    def upload():
        engine.transfer([source], folder)
        equal(uploaded, payload)

    uploaded_ok = check('Unicode upload and exact 256-KiB readback', upload)
    if uploaded_ok:
        def rename_undo():
            engine.rename(uploaded, 'renamed.bin')
            time.sleep(2.2)
            equal(folder / 'renamed.bin', payload)
            FileEngine(engine.state_dir).undo()
            equal(uploaded, payload)
        check('rename and persistent undo after cache expiry', rename_undo)

        def download():
            target = local / 'download'
            target.mkdir()
            FileEngine(engine.state_dir).transfer([uploaded], target)
            equal(target / uploaded.name, payload)
        check('download and exact byte comparison', download)

        def trash_undo():
            restored = FileEngine(engine.state_dir)
            operation = restored.trash([uploaded])
            assert not uploaded.exists()
            FileEngine(engine.state_dir).undo(operation['id'])
            equal(uploaded, payload)
        check('recoverable remove and persistent undo', trash_undo)

    def pause_resume():
        paused = local / 'paused.bin'
        paused.write_bytes(payload * 8)
        current = FileEngine(engine.state_dir)
        job = current.transfers.create([paused], folder, 'keep')
        def pause(count, _):
            if count >= 1024 * 1024:
                current.pause.set()
                current.cancel.set()
        current.progress = pause
        try:
            current.transfer([paused], folder, job_id=job['id'])
        except Cancelled:
            pass
        else:
            raise AssertionError('Transfer did not pause')
        resumed = FileEngine(engine.state_dir)
        resumed.transfer([paused], folder, job_id=job['id'])
        equal(folder / paused.name, paused.read_bytes())
        assert not resumed.transfers.jobs()
    check('2-MiB queued upload pause and resume', pause_resume)

    def move_undo():
        moving = local / 'move-to-device.bin'
        moving.write_bytes(payload)
        current = FileEngine(engine.state_dir)
        job = current.transfers.create([moving], folder, 'keep', move=True)
        operation = current.transfer([moving], folder, move=True, job_id=job['id'])
        assert not moving.exists()
        equal(folder / moving.name, payload)
        FileEngine(engine.state_dir).undo(operation['id'])
        equal(moving, payload)
        assert not (folder / moving.name).exists()
    check('queued move with verified source cleanup and undo', move_undo)

    def reconnect_undo():
        current = FileEngine(engine.state_dir)
        current.rename(uploaded, 'after-reconnect.bin')
        windows_devices.unmount(identifier)
        deadline = time.monotonic() + 10
        while (root.is_mount() or root.is_junction()) and time.monotonic() < deadline:
            time.sleep(.1)
        assert not root.is_junction(), 'Logical disconnect did not complete'
        newroot = windows_devices.mount(identifier)
        assert newroot == root
        FileEngine(engine.state_dir).undo()
        equal(uploaded, payload)
    if uploaded_ok:
        check('logical reconnect and persistent undo', reconnect_undo)

    def directory_tools():
        from opencommander.commander_tools import search, compare
        tree = local / 'directory-fixture'
        (tree / 'nested').mkdir(parents=True)
        (tree / 'nested/Prüfung.txt').write_text('OpenCommander MTP: Grüße 日本語\n', encoding='utf-8')
        FileEngine(engine.state_dir).transfer([tree], folder)
        target = folder / tree.name
        hits, warnings = search(target, '*.txt', False, False, threading.Event())
        assert not warnings and len(hits) == 1 and hits[0].name == 'Prüfung.txt'
        rows, warnings = compare(tree, target, True, threading.Event())
        assert not warnings and rows and all(row[1] == 'equal' for row in rows), (rows, warnings)
        equal(target / 'nested/Prüfung.txt', (tree / 'nested/Prüfung.txt').read_bytes())
    tools_ok = check('nested directory copy, search and SHA-256 comparison', directory_tools)

    def archive_roundtrip():
        import zipfile
        target = folder / 'directory-fixture'
        archive = folder / 'device-archive.zip'
        current = FileEngine(engine.state_dir)
        current.make_zip([target], archive)
        with zipfile.ZipFile(archive) as zipped:
            assert zipped.testzip() is None
            assert zipped.read('directory-fixture/nested/Prüfung.txt') == (local / 'directory-fixture/nested/Prüfung.txt').read_bytes()
        extracted = folder / 'extracted'
        extracted.mkdir()
        current.extract_zip(archive, extracted)
        equal(extracted / 'directory-fixture/nested/Prüfung.txt', (local / 'directory-fixture/nested/Prüfung.txt').read_bytes())
    if tools_ok:
        check('create and extract ZIP directly on phone', archive_roundtrip)

    if args.ui_ready_file and tools_ok:
        ready = args.ui_ready_file.resolve()
        assert REPO / 'windows/build' in ready.parents, 'UI coordination must stay in local build output'
        ready.write_text(json.dumps(dict(path=str(folder / 'directory-fixture/nested'), test_folder=folder.name)), encoding='utf-8')
        print('UI_READY', flush=True)
        deadline = time.monotonic() + 180
        while ready.exists() and time.monotonic() < deadline:
            time.sleep(.2)
        results['ui_coordination'] = 'completed' if not ready.exists() else 'timed out'
        ready.unlink(missing_ok=True)

    def cleanup():
        # Confine deletion to our unique test folder, and verify ownership first.
        assert folder.parent == storages[0] and folder.name == 'OpenCommander-MTP-Test-' + token
        assert marker.read_text(encoding='ascii') == token, 'Ownership marker changed'
        paths = list(folder.rglob('*'))
        assert all(folder in p.parents and not p.is_symlink() and not p.is_junction() for p in paths)
        for path in sorted(paths, key=lambda p: len(p.parts), reverse=True):
            if path == marker:
                continue
            path.rmdir() if path.is_dir() else path.unlink()
        marker.unlink()
        folder.rmdir()
        assert not folder.exists()
        results['cleanup'] = 'pass'
    if not check('remove only owned generated test data', cleanup):
        results['cleanup'] = 'failed; inspect unique test folder before retrying'
    results['status'] = 'pass' if all(c['status'] == 'pass' for c in results['checks']) else 'failed'
    save()
    print('RESULT', results['status'], flush=True)
    return 0 if results['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
