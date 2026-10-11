from pathlib import Path
import os
import stat

import pytest

from opencommander.operations import FileEngine, Cancelled, SafetyError
from opencommander.resumable_copy import discard
from opencommander.transfer_store import guards_for


@pytest.fixture
def fixture(tmp_path):
    source, target = tmp_path / 'source', tmp_path / 'target'
    source.mkdir()
    target.mkdir()
    return FileEngine(tmp_path / 'state'), source, target


def run(engine, job):
    return engine.transfer(job['sources'], job['directory'], False, job['conflict'], job['id'])


def pause_after_block(engine, name=None):
    def progress(count, current):
        if name is None or current == name:
            engine.pause.set()
            engine.cancel.set()
    engine.progress = progress


def test_partial_file_survives_restart_and_resumes_bytes(fixture):
    engine, source, target = fixture
    file = source / 'large.bin'
    file.write_bytes(b'a' * 1024**2 + b'b' * 1024**2 + b'c' * 1024**2)
    job = engine.transfers.create([file], target, 'keep', guards_for([file, target]))
    pause_after_block(engine)
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    assert saved['status'] == 'paused'
    payload = Path(saved['roots'][0]['staging']) / 'payload'
    assert payload.stat().st_size == 1024**2
    inode = payload.stat().st_ino
    assert not (target / file.name).exists()
    resumed = FileEngine(engine.state_dir)
    counts = []
    resumed.progress = lambda count, name: counts.append(count)
    operation = run(resumed, saved)
    destination = target / file.name
    assert counts[0] == 2 * 1024**2
    assert destination.stat().st_ino == inode
    assert destination.read_bytes() == file.read_bytes()
    assert not resumed.transfers.jobs()
    assert not list(target.glob('.OpenCommanderTransfer-*'))
    resumed.undo(operation['id'])
    assert not destination.exists() and file.exists()


def test_completed_files_in_folder_are_verified_not_recopied(fixture, monkeypatch):
    engine, source, target = fixture
    folder = source / 'journey'
    folder.mkdir()
    (folder / 'a.jpg').write_bytes(b'a' * 1024)
    (folder / 'b.jpg').write_bytes(b'b' * 2 * 1024**2)
    (folder / 'empty').mkdir()
    os.symlink('a.jpg', folder / 'link')
    job = engine.transfers.create([folder], target, 'keep')
    pause_after_block(engine, 'b.jpg')
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    payload = Path(saved['roots'][0]['staging']) / 'payload'
    inode = (payload / 'a.jpg').stat().st_ino
    resumed = FileEngine(engine.state_dir)
    metadata = []
    original = resumed.copy_metadata
    monkeypatch.setattr(resumed, 'copy_metadata', lambda src, dst: (metadata.append(src.name), original(src, dst)))
    run(resumed, saved)
    destination = target / folder.name
    assert (destination / 'a.jpg').stat().st_ino == inode
    assert 'a.jpg' not in metadata
    assert (destination / 'b.jpg').read_bytes() == (folder / 'b.jpg').read_bytes()
    assert (destination / 'empty').is_dir()
    assert os.readlink(destination / 'link') == 'a.jpg'


def test_explicit_cancel_discards_partial_and_queued_jobs(fixture):
    engine, source, target = fixture
    file = source / 'large.bin'
    file.write_bytes(b'a' * 2 * 1024**2)
    job = engine.transfers.create([file], target, 'keep')
    engine.progress = lambda *_: engine.cancel.set()
    with pytest.raises(Cancelled):
        run(engine, job)
    assert not engine.transfers.jobs()
    assert not list(target.iterdir())
    assert file.exists()
    queued = engine.transfers.create([file], target, 'keep')
    discard(engine, queued['id'])
    assert not engine.transfers.jobs()


@pytest.mark.parametrize('change', ['source', 'partial', 'mount'])
def test_resume_stops_if_source_partial_or_mount_changed(fixture, monkeypatch, change):
    engine, source, target = fixture
    file = source / 'large.bin'
    file.write_bytes(b'a' * 2 * 1024**2)
    job = engine.transfers.create([file], target, 'keep', guards_for([file, target]))
    pause_after_block(engine)
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    payload = Path(saved['roots'][0]['staging']) / 'payload'
    if change == 'source':
        file.write_bytes(b'changed')
    elif change == 'partial':
        payload.write_bytes(b'wrong data')
    else:
        import opencommander.resumable_copy as copies
        monkeypatch.setattr(copies, 'mount_identity', lambda path: None)
    resumed = FileEngine(engine.state_dir)
    with pytest.raises(SafetyError):
        run(resumed, saved)
    assert resumed.transfers.get(job['id'])['status'] == 'blocked'
    assert payload.exists() and not (target / file.name).exists()


def test_pause_between_roots_preserves_one_history_and_no_duplicates(fixture):
    engine, source, target = fixture
    a, b = source / 'a', source / 'b'
    a.write_bytes(b'a')
    b.write_bytes(b'b' * 2 * 1024**2)
    job = engine.transfers.create([a, b], target, 'keep')
    pause_after_block(engine, 'b')
    with pytest.raises(Cancelled):
        run(engine, job)
    assert (target / 'a').read_bytes() == b'a'
    first_inode = (target / 'a').stat().st_ino
    with pytest.raises(SafetyError, match='Resume or cancel'):
        engine.undo()
    resumed = FileEngine(engine.state_dir)
    run(resumed, resumed.transfers.get(job['id']))
    assert (target / 'a').stat().st_ino == first_inode
    assert len(resumed.history) == 1
    assert len(resumed.history[0]['records']) == 2
    assert 'paused' not in resumed.history[0] and 'error' not in resumed.history[0]
    resumed.undo()
    assert not (target / 'a').exists() and not (target / 'b').exists()


