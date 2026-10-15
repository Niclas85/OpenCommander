"""Opt-in real SMB acceptance, confined to one new, marked test directory."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import sys
import threading
import time
import traceback
import uuid

REPO = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--share', required=True, help=r'Existing authorized UNC share, e.g. \\server\Test')
    parser.add_argument('--allow-share-writes', required=True, action='store_true')
    args = parser.parse_args()
    share = Path(args.share)
    assert PureWindowsPath(share).drive.startswith('\\\\') and share.is_dir(), 'Accessible UNC share required'
    installed = Path(os.environ['LOCALAPPDATA']) / 'Programs/OpenCommander'
    sys.path.insert(0, str(installed / 'source/linux'))
    from opencommander import platform_support, windows_native
    from opencommander.operations import FileEngine, Cancelled, SafetyError
    from opencommander.commander_tools import compare, search
    platform_support.helper_command = lambda name: [str(installed / 'helpers/OpenCommanderHelper.exe'), name]
    token = uuid.uuid4().hex
    folder = share / ('OpenCommander-NAS-Test-' + token)
    local = REPO / 'windows/build/nas-hardware' / token
    local.mkdir(parents=True)
    engine = FileEngine(local / 'recovery')
    marker = folder / 'OPENCOMMANDER-TEST-OWNER.txt'
    payload = bytes(range(256)) * 4096
    source = local / 'Grüße 日本語.bin'
    source.write_bytes(payload)
    uploaded = folder / source.name
    results = dict(share=str(share), test_folder=folder.name, checks=[], cleanup='not started')
    report = REPO / 'windows/build/nas-expanded-results.json'

    def save():
        text = json.dumps(results, ensure_ascii=False, indent=2)
        report.write_text(text, encoding='utf-8')
        (local / 'results.json').write_text(text, encoding='utf-8')

    def check(name, action):
        print('START', name, flush=True)
        start = time.monotonic()
        try:
            action()
            result = dict(name=name, status='pass')
        except Exception as error:
            result = dict(name=name, status='failed', error=str(error))
            traceback.print_exc()
        result['seconds'] = round(time.monotonic() - start, 2)
        results['checks'].append(result)
        save()
        print(result, flush=True)
        return result['status'] == 'pass'

    def equal(path, data):
        assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(data).digest()

    assert not folder.exists()
    folder.mkdir()
    marker.write_text(token, encoding='ascii')
    assert marker.read_text(encoding='ascii') == token

    def upload():
        engine.transfer([source], folder)
        equal(uploaded, payload)
        target = local / 'download'
        target.mkdir()
        engine.transfer([uploaded], target)
        equal(target / source.name, payload)
        records = windows_native.invoke('scan', str(folder))
        assert any(r['name'] == source.name and r['size'] == len(payload) for r in records)
        assert windows_native.invoke('properties', str(uploaded))['size'] == len(payload)
    uploaded_ok = check('1-MiB Unicode roundtrip and installed native helper', upload)

    if uploaded_ok:
        def rename_remove():
            current = FileEngine(engine.state_dir)
            current.rename(uploaded, 'renamed.bin')
            FileEngine(engine.state_dir).undo()
            equal(uploaded, payload)
            operation = current.trash([uploaded])
            assert not uploaded.exists()
            FileEngine(engine.state_dir).undo(operation['id'])
            equal(uploaded, payload)
        check('rename, recoverable remove and persistent undo', rename_remove)

        def conflicts():
            current = FileEngine(engine.state_dir)
            current.transfer([source], folder, conflict='keep')
            second = folder / 'Grüße 日本語 (2).bin'
            equal(uploaded, payload)
            equal(second, payload)
            replacement = local / 'replacement'
            replacement.mkdir()
            replacing = replacement / source.name
            replacing.write_bytes(b'generated replacement')
            operation = current.transfer([replacing], folder, conflict='replace')
            equal(uploaded, replacing.read_bytes())
            FileEngine(engine.state_dir).undo(operation['id'])
            equal(uploaded, payload)
        check('keep-both and replacement with exact original recovery', conflicts)

        def changed_target():
            current = FileEngine(engine.state_dir)
            current.rename(uploaded, 'changed-target.bin')
            renamed = folder / 'changed-target.bin'
            renamed.write_bytes(bytes(v ^ 255 for v in payload))
            try:
                FileEngine(engine.state_dir).undo()
            except SafetyError:
                equal(renamed, bytes(v ^ 255 for v in payload))
            else:
                raise AssertionError('Changed remote file was not protected')
        check('same-size remote content change blocks undo', changed_target)

    def queued_transfer():
        paused = local / 'paused.bin'
        paused.write_bytes(payload * 4)
        current = FileEngine(local / 'paused-recovery')
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
        resumed = FileEngine(current.state_dir)
        resumed.transfer([paused], folder, job_id=job['id'])
        equal(folder / paused.name, paused.read_bytes())
        assert not resumed.transfers.jobs()
        moving = local / 'move.bin'
        moving.write_bytes(payload)
        job = resumed.transfers.create([moving], folder, 'keep', move=True)
        operation = resumed.transfer([moving], folder, move=True, job_id=job['id'])
        assert not moving.exists()
        equal(folder / moving.name, payload)
        FileEngine(current.state_dir).undo(operation['id'])
        equal(moving, payload)
    check('4-MiB pause/resume and queued cross-volume move/undo', queued_transfer)

    def tools():
        tree = local / 'tree'
        (tree / 'nested').mkdir(parents=True)
        (tree / 'nested/Prüfung.txt').write_text('NAS test: Grüße 日本語\n', encoding='utf-8')
        current = FileEngine(local / 'tools-recovery')
        current.transfer([tree], folder)
        target = folder / tree.name
        rows, warnings = compare(tree, target, True, threading.Event())
        assert not warnings and rows and all(row[1] == 'equal' for row in rows)
        hits, warnings = search(target, '*.txt', False, False, threading.Event())
        assert not warnings and len(hits) == 1
        current.make_zip([target], folder / 'archive.zip')
        extracted = folder / 'extracted'
        extracted.mkdir()
        current.extract_zip(folder / 'archive.zip', extracted)
        equal(extracted / 'tree/nested/Prüfung.txt', (tree / 'nested/Prüfung.txt').read_bytes())
    check('nested copy, search, content comparison and NAS ZIP roundtrip', tools)

    def locked_file():
        import win32file
        path = folder / 'locked.bin'
        path.write_bytes(payload)
        handle = win32file.CreateFile(str(path), win32file.GENERIC_READ, 0, None, win32file.OPEN_EXISTING, 0, None)
        try:
            try:
                FileEngine(local / 'locked-recovery').trash([path])
            except OSError:
                pass
            else:
                raise AssertionError('SMB exclusive share lock did not block removal')
        finally:
            handle.Close()
        equal(path, payload)
    check('busy remote file rejected with source retained', locked_file)

    def cleanup():
        assert folder.parent == share and folder.name == 'OpenCommander-NAS-Test-' + token
        assert marker.read_text(encoding='ascii') == token
        paths = list(folder.rglob('*'))
        assert all(folder in p.parents and not p.is_symlink() and not p.is_junction() for p in paths)
        for path in sorted(paths, key=lambda p: len(p.parts), reverse=True):
            if path != marker:
                path.rmdir() if path.is_dir() else path.unlink()
        marker.unlink()
        folder.rmdir()
        assert not folder.exists()
        results['cleanup'] = 'pass'
    check('remove only owned generated test data', cleanup)
    results['status'] = 'pass' if all(c['status'] == 'pass' for c in results['checks']) else 'failed'
    save()
    return 0 if results['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
