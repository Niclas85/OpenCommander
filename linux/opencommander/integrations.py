"""Desktop integration through the host's GIO/GVFS services."""
from pathlib import Path
import os
import json
import subprocess
import time
from urllib.parse import urlsplit
from .desktop import host_environment


def validate_uri(value):
    value = value.strip()
    parsed = urlsplit(value)
    if parsed.scheme not in ('smb', 'sftp', 'dav', 'davs', 'ftp') or not parsed.hostname:
        raise ValueError('Adresse: smb://server/freigabe, sftp://server oder davs://server/pfad')
    if parsed.password is not None or any(ord(c) < 32 for c in value):
        raise ValueError('Passwörter bitte ausschließlich im System-Anmeldedialog eingeben.')
    return value


def invoke(action='list', identifier='', cancel=None):
    if os.name == 'nt':
        from .windows_native import invoke as windows_invoke
        return windows_invoke(action, identifier, cancel)
    if cancel is not None:
        return invoke_cancellable(action, identifier, cancel)
    result = subprocess.run(['/usr/bin/python3', str(Path(__file__).with_name('gio_bridge.py'))],
                            input=json.dumps({'action': action, 'id': identifier}),
                            text=True, capture_output=True, env=host_environment(), timeout=15 if action in ('list', 'scan', 'properties', 'directory-size') else None)
    try:
        response = json.loads(result.stdout)
    except ValueError:
        raise RuntimeError('GVFS nicht verfügbar. Benötigt: python3-gi, gir1.2-gtk-4.0, gvfs-backends und gvfs-fuse.') from None
    if result.returncode or response.get('error'):
        raise RuntimeError(response.get('error', 'GVFS operation failed'))
    return response['locations']


def open_accounts():
    subprocess.Popen(['gnome-control-center', 'online-accounts'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, env=host_environment())


def invoke_cancellable(action, identifier, cancel):
    """Only read-only scans may be terminated; never interrupt a filesystem mutation."""
    if action != 'scan':
        raise ValueError('Cancellation is only supported for directory scans')
    if cancel.is_set():
        raise RuntimeError('Abgebrochen / Cancelled')
    command = ['/usr/bin/python3', str(Path(__file__).with_name('gio_bridge.py'))]
    request = json.dumps({'action': action, 'id': identifier})
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, env=host_environment()) as process:
        deadline = time.monotonic() + 15
        first = True
        try:
            while True:
                if cancel.is_set():
                    raise RuntimeError('Abgebrochen / Cancelled')
                if time.monotonic() >= deadline:
                    raise subprocess.TimeoutExpired(command, 15)
                try:
                    output, _ = process.communicate(input=request if first else None, timeout=0.1)
                    break
                except subprocess.TimeoutExpired:
                    first = False
            response = json.loads(output)
            if process.returncode or response.get('error'):
                raise RuntimeError(response.get('error', 'GVFS operation failed'))
            return response['locations']
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
