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


def test_rejected_publication_resumes_complete_staging_without_recopy(fixture,monkeypatch):
    import errno
    engine,source,target=fixture
    folder=source/'project';folder.mkdir();(folder/'large.zip').write_bytes(b'a'*3*1024**2)
    job=engine.transfers.create([folder],target,'keep',guards_for([folder,target]))
    def reject(*args):raise OSError(errno.EINVAL,'unsupported no-replace rename')
    monkeypatch.setattr(engine,'publish',reject)
    with pytest.raises(OSError):run(engine,job)
    saved=engine.transfers.get(job['id'])
    assert saved['roots'][0]['status']=='publishing'
    stage=Path(saved['roots'][0]['staging'])
    inode=(stage/'payload/large.zip').stat().st_ino
    resumed=FileEngine(engine.state_dir)
    reports=[];writes=[]
    resumed.metrics_report=lambda value:reports.append(dict(value))
    resumed.progress=lambda *args:writes.append(args)
    run(resumed,saved)
    assert not writes and not resumed.transfers.jobs()
    assert (target/'project/large.zip').stat().st_ino==inode
    assert (target/'project/large.zip').read_bytes()==b'a'*3*1024**2
    assert folder.is_dir() and not stage.exists()
    assert any(r['phase']=='publishing' for r in reports)
    assert max(r.get('verify_bytes_checked',0) for r in reports)==3*1024**2
    assert reports[-1]['phase']=='complete' and reports[-1]['bytes_done']==3*1024**2


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


def test_legacy_stage_reuses_full_and_partial_files_without_rewriting_full_file(fixture, monkeypatch):
    import opencommander.resumable_copy as copies
    engine, source, target = fixture
    folder = source / 'Weltreise'
    folder.mkdir()
    (folder / 'a').write_bytes(b'complete')
    (folder / 'b').write_bytes(b'b' * 2 * 1024**2)
    (folder / 'c').write_bytes(b'missing')
    stage = target / '.OpenCommanderTransfer-legacy'
    payload = stage / 'payload'
    payload.mkdir(parents=True)
    (payload / 'a').write_bytes(b'complete')
    (payload / 'b').write_bytes(b'b' * 1024**2)
    inode = (payload / 'a').stat().st_ino
    original = copies.open_regular
    def forbid_rewrite(path, flags):
        assert path != payload / 'a' or not flags & (os.O_WRONLY | os.O_RDWR)
        return original(path, flags)
    monkeypatch.setattr(copies, 'open_regular', forbid_rewrite)
    monkeypatch.setattr(engine, 'plan_transfer', lambda paths: pytest.fail('Backend totals should avoid a full FUSE scan'))
    size = sum(file.stat().st_size for file in folder.iterdir())
    job = engine.transfers.create([folder], target, 'keep', legacy_staging=stage, legacy_totals=(size, 3))
    run(engine, job)
    destination = target / folder.name
    assert (destination / 'a').stat().st_ino == inode
    assert all((destination / file.name).read_bytes() == file.read_bytes() for file in folder.iterdir())
    assert not stage.exists() and not engine.transfers.jobs()
    engine.undo()
    assert not destination.exists()


def test_legacy_data_mismatch_remains_unmodified_and_unpublished(fixture):
    engine, source, target = fixture
    folder = source / 'Weltreise'
    folder.mkdir()
    (folder / 'a').write_bytes(b'source')
    stage = target / '.OpenCommanderTransfer-legacy'
    payload = stage / 'payload'
    payload.mkdir(parents=True)
    (payload / 'a').write_bytes(b'wrong!')
    job = engine.transfers.create([folder], target, 'keep', legacy_staging=stage)
    with pytest.raises(SafetyError, match='Partial data mismatch'):
        run(engine, job)
    assert (payload / 'a').read_bytes() == b'wrong!'
    assert not (target / folder.name).exists()
    assert engine.transfers.get(job['id'])['status'] == 'blocked'


