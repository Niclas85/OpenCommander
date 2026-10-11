"""Private, durable copy queue and per-file checkpoints (no credentials)."""
import json
import os
from pathlib import Path
import sqlite3
import threading
import time
import uuid
from contextlib import contextmanager


class TransferStore:
    def __init__(self, state_dir):
        self.path = Path(state_dir) / 'transfers.sqlite3'
        self.lock = threading.RLock()
        self.error = None
        try:
            # Create with private permissions before SQLite opens the file.
            fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
            os.close(fd)
            os.chmod(self.path, 0o600)
            with self.connection() as db:
                if db.execute('PRAGMA user_version').fetchone()[0] not in (0, 1):
                    raise sqlite3.DatabaseError('Unsupported copy queue format')
                db.execute('CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, data TEXT NOT NULL)')
                db.execute('CREATE TABLE IF NOT EXISTS files (job TEXT, root INTEGER, path TEXT, data TEXT NOT NULL, PRIMARY KEY(job, root, path))')
                db.execute('PRAGMA user_version=1')
        except (OSError, sqlite3.Error) as error:
            self.error = str(error)

    @contextmanager
    def connection(self):
        if self.error:
            raise RuntimeError('Kopierwarteschlange nicht lesbar / Copy queue unreadable: ' + self.error)
        db = sqlite3.connect(self.path, timeout=10)
        try:
            db.execute('PRAGMA synchronous=FULL')
            with db:
                yield db
        finally:
            db.close()

    def create(self, paths, directory, conflict, guards=None, profiles=None, legacy_staging=None, legacy_totals=None, move=False):
        job = dict(id=uuid.uuid4().hex, created=time.time(), status='queued',
                   sources=[os.path.abspath(path) for path in paths],
                   directory=os.path.abspath(directory), conflict=conflict,
                   guards=guards or [], profiles=profiles or [], roots=None, move=bool(move))
        if legacy_staging is not None:
            stage = Path(os.path.abspath(legacy_staging))
            if len(job['sources']) != 1 or stage.parent != Path(job['directory']) or not stage.name.startswith('.OpenCommanderTransfer-'):
                raise ValueError('Invalid legacy staging path')
            job['legacy_staging'] = str(stage)
            if legacy_totals is not None:
                size, files = legacy_totals
                if type(size) is not int or type(files) is not int or size < 0 or files < 0:
                    raise ValueError('Invalid legacy copy totals')
                job['legacy_totals'] = [size, files]
        self.save(job)
        return job

    def save(self, job):
        with self.lock, self.connection() as db:
            db.execute('INSERT OR REPLACE INTO jobs VALUES (?, ?)', (job['id'], json.dumps(job)))

    def jobs(self):
        with self.lock, self.connection() as db:
            return sorted((json.loads(row[0]) for row in db.execute('SELECT data FROM jobs')), key=lambda row: row['created'])

    def get(self, identifier):
        with self.lock, self.connection() as db:
            row = db.execute('SELECT data FROM jobs WHERE id=?', (identifier,)).fetchone()
            return json.loads(row[0]) if row else None

    def checkpoint(self, identifier, root, relative, data):
        with self.lock, self.connection() as db:
            db.execute('INSERT OR REPLACE INTO files VALUES (?, ?, ?, ?)',
                       (identifier, root, relative, json.dumps(data)))

    def file(self, identifier, root, relative):
        with self.lock, self.connection() as db:
            row = db.execute('SELECT data FROM files WHERE job=? AND root=? AND path=?',
                             (identifier, root, relative)).fetchone()
            return json.loads(row[0]) if row else None

    def delete(self, identifier):
        with self.lock, self.connection() as db:
            db.execute('DELETE FROM files WHERE job=?', (identifier,))
            db.execute('DELETE FROM jobs WHERE id=?', (identifier,))


def mount_identity(path):
    """Stable mount identity without touching a possibly stalled filesystem."""
    import re
    path = Path(os.path.abspath(path))
    result = None
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        before, after = line.split(' - ', 1)
        root = Path(re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), before.split()[4]))
        if root == path or root in path.parents:
            if result is None or len(root.parts) > len(Path(result['root']).parts):
                fields = after.split()
                result = dict(root=str(root), filesystem=fields[0], device=fields[1])
    return result


def guards_for(paths):
    return [dict(path=os.path.abspath(path), mount=mount_identity(path)) for path in paths]
