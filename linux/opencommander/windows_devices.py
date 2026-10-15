"""Discover and mount native WPD devices through the installed WinFsp runtime."""
import hashlib
import json
import os
from pathlib import Path
import queue
import secrets
import subprocess
import threading
import time


def paths(identifier):
    from .platform_support import data_directory
    namespace = data_directory().parent / 'OpenCommanderDevices'
    name = hashlib.sha256(identifier.encode('utf-8')).hexdigest()
    return namespace / 'mounts' / name, namespace / 'private' / name


def locations():
    from .windows_wpd import devices
    from .windows_mounts import processes
    mounted = {root: args for _, args, _, root in processes()}
    result = []
    for device in devices():
        identifier = 'wpd:' + device['id']
        root, private = paths(identifier)
        args = mounted.get(root, [])
        from .windows_mounts import option
        ready = (args and Path(option(args, '--config')) == private / 'rclone.conf' and
                 (root.is_mount() or root.is_junction()))
        result.append(dict(id=identifier, volume_id=identifier, path=str(root) if ready else '',
                           name=device['name'] + ' (MTP)', kind='MTP', mounted=bool(ready),
                           eject=False, unmount=bool(ready)))
    return result


def mount(identifier):
    """Publish the mount only after the helper confirms actual WinFsp readiness."""
    from .platform_support import helper_command
    from .windows_mounts import processes, option
    from .windows_native import protect_private_directory
    from .provider_mounts import register
    if not identifier.startswith('wpd:'):
        raise ValueError('Not a portable device')
    root, private = paths(identifier)
    root.parent.parent.mkdir(parents=True, exist_ok=True)
    if root.parent.parent.is_symlink() or root.parent.parent.is_junction():
        raise OSError('Device mount namespace must not be a link')
    protect_private_directory(root.parent.parent)
    private.mkdir(parents=True, exist_ok=True)
    if private.is_symlink() or private.is_junction():
        raise OSError('Device control directory must not be a link')
    protect_private_directory(private)
    import msvcrt
    with (private / 'startup.lock').open('a+b') as lock:
        lock.seek(0)
        if not lock.read(1):
            lock.write(b'0')
            lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise RuntimeError('Gerät verbindet bereits; erneut versuchen / Device is already connecting; retry') from None
        try:
            for _, args, _, existing in processes():
                if existing != root:
                    continue
                if Path(option(args, '--config')) != private / 'rclone.conf':
                    raise RuntimeError('Device mount path is occupied')
                if root.is_mount() or root.is_junction():
                    register(root, portable=True)
                    return root
                raise RuntimeError('Device is still connecting; retry')
            if identifier not in {row['id'] for row in locations()}:
                raise OSError('Gerät nicht verbunden / Device is not connected')
            process = subprocess.Popen(helper_command('device_bridge'), stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                       text=True, encoding='utf-8')
            replies = queue.Queue()
            threading.Thread(target=lambda: replies.put(process.stdout.readline()), daemon=True).start()
            try:
                process.stdin.write(json.dumps(dict(id=identifier, password=secrets.token_urlsafe(32))) + '\n')
                process.stdin.close()
                line = replies.get(timeout=35)
                result = json.loads(line)
                if not result.get('ready') or result.get('root') != str(root):
                    raise RuntimeError(result.get('error', 'Device mount failed'))
                register(root, portable=True)
                return root
            except BaseException:
                # Until readiness is published no application file action can
                # reach this mount. Kill only descendants created by this helper.
                import psutil
                try:
                    children = psutil.Process(process.pid).children(recursive=True)
                    for child in children:
                        child.terminate()
                except psutil.Error:
                    pass
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
                raise
            finally:
                process.stdout.close()
        finally:
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)


