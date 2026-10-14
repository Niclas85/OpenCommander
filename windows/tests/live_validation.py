"""Opt-in live validation using only a newly created, explicitly owned fixture.

Run against the installed source and frozen helper. NAS writes are confined to
the unique folder recorded in live-context.json; no existing user data is read.
"""
import argparse
from pathlib import Path
import json
import os
import sys
import threading
import time
import traceback
import subprocess
import wave
import zipfile
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[2]
CONTEXT = REPO / 'windows/build/live-context.json'
context = json.loads(CONTEXT.read_text(encoding='utf-8-sig'))
ROOT = Path(context['root'])
STATE = Path(context['state'])
INSTALLED = Path(context['installed'])
assert ROOT.name == 'OpenCommander-Pruefung-' + context['id']
sys.path.insert(0, str(INSTALLED / 'source/linux'))
from opencommander import platform_support, rclone_runtime
platform_support.helper_command = lambda name: [str(INSTALLED / 'helpers/OpenCommanderHelper.exe'), name]
rclone_runtime.binary = lambda: str(INSTALLED / 'tools/rclone.exe')
from opencommander.operations import FileEngine, SafetyError, Cancelled
from opencommander import windows_native, windows_mounts
from opencommander.filesystem import Entry, listing, archive_listing
from opencommander.commander_tools import compare, search, rename_plan, rename_batch

REPORT = REPO / 'windows/build/live-results.json'
results = []


def save():
    REPORT.write_text(json.dumps(dict(context=context, results=results), ensure_ascii=False, indent=2), encoding='utf-8')


def case(name, callback):
    started = time.monotonic()
    try:
        details = callback()
        results.append(dict(name=name, status='pass', seconds=round(time.monotonic()-started, 3), details=details))
        print('PASS: ' + name, flush=True)
    except Exception as error:
        results.append(dict(name=name, status='fail', seconds=round(time.monotonic()-started, 3), error=str(error),
                            traceback=traceback.format_exc()))
        print('FAIL: ' + name + ': ' + str(error), flush=True)
    save()


def setup():
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / '.opencommander-test-owner.json').write_text(json.dumps(context), encoding='utf-8')
    for name in ('UI-links', 'UI-rechts', 'core', 'remote-fixture'):
        (ROOT / name).mkdir(exist_ok=True)
    left = ROOT / 'UI-links'
    (left / 'Kopiertest Grüße 日本語.txt').write_text('OpenCommander – praktische Windows-Prüfung\n', encoding='utf-8')
    (left / 'Ordner').mkdir(exist_ok=True)
    (left / 'Ordner/Unterdatei.txt').write_bytes(b'nested fixture')
    (left / '.Versteckt.txt').write_bytes(b'hidden fixture')
    from PySide6.QtGui import QImage, QColor, QPainter
    from PySide6.QtCore import Qt, QSettings
    from PySide6.QtWidgets import QApplication
    app = QApplication.instance() or QApplication([])
    image = QImage(640, 360, QImage.Format_RGB32); image.fill(QColor('#245d8d'))
    painter = QPainter(image); painter.setPen(QColor('white'))
    painter.drawText(image.rect(), Qt.AlignCenter, 'OpenCommander Windows – Bildtest'); painter.end()
    image.save(str(left / 'Bild.png'))
    with wave.open(str(left / 'Ton.wav'), 'wb') as output:
        output.setnchannels(1); output.setsampwidth(2); output.setframerate(8000)
        output.writeframes(b'\0\0' * 16000)
    import imageio_ffmpeg
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run([ffmpeg, '-v', 'error', '-y', '-f', 'lavfi', '-i', 'color=c=blue:s=320x180:d=2',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(left / 'Video.mp4')], check=True, timeout=30)
    with zipfile.ZipFile(left / 'Archiv.zip', 'w') as archive:
        archive.writestr('Ordner/Archivdatei.txt', 'archive fixture')
    settings = QSettings(str(STATE / 'ui/settings.ini'), QSettings.IniFormat)
    settings.setValue('language', 'de'); settings.setValue('windows_default_prompted', True); settings.sync()
    context['nas_root'] = r'\\192.168.0.22\Test\OpenCommander-Pruefung-' + context['id']
    CONTEXT.write_text(json.dumps(context, indent=2), encoding='utf-8')
    return dict(left=str(left), right=str(ROOT / 'UI-rechts'), video=str(left / 'Video.mp4'))


