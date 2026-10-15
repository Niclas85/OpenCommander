"""Checkpointed copies into private target-volume staging.

Pause keeps staging; explicit cancel removes unpublished staging. Published
destinations are never removed on error. An ambiguous interrupted publication
stops for inspection rather than guessing which file belongs to this job.
"""
import hashlib
import errno
import os
from pathlib import Path
import shutil
import stat
import tempfile
import time

from .operations import (Cancelled, SafetyError, exists, selected_roots,
                         validate_target, unique_path, rename_new, safe_snapshot, recorded_snapshot)
from .transfer_store import mount_identity
from .platform_support import is_link, canonical_path


def signature(info):
    return [info.st_mode, info.st_size, info.st_mtime_ns]


def open_regular(path, flags):
    if os.name == 'nt':
        from .windows_native import open_regular as windows_open
        return windows_open(path, flags)
    fd = os.open(path, flags | os.O_NOFOLLOW)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise SafetyError(f'Keine reguläre Datei / Not a regular file: {path}')
    return fd


def digest_file(engine, path, resuming=False):
    digest = hashlib.sha256()
    with os.fdopen(open_regular(path, os.O_RDONLY), 'rb') as stream:
        while True:
            engine.check_cancel()
            block = stream.read(1024 * 1024)
            if not block:
                return digest.hexdigest()
            digest.update(block)
            if resuming:
                engine.transfer_metrics['resume_bytes_checked'] += len(block)
                engine.report_transfer('resuming', path.name)


def verify_saved_file(engine, target, size, expected):
    engine.transfer_metrics.pop('verification_source', None)
    baseline = engine.transfer_metrics['resume_bytes_checked']
    try:
        if target.lstat().st_size != size or digest_file(engine, target, resuming=True) != expected:
            raise SafetyError(f'Zwischenstand geändert / Partial copy changed: {target}')
    except OSError as error:
        if error.errno != errno.EIO:
            raise
        from .cloud_verify import server_digest
        engine.check_cancel()
        digest = server_digest(engine, target, size)
        if digest is None:
            raise
        if digest != expected:
            raise SafetyError(f'Cloud-Zwischenstand geändert / Cloud partial copy changed: {target}') from None
        engine.transfer_metrics['resume_bytes_checked'] = baseline + size
        engine.transfer_metrics['verification_source'] = 'provider'
        engine.report_transfer('resuming', target.name)


