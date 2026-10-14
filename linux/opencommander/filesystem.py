from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import os
import re
import zipfile
import subprocess
import json
from .operations import checked_members


@dataclass
class Entry:
    name: str
    path: Path
    directory: bool
    size: int = 0
    modified: float = 0
    link: bool = False
    member: str | None = None
    error: str = ''


def listing(directory: Path, hidden=False, cancel=None):
    if cancel is not None and cancel.is_set():
        return []
    if remote_location(directory):
        from .integrations import invoke
        try:
            records = invoke('scan', str(directory), cancel=cancel) if cancel is not None else invoke('scan', str(directory))
        except subprocess.TimeoutExpired:
            raise OSError('Network / Cloud: Zeitüberschreitung / connection timed out (15 s)') from None
        entries = [Entry(**dict(record, path=Path(record['path']))) for record in records
                   if hidden or not record['name'].startswith('.')]
        return sorted(entries, key=lambda e: (not e.directory, e.name.casefold()))
    entries = []
    with os.scandir(directory) as stream:
        for item in stream:
            if cancel is not None and cancel.is_set():
                return []
            if not hidden and item.name.startswith('.'):
                continue
            try:
                info = item.stat(follow_symlinks=False)
                if not hidden and (item.name.startswith('.') or getattr(info, 'st_file_attributes', 0) & 2):
                    continue
                entries.append(Entry(item.name, Path(item.path), item.is_dir(), info.st_size,
                                     info.st_mtime, item.is_symlink() or (os.name == 'nt' and item.is_junction())))
            except FileNotFoundError:
                continue  # An external writer removed this entry while listing.
            except PermissionError as error:
                entries.append(Entry(item.name, Path(item.path), False, error=str(error)))
    return sorted(entries, key=lambda e: (not e.directory, e.name.casefold()))


def archive_listing(path: Path, prefix=''):
    result = {}
    from .archives import open_archive
    with open_archive(path) as archive:
        for item in checked_members(archive):
            if not item.filename.startswith(prefix):
                continue
            remainder = item.filename[len(prefix):].rstrip('/')
            if not remainder:
                continue
            name, separator, _ = remainder.partition('/')
            directory = bool(separator) or item.is_dir()
            result[name] = Entry(name, path, directory, item.file_size if not directory else 0,
                                 member=prefix + name + ('/' if directory else ''))
    return sorted(result.values(), key=lambda e: (not e.directory, e.name.casefold()))


def mounted_locations():
    if os.name == 'nt':
        from .windows_native import drive_roots
        return drive_roots()
    result = []
    try:
        for line in Path('/proc/self/mountinfo').read_text().splitlines():
            fields = line.split()
            mount = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), fields[4])
            if mount.startswith(('/media/', '/mnt/', '/run/media/')):
                path = Path(mount)
                if path not in result:
                    result.append(path)
    except (OSError, IndexError):
        pass
    return result


def cloud_locations(home=None):
    home = Path(home or Path.home())
    candidates = [home / name for name in ('Dropbox', 'OneDrive', 'Google Drive', 'Nextcloud',
                                            'iCloud', 'iCloud Drive', 'iCloudDrive')]
    if os.name == 'nt':
        candidates.extend(Path(os.environ[key]) for key in ('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')
                          if os.environ.get(key))
        try:
            info = json.loads((Path(os.environ.get('LOCALAPPDATA', home / 'AppData/Local')) / 'Dropbox/info.json').read_text(encoding='utf-8'))
            candidates.extend(Path(account['path']) for account in info.values()
                              if isinstance(account, dict) and isinstance(account.get('path'), str))
        except (OSError, ValueError, AttributeError):
            pass
    # Dropbox's public installation metadata may point outside the home folder.
    try:
        info = json.loads((home / '.dropbox/info.json').read_text())
        for account in info.values():
            if isinstance(account, dict) and isinstance(account.get('path'), str):
                candidates.append(Path(account['path']))
    except (OSError, ValueError, AttributeError):
        pass
    return list(dict.fromkeys(p for p in candidates if p.is_absolute() and (remote_location(p) or p.is_dir())))



def remote_location(directory):
    """Identify provider paths without probing a potentially unavailable server."""
    if os.name == 'nt':
        from .windows_native import remote_location as windows_remote
        return windows_remote(directory)
    directory = Path(os.path.abspath(directory))
    mounts = []
    try:
        for line in Path('/proc/self/mountinfo').read_text().splitlines():
            before, after = line.split(' - ', 1)
            filesystem = after.split()[0]
            if not filesystem.startswith(('fuse', 'nfs', 'cifs', 'smb', '9p')):
                continue
            mount = Path(re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), before.split()[4]))
            mounts.append(mount)
    except (OSError, ValueError, IndexError):
        pass
    for _ in range(16):
        if any(mount == directory or mount in directory.parents for mount in mounts):
            return True
        # Resolve links only on local ancestors. Never stat/readlink a provider:
        # a local Downloads/OneDrive symlink can otherwise bypass remote guards.
        prefix = Path('/')
        changed = False
        for index, part in enumerate(directory.parts[1:], 1):
            prefix /= part
            if any(mount == prefix or mount in prefix.parents for mount in mounts):
                return True
            try:
                link = os.readlink(prefix)
            except OSError:
                continue
            destination = Path(link) if os.path.isabs(link) else prefix.parent / link
            directory = Path(os.path.abspath(destination.joinpath(*directory.parts[index + 1:])))
            changed = True
            break
        if not changed:
            return False
    return True  # Cyclic links must not trigger synchronous GUI filesystem probes.
