"""Validated server settings; credentials stay outside the rclone config."""
import base64
import configparser
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile

from .desktop import host_environment
from . import rclone_runtime

SERVER_KINDS = ('sftp', 'ftp', 'ftps')


def settings(kind, host, port, user, mode, key='', directory=''):
    host, user, directory = host.strip(), user.strip(), directory.strip()
    if kind not in SERVER_KINDS or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.:-]*', host):
        raise ValueError('Server ohne Protokoll/Pfad eingeben, z. B. nas.example.org / Enter a host name only')
    if not 1 <= int(port) <= 65535 or not user or any(c in user + directory for c in '\r\n\x00'):
        raise ValueError('Benutzer, Port oder Startordner ungültig / Invalid user, port or folder')
    if mode not in ('password', 'key', 'agent') or (kind != 'sftp' and mode != 'password'):
        raise ValueError('FTP/FTPS verwendet Benutzer und Passwort / FTP requires password authentication')
    section = {'type': 'sftp' if kind == 'sftp' else 'ftp', 'host': host, 'port': str(port), 'user': user}
    encrypted_openssh = False
    encrypted_pem = False
    if kind == 'sftp':
        section.update(known_hosts_file=str(Path.home() / '.ssh/known_hosts'), shell_type='none')
        if mode == 'key':
            keypath = Path(key).expanduser().absolute()
            if not keypath.is_file() or keypath.stat().st_size > 1024 * 1024:
                raise ValueError('Private SSH-Schlüsseldatei auswählen / Select a private SSH key')
            if keypath.stat().st_mode & 0o077:
                raise ValueError('SSH-Schlüssel ist für andere Benutzer lesbar. Rechte auf 600 setzen / Set private key permissions to 600')
            data = keypath.read_bytes()
            encrypted_pem = b'ENCRYPTED' in data
            if b'PRIVATE KEY-----' not in data:
                raise ValueError('Privaten Schlüssel auswählen; .pub und PuTTY .ppk werden nicht unterstützt / Select a private OpenSSH or PEM key')
            if b'BEGIN OPENSSH PRIVATE KEY' in data:
                try:
                    raw = base64.b64decode(b''.join(data.splitlines()[1:-1]), validate=True)
                    offset = len(b'openssh-key-v1\x00')
                    if not raw.startswith(b'openssh-key-v1\x00'):
                        raise ValueError()
                    length = struct.unpack('>I', raw[offset:offset + 4])[0]
                    encrypted_openssh = raw[offset + 4:offset + 4 + length] != b'none'
                except Exception:
                    raise ValueError('Ungültiger OpenSSH-Schlüssel / Invalid OpenSSH key') from None
            if encrypted_openssh:
                section['key_use_agent'] = 'true'
                if Path(str(keypath) + '.pub').is_file():
                    section['key_file'] = str(keypath)
            else:
                section['key_file'] = str(keypath)
        elif mode == 'agent':
            section['key_use_agent'] = 'true'
    elif kind == 'ftps':
        section.update(explicit_tls='true', tls='false', no_check_certificate='false')
    return section, {'auth_mode': mode, 'key_path': str(Path(key).expanduser().absolute()) if mode == 'key' else '',
                     'agent_key': encrypted_openssh, 'secret_required': mode == 'password' or encrypted_openssh or encrypted_pem,
                     'remote_directory': directory, 'server_login': True}


