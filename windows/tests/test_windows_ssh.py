import socket
import pytest
import paramiko  # Import before the Windows fixture wraps subprocess.Popen.
from PySide6.QtWidgets import QLineEdit

from opencommander import windows_ssh
from test_ui import app, window, wait


@pytest.mark.parametrize('error,expected', [
    (TimeoutError('private-transport-detail'), 'Zeitüberschreitung'),
    (ConnectionRefusedError('private-transport-detail'), 'Verbindung abgelehnt'),
    (socket.gaierror('private-transport-detail'), 'Servername nicht auflösbar'),
    (OSError('private-transport-detail'), 'Server nicht erreichbar'),
])
def test_identity_failure_identifies_phase_without_raw_transport_details(monkeypatch, error, expected):
    def fail(*args, **kwargs):
        raise error
    monkeypatch.setattr(windows_ssh.socket, 'create_connection', fail)
    with pytest.raises(RuntimeError) as caught:
        windows_ssh.scan('example.org', 2222)
    message = str(caught.value)
    assert 'example.org:2222' in message and expected in message
    assert 'Passwortanmeldung' in message and 'private-transport-detail' not in message


def test_host_key_preflight_failure_preserves_masked_password_without_saving(window, app, monkeypatch):
    from opencommander import online_ui, server_connections
    window.online_locations()
    dialog = window.online_dialog
    dialog.provider.setCurrentIndex(dialog.provider.findData('sftp'))
    dialog.server_form.host.setText('example.org')
    dialog.server_form.user.setText('fixture')
    dialog.server_form.secret.setText('fixture-only-password')
    dialog.server_form.remember.setChecked(True)
    stored = []
    monkeypatch.setattr(server_connections, 'keyring', lambda *args: stored.append(args))
    def failed(*args):
        raise RuntimeError('SSH-Vorprüfung fehlgeschlagen')
    monkeypatch.setattr(online_ui, 'ssh_fingerprints', failed)
    dialog.connect_server()
    wait(app, lambda: not dialog.pending)
    assert 'SSH-Vorprüfung' in dialog.status.text()
    assert dialog.server_form.secret.text() == 'fixture-only-password'
    assert dialog.server_form.secret.echoMode() == QLineEdit.EchoMode.Password
    assert not stored
    dialog.close()


def test_directory_refresh_uses_authenticated_loopback_and_only_managed_parent(tmp_path, monkeypatch):
    import base64
    import json
    import threading
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from opencommander import provider_mounts, windows_mounts, windows_native
    root = tmp_path / 'mount'; root.mkdir()
    received = []
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            assert self.path == '/vfs/forget'
            assert self.headers['Authorization'] == 'Basic ' + base64.b64encode(b'OpenCommander:fixture-only').decode()
            received.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
            self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
        def log_message(self, *_):
            pass
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    monkeypatch.setattr(provider_mounts, '_roots', {root})
    def credential(path, identifier, action):
        assert path == root and identifier == 'mount-control' and action == 'lookup'
        return json.dumps(dict(port=server.server_port, password='fixture-only'))
    monkeypatch.setattr(windows_native, 'keyring', credential)
    monkeypatch.setenv('http_proxy', 'http://127.0.0.1:1')
    monkeypatch.setenv('no_proxy', '')
    try:
        assert windows_mounts.settle(root / 'own/renamed')
        assert received == [dict(dir='own')]
        assert windows_mounts.settle(tmp_path / 'outside') is False
        assert len(received) == 1
    finally:
        server.shutdown(); server.server_close(); thread.join(timeout=2)


def test_failed_directory_refresh_keeps_data_without_inventing_undo_proof(tmp_path, monkeypatch):
    from opencommander import provider_mounts, windows_mounts
    from opencommander.operations import FileEngine, SafetyError
    root = tmp_path / 'mount'; root.mkdir()
    monkeypatch.setattr(provider_mounts, '_roots', {root})
    def failed(_):
        raise OSError('fixture control unavailable')
    monkeypatch.setattr(windows_mounts, 'settle', failed)
    engine = FileEngine(tmp_path / 'recovery')
    engine.mkdir(root, 'retained')
    assert (root / 'retained').is_dir()
    assert engine.history[-1]['records'][0]['snapshot'] is None
    with pytest.raises(SafetyError):
        FileEngine(engine.state_dir).undo()
    assert (root / 'retained').is_dir()
