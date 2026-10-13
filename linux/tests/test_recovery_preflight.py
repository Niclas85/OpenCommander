"""Mac safety backport; these refusal paths do not depend on renameat2/FUSE."""
from pathlib import Path

import pytest
from opencommander.operations import FileEngine, SafetyError


def fixture(tmp_path):
    target = tmp_path / 'current.txt'
    target.write_text('current synthetic data')
    previous = tmp_path / 'previous.txt'
    previous.write_text('previous synthetic data')
    engine = FileEngine(tmp_path / 'state')
    operation = engine.begin('copy')
    engine.record(operation, tmp_path / 'source.txt', target, 'copy', previous)
    return engine, operation, target, previous


@pytest.mark.parametrize('legacy', [False, True])
def test_missing_backup_never_displaces_visible_current_version(tmp_path, legacy):
    engine, operation, target, previous = fixture(tmp_path)
    if legacy:
        operation['records'][0].pop('backup_snapshot')
        engine.save()
    previous.unlink()
    with pytest.raises(SafetyError, match='previous version'):
        FileEngine(engine.state_dir).undo()
    assert target.read_text() == 'current synthetic data'
    assert operation['records'][0]['reverted'] is False
    assert not list(tmp_path.glob('.OpenCommanderUndo-*'))
    assert FileEngine(engine.state_dir).history[-1]['records'][0]['reverted'] is False


def test_changed_persisted_backup_never_displaces_current_version(tmp_path):
    engine, operation, target, previous = fixture(tmp_path)
    previous.write_text('changed synthetic backup')
    with pytest.raises(SafetyError, match='previous version'):
        FileEngine(engine.state_dir).undo()
    assert target.read_text() == 'current synthetic data'
    assert previous.read_text() == 'changed synthetic backup'
    assert not list(tmp_path.glob('.OpenCommanderUndo-*'))


def test_new_unverifiable_backup_cannot_silently_become_a_different_old_version(tmp_path):
    engine, operation, target, previous = fixture(tmp_path)
    operation['records'][0]['backup_snapshot'] = None
    engine.save()
    with pytest.raises(SafetyError, match='previous version'):
        engine.undo()
    assert target.read_text() == 'current synthetic data'
    assert previous.exists()


@pytest.mark.parametrize('key', ['undo_backup_unavailable', 'undo_changed', 'undo_occupied'])
def test_undo_error_uses_current_language_without_changing_the_path(key):
    from opencommander.i18n import text, operation_error
    from opencommander.history_ui import describe
    path = '/synthetic/Grüsse und 東京/previous.txt'
    message = text('en', key) + '\n' + path
    assert operation_error(message, 'de') == text('de', key) + '\n' + path
    assert operation_error(message, 'en') == message
    operation = dict(records=[], error=message)
    german = describe(operation, True)
    assert text('de', key) in german and 'Undo stopped' not in german and path in german
    assert message in describe(operation, False)


def test_unknown_error_is_not_reclassified_from_an_undo_phrase_in_the_filename():
    from opencommander.i18n import operation_error
    message = 'Unknown failure\n/folder/Undo stopped: original path is occupied.'
    assert operation_error(message, 'de') == message


def test_checkpoint_backup_string_has_a_persisted_fingerprint(tmp_path):
    from opencommander.operations import fingerprint
    target = tmp_path / 'target.txt'; target.write_text('new synthetic contents')
    backup = tmp_path / 'previous.txt'; backup.write_text('old synthetic contents')
    engine = FileEngine(tmp_path / 'state')
    operation = engine.begin('copy')
    # Resumable-copy journals store paths as JSON strings rather than Path.
    engine.record(operation, tmp_path / 'source.txt', target, 'copy', str(backup), cancellable=True)
    assert operation['records'][0]['backup_snapshot'] == fingerprint(backup)
    assert FileEngine(engine.state_dir).history[-1]['records'][0]['backup_snapshot'] == fingerprint(backup)
