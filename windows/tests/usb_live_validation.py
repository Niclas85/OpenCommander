"""Explicitly authorized removable-drive acceptance and optional safe eject."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import traceback
import uuid

REPO = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--drive', required=True)
    parser.add_argument('--expected-label', required=True)
    parser.add_argument('--allow-device-writes', required=True, action='store_true')
    parser.add_argument('--eject', action='store_true', help='Only after passing checks and removing generated data')
    args = parser.parse_args()
    import win32api
    import win32file
    root = Path(args.drive)
    assert root.is_absolute() and root == Path(root.anchor) and not str(root).startswith('\\\\')
    assert win32file.GetDriveType(str(root)) == 2, 'Only removable drive roots may be tested'
    assert win32api.GetVolumeInformation(str(root))[0] == args.expected_label
    installed = Path(os.environ['LOCALAPPDATA']) / 'Programs/OpenCommander'
    sys.path.insert(0, str(installed / 'source/linux'))
    from opencommander import platform_support, windows_native, windows_wpd
    from opencommander.operations import FileEngine
    platform_support.helper_command = lambda name: [str(installed / 'helpers/OpenCommanderHelper.exe'), name]
    identity = windows_native.mount_identity(root)
    token = uuid.uuid4().hex
    folder = root / ('OpenCommander-USB-Test-' + token)
    marker = folder / 'OPENCOMMANDER-TEST-OWNER.txt'
    local = REPO / 'windows/build/usb-hardware' / token
    local.mkdir(parents=True)
    engine = FileEngine(local / 'recovery')
    payload = bytes(range(256)) * 4096
    source = local / 'Grüße 日本語.bin'
    source.write_bytes(payload)
    results = dict(drive=str(root), label=args.expected_label, checks=[], cleanup=False,
                   safe_eject_requested=args.eject, installed_helper=True,
                   installed_exe_sha256=hashlib.sha256((installed / 'OpenCommander.exe').read_bytes()).hexdigest())
    def save():
        text = json.dumps(results, ensure_ascii=False, indent=2)
        (local / 'results.json').write_text(text, encoding='utf-8')
        (REPO / 'windows/build/usb-hardware-results.json').write_text(text, encoding='utf-8')
    def check(name, action):
        start = time.monotonic()
        print('START', name, flush=True)
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
    def transfers():
        locations = windows_native.invoke('list')
        assert len([row for row in locations if row['id'] == str(root) and row['kind'] == 'USB']) == 1
        assert all(windows_wpd.device_service(row['id'][4:]).casefold() != 'wudfwpdfs'
                   for row in locations if row.get('kind') == 'MTP')
        engine.transfer([source], folder)
        uploaded = folder / source.name
        equal(uploaded, payload)
        rows = windows_native.invoke('scan', str(folder))
        assert any(row['name'] == source.name and row['size'] == len(payload) for row in rows)
        target = local / 'download'
        target.mkdir()
        engine.transfer([uploaded], target)
        equal(target / source.name, payload)
        moving = local / 'move.bin'
        moving.write_bytes(payload)
        operation = engine.transfer([moving], folder, move=True)
        assert not moving.exists()
        equal(folder / moving.name, payload)
        FileEngine(engine.state_dir).undo(operation['id'])
        equal(moving, payload)
        assert not (folder / moving.name).exists()
    check('Unicode 1-MiB roundtrip, native helper, cross-volume move and persistent undo', transfers)
    def cleanup():
        assert windows_native.mount_identity(root) == identity
        assert folder.parent == root and folder.name == 'OpenCommander-USB-Test-' + token
        assert marker.read_text(encoding='ascii') == token
        paths = list(folder.rglob('*'))
        assert all(folder in p.parents and not p.is_symlink() and not p.is_junction() for p in paths)
        for path in sorted(paths, key=lambda p: len(p.parts), reverse=True):
            if path != marker:
                path.rmdir() if path.is_dir() else path.unlink()
        marker.unlink()
        folder.rmdir()
        assert not folder.exists()
        results['cleanup'] = True
    check('remove only owned test data before eject', cleanup)
    if args.eject and results['cleanup'] and all(c['status'] == 'pass' for c in results['checks']):
        def eject():
            assert windows_native.mount_identity(root) == identity
            assert win32file.GetDriveType(str(root)) == 2
            assert win32api.GetVolumeInformation(str(root))[0] == args.expected_label
            # Windows shell performs safe removal. Never force-disconnect,
            # offline the disk, remove a drive letter, or close other apps.
            locations = windows_native.invoke('eject', str(root))
            assert not any(row.get('id') == str(root) for row in locations)
            try:
                win32api.GetVolumeInformation(str(root))
            except Exception as error:
                assert getattr(error, 'winerror', None) in windows_native._REMOVED_MEDIA_ERRORS
            else:
                raise AssertionError('Volume still available after eject')
            results['safe_eject'] = True
        check('safe eject through installed Windows helper', eject)
    results['status'] = 'pass' if all(c['status'] == 'pass' for c in results['checks']) else 'failed'
    save()
    return 0 if results['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