def write_config(path, identifier, section):
    if not re.fullmatch(r'oc_[A-Za-z0-9]+', identifier):
        raise ValueError('Invalid profile')
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(path)
    parser[identifier] = section  # Replace removes stale passwords and alternative auth modes.
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.server-')
    try:
        with os.fdopen(fd, 'w') as stream:
            parser.write(stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def keyring(state, identifier, action, secret=None):
    request = dict(state=str(Path(state).resolve()), profile=identifier, action=action)
    if secret is not None:
        request['secret'] = secret
    try:
        result = subprocess.run(['/usr/bin/python3', str(Path(__file__).with_name('secret_bridge.py'))],
                                input=json.dumps(request), text=True, capture_output=True,
                                env=host_environment(), timeout=60)
        value = json.loads(result.stdout)
    except Exception:
        raise RuntimeError('Linux-Schlüsselbund nicht verfügbar / Linux keyring unavailable') from None
    if result.returncode or 'error' in value:
        raise RuntimeError('Linux-Schlüsselbund nicht verfügbar oder gesperrt / Linux keyring unavailable or locked')
    return value.get('result')


def credential_environment(main, profile):
    env = host_environment()
    if not profile.get('server_login'):
        return env
    secret = getattr(main, 'server_secrets', {}).get(profile['id'])
    if secret is None and profile.get('remember_secret'):
        secret = keyring(main.state_dir, profile['id'], 'lookup')
    mode = profile.get('auth_mode')
    if secret is None and profile.get('secret_required', mode == 'password'):
        raise RuntimeError('Anmeldung benötigt: „Erneut anmelden“ wählen / Sign in again to enter credentials')
    if profile.get('agent_key'):
        if not env.get('SSH_AUTH_SOCK'):
            raise RuntimeError('SSH-Agent fehlt. Linux-Schlüsselverwaltung aktivieren / SSH agent unavailable')
        askpass = Path(__file__).with_name('secret_bridge.py')
        agent_env = dict(env, SSH_ASKPASS=str(askpass), SSH_ASKPASS_REQUIRE='force',
                         DISPLAY=env.get('DISPLAY', ':0'), OPENCOMMANDER_ASKPASS='1',
                         OPENCOMMANDER_KEY_PASSPHRASE=secret or '')
        result = subprocess.run(['ssh-add', '-t', '3600', profile['key_path']], stdin=subprocess.DEVNULL,
                                capture_output=True, env=agent_env, timeout=30)
        if result.returncode:
            raise RuntimeError('SSH-Schlüssel konnte nicht entsperrt werden. Passphrase und Agent prüfen / Could not unlock SSH key')
    elif mode == 'agent' and not env.get('SSH_AUTH_SOCK'):
        raise RuntimeError('SSH-Agent fehlt / SSH agent unavailable')
    elif secret:
        # Obscure only for rclone's wire format, not for persistent storage.
        result = subprocess.run([rclone_runtime.binary(), 'obscure', '-'], input=secret + '\n',
                                capture_output=True, text=True, env=env, timeout=10)
        if result.returncode:
            raise RuntimeError('Anmeldung konnte nicht vorbereitet werden / Could not prepare login')
        option = 'PASS' if mode == 'password' else 'KEY_FILE_PASS'
        env['RCLONE_CONFIG_' + profile['id'].upper() + '_' + option] = result.stdout.strip()
    return env


def hostkey_status(target, keys):
    """Untrusted scans never replace a known key, even before the trust prompt."""
    rows = [row.split() for row in keys.decode().splitlines() if row and not row.startswith('#')]
    if not rows or any(len(row) != 3 for row in rows):
        raise ValueError('Ungültige SSH-Serverschlüssel / Invalid host keys')
    if not target.exists():
        return 'unknown'
    result = subprocess.run(['ssh-keygen', '-F', rows[0][0], '-f', str(target)],
                            capture_output=True, timeout=5, env=host_environment())
    if result.returncode not in (0, 1):
        raise RuntimeError('known_hosts nicht lesbar / Could not read known_hosts')
    known = [row.split() for row in result.stdout.decode().splitlines() if row and not row.startswith('#')]
    if not known:
        return 'unknown'
    incoming = {tuple(row[-2:]) for row in rows}
    recorded = {tuple(row[-2:]) for row in known}
    if any(kind == other and key != value for kind, key in recorded for other, value in incoming):
        raise RuntimeError('SSH-Serverschlüssel geändert! Verbindung abgebrochen. Beim Betreiber prüfen; kein automatisches Ersetzen. / SSH host key changed; connection refused')
    if not incoming & recorded:
        raise RuntimeError('SSH-Serverschlüssel stimmt nicht überein / SSH host key does not match')
    return 'known'