def test_pause_during_published_history_check_keeps_destination(fixture, monkeypatch):
    engine, source, target = fixture
    file = source / 'a'
    file.write_bytes(b'a')
    job = engine.transfers.create([file], target, 'keep')
    original = engine.record
    def pause(*args, **kwargs):
        engine.pause.set()
        engine.cancel.set()
        return original(*args, **kwargs)
    monkeypatch.setattr(engine, 'record', pause)
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    assert saved['roots'][0]['status'] == 'published'
    assert (target / 'a').read_bytes() == b'a'
    resumed = FileEngine(engine.state_dir)
    run(resumed, saved)
    assert len(resumed.history[0]['records']) == 1
    assert not (target / 'a (2)').exists()


def test_replacement_pause_keeps_original_and_undo_backup(fixture):
    engine, source, target = fixture
    file = source / 'a'
    file.write_bytes(b'a' * 2 * 1024**2)
    (target / 'a').write_bytes(b'original')
    job = engine.transfers.create([file], target, 'replace')
    pause_after_block(engine)
    with pytest.raises(Cancelled):
        run(engine, job)
    assert (target / 'a').read_bytes() == b'original'
    resumed = FileEngine(engine.state_dir)
    run(resumed, resumed.transfers.get(job['id']))
    assert (target / 'a').read_bytes() == file.read_bytes()
    resumed.undo()
    assert (target / 'a').read_bytes() == b'original'


def test_checkpoint_store_private_and_corruption_is_preserved(fixture):
    engine, source, target = fixture
    path = engine.transfers.path
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    path.write_bytes(b'not a database')
    restarted = FileEngine(engine.state_dir)
    assert restarted.transfers.error
    assert path.read_bytes() == b'not a database'


def test_copy_continues_in_fresh_python_process(fixture):
    import subprocess
    import sys
    engine, source, target = fixture
    file = source / 'large.bin'
    file.write_bytes(b'a' * 2 * 1024**2)
    job = engine.transfers.create([file], target, 'keep')
    pause_after_block(engine)
    with pytest.raises(Cancelled):
        run(engine, job)
    code = '''import sys
from opencommander.operations import FileEngine
engine = FileEngine(sys.argv[1])
job = engine.transfers.get(sys.argv[2])
engine.transfer(job['sources'], job['directory'], False, job['conflict'], job['id'])
assert not engine.transfers.jobs()
assert len(engine.history[0]['records']) == 1
'''
    env = dict(os.environ, PYTHONPATH=str(Path(__file__).resolve().parents[1]))
    result = subprocess.run([sys.executable, '-c', code, str(engine.state_dir), job['id']],
                            capture_output=True, text=True, env=env, timeout=10)
    assert result.returncode == 0, result.stderr
    assert (target / file.name).read_bytes() == file.read_bytes()


def test_ambiguous_crash_during_publish_stops_without_duplicate_or_deletion(fixture, monkeypatch):
    engine, source, target = fixture
    file = source / 'a'
    file.write_bytes(b'a')
    job = engine.transfers.create([file], target, 'keep')
    original = engine.publish
    def crash(*args, **kwargs):
        original(*args, **kwargs)
        raise KeyboardInterrupt('simulated process termination')
    monkeypatch.setattr(engine, 'publish', crash)
    with pytest.raises(KeyboardInterrupt):
        run(engine, job)
    restarted = FileEngine(engine.state_dir)
    with pytest.raises(SafetyError, match='Inspect interrupted publication'):
        run(restarted, restarted.transfers.get(job['id']))
    assert restarted.transfers.get(job['id'])['status'] == 'blocked'
    with pytest.raises(SafetyError, match='Inspect interrupted publication'):
        discard(restarted, job['id'])
    assert (target / file.name).read_bytes() == b'a'
    assert not (target / 'a (2)').exists()


def test_cancel_paused_copy_when_destination_disconnected_retains_checkpoint(fixture, monkeypatch):
    engine, source, target = fixture
    file = source / 'large.bin'
    file.write_bytes(b'a' * 2 * 1024**2)
    job = engine.transfers.create([file], target, 'keep', guards_for([file, target]))
    pause_after_block(engine)
    with pytest.raises(Cancelled):
        run(engine, job)
    import opencommander.resumable_copy as copies
    monkeypatch.setattr(copies, 'mount_identity', lambda path: None)
    with pytest.raises(SafetyError, match='Reconnect destination'):
        discard(engine, job['id'])
    assert engine.transfers.get(job['id'])['status'] == 'blocked'


def test_changed_completed_staged_file_is_not_published(fixture):
    engine, source, target = fixture
    folder = source / 'folder'
    folder.mkdir()
    (folder / 'a').write_bytes(b'a')
    (folder / 'b').write_bytes(b'b' * 2 * 1024**2)
    job = engine.transfers.create([folder], target, 'keep')
    pause_after_block(engine, 'b')
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    (Path(saved['roots'][0]['staging']) / 'payload/a').write_bytes(b'x')
    restarted = FileEngine(engine.state_dir)
    with pytest.raises(SafetyError, match='Partial copy changed'):
        run(restarted, saved)
    assert not (target / folder.name).exists()
