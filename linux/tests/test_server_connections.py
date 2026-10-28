import configparser
import os
from pathlib import Path
import subprocess
from types import SimpleNamespace

import pytest
from opencommander import server_connections as server
from opencommander.online_ui import private_config, ssh_fingerprints, save_hostkeys


def test_settings_validate_and_disable_remote_shell(tmp_path):
    section, profile = server.settings('sftp', 'nas.example.org', 22, 'alice', 'password')
    assert Path(section['known_hosts_file']).parts[-2:] == ('.ssh', 'known_hosts')
    assert section['shell_type'] == 'none'
    assert profile['secret_required']
    section, _ = server.settings('ftps', 'nas.example.org', 21, 'alice', 'password')
    assert section['explicit_tls'] == 'true'
    assert section['no_check_certificate'] == 'false'
    for host in ('-oProxyCommand=evil', 'sftp://server', 'server/path', 'server\noption'):
        with pytest.raises(ValueError):
            server.settings('sftp', host, 22, 'alice', 'password')
    with pytest.raises(ValueError):
        server.settings('ftp', 'server', 21, 'alice', 'agent')


def test_reconfigure_removes_old_secrets_without_affecting_cloud(tmp_path):
    path = private_config(tmp_path)
    path.write_text('[oc_server]\ntype = sftp\npass = old-secret\nkey_file_pass = old-passphrase\n[oc_cloud]\ntype = drive\ntoken = fixture\n')
    section, _ = server.settings('sftp', 'server', 22, 'alice', 'agent')
    server.write_config(path, 'oc_server', section)
    parser = configparser.ConfigParser()
    parser.read(path)
    assert 'pass' not in parser['oc_server']
    assert 'key_file_pass' not in parser['oc_server']
    assert parser['oc_cloud']['token'] == 'fixture'
    from desktop_test_support import assert_private_file
    assert_private_file(path)


def test_secret_is_only_in_stdin_and_child_environment(tmp_path, monkeypatch):
    calls = []
    def run(command, **kwargs):
        calls.append((command, kwargs))
        return SimpleNamespace(returncode=0, stdout='obscured-value\n')
    monkeypatch.setattr(server.subprocess, 'run', run)
    monkeypatch.setattr(server.rclone_runtime, 'binary', lambda: '/fixture/rclone')
    main = SimpleNamespace(state_dir=tmp_path, server_secrets={'oc_test': ' a private password '})
    env = server.credential_environment(main, dict(id='oc_test', server_login=True, auth_mode='password'))
    assert calls[0][0] == ['/fixture/rclone', 'obscure', '-']
    assert calls[0][1]['input'] == ' a private password \n'
    assert env['RCLONE_CONFIG_OC_TEST_PASS'] == 'obscured-value'
    assert ' a private password ' not in str(calls[0][0])
    assert 'RCLONE_CONFIG_OC_TEST_PASS' not in os.environ


def test_key_permissions_and_encrypted_openssh_agent(tmp_path):
    key = tmp_path / 'key'
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', 'fixture-only', '-f', str(key)], check=True)
    section, profile = server.settings('sftp', 'localhost', 22, 'alice', 'key', str(key))
    assert profile['agent_key'] and profile['secret_required']
    assert section['key_use_agent'] == 'true'
    assert section['key_file'] == str(key)
    key.chmod(0o644)
    if os.name != 'nt':
        with pytest.raises(ValueError, match='600'):
            server.settings('sftp', 'localhost', 22, 'alice', 'key', str(key))
    with pytest.raises(ValueError, match='Privaten'):
        (tmp_path / 'key.pub').chmod(0o600)
        server.settings('sftp', 'localhost', 22, 'alice', 'key', str(key) + '.pub')


def test_trust_unknown_known_and_changed(tmp_path):
    target = tmp_path / 'known_hosts'
    a = b'example.org ssh-ed25519 AAAA\n'
    assert server.hostkey_status(target, a) == 'unknown'
    # Real public keys are required by ssh-keygen -F.
    key = tmp_path / 'key'
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
    parts = (tmp_path / 'key.pub').read_text().split()
    original = ('example.org ' + ' '.join(parts[:2]) + '\n').encode()
    save_hostkeys(target, original)
    assert server.hostkey_status(target, original) == 'known'
    with pytest.raises(RuntimeError, match='geändert'):
        server.hostkey_status(target, a)


