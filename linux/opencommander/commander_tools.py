"""Bounded Commander tools shared by local paths and Linux provider mounts."""
import hashlib
import os
import re
import stat
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from .filesystem import listing
from .operations import SafetyError, Cancelled, exists, rename_new
from .platform_support import is_link


def check(cancel):
    if cancel.is_set():
        raise Cancelled('Abgebrochen / Cancelled')


def search_directory(value):
    path = Path(os.path.expanduser(value))
    if not value or '\0' in value or not path.is_absolute():
        raise SafetyError('Absoluten Suchpfad oder ~/… angeben / Use an absolute search path')
    return Path(os.path.abspath(path))


def scan(root, hidden, cancel, progress=lambda *args: None, limit=100000):
    root = Path(root)
    if is_link(root) or not root.is_dir():
        raise SafetyError('Kein Ordner oder symbolischer Link / Not a directory or symbolic link')
    result, warnings, queue = {}, [], [root]
    while queue:
        check(cancel)
        directory = queue.pop()
        progress(len(result), str(directory))
        try:
            entries = listing(directory, hidden, cancel=cancel)
        except OSError as error:
            warnings.append(f'{directory}: {error}')
            continue
        for entry in entries:
            check(cancel)
            if len(result) >= limit:
                raise SafetyError(f'Limit: {limit} Einträge / entries')
            result[str(entry.path.relative_to(root))] = entry
            if entry.error:
                warnings.append(f'{entry.path}: {entry.error}')
            elif entry.directory and not entry.link:
                queue.append(entry.path)
    return result, warnings


def search(root, query, hidden, sensitive, cancel, progress=lambda *args: None, limit=100000):
    entries, warnings = scan(root, hidden, cancel, progress, limit)
    query = unicodedata.normalize('NFC', query)
    expression = re.escape(query).replace(r'\*', '.*').replace(r'\?', '.')
    if '*' in query or '?' in query:
        expression = '^' + expression + '$'
    pattern = re.compile(expression, 0 if sensitive else re.IGNORECASE)
    return [entry for _, entry in sorted(entries.items())
            if pattern.search(unicodedata.normalize('NFC', entry.name))], warnings


def identity(path):
    info = Path(path).lstat()
    return info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns


def digest(path, cancel):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while True:
            check(cancel)
            block = stream.read(1024 * 1024)
            if not block:
                break
            value.update(block)
    return value.digest()


def compare(left, right, hidden, cancel, progress=lambda *args: None):
    a, aw = scan(left, hidden, cancel, progress)
    b, bw = scan(right, hidden, cancel, progress)
    rows = []
    for number, name in enumerate(sorted(a.keys() | b.keys())):
        check(cancel)
        progress(number, name)
        if name not in a:
            rows.append((name, 'right', ''))
        elif name not in b:
            rows.append((name, 'left', ''))
        else:
            l, r = a[name], b[name]
            try:
                if l.error or r.error:
                    raise SafetyError(l.error or r.error)
                before_l, before_r = identity(l.path), identity(r.path)
                lt, rt = stat.S_IFMT(before_l[2]), stat.S_IFMT(before_r[2])
                if lt != rt:
                    equal = False
                elif stat.S_ISDIR(lt):
                    continue
                elif stat.S_ISLNK(lt):
                    equal = os.readlink(l.path) == os.readlink(r.path)
                elif stat.S_ISREG(lt):
                    equal = l.size == r.size and digest(l.path, cancel) == digest(r.path, cancel)
                else:
                    raise SafetyError('Nicht unterstützter Dateityp / Unsupported file type')
                if before_l != identity(l.path) or before_r != identity(r.path):
                    raise SafetyError('Datei während Vergleich geändert / File changed during comparison')
                rows.append((name, 'equal' if equal else 'different', ''))
            except (OSError, SafetyError) as error:
                check(cancel)
                rows.append((name, 'unreadable', str(error)))
    return rows, aw + bw


@dataclass(frozen=True)
class Rename:
    source: Path
    destination: Path
    identity: tuple


def rename_plan(paths, pattern='[N][E]', find='', replacement='', start=1, digits=3):
    paths = sorted(map(Path, paths), key=lambda path: path.name.casefold())
    if not paths or len(paths) > 10000 or start < 0 or not 1 <= digits <= 9:
        raise SafetyError('Ungültige Auswahl / Invalid selection or counter')
    result, seen = [], set()
    for number, path in enumerate(paths, start):
        before = identity(path)
        ext = '' if stat.S_ISDIR(before[2]) else path.suffix
        stem = path.name[:-len(ext)] if ext else path.name
        values = {'N': stem, 'E': ext, 'C': str(number).zfill(digits)}
        name = re.sub(r'\[([NEC])\]', lambda match: values[match[1]], pattern)
        if find:
            name = name.replace(find, replacement)
        from .platform_support import validate_component
        validate_component(name)
        if not name or name in ('.', '..') or any(c in name for c in '/\0:') or len(os.fsencode(name)) > 255:
            raise SafetyError(f'Ungültiger Name / Invalid name: {name}')
        destination = path.parent / name
        key = unicodedata.normalize('NFC', str(destination)).casefold()
        if key in seen:
            raise SafetyError(f'Doppeltes Ziel / Duplicate destination: {name}')
        seen.add(key)
        if destination != path and (exists(destination) or name.casefold() == path.name.casefold()):
            raise SafetyError(f'Ziel belegt / Destination occupied: {name}')
        result.append(Rename(path, destination, before))
    return result


def rename_batch(engine, plan):
    engine.protect_state([row.source for row in plan])
    for row in plan:
        engine.check_cancel()
        if identity(row.source) != row.identity or (row.source != row.destination and exists(row.destination)):
            raise SafetyError(f'Vorschau veraltet / Preview is stale: {row.source}')
    operation = engine.begin('multi_rename')
    completed = []
    try:
        for row in plan:
            engine.check_cancel()
            if row.source == row.destination:
                continue
            if identity(row.source) != row.identity:
                raise SafetyError(f'Quelle geändert / Source changed: {row.source}')
            rename_new(row.source, row.destination)
            completed.append((row, identity(row.destination)))
            engine.record(operation, row.source, row.destination, 'move')
    except Exception:
        for row, moved in reversed(completed):
            try:
                if exists(row.source) or identity(row.destination) != moved:
                    raise SafetyError('Rollback target changed')
                rename_new(row.destination, row.source)
                operation['records'] = [r for r in operation['records'] if r['destination'] != str(row.destination)]
                engine.save()
            except (OSError, SafetyError):
                # Retain the recovery record and precise destination for later undo.
                pass
        raise
    finally:
        engine.finish(operation)
