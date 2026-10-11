"""Checkpointed copies into private target-volume staging.

Pause keeps staging; explicit cancel removes unpublished staging. Published
destinations are never removed on error. An ambiguous interrupted publication
stops for inspection rather than guessing which file belongs to this job.
"""
import hashlib
import os
from pathlib import Path
import shutil
import stat
import tempfile

from .operations import (Cancelled, SafetyError, exists, selected_roots,
                         validate_target, unique_path)
from .transfer_store import mount_identity


def signature(info):
    return [info.st_mode, info.st_size, info.st_mtime_ns]


def open_regular(path, flags):
    fd = os.open(path, flags | os.O_NOFOLLOW)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise SafetyError(f'Keine reguläre Datei / Not a regular file: {path}')
    return fd


def digest_file(engine, path):
    digest = hashlib.sha256()
    with os.fdopen(open_regular(path, os.O_RDONLY), 'rb') as stream:
        while True:
            engine.check_cancel()
            block = stream.read(1024 * 1024)
            if not block:
                return digest.hexdigest()
            digest.update(block)


def copy_file(engine, source, target):
    store = engine.transfers
    job, index, origin = engine.resuming_copy
    relative = source.relative_to(origin).as_posix()
    saved = store.file(job['id'], index, relative)
    engine.check_cancel()
    info = source.lstat()
    current = signature(info)
    engine.report_transfer('copying', source.name)
    if saved and saved['source'] != current:
        raise SafetyError(f'Quelle seit Pause geändert / Source changed since pause: {source}')
    if not saved:
        if exists(target):
            # A process may have died after mkdir/create but before its checkpoint.
            raise SafetyError(f'Unbekannter Zwischenstand / Unrecognized partial file: {target}')
        saved = dict(source=current, complete=False)
        if stat.S_ISDIR(info.st_mode):
            saved['children'] = sorted(child.name for child in source.iterdir())
        store.checkpoint(job['id'], index, relative, saved)
    if stat.S_ISLNK(info.st_mode):
        link = os.readlink(source)
        if exists(target):
            if not target.is_symlink() or os.readlink(target) != link:
                raise SafetyError(f'Zwischenstand geändert / Partial copy changed: {target}')
        else:
            os.symlink(link, target)
    elif stat.S_ISDIR(info.st_mode):
        if sorted(child.name for child in source.iterdir()) != saved['children']:
            raise SafetyError(f'Quellordner geändert / Source folder changed: {source}')
        if exists(target):
            if target.is_symlink() or not target.is_dir() or any(child.name not in saved['children'] for child in target.iterdir()):
                raise SafetyError(f'Zwischenordner geändert / Partial folder changed: {target}')
        else:
            target.mkdir()
        for name in saved['children']:
            engine.copy_file(source / name, target / name)
        engine.copy_metadata(source, target)
    elif stat.S_ISREG(info.st_mode):
        if saved['complete']:
            if target.lstat().st_size != info.st_size or digest_file(engine, target) != saved['digest']:
                raise SafetyError(f'Zwischenstand geändert / Partial copy changed: {target}')
            engine.bytes_done += info.st_size
            engine.transfer_metrics['bytes_resumed'] += info.st_size
        else:
            digest = hashlib.sha256()
            offset = 0
            with os.fdopen(open_regular(source, os.O_RDONLY), 'rb') as inp:
                if exists(target):
                    with os.fdopen(open_regular(target, os.O_RDONLY), 'rb') as previous:
                        while True:
                            engine.check_cancel()
                            block = previous.read(1024 * 1024)
                            if not block:
                                break
                            if inp.read(len(block)) != block:
                                raise SafetyError(f'Unvollständige Datei stimmt nicht überein / Partial data mismatch: {target}')
                            digest.update(block)
                            offset += len(block)
                            engine.report_transfer('verifying', source.name)
                    fd = open_regular(target, os.O_WRONLY | os.O_APPEND)
                    if os.fstat(fd).st_size != offset:
                        os.close(fd)
                        raise SafetyError(f'Zwischenstand geändert / Partial copy changed: {target}')
                else:
                    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                engine.bytes_done += offset
                engine.transfer_metrics['bytes_resumed'] += offset
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
        engine.transfer_metrics['files_done'] += 1
        engine.report_transfer('copying', source.name)


