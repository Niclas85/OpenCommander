import errno
import os
from pathlib import Path
import stat
import zipfile

import pytest
from opencommander import operations as ops
from opencommander.operations import FileEngine, SafetyError, CleanupError, Cancelled
from opencommander.filesystem import listing, archive_listing


@pytest.fixture
def fixture(tmp_path):
    left, right = tmp_path / 'left', tmp_path / 'right'
    left.mkdir()
    right.mkdir()
    return FileEngine(tmp_path / 'state'), left, right


def write(path, value='fixture content'):
    path.write_text(value)
    return path


def test_copy_unicode_and_persistent_undo(fixture):
    engine, left, right = fixture
    source = write(left / 'Grüße 日本語.txt')
    engine.transfer([source], right)
    target = right / source.name
    assert target.read_bytes() == source.read_bytes()
    restarted = FileEngine(engine.state_dir)
    restarted.undo()
    assert not target.exists()
    assert source.exists()
    assert any(p.read_bytes() == source.read_bytes() for p in right.glob('.OpenCommanderUndo-*/*'))
    assert not restarted.history


def test_replacement_undo_restores_exact_old_inode(fixture):
    engine, left, right = fixture
    source = write(left / 'a', 'new')
    target = write(right / 'a', 'old')
    inode = target.stat().st_ino
    engine.transfer([source], right, conflict='replace')
    assert target.read_text() == 'new'
    engine.undo()
    assert target.read_text() == 'old'
    assert target.stat().st_ino == inode


def test_keep_both(fixture):
    engine, left, right = fixture
    source = write(left / 'a.txt', 'new')
    write(right / 'a.txt', 'old')
    engine.transfer([source], right)
    assert (right / 'a.txt').read_text() == 'old'
    assert (right / 'a (2).txt').read_text() == 'new'


def test_move_and_undo(fixture):
    engine, left, right = fixture
    source = write(left / 'a')
    engine.transfer([source], right, move=True)
    assert not source.exists()
    engine.undo()
    assert source.read_text() == 'fixture content'
    assert not (right / 'a').exists()


def test_move_undo_conflict_retains_both(fixture):
    engine, left, right = fixture
    source = write(left / 'a')
    engine.transfer([source], right, move=True)
    write(source, 'new file')
    with pytest.raises(SafetyError):
        engine.undo()
    assert source.read_text() == 'new file'
    assert (right / 'a').read_text() == 'fixture content'


def test_same_size_edit_even_with_original_mtime_stops_undo(fixture):
    engine, left, right = fixture
    source = write(left / 'a', 'one')
    engine.transfer([source], right)
    target = right / 'a'
    original = target.stat()
    write(target, 'two')
    os.utime(target, ns=(original.st_atime_ns, original.st_mtime_ns))
    with pytest.raises(SafetyError):
        engine.undo()
    assert target.read_text() == 'two'


def test_new_folder_child_stops_undo(fixture):
    engine, left, right = fixture
    engine.mkdir(right, 'new')
    write(right / 'new' / 'later.txt')
    with pytest.raises(SafetyError):
        engine.undo()
    assert (right / 'new' / 'later.txt').exists()


def test_undo_retry_after_partially_completed_batch(fixture):
    engine, left, right = fixture
    a, b = write(left / 'a'), write(left / 'b')
    engine.transfer([a, b], right)
    target = right / 'a'
    snapshot = target.stat()
    write(target, 'edited')
    with pytest.raises(SafetyError):
        engine.undo()
    assert not (right / 'b').exists()
    assert len(engine.history[-1]['records']) == 1
    write(target, 'fixture content')
    os.utime(target, ns=(snapshot.st_atime_ns, snapshot.st_mtime_ns))
    FileEngine(engine.state_dir).undo()
    assert not target.exists()


def test_copy_failure_never_displaces_target(fixture, monkeypatch):
    engine, left, right = fixture
    source = write(left / 'a', 'new')
    target = write(right / 'a', 'old')
    def fail(source, target):
        write(target, 'partial')
        raise OSError('injected disk full')
    monkeypatch.setattr(engine, 'copy_file', fail)
    with pytest.raises(OSError):
        engine.transfer([source], right, conflict='replace')
    assert target.read_text() == 'old'
    assert source.read_text() == 'new'
    assert not engine.history