def sandbox(name):
    root = ROOT / 'core' / (name + '-' + str(time.time_ns())); root.mkdir()
    left, right = root / 'left', root / 'right'; left.mkdir(); right.mkdir()
    return FileEngine(STATE / 'core' / root.name), left, right


def local_operations():
    engine, left, right = sandbox('operations')
    source = left / 'Grüße 日本語.bin'; data = bytes(range(256)) * 1024; source.write_bytes(data)
    operation = engine.transfer([source], right)
    assert (right / source.name).read_bytes() == data
    restarted = FileEngine(engine.state_dir); restarted.undo(operation['id'])
    assert not (right / source.name).exists() and source.read_bytes() == data
    operation = restarted.transfer([source], right, move=True)
    assert not source.exists() and (right / source.name).read_bytes() == data
    restarted.undo(operation['id']); assert source.read_bytes() == data
    (right / source.name).write_bytes(b'previous')
    operation = restarted.transfer([source], right, conflict='replace')
    assert (right / source.name).read_bytes() == data
    restarted.undo(operation['id']); assert (right / source.name).read_bytes() == b'previous'
    restarted.transfer([source], right, conflict='keep')
    assert (right / 'Grüße 日本語 (2).bin').read_bytes() == data
    restarted.rename(source, 'Umbenannt.bin'); source = left / 'Umbenannt.bin'
    restarted.trash([source]); assert not source.exists()
    restarted.undo(); assert source.read_bytes() == data
    restarted.mkdir(left, 'Neuer Ordner'); assert (left / 'Neuer Ordner').is_dir()
    return 'copy, move, replace, keep both, rename, mkdir, recoverable trash and persistent undo on exFAT'


def cross_volume():
    engine, left, right = sandbox('cross-volume')
    source = STATE / 'cross-volume-source.bin'; data = bytes(range(256)) * 4096; source.write_bytes(data)
    operation = engine.transfer([source], right, move=True)
    assert not source.exists() and (right / source.name).read_bytes() == data
    engine.undo(operation['id']); assert source.read_bytes() == data
    return 'NTFS C: -> exFAT D: move and undo, content verified'


def pause_resume():
    engine, left, right = sandbox('pause-resume')
    source = left / 'large.bin'
    with source.open('wb') as out:
        for _ in range(16): out.write(bytes(range(256)) * 4096)
    job = engine.transfers.create([source], right, 'keep')
    def pause(count, name):
        if count >= 1024**2: engine.pause.set(); engine.cancel.set()
    engine.progress = pause
    try: engine.transfer([source], right, job_id=job['id'])
    except Cancelled: pass
    else: raise AssertionError('pause did not stop transfer')
    assert engine.transfers.get(job['id'])['status'] == 'paused'
    restarted = FileEngine(engine.state_dir); restarted.transfer([source], right, job_id=job['id'])
    assert (right / source.name).read_bytes() == source.read_bytes()
    assert not restarted.transfers.jobs()
    return '16 MiB transfer paused at 1 MiB and completed from persisted checkpoint'


def modified_undo():
    engine, left, right = sandbox('modified-undo')
    source = left / 'file'; source.write_bytes(b'original')
    engine.transfer([source], right); (right / 'file').write_bytes(b'changed!')
    try: engine.undo()
    except SafetyError: pass
    else: raise AssertionError('modified destination was not protected')
    assert (right / 'file').read_bytes() == b'changed!' and source.read_bytes() == b'original'
    return 'changed destination retained; undo stopped'


def archives():
    import libarchive
    engine, left, right = sandbox('archives')
    source = left / 'archive-source'; source.mkdir(); (source / 'file.txt').write_bytes(b'archive data')
    zip_path = left / 'created.zip'; engine.make_zip([source], zip_path)
    assert archive_listing(zip_path)[0].directory
    archive_results = []
    for kind, compression, suffix in [('ustar', None, '.tar'), ('ustar', 'gzip', '.tgz'), ('ustar','bzip2','.tar.bz2'),
                                      ('ustar','xz','.tar.xz'), ('ustar','zstd','.tar.zst'), ('7zip',None,'.7z')]:
        path = left / ('native' + suffix)
        with libarchive.file_writer(str(path), kind, compression) as writer:
            writer.add_file_from_memory('folder/file.txt', 12, b'archive data')
        output = right / suffix.lstrip('.'); output.mkdir()
        engine.extract_zip(path, output); assert (output / 'folder/file.txt').read_bytes() == b'archive data'
        engine.undo(); assert not (output / 'folder').exists()
        archive_results.append(suffix)
    rar = REPO / 'linux/tests/fixtures/rar5-stored.rar'; output=right/'rar';output.mkdir()
    engine.extract_zip(rar, output); assert (output/'helloworld.txt').stat().st_size == 29
    return ['ZIP create/browse', *archive_results, 'RAR5 extract']


