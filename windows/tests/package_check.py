"""Verify frozen helper I/O and dependencies using a disposable local fixture."""
import json
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import socket
import time

parser = argparse.ArgumentParser()
parser.add_argument('bundle', type=Path)
parser.add_argument('--require-publisher-google', action='store_true')
args = parser.parse_args()
bundle = args.bundle
publisher = bundle / '_internal/opencommander/assets/google-oauth.json'
if args.require_publisher_google and not publisher.is_file():
    raise SystemExit('Publisher Google Desktop OAuth identity missing from the Windows package.')
if publisher.exists():
    sys.path.insert(0, str(bundle / 'source/linux'))
    from opencommander.public_oauth import normalized
    exported = json.loads(publisher.read_text(encoding='utf-8'))
    assert exported == normalized(exported), 'Only the sanitized publisher application identity may be packaged'
helper = bundle / 'helpers/OpenCommanderHelper.exe'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / 'Grüße 日本語.bin'
    source.write_bytes(bytes(range(256)) * 100)
    scan = subprocess.run([str(helper), 'windows_bridge'], input=json.dumps(dict(action='scan', id=str(root))),
                          text=True, capture_output=True, timeout=20, check=True)
    assert json.loads(scan.stdout)['locations'][0]['name'] == source.name
    target = root / 'copy'
    fetch = subprocess.run([str(helper), 'media_fetch'], input=json.dumps(dict(source=str(source), target=str(target), limit=30000)),
                           text=True, capture_output=True, timeout=20, check=True)
    assert json.loads(fetch.stdout.splitlines()[-1])['done']
    assert source.read_bytes() == target.read_bytes()
    backend = subprocess.run([str(bundle / 'tools/rclone.exe'), 'version'], capture_output=True, check=True, timeout=10)
    assert b'rclone v' in backend.stdout
    # Exercise the frozen SSH scanner and its crypto dependencies against a real
    # server. Compare its public key; discovery must never authenticate or trust it.
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.hazmat.primitives import serialization
    host_key = ed25519.Ed25519PrivateKey.generate()
    key_file = root / 'fixture-host-key'
    key_file.write_bytes(host_key.private_bytes(serialization.Encoding.PEM,
        serialization.PrivateFormat.OpenSSH, serialization.NoEncryption()))
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    server = subprocess.Popen([str(bundle / 'tools/rclone.exe'), '--config', str(root / 'empty.conf'),
        'serve', 'sftp', str(root), '--addr', f'127.0.0.1:{port}', '--user', 'fixture',
        '--pass', 'fixture-only-password', '--key', str(key_file)],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 10
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.2):
                    break
            except OSError:
                assert server.poll() is None and time.monotonic() < deadline
                time.sleep(.1)
        identity = subprocess.run([str(helper), 'windows_bridge'],
            input=json.dumps(dict(action='ssh-fingerprints', id=dict(host='127.0.0.1', port=port))),
            text=True, capture_output=True, timeout=20, check=True)
        identity = json.loads(identity.stdout)['locations']
        public = host_key.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH).decode()
        assert identity['keys'] == f'[127.0.0.1]:{port} {public}\n'
        assert 'SHA256:' in identity['fingerprints']
    finally:
        server.terminate()
        server.wait(timeout=5)
    refused = subprocess.run([str(helper), 'windows_bridge'],
        input=json.dumps(dict(action='ssh-fingerprints', id=dict(host='127.0.0.1', port=port))),
        text=True, capture_output=True, timeout=20)
    assert refused.returncode != 0
    error = json.loads(refused.stdout)['error']
    assert f'127.0.0.1:{port}' in error and 'Connection refused' in error
    assert 'Password authentication has not started' in error
    devices = subprocess.run([str(helper), 'windows_bridge'], input=json.dumps(dict(action='list', id='')),
                             text=True, capture_output=True, timeout=20, check=True)
    assert isinstance(json.loads(devices.stdout)['locations'], list)
    environment = dict(os.environ, LOCALAPPDATA=str(root))
    absent = subprocess.run([str(helper), 'device_bridge'],
        input=json.dumps(dict(id='wpd:OpenCommander-Nonexistent-Test-Device', password='x' * 40)) + '\n',
        text=True, capture_output=True, timeout=20, env=environment)
    error = json.loads(absent.stdout)['error']
    assert absent.returncode != 0 and 'HRESULT' in error, error
print('PASS: frozen Windows/WPD helpers, missing-device failure, Unicode listing, binary media download and rclone runtime')