def test_cross_volume_partial_source_delete_retains_complete_target(fixture, monkeypatch):
    engine, left, right = fixture
    source = left / 'folder'
    source.mkdir()
    write(source / 'a', 'one')
    write(source / 'b', 'two')
    real_rename = ops.rename_new
    def rename(from_path, target):
        if from_path == source:
            raise OSError(errno.EXDEV, 'injected cross-volume rename')
        real_rename(from_path, target)
    def partial_delete(path):
        (path / 'a').unlink()
        raise OSError('injected permission error')
    monkeypatch.setattr(ops, 'rename_new', rename)
    monkeypatch.setattr(ops, 'remove_tree', partial_delete)
    with pytest.raises(CleanupError):
        engine.transfer([source], right, move=True)
    assert (right / 'folder' / 'a').read_text() == 'one'
    assert (right / 'folder' / 'b').read_text() == 'two'
    assert (source / 'b').exists()


def test_atomic_publication_preserves_racing_writer(fixture, monkeypatch):
    engine, left, right = fixture
    source = write(left / 'a', 'source')
    real_copy = engine.copy_file
    def copy(source, target):
        real_copy(source, target)
        write(right / 'a', 'racing writer')
    monkeypatch.setattr(engine, 'copy_file', copy)
    with pytest.raises(FileExistsError):
        engine.transfer([source], right)
    assert (right / 'a').read_text() == 'racing writer'
    assert source.read_text() == 'source'


def test_symlinks_are_preserved_not_traversed(fixture):
    engine, left, right = fixture
    outside = write(left.parent / 'outside', 'private')
    link = left / 'link'
    link.symlink_to(outside)
    engine.transfer([link], right)
    assert (right / 'link').is_symlink()
    engine.undo()
    assert outside.read_text() == 'private'


def test_dangling_symlink_is_a_conflict(fixture):
    engine, left, right = fixture
    source = write(left / 'a')
    (right / 'a').symlink_to(right / 'missing')
    with pytest.raises(FileExistsError):
        ops.rename_new(source, right / 'a')
    assert source.exists()
    assert (right / 'a').is_symlink()


def test_nested_target_and_selected_descendants(fixture):
    engine, left, right = fixture
    folder = left / 'folder'
    folder.mkdir()
    child = write(folder / 'a')
    with pytest.raises(SafetyError):
        engine.transfer([folder], folder)
    engine.transfer([folder, child], right)
    assert len(engine.history[-1]['records']) == 1


def test_rename_new_folder_and_recoverable_remove(fixture):
    engine, left, right = fixture
    engine.mkdir(left, 'new')
    engine.rename(left / 'new', 'renamed')
    engine.trash([left / 'renamed'])
    assert not (left / 'renamed').exists()
    engine.undo()
    engine.undo()
    engine.undo()
    assert not (left / 'new').exists()


def test_zip_roundtrip_and_undo(fixture):
    engine, left, right = fixture
    folder = left / '資料'
    folder.mkdir()
    write(folder / 'Grüße.txt', 'hello')
    (folder / 'empty').mkdir()
    archive = left / 'test.zip'
    engine.make_zip([folder], archive)
    assert archive_listing(archive)[0].name == '資料'
    engine.extract_zip(archive, right)
    assert (right / '資料' / 'Grüße.txt').read_text() == 'hello'
    assert (right / '資料' / 'empty').is_dir()
    engine.undo()
    assert not (right / '資料').exists()


@pytest.mark.parametrize('name', ['../escape', '/absolute', 'a/../../escape', 'a\\b'])
def test_zip_slip_is_rejected(fixture, name):
    engine, left, right = fixture
    archive = left / 'unsafe.zip'
    with zipfile.ZipFile(archive, 'w') as out:
        out.writestr(name, 'unsafe')
    with pytest.raises(SafetyError):
        engine.extract_zip(archive, right)
    assert list(right.iterdir()) == []