@pytest.mark.parametrize('condition', ['previous', 'symlink'])
def test_legacy_unknown_original_or_symlink_requires_inspection(fixture, condition):
    engine, source, target = fixture
    folder = source / 'Weltreise'
    folder.mkdir()
    (folder / 'a').write_bytes(b'a')
    stage = target / '.OpenCommanderTransfer-legacy'
    stage.mkdir()
    if condition == 'previous':
        (stage / 'payload').mkdir()
        (stage / 'previous').write_bytes(b'original')
    else:
        os.symlink(folder, stage / 'payload')
    job = engine.transfers.create([folder], target, 'keep', legacy_staging=stage)
    with pytest.raises(SafetyError, match='requires inspection'):
        run(engine, job)
    assert (folder / 'a').read_bytes() == b'a'
    assert not (target / folder.name).exists()
    if condition == 'previous':
        assert (stage / 'previous').read_bytes() == b'original'


def test_legacy_staging_must_be_on_exact_target_volume(fixture):
    engine, source, target = fixture
    file = source / 'a'
    file.write_bytes(b'a')
    with pytest.raises(ValueError, match='Invalid legacy'):
        engine.transfers.create([file], target, 'keep', legacy_staging=source / '.OpenCommanderTransfer-invalid')
    assert not engine.transfers.jobs()


def test_resumable_native_move_and_undo(fixture):
    engine, source, target = fixture
    file = source / 'move.bin'
    file.write_bytes(b'original')
    inode = file.stat().st_ino
    job = engine.transfers.create([file], target, 'keep', move=True)
    operation = run(engine, job)
    assert not file.exists() and (target / file.name).stat().st_ino == inode
    assert operation['label'] == 'move' and operation['records'][0]['kind'] == 'move'
    assert not engine.transfers.jobs()
    engine.undo(operation['id'])
    assert file.read_bytes() == b'original' and not (target / file.name).exists()


def force_cross_device(monkeypatch, source):
    import errno
    import opencommander.resumable_copy as copies
    rename = copies.rename_new
    def cross_device(src, dst):
        if Path(src) == source and not Path(dst).parent.name.startswith('.OpenCommanderMove-'):
            raise OSError(errno.EXDEV, 'cross device')
        return rename(src, dst)
    monkeypatch.setattr(copies, 'rename_new', cross_device)


def test_cross_device_move_pause_restart_and_undo(fixture, monkeypatch):
    engine, source, target = fixture
    file = source / 'move.bin'
    file.write_bytes(b'a' * 3 * 1024**2)
    force_cross_device(monkeypatch, file)
    job = engine.transfers.create([file], target, 'keep', move=True)
    pause_after_block(engine)
    with pytest.raises(Cancelled):
        run(engine, job)
    assert file.exists() and not (target / file.name).exists()
    resumed = FileEngine(engine.state_dir)
    operation = run(resumed, job)
    assert not file.exists() and (target / file.name).read_bytes() == b'a' * 3 * 1024**2
    assert not list(source.glob('.OpenCommanderMove-*'))
    resumed.undo(operation['id'])
    assert file.read_bytes() == b'a' * 3 * 1024**2


def test_move_source_changed_after_copy_is_retained(fixture, monkeypatch):
    engine, source, target = fixture
    file = source / 'move.bin'
    file.write_bytes(b'original')
    force_cross_device(monkeypatch, file)
    record = engine.record
    def changing_record(*args, **kwargs):
        record(*args, **kwargs)
        file.write_bytes(b'changed')
    monkeypatch.setattr(engine, 'record', changing_record)
    job = engine.transfers.create([file], target, 'keep', move=True)
    with pytest.raises(SafetyError, match='Changed source retained'):
        run(engine, job)
    assert file.read_bytes() == b'changed'
    assert (target / file.name).read_bytes() == b'original'
    assert engine.transfers.get(job['id'])['status'] == 'blocked'