def copy_file(engine, source, target):
    store = engine.transfers
    job, index, origin = engine.resuming_copy
    relative = source.relative_to(origin).as_posix()
    saved = store.file(job['id'], index, relative)
    credited = bool(saved and saved.get('complete'))
    engine.check_cancel()
    deferred = getattr(engine, 'deferred_copy_checks', None)
    if credited and deferred is not None:
        # Resume unfinished work first. Completed subtrees stay read-only and
        # are fully verified below before anything is published or removed.
        deferred.append((source, target))
        return
    engine.report_transfer('resuming' if credited else 'copying', source.name)
    info = source.lstat()
    current = signature(info)
    if saved and saved['source'] != current:
        raise SafetyError(f'Quelle seit Pause geändert / Source changed since pause: {source}')
    if not saved:
        if exists(target) and not job.get('legacy_staging'):
            # A process may have died after mkdir/create but before its checkpoint.
            raise SafetyError(f'Unbekannter Zwischenstand / Unrecognized partial file: {target}')
        saved = dict(source=current, complete=False)
        if stat.S_ISDIR(info.st_mode):
            saved['children'] = sorted(child.name for child in source.iterdir())
        store.checkpoint(job['id'], index, relative, saved)
    if stat.S_ISLNK(info.st_mode):
        link = os.readlink(source)
        if saved.get('link', link) != link:
            raise SafetyError(f'Quellverknüpfung geändert / Source link changed: {source}')
        saved['link'] = link
        if exists(target):
            if not target.is_symlink() or os.readlink(target) != link:
                raise SafetyError(f'Zwischenstand geändert / Partial copy changed: {target}')
        else:
            os.symlink(link, target, target_is_directory=bool(getattr(info, 'st_file_attributes', 0) & 16))
    elif stat.S_ISDIR(info.st_mode):
        if sorted(child.name for child in source.iterdir()) != saved['children']:
            raise SafetyError(f'Quellordner geändert / Source folder changed: {source}')
        if exists(target):
            if is_link(target) or not target.is_dir() or any(child.name not in saved['children'] for child in target.iterdir()):
                raise SafetyError(f'Zwischenordner geändert / Partial folder changed: {target}')
        else:
            target.mkdir()
        for name in saved['children']:
            engine.copy_file(source / name, target / name)
        engine.copy_metadata(source, target)
    elif stat.S_ISREG(info.st_mode):
        if saved['complete']:
            verify_saved_file(engine, target, info.st_size, saved['digest'])
        else:
            digest = hashlib.sha256()
            offset = 0
            with os.fdopen(open_regular(source, os.O_RDONLY), 'rb') as inp:
                if exists(target):
                    from .provider_mounts import portable
                    if portable(target):
                        # A paused upload can still have rclone's synthetic
                        # timestamp cached. Refresh before opening the read-only
                        # verification handle so both metadata checks describe
                        # the device object, not two different cache generations.
                        from .windows_devices import settle
                        settle(target)
                    with os.fdopen(open_regular(target, os.O_RDONLY), 'rb') as previous:
                        partial_info = os.fstat(previous.fileno())
                        while True:
                            engine.check_cancel()
                            block = previous.read(1024 * 1024)
                            if not block:
                                break
                            if inp.read(len(block)) != block:
                                raise SafetyError(f'Unvollständige Datei stimmt nicht überein / Partial data mismatch: {target}')
                            digest.update(block)
                            offset += len(block)
                            engine.report_transfer('checking_partial', source.name)
                    # A legacy or interrupted checkpoint can contain a full file.
                    # Its prefix was compared to the source; do not open it for
                    # writing, since cloud mounts may upload on writable close.
                    fd = None
                    if offset < info.st_size:
                        from .provider_mounts import rclone_mount, portable
                        engine.check_cancel()
                        if rclone_mount(target) is not None:
                            # Cache-off rclone accepts an append descriptor but
                            # fails on write (ESPIPE); closing it may also fail.
                            # Only restart our verified incomplete staging file.
                            # Finished files above remain read-only. Be conservative
                            # for external mounts whose cache mode can change.
                            inp.seek(0)
                            if portable(target):
                                # The device bridge rejects replacement PUTs.
                                # This is exclusively our incomplete staging
                                # file, whose entire prefix was just compared to
                                # the source. Recreate it with exclusive creation
                                # rather than asking WPD to overwrite an object.
                                current_partial = target.lstat()
                                if (not stat.S_ISREG(current_partial.st_mode) or current_partial.st_size != offset or
                                        (current_partial.st_dev, current_partial.st_ino, current_partial.st_mtime_ns) !=
                                        (partial_info.st_dev, partial_info.st_ino, partial_info.st_mtime_ns)):
                                    raise SafetyError(f'Zwischenstand geändert / Partial copy changed: {target}')
                                target.unlink()
                                fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                                             getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_BINARY', 0), 0o600)
                            else:
                                fd = open_regular(target, os.O_WRONLY | os.O_TRUNC)
                            digest = hashlib.sha256()
                            offset = 0
                            engine.compatibility_warnings.add(
                                'rclone: Unvollständige Datei beim Fortsetzen neu geschrieben; fertige Dateien erhalten / '
                                'Partial file restarted on resume; completed files retained')
                        else:
                            fd = open_regular(target, os.O_WRONLY | os.O_APPEND)
                            if os.fstat(fd).st_size != offset:
                                os.close(fd)
                                raise SafetyError(f'Zwischenstand geändert / Partial copy changed: {target}')
                else:
                    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_BINARY', 0), 0o600)
                engine.bytes_done += offset
                engine.transfer_metrics['bytes_resumed'] += offset
                if fd is not None:
                    write_rest(engine, inp, fd, source, target, digest)
                if signature(source.lstat()) != current or target.lstat().st_size != info.st_size:
                    engine.check_cancel()
                    raise SafetyError(f'Quelle während Kopie geändert / Source changed while copying: {source}')
            engine.copy_metadata(source, target)
            saved['digest'] = digest.hexdigest()
    else:
        raise SafetyError(f'Unsupported file: {source}')
    if signature(source.lstat()) != current:
        raise SafetyError(f'Quelle während Kopie geändert / Source changed while copying: {source}')
    saved['complete'] = True
    store.checkpoint(job['id'], index, relative, saved)
    if not stat.S_ISDIR(info.st_mode):
        if credited:
            engine.transfer_metrics['resume_files_checked'] += 1
        else:
            engine.transfer_metrics['files_done'] += 1
        engine.report_transfer('resuming' if credited else 'copying', source.name)