def test_zip_symlink_rejected(fixture):
    engine, left, right = fixture
    archive = left / 'link.zip'
    with zipfile.ZipFile(archive, 'w') as out:
        info = zipfile.ZipInfo('link')
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        out.writestr(info, '/etc')
    with pytest.raises(SafetyError):
        engine.extract_zip(archive, right)


def test_cancel_leaves_no_partial_copy(fixture):
    engine, left, right = fixture
    source = write(left / 'a')
    engine.cancel.set()
    with pytest.raises(Cancelled):
        engine.transfer([source], right)
    assert source.exists()
    assert list(right.iterdir()) == []


def test_unreadable_history_is_retained(fixture):
    engine, left, right = fixture
    engine.history_file.write_text('broken history')
    reopened = FileEngine(engine.state_dir)
    with pytest.raises(SafetyError):
        reopened.transfer([write(left / 'a')], right)
    assert engine.history_file.read_text() == 'broken history'


def test_hidden_files_filter_and_missing_directory(fixture):
    _, left, right = fixture
    write(left / '.hidden')
    write(left / 'visible')
    assert [entry.name for entry in listing(left)] == ['visible']
    assert len(listing(left, hidden=True)) == 2
    with pytest.raises(FileNotFoundError):
        listing(right / 'missing')


def test_active_recovery_profile_cannot_be_removed(fixture):
    engine, left, right = fixture
    with pytest.raises(SafetyError):
        engine.trash([engine.state_dir])
    with pytest.raises(SafetyError):
        engine.rename(engine.state_dir, 'moved-state')
    assert engine.state_dir.is_dir()


def test_transfer_reports_nested_file_and_byte_totals(tmp_path):
    from opencommander.operations import FileEngine
    source = tmp_path / 'source'; source.mkdir()
    (source / 'empty').write_bytes(b'')
    child = source / 'sub'; child.mkdir()
    (child / 'data').write_bytes(b'hello')
    (child / 'link').symlink_to('data')
    target = tmp_path / 'target'; target.mkdir()
    engine = FileEngine(tmp_path / 'state')
    reports = []
    engine.metrics_report = reports.append
    engine.transfer([source], target)
    assert reports[0]['phase'] == 'planning'
    assert reports[-1]['phase'] == 'complete'
    assert reports[-1]['files_total'] == reports[-1]['files_done'] == 3
    assert reports[-1]['bytes_total'] == reports[-1]['bytes_done'] == 5
    assert any(row['phase'] == 'verifying' for row in reports)


def test_fast_move_reports_files_without_copying(tmp_path):
    from opencommander.operations import FileEngine
    source = tmp_path / 'source'; source.write_bytes(b'hello')
    target = tmp_path / 'target'; target.mkdir()
    engine = FileEngine(tmp_path / 'state')
    reports = []
    engine.metrics_report = reports.append
    engine.transfer([source], target, move=True)
    assert reports[-1]['files_done'] == reports[-1]['files_total'] == 1
    assert reports[-1]['bytes_done'] == reports[-1]['bytes_total'] == 5
    assert not source.exists()


def test_provider_unsupported_fsync_and_mode_keep_bytes_timestamps_and_undo(fixture, monkeypatch):
    from opencommander import provider_mounts
    engine, left, right = fixture
    monkeypatch.setattr(provider_mounts, '_roots', {right})
    folder = left / '01_Anreise'
    folder.mkdir()
    source = write(folder / '20241104_164044.jpg', 'exact fixture bytes')
    os.utime(source, ns=(1700000000000000000, 1700000000000000000))
    real_sync, real_chmod = os.fsync, os.chmod
    def fsync(fd):
        path = Path(os.readlink(f'/proc/self/fd/{fd}'))
        if right in path.parents:
            raise OSError(errno.EOPNOTSUPP, 'fixture unsupported fsync', str(path))
        return real_sync(fd)
    def chmod(path, mode, **kwargs):
        if right == Path(path) or right in Path(path).parents:
            raise OSError(errno.EOPNOTSUPP, 'fixture unsupported chmod', str(path))
        return real_chmod(path, mode, **kwargs)
    monkeypatch.setattr(os, 'fsync', fsync)
    monkeypatch.setattr(os, 'chmod', chmod)
    operation = engine.transfer([folder], right)
    target = right / folder.name / source.name
    assert target.read_bytes() == source.read_bytes()
    assert target.stat().st_mtime_ns == source.stat().st_mtime_ns
    assert len(operation['warnings']) == 2
    assert not list(right.glob('.OpenCommanderTransfer-*'))
    assert FileEngine(engine.state_dir).history[-1]['warnings'] == operation['warnings']
    engine.undo()
    assert not (right / folder.name).exists()
    assert source.exists()


