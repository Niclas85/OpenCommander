import threading
from pathlib import Path
import pytest
from opencommander import commander_tools as tools
from opencommander.operations import FileEngine, SafetyError, Cancelled


def test_search_unicode_case_hidden_links_and_limit(tmp_path):
    (tmp_path / 'Grüße.TXT').write_text('a')
    (tmp_path / '.hidden').write_text('b')
    (tmp_path / 'folder').mkdir()
    (tmp_path / 'folder/sub.txt').write_text('c')
    (tmp_path / 'link').symlink_to(tmp_path / 'folder', target_is_directory=True)
    cancel = threading.Event()
    entries, warnings = tools.search(tmp_path, '*.txt', False, False, cancel)
    assert sorted(entry.name for entry in entries) == ['Grüße.TXT', 'sub.txt']
    assert not warnings
    assert [entry.name for entry in tools.search(tmp_path, '*.txt', False, True, cancel)[0]] == ['sub.txt']
    assert not tools.search(tmp_path, 'hidden', False, False, cancel)[0]
    assert len(tools.search(tmp_path, 'hidden', True, False, cancel)[0]) == 1
    assert len(tools.scan(tmp_path, False, cancel)[0]) == 4
    with pytest.raises(SafetyError, match='Limit'):
        tools.scan(tmp_path, False, cancel, limit=1)
    cancel.set()
    with pytest.raises(Cancelled):
        tools.search(tmp_path, '', True, False, cancel)


def test_search_directory_rejects_relative():
    with pytest.raises(SafetyError):
        tools.search_directory('relative')
    assert tools.search_directory('~/') == Path.home()


def test_comparison_checks_content_not_just_size(tmp_path):
    left, right = tmp_path / 'a', tmp_path / 'b'
    left.mkdir(); right.mkdir()
    for root in (left, right):
        (root / 'same').write_text('same')
    (left / 'different').write_text('aaa')
    (right / 'different').write_text('bbb')
    (left / 'only').write_text('l')
    rows, warnings = tools.compare(left, right, False, threading.Event())
    assert {name: state for name, state, _ in rows} == {'different': 'different', 'only': 'left', 'same': 'equal'}
    assert not warnings


def test_rename_preview_execution_persistence_and_undo(tmp_path):
    a, b = tmp_path / 'A.txt', tmp_path / 'B.txt'
    a.write_text('a'); b.write_text('b')
    plan = tools.rename_plan([b, a], 'Foto-[C]-[N][E]', start=4, digits=2)
    assert [row.destination.name for row in plan] == ['Foto-04-A.txt', 'Foto-05-B.txt']
    engine = FileEngine(tmp_path / 'state')
    tools.rename_batch(engine, plan)
    assert not a.exists() and plan[0].destination.read_text() == 'a'
    reloaded = FileEngine(tmp_path / 'state')
    reloaded.undo()
    assert a.read_text() == 'a' and b.read_text() == 'b'


@pytest.mark.parametrize('pattern', ['../escape', '.', 'same.txt', '[N]/bad', '[N]:bad', 'x' * 256])
def test_rename_refuses_invalid_duplicate_destinations(tmp_path, pattern):
    paths = [tmp_path / name for name in ('a.txt', 'b.txt')]
    for path in paths:
        path.write_text('original')
    with pytest.raises(SafetyError):
        tools.rename_plan(paths, pattern)
    assert all(path.read_text() == 'original' for path in paths)


def test_stale_rename_preview_and_collision(tmp_path):
    path = tmp_path / 'a.txt'
    path.write_text('original')
    plan = tools.rename_plan([path], 'new[E]')
    path.write_text('changed')
    engine = FileEngine(tmp_path / 'state')
    with pytest.raises(SafetyError, match='stale'):
        tools.rename_batch(engine, plan)
    assert path.read_text() == 'changed' and not engine.history
    (tmp_path / 'new.txt').write_text('occupied')
    with pytest.raises(SafetyError, match='occupied'):
        tools.rename_plan([path], 'new[E]')


def test_batch_failure_rolls_back_completed_changes(tmp_path, monkeypatch):
    paths = [tmp_path / name for name in ('a.txt', 'b.txt')]
    for path in paths:
        path.write_text(path.name)
    plan = tools.rename_plan(paths, 'new-[C][E]')
    engine = FileEngine(tmp_path / 'state')
    real = tools.rename_new
    def fail(source, target):
        if source == paths[1]:
            raise OSError('simulated failure')
        real(source, target)
    monkeypatch.setattr(tools, 'rename_new', fail)
    with pytest.raises(OSError):
        tools.rename_batch(engine, plan)
    assert all(path.read_text() == path.name for path in paths)
    assert not engine.history