def write_rest(engine, inp, fd, source, target, digest):
    with os.fdopen(fd, 'wb') as out:
        try:
            while True:
                engine.check_cancel()
                block = inp.read(1024 * 1024)
                if not block:
                    break
                engine.check_cancel()
                out.write(block)
                digest.update(block)
                engine.bytes_done += len(block)
                engine.progress(engine.bytes_done, source.name)
                engine.report_transfer('copying', source.name)
            engine.report_transfer('uploading', source.name)
        finally:
            out.flush()
            if not engine.cancel.is_set() or engine.pause.is_set():
                try:
                    os.fsync(out.fileno())
                except OSError as error:
                    engine.unsupported_provider_feature(error, target,
                        'NAS/Online: Server-Dauerhaftigkeit nicht bestätigt / Server durability not confirmed')


def staging_for(job, root):
    stage = Path(root['staging'])
    if stage.parent != Path(job['directory']) or not stage.name.startswith('.OpenCommanderTransfer-'):
        raise SafetyError(f'Invalid copy staging: {stage}')
    if exists(stage) and (is_link(stage) or not stage.is_dir()):
        raise SafetyError(f'Copy staging changed: {stage}')
    return stage


def verify_move_source(engine, job, index, source, origin=None):
    """Never remove a source that changed after its checkpointed copy."""
    origin = origin or Path(job['roots'][index]['source'])
    saved = engine.transfers.file(job['id'], index, source.relative_to(origin).as_posix())
    engine.check_cancel()
    info = source.lstat()
    if not saved or not saved['complete'] or signature(info) != saved['source']:
        raise SafetyError(f'Quelle seit Kopie geändert; bleibt erhalten / Changed source retained: {source}')
    if stat.S_ISDIR(info.st_mode):
        if sorted(child.name for child in source.iterdir()) != saved['children']:
            raise SafetyError(f'Quellordner geändert; bleibt erhalten / Changed source retained: {source}')
        for name in saved['children']:
            verify_move_source(engine, job, index, source / name, origin)
    elif stat.S_ISREG(info.st_mode) and digest_file(engine, source) != saved['digest']:
        raise SafetyError(f'Quellinhalt geändert; bleibt erhalten / Changed source retained: {source}')
    elif stat.S_ISLNK(info.st_mode) and os.readlink(source) != saved.get('link'):
        raise SafetyError(f'Quellverknüpfung geändert; bleibt erhalten / Changed source retained: {source}')


def remove_move_backup(engine, job, index, path, origin):
    engine.check_cancel()
    saved = engine.transfers.file(job['id'], index, path.relative_to(origin).as_posix())
    info = path.lstat()
    if not saved or not saved['complete']:
        raise SafetyError(f'Unbekannte Quelldaten bleiben erhalten / Unrecognized source retained: {path}')
    if path.is_dir() and not path.is_symlink():
        if any(child.name not in saved['children'] for child in path.iterdir()):
            raise SafetyError(f'Neue Quelldaten bleiben erhalten / New source data retained: {path}')
        for child in sorted(path.iterdir()):
            remove_move_backup(engine, job, index, child, origin)
        engine.check_cancel()
        path.rmdir()
    else:
        verify_move_source(engine, job, index, path, origin)
        path.unlink()


