"""Opt-in Pageant/SFTP live check, only synthetic keys and a loopback server.

Usage: python windows/tests/agent_live_validation.py PATH_TO_OFFICIAL_PAGEANT
Never attaches test keys to an already running personal Pageant instance.
"""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import threading
import time
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'linux'))
from opencommander import rclone_runtime, server_connections, windows_mounts, windows_native
from opencommander.online_ui import private_config
from opencommander.operations import FileEngine


def ssh_string(value):
    return struct.pack('>I', len(value)) + value


def mpint(value):
    data = value.to_bytes((value.bit_length() + 7) // 8, 'big')
    return ssh_string((b'\0' if data[0] & 128 else b'') + data)


def make_ppk(key, path):
    from cryptography.hazmat.primitives import serialization
    public = key.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH)
    blob = base64.b64decode(public.split()[1])
    numbers = key.private_numbers()
    private = b''.join(mpint(value) for value in (numbers.d, numbers.p, numbers.q, numbers.iqmp))
    comment = b'OpenCommander disposable loopback fixture'
    mac_key = hashlib.sha1(b'putty-private-key-file-mac-key').digest()
    mac = hmac.new(mac_key, b''.join(ssh_string(value) for value in
                   (b'ssh-rsa', b'none', comment, blob, private)), hashlib.sha1).hexdigest()
    def lines(data):
        encoded = base64.b64encode(data).decode()
        return [encoded[i:i + 64] for i in range(0, len(encoded), 64)]
    pub_lines, private_lines = lines(blob), lines(private)
    path.write_text('\n'.join(['PuTTY-User-Key-File-2: ssh-rsa', 'Encryption: none',
        'Comment: ' + comment.decode(), f'Public-Lines: {len(pub_lines)}', *pub_lines,
        f'Private-Lines: {len(private_lines)}', *private_lines, 'Private-MAC: ' + mac, '']), encoding='ascii')
    return public


def main():
    import psutil
    from cryptography.hazmat.primitives.asymmetric import rsa, ed25519
    from cryptography.hazmat.primitives import serialization
    pageant = Path(sys.argv[1]).resolve()
    assert hashlib.file_digest(pageant.open('rb'), 'sha256').hexdigest() == '3bd76b57fcd09acc948268c753ea2077b0c557ca435323301a9b572661f98ecd'
    if any((process.info['name'] or '').casefold() == 'pageant.exe' for process in psutil.process_iter(['name'])):
        raise RuntimeError('Personal Pageant is already running; no fixture key will be added')
    base = REPO / 'windows/build/agent-fixtures' / str(time.time_ns())
    base.mkdir(parents=True)
    windows_native.protect_private_directory(base)
    backing = base / 'server'
    backing.mkdir()
    (backing / 'read.txt').write_bytes(b'Synthetic agent fixture')
    ppk = base / 'fixture.ppk'
    public = make_ppk(rsa.generate_private_key(public_exponent=65537, key_size=2048), ppk)
    authorized = base / 'authorized_keys'
    authorized.write_bytes(public + b'\n')
    host = ed25519.Ed25519PrivateKey.generate()
    host_key = base / 'host-key'
    host_key.write_bytes(host.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH,
                                          serialization.NoEncryption()))
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    known = base / 'known_hosts'
    host_public = host.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH)
    known.write_bytes(f'[127.0.0.1]:{port} '.encode() + host_public + b'\n')
    binary = str(REPO / 'windows/build/runtime/rclone.exe')
    rclone_runtime.binary = lambda: binary
    state = base / 'profile'
    config = private_config(state)
    section, detail = server_connections.settings('sftp', '127.0.0.1', port, 'fixture', 'agent')
    section['known_hosts_file'] = str(known)
    assert 'pass' not in section and 'key_file' not in section
    server_connections.write_config(config, 'oc_agentfixture', section)
    profile = dict(id='oc_agentfixture', kind='sftp', name='Ephemeral Pageant fixture', **detail)
    owner = SimpleNamespace(state_dir=state, server_secrets={})
    log = (base / 'server.log').open('w', encoding='utf-8')
    environment = dict(os.environ)
    for key in list(environment):
        if key.startswith('RCLONE_CONFIG_') or key == 'SSH_AUTH_SOCK':
            environment.pop(key)
    server = subprocess.Popen([binary, '--config', str(config), 'serve', 'sftp', str(backing),
        '--addr', f'127.0.0.1:{port}', '--key', str(host_key), '--authorized-keys', str(authorized)],
        stdout=log, stderr=log, env=environment, creationflags=subprocess.CREATE_NO_WINDOW)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    agent = subprocess.Popen([str(pageant), '-restrict-acl', str(ppk)], startupinfo=startup)
    root = None
    try:
        deadline = time.monotonic() + 12
        while True:
            probe = subprocess.run([binary, '--config', str(config), 'lsjson', 'oc_agentfixture:',
                '--contimeout', '2s', '--timeout', '3s', '--retries', '1', '--low-level-retries', '1'],
                capture_output=True, env=environment, timeout=6, creationflags=subprocess.CREATE_NO_WINDOW)
            if probe.returncode == 0:
                assert any(row['Name'] == 'read.txt' for row in json.loads(probe.stdout))
                break
            if agent.poll() is not None or server.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('Pageant-only authentication failed: ' + probe.stderr.decode('utf-8', errors='replace'))
            time.sleep(.2)
        root = windows_mounts.mount_profile(owner, profile, threading.Event())
        source = base / 'Agent Grüße 日本語.bin'
        payload = bytes(range(256)) * 1024
        source.write_bytes(payload)
        engine = FileEngine(base / 'recovery')
        operation = engine.transfer([source], root)
        assert (backing / source.name).read_bytes() == payload
        assert (root / source.name).read_bytes() == payload
        FileEngine(engine.state_dir).undo(operation['id'])
        assert not (backing / source.name).exists()
        windows_mounts.unmount(root)
        root = None
        # Refuse another server identity even though a valid signing agent exists.
        other = ed25519.Ed25519PrivateKey.generate().public_key().public_bytes(
            serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH)
        known.write_bytes(f'[127.0.0.1]:{port} '.encode() + other + b'\n')
        rejection = subprocess.run([binary, '--config', str(config), 'lsjson', 'oc_agentfixture:',
            '--contimeout', '2s', '--timeout', '3s', '--retries', '1', '--low-level-retries', '1'],
            capture_output=True, env=environment, timeout=6, creationflags=subprocess.CREATE_NO_WINDOW)
        assert rejection.returncode != 0
        result = dict(status='pass', agent='Pageant 0.85', personal_keys_used=False,
            authentication='agent only, no password or client key file in rclone',
            mount=True, upload_bytes=len(payload), exact_download=True, persistent_undo=True,
            changed_host_key_rejected=True, graceful_unmount=True)
        (REPO / 'windows/build/agent-live-results.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result))
    finally:
        if root is not None:
            windows_mounts.unmount(root)
        for process in (agent, server):
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
        log.close()
        # Only the generated fixture keys, never ~/.ssh or a personal keyring.
        ppk.unlink(missing_ok=True)
        host_key.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