def serve(configuration):
    """Persistent helper; device COM and HTTP handling stay on this one thread."""
    import socket
    from .windows_wpd import apartment, Device
    from .device_dav import DeviceServer
    from . import rclone_runtime
    from .windows_native import keyring, protect_private_directory
    from .windows_mounts import processes
    identifier = configuration['id']
    if not identifier.startswith('wpd:'):
        raise ValueError('Not a portable device')
    root, private = paths(identifier)
    password = configuration['password']
    if not isinstance(password, str) or len(password) < 32 or '\n' in password:
        raise ValueError('Invalid mount credential')
    cache = private / 'uploads'
    cache.mkdir(parents=True, exist_ok=True)
    protect_private_directory(private)
    # Never recursively delete an occupied path or attach over another mount.
    if any(existing == root for _, _, _, existing in processes()):
        raise RuntimeError('Device mount path is already used')
    root.parent.mkdir(parents=True, exist_ok=True)
    if os.path.lexists(root):
        if root.is_symlink() or root.is_junction() or not root.is_dir():
            raise RuntimeError('Device mount path is occupied')
        root.rmdir()
    binary = rclone_runtime.ensure_cloud_backend(threading.Event())
    with apartment(), Device(identifier[4:]) as device, DeviceServer(device, password, cache) as server:
        # Trigger real storage access before starting a mount; locked phones must
        # fail visibly, rather than appear as an empty filesystem.
        if not device.children('DEVICE'):
            raise RuntimeError('Kein Gerätespeicher verfügbar. Gerät entsperren und Dateiübertragung erlauben. / Unlock device and enable file transfer.')
        obscured = subprocess.run([binary, 'obscure', '-'], input=password + '\n', text=True,
                                  capture_output=True, check=True, timeout=10).stdout.strip()
        config = private / 'rclone.conf'
        config.write_text('[device]\ntype = webdav\nvendor = other\nurl = http://127.0.0.1:' +
                          str(server.server_port) + '/\nuser = OpenCommander\npass = ' + obscured + '\n', encoding='utf-8')
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            port = listener.getsockname()[1]
        control = secrets.token_urlsafe(32)
        env = dict(os.environ, RCLONE_RC_USER='OpenCommander', RCLONE_RC_PASS=control)
        command = [binary, '--config', str(config), 'mount', 'device:', str(root),
                   '--vfs-cache-mode', 'off', '--dir-cache-time', '2s', '--attr-timeout', '0s', '--poll-interval', '0',
                   '--fuse-flag', '-oVolumeSerialNumber=' + root.name[:8],
                   '--contimeout', '5s', '--timeout', '30s', '--low-level-retries', '1', '--retries', '1',
                   '--rc', '--rc-addr', f'127.0.0.1:{port}']
        keyring(root, 'mount-control', 'store', json.dumps(dict(port=port, password=control)))
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, env=env)
        ready, deadline = False, time.monotonic() + 25
        try:
            while process.poll() is None and not server.stopping:
                server.handle_request()
                if not ready:
                    if root.is_mount() or root.is_junction():
                        print(json.dumps(dict(ready=True, root=str(root))), flush=True)
                        ready = True
                    elif time.monotonic() >= deadline:
                        raise RuntimeError('WinFsp-Geräteeinbindung fehlgeschlagen / WinFsp device mount failed')
            if not ready:
                raise RuntimeError('WinFsp fehlt oder Geräteeinbindung fehlgeschlagen / Install WinFsp or retry device connection')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
            keyring(root, 'mount-control', 'clear')
            # Credentials are useful only to this live process.
            config.unlink(missing_ok=True)


def unmount(identifier):
    from .windows_mounts import unmount as disconnect
    root, _ = paths(identifier)
    disconnect(root)


def settle(path):
    """Discard synthetic VFS timestamps before recording a recovery proof.

MTP devices may not support setting modification times. rclone can temporarily
cache a requested time despite that limitation. Read the actual device metadata
before hashing; do not weaken the fingerprint or save that temporary value.
"""
    import base64
    import urllib.request
    from .provider_mounts import portable
    from .windows_native import keyring
    root = portable(path)
    if root is None:
        return
    control = keyring(root, 'mount-control', 'lookup')
    if control is None:
        raise OSError('Portable device mount control is unavailable')
    value = json.loads(control)
    relative = Path(path).parent.relative_to(root).as_posix()
    request = urllib.request.Request(f'http://127.0.0.1:{int(value["port"])}/vfs/refresh',
        data=json.dumps({'dir': '' if relative == '.' else relative}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Basic ' + base64.b64encode(
            ('OpenCommander:' + value['password']).encode()).decode()})
    with urllib.request.urlopen(request, timeout=10) as response:
        result = json.load(response)
        if 'error' in result:
            raise OSError('Could not refresh portable device metadata')