def finish_move(engine, job, index, root, operation):
    source, target = Path(root['source']), Path(root['target'])
    record = next(row for row in operation['records'] if row['destination'] == str(target))
    if root['status'] == 'published':
        if record['snapshot'] is None:
            raise SafetyError('Ziel nicht verifizierbar; Quelle bleibt erhalten / Unverifiable target; source retained')
        verify_move_source(engine, job, index, source)
        engine.check_cancel()
        container = Path(tempfile.mkdtemp(prefix='.OpenCommanderMove-', dir=source.parent))
        root.update(status='source-moving', source_backup=str(container / source.name))
        engine.transfers.save(job)
        rename_new(source, container / source.name)
        root['status'] = 'cleanup'
        with engine.history_lock:
            record['kind'] = 'move'
            record['source_backup'] = root['source_backup']
            engine.save()
        engine.transfers.save(job)
    backup = Path(root['source_backup'])
    if backup.parent.parent != source.parent or not backup.parent.name.startswith('.OpenCommanderMove-') or backup.name != source.name or is_link(backup.parent):
        raise SafetyError('Ungültiger Verschiebe-Zwischenstand / Invalid move recovery path')
    # A restart must verify the only published original before continuing cleanup.
    if recorded_snapshot(record, target, engine.check_cancel) != record['snapshot'] or record['snapshot'] is None:
        raise SafetyError('Ziel geändert; Quellkopie bleibt erhalten / Changed target; source backup retained')
    engine.report_transfer('cleanup', source.name)
    if exists(backup):
        remove_move_backup(engine, job, index, backup, backup)
    if exists(backup.parent):
        backup.parent.rmdir()
    with engine.history_lock:
        record.pop('source_backup', None)
        engine.save()


def discard(engine, identifier):
    try:
        _discard(engine, identifier)
    except Exception as error:
        job = engine.transfers.get(identifier)
        if job:
            job.update(status='blocked', error=str(error))
            engine.transfers.save(job)
        raise


def _discard(engine, identifier):
    job = engine.transfers.get(identifier)
    if job is None:
        return
    if any(root.get('staging') for root in job.get('roots') or []):
        for guard in job['guards']:
            if guard['path'] == job['directory'] and mount_identity(guard['path']) != guard['mount']:
                raise SafetyError('Ziellaufwerk zum Entfernen des Zwischenstands verbinden / Reconnect destination to discard partial copy')
    for root in job.get('roots') or []:
        if not root.get('staging') or root['status'] == 'done':
            continue
        stage = staging_for(job, root)
        if root['status'] in ('published', 'renamed'):
            operation = next((row for row in engine.history if row['id'] == job.get('operation')), None)
            if operation is None:
                operation = engine.begin('copy')
            if not any(record['destination'] == root['target'] for record in operation['records']):
                # Cancellation must not spend hours hashing an already published
                # folder. Retain its history, but never allow unverified undo.
                with engine.history_lock:
                    operation['records'].append(dict(source=root['source'], destination=root['target'],
                        kind='move' if root['status'] == 'renamed' else 'copy', backup=root.get('backup'), snapshot=None, reverted=False))
                    engine.save()
        # Displaced originals and ambiguous publication are retained for recovery.
        if root['status'] in ('publishing', 'renaming', 'source-moving'):
            raise SafetyError(f'Unterbrochene Veröffentlichung prüfen / Inspect interrupted publication: {root["target"]}\n{stage}')
        if root['status'] == 'cleanup':
            raise SafetyError('Verschobene Daten sind am Ziel; Quellbereinigung bleibt gespeichert. Fortsetzen zum Abschließen. / Move cleanup saved; resume to finish')
        if exists(stage / 'previous'):
            continue
        shutil.rmtree(stage, ignore_errors=False) if exists(stage) else None
    engine.transfers.delete(identifier)