def test_move_pause_during_source_cleanup_resumes_remaining_files(fixture, monkeypatch):
    import opencommander.resumable_copy as copies
    engine, source, target = fixture
    folder = source / 'folder'
    folder.mkdir()
    (folder / 'a').write_bytes(b'a')
    (folder / 'b').write_bytes(b'b')
    force_cross_device(monkeypatch, folder)
    remove = copies.remove_move_backup
    removed = []
    def pause_cleanup(current, job, index, path, origin):
        result = remove(current, job, index, path, origin)
        if path.name == 'a':
            removed.append(path.name)
            current.pause.set()
            current.cancel.set()
        return result
    monkeypatch.setattr(copies, 'remove_move_backup', pause_cleanup)
    job = engine.transfers.create([folder], target, 'keep', move=True)
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    assert saved['status'] == 'paused' and saved['roots'][0]['status'] == 'cleanup'
    backup = Path(saved['roots'][0]['source_backup'])
    assert (backup / 'b').read_bytes() == b'b'
    assert (target / 'folder' / 'a').read_bytes() == b'a'
    monkeypatch.setattr(copies, 'remove_move_backup', remove)
    resumed = FileEngine(engine.state_dir)
    operation = run(resumed, saved)
    assert not backup.parent.exists() and not resumed.transfers.jobs()
    resumed.undo(operation['id'])
    assert (folder / 'a').read_bytes() == b'a' and (folder / 'b').read_bytes() == b'b'


def test_independent_engines_serialize_shared_history(fixture):
    import concurrent.futures
    engine, source, target = fixture
    forks = [engine.fork() for _ in range(3)]
    files = []
    for index in range(4):
        file = source / str(index)
        file.write_bytes(bytes([index]) * 1024**2)
        files.append(file)
    jobs = [engine.transfers.create([file], target, 'keep') for file in files]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda pair: run(*pair), zip([engine]+forks, jobs)))
    restored = FileEngine(engine.state_dir)
    assert len(restored.history) == 4 and not restored.transfers.jobs()
    assert {operation['id'] for operation in restored.history} == {operation['id'] for operation in results}
    assert all((target / file.name).read_bytes() == file.read_bytes() for file in files)
    assert len({id(worker.cancel) for worker in [engine]+forks}) == 4


def test_rclone_resume_restarts_only_verified_partial_file(fixture, monkeypatch):
    from opencommander import provider_mounts
    engine, source, target = fixture
    folder = source / 'folder'
    folder.mkdir()
    (folder / 'a.txt').write_bytes(b'complete')
    (folder / 'b.bin').write_bytes(b'b' * 2 * 1024**2)
    job = engine.transfers.create([folder], target, 'keep')
    pause_after_block(engine, 'b.bin')
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    payload = Path(saved['roots'][0]['staging']) / 'payload'
    partial = payload / 'b.bin'
    assert (payload / 'a.txt').read_bytes() == b'complete'
    assert partial.stat().st_size == 1024**2
    monkeypatch.setattr(provider_mounts, 'rclone_mount', lambda path: (target, 'fixture'))
    partial.write_bytes(b'c' * 1024**2)
    with pytest.raises(SafetyError, match='Partial data mismatch'):
        run(FileEngine(engine.state_dir), saved)
    assert partial.read_bytes() == b'c' * 1024**2
    partial.write_bytes(b'b' * 1024**2)
    original_open = os.open
    writes = []
    def opening(path, flags, *args, **kwargs):
        if Path(path).parent == payload and flags & os.O_WRONLY:
            writes.append((Path(path).name, bool(flags & os.O_TRUNC)))
        return original_open(path, flags, *args, **kwargs)
    monkeypatch.setattr(os, 'open', opening)
    resumed = FileEngine(engine.state_dir)
    operation = run(resumed, saved)
    assert writes == [('b.bin', True)]
    assert (target / 'folder' / 'a.txt').read_bytes() == b'complete'
    assert (target / 'folder' / 'b.bin').read_bytes() == (folder / 'b.bin').read_bytes()
    assert any('Partial file restarted' in value for value in operation['warnings'])


