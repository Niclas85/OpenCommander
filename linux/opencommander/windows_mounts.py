"""WinFsp/rclone mounts with authenticated graceful shutdown and discovery."""
import configparser
import hashlib
import json
import os
import re
from pathlib import Path
import secrets
import socket
import subprocess
import time
import urllib.request

_known_roots = set()


def processes():
    import psutil
    user = psutil.Process().username().casefold()
    result = []
    for process in psutil.process_iter(['pid', 'name', 'username', 'cmdline']):
        try:
            data = process.info
            if (data['name'] or '').lower() != 'rclone.exe' or (data['username'] or '').casefold() != user:
                continue
            args = data['cmdline'] or []
            if 'mount' not in args:
                continue
            index = args.index('mount')
            remote, root = args[index + 1:index + 3]
            if re.fullmatch(r'[A-Za-z]:', root):
                root += '\\'
            if ':' not in remote or not Path(root).is_absolute():
                continue
            result.append((process, args, remote, Path(root)))
        except (psutil.Error, ValueError, IndexError):
            continue
    return result


def option(args, key, default=''):
    if key in args:
        return args[args.index(key) + 1]
    return next((arg.split('=', 1)[1] for arg in args if arg.startswith(key + '=')), default)


def discover():
    from .provider_mounts import register, _roots
    from .external_cloud import KINDS
    result = []
    running = processes()
    alive = {root for _, _, _, root in running}
    _roots.difference_update(_known_roots - alive)
    _known_roots.intersection_update(alive)
    for _, args, remote, root in running:
        if not root.is_mount() and not root.is_junction():
            continue
        register(root)
        _known_roots.add(root)
        if any(arg.split('=')[0] in {'--drive-root-folder-id', '--drive-shared-with-me', '--drive-team-drive',
                                    '--onedrive-drive-id', '--onedrive-root-folder-id'} for arg in args):
            continue
        default = Path(os.environ.get('APPDATA', Path.home() / 'AppData/Roaming')) / 'rclone/rclone.conf'
        config = Path(option(args, '--config', str(default)))
        if not config.is_absolute():
            continue
        try:
            parser = configparser.ConfigParser(interpolation=None)
            parser.read(config, encoding='utf-8')
            kind = parser[remote.split(':', 1)[0]].get('type')
            if kind in KINDS:
                result.append(dict(id='external_' + hashlib.sha256(str(root).encode()).hexdigest()[:16],
                                   kind=kind, name=root.name or str(root), external=True, mount_root=str(root),
                                   config_path=str(config), remote_base=remote))
        except (OSError, KeyError, configparser.Error):
            continue
    return result


def mount_profile(main, profile, cancel):
    from . import rclone_runtime, server_connections
    from .online_ui import mount_path, private_config
    from .provider_mounts import register
    from .windows_native import keyring
    root = mount_path(main.state_dir, profile['id'])
    config = private_config(main.state_dir)
    remote = profile['id'] + ':' + profile.get('remote_directory', '')
    for _, args, mounted_remote, mounted_root in processes():
        if mounted_root == root:
            if mounted_remote != remote or Path(option(args, '--config')) != config:
                raise RuntimeError('Mount path already used by another connection')
            if root.is_mount() or root.is_junction():
                register(root)
                _known_roots.add(root)
                return root
            raise RuntimeError('Verbindung startet noch; erneut versuchen / Mount is still starting; retry')
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\WinFsp', 0, winreg.KEY_READ | winreg.KEY_WOW64_32KEY):
            pass
    except OSError:
        raise RuntimeError('WinFsp fehlt. Bitte von https://winfsp.dev installieren, danach erneut verbinden. / Install WinFsp, then reconnect.') from None
    binary = rclone_runtime.ensure_cloud_backend(cancel)
    root.parent.mkdir(parents=True, exist_ok=True)
    if os.path.lexists(root):
        # Only rmdir an empty, ordinary leftover mount directory. Never recurse.
        if root.is_junction() or root.is_symlink() or not root.is_dir():
            raise RuntimeError('Mount path is occupied: ' + str(root))
        root.rmdir()
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    password = secrets.token_urlsafe(32)
    env = server_connections.credential_environment(main, profile)
    env.update(RCLONE_RC_USER='OpenCommander', RCLONE_RC_PASS=password)
    command = [binary, '--config', str(config), 'mount', remote, str(root),
               '--vfs-cache-mode', 'off', '--dir-cache-time', '5s', '--contimeout', '10s', '--timeout', '20s',
               '--low-level-retries', '2', '--retries', '1', '--rc', '--rc-addr', f'127.0.0.1:{port}']
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    keyring(root, 'mount-control', 'store', json.dumps(dict(port=port, password=password)))
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, env=env)
    deadline = time.monotonic() + 20
    try:
        while process.poll() is None and time.monotonic() < deadline:
            if cancel.is_set():
                raise RuntimeError('Abgebrochen / Cancelled')
            if root.is_mount() or root.is_junction():
                register(root)
                _known_roots.add(root)
                return root
            time.sleep(.1)
        raise RuntimeError('Online-Ort nicht eingebunden. Anmeldung, WinFsp und SSH-Hostschlüssel prüfen. / Mount failed.')
    except BaseException:
        # No file operations are possible until this method publishes the mount.
        process.terminate()
        process.wait(timeout=5)
        keyring(root, 'mount-control', 'clear')
        raise


