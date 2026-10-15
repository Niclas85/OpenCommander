"""Explicitly registered application-managed mounts with provider semantics."""
import os
import re
from pathlib import Path

_roots = set()
_portable_roots = set()


def register(path, *, portable=False):
    root = Path(os.path.abspath(path))
    _roots.add(root)
    if portable:
        _portable_roots.add(root)


def portable(path):
    path = Path(os.path.abspath(path))
    return next((root for root in _portable_roots & _roots if root == path or root in path.parents), None)


def managed(path):
    path = Path(os.path.abspath(path))
    return any(root == path or root in path.parents for root in _roots)


def same_mount(a, b):
    a, b = Path(os.path.abspath(a)), Path(os.path.abspath(b))
    if any((root == a or root in a.parents) and (root == b or root in b.parents) for root in _roots):
        return True
    first = provider_mount(a)
    return first is not None and first == provider_mount(b)


def rclone_mount(path):
    """Recognize an external rclone mount without contacting its provider."""
    if os.name == 'nt':
        path = Path(os.path.abspath(path))
        return next(((root, str(root)) for root in _roots if root == path or root in path.parents), None)
    mount = _closest_mount(path)
    return mount[:2] if mount and mount[2] == 'fuse.rclone' else None


def provider_mount(path):
    """GVFS shares are separate providers even within one FUSE mount."""
    if os.name == 'nt':
        return rclone_mount(path)
    mount = _closest_mount(path)
    if not mount:
        return None
    if mount[2] == 'fuse.rclone':
        return mount[:2]
    if mount[2] == 'fuse.gvfsd-fuse':
        relative = Path(os.path.abspath(path)).relative_to(mount[0])
        if relative.parts:
            return (mount[0] / relative.parts[0], mount[1])
    return None


def _closest_mount(path):
    path = Path(os.path.abspath(path))
    closest = None
    try:
        for line in Path('/proc/self/mountinfo').read_text().splitlines():
            before, after = line.split(' - ', 1)
            fields = before.split()
            root = Path(re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), fields[4]))
            if root == path or root in path.parents:
                if closest is None or len(root.parts) > len(closest[0].parts):
                    closest = (root, fields[0], after.split()[0])
    except (OSError, IndexError, ValueError):
        return None
    return closest