def test_keyring_payload_not_in_command(tmp_path, monkeypatch):
    calls = []
    def run(command, **kwargs):
        calls.append((command, kwargs))
        return SimpleNamespace(returncode=0, stdout='{"result": true}')
    monkeypatch.setattr(server.subprocess, 'run', run)
    assert server.keyring(tmp_path, 'oc_fixture', 'store', 'private-secret') is True
    assert 'private-secret' not in str(calls[0][0])
    assert 'private-secret' in calls[0][1]['input']
    assert calls[0][1]['timeout'] == 60


def test_real_local_sftp_password_key_and_encrypted_key(tmp_path):
    import socket
    import time
    from opencommander import rclone_runtime
    binary = rclone_runtime.binary()
    if not binary:
        pytest.skip('rclone unavailable')
    root = tmp_path / 'files'
    root.mkdir()
    (root / 'fixture.txt').write_text('fixture')
    hostkey = tmp_path / 'hostkey'
    key = tmp_path / 'clientkey'
    encrypted = tmp_path / 'encryptedkey'
    for path, password in ((hostkey, ''), (key, ''), (encrypted, 'fixture-passphrase')):
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', password, '-f', str(path)], check=True)
    authorized = tmp_path / 'authorized_keys'
    authorized.write_bytes(key.with_suffix('.pub').read_bytes() + encrypted.with_suffix('.pub').read_bytes())
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = dict(server.host_environment(), RCLONE_PASS='fixture-password')
    process = subprocess.Popen([binary, 'serve', 'sftp', str(root), '--addr', f'127.0.0.1:{port}',
                                '--key', str(hostkey), '--authorized-keys', str(authorized), '--user', 'fixture',
                                '--config', str(tmp_path / 'empty.conf')], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    agent_pid = None
    try:
        until = time.monotonic() + 5
        while True:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.1):
                    break
            except OSError:
                if time.monotonic() > until:
                    raise AssertionError('Fixture SFTP server did not start')
                time.sleep(.05)
        _, keys = ssh_fingerprints('127.0.0.1', port)
        known = tmp_path / 'known_hosts'
        save_hostkeys(known, keys)
        assert server.hostkey_status(known, keys) == 'known'
        config = private_config(tmp_path / 'state')
        main = SimpleNamespace(state_dir=tmp_path / 'state', server_secrets={})
        for mode, path, secret in (('password', '', 'fixture-password'), ('key', str(key), ''),
                                   ('key', str(encrypted), 'fixture-passphrase')):
            section, extra = server.settings('sftp', '127.0.0.1', port, 'fixture', mode, path)
            section['known_hosts_file'] = str(known)
            profile = dict(id='oc_test', **extra)
            server.write_config(config, profile['id'], section)
            main.server_secrets[profile['id']] = secret
            if extra['agent_key'] and os.name != 'nt':
                agent = subprocess.run(['ssh-agent', '-s'], capture_output=True, text=True, check=True)
                import re
                agent_pid = int(re.search(r'SSH_AGENT_PID=(\d+)', agent.stdout).group(1))
                sock = re.search(r'SSH_AUTH_SOCK=([^;]+)', agent.stdout).group(1)
                previous_sock = os.environ.get('SSH_AUTH_SOCK')
                os.environ['SSH_AUTH_SOCK'] = sock
            try:
                connection_env = server.credential_environment(main, profile)
                result = subprocess.run([binary, '--config', str(config), 'lsf', 'oc_test:'],
                                        capture_output=True, text=True, env=connection_env, timeout=15)
                assert result.returncode == 0, 'Local SFTP authentication failed'
                assert result.stdout.strip() == 'fixture.txt'
                assert secret not in config.read_text() if secret else True
                denied = dict(connection_env, RCLONE_CONFIG_OC_TEST_KNOWN_HOSTS_FILE=str(tmp_path / 'missing_hosts'))
                refused = subprocess.run([binary, '--config', str(config), 'lsf', 'oc_test:'],
                                         capture_output=True, env=denied, timeout=15)
                assert refused.returncode != 0
            finally:
                if extra['agent_key'] and os.name != 'nt':
                    if previous_sock is None:
                        os.environ.pop('SSH_AUTH_SOCK', None)
                    else:
                        os.environ['SSH_AUTH_SOCK'] = previous_sock
        assert sorted(p.name for p in root.iterdir()) == ['fixture.txt']
    finally:
        process.terminate()
        process.wait(timeout=5)
        if agent_pid:
            import signal
            os.kill(agent_pid, signal.SIGTERM)