def unmount(root):
    import base64
    from .windows_native import keyring
    from .provider_mounts import _roots
    control = keyring(root, 'mount-control', 'lookup')
    if control is None:
        raise RuntimeError('Externe Verbindung bitte im ursprünglichen Programm trennen / Disconnect external mounts in their owning application')
    value = json.loads(control)
    request = urllib.request.Request(f"http://127.0.0.1:{int(value['port'])}/core/quit", data=b'{}',
        headers={'Content-Type': 'application/json', 'Authorization': 'Basic ' + base64.b64encode(
            ('OpenCommander:' + value['password']).encode()).decode()})
    with urllib.request.urlopen(request, timeout=10) as response:
        response.read()
    for _ in range(100):
        if not root.is_mount() and not root.is_junction():
            _roots.discard(root)
            keyring(root, 'mount-control', 'clear')
            return
        time.sleep(.1)
    raise RuntimeError('Laufwerk noch verbunden / Mount is still connected')


def settle(path):
    """Forget a published parent before reading descendants or undo proofs.

    WinFsp/rclone can retain a negative stat or a moved directory's empty staging
    cache even though SFTP already has all data. Only use our authenticated loopback control;
    external mounts without an OpenCommander control credential remain untouched.
    """
    import base64
    from .provider_mounts import _roots
    from .windows_native import keyring
    path = Path(os.path.abspath(path))
    root = next((root for root in sorted(_roots, key=lambda p: len(p.parts), reverse=True)
                 if root == path or root in path.parents), None)
    if root is None:
        return False
    control = keyring(root, 'mount-control', 'lookup')
    if control is None:
        return False
    value = json.loads(control)
    port = int(value['port'])
    if not 1 <= port <= 65535:
        raise ValueError('Invalid mount control port')
    parent = path.parent if path != root else root
    relative = parent.relative_to(root).as_posix()
    data = json.dumps(dict(dir='' if relative == '.' else relative)).encode('utf-8')
    request = urllib.request.Request(f'http://127.0.0.1:{port}/vfs/forget', data=data,
        headers={'Content-Type': 'application/json', 'Authorization': 'Basic ' + base64.b64encode(
            ('OpenCommander:' + value['password']).encode()).decode()})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=5) as response:
        json.loads(response.read())
    return True


def evicted_target(path):
    path = Path(os.path.abspath(path))
    for profile in discover():
        root = Path(profile['mount_root'])
        if profile['kind'] != 'drive' or not path.is_relative_to(root) or not profile['remote_base'].endswith(':'):
            continue
        for _, args, remote, mounted_root in processes():
            if mounted_root != root or remote != profile['remote_base']:
                continue
            cache = Path(option(args, '--cache-dir'))
            if option(args, '--vfs-cache-mode') not in ('full', 'writes') or not cache.is_absolute():
                continue
            namespace = remote[:-1]
            if not (cache / 'vfsMeta' / namespace).is_dir():
                continue
            relative = path.relative_to(root)
            guard = (cache / 'vfsMeta' / namespace / relative, cache / 'vfs' / namespace / relative)
            if any(os.path.lexists(item) for item in guard):
                return None
            return profile, relative.as_posix(), guard
    return None
