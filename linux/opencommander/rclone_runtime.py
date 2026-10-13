"""App-private, checksum-verified rclone runtime; system mounts are untouched."""
import hashlib
import os
import platform
import re
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from .desktop import host_environment


def runtime_root():
    base = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    return base / 'opencommander/runtime'


def binary():
    local = runtime_root() / 'rclone'
    return str(local) if local.is_file() and os.access(local, os.X_OK) else shutil.which('rclone')


def ensure_cloud_backend(cancel):
    executable = binary()
    if executable:
        info = subprocess.run([executable, 'version'], capture_output=True, text=True,
                              timeout=10, env=host_environment())
        match = re.search(r'rclone v(\d+)\.(\d+)\.(\d+)', info.stdout)
        # Current SRP authentication requires a recent iCloud implementation.
        if match and tuple(map(int, match.groups())) >= (1, 75, 2):
            return executable
    return install(cancel)


def fetch(url, cancel, destination=None):
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'OpenCommander-Linux/0.3.6'}), timeout=30) as response:
        data = bytearray()
        while True:
            if cancel.is_set():
                raise RuntimeError('Abgebrochen / Cancelled')
            block = response.read(1024 * 1024)
            if not block:
                break
            if destination is None:
                data.extend(block)
                if len(data) > 2 * 1024 * 1024:
                    raise RuntimeError('Invalid runtime metadata')
            else:
                destination.write(block)
        return bytes(data)


def install(cancel):
    arch = {'x86_64': 'amd64', 'aarch64': 'arm64'}.get(platform.machine())
    if not arch:
        raise RuntimeError('Unsupported runtime architecture')
    version = fetch('https://downloads.rclone.org/version.txt', cancel).decode().strip()
    if not re.fullmatch(r'rclone v\d+\.\d+\.\d+', version):
        raise RuntimeError('Invalid rclone release version')
    version = version.split()[1]
    name = f'rclone-{version}-linux-{arch}'
    base = f'https://downloads.rclone.org/{version}/'
    checksums = fetch(base + 'SHA256SUMS', cancel).decode()
    expected = next((line.split()[0] for line in checksums.splitlines()
                     if line.split() and line.split()[-1].lstrip('*') == name + '.zip'), None)
    if not expected or not re.fullmatch(r'[a-fA-F0-9]{64}', expected):
        raise RuntimeError('Missing official rclone checksum')
    root = runtime_root()
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(root, 0o700)
    with tempfile.TemporaryDirectory(prefix='download-', dir=root) as temp:
        archive = Path(temp) / 'runtime.zip'
        with archive.open('wb') as stream:
            fetch(base + name + '.zip', cancel, stream)
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual.lower() != expected.lower():
            raise RuntimeError('rclone checksum mismatch; installation stopped')
        with zipfile.ZipFile(archive) as package:
            executable = Path(temp) / 'rclone'
            executable.write_bytes(package.read(name + '/rclone'))
            license_text = package.read(name + '/README.txt')
        executable.chmod(0o700)
        # Validate before atomically replacing only the private executable.
        subprocess.run([str(executable), 'version'], capture_output=True, check=True,
                       timeout=10, env=host_environment())
        if cancel.is_set():
            raise RuntimeError('Abgebrochen / Cancelled')
        (root / 'rclone-README.txt').write_bytes(license_text)
        os.replace(executable, root / 'rclone')
    return str(root / 'rclone')