def test_error_resume_preserves_completed_progress_and_never_rewrites_finished_files(fixture, monkeypatch):
    import errno
    engine, source, target = fixture
    folder = source / 'journey'
    folder.mkdir()
    (folder / 'a.bin').write_bytes(b'a' * 2 * 1024**2)
    (folder / 'b.bin').write_bytes(b'b' * 2 * 1024**2)
    job = engine.transfers.create([folder], target, 'keep')
    original_open = os.open
    def fail_second(path, flags, *args, **kwargs):
        if Path(path).name == 'b.bin' and flags & os.O_WRONLY:
            raise OSError(errno.EIO, 'simulated provider write failure')
        return original_open(path, flags, *args, **kwargs)
    monkeypatch.setattr(os, 'open', fail_second)
    with pytest.raises(OSError, match='simulated provider'):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    assert saved['status'] == 'blocked'
    assert 'simulated provider' in saved['last_error']
    assert saved['progress']['bytes_done'] == 2 * 1024**2
    writes = []
    events = []
    from opencommander import resumable_copy
    original_digest = resumable_copy.digest_file
    def digest(*args, **kwargs):
        events.append(('verify', Path(args[1]).name))
        return original_digest(*args, **kwargs)
    monkeypatch.setattr(resumable_copy, 'digest_file', digest)
    def observe(path, flags, *args, **kwargs):
        if flags & os.O_WRONLY:
            writes.append(Path(path).name)
            events.append(('write', Path(path).name))
        return original_open(path, flags, *args, **kwargs)
    monkeypatch.setattr(os, 'open', observe)
    resumed = FileEngine(engine.state_dir)
    metrics = []
    resumed.metrics_report = metrics.append
    operation = run(resumed, saved)
    assert 'a.bin' not in writes and writes.count('b.bin') == 1
    assert events.index(('write', 'b.bin')) < events.index(('verify', 'a.bin'))
    assert metrics[0]['bytes_done'] == 2 * 1024**2
    assert metrics[0]['files_done'] == 1
    assert metrics[0]['bytes_resumed'] == 2 * 1024**2
    checking = [m for m in metrics if m['phase'] == 'resuming']
    assert any(m['resume_bytes_checked'] == 1024**2 for m in checking)
    assert any(m['resume_files_checked'] == 1 for m in checking)
    assert all(m['bytes_done'] >= 2 * 1024**2 for m in metrics)
    assert metrics[-1]['bytes_done'] == metrics[-1]['bytes_total'] == 4 * 1024**2
    assert metrics[-1]['files_done'] == metrics[-1]['files_total'] == 2
    assert len(operation['transfer_errors']) == 1
    assert 'simulated provider' in operation['transfer_errors'][0]['message']
    assert all((target / 'journey' / p.name).read_bytes() == p.read_bytes() for p in folder.iterdir())


def test_pause_during_resume_verification_keeps_saved_baseline(fixture):
    engine, source, target = fixture
    folder = source / 'journey'
    folder.mkdir()
    (folder / 'a.bin').write_bytes(b'a' * 3 * 1024**2)
    (folder / 'b.bin').write_bytes(b'b' * 2 * 1024**2)
    job = engine.transfers.create([folder], target, 'keep')
    pause_after_block(engine, 'b.bin')
    with pytest.raises(Cancelled):
        run(engine, job)
    resumed = FileEngine(engine.state_dir)
    def pause_check(value):
        if value.get('resume_bytes_checked', 0) >= 1024**2:
            resumed.pause.set()
            resumed.cancel.set()
    resumed.metrics_report = pause_check
    with pytest.raises(Cancelled):
        run(resumed, resumed.transfers.get(job['id']))
    saved = resumed.transfers.get(job['id'])
    assert saved['status'] == 'paused'
    assert saved['progress']['bytes_done'] == 5 * 1024**2
    assert saved['progress']['files_done'] == 2
    assert saved['progress']['resume_bytes_checked'] == 1024**2
    final = FileEngine(engine.state_dir)
    values = []
    final.metrics_report = values.append
    run(final, saved)
    assert values[0]['bytes_done'] == 5 * 1024**2
    assert values[-1]['bytes_done'] == 5 * 1024**2