def transfer(engine, identifier):
    store = engine.transfers
    job = store.get(identifier)
    if job is None:
        return
    operation = None
    started = time.monotonic()
    move = job.get('move', False)
    try:
        engine.check_cancel()
        for guard in job['guards']:
            actual_mount = mount_identity(guard['path'])
            if actual_mount != guard['mount']:
                expected_mount = guard.get('mount') or {}
                if expected_mount.get('filesystem') == 'fuse.rclone' and (not actual_mount or actual_mount.get('root') != expected_mount.get('root')):
                    raise SafetyError('Online-Laufwerk nicht verbunden. Wieder verbinden und danach Fortsetzen wählen; '
                                      'der Kopierstand bleibt gespeichert. / Reconnect the online drive, then resume; saved progress is retained: ' + guard['path'])
                raise SafetyError(f'Laufwerk fehlt oder wurde ersetzt / Drive missing or replaced: {guard["path"]}')
        directory = Path(job['directory'])
        if not directory.is_dir():
            raise NotADirectoryError(str(directory))
        if canonical_path(directory) == canonical_path(engine.state_dir) or canonical_path(engine.state_dir) in canonical_path(directory).parents:
            raise SafetyError('The recovery profile cannot be a destination')
        if job['roots'] is None:
            sources = selected_roots(job['sources'])
            if move:
                engine.protect_state(sources)
            for source in sources:
                validate_target(source, directory)
            totals = {sources[0]: tuple(job['legacy_totals'])} if job.get('legacy_totals') is not None else engine.plan_transfer(sources)
            job['roots'] = [dict(source=str(source), status='pending', size=totals[source][0], files=totals[source][1]) for source in sources]
            store.save(job)
        operation = next((row for row in engine.history if row['id'] == job.get('operation')), None)
        if operation is None:
            operation = engine.begin('move' if move else 'copy')
            job['operation'] = operation['id']
        else:
            engine.bytes_done = 0
            engine.compatibility_warnings.clear()
            with engine.history_lock:
                operation.pop('paused', None)
                operation.pop('error', None)
        engine.transfer_metrics = dict(phase='copying', name='', bytes_done=0,
            bytes_resumed=0,
            bytes_total=sum(root['size'] for root in job['roots']),
            files_total=sum(root['files'] for root in job['roots']), files_done=0,
            resume_files_total=0, resume_files_checked=0,
            resume_bytes_total=0, resume_bytes_checked=0)
        completed = store.completed_totals(identifier)
        credited_roots = set()
        for index, root in enumerate(job['roots']):
            if root['status'] in ('done', 'renamed', 'cleanup'):
                size, files = root['size'], root['files']
                credited_roots.add(index)
            elif root['status'] in ('copying', 'published'):
                size, files = completed.get(index, (0, 0))
                engine.transfer_metrics['resume_files_total'] += files
                engine.transfer_metrics['resume_bytes_total'] += size
            else:
                size = files = 0
            engine.bytes_done += size
            engine.transfer_metrics['files_done'] += files
        engine.transfer_metrics['bytes_resumed'] = engine.bytes_done
        if job.get('error'):
            job['last_error'] = job['error']
        engine.report_transfer('resuming' if engine.transfer_metrics['resume_files_total'] else 'copying')
        job.update(status='running', error=None)
        store.save(job)
        for index, root in enumerate(job['roots']):
            engine.check_cancel()
            source = Path(root['source'])
            if root['status'] == 'done':
                continue
            if root['status'] in ('publishing', 'renaming', 'source-moving'):
                raise SafetyError(f'Unterbrochene Veröffentlichung prüfen / Inspect interrupted publication: {root["target"]}\n{root["staging"]}')
            if root['status'] == 'pending':
                preferred = directory / source.name
                if move and source == preferred:
                    root['status'] = 'done'
                    engine.bytes_done += root['size']
                    engine.transfer_metrics['files_done'] += root['files']
                    store.save(job)
                    continue
                target = unique_path(directory, source.name) if job['conflict'] == 'keep' or source == preferred else preferred
                if job.get('legacy_staging'):
                    stage = Path(job['legacy_staging'])
                    if stage.parent != directory or not stage.name.startswith('.OpenCommanderTransfer-') or is_link(stage) or not stage.is_dir():
                        raise SafetyError('Invalid legacy copy staging')
                    if exists(stage / 'previous') or not exists(stage / 'payload') or is_link(stage / 'payload'):
                        raise SafetyError('Legacy staging requires inspection; original or payload not identifiable')
                else:
                    stage = Path(tempfile.mkdtemp(prefix='.OpenCommanderTransfer-', dir=directory))
                root.update(status='copying', staging=str(stage), target=str(target))
                store.save(job)
                if move and not exists(target):
                    root['status'] = 'renaming'
                    store.save(job)
                    try:
                        rename_new(source, target)
                    except OSError as error:
                        if error.errno not in (errno.EXDEV, errno.EOPNOTSUPP, errno.ENOSYS):
                            raise
                        root['status'] = 'copying'
                    else:
                        root['status'] = 'renamed'
                    store.save(job)
            stage = staging_for(job, root)
            target = Path(root['target'])
            if target.parent != directory:
                raise SafetyError('Invalid copy destination')
            if root['status'] == 'copying':
                engine.resuming_copy = (job, index, source)
                engine.deferred_copy_checks = []
                try:
                    engine.copy_file(source, stage / 'payload')
                    pending_checks = engine.deferred_copy_checks
                    engine.deferred_copy_checks = None
                    for saved_source, saved_target in pending_checks:
                        engine.check_cancel()
                        engine.copy_file(saved_source, saved_target)
                finally:
                    engine.deferred_copy_checks = None
                    engine.resuming_copy = None
                engine.check_cancel()
                root['status'] = 'publishing'
                store.save(job)
                backup = engine.publish(stage / 'payload', target, job['conflict'] == 'replace' and source != target)
                root.update(status='published', backup=str(backup) if backup else None)
                store.save(job)
            elif root['status'] == 'published':
                # A pause during history verification already published this root.
                engine.resuming_copy = (job, index, source)
                try:
                    engine.copy_file(source, target)
                finally:
                    engine.resuming_copy = None
            elif root['status'] in ('renamed', 'cleanup'):
                if index not in credited_roots:
                    engine.bytes_done += root['size']
                    engine.transfer_metrics['files_done'] += root['files']
            engine.check_cancel()
            engine.report_transfer('verifying', source.name)
            if not any(record['destination'] == str(target) for record in operation['records']):
                engine.record(operation, source, target, 'move' if root['status'] == 'renamed' else 'copy', root.get('backup'), cancellable=True)
            if move and root['status'] in ('published', 'cleanup'):
                finish_move(engine, job, index, root, operation)
            root['status'] = 'done'
            store.save(job)
            if not root.get('backup'):
                shutil.rmtree(stage)
        engine.report_transfer('complete')
        store.delete(identifier)
        return operation
    except Cancelled:
        if engine.pause.is_set():
            job.update(status='paused', error=None)
            store.save(job)
        else:
            discard(engine, identifier)
        raise
    except Exception as error:
        job.update(status='blocked', error=str(error))
        job['last_error'] = str(error)
        job['errors'] = (job.get('errors', []) + [dict(time=time.time(), message=str(error))])[-20:]
        store.save(job)
        raise
    finally:
        engine.resuming_copy = None
        if job['status'] in ('paused', 'blocked'):
            if engine.transfer_metrics is not None:
                job['progress'] = dict(engine.transfer_metrics)
            job['elapsed'] = job.get('elapsed', 0) + time.monotonic() - started
            store.save(job)
        engine.transfer_metrics = None
        if operation is not None:
            if job.get('errors'):
                with engine.history_lock:
                    operation['transfer_errors'] = list(job['errors'])
            engine.finish(operation)
            if job['status'] == 'paused' and operation in engine.history:
                with engine.history_lock:
                    operation.pop('error', None)
                    operation['paused'] = True
                    engine.save()