@pytest.mark.parametrize('number,provider', [(errno.EIO, True), (errno.ENOSPC, True),
                                             (errno.EACCES, True), (errno.EOPNOTSUPP, False)])
def test_real_sync_errors_and_local_unsupported_sync_fail_safely(fixture, monkeypatch, number, provider):
    from opencommander import provider_mounts
    engine, left, right = fixture
    monkeypatch.setattr(provider_mounts, '_roots', {right} if provider else set())
    monkeypatch.setattr(provider_mounts, 'provider_mount', lambda _: None)
    source = write(left / 'original.jpg')
    original = os.fsync
    def fsync(fd):
        path = Path(os.readlink(f'/proc/self/fd/{fd}'))
        if right in path.parents:
            raise OSError(number, 'fixture failure', str(path))
        return original(fd)
    monkeypatch.setattr(os, 'fsync', fsync)
    with pytest.raises(OSError) as error:
        engine.transfer([source], right)
    assert error.value.errno == number
    assert source.read_text() == 'fixture content'
    assert not (right / source.name).exists()
    assert not list(right.glob('.OpenCommanderTransfer-*'))
    assert not engine.history


def test_missing_nofollow_chmod_api_does_not_fail_after_writing(fixture, monkeypatch):
    engine, left, right = fixture
    source = write(left / 'file.webp', 'complete image fixture')
    os.utime(source, ns=(1700000000000000000, 1700000000000000000))
    def copystat(*args, **kwargs):
        raise NotImplementedError('chmod: follow_symlinks unavailable on this platform')
    original = os.chmod
    def chmod(path, mode, **kwargs):
        if kwargs.get('follow_symlinks') is False:
            raise NotImplementedError('chmod: follow_symlinks unavailable on this platform')
        return original(path, mode, **kwargs)
    monkeypatch.setattr(ops.shutil, 'copystat', copystat)
    monkeypatch.setattr(os, 'chmod', chmod)
    operation = engine.transfer([source], right)
    target = right / source.name
    assert target.read_bytes() == source.read_bytes()
    assert target.stat().st_mtime_ns == source.stat().st_mtime_ns
    assert operation['warnings']
    assert len(operation['records']) == 1
    engine.undo()
    assert source.exists() and not target.exists()


def test_undo_cancel_during_verification_retains_both_files(fixture, monkeypatch):
    engine, left, right = fixture
    source = left / 'large.bin'
    source.write_bytes(b'x' * 3 * 1024**2)
    operation = engine.transfer([source], right)
    check = engine.check_cancel
    checks = 0
    def cancel_inside_hash():
        nonlocal checks
        checks += 1
        if checks == 3:
            engine.cancel.set()
        check()
    monkeypatch.setattr(engine, 'check_cancel', cancel_inside_hash)
    with pytest.raises(Cancelled):
        engine.undo(operation['id'])
    assert (right / source.name).read_bytes() == source.read_bytes()
    assert not operation['records'][0]['reverted']
    engine.cancel.clear()
    monkeypatch.setattr(engine, 'check_cancel', check)
    engine.undo(operation['id'])
    assert not (right / source.name).exists()


def test_local_listing_stops_when_cancelled(tmp_path, monkeypatch):
    import threading
    from types import SimpleNamespace
    from opencommander import filesystem
    cancel = threading.Event()
    seen = []
    class Stream:
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def __iter__(self):
            for number in range(10000):
                seen.append(number)
                if number == 5:
                    cancel.set()
                yield SimpleNamespace(name='.hidden')
    monkeypatch.setattr(filesystem, 'remote_location', lambda _: False)
    monkeypatch.setattr(filesystem.os, 'scandir', lambda _: Stream())
    assert filesystem.listing(tmp_path, cancel=cancel) == []
    assert len(seen) == 6