def staging_for(job, root):
    stage = Path(root['staging'])
    if stage.parent != Path(job['directory']) or not stage.name.startswith('.OpenCommanderTransfer-'):
        raise SafetyError(f'Invalid copy staging: {stage}')
    if exists(stage) and (stage.is_symlink() or not stage.is_dir()):
        raise SafetyError(f'Copy staging changed: {stage}')
    return stage


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
        if root['status'] == 'published':
            operation = next((row for row in engine.history if row['id'] == job.get('operation')), None)
            if operation is None:
                operation = engine.begin('copy')
            if not any(record['destination'] == root['target'] for record in operation['records']):
                # Cancellation must not spend hours hashing an already published
                # folder. Retain its history, but never allow unverified undo.
                operation['records'].append(dict(source=root['source'], destination=root['target'],
                    kind='copy', backup=root.get('backup'), snapshot=None, reverted=False))
                engine.save()
        # Displaced originals and ambiguous publication are retained for recovery.
        if root['status'] == 'publishing':
            raise SafetyError(f'Unterbrochene Veröffentlichung prüfen / Inspect interrupted publication: {root["target"]}\n{stage}')
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
    try:
        engine.check_cancel()
        for guard in job['guards']:
            if mount_identity(guard['path']) != guard['mount']:
                raise SafetyError(f'Laufwerk fehlt oder wurde ersetzt / Drive missing or replaced: {guard["path"]}')
        directory = Path(job['directory'])
        if not directory.is_dir():
            raise NotADirectoryError(str(directory))
        if directory.resolve() == engine.state_dir.resolve() or engine.state_dir.resolve() in directory.resolve().parents:
            raise SafetyError('The recovery profile cannot be a destination')
        if job['roots'] is None:
            sources = selected_roots(job['sources'])
            for source in sources:
                validate_target(source, directory)
            totals = engine.plan_transfer(sources)
            job['roots'] = [dict(source=str(source), status='pending', size=totals[source][0], files=totals[source][1]) for source in sources]
            store.save(job)
        operation = next((row for row in engine.history if row['id'] == job.get('operation')), None)
        if operation is None:
            operation = engine.begin('copy')
            job['operation'] = operation['id']
        else:
            engine.bytes_done = 0
            engine.compatibility_warnings.clear()
            operation.pop('paused', None)
            operation.pop('error', None)
        engine.transfer_metrics = dict(phase='copying', name='', bytes_done=0,
            bytes_resumed=0,
            bytes_total=sum(root['size'] for root in job['roots']),
            files_total=sum(root['files'] for root in job['roots']), files_done=0)
        job.update(status='running', error=None)
        store.save(job)
        for index, root in enumerate(job['roots']):
            engine.check_cancel()
            source = Path(root['source'])
            if root['status'] == 'done':
                engine.bytes_done += root['size']
                engine.transfer_metrics['bytes_resumed'] += root['size']
                engine.transfer_metrics['files_done'] += root['files']
                continue
            if root['status'] == 'publishing':
                raise SafetyError(f'Unterbrochene Veröffentlichung prüfen / Inspect interrupted publication: {root["target"]}\n{root["staging"]}')
            if root['status'] == 'pending':
                preferred = directory / source.name
                target = unique_path(directory, source.name) if job['conflict'] == 'keep' or source == preferred else preferred
                stage = Path(tempfile.mkdtemp(prefix='.OpenCommanderTransfer-', dir=directory))
                root.update(status='copying', staging=str(stage), target=str(target))
                store.save(job)
            stage = staging_for(job, root)
            target = Path(root['target'])
            if target.parent != directory:
                raise SafetyError('Invalid copy destination')
            if root['status'] == 'copying':
                engine.resuming_copy = (job, index, source)
                try:
                    engine.copy_file(source, stage / 'payload')
                finally:
                    engine.resuming_copy = None
                engine.check_cancel()
                root['status'] = 'publishing'
                store.save(job)
                backup = engine.publish(stage / 'payload', target, job['conflict'] == 'replace' and source != target)
                root.update(status='published', backup=str(backup) if backup else None)
                store.save(job)
            else:
                # A pause during history verification already published this root.
                engine.resuming_copy = (job, index, source)
                try:
                    engine.copy_file(source, target)
                finally:
                    engine.resuming_copy = None
            engine.check_cancel()
            engine.report_transfer('verifying', source.name)
            if not any(record['destination'] == str(target) for record in operation['records']):
                engine.record(operation, source, target, 'copy', root.get('backup'), cancellable=True)
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
        store.save(job)
        raise
    finally:
        engine.resuming_copy = None
        engine.transfer_metrics = None
        if operation is not None:
            engine.finish(operation)
            if job['status'] == 'paused' and operation in engine.history:
                operation.pop('error', None)
                operation['paused'] = True
                engine.save()