def test_completed_checkpoint_tampering_is_still_detected(fixture):
    engine, source, target = fixture
    folder = source / 'journey'
    folder.mkdir()
    (folder / 'a.bin').write_bytes(b'a' * 1024)
    (folder / 'b.bin').write_bytes(b'b' * 2 * 1024**2)
    job = engine.transfers.create([folder], target, 'keep')
    pause_after_block(engine, 'b.bin')
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    finished = Path(saved['roots'][0]['staging']) / 'payload/a.bin'
    before = finished.stat()
    finished.write_bytes(b'x' * before.st_size)
    os.utime(finished, ns=(before.st_atime_ns, before.st_mtime_ns))
    with pytest.raises(SafetyError, match='Partial copy changed'):
        run(FileEngine(engine.state_dir), saved)
    assert not (target / 'journey').exists()


@pytest.mark.parametrize('kind', ['local', 'online'])
def test_unavailable_mount_does_not_erase_saved_progress(fixture, monkeypatch, kind):
    import opencommander.resumable_copy as copies
    engine, source, target = fixture
    file = source / 'a.bin'
    file.write_bytes(b'a' * 2 * 1024**2)
    job = engine.transfers.create([file], target, 'keep', guards_for([file, target]))
    pause_after_block(engine)
    with pytest.raises(Cancelled):
        run(engine, job)
    saved = engine.transfers.get(job['id'])
    before = saved['progress'].copy()
    if kind == 'online':
        saved['guards'][0]['mount']={'root':str(source),'filesystem':'fuse.rclone','device':'fixture:'}
        engine.transfers.save(saved)
    monkeypatch.setattr(copies, 'mount_identity', lambda _: None)
    resumed = FileEngine(engine.state_dir)
    message='Drive missing' if kind=='local' else 'Reconnect the online drive'
    with pytest.raises(SafetyError, match=message):
        run(resumed, saved)
    failed = resumed.transfers.get(job['id'])
    assert failed['progress'] == before
    assert failed['status'] == 'blocked'
    assert message in failed['last_error']


@pytest.mark.parametrize('proof', ['matching', 'different', 'unavailable'])
def test_saved_file_eio_uses_only_matching_remote_digest_without_rewriting(fixture, monkeypatch, proof):
    import errno
    import hashlib
    from opencommander import resumable_copy, cloud_verify
    engine, source, target = fixture
    file = target / 'saved.jpg'
    payload = b'previously completed bytes'
    file.write_bytes(payload)
    expected = hashlib.sha256(payload).hexdigest()
    engine.transfer_metrics = {'resume_bytes_checked': 10}
    def broken(*args, **kwargs):
        engine.transfer_metrics['resume_bytes_checked'] += 3
        raise OSError(errno.EIO, 'simulated FUSE read error')
    monkeypatch.setattr(resumable_copy, 'digest_file', broken)
    monkeypatch.setattr(cloud_verify, 'server_digest', lambda *a: expected if proof == 'matching' else '0' * 64 if proof == 'different' else None)
    if proof == 'matching':
        resumable_copy.verify_saved_file(engine, file, len(payload), expected)
        assert engine.transfer_metrics['resume_bytes_checked'] == 10 + len(payload)
        assert engine.transfer_metrics['verification_source'] == 'provider'
    else:
        with pytest.raises(SafetyError if proof == 'different' else OSError):
            resumable_copy.verify_saved_file(engine, file, len(payload), expected)
    assert file.read_bytes() == payload


def test_saved_file_permission_error_never_uses_remote_fallback(fixture, monkeypatch):
    import errno
    from opencommander import resumable_copy, cloud_verify
    engine, source, target = fixture
    file = target / 'saved.jpg';file.write_bytes(b'fixture')
    engine.transfer_metrics = {'resume_bytes_checked': 0}
    monkeypatch.setattr(resumable_copy, 'digest_file', lambda *a, **k: (_ for _ in ()).throw(OSError(errno.EACCES, 'permission denied')))
    calls = []
    monkeypatch.setattr(cloud_verify, 'server_digest', lambda *a: calls.append(a))
    with pytest.raises(OSError):
        resumable_copy.verify_saved_file(engine, file, 7, '0' * 64)
    assert not calls