def tools():
    engine, left, right = sandbox('tools')
    for name in ('a.txt', 'b.txt'):
        (left/name).write_bytes(b'fixture'); (right/name).write_bytes(b'fixture')
    rows, warnings = compare(left, right, True, threading.Event()); assert all(r[1]=='equal' for r in rows)
    (right/'b.txt').write_bytes(b'changed'); rows,_=compare(left,right,True,threading.Event())
    assert next(r for r in rows if r[0]=='b.txt')[1] == 'different'
    matches,_=search(left,'*.txt',True,False,threading.Event()); assert len(matches)==2
    plan=rename_plan([left/'a.txt',left/'b.txt'],pattern='Datei-[C][E]'); rename_batch(engine,plan)
    assert (left/'Datei-001.txt').exists() and (left/'Datei-002.txt').exists()
    engine.undo(); assert (left/'a.txt').exists() and (left/'b.txt').exists()
    return 'search, content comparison, multi-rename preview/execution and undo'


def nas():
    root = Path(context['nas_root']); root.mkdir()
    (root / '.opencommander-test-owner.json').write_text(json.dumps({'id':context['id']}), encoding='utf-8')
    left, right=root/'left',root/'right';left.mkdir();right.mkdir()
    engine=FileEngine(STATE/'nas')
    file=left/'Grüße 日本語.bin';data=bytes(range(256))*1024;file.write_bytes(data)
    listing_rows=windows_native.invoke('scan',str(left));assert any(r['name']==file.name for r in listing_rows)
    engine.transfer([file],right);assert (right/file.name).read_bytes()==data
    restarted=FileEngine(engine.state_dir);restarted.undo();assert not (right/file.name).exists()
    operation=restarted.transfer([file],right,move=True);assert not file.exists()
    restarted.undo(operation['id']);assert file.read_bytes()==data
    operation=restarted.trash([file]);assert not file.exists();restarted.undo(operation['id']);assert file.read_bytes()==data
    props=windows_native.invoke('properties',str(file));assert props['size']==len(data)
    return dict(root=str(root),bytes=len(data),operations='Unicode listing, copy/move/trash/undo, properties, byte comparison')


def mount():
    from opencommander.online_ui import private_config
    root=ROOT/'remote-fixture';(root/'read.txt').write_bytes(b'remote fixture')
    state=STATE/'mount';config=private_config(state)
    config.write_text('[oc_live_alias]\ntype = alias\nremote = '+str(root)+'\n',encoding='utf-8')
    main=SimpleNamespace(state_dir=state,server_secrets={})
    profile=dict(id='oc_live_alias',kind='alias',name='Live mount test')
    mounted=windows_mounts.mount_profile(main,profile,threading.Event())
    try:
        assert (mounted/'read.txt').read_bytes()==b'remote fixture'
        assert windows_native.mount_identity(mounted)['filesystem']=='fuse.rclone'
        assert windows_native.invoke('scan',str(mounted))[0]['name']=='read.txt'
        source=ROOT/'mount-upload.txt';source.write_bytes(b'uploaded through WinFsp')
        engine=FileEngine(STATE/'mount-engine');engine.transfer([source],mounted)
        assert (root/source.name).read_bytes()==source.read_bytes()
        engine.undo();assert not (root/source.name).exists()
    finally:
        windows_mounts.unmount(mounted)
    return 'actual rclone + WinFsp mount, frozen helper listing, upload/undo, authenticated graceful unmount'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--setup',action='store_true');parser.add_argument('--only')
    args=parser.parse_args()
    if args.setup:
        case('prepare-fixtures',setup);return
    global results
    if REPORT.exists():results=json.loads(REPORT.read_text(encoding='utf-8'))['results']
    cases=[('local-operations',local_operations),('cross-volume',cross_volume),('pause-resume',pause_resume),
           ('modified-undo',modified_undo),('archives',archives),('commander-tools',tools),('nas-smb',nas),('winfsp-mount',mount)]
    for name,callback in cases:
        if not args.only or args.only==name:case(name,callback)


if __name__=='__main__':main()
