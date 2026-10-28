"""Read-only recovery of evicted Google files when their FUSE read fails.

Never bypass locally cached data: they may contain writes not yet uploaded.
A matching server SHA-256 is a proof for the saved bytes, not just existence.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import time

from . import rclone_runtime
from .desktop import host_environment
from .cloud_listing import CloudError, provider_error


def evicted_target(path):
    if os.name == 'nt':
        from .windows_mounts import evicted_target as windows_evicted
        return windows_evicted(path)
    from .external_cloud import discover
    from .provider_mounts import rclone_mount
    path = Path(os.path.abspath(path))
    mounted = rclone_mount(path)
    if mounted is None:
        return None
    for profile in discover():
        root = Path(profile['mount_root'])
        if root != mounted[0] or profile['kind'] != 'drive':
            continue
        remote = profile['remote_base']
        if not re.fullmatch(r'[A-Za-z0-9_-]+:', remote):
            continue
        # Require an explicit local cache namespace; unknown layouts fail closed.
        for process in Path('/proc').iterdir():
            if not process.name.isdigit():
                continue
            try:
                if process.stat().st_uid != os.getuid():
                    continue
                args = (process / 'cmdline').read_bytes().decode().rstrip('\0').split('\0')
                if Path(args[0]).name != 'rclone' or 'mount' not in args:
                    continue
                index = args.index('mount')
                if args[index + 1:index + 3] != [remote, str(root)]:
                    continue
                def option(name):
                    if name in args:
                        return args[args.index(name) + 1]
                    return next((item.split('=', 1)[1] for item in args if item.startswith(name + '=')), '')
                cache = Path(option('--cache-dir'))
                if option('--vfs-cache-mode') not in ('full', 'writes') or not cache.is_absolute():
                    continue
                namespace = remote[:-1]
                if not (cache / 'vfsMeta' / namespace).is_dir():
                    continue
                relative = path.relative_to(root)
                guard = (cache / 'vfsMeta' / namespace / relative,
                         cache / 'vfs' / namespace / relative)
                if any(os.path.lexists(item) for item in guard):
                    return None
                return profile, relative.as_posix(), guard
            except (OSError, ValueError, IndexError, UnicodeError):
                continue
    return None


def server_digest(engine, path, size, timeout=20):
    target = evicted_target(path)
    binary = rclone_runtime.binary()
    if target is None or not binary:
        return None
    profile, relative, guard = target
    command = [binary, '--config', profile['config_path'], 'lsjson',
               profile['remote_base'] + relative, '--stat', '--hash',
               '--retries', '1', '--low-level-retries', '1', '--contimeout', '5s', '--timeout', '10s']
    engine.check_cancel()
    with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, env=host_environment()) as process:
        deadline = time.monotonic() + timeout
        try:
            while True:
                engine.check_cancel()
                if time.monotonic() >= deadline:
                    raise CloudError('Cloud-Prüfsumme nicht rechtzeitig verfügbar. Zwischenstand bleibt gespeichert. / Cloud verification timed out', True)
                try:
                    output, error = process.communicate(timeout=.1)
                    break
                except subprocess.TimeoutExpired:
                    continue
            if process.returncode:
                raise provider_error(error)
            try:
                row = json.loads(output)
                digest = row.get('Hashes', {}).get('sha256', '')
                valid = row.get('IsDir') is False and row.get('Size') == size and re.fullmatch(r'[0-9a-fA-F]{64}', digest)
            except (ValueError, TypeError, AttributeError):
                return None
            # A concurrent local write makes the remote proof insufficient.
            if any(os.path.lexists(item) for item in guard):
                return None
            return digest.lower() if valid else None
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
